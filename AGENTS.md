# aseprite-mcp

Guidance for coding agents (Codex, Claude Code, Cursor, etc.) and humans
working in this repo.

MCP server that drives a live Aseprite instance over a local WebSocket bridge.
Two processes, one socket between them.

## Architecture

```
Makefile                      → dev tasks; `make` lists them, Python runs in Poetry's ./.venv
src/aseprite_mcp/server.py    → WebSocket server + MCP stdio server on one event loop
src/aseprite_mcp/__main__.py  → console script; resolves the port before asyncio.run
plugin/main.lua               → the Aseprite-side WebSocket client (only source of truth)
plugin/package.json           → extension manifest Aseprite reads
scripts/build_extension.py    → zips plugin/ into dist/aseprite-mcp.aseprite-extension
scripts/install_plugin.py     → build + unpack into Aseprite's extensions dir
tests/test_server.py          → pytest: dispatch, timeout, disconnects, contract drift
tests/lua/                    → zero-dependency Lua runner for main.lua's pure functions
sugar/                        → spec-driven change dirs (see "Spec-driven workflow")
.claude/skills/sf-*/SKILL.md  → the sf-* workflow definitions, plain markdown
```

Data flow for one tool call:

```
client ──MCP stdio──▶ server.py ──JSON/ws──▶ main.lua ──▶ app.useTool / img:drawPixel
                          ▲                      │
                          └──── {id, ok, result} ┘
```

`server.py` holds at most one Aseprite connection (`aseprite_ws`) and a
`pending` dict of futures keyed by command UUID. `_dispatch` sends, awaits the
matching reply, and returns Aseprite's actual result — not an acknowledgement.

## Tools

Thirty, registered in `list_tools()` in `server.py` and handled in the
`handlers` table in `plugin/main.lua`.

**Write:** `create_sprite`, `draw_pixel`, `fill_area`, `add_layer`,
`export_png`, `draw_pixels_batch`, `draw_line`, `draw_rect`, `draw_ellipse`,
`erase_area`.
**Read:** `get_canvas_image`, `get_sprite_info`, `list_layers`, `get_pixel`,
`get_region`, `get_selection`.
**History:** `undo`, `redo`, `get_undo_depth`.
**Frames:** `add_frame`, `delete_frame`, `set_frame_duration`,
`set_active_frame`, `list_frames`.
**Files and sprites:** `open_file`, `save_sprite`, `list_sprites`,
`set_active_sprite`, `close_sprite`.
**Export:** `export_spritesheet` (and `export_png` above).

Every one except `create_sprite`, `open_file` and `list_sprites` errors with
`no active sprite` when nothing is open — including `undo`/`redo`, whose `app`
calls tolerate no sprite but whose step counts do not. `get_canvas_image` is the
only tool that does not go straight through `_dispatch` — see the temp-file
decision below.

Adding a tool means editing **both** files. The test suite enforces the pairing
(see "Contract tests" below).

Full parameter reference lives in [docs/TOOLS.md](docs/TOOLS.md) and every error
string in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — those two are the
user-facing docs, and the error strings in them are quoted verbatim from the
code. README.md is the short front door and links to both; keep it that way.

## Key design decisions

### `draw_pixels_batch` takes a flat string, not an array

`pixels` is `"x,y,RRGGBB;x,y,RRGGBB;..."` — no spaces, no `#`, six hex digits.

**Why:** it was originally forced — the decoder was a hand-rolled pattern
matcher that handled flat objects only. It no longer is (`json.decode` parses
anything), and the format stays anyway: a thousand pixel objects cost far more
on the wire than a thousand triples, and `get_region` reads back with the same
delimiters, so callers meet one encoding idiom rather than two.

**Trade-off:** callers must encode by hand, and malformed entries are silently
skippable. `parse_pixels` counts them and the result says so —
`drew 561 pixels (2 malformed entries skipped)` — so a typo is visible rather
than a missing pixel.

### Decoding is Aseprite's; encoding is still ours

`json_decode_command` calls `json.decode` under `pcall`, hands the result to a
pure `normalize_command`, and returns nil if it is not a command. `json_encode`
is unchanged and still hand-rolled.

