## ADDED Requirements

### Requirement: Shared bridge starts automatically

The existing `aseprite-mcp` command MUST start a stdio frontend and discover or
start a detached shared bridge on `ASEPRITE_MCP_PORT`, defaulting to 9876.
Discovery MUST be bounded to five seconds and verify protocol compatibility.

#### Scenario: Concurrent first sessions
- **WHEN** multiple frontends start with no bridge listening
- **THEN** one child owns the configured port and all frontends connect to it

#### Scenario: An incompatible process owns the port
- **WHEN** discovery encounters an incompatible service or legacy bridge
- **THEN** startup fails clearly without terminating that process

### Requirement: Bridge lifetime is independent of its first session

The bridge MUST survive its launching frontend and exit after 60 seconds
without frontends, allowing dispatched calls to finish. Logs MUST use a
separate file whose path is reported to the launching frontend's stderr.

#### Scenario: First session exits
- **WHEN** the launching frontend closes while another is attached
- **THEN** the remaining frontend continues using the same bridge

#### Scenario: Only the plugin remains
- **WHEN** no frontends remain for 60 seconds and no calls are running
- **THEN** the bridge exits even if the plugin is connected
