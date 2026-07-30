# Editor probe — tasks 1.1 and 1.2

Three open questions from `proposal.md` gated groups 2 and 3:

1. Does `json.decode` return a plain Lua table or a proxy?
2. Does `saveCopyAs` to a `.png` on a multi-frame sprite write one file or a
   numbered sequence?
3. Is there a Lua route that upscales the canvas, and what can `scale` be?

**Answers: a proxy (`JsonObj` userdata); a numbered sequence; yes —
`Image(sprite, frame)` composites and `image:resize{method="nearest"}` upscales.**

## Method

`aseprite.exe -b --script <probe>.lua` against the local build
(`C:\Users\ADMIN\Documents\aseprite\build\bin\aseprite.exe`, `1.0-dev`,
`app.apiVersion` 40), three scripts: one for the `json` namespace, one for the
image/save paths, one for the enum keys and per-frame compositing.

## Output — `json` (task 1.1)

```
type(json) = table
json fields:                     ← pairs() enumerates nothing; methods are behind a metatable
_VERSION = Lua 5.4

pcall(json.decode, CMD)          ok=true
type(res)                        = userdata      ← NOT a table
getmetatable(res)                = table: 0000028FA0440DC0
res.id                           = abc-123       ← indexing works
res['id']                        = abc-123
type(res.params)                 = userdata
params.pixels                    = 0,0,FF0000;1,1,00FF00
params.x                         = 5.0   type=number   ← integers decode as FLOATS
params.y                         = -3.0
params.flag                      = true  type=boolean
params.nil_ish                   = nil   type=nil      ← JSON null reads back as nil
params.missing                   = nil

type(nested)                     = userdata
nested.deep.n                    = 2.0             ← nesting survives, arbitrarily deep
type(arr)                        = userdata
#arr                             = 3               ← # works
ipairs(arr)                      = 1=10.0 2=20.0 3=30.0
pairs(arr)                       = (nothing)       ← pairs() yields nothing for a JSON array
arr[1]                           = 10.0
objarr[2].a                      = 2.0
pairs(res)                       = id:string params:userdata tool:string
                                                   ← pairs() DOES work for a JSON object
next(empty_o)                    ok=false  bad argument #1 to 'next' (table expected, got JsonObj)

decode("{not json")              ok=false  expected '"' in object, got 'n' (110)
decode("")                       ok=false  unexpected end of input
decode("[1,2")                   ok=false  unexpected end of input
decode("{\"a\":}")               ok=false  expected value, got '}' (125)
decode("nonsense")               ok=false  parse error: expected null, got nons
decode("null")                   ok=true   null          ← the one input that does not raise

json.encode({})                  = []               ← same empty-table ambiguity as ours
```

## Output — images and saving (task 1.2)

```
Image(spr)                       4x4, px(1,1) = 00FF00     (green top layer over red)
Image(spr) with top hidden       px(1,1) = FF0000          ← hidden layers are skipped
Image(spr, 1)                    4x4                        ← frame-selecting form exists
Image(spr, 2) both visible       00FF00 a=255
Image(spr, 2) top hidden         FF0000 a=255               ← composites per frame the same way
empty sprite composite           000000 a=0                 ← transparent, not opaque black

type(base.resize)                = function
resize{width=8,height=8}                     ok=true  8x8
resize method=nearest                        ok=true  8x8 px=00FF00
resize method=bilinear                       ok=true  8x8 px=00FE00   ← methods differ, so they apply
resize method='definitely-not-a-method'      ok=true            ← invalid methods do NOT raise
resize(8, 8) positional                      ok=true  8x8

Image(spr):saveAs(path)                      ok=true  file exists

spr:saveCopyAs("probe_single.png")   1 frame  → probe_single.png            exists
spr:saveCopyAs("probe_multi.png")    3 frames → probe_multi.png             DOES NOT EXIST
                                               probe_multi1.png
                                               probe_multi2.png
                                               probe_multi3.png
Image(spr, 2):saveAs("probe_frame2.png")     → exactly one file
Image(spr,2):resize{16,16,nearest}:saveAs    → exactly one file, 16x16
```

