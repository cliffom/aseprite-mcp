## ADDED Requirements

### Requirement: The animation tools are documented

Documentation MUST describe the five new tools' parameters, result shapes,
and error strings in the README tool reference, at the same detail given to
the tools added by `add-canvas-readback` and `add-shape-and-undo-tools`.

#### Scenario: Tool reference covers the new tools

- **WHEN** a user reads the README's tool reference
- **THEN** `add_frame`, `delete_frame`, `set_frame_duration`,
  `set_active_frame`, and `list_frames` appear there with their parameters
  and results

#### Scenario: New error strings are diagnosable

- **WHEN** a user encounters an error raised by one of the new tools
- **THEN** the troubleshooting section explains that error, quoted exactly as
  the code emits it

### Requirement: The frame-targeting workflow is explained

Documentation MUST explain that draw and read tools operate on the active
frame, and that `set_active_frame` is how a caller moves that target, since
this is the behavioural dependency the whole change exists to unblock.

#### Scenario: Workflow is explained

- **WHEN** a user reads the tool reference section covering animation
- **THEN** it states that existing draw and read tools are unaffected by this
  change except that `set_active_frame` now lets them target a frame other
  than the sprite's first

### Requirement: Project documentation reflects the new tool surface

`CLAUDE.md` MUST record the new tool count and the millisecond/seconds
conversion boundary, so the architecture notes describe the shipped contract
rather than Aseprite's native units.

#### Scenario: Tool count and duration unit are current

- **WHEN** a contributor reads the design decisions in `CLAUDE.md`
- **THEN** the tool count reflects twenty-four tools and a note explains that
  frame duration crosses the bridge in milliseconds, converted to Aseprite's
  native seconds internally