**Why decode moved:** the pattern matcher bounded every future tool's parameter
shape to flat key/value pairs. **Why encode did not:** it already walks nested
tables and arrays, it is unit-tested, and swapping it buys nothing — Aseprite's
`json.encode` has the same empty-table ambiguity ours does.

Two findings from `notes/editor-probe.md` in the change that did this are
load-bearing, and neither is in the API docs:

- **`json.decode` returns a `JsonObj` userdata, not a table.** Indexing, `pairs`
  on objects, and `#`/`ipairs` on arrays work; `next` does not. `to_plain`
  copies it into a real table at the boundary so nothing downstream cares.
- **Every number decodes as a float.** `5` arrives as `5.0` and concatenates as
  `"5.0"`. `to_plain` narrows integral floats back, which is what keeps
  `pixel drawn at 5,5` from becoming `pixel drawn at 5.0,5.0`.

Malformed JSON raises rather than returning nil, so the `pcall` is required, not
decoration.

### Handlers may return tables; `dispatch` no longer flattens

`dispatch` sends a table result through `json_encode` as a nested structure and
keeps `tostring` for everything else. `_dispatch` in `server.py` `json.dumps`-es
a non-`str` result for the caller — a branch that existed before this and was
simply unreachable.

`json_encode` encodes the empty table as `{}`, not `[]`: an empty table
satisfies both branches of its array check, and a structured result with no
fields is still a result.

### The pixel readers read the active cel; only the image reads the composite

`get_pixel` and `get_region` read `app.activeLayer:cel(...)`, offset by
`cel.position` exactly as `draw_pixels_batch` writes, and error with
`no cel at the active layer and frame` when there is none.
`get_canvas_image` returns the flattened, composited sprite.

**Why:** a model that just drew to a layer wants to verify *that layer*;
flattening per sample is slow and answers a different question. One tool per
question — "what did I paint?" versus "what does this look like?"

A coordinate inside the sprite but outside the cel reads as transparent
(`#000000`, alpha 0) rather than erroring: the layer genuinely holds nothing
there.

### Nothing writes an image through `saveCopyAs`, and `save_sprite` refuses flat formats

Handed a still-image format on a multi-frame sprite, Aseprite spreads the frames
over as many files, **incrementing whatever number is already in the base name**:
`run3.png` on three frames writes `run3.png`, `run4.png` and `run5.png`, and
`copy.png` writes `copy1/2/3.png` — never the path it was given. This is true of
`Sprite:saveCopyAs` *and* `Sprite:saveAs`; only the format differs in whether it
can hold the frames.

So three tools are shaped by it:

- **`export_png`** renders into an `Image` and saves that — one file, at the
  path asked for, whatever the frame count. It used `saveCopyAs` until
  `add-file-and-sprite-tools`; that was latent while every sprite was
  single-frame and became a live bug the moment the frame tools shipped.
- **`get_canvas_image`** does the same, and always has.
- **`save_sprite`** accepts `.ase`/`.aseprite` only. Those are also the only
  formats that keep layers, frames and tags, so the restriction costs nothing
  the tool was for — and `.gif`/`.webp`, which do hold every frame in one file,
  would still flatten the rest.

Do not "simplify" any of them back to `saveCopyAs`.

### The render is `drawSprite`, and `Image(sprite, frame)` is a trap

```lua
local img = Image(spr.width, spr.height, spr.colorMode)
img:drawSprite(spr, frame)
```

`Image(sprite, frame)` is the call the API reference points at and it looks
exactly right. **It ignores the frame argument and always renders frame 1** — a
number, a `FrameObj`, and moving `app.frame` beforehand all give frame 1's
pixels, and an out-of-range frame does not raise either, which is what lets it
pass for working. `drawSprite` honours the frame and composites identically:
visible layers only, layer opacity blended, untouched areas transparent.

`get_canvas_image` shipped on the broken call and therefore returned frame 1
whatever was active — unnoticed because nothing asked it for a specific frame
until `export_png` gained one. Both were fixed together. Do not "simplify"
either back to `Image(spr, f)`.

The out-of-range tolerance is also why `export_png` range-checks `frame`
itself, exactly as `add_frame` range-checks `after`.

