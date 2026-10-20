"""Shared loopback bridge and per-session MCP stdio frontends."""

from __future__ import annotations

import asyncio
import errno
import inspect
import json
import os
import subprocess
import sys
import tempfile
import uuid
from typing import Any

import mcp.server.stdio
import mcp.types as types
import websockets.exceptions
from mcp.server import Server
from websockets.asyncio.client import ClientConnection, connect
from websockets.asyncio.server import ServerConnection, serve
from websockets.protocol import State

from . import server

BRIDGE_PROTOCOL = 1
STARTUP_TIMEOUT = 5.0
IDLE_TIMEOUT = 60.0
HELLO = {"type": "aseprite-mcp-bridge", "protocol": BRIDGE_PROTOCOL}


class Bridge:
    """Own one editor connection and serialize calls from all frontends."""

    def __init__(self, idle_timeout: float = IDLE_TIMEOUT) -> None:
        self.lock = asyncio.Lock()
        self.clients: set[ServerConnection] = set()
        self.jobs: dict[asyncio.Task[None], bool] = {}
        self.idle_timeout = idle_timeout
        self.last_client = asyncio.get_running_loop().time()

    async def handler(self, ws: ServerConnection) -> None:
        assert ws.request is not None
        if ws.request.path == "/":
            await server.ws_handler(ws)
            return
        if ws.request.path != "/clients":
            await ws.close(1008, "Unknown bridge endpoint")
            return
        self.clients.add(ws)
        owned: set[asyncio.Task[None]] = set()
        try:
            await ws.send(json.dumps(HELLO))
            async for raw in ws:
                try:
                    request = json.loads(raw)
                    if (
                        not isinstance(request, dict)
                        or not isinstance(request.get("id"), str)
                        or not isinstance(request.get("tool"), str)
                        or not isinstance(request.get("params"), dict)
                    ):
                        raise ValueError("Invalid bridge request")
                except (ValueError, TypeError):
                    await ws.close(1008, "Invalid bridge request")
                    break
                task = asyncio.create_task(self.execute(ws, request))
                self.jobs[task] = False
                owned.add(task)
                task.add_done_callback(owned.discard)
                task.add_done_callback(self.finished)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            self.clients.discard(ws)
            self.last_client = asyncio.get_running_loop().time()
            # A dispatched editor mutation cannot be undone by cancelling its
            # caller. Finish it, including image cleanup, before the next call.
            for task in owned:
                if not self.jobs.get(task, False):
                    task.cancel()

    def finished(self, task: asyncio.Task[None]) -> None:
        self.jobs.pop(task, None)
        if not task.cancelled() and task.exception() is not None:
            server.log.error("Bridge request failed", exc_info=task.exception())

    async def execute(self, ws: ServerConnection, request: dict[str, Any]) -> None:
        async with self.lock:
            if ws.state is not State.OPEN:
                return
            task = asyncio.current_task()
            assert task is not None
            self.jobs[task] = True
            try:
                result = await server.call_tool(request["tool"], request["params"])
            except Exception:
                server.log.exception("Unexpected tool failure")
                result = server._error("Error: Internal bridge failure; see bridge log")
            try:
                await ws.send(json.dumps({
                    "id": request["id"], "result": result.model_dump(mode="json"),
                }))
            except websockets.exceptions.ConnectionClosed:
                pass

    async def wait_idle(self) -> None:
        loop = asyncio.get_running_loop()
        while True:
            await asyncio.sleep(min(self.idle_timeout, 1.0))
            if (
                not self.clients and not self.jobs
                and loop.time() - self.last_client >= self.idle_timeout
            ):
                return


async def bridge_main(port: int) -> None:
    bridge = Bridge()
    server.log.info("Starting WebSocket server on ws://127.0.0.1:%d", port)
    try:
        async with serve(bridge.handler, "127.0.0.1", port, max_size=None):
            await bridge.wait_idle()
    except OSError as exc:
        # Concurrent frontends can both launch a child. Binding elects one;
        # the other frontend discovers the winner through its handshake.
        if exc.errno not in (errno.EADDRINUSE, 10048):
            raise


