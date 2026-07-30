## ADDED Requirements

### Requirement: Failures are reported as MCP errors

Every failed tool call MUST return a result marked as an error, so that a client
can distinguish failure from success without parsing prose.

#### Scenario: No plugin connected

- **WHEN** a tool is called while no Aseprite plugin is connected
- **THEN** the result is marked as an error and still explains that Aseprite is
  not connected

#### Scenario: Plugin reports a failure

- **WHEN** the plugin replies with `ok=false` and an error message
- **THEN** the result is marked as an error and carries that message

#### Scenario: Plugin does not respond

- **WHEN** the plugin fails to respond within the tool timeout
- **THEN** the result is marked as an error describing the timeout

#### Scenario: Successful calls are unaffected

- **WHEN** a tool call succeeds
- **THEN** the result is not marked as an error and its text is unchanged

### Requirement: Listen port is configurable

The server MUST read its WebSocket listen port from the `ASEPRITE_MCP_PORT`
environment variable, defaulting to 9876, and MUST reject an invalid value at
startup rather than silently falling back.

#### Scenario: Default port

- **WHEN** `ASEPRITE_MCP_PORT` is not set
- **THEN** the server listens on port 9876

#### Scenario: Overridden port

- **WHEN** `ASEPRITE_MCP_PORT` is set to a valid port number
- **THEN** the server listens on that port

#### Scenario: Invalid port rejected

- **WHEN** `ASEPRITE_MCP_PORT` is set to a value that is not a port number
- **THEN** the server exits at startup with a message naming the variable

## MODIFIED Requirements

### Requirement: Tool registry is covered by tests

The test suite MUST assert the registered tool set against the server's actual
registry rather than a hardcoded count. The expected set now includes
`get_sprite_info`, which was implemented in the plugin but previously
unregistered, leaving the model unable to read the canvas it draws into.

#### Scenario: All registered tools are asserted

- **WHEN** the tool-registry test runs against a server registering
  `create_sprite`, `draw_pixel`, `fill_area`, `add_layer`, `export_png`,
  `draw_pixels_batch`, and `get_sprite_info`
- **THEN** the test passes and names every one of those tools

#### Scenario: Suite is collectable from a clean environment

- **WHEN** a contributor installs the declared development dependencies and runs
  `pytest`
- **THEN** the suite collects without import errors and every test passes

### Requirement: Runtime dependencies are bounded

Declared dependencies MUST carry version bounds. The `websockets` ceiling was
introduced to keep a fresh install away from the release that removes
`websockets.server.WebSocketServerProtocol`; with the server migrated to
`websockets.asyncio.server` that specific hazard is gone, so the ceiling widens
while remaining present as a guard against future breaking majors.

#### Scenario: websockets remains bounded

- **WHEN** the package metadata is inspected
- **THEN** the `websockets` requirement still specifies both a lower and an upper
  bound

#### Scenario: Deprecated API is no longer used

- **WHEN** the server source is inspected
- **THEN** it references no symbol from `websockets.server` that emits a
  deprecation warning on the supported range