### Aseprite's file calls fail without raising

`app.open` returns `nil`. `Sprite:saveAs` returns normally having written
nothing — **and clears `isModified` on the way past**, which would leave unsaved
work flagged as safe for `close_sprite` to discard. `ExportSpriteSheet` writes no
file and says nothing. In all three the real reason goes to Aseprite's console,
where Lua cannot reach it.

So none of them is wrapped in `pcall`; each is checked by its effect:

- `open_file` tests the return for `nil`, then distinguishes the one case a
  caller can act on with `app.fs.isFile` — `no file at <path>` versus
  `could not open <path> — Aseprite cannot read that file`.
- `save_sprite` validates the extension **before** calling, precisely because
  diagnosing afterwards happens too late to undo the `isModified` clear, then
  still post-checks `app.fs.isFile` for the failures validation cannot foresee
  and restores the previous `filename` if the file is not there.
- `export_spritesheet` post-checks `app.fs.isFile`.

`app.fs.fileExtension` returns the extension without the dot and preserves
case, so `save_sprite` lowercases before matching.

### The active *sprite* is a pointer like the active frame

`set_active_sprite` is to the other twenty-nine tools what `set_active_frame` is
to the drawing tools: they all already read `app.activeSprite`, so moving it is
the whole of what was missing. Nothing else changed when it was added.

`app.sprites` is ordered **newest first** and is stable — reassigning the active
sprite does not reorder it, but opening, creating or closing one does. So an
index is a position at a moment, not an identity, the same contract
`list_layers`' `stackIndex` and the frame numbers carry. `list_sprites` reports
`app.sprites`' own order rather than inventing a second index space.

Two behaviours are Aseprite's, not choices:

- **What becomes active after a close differs between batch and the GUI.** A
  `-b --script` run leaves none active even with others open; a live editor
  promotes a survivor, because the UI has a focused tab and batch has nothing to
  focus. `close_sprite` reads `app.activeSprite` afterwards and reports what it
  finds rather than asserting either — a batch probe alone gets this wrong.
- **A closed `Sprite` handle raises** "Tried to access a deleted 'doc::Sprite'",
  so `close_sprite` reads the filename before closing.

`close_sprite`'s `force` is entirely ours: `Sprite:close()` takes no such
argument (it accepts and ignores one) and in a batch probe discards a modified
sprite silently. What a live editor does with a UI attached is the open
question, and the reason the default refuses — a confirmation dialog would block
the socket for the full timeout and every call after it.

`list_sprites` is the one handler whose list can genuinely be empty, so it is
also the only place `json_encode`'s empty-table rule shows: nothing open encodes
as `{}`, not `[]`. Documented rather than worked around; the rule is pinned by a
test.

### `export_spritesheet` is a wrapper, and `type` is a literal

`app.command.ExportSpriteSheet` needs `ui=false`, `textureFilename`, `columns`
and — load-bearing — `type`. **Without `type` every frame lands at 0,0 and
`columns` is ignored entirely**, producing a one-cell sheet. It is passed as
`SpriteSheetType.ROWS`, the enum value: a string works too, but an unrecognised
one does not raise, it degrades to that same one-cell sheet. Same reasoning as
`get_canvas_image`'s `method="nearest"` — never caller input.

`columns` needs no clamping (0 means unlimited, oversized collapses to the frame
count) but `< 1` is still rejected, because `0` meaning "one row of everything"
is an encoding coincidence rather than a contract.

Omitting `dataFilename` is what keeps a JSON sidecar off disk; Aseprite dumps
the metadata to **View → Console** instead. Cosmetic, and the alternative is
writing a file nobody asked for.

### The canvas image is a temp file, not a WebSocket payload

`call_tool` intercepts `get_canvas_image`, generates a path with
`tempfile.mkstemp`, **overrides** any caller-supplied `path`, and unlinks it in
a `finally` that covers success, plugin error, timeout, and disconnect.

It renders with `img:drawSprite` and saves that — see the two decisions above
for why, the first of which applies here doubly: the server is reading the file
back, so a numbered sequence leaves it opening a path that does not exist.

`scale` upscales via `image:resize{method="nearest"}`. The method is a literal
and never caller input: an unrecognised method string does not raise, it
silently falls back.

