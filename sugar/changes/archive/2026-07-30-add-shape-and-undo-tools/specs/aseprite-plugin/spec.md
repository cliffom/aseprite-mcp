## ADDED Requirements

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
