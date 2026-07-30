## ADDED Requirements

### Requirement: File and sprite lifecycle tools are registered and described

The server MUST register `open_file`, `save_sprite`, `list_sprites`,
`set_active_sprite`, `close_sprite`, and `export_spritesheet` alongside the
existing tools, and MUST update `export_png`'s schema to document its new
`frame` parameter and the corrected one-file-per-call behaviour.

#### Scenario: Registered set

- **WHEN** the tool list is requested
- **THEN** it contains the six tools this change adds, in addition to the
  twenty-four that existed before

#### Scenario: close_sprite's safety default is documented

- **WHEN** a caller reads the `close_sprite` schema
- **THEN** the description states that a modified sprite is refused unless
  `force` is set

#### Scenario: export_png's frame parameter is documented

- **WHEN** a caller reads the `export_png` schema
- **THEN** the description states that `frame` defaults to the active frame
  and that the tool writes exactly one file regardless of frame count

#### Scenario: Every registered tool is served

- **WHEN** the registered tool set is compared against the plugin's handlers
- **THEN** every registered tool has a handler, so no tool can be advertised
  that Aseprite would answer as unknown
