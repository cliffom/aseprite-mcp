## ADDED Requirements

### Requirement: Handlers may return structured results

The plugin's dispatch MUST transmit a handler's table return value as an encoded
JSON structure rather than flattening it to a string, so that read tools can
report fields instead of prose.

#### Scenario: Handler returns a table

- **WHEN** a handler returns a Lua table
- **THEN** the reply's `result` carries the table's fields as a JSON structure

#### Scenario: Handler returns a string

- **WHEN** a handler returns a string, as every write tool does
- **THEN** the reply's `result` is that string unchanged, so existing tools keep
  their current output

#### Scenario: Structure with no fields

- **WHEN** a handler returns a table that has no keys
- **THEN** it is encoded as an empty object rather than an empty array

### Requirement: Commands are decoded by the editor's JSON parser

The plugin MUST decode incoming commands with Aseprite's native `json`
namespace, so that parameter values are no longer restricted to the flat
key/value shapes a pattern matcher can recognise.

#### Scenario: Nested parameter value

- **WHEN** a command arrives whose `params` contains a nested object or array
- **THEN** the decoded parameters preserve that structure

#### Scenario: Existing flat parameters are unaffected

- **WHEN** a command arrives with the scalar and delimited-string parameters the
  current tools use
- **THEN** the handlers receive the same values they received before the
  migration

#### Scenario: Malformed JSON arrives

- **WHEN** the incoming text is not valid JSON
- **THEN** the failure is contained, the command is logged and dropped, and the
  plugin remains connected and able to serve the next command

### Requirement: Command validation is separable from parsing

Validation of a decoded command MUST be performed by a pure function that takes
an already-decoded value, so that it remains testable outside the editor where
the `json` namespace does not exist.

#### Scenario: Well-formed command

- **WHEN** validation receives a decoded value carrying a string id, a string
  tool name, and a table of parameters
- **THEN** it returns a command whose id, tool, and parameters match the input

#### Scenario: Required field missing or of the wrong type

- **WHEN** validation receives a decoded value whose id or tool is absent or is
  not a string
- **THEN** it rejects the value rather than producing a command with a missing
  or non-string field

#### Scenario: Parameters absent

- **WHEN** validation receives a decoded value with no parameters
- **THEN** it returns a command with an empty parameter table, not a nil one

### Requirement: The composited canvas can be read as an image

The plugin MUST be able to write the active sprite's composited appearance to a
caller-supplied path, so that the canvas can be returned to the model as an
image rather than described in text.

#### Scenario: Canvas written on request

- **WHEN** the canvas image tool is invoked with a destination path and a sprite
  is open
- **THEN** a PNG of the composited sprite exists at that path and the reply
  reports the dimensions written

#### Scenario: No sprite open

- **WHEN** the canvas image tool is invoked with nothing open
- **THEN** the call fails with the same `no active sprite` error the other tools
  raise

### Requirement: Sprite information is reported as structured fields

`get_sprite_info` MUST report the sprite's colour mode, frame count, layer
count, active layer, active frame, and palette size as separate fields, rather
than a single line of text describing only dimensions and layer count.

#### Scenario: Information requested

- **WHEN** `get_sprite_info` is called with a sprite open
- **THEN** the result carries the sprite's dimensions, colour mode, frame count,
  layer count, active layer, active frame, and palette size as distinct fields

### Requirement: Layers can be enumerated

The plugin MUST report every layer of the active sprite with the attributes that
determine where a drawing operation lands and whether its result is visible.

#### Scenario: Layers listed

- **WHEN** `list_layers` is called with a sprite open
- **THEN** each layer is reported with its name, stack position, opacity, blend
  mode, visibility, editability, and whether it holds a cel at the active frame

#### Scenario: Hidden layer

- **WHEN** a layer has been hidden in the editor
- **THEN** it still appears in the listing, reported as not visible

### Requirement: Individual pixels can be sampled

The plugin MUST report the colour and alpha of a pixel on the active layer,
resolving the value to a hexadecimal colour regardless of the sprite's colour
mode.

#### Scenario: Painted pixel sampled

- **WHEN** `get_pixel` is called for a coordinate that was previously painted
- **THEN** the reported colour is the colour that was written there

#### Scenario: Indexed sprite sampled

- **WHEN** `get_pixel` is called on an indexed-mode sprite
- **THEN** the palette index is resolved through the sprite's palette and
  reported as a hexadecimal colour, not as a raw index

#### Scenario: No cel at the active layer and frame

- **WHEN** `get_pixel` is called on a layer that holds no cel at the active
  frame
- **THEN** the call fails with an error naming that condition, rather than
  reporting a transparent pixel

#### Scenario: Coordinate outside the sprite

- **WHEN** `get_pixel` is called for a coordinate beyond the sprite bounds
- **THEN** the call fails with an error naming that condition

### Requirement: Regions are read back in a bounded, compressed encoding

The plugin MUST return a rectangular region of the active layer run-length
encoded, and MUST refuse regions larger than a documented pixel limit so that a
read cannot exhaust the call timeout.

#### Scenario: Flat region read

- **WHEN** a region covering pixels of a single colour is requested
- **THEN** each row is reported as one run rather than one entry per pixel

#### Scenario: Region exceeds the limit

- **WHEN** a region larger than the documented pixel limit is requested
- **THEN** the call fails with an error stating the requested size and the
  limit, rather than attempting the read

#### Scenario: Region partly outside the sprite

- **WHEN** a region overlaps the sprite bounds only in part
- **THEN** the read is clipped to the sprite and the result describes the area
  actually read

### Requirement: Selection bounds can be read

The plugin MUST report whether the active sprite has a selection and, when it
does, the rectangle that selection occupies.

#### Scenario: Selection present

- **WHEN** `get_selection` is called while a selection exists
- **THEN** the result reports the selection as non-empty together with its
  origin and dimensions

#### Scenario: Nothing selected

- **WHEN** `get_selection` is called with no active selection
- **THEN** the result reports the selection as empty
