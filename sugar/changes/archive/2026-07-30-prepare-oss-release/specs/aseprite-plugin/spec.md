## ADDED Requirements

### Requirement: Command payload decoding

The plugin's JSON parameter decoder MUST return string values byte-for-byte as
sent by the server, including commas, braces, and escape sequences. Values MUST
NOT be truncated at a delimiter that appears inside a quoted string.

#### Scenario: Batch pixel payload containing commas

- **WHEN** the server sends `{"pixels":"0,0,FF0000;1,0,00FF00"}`
- **THEN** the decoder yields the exact string `0,0,FF0000;1,0,00FF00`

#### Scenario: Windows path containing escaped backslashes

- **WHEN** the server sends a `path` value of `"C:\\out\\a.png"`
- **THEN** the decoder yields `C:\out\a.png`

#### Scenario: Delimiters inside a quoted value

- **WHEN** the server sends `{"name":"Layer, 2}"}`
- **THEN** the decoder yields the layer name `Layer, 2}` rather than stopping at
  the comma or the brace

#### Scenario: Keys following an escaped string value

- **WHEN** the server sends `{"s":"he said \"hi\"","n":7}`
- **THEN** the decoder yields both `s` as `he said "hi"` and `n` as the number `7`

#### Scenario: Scalar values still decode

- **WHEN** the server sends `{"x":5,"y":12,"color":"#FF0000"}`
- **THEN** `x` and `y` are numbers and `color` is the string `#FF0000`

### Requirement: Standalone loadability

`plugin/main.lua` MUST load in a bare Lua 5.4 interpreter without side effects,
and MUST expose its internal functions so they can be exercised by tests. The
WebSocket connection SHALL be initiated only when running inside Aseprite.

#### Scenario: Loading outside Aseprite

- **WHEN** `main.lua` is loaded by a plain Lua interpreter where the `WebSocket`
  global is absent
- **THEN** the file returns a table exposing `json_encode`, `json_decode_params`,
  `json_decode_command`, `parse_pixels`, and `handlers`, and no connection is
  attempted

#### Scenario: Loading inside Aseprite

- **WHEN** `main.lua` is loaded by Aseprite, where the `WebSocket` global exists
- **THEN** the plugin connects to the configured server URL as it does today

### Requirement: Batch pixel parsing reports skipped entries

Parsing of the `x,y,RRGGBB;...` batch encoding MUST be a pure function separate
from canvas mutation, and MUST report how many entries it rejected so that
malformed input is visible to the caller rather than silently discarded.

#### Scenario: All entries well formed

- **WHEN** `parse_pixels` is given `9,3,5C2E1A;22,3,5C2E1A`
- **THEN** it returns two parsed entries and a skipped count of zero

#### Scenario: Some entries malformed

- **WHEN** `parse_pixels` is given an input where one entry has a non-hex colour
- **THEN** the well-formed entries are returned and the skipped count is one

#### Scenario: Empty payload rejected

- **WHEN** `draw_pixels_batch` is invoked with an empty `pixels` string
- **THEN** the handler raises an error stating that `pixels` is required
