# Editor probe — tasks 1.1, 1.2, 1.3 and 1.4

Four open questions from `proposal.md` gated groups 2 and 3:

1. Does `Sprite:saveAs` infer its format from the extension, what does it
   accept for a multi-layer multi-frame sprite, and what happens with an empty
   path on a sprite that has never been saved?
2. Does `app.open` raise, return `nil`, or leave `app.activeSprite` unchanged
   on a path it cannot read?
3. Does `Sprite:close()` prompt, raise, or discard silently?
4. What are `ExportSpriteSheet`'s real parameter names, and is `type` a string
   or a `SpriteSheetType` enum value?

**Answers: `saveAs` writes a numbered SEQUENCE to any still-image format on a
multi-frame sprite — the same `export_png` bug this change fixes, so
`save_sprite` restricts to `.ase`/`.aseprite`; `app.open` never raises and
returns `nil` for every failure; `Sprite:close()` never raises and never
prompts, and leaves NO sprite active even when others are still open;
`ExportSpriteSheet` takes `textureFilename`/`columns`/`type`, accepts either an
enum or a string for `type`, and needs `type` present or `columns` is ignored
entirely. Two findings fell out that neither question anticipated: a failed
`saveAs` reports success AND clears `isModified`, and a fresh sprite's
`filename` is the bare string `"Sprite"`, not empty.**

## Method

`aseprite.exe -b --script <probe>.lua` against the same local build the three
prior probes used (`C:\Users\ADMIN\Documents\aseprite\build\bin\aseprite.exe`,
`1.0-dev`), six scripts: `saveAs` extensions and round-trip, a follow-up to
settle the sequence-naming hypothesis, `app.open` against four fixture kinds,
`Sprite:close` plus `app.sprites` ordering, `ExportSpriteSheet` parameters, and
a follow-up on the JSON dump.

Sprites are tagged by **width**, not filename: every unsaved sprite reports the
same `filename`, so width is the only thing that tells two of them apart in an
ordering dump. Frames are tagged by fill colour and duration, as in the prior
probes.

One counting mistake is worth recording because it nearly hid the main finding.
The first extension sweep counted output files with the prefix `t3.`, which
does not match `t4.png` — and `t4.png` is exactly what saving `t3.png` produces.
The per-iteration listings only made sense once re-run with a
new-files-since-last-check diff.

## Output — `Sprite:saveAs` (task 1.1)

Extensions, saving a 2-layer 3-frame 8x8 sprite:

```
saveAs t1.ase        ok=true   spr.filename=<path>  isModified=false
saveAs t2.aseprite   ok=true   spr.filename=<path>  isModified=false
saveAs t3.png        ok=true   spr.filename=<path>  isModified=false
saveAs t4.gif        ok=true   spr.filename=<path>  isModified=false
saveAs t5.bmp        ok=true   spr.filename=<path>  isModified=false
saveAs t6.jpg        ok=true   spr.filename=<path>  isModified=false
saveAs t7.webp       ok=true   spr.filename=<path>  isModified=false
saveAs t8.xyz        ok=true   spr.filename=<path>  isModified=false
   Aseprite can't save "…\t8.xyz" file ("xyz")      ← console only, NOT an error
saveAs t9  (no ext)  ok=true   spr.filename=<path>  isModified=false
   Aseprite can't save "…\t9" file ("")             ← console only
```

Reopening the `.aseprite` preserves everything:

```
layers=2 frames=3 tags=1 durations=0.100/0.200/0.300   tag1 = walk
```

The sequence hypothesis, re-run with a clean new-files diff:

```
3-frame sprite, saveAs -> plain.png    new files: [plain1.png plain2.png plain3.png]
3-frame sprite, saveAs -> num3.png     new files: [num3.png num4.png num5.png]
3-frame sprite, saveAs -> shot07.png   new files: [shot07.png shot08.png shot09.png]
1-frame sprite, saveAs -> plain.png    new files: [plain.png]
3-frame sprite, saveAs -> anim.gif     new files: [anim.gif]
3-frame sprite, saveAs -> anim.webp    new files: [anim.webp]
```

