# add-animation-tools — tasks

Group 1 gates groups 2 and 3: frame insertion and deletion semantics are
either undocumented or ambiguous in the API reference. Record findings in
`sugar/changes/add-animation-tools/notes/editor-probe.md`, following the
format of the two prior changes' probe notes.

## 1. Probe the editor

- [x] 1.1 Probe `Sprite:newFrame(frameNumber)` and
      `Sprite:newEmptyFrame(frameNumber)` on a multi-layer sprite: confirm the
      new frame's position relative to `frameNumber` (inserted immediately
      after it, or at that position shifting the existing frame back),
      whether `newFrame` copies cels on every layer that had one, whether the
      new frame becomes `app.activeFrame` automatically, and what each call
      returns
- [x] 1.2 Probe `Sprite:deleteFrame` called on a sprite's only remaining
      frame: confirm whether it raises, no-ops, or is otherwise refused, and
      record the exact behaviour when deleting a frame before the active one
      (does `app.activeFrame` shift to compensate, or point at the wrong
      content afterward)
- [x] 1.3 Probe `Frame.duration`: confirm it reads/writes in seconds as
      documented, and check the result of setting it to zero or a negative
      value
- [x] 1.4 Write `notes/editor-probe.md` with the method, raw output, and what
      each finding settles — including the exact `add_frame`/`delete_frame`
      behaviour the handlers will implement

## 2. Plugin: frame management handlers

- [x] 2.1 Add `handlers.add_frame(duplicate, after)`: validate `after` against
      the current frame count (defaulting to the active frame), call
      `Sprite:newFrame` or `Sprite:newEmptyFrame` per 1.1's finding inside
      `app.transaction`, and return `"added frame N (duplicated frame M)"` or
      `"added empty frame N"`
- [x] 2.2 Add `handlers.delete_frame(frame)`: validate the frame number and
      reject deleting the sprite's only frame per 1.2's finding, call
      `Sprite:deleteFrame` inside `app.transaction`, return `"deleted frame
      N"`
- [x] 2.3 Add `handlers.set_frame_duration(frame, duration)`: validate the
      frame number and that `duration` is a positive integer, convert
      milliseconds to seconds, set `Frame.duration`, return `"frame N
      duration set to Xms"`
- [x] 2.4 Add `handlers.set_active_frame(frame)`: validate the frame number,
      set `app.frame = spr.frames[frame]`, return `"active frame set to N"`
- [x] 2.5 Add `handlers.list_frames()` returning one entry per frame with
      `frameNumber`, `durationMs` (converted from seconds), and `isActive`

## 3. Server

- [x] 3.1 Register `add_frame` and `delete_frame`, documenting the
      duplicate/empty flag and the frame-renumbering-on-delete behaviour
- [x] 3.2 Register `set_frame_duration` and `list_frames`, documenting that
      duration is in milliseconds
- [x] 3.3 Register `set_active_frame`, documenting that existing draw and
      read tools operate on whatever frame is active

## 4. Tests

- [x] 4.1 If the millisecond/second conversion involves more than a single
      arithmetic expression (per design.md's test-plan note), add a Lua unit
      test pinning it; otherwise confirm inline and skip a dedicated test
- [x] 4.2 Update `test_list_tools_matches_registry` in `tests/test_server.py`
      to the twenty-four-tool set
- [x] 4.3 Run `pytest` and `lua tests/lua/run.lua`; both must pass, including
      `test_every_tool_has_a_plugin_handler` picking up the five new handlers
      with no code change

## 5. Documentation

- [x] 5.1 Add `add_frame`, `delete_frame`, `set_frame_duration`,
      `set_active_frame`, `list_frames` to the README tool reference with
      their parameters, results, and the millisecond duration convention
- [x] 5.2 Add a README note that existing draw/read tools operate on the
      active frame and `set_active_frame` is how to target another one
- [x] 5.3 Add the new error strings to the README troubleshooting section,
      quoted exactly as the code emits them
- [x] 5.4 Update `CLAUDE.md`: nineteen tools becomes twenty-four, and record
      the millisecond/seconds conversion boundary
- [x] 5.5 Bump the version in `pyproject.toml`, `plugin/package.json`, and
      `PLUGIN_VER` in `plugin/main.lua` together

## 6. Manual verification

- [x] 6.1 Against a live editor: `add_frame` with `duplicate=true` copies the
      previous frame's art on every layer; `add_frame` with `duplicate=false`
      is blank
- [x] 6.2 Against a live editor: `set_active_frame` followed by `draw_pixel`
      lands on the targeted frame, verified by `get_pixel` on both frames
- [x] 6.3 Against a live editor: `delete_frame` renumbers later frames, and
      `list_frames` reflects the new count and durations; `set_frame_duration`
      followed by `list_frames` reports back the same millisecond value
