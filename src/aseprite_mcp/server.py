"""
aseprite_mcp.server
===================
Single asyncio process that runs:
  - A WebSocket server on ws://127.0.0.1:<port> (for the Aseprite Lua plugin),
    where <port> comes from ASEPRITE_MCP_PORT and defaults to 9876
  - An MCP stdio server (for Claude / Claude Code)

Both share the same event loop so tool calls can reach Aseprite over the
WebSocket and await the response before returning to the MCP caller.
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import json
import logging
import os
import tempfile
import uuid
from collections.abc import Mapping
from typing import Any

import mcp.server.stdio
import mcp.types as types
import websockets
from mcp.server import Server
from websockets.asyncio.server import ServerConnection, serve

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

# The single active Aseprite WebSocket connection (or None).
aseprite_ws: ServerConnection | None = None

# Futures keyed by command UUID; resolved when Aseprite sends a matching reply.
pending: dict[str, asyncio.Future[dict[str, Any]]] = {}

TOOL_TIMEOUT = 10  # seconds

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PORT_ENV_VAR = "ASEPRITE_MCP_PORT"
DEFAULT_PORT = 9876


def resolve_port(env: Mapping[str, str] | None = None) -> int:
    """
    The port both ends of the bridge must agree on.

    Nothing negotiates it, so a bad value is rejected here rather than left to
    present as "Aseprite not connected" once the bridge silently fails to form.
    """
    raw = (os.environ if env is None else env).get(PORT_ENV_VAR)
    if raw is None or not raw.strip():
        return DEFAULT_PORT

    complaint = f"{PORT_ENV_VAR} must be an integer between 1 and 65535, got {raw!r}"
    try:
        port = int(raw.strip())
    except ValueError:
        raise ValueError(complaint) from None

    if not 1 <= port <= 65535:
        raise ValueError(complaint)

    return port

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("aseprite-mcp")

# ---------------------------------------------------------------------------
# MCP server definition
# ---------------------------------------------------------------------------

mcp_server = Server("aseprite-mcp")


# ----- tool registration ---------------------------------------------------

@mcp_server.list_tools()
async def list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="create_sprite",
            description="Create a new sprite in Aseprite.",
            inputSchema={
                "type": "object",
                "properties": {
                    "width":  {"type": "integer", "description": "Sprite width in pixels"},
                    "height": {"type": "integer", "description": "Sprite height in pixels"},
                    "mode":   {"type": "string",  "description": "Color mode: RGB, Grayscale, or Indexed", "default": "RGB"},
                },
                "required": ["width", "height"],
            },
        ),
        types.Tool(
            name="draw_pixel",
            description="Set the color of a single pixel in the active sprite.",
            inputSchema={
                "type": "object",
                "properties": {
                    "x":     {"type": "integer", "description": "X coordinate (0-based)"},
                    "y":     {"type": "integer", "description": "Y coordinate (0-based)"},
                    "color": {"type": "string",  "description": "Hex color string, e.g. #FF0000"},
                },
                "required": ["x", "y", "color"],
            },
        ),
        types.Tool(
            name="fill_area",
            description="Flood-fill an area in the active sprite starting from (x, y).",
            inputSchema={
                "type": "object",
                "properties": {
                    "x":     {"type": "integer", "description": "X coordinate of the seed pixel"},
                    "y":     {"type": "integer", "description": "Y coordinate of the seed pixel"},
                    "color": {"type": "string",  "description": "Hex color string, e.g. #00FF00"},
                },
                "required": ["x", "y", "color"],
            },
        ),
        types.Tool(
            name="add_layer",
            description="Add a new layer to the active sprite.",
            inputSchema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Name for the new layer"},
                },
                "required": ["name"],
            },
        ),
        types.Tool(
            name="export_png",
            description=(
                "Export ONE frame of the active sprite, composited from its visible "
                "layers, to a PNG file. Writes exactly one file at the path given, "
                "whatever the sprite's frame count. The frame defaults to the active "
                "one; pass frame to export another without moving the active frame "
                "first. Frame numbers are 1-based — list_frames reports the valid "
                "range. To get every frame in one image instead, use "
                "export_spritesheet."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "path":  {"type": "string", "description": "Absolute file path for the exported PNG"},
                    "frame": {
                        "type": "integer",
                        "description": "1-based frame to export. Defaults to the active frame.",
                        "minimum": 1,
                    },
                },
                "required": ["path"],
            },
        ),
        types.Tool(
            name="draw_pixels_batch",
            description=(
                "Draw many pixels in one call — use this instead of repeated draw_pixel calls. "
                "Encode pixels as a semicolon-separated string: 'x,y,RRGGBB;x,y,RRGGBB;...'. "
                "Example: '0,0,FF0000;1,0,FF0000;2,0,00FF00'. No # prefix on colors."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "pixels": {
                        "type": "string",
                        "description": "Pixels as 'x,y,RRGGBB;...' — no spaces, no # prefix. E.g. '4,5,E8782A;5,5,E8782A'",
                    },
                },
                "required": ["pixels"],
            },
        ),
        types.Tool(
            name="draw_line",
            description=(
                "Draw a 1px line on the active layer — one call instead of a "
                "draw_pixels_batch triple per pixel. The coordinates are the two "
                "ENDPOINTS, both inclusive; identical endpoints draw a single pixel. "
                "Uses Aseprite's own line tool, so the stepping matches drawing "
                "interactively. A line running past the canvas edge is clipped."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "x1":    {"type": "integer", "description": "X of the first endpoint (0-based)"},
                    "y1":    {"type": "integer", "description": "Y of the first endpoint (0-based)"},
                    "x2":    {"type": "integer", "description": "X of the second endpoint, inclusive"},
                    "y2":    {"type": "integer", "description": "Y of the second endpoint, inclusive"},
                    "color": {"type": "string",  "description": "Hex color string, e.g. #FF0000"},
                },
                "required": ["x1", "y1", "x2", "y2", "color"],
            },
        ),
        types.Tool(
            name="draw_rect",
            description=(
                "Draw a rectangle on the active layer, outlined or filled. The "
                "coordinates are a BOUNDING BOX, not two corners: x,y is the top-left "
                "pixel and width/height are sizes, so x=2, y=2, width=8, height=6 "
                "covers columns 2-9 and rows 2-7. Set fill true for a solid rectangle, "
                "false or omitted for a 1px outline. Width and height must be at least "
                "1. Parts of the rectangle past the canvas edge are clipped."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "x":      {"type": "integer", "description": "Left edge of the bounding box (0-based)"},
                    "y":      {"type": "integer", "description": "Top edge of the bounding box (0-based)"},
                    "width":  {"type": "integer", "description": "Box width in pixels, at least 1"},
                    "height": {"type": "integer", "description": "Box height in pixels, at least 1"},
                    "color":  {"type": "string",  "description": "Hex color string, e.g. #FF0000"},
                    "fill":   {
                        "type": "boolean",
                        "description": "True for a solid rectangle, false for a 1px outline. Default false.",
                        "default": False,
                    },
                },
                "required": ["x", "y", "width", "height", "color"],
            },
        ),
        types.Tool(
            name="draw_ellipse",
            description=(
                "Draw an ellipse inscribed in a BOUNDING BOX on the active layer, "
                "outlined or filled. Takes the same coordinates as draw_rect — x,y "
                "top-left plus width/height, not two corners — so an equal width and "
                "height gives a circle. Set fill true for a solid ellipse, false or "
                "omitted for a 1px outline. Width and height must be at least 1. "
                "Parts past the canvas edge are clipped."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "x":      {"type": "integer", "description": "Left edge of the bounding box (0-based)"},
                    "y":      {"type": "integer", "description": "Top edge of the bounding box (0-based)"},
                    "width":  {"type": "integer", "description": "Box width in pixels, at least 1"},
                    "height": {"type": "integer", "description": "Box height in pixels, at least 1"},
                    "color":  {"type": "string",  "description": "Hex color string, e.g. #FF0000"},
                    "fill":   {
                        "type": "boolean",
                        "description": "True for a solid ellipse, false for a 1px outline. Default false.",
                        "default": False,
                    },
                },
                "required": ["x", "y", "width", "height", "color"],
            },
        ),
        types.Tool(
            name="erase_area",
            description=(
                "Erase a rectangle of the ACTIVE LAYER's cel back to transparency — "
                "alpha 0, not an opaque colour painted over the top, so this is how a "
                "mistake is taken back rather than covered up. Coordinates are a "
                "bounding box, as in get_region and draw_rect. At most 4096 pixels "
                "(64x64) per call, the same cap get_region has; a request overhanging "
                "the canvas is clipped to the part that exists. If the active layer "
                "has no cel at the active frame there is nothing painted to erase, and "
                "the call succeeds reporting 0 pixels."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "x":      {"type": "integer", "description": "Left edge (0-based)"},
                    "y":      {"type": "integer", "description": "Top edge (0-based)"},
                    "width":  {"type": "integer", "description": "Region width in pixels, at least 1"},
                    "height": {"type": "integer", "description": "Region height in pixels, at least 1"},
                },
                "required": ["x", "y", "width", "height"],
            },
        ),
        types.Tool(
            name="get_sprite_info",
            description=(
                "Read the active sprite as structured fields: width, height, colorMode, "
                "frames, layers, activeLayer, activeFrame, paletteSize, filename, "
                "isModified. Call this to find out what canvas you are drawing into — "
                "its size bounds every coordinate the other tools accept."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="get_canvas_image",
            description=(
                "See the canvas. Returns the active sprite composited — visible layers, "
                "active frame — as a PNG image. This is the only tool that shows the "
                "composite; get_pixel and get_region read the active layer instead. "
                "Small sprites carry little for a vision model, so scale them up: a "
                "32x32 sprite at scale 8 arrives as 256x256, nearest-neighbour, no blur."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "scale": {
                        "type": "integer",
                        "description": "Nearest-neighbour upscale factor, 1-8. Default 1.",
                        "minimum": 1,
                        "maximum": 8,
                        "default": 1,
                    },
                },
            },
        ),
        types.Tool(
            name="get_pixel",
            description=(
                "Read one pixel of the ACTIVE LAYER's cel — not the composite, so a "
                "colour on a layer below is not what comes back. Returns "
                "{\"x\", \"y\", \"color\": \"#RRGGBB\", \"alpha\": 0-255}, resolved to hex in "
                "every colour mode including indexed. Errors if the active layer has no "
                "cel at the active frame, rather than reporting a transparent pixel."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "x": {"type": "integer", "description": "X coordinate (0-based)"},
                    "y": {"type": "integer", "description": "Y coordinate (0-based)"},
                },
                "required": ["x", "y"],
            },
        ),
        types.Tool(
            name="get_region",
            description=(
                "Read a rectangle of the ACTIVE LAYER's cel, run-length encoded. Returns "
                "{\"x\", \"y\", \"width\", \"height\", \"encoding\": \"rle\", \"rows\"}, where rows is "
                "row-major: rows delimited by '|', runs within a row as 'count,RRGGBB' "
                "delimited by ';'. E.g. '3,FF0000;1,000000|4,00FF00' is a 4x2 region — "
                "three red then one black, then four green. Colour only: a transparent "
                "pixel reads as 000000, so use get_pixel when alpha matters. At most "
                "4096 pixels (64x64) per call; a request overhanging the canvas is "
                "clipped, and x/y/width/height report what was actually read."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "x":      {"type": "integer", "description": "Left edge (0-based)"},
                    "y":      {"type": "integer", "description": "Top edge (0-based)"},
                    "width":  {"type": "integer", "description": "Region width in pixels"},
                    "height": {"type": "integer", "description": "Region height in pixels"},
                },
                "required": ["x", "y", "width", "height"],
            },
        ),
        types.Tool(
            name="list_layers",
            description=(
                "List every layer of the active sprite, bottom to top, each with name, "
                "stackIndex, opacity, blendMode, isVisible, isEditable, isGroup, "
                "isBackground, and hasCel for the active frame. Call this to find out "
                "where a drawing operation will land and whether its result will be "
                "visible. Layers inside a group are listed after the group itself."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="get_selection",
            description=(
                "Read the active sprite's selection bounds: "
                "{\"isEmpty\", \"x\", \"y\", \"width\", \"height\"}. Reads only — nothing here "
                "changes the selection."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="undo",
            description=(
                "Undo one step of the active sprite's history — Aseprite's own undo "
                "stack, the one Ctrl+Z drives. One step is not necessarily one tool "
                "call: Aseprite sets the granularity, so a single undo may reverse less "
                "than a whole call, and get_undo_depth is the way to see how many steps "
                "there are. Returns \"nothing to undo\" on an empty stack rather than "
                "failing."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="redo",
            description=(
                "Redo one step of the active sprite's history, reversing an undo. Any "
                "new drawing operation discards the redo stack, as it does in the "
                "editor. Returns \"nothing to redo\" when there is nothing to redo "
                "rather than failing."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="get_undo_depth",
            description=(
                "Read how far the active sprite's history reaches: "
                "{\"undoSteps\", \"redoSteps\"} — the number of steps available to undo "
                "and to redo. Call this to find out whether an undo will do anything "
                "before spending a call on it."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="add_frame",
            description=(
                "Add a frame to the active sprite, either duplicating an existing "
                "frame's art or starting blank. The new frame is inserted immediately "
                "after the reference frame and becomes the active frame, so a draw call "
                "straight afterwards lands on it. Duplicating copies the cels of every "
                "layer that had one, groups included — that is how you continue an "
                "animation from the previous pose; set duplicate false to start from an "
                "empty canvas. Frame numbers are 1-based."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "duplicate": {
                        "type": "boolean",
                        "description": (
                            "True to copy the reference frame's art into the new frame, "
                            "false for an empty frame. Default true."
                        ),
                        "default": True,
                    },
                    "after": {
                        "type": "integer",
                        "description": (
                            "1-based number of the frame to insert after. Defaults to "
                            "the active frame."
                        ),
                        "minimum": 1,
                    },
                },
            },
        ),
        types.Tool(
            name="delete_frame",
            description=(
                "Delete a frame from the active sprite by its 1-based number. EVERY "
                "LATER FRAME SHIFTS DOWN BY ONE — deleting frame 2 of 5 makes the old "
                "frame 3 the new frame 2 — so a frame number identifies a position at "
                "one moment, not a frame across calls; re-read list_frames after "
                "deleting rather than reusing numbers. A sprite cannot be left with no "
                "frames, so deleting the only frame is refused."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "frame": {
                        "type": "integer",
                        "description": "1-based number of the frame to delete",
                        "minimum": 1,
                    },
                },
                "required": ["frame"],
            },
        ),
        types.Tool(
            name="set_frame_duration",
            description=(
                "Set how long a frame is held during playback. THE DURATION IS IN "
                "MILLISECONDS, not seconds — 100 is a tenth of a second, and 12fps is "
                "83. Valid range is 1 to 65535 ms; Aseprite stores nothing outside it, "
                "so a value beyond either end is refused rather than silently clamped. "
                "Durations are per frame, so an animation with varied timing takes one "
                "call per frame. Read them back with list_frames."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "frame": {
                        "type": "integer",
                        "description": "1-based number of the frame to retime",
                        "minimum": 1,
                    },
                    "duration": {
                        "type": "integer",
                        "description": "Duration in MILLISECONDS, 1 to 65535. E.g. 83 for 12fps.",
                        "minimum": 1,
                        "maximum": 65535,
                    },
                },
                "required": ["frame", "duration"],
            },
        ),
        types.Tool(
            name="set_active_frame",
            description=(
                "Move which frame is active. THIS IS HOW YOU DRAW ON A FRAME OTHER THAN "
                "THE FIRST: every drawing and reading tool here — draw_pixel, "
                "draw_pixels_batch, the shape tools, erase_area, get_pixel, get_region, "
                "get_canvas_image — works on whatever frame is active and takes no frame "
                "parameter of its own, so target a frame once with this and the calls "
                "that follow land there. Frame numbers are 1-based; list_frames reports "
                "the valid range and which frame is active now."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "frame": {
                        "type": "integer",
                        "description": "1-based number of the frame to make active",
                        "minimum": 1,
                    },
                },
                "required": ["frame"],
            },
        ),
        types.Tool(
            name="list_frames",
            description=(
                "List every frame of the active sprite in order, each with "
                "{\"frameNumber\", \"durationMs\", \"isActive\"}. Durations are in "
                "MILLISECONDS, matching set_frame_duration. Exactly one frame reports "
                "isActive true — that is the frame every draw and read tool is currently "
                "working on. Call this to see an animation's structure rather than "
                "guessing at frame numbers, especially after a delete has renumbered "
                "them."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="open_file",
            description=(
                "Open an existing file from disk — an .aseprite sprite, or any image "
                "format Aseprite can read — as a new sprite, which BECOMES THE ACTIVE "
                "SPRITE. Every drawing and reading tool works on the active sprite, so "
                "the calls that follow land on what was just opened; use "
                "set_active_sprite to go back to another one. Opening a plain image "
                "gives a single-layer, single-frame sprite; an .aseprite file keeps its "
                "layers, frames, and tags."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Absolute path of the file to open"},
                },
                "required": ["path"],
            },
        ),
        types.Tool(
            name="save_sprite",
            description=(
                "Save the active sprite to disk, keeping its layers, frames, and tags. "
                "WRITES .ase OR .aseprite ONLY — those are the formats that preserve "
                "that structure, and pointing this at a flat format would scatter one "
                "file per frame rather than writing the path you asked for; use "
                "export_png or export_spritesheet for flat output. With no path it "
                "saves back over the file the sprite was opened from or last saved to, "
                "and a sprite that has never been saved has no such path, so the first "
                "save must name one."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": (
                            "Absolute path ending in .ase or .aseprite. Omit to save "
                            "back to the sprite's existing file."
                        ),
                    },
                },
            },
        ),
        types.Tool(
            name="list_sprites",
            description=(
                "List every sprite currently open, each with {\"index\", \"filename\", "
                "\"width\", \"height\", \"isModified\", \"isActive\"}. Exactly one reports "
                "isActive true — that is the sprite every other tool is working on. "
                "INDEX 1 IS THE MOST RECENTLY OPENED, and opening or closing a sprite "
                "renumbers the rest, so read this again rather than reusing an index "
                "across those calls. Returns an empty result when nothing is open, "
                "rather than failing."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
            },
        ),
        types.Tool(
            name="set_active_sprite",
            description=(
                "Move which sprite is active. THIS IS HOW YOU WORK ON A SPRITE OTHER "
                "THAN THE LAST ONE OPENED: every drawing and reading tool here operates "
                "on whatever sprite is active and takes no sprite parameter of its own, "
                "so target a sprite once with this and the calls that follow land there. "
                "Indexes are 1-based and come from list_sprites, which reports the valid "
                "range and which sprite is active now."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "index": {
                        "type": "integer",
                        "description": "1-based index from list_sprites",
                        "minimum": 1,
                    },
                },
                "required": ["index"],
            },
        ),
        types.Tool(
            name="close_sprite",
            description=(
                "Close the active sprite. A SPRITE WITH UNSAVED CHANGES IS REFUSED "
                "unless force is true — call save_sprite first, or pass force to discard "
                "the changes deliberately. Which sprite is active afterwards is "
                "Aseprite's choice — the result names it when one is promoted, and says "
                "so when nothing is left active. Read that rather than assuming, and use "
                "set_active_sprite if it is not the one you want."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "force": {
                        "type": "boolean",
                        "description": (
                            "True to close and discard unsaved changes. Default false, "
                            "which refuses a modified sprite."
                        ),
                        "default": False,
                    },
                },
            },
        ),
        types.Tool(
            name="export_spritesheet",
            description=(
                "Export every frame of the active sprite as ONE image laid out in a "
                "grid, left to right then top to bottom. This is a minimal wrapper: one "
                "PNG, all frames, and columns is the only control — no padding, "
                "trimming, tag or layer filtering, and no JSON data file. Cells are the "
                "full sprite size, so a 6-frame 32x32 sprite at 3 columns comes out "
                "96x64. A column count larger than the frame count collapses to one row."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "path":    {"type": "string", "description": "Absolute file path for the exported sheet"},
                    "columns": {
                        "type": "integer",
                        "description": "Cells per row, at least 1. Default 1.",
                        "minimum": 1,
                        "default": 1,
                    },
                },
                "required": ["path"],
            },
        ),
    ]


# ----- tool dispatch -------------------------------------------------------

def _ok(text: str) -> types.CallToolResult:
    return types.CallToolResult(content=[types.TextContent(type="text", text=text)])


def _image(data: bytes) -> types.CallToolResult:
    """
    A PNG returned as image content, so the model sees the canvas rather than a
    description of it. The bytes are base64-encoded here because that is what
    the MCP image block carries.
    """
    return types.CallToolResult(
        content=[
            types.ImageContent(
                type="image",
                data=base64.b64encode(data).decode("ascii"),
                mimeType="image/png",
            )
        ]
    )


def _error(text: str) -> types.CallToolResult:
    """
    A failed call, marked so the client can tell it apart from a success without
    reading the prose. The message text is deliberately unchanged:
    docs/TROUBLESHOOTING.md quotes these strings verbatim.
    """
    return types.CallToolResult(
        content=[types.TextContent(type="text", text=text)],
        isError=True,
    )


@mcp_server.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> types.CallToolResult:
    # The SDK returns a CallToolResult through unchanged, which is what keeps
    # isError under our control rather than the exception wrapper's.
    if name == "get_canvas_image":
        return await _canvas_image(arguments)
    return await _dispatch(name, arguments)


async def _canvas_image(arguments: dict[str, Any]) -> types.CallToolResult:
    """
    The canvas takes a side path: a base64 PNG has no business crossing a socket
    that carries line-oriented control traffic. Aseprite writes the file, this
    reads it back.

    The destination is generated here and overrides anything the caller passed,
    so no tool parameter can aim the write. Both processes already share a
    filesystem — the bridge binds 127.0.0.1 and export_png has always written
    paths the plugin resolves locally.
    """
    fd, path = tempfile.mkstemp(prefix="aseprite-mcp-", suffix=".png")
    os.close(fd)

    try:
        result = await _dispatch("get_canvas_image", {**arguments, "path": path})
        if result.isError:
            return result

        try:
            with open(path, "rb") as handle:
                data = handle.read()
        except OSError as exc:
            return _error(f"Error: Aseprite reported success but the image was unreadable: {exc}")

        return _image(data)
    finally:
        # Covers every outcome — success, plugin error, timeout, disconnect.
        with contextlib.suppress(OSError):
            os.unlink(path)


async def _dispatch(tool: str, params: dict[str, Any]) -> types.CallToolResult:
    """Send a command to Aseprite, await the response, return the tool result."""
    global aseprite_ws

    if aseprite_ws is None:
        return _error("Aseprite not connected — open Aseprite and load the plugin")

    command_id = str(uuid.uuid4())
    message = json.dumps({"id": command_id, "tool": tool, "params": params})

    future: asyncio.Future[dict[str, Any]] = asyncio.get_running_loop().create_future()
    pending[command_id] = future

    try:
        await aseprite_ws.send(message)
        log.info("Sent command %s: %s", command_id, tool)

        response = await asyncio.wait_for(future, timeout=TOOL_TIMEOUT)
    except asyncio.TimeoutError:
        pending.pop(command_id, None)
        return _error(f"Timeout: Aseprite did not respond within {TOOL_TIMEOUT}s")
    except websockets.exceptions.ConnectionClosed:
        pending.pop(command_id, None)
        aseprite_ws = None
        return _error("Aseprite disconnected before responding")
    finally:
        pending.pop(command_id, None)

    if response.get("ok"):
        result_data = response.get("result", {})
        if isinstance(result_data, str):
            return _ok(result_data)
        return _ok(json.dumps(result_data))
    else:
        error = response.get("error", "Unknown error from Aseprite")
        return _error(f"Error: {error}")


# ---------------------------------------------------------------------------
# WebSocket server
# ---------------------------------------------------------------------------

async def ws_handler(websocket: ServerConnection) -> None:
    """Handle the Aseprite plugin WebSocket connection."""
    global aseprite_ws

    if aseprite_ws is not None:
        log.warning("Second Aseprite connection rejected (already have one)")
        await websocket.close(1008, "Only one Aseprite connection allowed")
        return

    aseprite_ws = websocket
    log.info("Aseprite connected from %s", websocket.remote_address)

    try:
        async for raw in websocket:
            try:
                msg: dict[str, Any] = json.loads(raw)
            except json.JSONDecodeError:
                log.warning("Received non-JSON message: %r", raw)
                continue

            # Handshake packet — just log it.
            if msg.get("type") == "handshake":
                log.info(
                    "Handshake: Aseprite %s, plugin protocol %s",
                    msg.get("aseprite", "?"),
                    msg.get("version", "?"),
                )
                continue

            # Response to a pending command.
            cmd_id: str | None = msg.get("id")
            if cmd_id is None:
                log.warning("Message without 'id' field dropped: %s", msg)
                continue

            future = pending.get(cmd_id)
            if future is None:
                # Unknown UUID — drop silently as required.
                log.debug("Dropped response for unknown id %s", cmd_id)
                continue

            if not future.done():
                future.set_result(msg)

    except websockets.exceptions.ConnectionClosed as exc:
        log.info("Aseprite disconnected: %s", exc)
    finally:
        aseprite_ws = None
        # Cancel any futures that are still waiting.
        for fut in list(pending.values()):
            if not fut.done():
                fut.cancel()
        log.info("Aseprite connection cleaned up")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main(port: int | None = None) -> None:
    if port is None:
        port = resolve_port()

    log.info("Starting WebSocket server on ws://127.0.0.1:%d", port)
    async with serve(ws_handler, "127.0.0.1", port):
        log.info("WebSocket server ready. Starting MCP stdio transport…")
        async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
            await mcp_server.run(
                read_stream,
                write_stream,
                mcp_server.create_initialization_options(),
            )


if __name__ == "__main__":
    asyncio.run(main())
