# add-file-and-sprite-tools

**Source:** none — scope was set in conversation as "Tier 7 — File & sprite
lifecycle" from a longer tier survey. No `sugar/ideas/` one-pager exists.
**Created:** 2026-07-30
**Capabilities:** mcp-server, aseprite-plugin, distribution

## Why

Every tool the bridge has today assumes exactly one sprite: whichever one
`create_sprite` last made active. There is no way to open an existing
`.aseprite` file or image and edit it, no way to save the layered, multi-frame
result of `add-animation-tools`' new frame tools back to disk in a format that
preserves any of that structure, and no way to work with more than one open
sprite at a time even though Aseprite itself supports it. The bridge can
create art from nothing and export a flat PNG of it, and that is the entire
lifecycle.

Alongside that gap, `export_png` has a live bug. It calls `spr:saveCopyAs`,
which `add-canvas-readback`'s probe already proved writes `<name>1.png`,
`<name>2.png`, … on a multi-frame sprite — never the path it was given.
`get_canvas_image` was rewritten around that exact finding at the time;
`export_png` was not, because every sprite was still single-frame. It was
latent then. `add-animation-tools` just shipped multi-frame sprites, so it is
reachable now, and it sits directly in this change's scope.

## What

`open_file`, `save_sprite`, `list_sprites`, `set_active_sprite`, and
`close_sprite` give the bridge a real multi-sprite lifecycle. A minimal
`export_spritesheet` covers the one export shape the bridge cannot currently
produce at all. `export_png` is fixed to use the same composite-and-save
technique `get_canvas_image` already proved, and gains an optional `frame`
parameter now that "the sprite" can mean more than one frame.

## Impact

- **Adds:** `open_file`, `save_sprite`, `list_sprites`, `set_active_sprite`,
  `close_sprite`, `export_spritesheet` as six registered tools, taking the
  surface from twenty-four to thirty.
- **Changes:** `export_png` no longer calls `spr:saveCopyAs`; it composites
  the active (or a specified) frame with `Image(sprite, frame):saveAs(path)`,
  the same approach `get_canvas_image` uses, and gains an optional `frame`
  parameter. Every other existing tool is unaffected — they all already
  operate on `app.activeSprite`/`app.activeLayer`/`app.activeFrame`, and
  `set_active_sprite` supplies the only missing piece, the same way
  `set_active_frame` did for frames.
- **Removes:** nothing.
- **Out of scope:** full `ExportSpriteSheet` parameter passthrough (layout
  type beyond a basic grid, padding, trim, tag/layer filtering, a JSON data
  file) — decided in conversation in favour of a minimal wrapper; multi-sprite
  concurrent editing beyond one active sprite at a time (there is still one
  `app.activeSprite`, `set_active_sprite` only changes which open sprite that
  is); import formats beyond whatever `app.open` itself supports; any
  autosave or crash-recovery behaviour.

## Open questions

- Whether `Sprite:saveAs` infers its format from the path's extension, what
  extensions it accepts, and what happens when no path is given and the
  sprite has never been saved (`Sprite.filename` empty) is unverified. Task
  1.1 checks this before `save_sprite` is written against an assumption.
- Whether `app.open(filename)` raises, returns `nil`, or leaves
  `app.activeSprite` unchanged on a nonexistent path or unsupported format is
  unverified. Task 1.2 checks this.
- Whether `Sprite:close()` on a modified sprite raises, silently discards, or
  actually opens a UI confirmation dialog — the risk this change's close-safety
  decision exists to avoid — is unverified even for the case this change
  guards against with `force`. Task 1.3 checks the behaviour on an
  **unmodified** sprite, since the modified-sprite path is refused before
  `Sprite:close()` is ever called except when `force` is set, and confirms
  what `force=true` actually triggers.
- The exact `app.command.ExportSpriteSheet` parameter names and whether `type`
  takes a plain string or a `SpriteSheetType` enum value (the way
  `create_sprite` needs `ColorMode[mode]`, not a string, while `useTool`
  accepts a bare tool-id string) is unverified. Task 1.4 checks this against a
  live editor before `export_spritesheet`'s schema is finalised.
- `sugar/specs/` still does not exist — none of the prior three changes have
  been archived. This change's delta specs are ADDED-only, including the
  `export_png` fix, which is written as a corrected `ADDED` requirement rather
  than a `MODIFIED` one because there is no archived spec yet to modify.