### Regions come back run-length encoded, capped at 4096 pixels

Row-major: rows delimited by `|`, runs as `count,RRGGBB` delimited by `;`.

**Why the cap:** `TOOL_TIMEOUT` is 10s for the whole call and the region is read
one `getPixel` at a time in Lua. An error naming the limit is easier to act on
than a timeout, and it bounds the caller's context too. The cap applies to the
clipped area, so an overhanging request reads the part that exists.

The encoding carries colour only — a transparent pixel reads as `000000`. That
is documented, and `get_pixel` is the way to get alpha.

### Batch writes to `cel.image` directly, not `app.useTool`

`draw_pixel` uses the pencil tool (it auto-creates cels and takes
sprite-relative coordinates). `draw_pixels_batch` creates the cel itself, then
calls `img:drawPixel` inside one `app.transaction`.

**Why:** `useTool` per pixel is orders of magnitude slower and conflicts with
transaction nesting. Coordinates are offset by `cel.position` because cel image
space is not sprite space; out-of-bounds pixels are clipped silently.

### `erase_area` writes transparency directly; it does not use the eraser tool

It iterates the clipped region and writes `app.pixelColor.rgba(0,0,0,0)` into
`cel.image` inside one `app.transaction`, mirroring `draw_pixels_batch`'s cel
lookup and `cel.position` offset exactly.

**Why not `app.useTool{tool="eraser"}`:** the interactive eraser is
mode-dependent. On a background layer — which Aseprite does not let hold
transparency through the UI — it paints the background colour instead of
clearing, and its brush shape and opacity answer to tool settings this bridge
has no way to set.

A direct write has one behaviour everywhere. Verified against a live editor: an
alpha-0 `img:drawPixel` on a background layer succeeds, reads back alpha 0, and
composites transparent. Aseprite's restriction on background transparency lives
in the UI and the eraser, not in `Image:drawPixel`.

It does **not** auto-create a cel the way `draw_pixels_batch` does — no cel means
the layer is already empty there, and creating one to leave it transparent has no
observable effect. It returns `erased 0 pixels` instead.

The 4096-pixel `MAX_REGION_PIXELS` cap is reused rather than duplicated: a caller
names a rectangle in four integers, so unlike `draw_pixels_batch` (whose caller
already pays per-pixel in the request) it needs `get_region`'s bound against the
same 10s budget.

### The shape tools go through `useTool`, and `points` is inclusive

`draw_line`, `draw_rect`, and `draw_ellipse` call `app.useTool` inside
`app.transaction`, letting Aseprite's own rasterisation match what a user gets
drawing interactively. Per-pixel `useTool` is what `draw_pixels_batch` avoids;
a single stroke does not have that cost.

**`points` holds two opposite corners, inclusive at both ends** — verified, and
not in the API docs. `Point(2,2)` to `Point(9,7)` is 8 wide and 6 tall, so the
bounding-box handlers pass `Point(x + width - 1, y + height - 1)`. Off by one
here is the difference between a `draw_rect` of width 8 and one of width 9.

The filled variants are separate tool ids (`filled_rectangle`,
`filled_ellipse`), not a parameter, and they fill with nothing else supplied —
so `resolve_shape_tool(shape, fill)` returning the id *is* the fill decision,
which is why it is a pure function with tests. `draw_line` passes `"line"` as a
literal: two endpoints, no filled variant.

`useTool` auto-creates the cel and clips to the canvas, so no handler carries
bounds logic. A shape entirely off-canvas paints nothing, creates no cel, and
still succeeds.

### `undo`/`redo` must check the step count before calling

`app.undo()` and `app.redo()` never raise — not on an empty stack, not with no
sprite open, not called ten times past the bottom. So `"nothing to undo"` is
decided by reading `spr.undoHistory.undoSteps == 0` **before** the call.
Without that check the tool reports `"undone"` having done nothing.

`undoHistory` is a plain snapshot table holding exactly `undoSteps` and
`redoSteps` — no `canUndo`, no `position` — so it is read fresh each time rather
than held, and `get_undo_depth` has no richer form to expose.