```
ColorMode   GRAY=1 GRAYSCALE=1 INDEXED=2 RGB=0 TILEMAP=4
BlendMode   CLEAR=0 SRC=1 DST=2 NORMAL=3 SRC_OVER=3 DST_OVER=4 … MULTIPLY=14
            SCREEN=15 OVERLAY=16 … COLOR=27 HSL_COLOR=27 … DIVIDE=31

grayscale getPixel raw=65408 → app.pixelColor.grayaV=128, grayaA=255
indexed   getPixel raw=3     type=number         ← a palette index, not a colour
          #spr.palettes=1, #palette=256, palettes[1]:getColor(3) → .red .green .blue .alpha
          spr.transparentColor = 0               ← the index that means transparent
layer     name stackIndex opacity blendMode(number) isVisible isEditable isGroup isBackground
sprite    colorMode(number) #frames filename("Sprite" when unsaved) isModified
spr.selection is userdata with .isEmpty and .bounds{x,y,width,height}
```

## What this settles

- **`json.decode` returns userdata, so `normalize_command` must copy into a
  plain table** (task 2.2's "normalising to a plain table first" branch is the
  one that applies). Indexing, `pairs` on objects, and `#`/`ipairs` on arrays
  all work, so a recursive copy is straightforward — but `next` rejects a
  `JsonObj`, so nothing may assume table primitives work on the raw value.
- **Objects and arrays are indistinguishable by `type`, and `#` does not
  separate them.** `pairs` is the discriminator: it enumerates an object and
  yields nothing for an array. A follow-up probe, run after the first version
  of `to_plain` dropped every command in a live editor, settled why:

  ```
  obj = json.decode('{"id":"a","tool":"t","params":{"x":1}}')
  #obj         = 3     ← the KEY COUNT, not 0
  #obj.params  = 1
  #json.decode('[1,2,3]') = 3
  ```

  Branching on `#v > 0` therefore reads every command as a three-element array
  of nils, `normalize_command` rejects it, and the call times out at ten
  seconds with nothing in the log but a dropped command. Copy through `pairs`
  first, and fall back to `#` only when `pairs` yielded nothing.
- **Integers decode as floats.** `5` comes back as `5.0`, which would turn
  `draw_pixel`'s "pixel drawn at 5,5" into "pixel drawn at 5.0,5.0" and break
  the plugin spec's "existing flat parameters are unaffected" scenario. The
  normaliser converts integral floats back to integers.
- **Malformed JSON raises rather than returning nil**, exactly as design.md
  assumed — `pcall` at the call site is required, not defensive decoration. The
  single exception is the literal `null`, which decodes successfully to a value
  that is not a table; `normalize_command` rejects it on the type check.
- **`get_canvas_image` must not use `saveCopyAs`.** On a multi-frame sprite it
  writes `<name>1.png`, `<name>2.png`, … and never the path it was given, which
  would leave the server reading a file that does not exist. `Image(sprite,
  frame):saveAs(path)` writes exactly one file at the requested path, on
  single- and multi-frame sprites alike, and composites visible layers only.
  That is the route task 3.1 takes, and it makes the "explicit frame argument"
  contingency in design.md unnecessary — the active frame is implicit.
- **`scale` can be implemented for real.** `image:resize{width, height,
  method="nearest"}` upscales with nearest-neighbour, so task 3.1 is not capped
  at 1. Invalid method strings do not raise, so `"nearest"` is passed as a
  literal and never taken from caller input.
- **`get_pixel` needs three branches, and they are all reachable from Lua.**
  RGB via `app.pixelColor.rgbaR/G/B/A`, grayscale via `grayaV/grayaA`, indexed
  via `spr.palettes[1]:getColor(index)` with `spr.transparentColor` deciding
  alpha 0.
- **Enum values must be named, not echoed.** `colorMode` and `blendMode` are
  bare numbers on the objects. `BlendMode` has aliases sharing a value
  (`NORMAL` and `SRC_OVER` are both 3), so a reverse map built by iterating the
  enum is non-deterministic; the plugin resolves names through a fixed,
  ordered list of the modes Aseprite exposes on layers.

## Caveat

One self-built `1.0-dev` binary on Windows, `apiVersion` 40 — the same binary
the earlier `os.getenv` probe used. The `json` namespace was added in Aseprite
1.3, so a 1.2 editor would fail at `json.decode` with a nil-index error rather
than a handled one; the extension already declares no minimum version, and this
change does not add one.
