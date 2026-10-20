"""Exercise shared bridge ownership, real sockets, and MCP stdio processes."""

from __future__ import annotations

import asyncio
import base64
import json
import os
import sys
from contextlib import AsyncExitStack, asynccontextmanager
from pathlib import Path

import pytest
import mcp.types as types
from websockets.asyncio.client import connect
from websockets.asyncio.server import serve

from aseprite_mcp import server, transport


async def until(predicate):
    async def poll():
        while not predicate():
            await asyncio.sleep(0.005)
    await asyncio.wait_for(poll(), 3)


@asynccontextmanager
async def running_bridge(idle_timeout=60):
    server.aseprite_ws = None
    server.pending.clear()
    bridge = transport.Bridge(idle_timeout)
    async with serve(bridge.handler, "127.0.0.1", 0) as listener:
        port = listener.sockets[0].getsockname()[1]
        try:
            yield bridge, port
        finally:
            for ws in list(bridge.clients):
                await ws.close()
            if server.aseprite_ws is not None:
                await server.aseprite_ws.close()
            if bridge.jobs:
                await asyncio.gather(*list(bridge.jobs), return_exceptions=True)
    server.pending.clear()


@asynccontextmanager
async def relay(port):
    client = transport.Relay(port)
    await client.ensure_connected()
    try:
        yield client
    finally:
        await client.close()


class StdioClient:
    def __init__(self, process):
        self.process = process
        self.request_id = 0

    async def request(self, method, params):
        self.request_id += 1
        self.process.stdin.write((json.dumps({
            "jsonrpc": "2.0", "id": self.request_id, "method": method, "params": params,
        }) + "\n").encode())
        await self.process.stdin.drain()
        reply = json.loads(await asyncio.wait_for(self.process.stdout.readline(), 5))
        assert reply["id"] == self.request_id
        assert "error" not in reply
        return reply["result"]

    async def list_tools(self):
        return types.ListToolsResult.model_validate(await self.request("tools/list", {}))

    async def call_tool(self, name, arguments):
        return types.CallToolResult.model_validate(await self.request(
            "tools/call", {"name": name, "arguments": arguments},
        ))


