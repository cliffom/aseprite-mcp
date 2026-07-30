## ADDED Requirements

### Requirement: The read tools are documented

Documentation MUST describe every read tool's parameters and result shape, so
that the README remains the user-facing reference the code's error strings are
quoted from.

#### Scenario: Tool reference covers the new tools

- **WHEN** a user reads the README's tool reference
- **THEN** the five new read tools appear there with their parameters and the
  shape of what they return

#### Scenario: New error strings are diagnosable

- **WHEN** a user encounters an error raised by a read tool
- **THEN** the troubleshooting section explains that error, quoting it exactly
  as the code emits it

### Requirement: The region encoding is documented

Documentation MUST specify the run-length encoding `get_region` returns and the
pixel limit it enforces, in the same detail the batch drawing encoding already
receives.

#### Scenario: Encoding is specified

- **WHEN** a user reads the region encoding section
- **THEN** it states the row and run delimiters, the run format, and a worked
  example

#### Scenario: Limit is stated

- **WHEN** a user reads the region encoding section
- **THEN** it states the maximum region size and explains that the limit exists
  to bound the call against the response timeout

### Requirement: The reading and drawing views are distinguished

Documentation MUST state that the pixel readers report the active layer while
the canvas image reports the composite, because a user who confuses the two
will read a value that contradicts what they see on screen.

#### Scenario: The distinction is explained

- **WHEN** a user reads the tool reference for the pixel readers
- **THEN** it states that they read the active layer's cel, and points to the
  canvas image tool for the composited view

### Requirement: Project documentation reflects the new tool surface

`CLAUDE.md` MUST record the new tool count, the move to the editor's native JSON
decoder, and the reason the encoder was not migrated with it, so that the
architecture notes do not describe a decoder the code no longer uses.

#### Scenario: Decoder note is current

- **WHEN** a contributor reads the design decisions in `CLAUDE.md`
- **THEN** the note explaining the flat-string batch encoding reflects that
  parameter decoding is now native, and records why the encoder stayed
  hand-rolled
