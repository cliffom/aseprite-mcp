# add-shape-and-undo-tools

**Source:** none — scope was set in conversation, narrowed from a longer tier
list ("Tier 2 — shapes" and "Tier 8 — undo/redo") down to the primitives with
unambiguous `app.useTool` semantics plus the ability to remove pixels, which
`add-canvas-readback` left impossible. No `sugar/ideas/` one-pager exists.
**Created:** 2026-07-30
**Capabilities:** mcp-server, aseprite-plugin, distribution

## Why

`draw_pixels_batch` is the only way to place more than one pixel, and it costs
one triple per pixel: a 40px filled circle is roughly 1,200 characters of
`x,y,RRGGBB` triples where the shape itself is five integers. Every model call
that draws a line, a box, or a filled area pays that tax, and it pays it again
in Lua — a thousand individual `drawPixel` calls where `app.useTool` would do
one stroke.

The bridge is also one-directional in a second sense: nothing can be removed.
`draw_pixels_batch` always writes alpha 255, so a mistake can only be painted
over, never taken back to transparent, and there is no undo — a wrong shape
compounds instead of being correctable. `add-canvas-readback` gave the model
eyes; this gives it a way to fix what it sees without repainting from scratch.

## What

Three shape primitives with unambiguous two-point geometry — line, rectangle,
ellipse, each with outline and filled variants — an `erase_area` tool that
writes transparency directly the way `draw_pixels_batch` writes colour, and
`undo`/`redo`/`get_undo_depth` wired to Aseprite's own undo stack.

## Impact

- **Adds:** `draw_line`, `draw_rect`, `draw_ellipse`, `erase_area`, `undo`,
  `redo`, `get_undo_depth` as six registered tools, taking the surface from
  twelve to eighteen; a pure `resolve_shape_tool(shape, fill)` in the plugin
  mapping a shape and a fill flag to the `useTool` tool id.
- **Changes:** nothing about the existing twelve tools.
- **Removes:** nothing.
- **Out of scope:** polyline, polygon, and curve (all need a `points` array
  whose exact interpretation — open path vs. closed, how control points behave
  for `curve` — is unverified against a live editor, and are a separate probe
  from this change's); gradient fill; a `thickness`/brush-size parameter on any
  shape tool, so every stroke is 1px, matching `draw_pixel`; erasing via the
  `eraser` tool or an `ink` parameter on the shape tools, which behaves
  differently on a background layer than a transparent-layer direct write does
  and is not needed while `erase_area` covers the same need directly;
  selection-based operations of any kind.

## Open questions

- Whether `app.useTool` interprets `points` for `line`, `rectangle`, and
  `ellipse` as two opposite corners — mirroring the interactive click-drag
  gesture — is unverified; the API reference documents the parameter but not
  its geometry per tool. Task 1.1 checks this against a live editor before any
  handler is written against the assumption.
- Whether `filled_rectangle`/`filled_ellipse` fill without any parameter beyond
  the tool id, or need an explicit fill-related option, is unverified. Task 1.1
  checks this alongside the points geometry.
- Whether `app.undo()` / `app.redo()` raise or silently no-op when there is
  nothing to undo/redo, and whether either requires an active sprite, is
  unverified. Task 1.2 checks this; the answer decides whether `undo`/`redo`
  need a "nothing to undo" error path or can return a plain success message
  unconditionally.
- `sugar/specs/` still does not exist — `prepare-oss-release`,
  `improve-tool-api`, and `add-canvas-readback` are all unarchived. This
  change's delta specs are ADDED-only for that reason, same as the change
  before it.
