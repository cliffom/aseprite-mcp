# prepare-oss-release

**Source:** none — planned directly from an inline code review on 2026-07-29. No
`sugar/ideas/` one-pager exists; the findings below were verified against the
working tree rather than derived from a written pitch.
**Created:** 2026-07-29
**Capabilities:** mcp-server, aseprite-plugin, distribution

## Why

The project works — a Python MCP server bridges Claude to Aseprite over a
localhost WebSocket, and it successfully drew and exported a 32×32 sprite in
four batched tool calls. But it is not publishable. `git ls-tree -r HEAD` lists
exactly one file, `test_server.py`, and that file has been deleted; every line
of working source is untracked. Pushing today would publish an empty repository.
There is no LICENSE, so even a complete push would leave the code legally
unusable by anyone. The test suite cannot be collected because `pytest_asyncio`
is imported but never declared, and it would fail anyway: it asserts a five-tool
registry against a server that registers six.

## What

Make the repository something a stranger can clone, install, and contribute to.
This change commits the existing source under an MIT license, repairs the test
suite, adds Lua-side tests behind a newly installed Lua 5.4 interpreter, pins
the dependency that is about to break, packages the server so `uvx aseprite-mcp`
works with no clone at all, and ships the plugin as a double-clickable
`.aseprite-extension` bundle instead of manual file copying.

## Impact

- **Adds:** MIT LICENSE; `.gitignore`; README and CONTRIBUTING; `pyproject.toml`
  with an `aseprite-mcp` console script; a zero-dependency Lua test runner and
  its first tests; a build script producing `dist/aseprite-mcp.aseprite-extension`.
- **Changes:** `server/server.py` moves to `src/aseprite_mcp/` so it is
  importable and installable; `plugin/main.lua` gains an export table and only
  auto-connects inside Aseprite, so it can be loaded by tests; the pixel-entry
  parser is extracted from `handlers.draw_pixels_batch` and now reports how many
  entries it skipped; `requirements.txt` gains an upper bound on `websockets`.
- **Removes:** the stale deleted `test_server.py` at the repo root; the
  hand-maintained second copy of `main.lua` under `AppData`, which is replaced by
  a build-and-install script driven from `plugin/`.
- **Out of scope:** plugin auto-reconnect after the MCP server restarts; the
  `create_sprite` `mode` parameter that the Lua handler ignores; registering the
  orphaned `get_sprite_info` handler; returning MCP errors instead of success
  text when Aseprite is disconnected; the hardcoded `ASE_VER = "1.3"` handshake
  constant that misreports the Aseprite version in server logs; migrating off the
  deprecated `websockets.server.WebSocketServerProtocol` API. All of these are
  planned as a second change, `improve-tool-api`.

## Open questions

- Whether Aseprite's extension loader permits `require` of a sibling Lua file is
  unverified. The design avoids depending on it (see design.md, Decision 2), so
  this only matters if a future change wants real modules.
- Restructuring into `src/aseprite_mcp/` will invalidate the MCP client config
  currently pointing at `server/server.py`. Task 7.1 re-verifies a live tool call
  after the move; the user must update their local client config once.
- `PLUGIN_VER` in `main.lua`, `version` in `plugin/package.json`, and the
  `pyproject.toml` version are three independent strings. Task 7.2 checks they
  agree, but nothing enforces it automatically yet.
