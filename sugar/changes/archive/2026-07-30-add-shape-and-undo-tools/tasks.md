# add-shape-and-undo-tools — tasks

Group 1 gates groups 2 and 3: the shape tools' point geometry and the
undo/redo edge behaviour are documented ambiguously or not at all. Record
findings in `sugar/changes/add-shape-and-undo-tools/notes/editor-probe.md`,
following the format of `sugar/changes/add-canvas-readback/notes/editor-probe.md`.

## 1. Probe the editor

- [x] 1.1 Probe `app.useTool` with `tool="line"`, `"rectangle"`,
      `"filled_rectangle"`, `"ellipse"`, `"filled_ellipse"` on a fresh layer
      with no cel: confirm what `points` must contain (two opposite corners vs.
      something else), whether the `filled_*` tool ids fill with no parameter
      beyond the tool id, whether a cel is auto-created, and what a
      zero-length line (identical start/end point) produces
- [x] 1.2 Probe `app.undo()`, `app.redo()`, and `Sprite.undoHistory`: whether
      `undo`/`redo` raise or silently no-op with nothing to undo/redo, whether
      either requires an active sprite, and the exact field names for pending
      undo/redo step counts
- [x] 1.3 Probe writing alpha-0 pixels via `img:drawPixel` on a background
      layer (`Sprite.backgroundLayer` / `Layer.isBackground`): confirm whether
      the write clamps to opaque, is rejected, or succeeds as transparent
- [x] 1.4 Write `notes/editor-probe.md` with the method, raw output, and what
      each finding settles — including the exact `points` construction each
      shape handler will use

## 2. Plugin: shape and erase handlers

- [x] 2.1 Add a pure `resolve_shape_tool(shape, fill)` to `plugin/main.lua`
      returning the `useTool` tool id for `"rect"`/`"ellipse"` crossed with the
      fill flag, erroring on an unrecognised shape — mirrors
      `resolve_color_mode`
- [x] 2.2 Add `handlers.draw_line(x1, y1, x2, y2, color)`: validate all four
      coordinates and the colour, call `useTool{tool="line", points={...}}`
      inside `app.transaction` per 1.1's finding, return `"drew line from
      x1,y1 to x2,y2"`
- [x] 2.3 Add `handlers.draw_rect(x, y, width, height, color, fill)`: validate
      dimensions (reject width/height < 1) and colour, resolve the tool id via
      `resolve_shape_tool`, call `useTool` with the bounding-box points from
      1.1, return `"drew rect at x,y WxH"`
- [x] 2.4 Add `handlers.draw_ellipse(x, y, width, height, color, fill)`,
      identical structure to `draw_rect` with `resolve_shape_tool("ellipse",
      fill)`, return `"drew ellipse at x,y WxH"`
- [x] 2.5 Add `handlers.erase_area(x, y, width, height)`: validate dimensions,
      enforce the existing `MAX_REGION_PIXELS` cap with the same error message
      shape `get_region` uses, look up the active cel without auto-creating one
      (return `"erased 0 pixels"` if none exists), otherwise write
      `app.pixelColor.rgba(0,0,0,0)` over the clipped region inside
      `app.transaction` and return `"erased N pixels"`

## 3. Plugin: undo handlers

- [x] 3.1 Add `handlers.undo()` calling `app.undo()`, with the "nothing to
      undo" branch task 1.2 determined is needed
- [x] 3.2 Add `handlers.redo()` calling `app.redo()`, symmetric with 3.1
- [x] 3.3 Add `handlers.get_undo_depth()` returning
      `{undoSteps = spr.undoHistory.undoSteps, redoSteps =
      spr.undoHistory.redoSteps}`

## 4. Server

- [x] 4.1 Register `draw_line`, `draw_rect`, `draw_ellipse` with schemas
      stating each tool's coordinate convention (two endpoints vs. a bounding
      box) and, for rect/ellipse, that `fill` chooses outline vs. filled
- [x] 4.2 Register `erase_area`, describing that it writes transparency and is
      subject to the same pixel cap as `get_region`
- [x] 4.3 Register `undo`, `redo`, `get_undo_depth`

## 5. Tests

- [x] 5.1 Add `resolve_shape_tool` cases to the Lua suite: rect+fill,
      rect+no-fill, ellipse+fill, ellipse+no-fill, unrecognised shape errors
- [x] 5.2 Update `test_list_tools_matches_registry` in `tests/test_server.py`
      to the eighteen-tool set
- [x] 5.3 Run `pytest` and `lua tests/lua/run.lua`; both must pass, including
      `test_every_tool_has_a_plugin_handler` picking up the six new handlers
      with no code change

## 6. Documentation

- [x] 6.1 Add `draw_line`, `draw_rect`, `draw_ellipse`, `erase_area`, `undo`,
      `redo`, `get_undo_depth` to the README tool reference with their
      parameters, results, and coordinate conventions
- [x] 6.2 Add the new error strings to the README troubleshooting section,
      quoted exactly as the code emits them
- [x] 6.3 Update `CLAUDE.md`: twelve tools becomes eighteen, and record why
      `erase_area` writes transparency directly instead of using the `eraser`
      tool
- [x] 6.4 Bump the version in `pyproject.toml`, `plugin/package.json`, and
      `PLUGIN_VER` in `plugin/main.lua` together

## 7. Manual verification

- [x] 7.1 Against a live editor: `draw_rect` with `fill=false` then `fill=true`
      produce an outline and a filled box respectively; `draw_line` and
      `draw_ellipse` produce the expected shapes
- [x] 7.2 Against a live editor: `erase_area` over a previously drawn region
      makes `get_pixel` report alpha 0 there
- [x] 7.3 Against a live editor: `undo` after a draw call reverts it, `redo`
      restores it, and `get_undo_depth` reflects the step counts before and
      after each
