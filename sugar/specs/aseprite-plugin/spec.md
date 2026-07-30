# Aseprite-plugin specification

## Purpose

<Leave a placeholder — the user fills this in after the first archive.>

## Requirements

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

### Requirement: Connection survives a server restart

The plugin MUST retain a usable WebSocket handle across a connection close, so
that when the socket reconnects it can complete a handshake and reply to
commands without the editor being restarted.

#### Scenario: Server restarts while Aseprite stays open

- **WHEN** the MCP server is stopped and started again while Aseprite remains
  running
- **THEN** the plugin completes a handshake on the new connection and subsequent
  tool calls return results instead of timing out

#### Scenario: Handshake accompanies every reconnection

- **WHEN** the plugin's socket reports an OPEN event after an earlier close
- **THEN** a handshake message is transmitted, rather than being silently
  discarded because the handle was cleared

### Requirement: Handshake reports the real Aseprite version

The handshake MUST report the version of the running editor rather than a
compile-time constant, so that server logs describe the user's actual
environment.

#### Scenario: Version is read from the editor

- **WHEN** the plugin sends its handshake
- **THEN** the reported Aseprite version comes from the running application, not
  from a hardcoded string

### Requirement: Colour mode is honoured

`create_sprite` MUST create the sprite in the colour mode requested by the
caller, accepting RGB, Grayscale, and Indexed case-insensitively and defaulting
to RGB when the mode is omitted.

#### Scenario: Grayscale sprite requested

- **WHEN** `create_sprite` is called with a mode of `Grayscale`
- **THEN** the created sprite uses the grayscale colour mode

#### Scenario: Mode omitted

- **WHEN** `create_sprite` is called without a mode
- **THEN** the sprite is created in RGB

#### Scenario: Unrecognised mode rejected

- **WHEN** `create_sprite` is called with a mode that is not one of the accepted
  values
- **THEN** the call fails with an error naming the accepted values, rather than
  silently falling back to RGB

### Requirement: Plugin honours the configured port

The plugin MUST dial the port named by the shared configuration rather than an
unconditional literal, so that both ends of the bridge can be moved together.

#### Scenario: Port overridden

- **WHEN** the bridge is configured to use a port other than the default
- **THEN** the plugin connects to that port

#### Scenario: Port unset

- **WHEN** no port is configured
- **THEN** the plugin connects to the default port 9876

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

### Requirement: Shapes can be drawn without enumerating every pixel

The plugin MUST be able to draw a line, an outlined or filled rectangle, and an
outlined or filled ellipse in a single call, using Aseprite's own tool
rasterisation rather than a Lua-side pixel loop.

#### Scenario: Line drawn between two points

- **WHEN** `draw_line` is called with two coordinate pairs and a colour
- **THEN** a one-pixel-wide line connecting those two points is drawn on the
  active layer's cel

#### Scenario: Rectangle drawn, outline only

- **WHEN** `draw_rect` is called with a bounding box, a colour, and `fill`
  false or omitted
- **THEN** only the rectangle's border is drawn, matching the interactive
  rectangle tool

#### Scenario: Rectangle drawn, filled

- **WHEN** `draw_rect` is called with `fill` true
- **THEN** the entire bounding box is drawn, matching the interactive filled
  rectangle tool

#### Scenario: Ellipse drawn, outline and filled

- **WHEN** `draw_ellipse` is called with a bounding box and a colour, with
  `fill` true or false
- **THEN** an ellipse inscribed in that bounding box is drawn, outlined or
  filled to match the `fill` flag

#### Scenario: Degenerate or invalid dimensions rejected

- **WHEN** `draw_rect` or `draw_ellipse` is called with a width or height less
  than 1
- **THEN** the call fails with an error naming that requirement, rather than
  attempting to draw

### Requirement: The shape-to-tool mapping is a pure, testable function

Selecting which of Aseprite's tool ids a shape and fill flag resolve to MUST be
implemented as a pure function, so the mapping is unit-tested outside the
editor rather than verified only by drawing on a live canvas.

#### Scenario: Fill flag selects the filled tool variant

- **WHEN** the resolver is called with a shape and `fill` true
- **THEN** it returns the filled variant of that shape's tool id

#### Scenario: Unrecognised shape rejected

- **WHEN** the resolver is called with a shape that is not one of the ones this
  change adds
- **THEN** it raises an error naming the unrecognised shape, rather than
  returning a value that would be passed to `useTool` unchecked

### Requirement: Pixels can be erased back to transparency

The plugin MUST be able to write transparency directly into a rectangular
region of the active layer's cel, so that a mistake can be corrected without
overpainting it in an opaque colour.

