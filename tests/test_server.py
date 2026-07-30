"""
pytest-asyncio tests for aseprite_mcp.server

Run with:
    pip install -e ".[dev]"
    pytest -v
"""

from __future__ import annotations

import asyncio
import base64
import json
import re
import uuid
from pathlib import Path
from unittest.mock import MagicMock

import mcp.types as types
import pytest
import websockets.exceptions

from aseprite_mcp import server as srv

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _text(result: types.CallToolResult) -> str:
    """The human-readable text of a tool result, joined across content blocks."""
    return "".join(
        block.text for block in result.content if isinstance(block, types.TextContent)
    )


def _make_ws(responses: list[dict] | None = None, raise_on_send: Exception | None = None):
    """
    Return a minimal mock that looks enough like a websockets connection for
    our tests.  `responses` is the list of dicts the mock will push into
    pending futures when `send` is called.
    """
    ws = MagicMock()
    ws.remote_address = ("127.0.0.1", 9999)

    sent_messages: list[str] = []

    async def fake_send(msg: str):
        if raise_on_send:
            raise raise_on_send
        sent_messages.append(msg)

    ws.send = fake_send
    ws._sent = sent_messages
    return ws


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def reset_server_state():
    """Reset module-level state before every test."""
    srv.aseprite_ws = None
    srv.pending.clear()
    yield
    srv.aseprite_ws = None
    srv.pending.clear()


# ---------------------------------------------------------------------------
# Test 1: successful tool call when Aseprite is connected
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_tool_call_connected_success():
    """_dispatch sends JSON to Aseprite, resolves future, returns result."""
    ws = _make_ws()
    srv.aseprite_ws = ws

    # Simulate Aseprite responding correctly after the command is sent.
    async def fake_send(msg: str):
        data = json.loads(msg)
        cmd_id = data["id"]
        # Give the event loop a tick so the future is registered first.
        await asyncio.sleep(0)
        fut = srv.pending.get(cmd_id)
        if fut and not fut.done():
            fut.set_result({"id": cmd_id, "ok": True, "result": {"layer": "Layer 1"}})

    ws.send = fake_send

    result = await srv._dispatch("add_layer", {"name": "Background"})
    assert result.isError is False
    assert _text(result) == json.dumps({"layer": "Layer 1"})


# ---------------------------------------------------------------------------
# Test 2: tool call with no Aseprite connected
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_tool_call_no_connection():
    """_dispatch reports a clear MCP error when aseprite_ws is None."""
    assert srv.aseprite_ws is None
    result = await srv._dispatch("draw_pixel", {"x": 0, "y": 0, "color": "#FF0000"})
    assert result.isError is True
    text = _text(result)
    assert "Aseprite not connected" in text
    assert "plugin" in text.lower()


# ---------------------------------------------------------------------------
# Test 3: response with unmatched UUID is silently dropped
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_unmatched_uuid_dropped():
    """
    When ws_handler receives a response whose id is not in pending,
    it must not raise and the pending dict stays intact.
    """
    # Build a fake websocket whose async-for yields one unknown-id message
    # then raises ConnectionClosed to end the loop.
    import websockets.exceptions

    class FakeWS:
        remote_address = ("127.0.0.1", 9999)

        def __aiter__(self):
            return self

        _msgs = [json.dumps({"id": str(uuid.uuid4()), "ok": True, "result": {}})]
        _idx = 0

        async def __anext__(self):
            if self._idx < len(self._msgs):
                msg = self._msgs[self._idx]
                self._idx += 1
                return msg
            raise websockets.exceptions.ConnectionClosedOK(None, None)

        async def close(self, *a, **kw):
            pass

    fake_ws = FakeWS()

    # Put a known future in pending so we can verify it was NOT touched.
    sentinel_id = str(uuid.uuid4())
    sentinel_fut: asyncio.Future = asyncio.get_running_loop().create_future()
    srv.pending[sentinel_id] = sentinel_fut

    # Run the handler; it should finish without error.
    await srv.ws_handler(fake_ws)  # type: ignore[arg-type]

    # The sentinel future was cancelled by cleanup (aseprite_ws became None).
    assert sentinel_fut.cancelled()
    # The unknown id never created a new entry.
    assert sentinel_id not in srv.pending or srv.pending.get(sentinel_id) is sentinel_fut


