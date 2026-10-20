# Distribution specification

## Purpose

<Leave a placeholder — the user fills this in after the first archive.>

## Requirements

### Requirement: Sources are version controlled

All source required to build and run the project MUST be tracked in git, and
generated artefacts MUST be excluded.

#### Scenario: A fresh clone contains the whole project

- **WHEN** the repository is cloned into an empty directory
- **THEN** the server package, the plugin, the tests, the packaging metadata, and
  the documentation are all present

#### Scenario: Generated artefacts are not tracked

- **WHEN** the test suite and the extension build have both been run
- **THEN** `git status` reports no untracked or modified files under
  `__pycache__/`, `.pytest_cache/`, or `dist/`

### Requirement: Licensing is explicit

The repository MUST carry an MIT license file naming the copyright holder, so
that recipients have the right to use, modify, and redistribute the work.

#### Scenario: License is discoverable

- **WHEN** a prospective user opens the repository root
- **THEN** a `LICENSE` file containing the MIT terms is present, and the package
  metadata declares the same license

### Requirement: Plugin installs without manual file copying

The Aseprite plugin MUST be distributable as a single `.aseprite-extension`
bundle built from `plugin/`, which is the only source of truth for its contents.

#### Scenario: Bundle is built from the tracked plugin directory

- **WHEN** the extension build script is run
- **THEN** `dist/aseprite-mcp.aseprite-extension` is produced containing exactly
  `package.json` and `main.lua` from `plugin/`

#### Scenario: Bundle installs into Aseprite

- **WHEN** a user opens the built bundle with Aseprite and restarts the editor
- **THEN** the plugin loads and connects to a running server

#### Scenario: No second hand-maintained copy

- **WHEN** the plugin source is changed
- **THEN** the change reaches Aseprite only by rebuilding and reinstalling the
  bundle, with no separate copy edited by hand

### Requirement: Installation and client configuration are documented

The README MUST give a user a working setup without reading source, covering
server install, plugin install on each supported OS, and MCP client
configuration.

#### Scenario: Zero-clone server install

- **WHEN** a user follows the documented `uvx` instructions
- **THEN** they run the server without cloning the repository

#### Scenario: Plugin install path per platform

- **WHEN** a user on Windows, macOS, or Linux follows the plugin instructions
- **THEN** the documentation identifies the correct extensions location for their
  platform

#### Scenario: Client configuration is copy-pasteable

- **WHEN** a user configures Claude Code or Claude Desktop
- **THEN** the README supplies a configuration snippet requiring no edits beyond
  their own paths

### Requirement: Network exposure and file access are disclosed

Documentation MUST state the security posture of the bridge: that the WebSocket
listener is unauthenticated, that it is bound to loopback, and that `export_png`
writes to arbitrary filesystem paths.

#### Scenario: Security posture is stated

- **WHEN** a user reads the README
- **THEN** they learn the listener accepts any local connection while the server
  runs, is not reachable from other hosts, and that exports are written wherever
  the model specifies

### Requirement: Known limitations are documented

Documentation MUST record behaviours that will otherwise be reported as bugs.
Two entries change: the bridge now survives a server restart without the editor
being restarted, and the port is no longer fixed. The guidance to restart
Aseprite after every server restart becomes false and must be removed rather
than left to mislead.

#### Scenario: Restart workaround is gone

- **WHEN** a user reads the troubleshooting section after this change
- **THEN** it no longer instructs them to restart Aseprite whenever the server
  restarts, and no longer states that automatic recovery is unimplemented

#### Scenario: Stale bridge symptoms are still explained

- **WHEN** a user's tool calls time out
- **THEN** the troubleshooting section still describes what a stale bridge looks
  like and what to check, including the absence of a `Handshake:` line in the
  server log

#### Scenario: Port conflict is discoverable

- **WHEN** the server fails to start because its port is already bound
- **THEN** the troubleshooting section explains the cause and points at
  `ASEPRITE_MCP_PORT` as the remedy rather than describing the port as fixed

### Requirement: Port configuration is documented

Documentation MUST explain how to move the bridge off its default port, state
that both ends must agree, and describe how a mismatch presents.

#### Scenario: Configuring a non-default port

- **WHEN** a user wants to run the bridge on a port other than 9876
- **THEN** the README shows how to set `ASEPRITE_MCP_PORT` for both the server
  and the plugin, including where it belongs in an MCP client configuration

#### Scenario: Mismatch is diagnosable

- **WHEN** the two ends are configured with different ports
- **THEN** the troubleshooting section identifies this as a cause of "Aseprite
  not connected", since nothing negotiates the port

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

### Requirement: Project documentation reflects the new tool surface

`AGENTS.md` MUST record the new tool count and the millisecond/seconds
conversion boundary, so the architecture notes describe the shipped contract
rather than Aseprite's native units.

#### Scenario: Tool count and duration unit are current

- **WHEN** a contributor reads the design decisions in `AGENTS.md`
- **THEN** the tool count reflects twenty-four tools and a note explains that
  frame duration crosses the bridge in milliseconds, converted to Aseprite's
  native seconds internally

### Requirement: Project documentation reflects the new tool surface and the export_png fix

`AGENTS.md` MUST record the new tool count and the corrected reasoning behind
`export_png`'s implementation, replacing any note that still describes
`saveCopyAs` as the export mechanism.

#### Scenario: Tool count and export mechanism are current

- **WHEN** a contributor reads the design decisions in `AGENTS.md`
- **THEN** the tool count reflects thirty tools, and the `export_png` note
  describes `Image(sprite, frame):saveAs`, matching what `get_canvas_image`
  already documented, rather than `saveCopyAs`