So a still-image format spreads the frames over as many files, **incrementing
whatever number is already embedded in the base name** and appending one when
there is none. `num3.png` produces `num3/num4/num5` — the requested path exists,
but the two beside it are collateral. Reopening `t3.png` afterwards reports
`frames=3`, because Aseprite recognises its own sequence on the way back in.
This is the identical misbehaviour `add-canvas-readback` recorded for
`saveCopyAs`, re-confirmed here for completeness:

```
3-frame sprite, saveCopyAs -> copy.png   files: [copy1.png copy2.png copy3.png]
   isFile("copy.png") = false            ← never writes the path it was given
```

The two findings nobody asked for:

```
== a FAILED saveAs ==
before: filename=[Sprite]      isModified=true
        saveAs("…\nope.xyz")   → no error raised, no return value
after : filename=[…\nope.xyz]  isModified=false
        file written = false
        spr.filename is writable = true

== the "never been saved" test ==
fresh.filename              = [Sprite]     ← NOT "" as design.md assumed
app.fs.filePath(filename)   = []           ← this is the reliable test
app.fs.fileName(filename)   = [Sprite]
app.fs.fileExtension()      = []
app.fs.isFile(filename)     = false
after a real save, filePath = [C:\Users\…\asemcp-probe3]

== other edges ==
saveAs()                    raises a Lua TypeError (with file:line attached)
saveAs("")                  does not raise; console-only complaint
saveAs into a missing dir   succeeds, creating the directory
app.fs.isFile(path) after a good save = true   ← usable as a post-check
```

**Settles:** the format comes from the extension, and `saveAs` **never raises on
a save failure** — it prints to the console, returns normally, reassigns
`Sprite.filename` to the path it did not write, and clears `isModified`. That
last part is the dangerous one: it marks unsaved work as clean, which is exactly
the flag `close_sprite` consults before discarding a sprite. So the extension is
validated *before* the call rather than diagnosed after it, and
`app.fs.isFile` is still checked afterwards to catch the failures validation
cannot foresee (an unwritable directory, a locked file), restoring the old
`filename` when the file is not there.

`save_sprite` accepts `.ase` and `.aseprite` **only**. `design.md` left this
open — "the finding decides whether the handler restricts extensions or passes
the caller's choice straight through" — and the finding decides it: passing the
choice through would let `save_sprite` scatter a numbered PNG sequence across
the caller's directory while reporting `saved to <path>`, and `.ase`/`.aseprite`
are the only formats that satisfy the requirement's "preserving layers, frames,
and tags" anyway. `.gif` and `.webp` do hold every frame in one file, but they
flatten layers and drop tags, and flat output is what `export_png` and
`export_spritesheet` are for.

## Output — `app.open` (task 1.2)

```
app.open(real .aseprite)      raised=false  returned=doc::Sprite: 0000022C5A940AE8
   activeSprite changed = true   #app.sprites = 1
   opened: 6x5 layers=2 frames=2 isModified=false
   returned sprite IS app.activeSprite = true

app.open(real .png)           raised=false  returned=doc::Sprite: 0000022C5A941A38
   opened: 3x2 layers=1 frames=1   returned sprite IS app.activeSprite = true

app.open(nonexistent path)    raised=false  returned=nil
   File not found: "…\does-not-exist.aseprite"        ← console only
   activeSprite changed = false   #app.sprites = 2

app.open(text file named .png) raised=false returned=nil
   libpng error: Not a PNG file                        ← console only
   activeSprite changed = false

app.open(text file named .xyz) raised=false returned=nil
   Aseprite can't load "…\junk.xyz" file ("xyz")       ← console only
   activeSprite changed = false

app.open('')                  raised=false  returned=nil
   activeSprite changed = false
```

**Settles:** `app.open` returns the opened `Sprite` — which is already
`app.activeSprite` — or `nil`, for every failure kind, and never raises. The
reason is printed to the console and is not available to Lua, so
`open_file` cannot pass Aseprite's own explanation through. It distinguishes the
two cases itself with `app.fs.isFile`, which covers the one a caller can act on:

```
no file at <path>
could not open <path> — Aseprite cannot read that file
```

A failed open leaves the active sprite untouched, so there is no inconsistent
state to unwind.

## Output — `Sprite:close` and `app.sprites` ordering (task 1.3)

Ordering first, because `set_active_sprite` indexes into this list. `*` marks
the active sprite; sprites are labelled by width:

```
created w11                  [1:w11*]
created w12                  [1:w12* 2:w11]
created w13                  [1:w13* 2:w12 3:w11]
active := w11                [1:w13 2:w12 3:w11*]
active := w12                [1:w13 2:w12* 3:w11]
active := w13                [1:w13* 2:w12 3:w11]
active := w11 again          [1:w13 2:w12 3:w11*]
```

Closing:

```
== unmodified ==
isModified before any edit = false
before close                 [1:w21* 2:w13 3:w12 4:w11]
close raised = false
after close                  [1:w13 2:w12 3:w11]

== modified ==
isModified after edit = true
close raised = false                    ← silent discard, no prompt
app.isUIAvailable = false               ← but see the caveat below
x:close(true) raised = false            ← an argument is accepted and ignored

== closing the ACTIVE sprite with others still open ==
active := w32                [1:w33 2:w32* 3:w31 4:w13 5:w12 6:w11]
after closing the active w32 [1:w33 2:w31 3:w13 4:w12 5:w11]
app.activeSprite = nil                  ← NOT handed to a surviving sprite

== closing the last sprite ==
#app.sprites = 0   app.activeSprite = nil

== a closed handle ==
reading .width of a closed sprite → "Tried to access a deleted 'doc::Sprite'"
```

**Settles:** three things.

`app.sprites` is ordered **newest first** and is **stable** — reassigning the
active sprite does not reorder it, so an index survives across calls as long as
nothing is opened or closed. Opening or creating pushes the new sprite to index
1 and shifts everything down; closing removes and shifts. That is the same
"a number is a position at a moment, not an identity" contract `list_layers`'
`stackIndex` and the frame numbers already carry, so `list_sprites` reports
`app.sprites`' own order rather than inventing a second index space.

Closing the active sprite leaves **no** sprite active, even when others remain
open — Aseprite does not promote a survivor. `design.md` expected this only for
the last sprite. So `close_sprite` says so in its result, and the tool that
follows needs `set_active_sprite`.

`Sprite:close()` does not raise and does not prompt **in batch mode**, where
`app.isUIAvailable` is false. That is not the case `force` guards. A `-b` probe
structurally cannot answer what a live editor with a UI does on a modified
sprite, which is the whole reason `design.md` chose to refuse that case rather
than find out — the finding here is that the probe confirms the safe path and
leaves the forced path to task 7.3, not that the risk was imagined. There is no
`force` argument on the API: `close(true)` is accepted and ignored, so the flag
is entirely this bridge's own guard.

## Output — `ExportSpriteSheet` (task 1.4)

```
SpriteSheetType.HORIZONTAL  = 1
SpriteSheetType.VERTICAL    = 2
SpriteSheetType.ROWS        = 3
SpriteSheetType.COLUMNS     = 4
SpriteSheetType.PACKED      = 5
```

Six frames of 10x8, so the sheet's dimensions name the layout:

```
textureFilename only            → a.png  10x8    1 col  x 1 row   ← all overlap
type=SpriteSheetType.ROWS, columns=3 → b.png  30x16   3 cols x 2 rows
type="rows" (string), columns=3      → c.png  30x16   3 cols x 2 rows
columns=2, NO type              → d.png  10x8    1 col  x 1 row   ← ignored
type=ROWS, columns=4            → e.png  40x16   4 cols x 2 rows
type=ROWS, columns=99           → f.png  60x8    6 cols x 1 row   ← clamps
type=ROWS, columns=1            → g.png  10x48   1 col  x 6 rows
type=ROWS, columns=0            → h.png  60x8    6 cols x 1 row   ← unlimited
type="banana", columns=3        → i.png  10x8    1 col  x 1 row   ← silent
type=ROWS, textureFilename=j.xyz → no file written, no error raised
```

