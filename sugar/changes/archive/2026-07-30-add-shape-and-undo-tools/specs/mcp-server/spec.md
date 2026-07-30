## ADDED Requirements

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