def launch_bridge(port: int) -> subprocess.Popen[bytes]:
    fd, log_path = tempfile.mkstemp(prefix=f"aseprite-mcp-{port}-", suffix=".log")
    options: dict[str, Any] = {}
    if os.name == "nt":
        options["creationflags"] = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        options["start_new_session"] = True
    with os.fdopen(fd, "wb") as log:
        child = subprocess.Popen(
            [sys.executable, "-m", "aseprite_mcp", "--bridge", str(port)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=log,
            close_fds=True, **options,
        )
    server.log.info("Shared bridge log: %s", log_path)
    return child


async def connect_bridge(port: int) -> ClientConnection:
    loop = asyncio.get_running_loop()
    deadline = loop.time() + STARTUP_TIMEOUT
    child: subprocess.Popen[bytes] | None = None
    while loop.time() < deadline:
        if child is not None:
            child.poll()
        try:
            # websockets 15 added proxy discovery. Earlier supported versions
            # have no proxy option; local IPC must never use an HTTP proxy.
            options = {"proxy": None} if "proxy" in inspect.signature(connect).parameters else {}
            ws = await connect(
                f"ws://127.0.0.1:{port}/clients", open_timeout=0.5,
                close_timeout=0.2, max_size=None, **options,
            )
        except OSError as exc:
            if exc.errno not in (errno.ECONNREFUSED, 10061):
                raise RuntimeError(f"Cannot connect to shared bridge on port {port}: {exc}") from exc
            if child is None:
                child = launch_bridge(port)
            await asyncio.sleep(0.05)
            continue
        except (asyncio.TimeoutError, websockets.exceptions.WebSocketException) as exc:
            raise RuntimeError(f"Port {port} is occupied by an incompatible service; stop it or change ASEPRITE_MCP_PORT") from exc
        try:
            hello = json.loads(await asyncio.wait_for(ws.recv(), timeout=0.5))
            if hello != HELLO:
                raise ValueError("Incompatible bridge handshake")
        except (ValueError, asyncio.TimeoutError, websockets.exceptions.ConnectionClosed) as exc:
            await ws.close()
            raise RuntimeError(f"Port {port} is occupied by an incompatible bridge; stop old servers before upgrading") from exc
        return ws
    raise RuntimeError(f"Shared bridge on port {port} did not start within 5s; see bridge log")


class Relay:
    def __init__(self, port: int) -> None:
        self.port = port
        self.ws: ClientConnection | None = None
        self.reader: asyncio.Task[None] | None = None
        self.connect_lock = asyncio.Lock()
        self.pending: dict[str, asyncio.Future[types.CallToolResult]] = {}

    async def ensure_connected(self) -> None:
        async with self.connect_lock:
            if self.ws is None:
                self.ws = await connect_bridge(self.port)
                self.reader = asyncio.create_task(self.receive(self.ws))

    async def receive(self, ws: ClientConnection) -> None:
        try:
            async for raw in ws:
                response = json.loads(raw)
                future = self.pending.get(response["id"])
                if future is not None and not future.done():
                    future.set_result(types.CallToolResult.model_validate(response["result"]))
        except (websockets.exceptions.ConnectionClosed, ValueError, KeyError, TypeError):
            server.log.warning("Shared bridge connection lost")
        finally:
            self.ws = None
            for future in self.pending.values():
                if not future.done():
                    future.set_result(server._error("Shared bridge disconnected before responding; command outcome unknown"))
            await ws.close()

    async def call(self, name: str, arguments: dict[str, Any]) -> types.CallToolResult:
        try:
            await self.ensure_connected()
        except RuntimeError as exc:
            return server._error(str(exc))
        request_id = str(uuid.uuid4())
        future: asyncio.Future[types.CallToolResult] = asyncio.get_running_loop().create_future()
        self.pending[request_id] = future
        try:
            assert self.ws is not None
            await self.ws.send(json.dumps({"id": request_id, "tool": name, "params": arguments}))
            return await future
        except websockets.exceptions.ConnectionClosed:
            return server._error("Shared bridge disconnected before responding; command outcome unknown")
        finally:
            self.pending.pop(request_id, None)

    async def close(self) -> None:
        if self.ws is not None:
            await self.ws.close()
        if self.reader is not None:
            await self.reader


async def frontend_main(port: int) -> None:
    relay = Relay(port)
    try:
        await relay.ensure_connected()
        frontend = Server("aseprite-mcp")
        frontend.list_tools()(server.list_tools)
        frontend.call_tool()(relay.call)
        async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
            await frontend.run(read_stream, write_stream, frontend.create_initialization_options())
    finally:
        await relay.close()
