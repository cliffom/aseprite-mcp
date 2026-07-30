# Mcp-server specification

## Purpose

<Leave a placeholder — the user fills this in after the first archive.>

## Requirements

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

### Requirement: The canvas is returned to the model as an image

The server MUST return the composited canvas as image content, so that a model
can see what it has drawn instead of reading a description of it.

#### Scenario: Canvas requested

- **WHEN** `get_canvas_image` is called and a sprite is open
- **THEN** the result carries PNG image content, not a textual description of
  the sprite

#### Scenario: Aseprite reports a failure

- **WHEN** the plugin fails to write the canvas
- **THEN** the call returns an error result marked as an error, consistent with
  every other failing tool

### Requirement: Canvas transfer uses a server-owned temporary file

The server MUST generate the destination path for the canvas image itself and
MUST delete that file once the call completes, on every outcome including
failure, so that no caller-supplied path is written and no temporary files
accumulate.

#### Scenario: Path is not caller-supplied

- **WHEN** `get_canvas_image` is called
- **THEN** the destination written by the plugin is a path the server generated,
  and no tool parameter can influence it

#### Scenario: Successful read

- **WHEN** the canvas image has been read and returned
- **THEN** the temporary file no longer exists

#### Scenario: Call fails or times out

- **WHEN** the plugin reports an error, times out, or disconnects mid-call
- **THEN** the temporary file is still removed

### Requirement: Structured results are surfaced to the caller

The server MUST pass a structured result from Aseprite through to the caller as
JSON text rather than discarding its shape.

#### Scenario: Tool returns fields

- **WHEN** a tool's result is a structure rather than a string
- **THEN** the caller receives its fields as JSON text

#### Scenario: Tool returns prose

- **WHEN** a tool's result is a string
- **THEN** the caller receives that string unchanged

### Requirement: Read tools are registered and described

The server MUST register `get_canvas_image`, `get_pixel`, `get_region`,
`list_layers`, and `get_selection` alongside the existing tools, and each
schema MUST describe the parameter and result encodings a caller has to
construct or parse.

#### Scenario: Registered set

- **WHEN** the tool list is requested
- **THEN** it contains the five new read tools in addition to the seven that
  existed before

#### Scenario: Region encoding is described

- **WHEN** a caller reads the `get_region` schema
- **THEN** the description states the run-length encoding of the result and the
  pixel limit the tool enforces

#### Scenario: Every registered tool is served

- **WHEN** the registered tool set is compared against the plugin's handlers
- **THEN** every registered tool has a handler, so no tool can be advertised
  that Aseprite would answer as unknown

### Requirement: Shape and undo tools are registered and described

The server MUST register `draw_line`, `draw_rect`, `draw_ellipse`,
`erase_area`, `undo`, `redo`, and `get_undo_depth` alongside the existing
tools, and each schema MUST describe the coordinate convention it expects,
since the shape tools' geometry (two points vs. a bounding box) differs from
`draw_pixel`'s single point.

#### Scenario: Registered set

- **WHEN** the tool list is requested
- **THEN** it contains the seven tools this change adds, in addition to the
  twelve that existed before

#### Scenario: Bounding-box tools are described consistently

- **WHEN** a caller reads the `draw_rect` or `draw_ellipse` schema
- **THEN** the description states that the coordinates describe a bounding box
  and that `fill` chooses between an outline and a filled shape

#### Scenario: Every registered tool is served

- **WHEN** the registered tool set is compared against the plugin's handlers
- **THEN** every registered tool has a handler, so no tool can be advertised
  that Aseprite would answer as unknown

### Requirement: Animation tools are registered and described

The server MUST register `add_frame`, `delete_frame`, `set_frame_duration`,
`set_active_frame`, and `list_frames` alongside the existing tools, and the
schemas MUST state that frame duration is expressed in milliseconds and that
frame numbers are 1-based and re-read on every call rather than cached.

#### Scenario: Registered set

- **WHEN** the tool list is requested
- **THEN** it contains the five tools this change adds, in addition to the
  nineteen that existed before

#### Scenario: Duration unit is documented

- **WHEN** a caller reads the `set_frame_duration` or `list_frames` schema
- **THEN** the description states the value is in milliseconds, not seconds

#### Scenario: Frame renumbering is documented

- **WHEN** a caller reads the `delete_frame` schema
- **THEN** the description states that later frames' numbers shift down by
  one, so a frame number is not a stable identity across a delete

#### Scenario: Every registered tool is served

- **WHEN** the registered tool set is compared against the plugin's handlers
- **THEN** every registered tool has a handler, so no tool can be advertised
  that Aseprite would answer as unknown

### Requirement: File and sprite lifecycle tools are registered and described

The server MUST register `open_file`, `save_sprite`, `list_sprites`,
`set_active_sprite`, `close_sprite`, and `export_spritesheet` alongside the
existing tools, and MUST update `export_png`'s schema to document its new
`frame` parameter and the corrected one-file-per-call behaviour.

#### Scenario: Registered set

- **WHEN** the tool list is requested
- **THEN** it contains the six tools this change adds, in addition to the
  twenty-four that existed before

#### Scenario: close_sprite's safety default is documented

- **WHEN** a caller reads the `close_sprite` schema
- **THEN** the description states that a modified sprite is refused unless
  `force` is set

#### Scenario: export_png's frame parameter is documented

- **WHEN** a caller reads the `export_png` schema
- **THEN** the description states that `frame` defaults to the active frame
  and that the tool writes exactly one file regardless of frame count

#### Scenario: Every registered tool is served

- **WHEN** the registered tool set is compared against the plugin's handlers
- **THEN** every registered tool has a handler, so no tool can be advertised
  that Aseprite would answer as unknown
