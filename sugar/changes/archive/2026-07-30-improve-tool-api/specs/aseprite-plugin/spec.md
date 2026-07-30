## ADDED Requirements

### Requirement: Connection survives a server restart

The plugin MUST retain a usable WebSocket handle across a connection close, so
that when the socket reconnects it can complete a handshake and reply to
commands without the editor being restarted.

#### Scenario: Server restarts while Aseprite stays open

- **WHEN** the MCP server is stopped and started again while Aseprite remains
  running
- **THEN** the plugin completes a handshake on the new connection and subsequent
  tool calls return results instead of timing out

#### Scenario: Handshake accompanies every reconnection

- **WHEN** the plugin's socket reports an OPEN event after an earlier close
- **THEN** a handshake message is transmitted, rather than being silently
  discarded because the handle was cleared

### Requirement: Handshake reports the real Aseprite version

The handshake MUST report the version of the running editor rather than a
compile-time constant, so that server logs describe the user's actual
environment.

#### Scenario: Version is read from the editor

- **WHEN** the plugin sends its handshake
- **THEN** the reported Aseprite version comes from the running application, not
  from a hardcoded string

### Requirement: Colour mode is honoured

`create_sprite` MUST create the sprite in the colour mode requested by the
caller, accepting RGB, Grayscale, and Indexed case-insensitively and defaulting
to RGB when the mode is omitted.

#### Scenario: Grayscale sprite requested

- **WHEN** `create_sprite` is called with a mode of `Grayscale`
- **THEN** the created sprite uses the grayscale colour mode

#### Scenario: Mode omitted

- **WHEN** `create_sprite` is called without a mode
- **THEN** the sprite is created in RGB

#### Scenario: Unrecognised mode rejected

- **WHEN** `create_sprite` is called with a mode that is not one of the accepted
  values
- **THEN** the call fails with an error naming the accepted values, rather than
  silently falling back to RGB

### Requirement: Plugin honours the configured port

The plugin MUST dial the port named by the shared configuration rather than an
unconditional literal, so that both ends of the bridge can be moved together.

#### Scenario: Port overridden

- **WHEN** the bridge is configured to use a port other than the default
- **THEN** the plugin connects to that port

#### Scenario: Port unset

- **WHEN** no port is configured
- **THEN** the plugin connects to the default port 9876
