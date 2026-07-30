# add-canvas-readback

**Source:** none — scope was set in conversation from the "Out of scope" list in
`sugar/changes/improve-tool-api/proposal.md`, which deferred "reading pixel data
back out of the canvas" as a larger design question. No `sugar/ideas/`
one-pager exists; the payload-size and encoding questions that deferral named
are answered in this change's `design.md` rather than in a prior document.
**Created:** 2026-07-29
**Capabilities:** mcp-server, aseprite-plugin, distribution

## Why

The bridge is write-only. A model can create a sprite and paint into it, but
nothing it draws ever comes back — `get_sprite_info` returns a single line
(`32x32 layers=3`) and that is the entire read surface. So the model works
blind: it cannot check whether a batch landed where it intended, cannot sample a
colour it already placed, cannot tell which layer is active, and cannot see that
a fill escaped its boundary. Every correction is guesswork layered on guesswork,
and the usual failure mode is overpainting a mistake rather than noticing it.

Two structural limits keep that gap open. Handler results are forced through
`tostring()` in the plugin's `dispatch`, so no tool can return anything but a
line of prose. And the hand-rolled parameter decoder handles flat objects only,
which bounds what any future tool can accept.

## What

Close the feedback loop and remove the two limits behind it.

The plugin gains a composited view of the canvas returned as a real image, plus
five structured read tools: pixel sampling, a bounded region read, layer
listing, selection bounds, and a `get_sprite_info` that reports colour mode,
frame count, and active layer/frame instead of one line of text. Underneath,
command decoding moves to Aseprite's native `json` namespace and `dispatch`
stops flattening results, so handlers can return tables.

## Impact

- **Adds:** `get_canvas_image`, `get_pixel`, `get_region`, `list_layers`,
  `get_selection` as registered tools, taking the surface from seven to twelve;
  a `types.ImageContent` result path in the server so the model receives the
  canvas as an image rather than a description of one; a run-length region
  encoding with a documented pixel cap; a pure `normalize_command` in the plugin.
- **Changes:** `get_sprite_info` returns a structured object rather than
  `WxH layers=N`; `dispatch` passes table results through `json_encode` instead
  of `tostring`; command decoding uses `json.decode`, so params are no longer
  restricted to flat objects.
- **Removes:** `json_decode_params` and the hand-rolled command matcher in
  `json_decode_command`, along with the `json_test.lua` cases that pinned their
  behaviour.
- **Out of scope:** shape primitives via `app.useTool` points arrays; animation,
  frames, and tags; palette read/write; selection *manipulation* (this change
  reads selection bounds, it does not set them); layer mutation beyond the
  existing `add_layer`; undo/redo; `app.command` effects. Migrating the JSON
  *encoder* to the native namespace is also out of scope — see design.md.

## Open questions

- Whether `json.decode` returns a plain Lua table or a userdata-backed proxy
  object is unverified; the API docs say "a Lua table-like object", which is not
  the same claim. Task 1.1 settles it before any handler indexes the result.
- Whether `saveCopyAs` to a `.png` path on a multi-frame sprite writes one file
  or a numbered sequence is unverified, and the answer decides whether
  `get_canvas_image` needs an explicit frame argument. Task 1.2 checks it.
- Whether the canvas image should be upscaled before it reaches the model is
  unresolved. A 32×32 PNG carries very little for a vision encoder, but every
  upscaling route is unproven here (`Image(sprite)` compositing, a
  nearest-neighbour mode on `image:resize`) or costs a new Python dependency.
  Task 1.2 probes the Lua routes; task 3.1 implements whatever the probe
  supports and caps `scale` at 1 if it supports nothing.
- `sugar/specs/` still does not exist, because neither `prepare-oss-release` nor
  `improve-tool-api` has been archived. This change's delta specs are therefore
  ADDED-only. `/sf-archive` must run against those two changes in order before
  this one is archived.
