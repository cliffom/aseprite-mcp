## ADDED Requirements

### Requirement: Animation tools are registered and described

The server MUST register `add_frame`, `delete_frame`, `set_frame_duration`,
`set_active_frame`, and `list_frames` alongside the existing tools, and the
schemas MUST state that frame duration is expressed in milliseconds and that
frame numbers are 1-based and re-read on every call rather than cached.

#### Scenario: Registered set

- **WHEN** the tool list is requested
- **THEN** it contains the five tools this change adds, in addition to the
  nineteen that existed before

#### Scenario: Duration unit is documented

- **WHEN** a caller reads the `set_frame_duration` or `list_frames` schema
- **THEN** the description states the value is in milliseconds, not seconds

#### Scenario: Frame renumbering is documented

- **WHEN** a caller reads the `delete_frame` schema
- **THEN** the description states that later frames' numbers shift down by
  one, so a frame number is not a stable identity across a delete

#### Scenario: Every registered tool is served

- **WHEN** the registered tool set is compared against the plugin's handlers
- **THEN** every registered tool has a handler, so no tool can be advertised
  that Aseprite would answer as unknown
