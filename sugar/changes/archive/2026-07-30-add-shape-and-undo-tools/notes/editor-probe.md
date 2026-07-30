# Editor probe — tasks 1.1, 1.2 and 1.3

Three open questions from `proposal.md` gated groups 2 and 3:

1. What does `app.useTool` expect in `points` for `line`, `rectangle`, and
   `ellipse`, and do the `filled_*` ids fill with no parameter beyond the id?
2. Do `app.undo()` / `app.redo()` raise or no-op with nothing to undo, and what
   are `Sprite.undoHistory`'s field names?
3. Does an alpha-0 `img:drawPixel` on a background layer clamp, fail, or write
   transparency?

**Answers: two inclusive opposite corners; the `filled_*` ids need nothing else;
`undo`/`redo` never raise and silently no-op, and `undoHistory` holds exactly
`undoSteps` and `redoSteps`; the alpha-0 write succeeds as genuine transparency
even on a background layer.**

## Method

`aseprite.exe -b --script <probe>.lua` against the same local build the
`add-canvas-readback` probe used (`C:\Users\ADMIN\Documents\aseprite\build\bin\aseprite.exe`,
`1.0-dev`, `app.apiVersion` 40), two scripts: one for the shape tools, one for
undo/redo plus the background-layer write. Shapes are read back by walking the
active cel's image and printing `#` for any pixel with alpha > 0, so the ASCII
maps below are the literal canvas.

## Output — shape tools (task 1.1)

Every call below is `app.useTool{tool=…, color=RED, layer=app.activeLayer,
frame=app.activeFrame, points={…}}` on a freshly-added layer holding no cel.

```
useTool line (2,2)-(9,7)               ok=true      cel bounds = 2,2 8x6
   2 ..#.............
   3 ...##...........
   4 .....#..........
   5 ......#.........
   6 .......##.......
   7 .........#......

useTool rectangle (2,2)-(9,7)          ok=true      cel bounds = 2,2 8x6
   2 ..########......      ← 8 wide, 6 tall: both corners INCLUSIVE
   3 ..#......#......
   4 ..#......#......
   5 ..#......#......
   6 ..#......#......
   7 ..########......

useTool filled_rectangle (2,2)-(9,7)   ok=true      cel bounds = 2,2 8x6
   2 ..########......      ← fills with no parameter beyond the tool id
   3 ..########......
   4 ..########......
   5 ..########......
   6 ..########......
   7 ..########......

useTool ellipse (2,2)-(9,7)            ok=true      cel bounds = 2,2 8x6
   2 ....####........      ← inscribed in the same inclusive bounding box
   3 ...#....#.......
   4 ..#......#......
   5 ..#......#......
   6 ...#....#.......
   7 ....####........

useTool filled_ellipse (2,2)-(9,7)     ok=true      cel bounds = 2,2 8x6
   2 ....####........
   3 ...######.......
   4 ..########......
   5 ..########......
   6 ...######.......
   7 ....####........

useTool line (4,4)-(4,4)               ok=true   cel 4,4 1x1   one pixel at 4,4
useTool line points={Point(3,3)}       ok=true   cel 3,3 1x1   one pixel at 3,3
useTool rectangle (5,5)-(5,5)          ok=true   cel 5,5 1x1   one pixel at 5,5
useTool rectangle (9,7)-(2,2)          ok=true   identical to (2,2)-(9,7)
                                                 ← corner order does not matter
useTool tool='not_a_tool'              ok=false
        invalid tool specified in app.useTool() function
useTool rectangle inside app.transaction  ok=true   drew normally
```

Clipping, on an 8x6 sprite:

```
rectangle (-3,-2)-(4,3)          ok=true   cel bounds = 0,0 5x4
   0 ....#...          ← the two in-canvas edges only; the cel is created
   1 ....#...            tight to the CLIPPED shape, not to the request
   2 ....#...
   3 #####...

filled_rectangle (-3,-2)-(20,20) ok=true   cel bounds = 0,0 8x6, fully painted
rectangle (-3,-2)-(20,20)        ok=true   cel = nil — NOT created
                                           ← the outline lies entirely off-canvas,
                                             so nothing is painted and no cel appears
```

## Output — undo / redo (task 1.2)

```
app.undo type = function        app.redo type = function

app.activeSprite after :close() = nil
app.undo() with NO active sprite       ok=true      ← does not raise
app.redo() with NO active sprite       ok=true

spr.undoHistory type                  table        ← a plain table, not userdata
pairs(spr.undoHistory)                redoSteps=0 undoSteps=0
                                                   ← exactly two fields, no others
  undoHistory.undoSteps               0
  undoHistory.redoSteps               0
  undoHistory.canUndo                 nil
  undoHistory.canRedo                 nil
  undoHistory.position                nil
  undoHistory.size                    nil

app.undo() with nothing to undo        ok=true      ← silent no-op, not an error
app.redo() with nothing to redo        ok=true

after newLayer + 1 draw transaction   undoSteps=2  redoSteps=0
app.undo()                             ok=true     undoSteps=1  redoSteps=1
                                                   cel = nil (the draw is gone)
app.redo()                             ok=true     undoSteps=2  redoSteps=0
                                                   cel restored, 1,1 4x4

10x app.undo() from undoSteps=2        undoSteps=0  redoSteps=2  ← floors, no error
10x app.redo() from redoSteps=2        undoSteps=2  redoSteps=0  ← ceils, no error
```

