# improve-tool-api

**Source:** none — the scope was fixed by the "Out of scope" section of
`sugar/changes/prepare-oss-release/proposal.md`, then revised during this
planning session after the reconnect root cause turned out to differ from what
that document assumed. No `sugar/ideas/` one-pager exists.
**Created:** 2026-07-29
**Capabilities:** mcp-server, aseprite-plugin, distribution

## Why

`v0.1.0` is publishable but not yet honest. `create_sprite` advertises a `mode`
parameter accepting RGB, Grayscale, or Indexed, and the plugin hardcodes
`ColorMode.RGB` — a schema that lies to the model. `get_sprite_info` is
implemented in the plugin but registered nowhere, so the model cannot read the
canvas it is drawing into. The handshake reports a constant `"1.3"` as the
Aseprite version, so server logs misreport whatever the user is actually
running. Failures come back as ordinary success text, so a model has no
structured signal that a call failed. And the bridge still dies whenever the
MCP client restarts, which the README currently instructs users to work around
by restarting Aseprite.

## What

Repair the bridge's one real defect, then make the tool surface tell the truth.
The reconnect fix is far smaller than previously believed: Aseprite's WebSocket
already retries on its own, so the bridge only needs to stop discarding its
handle. Alongside that, honour `mode`, register `get_sprite_info`, report the
real Aseprite version, surface failures as MCP errors, make the port
configurable at both ends, and migrate off the deprecated `websockets` API that
`v0.1.0` pinned around.

## Impact

- **Adds:** `get_sprite_info` as a seventh registered tool; an
  `ASEPRITE_MCP_PORT` environment variable honoured by both the server and the
  plugin; structured MCP error results for failed calls.
- **Changes:** the plugin retains its WebSocket handle across a close so the
  existing auto-reconnect can complete a handshake; `create_sprite` honours the
  `mode` it already advertises; the handshake sends `app.version` instead of the
  hardcoded `ASE_VER = "1.3"`; the server moves to `websockets.asyncio.server`
  and the `<16` pin is relaxed; the README drops the restart-Aseprite workaround
  and the not-configurable port note.
- **Removes:** the `ASE_VER` constant; the "Recovering automatically is not
  implemented yet" troubleshooting guidance, which becomes false.
- **Out of scope:** reading pixel data back out of the canvas (a genuinely
  useful capability, but a larger design question about payload size and
  encoding); animation, frames, and timeline tools; selection and transform
  tools; palette manipulation; supporting more than one connected Aseprite;
  authenticating the WebSocket.

## Open questions

- `sugar/specs/` does not exist yet because `prepare-oss-release` has not been
  archived. The MODIFIED requirements in this change's delta specs reference
  requirement names introduced by that change, so `/sf-archive
  prepare-oss-release` must run before this change is archived, or those names
  will not resolve.
- Whether Aseprite's Lua API exposes the running version as `app.version` and
  what type it returns is unverified; task 2.3 confirms it against a live editor
  before the value is trusted in the handshake.
- Whether the plugin can read an environment variable at all is unverified.
  Aseprite's Lua sandbox may not expose `os.getenv`; task 3.1 checks this first
  and falls back to a documented constant in `package.json` if it cannot.
- Relaxing the `websockets` upper bound assumes the modern API is stable across
  the next major. The bound is widened rather than removed until that is
  observed.
