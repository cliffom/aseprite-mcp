## ADDED Requirements

### Requirement: The shape and undo tools are documented

Documentation MUST describe the seven new tools' parameters, result shapes,
and error strings in the README tool reference, matching the detail given to
the tools `add-canvas-readback` introduced.

#### Scenario: Tool reference covers the new tools

- **WHEN** a user reads the README's tool reference
- **THEN** `draw_line`, `draw_rect`, `draw_ellipse`, `erase_area`, `undo`,
  `redo`, and `get_undo_depth` appear there with their parameters and results

#### Scenario: New error strings are diagnosable

- **WHEN** a user encounters an error raised by one of the new tools
- **THEN** the troubleshooting section explains that error, quoted exactly as
  the code emits it

### Requirement: The shape coordinate convention is distinguished from `draw_pixel`

Documentation MUST state that the shape tools take two-point or bounding-box
coordinates rather than a single point, because a user who assumes
`draw_pixel`'s single-coordinate convention will pass the wrong number of
arguments.

#### Scenario: Convention is explained

- **WHEN** a user reads the tool reference for `draw_line`, `draw_rect`, or
  `draw_ellipse`
- **THEN** it states the specific coordinate pair or bounding box each tool
  expects

### Requirement: Project documentation reflects the new tool surface

`CLAUDE.md` MUST record the new tool count and the reasoning behind
`erase_area`'s direct pixel write, so the architecture notes describe the
shipped behaviour rather than the interactive eraser tool this change
deliberately did not use.

#### Scenario: Tool count and erase rationale are current

- **WHEN** a contributor reads the design decisions in `CLAUDE.md`
- **THEN** the tool count reflects eighteen tools and a note explains why
  `erase_area` writes transparency directly instead of using `app.useTool`
  with the eraser tool
