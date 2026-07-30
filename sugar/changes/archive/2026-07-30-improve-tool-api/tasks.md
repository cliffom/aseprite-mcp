# improve-tool-api — tasks

## 1. Restore the bridge across server restarts

- [x] 1.1 Stop clearing the socket handle on CLOSE in `plugin/main.lua` so the reconnect that already happens can complete a handshake
- [x] 1.2 Verify against a live editor: restart the MCP client with Aseprite left open, and confirm the server logs a `Handshake:` line and a tool call succeeds without restarting Aseprite

## 2. Make the tool surface honest

- [x] 2.1 Add a pure `resolve_color_mode(name)` helper mapping RGB, Grayscale, and Indexed case-insensitively, erroring on anything else, and use it in `create_sprite` instead of the hardcoded `ColorMode.RGB`
- [x] 2.2 Register `get_sprite_info` in the server's `list_tools()` with an empty input schema and a description explaining it lets the model read canvas state
- [x] 2.3 Confirm how the running Aseprite version is exposed to Lua, send that in the handshake, and delete the hardcoded `ASE_VER` constant
- [x] 2.4 Return `types.CallToolResult` with `isError=True` from every `_dispatch` failure path, preserving the existing message text the README quotes

## 3. Make the port configurable

- [x] 3.1 Determine whether Aseprite's Lua sandbox exposes `os.getenv`, and record the result — it decides whether the plugin reads the environment or a constant declared in `plugin/package.json`
- [x] 3.2 Read `ASEPRITE_MCP_PORT` in the server, defaulting to 9876 and failing fast at startup on a non-numeric or out-of-range value
- [x] 3.3 Apply the mechanism chosen in 3.1 so the plugin dials the configured port instead of the literal in `WS_URL`
- [x] 3.4 Verify live that both ends meet on a non-default port

## 4. Migrate off the deprecated websockets API

- [x] 4.1 Move `ws_handler` and `main()` to `websockets.asyncio.server` and drop the deprecated `WebSocketServerProtocol` annotations
- [x] 4.2 Widen the `websockets` bound in `pyproject.toml` and confirm the suite runs clean under `-W error::DeprecationWarning`

## 5. Tests

- [x] 5.1 Extend the registry test to the seven-tool set and confirm the existing server/plugin drift test now covers `get_sprite_info`
- [x] 5.2 Assert `isError` is set on all four dispatch failure paths: no connection, timeout, disconnect, and a plugin `ok=false` reply
- [x] 5.3 Add Python tests for port resolution covering the default, a valid override, and rejection of an invalid value
- [x] 5.4 Add `tests/lua/mode_test.lua` covering `resolve_color_mode` for each accepted spelling, mixed case, omission, and an unknown value
- [x] 5.5 Run `pytest` and `lua tests/lua/run.lua` and confirm both are green

## 6. Documentation

- [x] 6.1 Document `get_sprite_info` and the now-functional `mode` parameter in the README tool reference
- [x] 6.2 Document `ASEPRITE_MCP_PORT` for both ends, including where it belongs in an MCP client configuration block
- [x] 6.3 Rewrite troubleshooting: remove the restart-Aseprite-after-every-server-restart rule and the fixed-port claim, keep the stale-bridge symptoms, and add port mismatch as a cause of "Aseprite not connected"
- [x] 6.4 Bump the version in `pyproject.toml`, `plugin/package.json`, and `PLUGIN_VER` together

## 7. Release verification

- [x] 7.1 Manual pass: the reconnect cycle, Grayscale and Indexed sprite creation, and a non-default port
- [x] 7.2 Rebuild and reinstall the extension bundle and confirm a fresh install connects
- [ ] 7.3 Commit the completed change and tag `v0.2.0`