Each handler's `app.transaction` registers one undo step, verified — so one
`undo` does reverse one tool call today. But the granularity is Aseprite's, not
something this bridge defines or can hold it to, so neither the tools nor the
README promise the 1:1 mapping; `get_undo_depth` is what a caller checks instead.

### Frame duration crosses the bridge in milliseconds, and the `+ 0.5` is not a typo

`set_frame_duration` takes milliseconds and `list_frames` reports `durationMs`;
`Frame.duration` is seconds. `ms_to_duration`/`duration_to_ms` are the only
place the two units meet.

**Why milliseconds:** frame timing is reasoned about in ms or fps (12fps ≈
83ms), and seconds would have a model writing `0.0833` for a common case.

**Why the nudge:** `ms_to_duration` is `(ms + 0.5) / 1000`, not `ms / 1000`.
Aseprite keeps the duration as a 16-bit millisecond count derived from the
seconds it is handed, and that derivation truncates — plain `ms / 1000` loses a
millisecond on **741 of the 65535 valid inputs**, starting at 1001ms. Half a
millisecond of headroom lands the value inside the target integer; it
round-trips all 65535 exactly and never overshoots, at either clamp boundary.
Verified by sweeping the full range against a live editor.

`tests/lua/duration_test.lua` pins both directions and asserts that the naive
expression *would* fail, so the sweep cannot quietly become a test of nothing.
The two functions are deliberately **not** inverses on their own —
`duration_to_ms(ms_to_duration(1))` is 2 — because the editor's truncation is
the step between them; the test models it explicitly.

The range is `1..65535` ms, checked in the handler because Aseprite clamps
silently at both ends: 0 would otherwise be reported as set while the frame
holds 1ms.

### `add_frame` absorbs an asymmetry between Aseprite's two insert calls

`Sprite:newFrame(n)` inserts the copy at **n + 1**. `Sprite:newEmptyFrame(n)`
inserts the blank at **n**. So one `add_frame(after = N)` is `newFrame(N)` for
the duplicate and `newEmptyFrame(N + 1)` for the empty; both land at `N + 1`
and become active. Verified — the notes in the change that added these have the
sweep, since duplicate content makes a cel map useless for telling the two
apart.

**Neither return value names the new frame.** `newFrame` hands back the
*source* `FrameObj` — `frameNumber` reads `N`, and writing through it modifies
frame `N`. The position is computed as `after + 1` instead.

The range check on `after` is load-bearing, not defensive: `newFrame(99)` on a
5-frame sprite does not raise, it pads the sprite out to 100 frames.

### `delete_frame`'s only-frame guard has to be ours

`Sprite:deleteFrame` on a one-frame sprite returns normally and changes
nothing — no error, no deletion. Without the `#spr.frames == 1` check the tool
would report `deleted frame 1` of a frame that is still there.

Frame numbers after the deleted one shift down, and `app.activeFrame` follows
the frame it was showing rather than its number, so there is nothing to
compensate for. That renumbering is documented rather than worked around: it is
how Aseprite's own frame list behaves, and it is why frame numbers are read
fresh every call and never cached — the same contract `list_layers`'
`stackIndex` has.

### The plugin script must not return a value inside Aseprite

`main.lua` ends with a bare `return` in the `if WebSocket` branch, and only
returns its export table when `WebSocket` is absent.

**Why:** Aseprite tears down the script's Lua context when an extension script
returns a value. The socket still connects and even retries, but the
`onreceive` closure has been collected — so no handshake and no command reply
is ever sent, and every tool call times out after 10s. This is verified against
a live editor. **Do not tidy that bare `return` away.**

The same split is what lets the Lua tests `dofile` the plugin in a bare
interpreter with no side effects.

### The port is not negotiated — both ends read `ASEPRITE_MCP_PORT`

**Server:** `resolve_port()` raises on anything that is not 1–65535, and
`__main__.main()` exits 2 with one line. A bad value must fail loudly, because
the alternative presents as "Aseprite not connected" with no clue why.

**Plugin:** the same variable, but a bad value warns to **View → Console** and
falls back to 9876. Raising there would abort loading the whole extension, and
the server refuses to start on that value anyway.

Aseprite reads its environment at launch, so the variable must be set _before_
Aseprite starts.

