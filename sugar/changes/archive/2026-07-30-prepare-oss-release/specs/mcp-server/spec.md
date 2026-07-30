## ADDED Requirements

### Requirement: Tool registry is covered by tests

The test suite MUST assert the registered tool set against the server's actual
registry rather than a hardcoded count, so that adding a tool cannot leave a
stale assertion behind.

#### Scenario: All registered tools are asserted

- **WHEN** the tool-registry test runs against a server registering
  `create_sprite`, `draw_pixel`, `fill_area`, `add_layer`, `export_png`, and
  `draw_pixels_batch`
- **THEN** the test passes and names every one of those tools

#### Scenario: Suite is collectable from a clean environment

- **WHEN** a contributor installs the declared development dependencies and runs
  `pytest`
- **THEN** the suite collects without import errors and every test passes

### Requirement: Server and plugin tool names stay in sync

Every tool exposed by the MCP server MUST have a correspondingly named handler in
the Aseprite plugin, verified automatically.

#### Scenario: Every server tool has a plugin handler

- **WHEN** the drift test compares `list_tools()` against the `handlers` table
  defined in `plugin/main.lua`
- **THEN** every server tool name has a matching handler

#### Scenario: A server tool without a handler fails the build

- **WHEN** a tool is registered in the server with no corresponding plugin handler
- **THEN** the drift test fails and names the missing handler

### Requirement: Runtime dependencies are bounded

Declared dependencies MUST carry version bounds that prevent a fresh install from
picking up a release known to remove an API the server relies on.

#### Scenario: websockets is upper-bounded

- **WHEN** the package metadata is inspected
- **THEN** the `websockets` requirement specifies both a lower bound and an upper
  bound excluding the release that removes
  `websockets.server.WebSocketServerProtocol`

### Requirement: Server is installable and launchable as a command

The server MUST be installable as a Python package exposing an `aseprite-mcp`
console entry point, so it can be run without cloning the repository.

#### Scenario: Launch via the console script

- **WHEN** the package is installed and `aseprite-mcp` is executed
- **THEN** the WebSocket listener starts on `127.0.0.1:9876` and the MCP stdio
  transport begins serving

#### Scenario: Package is importable without path manipulation

- **WHEN** the tests import the server module
- **THEN** they do so through the installed package, with no `sys.path` mutation
