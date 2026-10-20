# Troubleshooting

Every message these tools produce, and what to do about it. Parameter reference
is in [TOOLS.md](TOOLS.md).

## Connection

### "Aseprite not connected — open Aseprite and load the plugin"

Every tool returns this — marked as an MCP error — when no plugin is connected.
In order of likelihood:

1. **Aseprite is not running.** Start it.
2. **The plugin is not installed or not enabled.** Check
   **Edit → Preferences → Extensions** for *Aseprite MCP Bridge*.
3. **The two ends are on different ports.** Nothing negotiates the port, so a
   bridge on 9876 and a plugin on 9877 will never meet, and neither logs an
   error about it. Check **View → Console** in Aseprite for the
   `[MCP] Connecting to ws://127.0.0.1:<port> ...` line and compare it with the
   server's `Starting WebSocket server on ws://127.0.0.1:<port>`. See
   [Setting the port](#setting-the-port) — remember the plugin only sees the
   variable if it was set **before** Aseprite started.
4. **The plugin failed to load.** Same console: `[MCP] Connecting to ...` with no
   `[MCP] Connected.` means it could not reach the server at all.

### "Timeout: Aseprite did not respond within 10s"

This is what a stale bridge looks like: the socket is connected but nothing
comes back, so every call waits the full ten seconds.

The reliable tell is in the bridge log — a connection with no `Handshake:` line
after it. A healthy reconnection logs both:

```
[INFO] Aseprite connected from ('127.0.0.1', 57859)
[INFO] Handshake: Aseprite 1.3.7, plugin protocol 0.4.0
```

If you see the connection but never the handshake, the plugin loaded is an old
one. Reinstall it (`python scripts/install_plugin.py`) and restart Aseprite.

A server restart on its own is no longer a cause. Aseprite's WebSocket
reconnects within a second or two and re-sends its handshake, so the bridge
recovers without touching the editor.

### "Port <port> is occupied by an incompatible bridge; stop old servers before upgrading"

Shared-session frontends automatically reuse a compatible bridge. An old server
cannot handle frontend connections; stop existing server processes once when
upgrading, then start a new session. The plugin reconnects automatically.

### "Port <port> is occupied by an incompatible service; stop it or change ASEPRITE_MCP_PORT"

Another service owns the configured port or does not complete the WebSocket
handshake. Stop that service or change the port for both the server and editor.
The frontend never terminates another process to claim its port.

### "Shared bridge on port <port> did not start within 5s; see bridge log"

The child process could not start listening in time. The launching frontend
prints `Shared bridge log: <path>` to stderr. That temporary log file holds
bridge startup, plugin handshake, command, and failure details. Existing sessions
that reuse a bridge do not create another log. Logs remain available after the
bridge exits and may be removed when no longer needed.

### "Cannot connect to shared bridge on port <port>: <reason>"

The operating system refused local communication for a reason other than an
unused port. Check the supplied reason, local firewall, and process permissions.

### "Shared bridge disconnected before responding; command outcome unknown"

The frontend lost contact with the bridge before receiving a result. The editor
may already have executed the command. Inspect its state before retrying a
mutation. The next call automatically reconnects or starts a replacement bridge;
the interrupted call is never replayed automatically.

### "Aseprite disconnected before responding" / "Error: Aseprite disconnected before responding"

The editor connection closed during a call. The editor may have executed the
command before disconnecting. Let the plugin reconnect and inspect editor state
before retrying. Existing MCP sessions remain usable.

### "Error: Internal bridge failure; see bridge log"

An unexpected server exception occurred. Inspect the bridge log for its traceback.
The call returns an MCP error, and the bridge continues serving other calls.

### Shared session lifetime

Closing the first session does not disconnect other sessions. After the last
frontend leaves, the bridge exits after 60 seconds, waiting for running calls to
finish. A connected plugin alone does not keep it alive. A later session starts
a new bridge and the plugin reconnects.

All sessions share active editor state. Individual calls serialize, but sequences
can interleave; coordinate sprite/frame changes between sessions when needed.

### Only one Aseprite at a time

A second Aseprite instance is rejected with WebSocket close code 1008. The
first connection keeps the bridge.

## Setting the port

The bridge uses `127.0.0.1:9876` by default. To move it, set
`ASEPRITE_MCP_PORT` — **for both ends**. Nothing negotiates the port, so if only
one side is changed, they never meet and every tool reports "Aseprite not
connected".

**The server** reads it from its own environment. In an MCP client
configuration that is the `env` block:

```json
{
  "mcpServers": {
    "aseprite": {
      "command": "uvx",
      "args": ["aseprite-mcp"],
      "env": { "ASEPRITE_MCP_PORT": "9877" }
    }
  }
}
```

For Claude Code, the equivalent is:

```bash
claude mcp add aseprite --env ASEPRITE_MCP_PORT=9877 -- uvx aseprite-mcp
```

An unusable value stops the server at startup with
`error: ASEPRITE_MCP_PORT must be an integer between 1 and 65535, got 'nine'`,
rather than falling back to the default and leaving you to wonder why nothing
connects.

**The plugin** reads the same variable from Aseprite's environment, which means
it must be set before Aseprite starts — Aseprite does not inherit anything you
export after launch:

| Platform | Setting it for Aseprite |
| --- | --- |
| Windows | `setx ASEPRITE_MCP_PORT 9877`, then start Aseprite from a **new** shell or the Start menu. |
| macOS / Linux | `ASEPRITE_MCP_PORT=9877 aseprite`, or export it from your shell profile / desktop entry. |

If the plugin sees a value that is not a port number it prints a warning to
**View → Console** and falls back to 9876 — the server refuses to start on that
same value anyway, so there is nothing to connect to either way.

## Where the plugin lands

Aseprite unpacks the bundle into a per-user directory. You do not need to touch
this by hand, but it is useful to know when something is not loading:

| Platform | Extensions directory |
| --- | --- |
| Windows | `%APPDATA%\Aseprite\extensions\aseprite-mcp\` |
| macOS | `~/Library/Application Support/Aseprite/extensions/aseprite-mcp/` |
| Linux | `~/.config/aseprite/extensions/aseprite-mcp/` |

Editing the copy in that directory is a trap — it drifts from the repository and
your changes vanish on the next install. Edit `plugin/main.lua`, then run
`python scripts/install_plugin.py`. If your Aseprite keeps its configuration
somewhere unusual, set `ASEPRITE_EXTENSIONS_DIR` to override the destination.

## Drawing and reading

### Drawing goes to the wrong layer

Tools act on the active layer and frame. `add_layer` makes its new layer
active, so anything drawn afterwards lands there until you change the selection
in Aseprite.

### "Error: no cel at the active layer and frame"

`get_pixel` and `get_region` read the active layer's cel, and a layer that has
never been drawn on has no cel at that frame — `add_layer` creates the layer,
not the pixels. This is an error rather than a page of transparent pixels,
because "empty" and "transparent" are answers you would act on differently.

Draw something first, or switch to the layer you meant: `list_layers` reports
`hasCel` for the active frame, so it tells you which layers have anything to
read.

### "Error: (40, 5) is outside the sprite"

The coordinate is off the canvas. `get_sprite_info` reports the bounds; they are
0-based, so a 32×32 sprite ends at 31. `get_region` raises the same error when
the rectangle misses the canvas entirely — a rectangle that only overhangs is
clipped instead, and the result reports what was actually read.

### "Error: region of 16384 pixels exceeds the 4096-pixel limit"

`get_region` and `erase_area` each touch at most 4096 pixels — 64×64 — per call.
A tool call has ten seconds to answer and the region is walked a pixel at a time
inside Aseprite, so the limit is what stops a large one from becoming a timeout.
Read the sprite in tiles, erase it in tiles, or call `get_canvas_image` to see it
whole. The count in the message is the clipped area, which can be smaller than
what you asked for.

### "Error: x, y, width and height are required" / "Error: x1, y1, x2 and y2 are required"

A coordinate was missing or was not a number. The four-name form comes from the
bounding-box tools — `draw_rect`, `draw_ellipse`, `erase_area`, `get_region` —
and the `x1, y1, x2, y2` form comes from `draw_line`, which takes two endpoints
instead. The names in the message are the parameters that tool actually wants,
so they are the fastest check that you called the one you meant: `draw_line`
does not take `width`, and `draw_rect` does not take `x2`.

### "Error: width and height must be at least 1"

`draw_rect`, `draw_ellipse`, `erase_area`, and `get_region` describe a
**bounding box**: `x`, `y` is the top-left corner, and `width`/`height` are
sizes. A zero or negative size describes no rectangle at all, so it is refused
rather than silently drawing nothing.

The usual cause is passing a bottom-right corner where a size belongs. To cover
columns 2–9 and rows 2–7, pass `x=2, y=2, width=8, height=6` — not `width=9,
height=7`. Only `draw_line` takes a second point rather than a size.

### `erase_area` reports "erased 0 pixels"

Not an error — nothing was there to erase. Either the active layer has no cel at
the active frame (it has never been drawn on, and `add_layer` creates the layer
but not the pixels), or the rectangle falls entirely outside the canvas. It is
reported rather than raised because an already-transparent region is the state
`erase_area` was asked to produce.

`list_layers` reports `hasCel` per layer for the active frame, which tells you
whether you are erasing on the layer you meant.

### "Error: scale must be between 1 and 8"

`get_canvas_image` takes whole-number scales from 1 to 8. The ceiling bounds the
PNG the assistant receives — a 128×128 sprite at 8× is already 1024×1024.

### "Error: Aseprite reported success but the image was unreadable"

`get_canvas_image` transfers the PNG through a temporary file, and Aseprite said
it wrote one that the server then could not read. The likely causes are a full
disk, or a temporary directory the two processes do not share — which happens
when the server runs somewhere the editor cannot see, such as a container.
`export_png` to a path you choose is the way around it.

## Frames

### "Error: frame must be between 1 and 4" / "Error: after must be between 1 and 4"

The frame number does not exist. Frames are numbered from **1**, not 0, and the
limit in the message is the sprite's current frame count — `list_frames` reports
the frames themselves and `get_sprite_info` reports the count.

The usual cause is a number that was valid before a `delete_frame`. Deleting
frame 2 of 5 leaves four frames and renumbers everything after it, so a frame 5
held from earlier is now past the end. Re-read `list_frames` after a delete
rather than reusing numbers across one.

`after` is the same check under `add_frame`'s parameter name: it names the frame
to insert *after*, so it has to be one that exists. The check is not a
formality — Aseprite does not reject an out-of-range frame here, it pads the
sprite out with blank frames to reach it.

`export_png`'s optional `frame` runs the same check, and for the same reason:
compositing an out-of-range frame does not raise either.

### "Error: cannot delete the only frame"

A sprite must have at least one frame, so the last one cannot be removed. To
clear it rather than delete it, `erase_area` over the canvas, or `add_frame`
with `duplicate: false` first and then delete the old one.

Aseprite itself does not refuse this — `deleteFrame` on a one-frame sprite
returns normally and changes nothing — so the tool raises rather than reporting
a deletion that did not happen.

### "Error: duration must be between 1 and 65535 milliseconds"

`set_frame_duration` takes **milliseconds**, and 1 to 65535 ms is the whole
range Aseprite can store — it keeps the duration as a 16-bit millisecond count.
Zero, a negative value, and anything above 65535 are refused rather than
clamped, because Aseprite clamps them silently: asking for 0 would otherwise
report success on a frame that actually holds 1 ms.

If the number looks far too small, check the unit. Seconds are the native
property but not what this tool takes: a tenth of a second is `100`, not `0.1`,
and `0.1` is not a whole number of milliseconds anyway.

## Files and sprites

### "Error: no file at C:\art\hero.aseprite"

`open_file` looked and there is nothing there. Aseprite resolves the path on its
own machine, so a relative path is relative to wherever Aseprite was launched
from, not to the server or to your shell — pass an absolute one. On Windows both
`C:\art\hero.aseprite` and `C:/art/hero.aseprite` work.

### "Error: could not open C:\art\hero.aseprite — Aseprite cannot read that file"

The file exists but Aseprite would not load it: an extension it has no decoder
for, or contents that do not match the extension. Aseprite prints its own
specific complaint — `libpng error: Not a PNG file`, and so on — to
**View → Console**, which is where to look when the file appears fine.

### "Error: path is required — this sprite has not been saved before"

`save_sprite` with no `path` saves back over the file the sprite came from, and
this sprite has no such file — it came from `create_sprite`, not `open_file`.
Name a path on the first save; afterwards the bare call works.
`get_sprite_info`'s `filename` shows whether a sprite has a file yet.

### "Error: save_sprite writes .ase or .aseprite only — use export_png or export_spritesheet for flat image formats"

`save_sprite` preserves layers, frames, and tags, and `.ase`/`.aseprite` are the
only formats that hold them. The restriction is not fussiness: Aseprite picks
the format from the extension, and a flat format on a multi-frame sprite makes
it write **one file per frame**, incrementing any number already in the name —
`run3.png` on three frames writes `run3.png`, `run4.png` and `run5.png`. Refusing
the extension is how that stays impossible.

For flat output, `export_png` writes one frame and `export_spritesheet` writes
all of them in a grid. Neither touches the sprite's own filename.

### "Error: could not save to C:\art\hero.aseprite" / "Error: could not write C:\art\sheet.png — Aseprite cannot write that format"

Aseprite accepted the call and produced no file. Neither `Sprite:saveAs` nor the
sheet export raises when a write fails, so both are verified by checking the
file afterwards — these messages mean that check found nothing. A read-only
destination, a full disk, or a file locked by another program are the usual
causes, and Aseprite's own explanation is in **View → Console**.

### "Error: sprite has unsaved changes — save_sprite first, or pass force=true"

`close_sprite` will not discard unsaved work by default. Either save it, or pass
`force: true` to close and lose the changes deliberately. `list_sprites` reports
`isModified` for every open sprite, and `get_sprite_info` reports it for the
active one.

### "Error: index must be between 1 and 2"

`set_active_sprite` was given an index that is not an open sprite. Indexes are
**1-based**, and the limit in the message is how many sprites are open now.

The usual cause is an index that was valid before an `open_file` or a
`close_sprite`. Index 1 is the most recently opened sprite, so opening one
renumbers everything below it — call `list_sprites` again rather than reusing an
index across either call.

### "Error: columns must be at least 1"

`export_spritesheet` lays frames out left to right, and a grid needs at least one
column. Aseprite treats `0` as "unlimited", which would put every frame in a
single row, but that is an artefact of its encoding rather than something this
tool promises — ask for the row count you want by name.

### "Error: invalid color mode: sepia (expected RGB, Grayscale, or Indexed)"

`create_sprite` takes `RGB`, `Grayscale`, or `Indexed`, matched
case-insensitively, defaulting to `RGB` when omitted. Anything else is rejected
rather than quietly creating an RGB sprite.