#### Scenario: Previously painted region erased

- **WHEN** `erase_area` is called over a region that was previously drawn to
- **THEN** every pixel in that region reads back as alpha 0 afterward

#### Scenario: Region with no cel

- **WHEN** `erase_area` is called on a layer that holds no cel at the active
  frame
- **THEN** the call succeeds and reports that nothing was erased, without
  creating a cel

#### Scenario: Region exceeds the read/write pixel limit

- **WHEN** `erase_area` is called with a region larger than the pixel limit
  `get_region` already enforces
- **THEN** the call fails with an error stating the requested size and the
  limit, rather than attempting the write

### Requirement: Undo and redo are reachable as tools

The plugin MUST expose Aseprite's own undo and redo, and the count of pending
undo and redo steps, so that a mistake can be reverted without redrawing.

#### Scenario: Undo reverts the most recent change

- **WHEN** `undo` is called after a drawing operation
- **THEN** the sprite returns to the state it was in before that operation

#### Scenario: Redo restores an undone change

- **WHEN** `redo` is called immediately after `undo`
- **THEN** the sprite returns to the state it was in before the undo

#### Scenario: Undo depth is reported

- **WHEN** `get_undo_depth` is called
- **THEN** the result reports the number of steps available to undo and the
  number available to redo

### Requirement: Frames can be added, as a duplicate or empty

The plugin MUST be able to insert a new frame into the active sprite, either
duplicating an existing frame's cels across every layer or leaving it
completely empty.

#### Scenario: Frame added as a duplicate

- **WHEN** `add_frame` is called with `duplicate` true or omitted
- **THEN** a new frame is inserted whose cels match the reference frame's,
  on every layer that had a cel there

#### Scenario: Frame added empty

- **WHEN** `add_frame` is called with `duplicate` false
- **THEN** a new frame is inserted holding no cels on any layer

#### Scenario: Reference frame out of range

- **WHEN** `add_frame` is called with an `after` value outside the sprite's
  current frame count
- **THEN** the call fails with an error naming the valid range, rather than
  inserting relative to an out-of-range position

### Requirement: Frames can be removed

The plugin MUST be able to delete a frame from the active sprite by number,
and MUST refuse to remove a sprite's only remaining frame.

#### Scenario: Frame deleted

- **WHEN** `delete_frame` is called with a valid frame number and the sprite
  has more than one frame
- **THEN** that frame is removed and every later frame's number decreases by
  one

#### Scenario: Only frame cannot be deleted

- **WHEN** `delete_frame` is called on a sprite that has exactly one frame
- **THEN** the call fails with an error naming that condition, rather than
  leaving the sprite with zero frames

### Requirement: A frame's playback duration can be set and read

The plugin MUST accept and report frame duration in milliseconds, converting
to and from Aseprite's native seconds-based `Frame.duration` at the boundary.

#### Scenario: Duration set

- **WHEN** `set_frame_duration` is called with a frame number and a positive
  millisecond value
- **THEN** that frame's duration is updated, and reading it back through
  `list_frames` reports the same millisecond value

#### Scenario: Non-positive duration rejected

- **WHEN** `set_frame_duration` is called with a duration of zero or less
- **THEN** the call fails with an error naming that requirement, rather than
  setting an unplayable duration

### Requirement: The active frame can be changed

The plugin MUST be able to change which frame is active, so that every
existing draw and read tool — which all operate on the active frame — can
target a frame other than the sprite's first.

#### Scenario: Active frame changed

- **WHEN** `set_active_frame` is called with a valid frame number
- **THEN** that frame becomes the active frame, and a subsequent draw
  operation with no frame parameter of its own lands there

#### Scenario: Frame number out of range

- **WHEN** `set_active_frame` is called with a frame number outside the
  sprite's current frame count
- **THEN** the call fails with an error naming the valid range

### Requirement: Frames can be enumerated

The plugin MUST report every frame of the active sprite with its duration and
whether it is currently active, so a caller can see the animation's structure
without guessing at frame numbers.

#### Scenario: Frames listed

- **WHEN** `list_frames` is called with a sprite open
- **THEN** each frame is reported with its frame number, its duration in
  milliseconds, and whether it is the active frame

#### Scenario: Exactly one frame reports active

- **WHEN** `list_frames` is called
- **THEN** exactly one entry in the result has `isActive` true

### Requirement: Files can be opened into a new active sprite

The plugin MUST be able to open an existing file from disk into a new sprite,
which becomes the active sprite, so a caller can edit existing art rather than
only sprites this bridge created.

#### Scenario: File opened

