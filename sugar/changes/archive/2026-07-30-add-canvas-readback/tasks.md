# add-canvas-readback — tasks

Group 1 gates groups 2 and 3: three design choices below are written against
behaviour the API docs describe but nobody here has observed. Record findings in
`sugar/changes/add-canvas-readback/notes/editor-probe.md`, following the format
of `sugar/changes/improve-tool-api/notes/lua-sandbox-probe.md`.

## 1. Probe the editor

- [x] 1.1 Probe the `json` namespace with `aseprite -b --script`: confirm it exists, record `type()` of a `json.decode` result, whether nested tables and arrays survive, whether `#` and `ipairs` work on decoded arrays, and whether malformed input raises or returns nil
- [x] 1.2 Probe the image paths: whether `Image(sprite)` composites all visible layers, whether `image:resize` accepts a nearest-neighbour method, and whether `saveCopyAs` to a `.png` on a multi-frame sprite writes one file or a numbered sequence
- [x] 1.3 Write `notes/editor-probe.md` with the method, raw output, and what each finding settles — including which `scale` behaviour task 3.1 can implement

## 2. Plugin protocol

- [x] 2.1 Add a pure `normalize_command(obj)` to `plugin/main.lua` that validates a decoded value into `{id, tool, params}` and returns nil when `id` or `tool` is absent or not a string, defaulting absent params to an empty table
- [x] 2.2 Rewrite `json_decode_command` to call `json.decode` under `pcall` and hand the result to `normalize_command`, normalising to a plain table first if 1.1 found the result is not one
- [x] 2.3 Delete `json_decode_params` and drop it from the export table, adding `normalize_command` in its place
- [x] 2.4 Fix `json_encode` so a table with no keys encodes as `{}` rather than `[]`
- [x] 2.5 Change `dispatch` to pass a table result through `json_encode` and keep `tostring` for every other type

## 3. Plugin read handlers

- [x] 3.1 Add `handlers.get_canvas_image`: write the composited sprite to the caller-supplied path, honour `scale` as far as 1.2 allows and reject it otherwise, and return `{path, width, height}`
- [x] 3.2 Rewrite `handlers.get_sprite_info` to return `{width, height, colorMode, frames, layers, activeLayer, activeFrame, paletteSize, filename, isModified}`
- [x] 3.3 Add `handlers.list_layers` returning one entry per layer with `name`, `stackIndex`, `opacity`, `blendMode`, `isVisible`, `isEditable`, `isGroup`, `isBackground`, and `hasCel` for the active frame
- [x] 3.4 Add a pure `resolve_pixel(value, colorMode, palette)` helper that turns a raw `getPixel` value into a hex colour and alpha for RGB, grayscale, and indexed modes
- [x] 3.5 Add `handlers.get_pixel` reading the active cel's image with the `cel.position` offset, erroring on a missing cel and on an out-of-bounds coordinate
- [x] 3.6 Add a pure `encode_region(pixels, width, height)` helper producing the row-major RLE described in design.md, with rows delimited by `|` and runs as `count,RRGGBB` delimited by `;`
- [x] 3.7 Add `handlers.get_region` clipping the request to the sprite bounds, enforcing the 4096-pixel cap before reading, and returning `{x, y, width, height, encoding, rows}`
- [x] 3.8 Add `handlers.get_selection` returning `{isEmpty, x, y, width, height}` from `Sprite.selection`

## 4. Server

- [x] 4.1 Add an `_image(data)` helper in `server.py` returning a `CallToolResult` carrying `types.ImageContent` with base64 PNG data
- [x] 4.2 Add a `get_canvas_image` path in `call_tool` that generates a temp path with `tempfile.mkstemp`, injects it into the params, reads and base64-encodes the file on success, and unlinks it in a `finally` covering error, timeout, and disconnect
- [x] 4.3 Register `get_canvas_image` with a `scale` parameter, describing that it returns the composited sprite as an image
- [x] 4.4 Register `get_pixel` and `get_region`, documenting the RLE result format, the pixel cap, and that both read the active layer rather than the composite
- [x] 4.5 Register `list_layers` and `get_selection`, and update the `get_sprite_info` description to match its new structured result

## 5. Tests

- [x] 5.1 Replace the `json_decode_params` cases in `tests/lua/json_test.lua` with `normalize_command` cases covering a well-formed command, missing id, missing tool, a non-string id, and absent params
- [x] 5.2 Add a `json_encode` case to `tests/lua/json_test.lua` pinning the empty table to `{}`
- [x] 5.3 Add `tests/lua/region_test.lua` covering `encode_region` for a single run, alternating pixels, multiple rows, and a zero-area region
- [x] 5.4 Add `resolve_pixel` cases to the Lua suite for RGB, grayscale, and indexed inputs
- [x] 5.5 Update `test_list_tools_matches_registry` in `tests/test_server.py` to the twelve-tool set
- [x] 5.6 Add a `test_server.py` case asserting a dict result from the plugin reaches the caller as JSON text
- [x] 5.7 Add `test_server.py` cases for `get_canvas_image`: `ImageContent` on success, and the temp file unlinked on success, on plugin error, and on timeout
- [x] 5.8 Run `pytest` and `lua tests/lua/run.lua`; both must pass

## 6. Documentation

- [x] 6.1 Add the five new tools to the README tool reference with parameters and result shapes, and update the `get_sprite_info` entry
- [x] 6.2 Add a README section specifying the region RLE encoding, its delimiters, a worked example, and the 4096-pixel cap with the reason for it
- [x] 6.3 Note in the README tool reference that the pixel readers read the active layer and `get_canvas_image` reads the composite
- [x] 6.4 Add the new error strings to the README troubleshooting section, quoted exactly as the code emits them
- [x] 6.5 Update `CLAUDE.md`: seven tools becomes twelve, the decoder is now native `json.decode`, the encoder stays hand-rolled and the reason why, and the active-layer versus composite split
- [x] 6.6 Bump the version in `pyproject.toml`, `plugin/package.json`, and `PLUGIN_VER` in `plugin/main.lua` together

## 7. Manual verification

- [x] 7.1 Against a live editor: `create_sprite` → `draw_pixels_batch` → `get_canvas_image` returns an image showing the drawing
- [x] 7.2 Against a live editor: `get_pixel` at a painted coordinate returns the colour written; `get_region` over a flat area returns one run per row; `list_layers` reports a hidden layer as not visible; `get_pixel` on an indexed sprite returns a hex colour
