# add-file-and-sprite-tools — tasks

Group 1 gates groups 2 and 3: file I/O and export-sheet semantics are either
undocumented or ambiguous in the API reference, and one of them
(`export_png`'s fix) reuses a finding already recorded in
`add-canvas-readback`'s probe rather than needing a fresh one. Record new
findings in `sugar/changes/add-file-and-sprite-tools/notes/editor-probe.md`,
following the format of the three prior changes' probe notes.

## 1. Probe the editor

- [x] 1.1 Probe `Sprite:saveAs`: confirm whether the format is inferred from
      the path's extension, which extensions are accepted for a multi-layer,
      multi-frame sprite, and what happens when called with an empty string
      on a sprite whose `Sprite.filename` is also empty
- [x] 1.2 Probe `app.open(filename)` on a nonexistent path and on a path of an
      unsupported format: confirm whether it raises, returns `nil`, or leaves
      `app.activeSprite` unchanged, and confirm it returns the opened `Sprite`
      and sets it active on success
- [x] 1.3 Probe `Sprite:close()` on an unmodified sprite (the modified case is
      refused before this ever runs except when `force` is set): confirm it
      closes without any UI prompt, and separately confirm what happens when
      `force=true` closes a modified sprite — silent discard or still a
      prompt
- [x] 1.4 Probe `app.command.ExportSpriteSheet{ui=false, ...}`: confirm the
      exact parameter names for output path and column count, whether `type`
      takes a plain string or a `SpriteSheetType` enum value, and the minimal
      parameter set that produces one PNG with no JSON data file
- [x] 1.5 Write `notes/editor-probe.md` with the method, raw output, and what
      each finding settles — including the exact `ExportSpriteSheet` call
      `export_spritesheet` will make

## 2. Plugin: sprite lifecycle handlers

- [x] 2.1 Add `handlers.open_file(path)`: validate `path`, call `app.open`
      per 1.2's finding, translate a failure to `could not open <path>:
      <reason>`, return `"opened <path> (WxH, N frames)"`
- [x] 2.2 Add `handlers.save_sprite(path)`: default to `spr.filename` when
      `path` is omitted, reject when both are empty, call `Sprite:saveAs` per
      1.1's finding, return `"saved to <path>"`
- [x] 2.3 Add `handlers.list_sprites()` returning one entry per `app.sprites`
      with `index`, `filename`, `width`, `height`, `isModified`, `isActive`
- [x] 2.4 Add `handlers.set_active_sprite(index)`: validate the index against
      `#app.sprites`, set `app.sprite = app.sprites[index]`, return `"active
      sprite set to <filename>"`
- [x] 2.5 Add `handlers.close_sprite(force)`: check `spr.isModified`, refuse
      with the `save_sprite`/`force` error unless `force` is true, otherwise
      call `Sprite:close()` per 1.3's finding, return `"closed <filename>"`

## 3. Plugin: export handlers

- [x] 3.1 Add `handlers.export_spritesheet(path, columns)`: validate `path`
      and `columns` (reject less than 1), call `app.command.ExportSpriteSheet`
      with `ui=false` and the parameters 1.4 settled, return `"exported
      spritesheet to <path> (WxH per frame, N frames, C columns)"`
- [x] 3.2 Rewrite `handlers.export_png` to composite with `Image(spr,
      frameNumber):saveAs(path)` instead of `spr:saveCopyAs(path)`, add a
      `frame` parameter defaulting to `app.activeFrame.frameNumber` and
      validate it against the sprite's frame count, keep the return value
      (`path`) unchanged

## 4. Server

- [x] 4.1 Register `open_file` and `save_sprite`, documenting `save_sprite`'s
      default-to-existing-filename behaviour and its error when neither a
      path nor an existing filename is available
- [x] 4.2 Register `list_sprites` and `set_active_sprite`, documenting that
      every other tool operates on whichever sprite is active
- [x] 4.3 Register `close_sprite`, documenting the `force` default and why it
      exists
- [x] 4.4 Register `export_spritesheet`, documenting that it is a minimal
      wrapper (one PNG, all frames, `columns` only) rather than the full
      `ExportSpriteSheet` surface
- [x] 4.5 Update the `export_png` schema: document the `frame` parameter and
      remove any wording that implied a possible numbered-sequence output

## 5. Tests

- [x] 5.1 If 1.4 finds `export_spritesheet` needs a string-to-enum resolver
      for `type` (per design.md's precedent from `resolve_shape_tool`), add
      Lua unit test cases for it; otherwise confirm inline and skip a
      dedicated test
- [x] 5.2 Update `test_list_tools_matches_registry` in `tests/test_server.py`
      to the thirty-tool set
- [x] 5.3 Run `pytest` and `lua tests/lua/run.lua`; both must pass, including
      `test_every_tool_has_a_plugin_handler` picking up the six new handlers
      with no code change

## 6. Documentation

- [x] 6.1 Add `open_file`, `save_sprite`, `list_sprites`, `set_active_sprite`,
      `close_sprite`, `export_spritesheet` to the README tool reference with
      their parameters, results, and errors
- [x] 6.2 Update the README's `export_png` entry: document the `frame`
      parameter and remove any language implying a possible numbered-sequence
      output
- [x] 6.3 Add a README note that every tool operates on the active sprite and
      `set_active_sprite` is how to target another one, matching the existing
      frame-targeting note's structure
- [x] 6.4 Add the new error strings to the README troubleshooting section,
      quoted exactly as the code emits them
- [x] 6.5 Update `CLAUDE.md`: twenty-four tools becomes thirty, and replace
      the `export_png`/`saveCopyAs` note with the corrected
      `Image(sprite, frame):saveAs` mechanism
- [x] 6.6 Bump the version in `pyproject.toml`, `plugin/package.json`, and
      `PLUGIN_VER` in `plugin/main.lua` together

## 7. Manual verification

- [x] 7.1 Against a live editor: `open_file` on a real multi-layer
      `.aseprite` file and on a `.png`; `save_sprite` round-trips layers,
      frames, and tags through a close and reopen
- [x] 7.2 Against a live editor: with two sprites open, `list_sprites` reports
      both and `set_active_sprite` correctly redirects `draw_pixel` to the
      chosen one
- [x] 7.3 Against a live editor: `close_sprite` refuses a modified sprite and
      succeeds with `force=true`; confirm no UI dialog appears either way
- [x] 7.4 Against a live editor: `export_spritesheet` produces a grid whose
      cell count matches the frame count; `export_png` with an explicit
      `frame` on a 3+-frame sprite writes exactly one file at the requested
      path — the regression check for the bug this change fixes