### Failures are MCP errors, not error-shaped text

`_error()` sets `isError=True` so a client can tell failure from success without
parsing prose. `call_tool` returns the `CallToolResult` through unchanged —
that is what keeps `isError` under our control instead of the SDK's exception
wrapper.

The message strings are load-bearing: `docs/TROUBLESHOOTING.md` quotes them
verbatim. Change one, change the doc.

### Validation messages raise through `fail`, not `error`

Every deliberate validation message in `main.lua` calls `fail(msg)`, a one-line
helper that is `error(msg, 0)`.

**Why:** Lua's `error()` prepends `<file>:<line>: ` at the default level, so
`error("no active sprite")` reached the caller as
`…/extensions/aseprite-mcp/main.lua:405: no active sprite`. That breaks the
verbatim match `docs/TROUBLESHOOTING.md`'s headings depend on, and it ships an
absolute local path across the bridge into the model's context.

The level is `0`, not `2`: there is no useful position to point at for a message
whose whole content is already the explanation.

**The split is the point.** `fail` is for messages a caller is meant to read. A
genuine Lua fault — indexing a nil, a bad `app` call — still raises through
plain `error()` and keeps its file and line, which is what makes a real bug
locatable. Do not "simplify" `fail` back into `error`, and do not route
unexpected faults through it.

`tests/lua/error_test.lua` guards both halves.

### One Aseprite at a time

A second connection is closed with code 1008. The first keeps the bridge.
On disconnect, every pending future is cancelled so no caller hangs.

### Dependency bounds are deliberate

`mcp>=1.0,<2` — 2.0 removed `Server.list_tools`, so an unbounded install fails
at import. `websockets>=13,<17` — 13 is the first release shipping
`websockets.asyncio.server`. Read the comments in `pyproject.toml` before
widening either.

### `plugin/` is the only source of truth

Aseprite unpacks the bundle into a per-user extensions directory. Editing that
copy is how the two versions drifted apart the first time. Always edit
`plugin/main.lua` and reinstall.

## Build and install

```bash
make install          # Poetry venv in ./.venv with dev extras
make build            # → dist/aseprite-mcp.aseprite-extension
make install-plugin   # build + install into Aseprite's extensions dir
```

Every Python target runs through `poetry run` in a project-local `.venv` —
the Makefile exports `POETRY_VIRTUALENVS_IN_PROJECT=true` so the global
interpreter and Poetry's shared cache are never touched. Needs Poetry 2.x,
which reads the PEP 621 `[project]` table as-is; do not add `[tool.poetry]`
sections to `pyproject.toml`. `make` on its own lists every target.

Restart Aseprite after either — extensions load only at startup.
`ASEPRITE_EXTENSIONS_DIR` overrides the install destination.

## Running

```bash
make run                     # or, inside the venv: aseprite-mcp / python -m aseprite_mcp
```

It logs to stderr and then waits on stdin. Started by hand it exits as soon as
stdin closes — that is correct; it speaks MCP over stdio and belongs under an
MCP client.

```bash
claude mcp add aseprite -- uvx aseprite-mcp   # Claude Code
codex mcp add aseprite -- uvx aseprite-mcp    # Codex
```

Any MCP client works the same way: register `uvx aseprite-mcp` as a stdio
server.

Either end can start first. The plugin retries until the server is up and
reconnects on its own if the server restarts.

## Tests

Both suites are fast and neither needs Aseprite running. Both must pass.

```bash
make test        # both suites
make test-py     # server: dispatch, timeout, disconnect, port, contracts
make test-lua    # plugin: JSON decode, parse_pixels, color modes, shapes, durations
```

Underneath they are `poetry run pytest` and `lua tests/lua/run.lua`.

The Lua runner needs a **Lua 5.4** interpreter on `PATH` (`winget install
DEVCOM.Lua` / `brew install lua` / `apt install lua5.4`). No LuaRocks, no
busted — dependency-free on purpose. It exits non-zero on failure.

### Contract tests

Two tests in `test_server.py` guard the contract rather than behaviour:

- `test_list_tools_matches_registry` — the registered tool set is exactly the
  documented thirty.
