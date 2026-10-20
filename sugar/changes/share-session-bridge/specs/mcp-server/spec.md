## ADDED Requirements

### Requirement: Sessions share a serialized editor bridge

Independent MCP stdio sessions MUST share one background bridge per configured
port. Calls MUST return their own editor results and execute one at a time.
The ten-second editor timeout MUST start at dispatch rather than while queued.

#### Scenario: Two sessions use one editor
- **WHEN** two sessions issue calls concurrently
- **THEN** the bridge sends one command at a time and routes each response only
  to the requesting session

#### Scenario: A session leaves
- **WHEN** a frontend disconnects
- **THEN** its queued calls are removed, dispatched calls finish with cleanup,
  and other frontends remain connected

### Requirement: Disconnects have explicit uncertain outcomes

Editor and bridge disconnections MUST produce MCP errors. Subsequent calls
MUST reconnect as needed without replaying earlier calls.

#### Scenario: Bridge connection is lost during a mutation
- **WHEN** the frontend loses its bridge connection before receiving a reply
- **THEN** it returns an error explaining that the outcome is unknown, and a
  later call reconnects without repeating that mutation

### Requirement: Canvas files belong to the bridge

The bridge MUST render, read, and remove its generated temporary canvas path,
returning completed MCP image content to the requesting frontend.

#### Scenario: Requesting session disappears
- **WHEN** a session disconnects after canvas rendering was dispatched
- **THEN** the bridge completes the request and removes its temporary file