Export does not mutate the sprite:

```
before: filename=[Sprite] isModified=true
after : filename=[Sprite] isModified=true
```

The JSON metadata:

```
### BEGIN plain     → dumps the whole JSON blob to the console; files: [plain.png]
### BEGIN nodata    (dataFilename="")  → still dumps;             files: [nodata.png]
### BEGIN nolists   (listLayers/Tags/Slices=false) → still dumps; files: [nolists.png]
### BEGIN withdata  (dataFilename=…json) → no dump;  files: [withdata.json withdata.png]
```

**Settles:** the call `export_spritesheet` makes is exactly

```lua
app.command.ExportSpriteSheet{
  ui              = false,
  type            = SpriteSheetType.ROWS,
  columns         = columns,
  textureFilename = path,
}
```

`type` is **required** — without it every frame lands at 0,0 and the sheet is
one cell, and `columns` is ignored. It is passed as the enum value rather than
the string: both work, but an unrecognised string does not raise, it silently
degrades to that same one-cell sheet, so the same reasoning that keeps
`get_canvas_image`'s `method="nearest"` a literal applies here. That also
answers task 5.1 — there is no string-to-enum mapping to write, so no
`resolve_*` function and no Lua test for one.

`columns` needs no pre-clamping: greater than the frame count collapses to the
frame count, and `0` means unlimited. The handler still rejects `< 1`, because
`0` meaning "one row of everything" is a coincidence of Aseprite's encoding, not
a contract worth exposing.

Omitting `dataFilename` writes **no JSON file**, which is what the task asked
for, at the cost of Aseprite dumping the metadata to the console. That is
cosmetic — it lands in View → Console next to the plugin's own `[MCP]` lines —
and the alternative is writing a JSON file beside the caller's PNG that nobody
asked for. Supplying a `dataFilename` is the only thing that silences it, so the
dump stays.

Like `saveAs`, a `textureFilename` Aseprite cannot write **fails silently** —
no file, no error — so `export_spritesheet` post-checks with `app.fs.isFile`.

## Output — the `app.fs` and `Image` shapes the handlers lean on

```
[C:\a\b.Aseprite ] ext=[Aseprite] path=[C:\a] name=[b.Aseprite]  ← case preserved
[b.ase           ] ext=[ase]      path=[]     name=[b.ase]
[b               ] ext=[]         path=[]     name=[b]
[C:/x/y.PNG      ] ext=[PNG]      path=[C:/x] name=[y.PNG]       ← forward slashes fine
[                ] ext=[]         path=[]     name=[]

Image(spr, 1) / Image(spr, 2)   ok
Image(spr, 99) on a 2-frame sprite   raised=false   ← does NOT reject
Image(spr, FrameObj)            ok
```

**Settles:** `app.fs.fileExtension` returns the extension **without** the dot and
**preserves case**, so `save_sprite` lowercases before matching. And
`Image(sprite, n)` does not reject an out-of-range frame number — the same trap
`newFrame(99)` set for `add_frame` — so `export_png`'s range check on `frame` is
load-bearing rather than defensive.

## Output — group 7, against the GUI (and what it overturned)

The four checks in group 7 ran through the full MCP → WebSocket → GUI-plugin
path, which is the first time anything here met a live editor rather than
`-b --script`. Three findings came out of it, two of them corrections to what
the batch probes above concluded.

### `Image(sprite, frame)` ignores the frame — it always renders frame 1

Found because `export_png` was asked for frame 1 and frame 2 of a 3-frame sprite
and produced two byte-identical files. `frame` was reaching the handler — 99 was
correctly rejected as out of range — so the fault was the render itself:

```
expect red 60 / 120 / 180 for frames 1 / 2 / 3

Image(spr, <number>):
   Image(spr, 1) -> red=60      Image(spr, 2) -> red=60      Image(spr, 3) -> red=60
Image(spr, <FrameObj>):
   frames[1] -> red=60          frames[2] -> red=60          frames[3] -> red=60
with the active frame moved to 3:
   Image(spr, 1) -> red=60      Image(spr, 2) -> red=60      Image(spr, 3) -> red=60
Image(spr, 99) -> red=60        ← and still does not raise
```

