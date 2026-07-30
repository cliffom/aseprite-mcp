## ADDED Requirements

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
