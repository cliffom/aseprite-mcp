# add-animation-tools

**Source:** none — scope was set in conversation, narrowed from a longer
"Tier 3 — animation" list down to frame management and navigation. Tags and
cel duplication across frames were both raised and explicitly deferred; see
Out of scope. No `sugar/ideas/` one-pager exists.
**Created:** 2026-07-30
**Capabilities:** mcp-server, aseprite-plugin, distribution

## Why

Every tool the bridge has today — `create_sprite` through `get_undo_depth`,
nineteen in total — operates on whatever Aseprite calls the active frame, and
nothing can change which frame that is. The sprite the model draws into is
permanently single-frame in practice: Aseprite is an animation tool, and
animation is the one thing this bridge cannot do, not because drawing on frame
2 is hard, but because there is no way to make frame 2 the active frame, or to
create it, or to tell it apart from frame 1 once it exists.

## What

Five tools that make a sprite's frame axis addressable: `add_frame` (as a
duplicate of an existing frame's content, or empty), `delete_frame`,
`set_frame_duration`, `set_active_frame` — the one that unblocks every
existing draw tool for anything beyond frame 1 — and `list_frames` to read
back what frames exist and how long each holds.

## Impact

- **Adds:** `add_frame`, `delete_frame`, `set_frame_duration`,
  `set_active_frame`, `list_frames` as five registered tools, taking the
  surface from nineteen to twenty-four.
- **Changes:** nothing about the existing nineteen tools — they already read
  `app.activeFrame`/`app.activeLayer` and need no change to work on a
  non-first frame once `set_active_frame` exists to put them there.
- **Removes:** nothing.
- **Out of scope:** tags (`create_tag`/`list_tags`/`delete_tag` — named
  playback ranges with direction and repeat count; a sprite is fully
  animatable without them, so they are a follow-up, not a dependency);
  cel duplication across frames independent of whole-frame duplication
  (`copy_cel` between two frames or scoped to one layer — `add_frame`'s
  duplicate flag covers the common case of "continue from the last frame",
  and the finer-grained version is a separate tool with its own edge cases);
  onion skinning, playback/preview, and any export beyond the existing
  single-frame `export_png`/`get_canvas_image`.

## Open questions

- Whether `Sprite:newFrame(frameNumber)` inserts a new frame immediately after
  `frameNumber` or at position `frameNumber` shifting the existing one back,
  and whether the new frame becomes `app.activeFrame` automatically, is
  unverified — the API reference documents the call but not its exact
  insertion semantics or side effects. Task 1.1 checks this before `add_frame`
  is written against an assumption.
- Whether `Sprite:deleteFrame` on a sprite's last remaining frame raises,
  no-ops, or is otherwise disallowed is unverified — a sprite cannot have zero
  frames, but what Aseprite does when asked to reach that state is not
  documented. Task 1.2 checks this.
- `sugar/specs/` still does not exist — none of the three prior changes have
  been archived. This change's delta specs are ADDED-only for that reason,
  consistent with both changes before it.