# ---------------------------------------------------------------------------
# Test 4: 10-second timeout returns error to caller
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_timeout_returns_error():
    """
    If Aseprite never responds, _dispatch must return a timeout error string
    within (mocked) TOOL_TIMEOUT seconds.
    """
    ws = _make_ws()

    async def fake_send_noop(msg: str):
        # Intentionally do nothing — never resolve the future.
        pass

    ws.send = fake_send_noop
    srv.aseprite_ws = ws

    # Patch the timeout to 0.05 s so the test runs fast.
    original_timeout = srv.TOOL_TIMEOUT
    srv.TOOL_TIMEOUT = 0.05
    try:
        result = await srv._dispatch("export_png", {"path": "/tmp/out.png"})
    finally:
        srv.TOOL_TIMEOUT = original_timeout

    assert result.isError is True
    text = _text(result)
    assert "Timeout" in text or "timeout" in text.lower()
    assert "Aseprite" in text


# ---------------------------------------------------------------------------
# Test 5: error response from Aseprite is surfaced cleanly
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_tool_call_aseprite_error():
    """When Aseprite replies with ok=false, the error message is returned."""
    ws = _make_ws()
    srv.aseprite_ws = ws

    async def fake_send(msg: str):
        data = json.loads(msg)
        cmd_id = data["id"]
        await asyncio.sleep(0)
        fut = srv.pending.get(cmd_id)
        if fut and not fut.done():
            fut.set_result({"id": cmd_id, "ok": False, "error": "no active sprite"})

    ws.send = fake_send

    result = await srv._dispatch("draw_pixel", {"x": 5, "y": 5, "color": "#0000FF"})
    assert result.isError is True
    text = _text(result)
    assert "no active sprite" in text
    assert text.startswith("Error:")


# ---------------------------------------------------------------------------
# Test 5b: a disconnect mid-send is an error, not success-shaped text
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_disconnect_during_send_returns_error():
    """
    The fourth failure path: the socket closes while the command is being sent.
    The caller gets an MCP error and the stale handle is dropped.
    """
    ws = _make_ws(raise_on_send=websockets.exceptions.ConnectionClosedError(None, None))
    srv.aseprite_ws = ws

    result = await srv._dispatch("add_layer", {"name": "Doomed"})

    assert result.isError is True
    assert "disconnected" in _text(result).lower()
    # A closed socket must not be left in place for the next call to reuse.
    assert srv.aseprite_ws is None


# ---------------------------------------------------------------------------
# Test 5c: a structured result keeps its shape; a string result keeps its prose
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_structured_result_arrives_as_json_text():
    """
    The read tools return a table, which the plugin sends as a JSON structure.
    The caller has to receive its fields, not a stringified Lua table.
    """
    ws = _make_ws()
    srv.aseprite_ws = ws

    fields = {
        "width": 32,
        "height": 32,
        "colorMode": "rgb",
        "frames": 1,
        "layers": 3,
        "activeLayer": "Layer 1",
    }

    async def fake_send(msg: str):
        cmd_id = json.loads(msg)["id"]
        await asyncio.sleep(0)
        fut = srv.pending.get(cmd_id)
        if fut and not fut.done():
            fut.set_result({"id": cmd_id, "ok": True, "result": fields})

    ws.send = fake_send

    result = await srv._dispatch("get_sprite_info", {})
    assert result.isError is False
    assert json.loads(_text(result)) == fields


