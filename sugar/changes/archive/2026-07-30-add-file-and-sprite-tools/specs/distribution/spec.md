## ADDED Requirements

### Requirement: The file and sprite lifecycle tools are documented

Documentation MUST describe the six new tools' parameters, result shapes, and
error strings in the README tool reference, and MUST update the `export_png`
entry to reflect its fix and new parameter.

#### Scenario: Tool reference covers the new tools

- **WHEN** a user reads the README's tool reference
- **THEN** `open_file`, `save_sprite`, `list_sprites`, `set_active_sprite`,
  `close_sprite`, and `export_spritesheet` appear there with their parameters
  and results

#### Scenario: export_png's entry reflects the fix

- **WHEN** a user reads the README's `export_png` entry
- **THEN** it documents the `frame` parameter and no longer implies the tool
  might write a numbered sequence of files

#### Scenario: New error strings are diagnosable

- **WHEN** a user encounters an error raised by one of the new or changed
  tools
- **THEN** the troubleshooting section explains that error, quoted exactly as
  the code emits it

### Requirement: The multi-sprite workflow is explained

Documentation MUST explain that every tool operates on the active sprite, and
that `set_active_sprite` is how a caller moves that target among more than one
open sprite, matching how the existing frame-targeting section explains
`set_active_frame`.

#### Scenario: Workflow is explained

- **WHEN** a user reads the tool reference section covering file and sprite
  lifecycle
- **THEN** it states that opening a second file does not stop tools from
  working, but redirects them to the newly opened sprite until
  `set_active_sprite` points elsewhere

### Requirement: Project documentation reflects the new tool surface and the export_png fix

`CLAUDE.md` MUST record the new tool count and the corrected reasoning behind
`export_png`'s implementation, replacing any note that still describes
`saveCopyAs` as the export mechanism.

#### Scenario: Tool count and export mechanism are current

- **WHEN** a contributor reads the design decisions in `CLAUDE.md`
- **THEN** the tool count reflects thirty tools, and the `export_png` note
  describes `Image(sprite, frame):saveAs`, matching what `get_canvas_image`
  already documented, rather than `saveCopyAs`