Not "always the active frame" — **always frame 1**, even with frame 3 active.
The silent tolerance of `Image(spr, 99)` recorded further up is the same defect
seen from the other side: the argument is not being used at all.

`Image:drawSprite(sprite, frame)` is the call that works:

```
A: img:drawSprite(spr, frame)     frame 1 -> 60   frame 2 -> 120   frame 3 -> 180
B: move app.frame, then Image(spr)          1 -> 60          2 -> 60          3 -> 60
C: move app.frame, Image(spr, activeFrame)  1 -> 60          2 -> 60          3 -> 60
```

and it is a real composite, not just the active cel:

```
both visible      (0,0)=200,100,50 a=255   empty(3,3) a=0
top hidden        (0,0)=10,20,30   a=255   empty(3,3) a=0   ← visibility honoured
bottom hidden     (0,0)=200,100,50 a=255
top opacity 128   (0,0)=105,60,40  a=255   ← layer opacity blended
```

**Settles:** both `export_png` and `get_canvas_image` render with

```lua
local img = Image(spr.width, spr.height, spr.colorMode)
img:drawSprite(spr, frame)
```

This also means **`get_canvas_image` was returning frame 1 from the day it
shipped**, whatever the active frame — invisible while every sprite was
single-frame, and invisible after the frame tools shipped too, because nothing
asked it for a specific frame until `export_png` grew a `frame` parameter.
The delta spec's wording for this requirement names
`Image(sprite, frameNumber):saveAs(path)` as the mechanism; that prescription is
wrong and the requirement's own scenarios ("the exported PNG composites that
frame") are what the code now satisfies.

### Closing DOES promote a survivor in the GUI

The batch finding above — "closing leaves no sprite active, even with others
still open" — is a batch artefact. Through the live editor, twice:

```
close roundtrip.aseprite (2 still open)  → flat.png  became active
close flat.png  (force, 2 still open)    → "Sprite"  became active
```

A UI has a focused tab; a batch run has nothing to focus. So `close_sprite`
reads `app.activeSprite` after closing and reports what it finds, rather than
asserting either behaviour — the hardcoded "none active — use
set_active_sprite" was actively wrong in the environment the plugin actually
runs in.

### `force` does not prompt in the GUI

The open question the whole `close_sprite` design was built around.
`close_sprite` on a modified sprite was refused as designed; `force: true` on
that same sprite returned **immediately** with no confirmation dialog and no
approach to the 10s timeout. So the forced path is usable, and the default
refusal stays a deliberate safety choice rather than a workaround for a dialog
that turns out not to exist.

## What this changes in the plan

- `save_sprite` restricts to `.ase`/`.aseprite` rather than passing the
  caller's extension through, and validates the extension *before* calling
  `saveAs` — a failed `saveAs` clears `isModified`, so diagnosing it afterwards
  would leave unsaved work flagged as safe to discard.
- `save_sprite`'s "never been saved" test is `app.fs.filePath(spr.filename) == ""`,
  not `spr.filename == ""`; a fresh sprite's filename is `"Sprite"`.
- `save_sprite` and `export_spritesheet` both post-check `app.fs.isFile`,
  because neither underlying call raises when the write fails.
- `open_file` checks for a `nil` return, not a raised error, and builds its own
  reason from `app.fs.isFile` since Aseprite's goes to the console.
- `close_sprite` reports whichever sprite is active after the close, or that
  none is — the two environments differ, so it reads rather than asserts.
- `export_png` and `get_canvas_image` render with `img:drawSprite(spr, frame)`;
  `Image(spr, frame)` silently ignores the frame.
- `list_sprites`/`set_active_sprite` document that index 1 is the most recently
  opened sprite and that opening or closing renumbers.
- `export_spritesheet` passes `type = SpriteSheetType.ROWS` as a literal enum
  value; task 5.1's resolver branch does not apply.