@pytest.mark.asyncio
async def test_string_result_is_passed_through_unchanged():
    """The write tools still return one line of prose, not JSON."""
    ws = _make_ws()
    srv.aseprite_ws = ws

    async def fake_send(msg: str):
        cmd_id = json.loads(msg)["id"]
        await asyncio.sleep(0)
        fut = srv.pending.get(cmd_id)
        if fut and not fut.done():
            fut.set_result({"id": cmd_id, "ok": True, "result": "drew 561 pixels"})

    ws.send = fake_send

    result = await srv._dispatch("draw_pixels_batch", {"pixels": "0,0,FF0000"})
    assert _text(result) == "drew 561 pixels"


# ---------------------------------------------------------------------------
# Test 5d: get_canvas_image — image content out, no temp file left behind
# ---------------------------------------------------------------------------

PNG_BYTES = b"\x89PNG\r\n\x1a\nnot-a-real-png-but-the-server-never-parses-it"


def _canvas_ws(reply, *, write_file: bool = True):
    """
    A mock Aseprite that behaves like the plugin's get_canvas_image: it writes
    the file at the path the server chose, then replies. `reply` maps that path
    to the response dict, or is None to never respond at all.

    Records every path the server sent, so a test can assert on cleanup.
    """
    ws = _make_ws()
    ws._paths = []

    async def fake_send(msg: str):
        data = json.loads(msg)
        path = data["params"]["path"]
        ws._paths.append(path)

        if write_file:
            Path(path).write_bytes(PNG_BYTES)
        if reply is None:
            return

        await asyncio.sleep(0)
        fut = srv.pending.get(data["id"])
        if fut and not fut.done():
            fut.set_result({"id": data["id"], **reply(path)})

    ws.send = fake_send
    return ws


@pytest.mark.asyncio
async def test_canvas_image_returns_image_content():
    """The canvas comes back as base64 PNG image content, not a description."""
    ws = _canvas_ws(lambda path: {
        "ok": True,
        "result": {"path": path, "width": 32, "height": 32},
    })
    srv.aseprite_ws = ws

    result = await srv.call_tool("get_canvas_image", {"scale": 2})

    assert result.isError is False
    assert len(result.content) == 1
    block = result.content[0]
    assert isinstance(block, types.ImageContent)
    assert block.mimeType == "image/png"
    assert base64.b64decode(block.data) == PNG_BYTES


@pytest.mark.asyncio
async def test_canvas_image_path_is_server_owned():
    """
    The destination is generated here and overrides anything the caller passed,
    so a tool argument cannot aim the write.
    """
    ws = _canvas_ws(lambda path: {
        "ok": True,
        "result": {"path": path, "width": 8, "height": 8},
    })
    srv.aseprite_ws = ws

    attacker = Path(__file__).parent / "should-never-be-written.png"
    await srv.call_tool("get_canvas_image", {"path": str(attacker)})

    assert ws._paths and ws._paths[0] != str(attacker)
    assert not attacker.exists()


@pytest.mark.asyncio
async def test_canvas_image_unlinks_temp_file_on_success():
    ws = _canvas_ws(lambda path: {
        "ok": True,
        "result": {"path": path, "width": 8, "height": 8},
    })
    srv.aseprite_ws = ws

    await srv.call_tool("get_canvas_image", {})

    assert ws._paths
    assert not Path(ws._paths[0]).exists()


@pytest.mark.asyncio
async def test_canvas_image_unlinks_temp_file_on_plugin_error():
    """A failed write still leaves nothing behind — the file may exist by then."""
    ws = _canvas_ws(lambda path: {"ok": False, "error": "no active sprite"})
    srv.aseprite_ws = ws

    result = await srv.call_tool("get_canvas_image", {})

    assert result.isError is True
    assert "no active sprite" in _text(result)
    assert ws._paths
    assert not Path(ws._paths[0]).exists()


@pytest.mark.asyncio
async def test_canvas_image_unlinks_temp_file_on_timeout():
    """mkstemp created the file, so a timeout must still clean it up."""
    ws = _canvas_ws(None, write_file=False)
    srv.aseprite_ws = ws

    original_timeout = srv.TOOL_TIMEOUT
    srv.TOOL_TIMEOUT = 0.05
    try:
        result = await srv.call_tool("get_canvas_image", {})
    finally:
        srv.TOOL_TIMEOUT = original_timeout

    assert result.isError is True
    assert "Timeout" in _text(result)
    assert ws._paths
    assert not Path(ws._paths[0]).exists()


