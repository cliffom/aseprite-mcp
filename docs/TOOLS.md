# Tool reference

Thirty tools — ten that draw, six that read, three that drive the undo stack,
five that manage frames, five that manage open sprites, and one that exports a
sheet. Every one operates on Aseprite's **active sprite**, and all of them
except `create_sprite`, `open_file` and `list_sprites` fail with
`no active sprite` if nothing is open.

For what to do when one of these returns an error, see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## How it works

```
MCP sessions ──stdio──▶ frontends ──/clients──▶ shared bridge ──/──▶ Aseprite plugin
                                             127.0.0.1:9876          │
                                                               canvas
```

Each session has its own stdio frontend. One background bridge holds the editor
connection and matches replies by UUID, returning actual editor results. The
port is configurable; see [Setting the port](TROUBLESHOOTING.md#setting-the-port).

Calls from every session execute one at a time. The ten-second editor timeout
starts when a call is dispatched, so queued calls can wait longer. Sessions
share active sprite, layer, frame, selection, and undo history; sequences of
calls can interleave. There is no session-specific editor state.

Disconnecting a session removes its queued calls. Already-dispatched calls
finish, including canvas-file cleanup, even if their caller has left. Bridge
failures return errors and reconnect for subsequent calls, without replaying
uncertain mutations.

## The tools

| Tool | Parameters | Does |
| --- | --- | --- |
| `create_sprite` | `width`, `height` (int); `mode` (string, optional) | Creates a new sprite and makes it active. |
| `draw_pixel` | `x`, `y` (int); `color` (`#RRGGBB`) | Draws one pixel with the pencil tool. |
| `fill_area` | `x`, `y` (int); `color` (`#RRGGBB`) | Flood-fills from the seed pixel. |
| `add_layer` | `name` (string) | Adds a layer and makes it active. |
| `export_png` | `path` (absolute string); `frame` (int, optional) | Writes **one** composited PNG of a single frame. |
| `draw_pixels_batch` | `pixels` (string, see below) | Draws many pixels in one call. |
| `draw_line` | `x1`, `y1`, `x2`, `y2` (int); `color` (`#RRGGBB`) | Draws a 1px line between **two endpoints**. |
| `draw_rect` | `x`, `y`, `width`, `height` (int); `color`; `fill` (bool, optional) | Draws a rectangle in a **bounding box**, outlined or filled. |
| `draw_ellipse` | `x`, `y`, `width`, `height` (int); `color`; `fill` (bool, optional) | Draws an ellipse inscribed in a **bounding box**. |
| `erase_area` | `x`, `y`, `width`, `height` (int) | Erases a rectangle of the **active layer** back to transparency. |
| `get_canvas_image` | `scale` (int 1–8, optional) | Returns the **composited** canvas as a PNG image. |
| `get_sprite_info` | none | Reports size, colour mode, frames, layers, active layer and frame. |
| `list_layers` | none | Lists every layer with the attributes that decide where drawing lands. |
| `get_pixel` | `x`, `y` (int) | Reads one pixel of the **active layer**. |
| `get_region` | `x`, `y`, `width`, `height` (int) | Reads a rectangle of the **active layer**, run-length encoded. |
| `get_selection` | none | Reports the selection bounds. |
| `undo` | none | Undoes one step of Aseprite's own history. |
| `redo` | none | Redoes one step. |
| `get_undo_depth` | none | Reports how many steps are available to undo and redo. |
| `add_frame` | `duplicate` (bool, optional); `after` (int, optional) | Inserts a frame after another, duplicating its art or empty. |
| `delete_frame` | `frame` (int) | Deletes a frame; **later frames renumber down**. |
| `set_frame_duration` | `frame` (int); `duration` (int, **milliseconds**) | Sets how long a frame is held in playback. |
| `set_active_frame` | `frame` (int) | Moves the frame every other tool works on. |
| `list_frames` | none | Lists every frame with its duration and which is active. |
| `open_file` | `path` (absolute string) | Opens a file from disk and makes it the active sprite. |
| `save_sprite` | `path` (absolute string, optional) | Saves the sprite, keeping layers and frames. **`.ase`/`.aseprite` only.** |
| `list_sprites` | none | Lists every open sprite and which one is active. |
| `set_active_sprite` | `index` (int) | Moves the sprite every other tool works on. |
| `close_sprite` | `force` (bool, optional) | Closes the active sprite; **refuses unsaved changes** unless forced. |
| `export_spritesheet` | `path` (absolute string); `columns` (int, optional) | Writes every frame as one image in a grid. |

Coordinates are 0-based from the top-left. Colours are hex; `draw_pixel` and
`fill_area` accept an optional leading `#`.

**The shape tools do not all take coordinates the same way.** `draw_pixel` takes
one point, `draw_line` takes two endpoints, and `draw_rect`/`draw_ellipse`/
`erase_area`/`get_region` take a bounding box — a top-left corner plus a width
and height, not a second corner. Passing a bottom-right corner as `width`,
`height` draws a shape far larger than intended.

**The two views are not the same view.** `get_pixel` and `get_region` read the
active layer's cel — what *you* painted — so a colour sitting on a layer
underneath is not what comes back, and a pixel on a hidden layer still reads at
full strength. `get_canvas_image` reads the composite: visible layers merged,
active frame, exactly what the editor is showing. Reach for the pixel readers
to check a batch you just drew, and for the image to see the result.

A failed call comes back marked as an MCP error, so an assistant can tell
failure from success without reading the message.

## Colour modes

`create_sprite` takes `mode` as `RGB`, `Grayscale`, or `Indexed`, matched
case-insensitively and defaulting to `RGB` when omitted. Anything else is
rejected — `invalid color mode: sepia (expected RGB, Grayscale, or Indexed)` —
rather than quietly creating an RGB sprite. The confirmation names the mode it
used: `created 32x32 GRAYSCALE`.

## `get_sprite_info`

Returns the active sprite as JSON. Worth calling before a batch: the canvas size
bounds every coordinate the drawing tools accept, and pixels outside it are
clipped silently.

```json
{
  "width": 32, "height": 32, "colorMode": "rgb",
  "frames": 1, "layers": 3,
  "activeLayer": "Layer 2", "activeFrame": 1,
  "paletteSize": 256, "filename": "fox.aseprite", "isModified": true
}
```

`colorMode` is `rgb`, `grayscale`, or `indexed`. `layers` counts top-level
layers, the same set `list_layers` starts from.

## `draw_pixels_batch` and its encoding

`pixels` is a single flat string:

```
x,y,RRGGBB;x,y,RRGGBB;...
```

for example `0,0,FF0000;1,0,FF0000;2,0,00FF00`. No spaces, no `#` prefix, and
six hex digits exactly. A trailing `;` is fine.

**Use this instead of repeated `draw_pixel` calls.** Every tool call is a full
round-trip — assistant to server to Aseprite and back — so drawing a 32×32
sprite one pixel at a time costs a thousand of them. The demo image in the
README was 563 pixels drawn in four calls.

The flat string exists because it is compact and because one encoding idiom is
easier to meet than two — `get_region` reads pixels back with the same
delimiters. It predates the plugin's move to Aseprite's native JSON parser,
which decodes nested structures fine; the format stays because a thousand pixel
objects cost far more on the wire than a thousand `x,y,RRGGBB` triples.

Entries that do not match the format exactly are skipped rather than aborting
the batch, and the result string reports how many — `drew 561 pixels (2
malformed entries skipped)`. Pixels outside the canvas are clipped silently.
Internally, `draw_pixels_batch` writes to the cel image directly instead of
invoking the pencil tool per pixel, which is what makes the batch fast.

## The shape tools

`draw_line`, `draw_rect`, and `draw_ellipse` draw a whole shape in one call, and
they are what to reach for before encoding one by hand. A 40px filled circle is
roughly 1,200 characters of `x,y,RRGGBB` triples for `draw_pixels_batch`; as
`draw_ellipse` it is five integers.

```
draw_line    x1, y1, x2, y2, color        two endpoints, both inclusive
draw_rect    x, y, width, height, color, fill    bounding box
draw_ellipse x, y, width, height, color, fill    bounding box
```

`draw_line` takes the two endpoints directly, and both are drawn: a line from
`0,0` to `9,0` is ten pixels long. Identical endpoints draw a single pixel rather
than failing.

`draw_rect` and `draw_ellipse` take a **bounding box** — `x`, `y` is the
top-left pixel, `width` and `height` are sizes. So `x=2, y=2, width=8, height=6`
covers columns 2–9 and rows 2–7. `width` and `height` must be at least 1;
anything smaller is refused with `width and height must be at least 1`. An equal
width and height gives `draw_ellipse` a circle.

`fill` chooses the shape: omitted or `false` draws a 1px outline, `true` fills
the whole shape. It defaults to the outline because filling is the destructive
choice — a filled shape paints over everything inside it.

```
draw_rect  x=2 y=2 w=8 h=6         draw_rect  ... fill=true
  ########                           ########
  #......#                           ########
  #......#                           ########
  #......#                           ########
  #......#                           ########
  ########                           ########
```

All three use Aseprite's own tools, so the line stepping and ellipse
rasterisation are the same ones you get drawing interactively, and every stroke
is 1px — there is no brush-size or thickness parameter. Parts of a shape past
the canvas edge are clipped, and a shape entirely off-canvas draws nothing and
still reports success.

The confirmations name what was drawn: `drew line from 2,2 to 9,7`,
`drew rect at 2,2 8x6`, `drew ellipse at 2,2 8x6`.

## `erase_area`

Erases a rectangle of the **active layer** back to transparency — alpha 0, not
an opaque colour painted over the top. It is the only way to take a mistake back
without undoing it: `draw_pixels_batch` and the shape tools always write alpha
255, so before this the only correction available was painting over.

Coordinates are a bounding box, the same convention as `draw_rect` and
`get_region`. The result reports what it touched: `erased 96 pixels`.

**At most 4096 pixels — 64×64 — per call**, the same cap `get_region` carries
and for the same reason: the region is walked one pixel at a time inside
Aseprite against a ten-second budget. A larger request is refused with
`region of 16384 pixels exceeds the 4096-pixel limit`.

A request overhanging the canvas is clipped to the part that exists, and the cap
applies to the clipped area. If the active layer has no cel at the active frame
there is nothing painted to erase, so the call succeeds with `erased 0 pixels`
rather than creating an empty cel.

Unlike Aseprite's interactive eraser, this behaves the same on a background
layer as anywhere else — it writes genuine transparency rather than the
background colour.

## `get_canvas_image`

Returns the composited sprite — visible layers merged, active frame — as a PNG
image block, so an assistant with vision sees the canvas rather than a
description of it.

`scale` upscales with nearest-neighbour, 1 to 8, default 1. Use it: a 32×32 PNG
carries very little for a vision model, and at `scale: 8` the same sprite
arrives as 256×256 with every pixel edge still hard. Anything outside 1–8 is
rejected with `scale must be between 1 and 8`.

The transfer goes through a temporary file rather than the WebSocket: the server
generates the path, Aseprite writes the PNG there, the server reads it back and
deletes it. The path is not a parameter, and passing one has no effect — it is
overwritten before the command is sent. The delete happens on every outcome,
including a plugin error or a timeout.

## `list_layers`

Returns one object per layer, bottom to top:

```json
[
  {"name": "Background", "stackIndex": 1, "opacity": 255, "blendMode": "normal",
   "isVisible": true, "isEditable": true, "isGroup": false,
   "isBackground": true, "hasCel": true}
]
```

`hasCel` is for the **active frame** — `false` means the layer holds nothing
there yet, which is what `get_pixel` errors on. Layers inside a group are listed
immediately after the group itself, and `stackIndex` is the position within the
parent.

## `get_selection`

Returns `{"isEmpty": true, "x": 0, "y": 0, "width": 0, "height": 0}`, or the
selection rectangle when one exists. Read-only — nothing here changes the
selection.

## `get_pixel`

```json
{"x": 4, "y": 5, "color": "#E8782A", "alpha": 255}
```

`color` is always `#RRGGBB`, in every colour mode: an indexed sprite's palette
index is resolved through the palette rather than handed back as a number, and a
grayscale value is mirrored across the three channels.

It reads the active layer's cel. A coordinate outside the canvas is an error
(`(40, 5) is outside the sprite`), and so is a layer with no cel at the active
frame (`no cel at the active layer and frame`) — an empty layer reports nothing
rather than a plausible-looking transparent pixel you might trust. A coordinate
inside the canvas but outside the cel's own bounds does read as transparent:
`#000000` with `alpha` 0.

## `get_region` and the region encoding

Reads a rectangle of the active layer, run-length encoded:

```json
{"x": 0, "y": 0, "width": 4, "height": 2, "encoding": "rle",
 "rows": "3,FF0000;1,000000|1,00FF00;3,000000"}
```

The `rows` string is row-major:

```
rows   are delimited by  |
runs   are delimited by  ;
a run  is               count,RRGGBB
```

So `3,FF0000;1,000000|1,00FF00;3,000000` is the 4×2 region above: the top row is
three red pixels then one black, the bottom row is one green then three black.
No spaces, no `#`, six hex digits — the same colour format `draw_pixels_batch`
takes, so what you read back can go straight into what you write.

Pixel art is mostly flat runs, which is exactly what this compresses: a 64×64
region of four-colour art comes back in a few hundred bytes where a per-pixel
dump would be 24 KB.

**The encoding carries colour only.** A transparent pixel reads as `000000`,
indistinguishable from painted black. When alpha matters, use `get_pixel`.

**At most 4096 pixels — 64×64 — per call.** A larger request is refused with
`region of 16384 pixels exceeds the 4096-pixel limit` rather than attempted: a
tool call has ten seconds to answer, the region is read one pixel at a time
inside Aseprite, and an error naming the limit is far easier to act on than a
timeout. Read a big sprite in tiles, or use `get_canvas_image` to see it whole.

A request that overhangs the canvas is clipped to it, and the returned
`x`, `y`, `width`, `height` describe what was actually read — check them rather
than assuming you got the rectangle you asked for. The cap applies to the
clipped area. A region entirely outside the canvas is an error.

## `undo`, `redo`, and `get_undo_depth`

These drive Aseprite's own undo stack — the one Ctrl+Z drives in the editor —
so a wrong shape can be reverted instead of painted over.

```json
get_undo_depth → {"undoSteps": 4, "redoSteps": 0}
```

`undo` returns `undone`, `redo` returns `redone`. Neither fails on an exhausted
stack: they return `nothing to undo` and `nothing to redo` instead, so a call at
the bottom of the history is a no-op you can read rather than an error you have
to handle.

**A step is Aseprite's unit, not this bridge's.** In practice each drawing call
registers one step, so one `undo` reverses one call — but the granularity is
Aseprite's to decide, not something these tools declare, so do not build on the
1:1 mapping. `get_undo_depth` before and after is how to tell how far a revert
actually went.

Drawing anything new discards the redo stack, exactly as it does in the editor.

## The frame tools

Aseprite is an animation tool, and these five are what make its frame axis
reachable. Frame numbers are **1-based**.

```json
list_frames → [
  {"frameNumber": 1, "durationMs": 100, "isActive": false},
  {"frameNumber": 2, "durationMs": 83,  "isActive": true},
  {"frameNumber": 3, "durationMs": 83,  "isActive": false}
]
```

**`add_frame`** inserts after a reference frame and makes the new frame active,
so the next drawing call lands on it without a separate `set_active_frame`.
`after` defaults to the active frame, and `duplicate` defaults to **true** —
copying the cels of every layer that had one, groups included, which is how an
animation continues from the previous pose. Pass `duplicate: false` for a blank
frame. It returns `added frame 3 (duplicated frame 2)` or `added empty frame 3`,
naming the number the new frame actually got.

**`delete_frame` renumbers.** Deleting frame 2 of 5 makes the old frame 3 the
new frame 2, exactly as the editor's frame list behaves. A frame number is a
position at one moment, not an identity that survives a delete — call
`list_frames` again rather than reusing numbers across one. Deleting the only
frame is refused; a sprite cannot have none.

**`set_frame_duration` takes milliseconds**, not Aseprite's native seconds: 100
is a tenth of a second and 12fps is 83. The valid range is **1 to 65535 ms**,
which is everything Aseprite can store — a value outside it is rejected rather
than silently clamped to the nearest end. Durations are per frame, so varied
timing costs one call per frame. `list_frames` reports `durationMs` in the same
unit, and a value set through this tool reads back exactly.

### Drawing on a frame other than the first

**Every drawing and reading tool works on the active frame and takes no frame
parameter of its own** — `draw_pixel`, `draw_pixels_batch`, the shape tools,
`erase_area`, `get_pixel`, `get_region`, and `get_canvas_image` alike. None of
them changed when the frame tools were added. `set_active_frame` is the one that
moves the target, and the calls after it land wherever it pointed:

```
add_frame {duplicate: true}      → added frame 2 (duplicated frame 1)
                                   (frame 2 is now active)
draw_pixels_batch {...}          → drew 12 pixels          on frame 2
set_active_frame {frame: 1}      → active frame set to 1
get_pixel {x: 3, y: 3}           → reads frame 1, not frame 2
```

`list_frames` reports which frame is active, and `get_sprite_info`'s
`activeFrame` says the same thing alongside the rest of the sprite.

## The file and sprite tools

These five give the bridge a lifecycle beyond "create a sprite from nothing and
export a flat PNG of it": existing art can be opened and edited, layered
multi-frame work can be written back to disk, and more than one sprite can be
open at a time.

```json
list_sprites → [
  {"index": 1, "filename": "C:\\art\\hero.aseprite", "width": 32, "height": 32,
   "isModified": true,  "isActive": true},
  {"index": 2, "filename": "C:\\art\\tiles.aseprite", "width": 64, "height": 64,
   "isModified": false, "isActive": false}
]
```

**`open_file`** reads any format Aseprite can open and makes the result the
active sprite. An `.aseprite` file keeps its layers, frames, and tags; a plain
image arrives as a single layer and a single frame. It reports what it opened —
`opened C:\art\hero.aseprite (32x32, 8 frames)`.

**`save_sprite` writes `.ase` or `.aseprite` only.** That is not caution, it is
the format question: those are the two that preserve layers, frames, and tags,
and Aseprite decides the format from the extension. Pointed at a flat format on
a multi-frame sprite it would write **one file per frame** — a 3-frame sprite
saved to `run3.png` produces `run3.png`, `run4.png` *and* `run5.png` — so the
extension is refused up front rather than after the fact. Use `export_png` for
one frame and `export_spritesheet` for all of them.

With no `path` it saves back over the file the sprite came from. A sprite made
by `create_sprite` has no such file until the first save names one.

**`close_sprite` refuses a modified sprite** unless `force` is true. Save it
first, or pass `force` to discard the changes deliberately — there is no
confirmation prompt behind this tool, and there is deliberately no way to
discard unsaved work by accident.

**Which sprite is active afterwards is Aseprite's choice, not this tool's.** With
others still open the editor generally promotes one, and the result names it —
`closed …\hero.aseprite (2 still open, now active: …\tiles.aseprite)`. Read that
rather than assuming, and use `set_active_sprite` if it picked one you did not
want. Closing the last sprite leaves nothing active, and the result says so.

**`export_spritesheet`** lays every frame out in a grid, left to right then top
to bottom, at the full sprite size per cell. It is a deliberately minimal
wrapper around Aseprite's own export: one image, all frames, and `columns` is
the only control. No padding, no trimming, no tag or layer filtering, and no
JSON data file. Six frames of 32x32 at `columns: 3` come out 96x64; a column
count larger than the frame count collapses to a single row.

### Working on a sprite other than the last one opened

**Every tool here operates on the active sprite and takes no sprite parameter of
its own** — exactly as they all work on the active *frame*. `open_file` and
`create_sprite` make their new sprite active, so a second `open_file` silently
redirects everything that follows. `set_active_sprite` is what moves the target
back:

```
open_file {path: "hero.aseprite"}   → opened hero.aseprite (32x32, 8 frames)
draw_pixel {...}                    → draws on hero
open_file {path: "tiles.aseprite"}  → opened tiles.aseprite (64x64, 1 frames)
draw_pixel {...}                    → draws on TILES, not hero
set_active_sprite {index: 2}        → active sprite set to …\hero.aseprite
draw_pixel {...}                    → draws on hero again
```

**Indexes are positions, not identities.** Index 1 is the most recently opened
sprite, and opening or closing renumbers the rest — the same contract
`delete_frame` has with frame numbers. Read `list_sprites` again after either
rather than reusing an index across one.