@asynccontextmanager
async def mcp_session(port):
    process = await asyncio.create_subprocess_exec(
        sys.executable, "-m", "aseprite_mcp",
        env={**os.environ, "ASEPRITE_MCP_PORT": str(port)},
        stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    try:
        client = StdioClient(process)
        await client.request("initialize", {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "bridge-test", "version": "1"},
        })
        process.stdin.write(b'{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
        await process.stdin.drain()
        yield client
    finally:
        process.stdin.close()
        try:
            await asyncio.wait_for(process.wait(), 3)
        except asyncio.TimeoutError:
            process.kill()
            await process.wait()


@pytest.mark.asyncio
async def test_two_stdio_processes_share_editor_and_first_can_exit():
    async with running_bridge() as (bridge, port):
        async with connect(f"ws://127.0.0.1:{port}") as plugin:
            await until(lambda: server.aseprite_ws is not None)

            async def respond():
                async for raw in plugin:
                    command = json.loads(raw)
                    await plugin.send(json.dumps({
                        "id": command["id"], "ok": True,
                        "result": command["params"].get("name", "still connected"),
                    }))

            responder = asyncio.create_task(respond())
            try:
                async with AsyncExitStack() as first_stack:
                    first = await first_stack.enter_async_context(mcp_session(port))
                    async with mcp_session(port) as second:
                        assert len((await first.list_tools()).tools) == 30
                        assert len((await second.list_tools()).tools) == 30
                        one, two = await asyncio.gather(
                            first.call_tool("add_layer", {"name": "one"}),
                            second.call_tool("add_layer", {"name": "two"}),
                        )
                        assert one.content[0].text == "one"
                        assert two.content[0].text == "two"
                        await first_stack.aclose()
                        result = await second.call_tool("list_layers", {})
                        assert result.content[0].text == "still connected"
                        assert not result.isError
            finally:
                await plugin.close()
                await responder


@pytest.mark.asyncio
async def test_serialization_and_disconnect_removes_queued_calls():
    async with running_bridge() as (bridge, port):
        async with connect(f"ws://127.0.0.1:{port}") as plugin:
            await until(lambda: server.aseprite_ws is not None)
            async with relay(port) as first, relay(port) as second:
                active = asyncio.create_task(first.call("add_layer", {"name": "active"}))
                command = json.loads(await plugin.recv())
                queued = asyncio.create_task(second.call("add_layer", {"name": "queued"}))
                await until(lambda: len(bridge.jobs) == 2)
                with pytest.raises(asyncio.TimeoutError):
                    await asyncio.wait_for(plugin.recv(), 0.03)
                await second.close()
                await until(lambda: len(bridge.jobs) == 1)
                await plugin.send(json.dumps({"id": command["id"], "ok": True, "result": "done"}))
                assert not (await active).isError
                assert (await queued).isError
                assert not server.pending


@pytest.mark.asyncio
async def test_images_finish_and_cleanup_after_requester_disconnect(tmp_path):
    async with running_bridge() as (bridge, port):
        async with connect(f"ws://127.0.0.1:{port}") as plugin:
            await until(lambda: server.aseprite_ws is not None)
            async with relay(port) as client:
                call = asyncio.create_task(client.call("get_canvas_image", {"path": str(tmp_path / "override.png")}))
                request = json.loads(await plugin.recv())
                path = Path(request["params"]["path"])
                assert path != tmp_path / "override.png"
                await client.close()
                assert (await call).isError
                path.write_bytes(b"png contents")
                await plugin.send(json.dumps({"id": request["id"], "ok": True, "result": "saved"}))
                await until(lambda: not bridge.jobs)
                assert not path.exists()


@pytest.mark.asyncio
@pytest.mark.parametrize("outcome", ["success", "error", "timeout", "disconnect"])
async def test_image_results_and_cleanup(outcome, monkeypatch):
    monkeypatch.setattr(server, "TOOL_TIMEOUT", 0.05)
    async with running_bridge() as (bridge, port):
        async with connect(f"ws://127.0.0.1:{port}") as plugin, relay(port) as client:
            await until(lambda: server.aseprite_ws is not None)
            call = asyncio.create_task(client.call("get_canvas_image", {}))
            request = json.loads(await plugin.recv())
            path = Path(request["params"]["path"])
            if outcome == "success":
                path.write_bytes(b"png" * 400_000)
                await plugin.send(json.dumps({"id": request["id"], "ok": True, "result": "saved"}))
            elif outcome == "error":
                await plugin.send(json.dumps({"id": request["id"], "ok": False, "error": "no active sprite"}))
            elif outcome == "disconnect":
                await plugin.close()
            result = await call
            assert result.isError == (outcome != "success")
            if outcome == "success":
                assert result.content[0].type == "image"
                assert base64.b64decode(result.content[0].data) == b"png" * 400_000
            assert not path.exists()


@pytest.mark.asyncio
async def test_plugin_reconnect_and_second_plugin_rejected():
    async with running_bridge() as (bridge, port), relay(port) as client:
        async with connect(f"ws://127.0.0.1:{port}") as plugin:
            await until(lambda: server.aseprite_ws is not None)
            original = server.aseprite_ws
            async with connect(f"ws://127.0.0.1:{port}") as other:
                await other.wait_closed()
                assert other.close_code == 1008
                assert server.aseprite_ws is original
            call = asyncio.create_task(client.call("list_layers", {}))
            await plugin.recv()
            await plugin.close()
            assert (await call).isError
        async with connect(f"ws://127.0.0.1:{port}") as replacement:
            await until(lambda: server.aseprite_ws is not None)
            call = asyncio.create_task(client.call("list_layers", {}))
            request = json.loads(await replacement.recv())
            await replacement.send(json.dumps({"id": request["id"], "ok": True, "result": "reconnected"}))
            assert (await call).content[0].text == "reconnected"


@pytest.mark.asyncio
async def test_bridge_disconnect_does_not_replay_inflight_call():
    async with running_bridge() as (bridge, port), relay(port) as client:
        async with connect(f"ws://127.0.0.1:{port}") as plugin:
            await until(lambda: server.aseprite_ws is not None)
            call = asyncio.create_task(client.call("add_layer", {"name": "once"}))
            request = json.loads(await plugin.recv())
            await next(iter(bridge.clients)).close()
            assert "outcome unknown" in (await call).content[0].text
            await until(lambda: client.ws is None)
            await plugin.send(json.dumps({"id": request["id"], "ok": True, "result": "done"}))
            await until(lambda: not bridge.jobs)
            later = asyncio.create_task(client.call("list_layers", {}))
            request = json.loads(await plugin.recv())
            assert request["tool"] == "list_layers"
            await plugin.send(json.dumps({"id": request["id"], "ok": True, "result": "later"}))
            assert not (await later).isError


@pytest.mark.asyncio
async def test_idle_shutdown_ignores_plugin_but_keeps_clients():
    async with running_bridge(0.04) as (bridge, port):
        async with connect(f"ws://127.0.0.1:{port}") as plugin:
            async with relay(port):
                idle = asyncio.create_task(bridge.wait_idle())
                await asyncio.sleep(0.08)
                assert not idle.done()
            await asyncio.wait_for(idle, 0.3)


@pytest.mark.asyncio
@pytest.mark.parametrize("hello", [{"type": "foreign"}, {**transport.HELLO, "protocol": 999}, None])
async def test_incompatible_service_is_not_replaced(hello, monkeypatch):
    async def foreign(ws):
        if hello is None:
            await ws.close(1008, "Only one Aseprite connection allowed")
        else:
            await ws.send(json.dumps(hello))
            await ws.wait_closed()

    def forbidden_launch(port):
        pytest.fail("Must not launch over an occupied port")

    monkeypatch.setattr(transport, "launch_bridge", forbidden_launch)
    async with serve(foreign, "127.0.0.1", 0) as listener:
        with pytest.raises(RuntimeError, match="incompatible"):
            await transport.connect_bridge(listener.sockets[0].getsockname()[1])


@pytest.mark.asyncio
async def test_automatic_start_race_and_recreation(monkeypatch):
    # Reserve a free custom port, then let two frontends race to start it.
    async with serve(lambda ws: ws.wait_closed(), "127.0.0.1", 0) as reservation:
        port = reservation.sockets[0].getsockname()[1]
    launch = transport.launch_bridge
    children = []

    def tracked_launch(port):
        child = launch(port)
        children.append(child)
        return child

    monkeypatch.setattr(transport, "launch_bridge", tracked_launch)
    first, second = transport.Relay(port), transport.Relay(port)
    try:
        await asyncio.gather(first.ensure_connected(), second.ensure_connected())
        assert len(children) == 2
        assert (await first.call("list_layers", {})).isError  # No editor, but bridge is alive.
        await first.close()
        assert "Aseprite not connected" in (await second.call("list_layers", {})).content[0].text
        for child in children:
            if child.poll() is None:
                child.terminate()
        for child in children:
            await asyncio.to_thread(child.wait, 3)
        await until(lambda: second.ws is None)
        assert "Aseprite not connected" in (await second.call("list_layers", {})).content[0].text
        assert len(children) == 3
    finally:
        await first.close()
        await second.close()
        for child in children:
            if child.poll() is None:
                child.terminate()
            await asyncio.to_thread(child.wait, 3)


@pytest.mark.asyncio
async def test_queued_call_timeout_starts_at_dispatch(monkeypatch):
    monkeypatch.setattr(server, "TOOL_TIMEOUT", 0.08)
    async with running_bridge() as (bridge, port), relay(port) as client:
        async with connect(f"ws://127.0.0.1:{port}") as plugin:
            await until(lambda: server.aseprite_ws is not None)
            first = asyncio.create_task(client.call("list_layers", {}))
            await plugin.recv()  # This call receives no reply and times out.
            second = asyncio.create_task(client.call("list_frames", {}))
            await until(lambda: len(bridge.jobs) == 2)
            assert "Timeout" in (await first).content[0].text
            request = json.loads(await plugin.recv())
            assert request["tool"] == "list_frames"
            await plugin.send(json.dumps({"id": request["id"], "ok": True, "result": "second"}))
            assert (await second).content[0].text == "second"


@pytest.mark.asyncio
async def test_idle_bridge_main_closes_plugin(monkeypatch):
    bridge = transport.Bridge(0.1)
    monkeypatch.setattr(transport, "Bridge", lambda: bridge)
    async with serve(lambda ws: ws.wait_closed(), "127.0.0.1", 0) as reservation:
        port = reservation.sockets[0].getsockname()[1]
    main = asyncio.create_task(transport.bridge_main(port))
    plugin = None
    try:
        for _ in range(20):
            try:
                plugin = await connect(f"ws://127.0.0.1:{port}")
                break
            except ConnectionRefusedError:
                await asyncio.sleep(0.005)
        assert plugin is not None
        await asyncio.wait_for(main, 0.5)
        await asyncio.wait_for(plugin.wait_closed(), 0.5)
    finally:
        if plugin is not None:
            await plugin.close()
        if not main.done():
            main.cancel()
        await asyncio.gather(main, return_exceptions=True)


@pytest.mark.asyncio
async def test_invalid_frontend_request_rejected_without_editor_work():
    async with running_bridge() as (bridge, port):
        async with connect(f"ws://127.0.0.1:{port}/clients") as ws:
            assert json.loads(await ws.recv()) == transport.HELLO
            await ws.send(json.dumps({"id": "bad", "tool": "undo", "params": []}))
            await ws.wait_closed()
            assert ws.close_code == 1008
            assert not bridge.jobs