- `test_every_tool_has_a_plugin_handler` — greps `handlers.<name> =` out of
  `plugin/main.lua` and asserts every registered tool has one. Add a tool
  without a handler and this fails here instead of Aseprite answering
  `unknown tool` at runtime.

### What is deliberately untested

Anything touching `app`, `Sprite`, `Image`, or the canvas needs a real editor
and is out of scope. Before a release, verify by hand: `create_sprite` →
`draw_pixels_batch` → `export_png` produces the file you expect.

A Lua test file is any `tests/lua/*_test.lua` returning a table of
name → function. `harness.lua` gives you `eq`, `is_true`, `throws`, and
`plugin()`.

## Versions

Three strings have to agree. `make check-versions` compares them and exits
non-zero on a mismatch, but nothing runs it for you. Bump together:

- `version` in `pyproject.toml`
- `version` in `plugin/package.json`
- `PLUGIN_VER` in `plugin/main.lua`

## Spec-driven workflow

Larger changes go through `sugar/`: an idea one-pager in `sugar/ideas/`, a
change directory (proposal, design, delta specs, `tasks.md`) in
`sugar/changes/<name>/`, archived to `sugar/changes/archive/<date>-<name>/`
once merged, with its delta specs folded into `sugar/specs/<capability>/spec.md`.

The steps are defined in `.claude/skills/sf-*/SKILL.md` (`sf-idea`, `sf-plan`,
`sf-build`, `sf-review`, `sf-ship`, `sf-archive`, plus `sf-parallel` and
`sf-converge`). Claude Code runs them as `/sf-*` commands; any other agent can
read the relevant `SKILL.md` and follow it as written. When a `tasks.md` is
being executed, mark each checkbox `[x]` as its task lands.

## Git flow

1. **`main` is the only long-lived branch.** Always in a runnable state (green
   `make test`). No direct pushes — every change goes through a PR.
2. **Branch names:** `<prefix>/<scope>/<slug>` with `<prefix>` one of `feat/`,
   `fix/`, `refactor/`, `docs/`, `test/`, `chore/`. `<scope>` matches the part
   of the tree the change lands in — `server` (`src/aseprite_mcp/`), `plugin`
   (`plugin/`), `scripts`, `docs`, `tests`, or `sugar` where applicable.
   Examples: `feat/plugin/add-flood-fill`, `fix/server/port-resolve`,
   `docs/docs/troubleshooting-reconnect`.
3. **Commit and PR title convention:** Conventional Commits with scope —
   `<type>(<scope>): <subject>`. Types match branch prefixes (`feat`, `fix`,
   `refactor`, `docs`, `test`, `chore`). Scope is `server`, `plugin`, `scripts`,
   `docs`, or `tests`. A change spanning both halves of a tool (see "Adding a
   tool means editing **both** files" above) uses both, comma-joined:
   `feat(server,plugin): add flood_fill tool`.
4. **Update a topic branch against `main` by rebase, never merge.**
   `git rebase main`; push with `--force-with-lease` (never plain `--force`).
   Keeps topic branches linear and PR diffs clean.
5. **Squash-merge only** via GitHub PR. The squash commit follows the
   Conventional Commit format. Delete the branch after merge.
6. **Before opening a PR that adds or changes a tool,** `make test` must
   pass locally, and if the change bumps a version, `make check-versions` must
   too.

## Debugging

**Aseprite side:** **View → Console**. The plugin prints
`[MCP] Connecting to ws://127.0.0.1:<port> …`, then `[MCP] Connected.`, then
`[MCP] RX: <first 200 chars>` per command.

**Server side:** stderr. A healthy connection logs two lines:

```
[INFO] Aseprite connected from ('127.0.0.1', 57859)
[INFO] Handshake: Aseprite 1.3.7, plugin protocol 0.6.0
```

A connection with **no** `Handshake:` line after it is the signature of a stale
plugin — the socket is up but the `onreceive` closure is gone, so every call
burns the full 10s timeout. Reinstall and restart Aseprite.

## Style

Match the file you are in. Python is typed and uses
`from __future__ import annotations`; Lua is `local`-scoped with aligned comment
banners. Comments explain the non-obvious constraint, not the line beneath them.
