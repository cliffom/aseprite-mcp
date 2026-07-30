# prepare-oss-release — tasks

## 1. Repo hygiene and licensing

- [x] 1.1 Add `.gitignore` covering `__pycache__/`, `*.pyc`, `.pytest_cache/`, `dist/`, `build/`, `*.egg-info/`, and `.venv/`
- [x] 1.2 Add `LICENSE` with the MIT text, copyright 2026 giangdv
- [x] 1.3 Commit all untracked source (`server/`, `plugin/`, `tests/`, `requirements.txt`) together with the JSON-parser fix, and record the deletion of the stale root `test_server.py`

## 2. Repair the Python test suite

- [x] 2.1 Install `pytest` and `pytest-asyncio` into the working environment so the suite can be collected
- [x] 2.2 Rewrite `test_list_tools_returns_all_five` to assert the full six-tool registry and rename it to `test_list_tools_matches_registry`
- [x] 2.3 Add a drift test asserting every name from `list_tools()` has a matching `handlers.<name>` entry in `plugin/main.lua`
- [x] 2.4 Run `pytest` and confirm the whole suite passes

## 3. Make the Lua plugin testable

- [x] 3.1 Extract the `x,y,RRGGBB` entry parsing out of `handlers.draw_pixels_batch` into a pure `parse_pixels(data)` returning parsed entries plus a skipped count, and report that count in the handler's result string
- [x] 3.2 Return an export table from `main.lua` and call `connect()` only when the Aseprite `WebSocket` global is present
- [x] 3.3 Add `tests/lua/json_test.lua` covering comma payloads, escaped quotes and backslashes, booleans, numbers, empty strings, and key recovery after an escaped value
- [x] 3.4 Add `tests/lua/pixels_test.lua` covering well-formed, malformed, and out-of-range pixel entries
- [x] 3.5 Add `tests/lua/run.lua`, a zero-dependency runner that executes every `*_test.lua` and exits non-zero on failure, then run it green

## 4. Packaging and dependencies

- [x] 4.1 Move `server/server.py` to `src/aseprite_mcp/server.py` and add `__init__.py` and `__main__.py`
- [x] 4.2 Add `pyproject.toml` using hatchling, declaring the MIT license and an `aseprite-mcp` console script
- [x] 4.3 Declare runtime dependencies with bounds (`websockets>=12,<16`, lower-bounded `mcp`), add `pytest` and `pytest-asyncio` under `[project.optional-dependencies] dev`, and reduce `requirements.txt` to point at the package
- [x] 4.4 Update the tests to import `aseprite_mcp` directly and delete the `sys.path.insert` hack
- [x] 4.5 Verify `uvx --from . aseprite-mcp` starts the server and that `pytest` still passes

## 5. One-click plugin install

- [x] 5.1 Add `scripts/build_extension.py` zipping `plugin/` into `dist/aseprite-mcp.aseprite-extension`
- [x] 5.2 Add `scripts/install_plugin.py` that builds and installs the bundle into the local Aseprite extensions directory for development
- [x] 5.3 Delete the hand-maintained copy under `AppData\Roaming\Aseprite\extensions\aseprite-mcp\` and reinstall via the script to prove the path works

## 6. Documentation

- [x] 6.1 Write the README opening: what the project does, the `output/clawd.png` demo image, and prerequisites
- [x] 6.2 Document server install for both `uvx` and a local clone
- [x] 6.3 Document plugin install from the `.aseprite-extension` bundle, naming the extensions directory on Windows, macOS, and Linux
- [x] 6.4 Add copy-pasteable MCP client configuration for `claude mcp add`, `.mcp.json`, and Claude Desktop
- [x] 6.5 Document all six tools, including the `x,y,RRGGBB;...` batch encoding and why that encoding exists
- [x] 6.6 Add a troubleshooting section covering "Aseprite not connected", port 9876 already bound, and the restart-Aseprite-after-server-restart limitation, plus a security note that the listener is unauthenticated but loopback-only and that `export_png` writes to arbitrary paths
- [x] 6.7 Add `CONTRIBUTING.md` documenting both the `pytest` and `lua tests/lua/run.lua` commands

## 7. Release verification

- [x] 7.1 Reinstall the MCP server from the new package path and confirm a live `create_sprite` round-trip against a running Aseprite
- [x] 7.2 Clone the repository into a temporary directory, follow the README verbatim, and confirm the version strings in `pyproject.toml`, `plugin/package.json`, and `PLUGIN_VER` all agree
- [x] 7.3 Commit the completed change and tag `v0.1.0`