# ---------------------------------------------------------------------------
# Test 6: the registered tool set matches the documented registry
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_tools_matches_registry():
    """list_tools() must expose exactly the documented tool set."""
    tools = await srv.list_tools()
    names = {t.name for t in tools}
    expected = {
        "create_sprite",
        "draw_pixel",
        "fill_area",
        "add_layer",
        "export_png",
        "draw_pixels_batch",
        "get_sprite_info",
        "get_canvas_image",
        "get_pixel",
        "get_region",
        "list_layers",
        "get_selection",
        "draw_line",
        "draw_rect",
        "draw_ellipse",
        "erase_area",
        "undo",
        "redo",
        "get_undo_depth",
        "add_frame",
        "delete_frame",
        "set_frame_duration",
        "set_active_frame",
        "list_frames",
        "open_file",
        "save_sprite",
        "list_sprites",
        "set_active_sprite",
        "close_sprite",
        "export_spritesheet",
    }
    assert names == expected, (
        f"Missing tools: {expected - names}; unexpected tools: {names - expected}"
    )


# ---------------------------------------------------------------------------
# Test 6b: ASEPRITE_MCP_PORT resolution
# ---------------------------------------------------------------------------


def test_port_defaults_when_unset():
    """With nothing configured, both ends meet on 9876."""
    assert srv.resolve_port({}) == srv.DEFAULT_PORT == 9876


@pytest.mark.parametrize("raw, expected", [("9877", 9877), ("  1024  ", 1024), ("1", 1), ("65535", 65535)])
def test_port_override_accepted(raw: str, expected: int):
    assert srv.resolve_port({srv.PORT_ENV_VAR: raw}) == expected


@pytest.mark.parametrize("raw", ["", "   "])
def test_blank_port_is_treated_as_unset(raw: str):
    """An exported-but-empty variable is a configuration no-op, not an error."""
    assert srv.resolve_port({srv.PORT_ENV_VAR: raw}) == srv.DEFAULT_PORT


@pytest.mark.parametrize("raw", ["nine", "98.7", "0", "-1", "65536", "9876abc"])
def test_invalid_port_rejected(raw: str):
    """
    Nothing negotiates the port, so a bad value must fail loudly at startup
    rather than leaving the bridge silently unformed. The message has to name
    the variable, since that is the only clue the user gets.
    """
    with pytest.raises(ValueError) as excinfo:
        srv.resolve_port({srv.PORT_ENV_VAR: raw})

    assert srv.PORT_ENV_VAR in str(excinfo.value)


# ---------------------------------------------------------------------------
# Test 7: every server tool has a handler in the Lua plugin
# ---------------------------------------------------------------------------

PLUGIN_MAIN = Path(__file__).parent.parent / "plugin" / "main.lua"


def _plugin_handler_names() -> set[str]:
    """Names assigned into the `handlers` table in plugin/main.lua."""
    source = PLUGIN_MAIN.read_text(encoding="utf-8")
    return set(re.findall(r"^handlers\.(\w+)\s*=", source, flags=re.MULTILINE))


@pytest.mark.asyncio
async def test_every_tool_has_a_plugin_handler():
    """
    A tool registered on the server with no Lua handler fails at runtime with
    'unknown tool'. Catch that drift here instead of in Aseprite.
    """
    tools = await srv.list_tools()
    tool_names = {t.name for t in tools}
    handler_names = _plugin_handler_names()

    assert handler_names, f"No handlers parsed from {PLUGIN_MAIN}"

    missing = tool_names - handler_names
    assert not missing, (
        f"Tools registered on the server with no handler in {PLUGIN_MAIN.name}: "
        f"{sorted(missing)}"
    )