## Output — alpha-0 write on a background layer (task 1.3)

```
Sprite(8,6).backgroundLayer            nil          ← a fresh sprite has none
layers[1].isBackground                 false
app.command.BackgroundFromLayer() → spr.backgroundLayer   Layer: …
bg.isBackground                        true
bg cel exists                          true
bg img colorMode                       0  (RGB)

bg (2,2) after opaque write            raw=4278190335 a=255
bg img:drawPixel alpha 0               ok=true      ← no error, no clamp
bg (2,2) after alpha-0 write           raw=0 a=0
composite Image(spr) at (2,2)          raw=0 a=0    ← transparent in the composite too

transparent layer, same sequence:
  (2,2) before erase                   raw=4278190335 a=255
  img:drawPixel alpha 0                ok=true
  (2,2) after erase                    raw=0 a=0    ← identical behaviour
```

## What this settles

- **`points` is two opposite corners, inclusive at both ends.** A `rectangle`
  from `Point(2,2)` to `Point(9,7)` is 8 wide and 6 tall, so every
  bounding-box handler constructs `{Point(x, y), Point(x + width - 1,
  y + height - 1)}`. Getting this wrong by one is the difference between a
  `draw_rect` of width 8 and one of width 9, and it is not in the API docs.
  Corner order is normalised by Aseprite, so no handler needs to sort them.
- **`line` takes the two endpoints directly**, so `draw_line` passes
  `{Point(x1, y1), Point(x2, y2)}` with no arithmetic at all.
- **The `filled_*` tool ids fill on their own.** No `fill`, `ink`, or brush
  parameter is involved, so `resolve_shape_tool` returning the id is the whole
  of the fill decision — which is what makes it worth being a pure function.
- **A degenerate shape is one pixel, not an error.** A zero-length line, a
  single-element `points`, and a 1x1 rectangle all draw exactly one pixel, so
  `draw_line` needs no special case and design.md's "not rejected" for
  identical endpoints is confirmed rather than assumed.
- **`useTool` auto-creates the cel, sized to the clipped shape** — not to the
  sprite, the way `draw_pixels_batch` creates a full-size cel. Nothing in this
  change depends on the cel's extent, but `get_pixel`/`get_region` read through
  `cel.position`, which already handles a tight cel.
- **Clipping is Aseprite's, and a fully off-canvas shape paints nothing** — no
  cel is created at all in that case, and the call still succeeds. So no
  handler adds bounds logic on top of `useTool`, and a caller who asks for a
  shape entirely outside the sprite gets a success with no visible effect
  rather than an error. That is the same shape as `draw_pixels_batch`'s silent
  clipping.
- **An unrecognised tool id raises** (`invalid tool specified in app.useTool()
  function`), so `resolve_shape_tool`'s error on an unknown shape is defence in
  depth rather than the only guard — but it produces a message naming the shape
  the caller actually passed, which the editor's does not.
- **`undo`/`redo` need the step count to decide anything.** `app.undo()` and
  `app.redo()` never raise: not with nothing to undo, not with no sprite open,
  not called ten times past the bottom of the stack. So the `"nothing to undo"`
  branch design.md left pending on this task is driven by reading
  `spr.undoHistory.undoSteps == 0` **before** calling `app.undo()`, not by
  catching an error from it. Without that check the tool would report `"undone"`
  having done nothing.
- **`undoHistory` has exactly `undoSteps` and `redoSteps`.** `pairs` enumerates
  those two and nothing else — `canUndo`, `canRedo`, `position`, and `size` are
  all nil — so `get_undo_depth` returns those two fields and there is no richer
  form to expose. It is a plain table, so unlike `json.decode`'s `JsonObj` it
  needs no normalisation. It is also a snapshot: re-read `spr.undoHistory`
  after each operation rather than holding one.
- **`undo`/`redo` still require an active sprite in this bridge**, even though
  `app.undo()` tolerates its absence: the step count comes from
  `Sprite.undoHistory`, so all three handlers keep the project's existing
  `no active sprite` convention. A tool that silently succeeded with no sprite
  open would be the one tool in eighteen that does.
- **`erase_area` can write alpha 0 unconditionally.** The background-layer case
  design.md flagged as a risk does not exist at the image level: the write
  succeeds, reads back `a=0`, and composites as transparent. Aseprite's
  restriction on background transparency lives in the UI and the interactive
  eraser, not in `Image:drawPixel` — which is exactly the argument for
  `erase_area` bypassing the eraser tool. One behaviour in every mode,
  confirmed rather than assumed.
- **One transaction can be more than one undo step.** `newLayer` plus a draw
  registered `undoSteps=2`, so `undo` is not "undo my last tool call" — it is
  Aseprite's own step granularity. Worth saying in the README so a caller does
  not expect one `undo` to reverse one MCP call.

## Caveat

Same single self-built `1.0-dev` binary on Windows, `apiVersion` 40, in batch
mode (`-b`). Batch mode is the caveat that matters most for the undo findings:
`app.undo()` is the same call the UI's Ctrl+Z reaches, but nothing here proves
the GUI's undo stack behaves identically under a live editor session with
tool-setting state. Tasks 7.1–7.3 verify all of it interactively before the
change ships.
