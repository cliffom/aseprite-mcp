## ADDED Requirements

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

## MODIFIED Requirements

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
