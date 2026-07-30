## ADDED Requirements

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

Documentation MUST record behaviours that will otherwise be reported as bugs,
including the plugin's inability to reconnect after the server restarts.

#### Scenario: Reconnect limitation is discoverable

- **WHEN** a user's tool calls stop working after restarting their MCP client
- **THEN** the README troubleshooting section tells them to restart Aseprite and
  notes that automatic reconnection is not yet implemented

#### Scenario: Port conflict is discoverable

- **WHEN** the server fails to start because port 9876 is already bound
- **THEN** the README troubleshooting section explains the cause