- **WHEN** `open_file` is called with the path to a file Aseprite can read
- **THEN** that file is loaded into a new sprite which becomes the active
  sprite, and the result reports its dimensions and frame count

#### Scenario: Path missing or unreadable

- **WHEN** `open_file` is called with an empty path, or a path Aseprite
  cannot open
- **THEN** the call fails with an error naming the problem, rather than
  leaving the active sprite in an inconsistent state

### Requirement: The active sprite can be saved to disk

The plugin MUST be able to save the active sprite to a path, preserving
layers, frames, and tags, defaulting to the sprite's existing filename when no
path is given.

#### Scenario: Saved to an explicit path

- **WHEN** `save_sprite` is called with a path
- **THEN** the active sprite is written there in a format that preserves its
  layers and frames

#### Scenario: Saved to the sprite's existing path

- **WHEN** `save_sprite` is called with no path, on a sprite that was opened
  from or previously saved to a file
- **THEN** the sprite is saved back to that same path

#### Scenario: Never-saved sprite with no path given

- **WHEN** `save_sprite` is called with no path, on a sprite that has never
  been saved
- **THEN** the call fails with an error naming that requirement, rather than
  attempting to save to an empty path

### Requirement: Open sprites can be enumerated and switched between

The plugin MUST report every currently open sprite and MUST be able to change
which one is active, so a caller can work with more than one sprite without
losing track of which is which.

#### Scenario: Sprites listed

- **WHEN** `list_sprites` is called
- **THEN** every open sprite is reported with its index, filename,
  dimensions, modified state, and whether it is the active sprite

#### Scenario: Nothing open

- **WHEN** `list_sprites` is called with no sprite open
- **THEN** it returns an empty list rather than an error

#### Scenario: Active sprite changed

- **WHEN** `set_active_sprite` is called with a valid index
- **THEN** that sprite becomes the active sprite, and a subsequent draw or
  read tool operates on it

#### Scenario: Index out of range

- **WHEN** `set_active_sprite` is called with an index outside the current
  open-sprite count
- **THEN** the call fails with an error naming the valid range

### Requirement: A sprite can be closed, refusing to discard unsaved work by default

The plugin MUST refuse to close a modified sprite unless explicitly forced, so
that unsaved work is not silently discarded and so that closing a sprite
cannot trigger an interactive confirmation dialog that would hang the bridge.

#### Scenario: Unmodified sprite closed

- **WHEN** `close_sprite` is called on a sprite with no unsaved changes
- **THEN** it closes without requiring `force`

#### Scenario: Modified sprite refused

- **WHEN** `close_sprite` is called on a sprite with unsaved changes and
  `force` is not set
- **THEN** the call fails with an error naming `save_sprite` or `force` as the
  ways forward, and the sprite remains open

#### Scenario: Modified sprite closed with force

- **WHEN** `close_sprite` is called with `force` true on a sprite with unsaved
  changes
- **THEN** the sprite closes, discarding those changes

### Requirement: A sprite sheet can be exported

The plugin MUST be able to export every frame of the active sprite as a single
image arranged in a grid, so an animation can be shared as one file without a
caller assembling frames by hand.

#### Scenario: Spritesheet exported

- **WHEN** `export_spritesheet` is called with a path
- **THEN** a single image containing every frame is written to that path

#### Scenario: Column count controls the grid

- **WHEN** `export_spritesheet` is called with a `columns` value
- **THEN** the exported grid uses that many columns

### Requirement: The active sprite can be exported to a PNG file, one file per call

`export_png` MUST composite the requested frame with `Image(sprite,
frameNumber):saveAs(path)` rather than `Sprite:saveCopyAs`, and MUST accept an
optional frame number defaulting to the active frame, so that exporting a
multi-frame sprite writes exactly one file at the requested path instead of a
numbered sequence that never includes that path.

#### Scenario: Single-frame sprite exported

- **WHEN** `export_png` is called on a sprite with one frame
- **THEN** a PNG of that frame is written at the requested path, as before

#### Scenario: Multi-frame sprite exports exactly one file

- **WHEN** `export_png` is called on a sprite with more than one frame
- **THEN** exactly one PNG is written, at the requested path, composited from
  the active frame or the frame explicitly requested — not a numbered
  sequence

#### Scenario: An explicit frame is exported

- **WHEN** `export_png` is called with a `frame` parameter
- **THEN** the exported PNG composites that frame rather than the active one

#### Scenario: Frame number out of range

- **WHEN** `export_png` is called with a `frame` value outside the sprite's
  current frame count
- **THEN** the call fails with an error naming the valid range
