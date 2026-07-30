## ADDED Requirements

### Requirement: Files can be opened into a new active sprite

The plugin MUST be able to open an existing file from disk into a new sprite,
which becomes the active sprite, so a caller can edit existing art rather than
only sprites this bridge created.

#### Scenario: File opened

- **WHEN** `open_file` is called with the path to a file Aseprite can read
- **THEN** that file is loaded into a new sprite which becomes the active
  sprite, and the result reports its dimensions and frame count

#### Scenario: Path missing or unreadable

- **WHEN** `open_file` is called with an empty path, or a path Aseprite
  cannot open
- **THEN** the call fails with an error naming the problem, rather than
  leaving the active sprite in an inconsistent state

### Requirement: The active sprite can be saved to disk

The plugin MUST be able to save the active sprite to a path, preserving
layers, frames, and tags, defaulting to the sprite's existing filename when no
path is given.

#### Scenario: Saved to an explicit path

- **WHEN** `save_sprite` is called with a path
- **THEN** the active sprite is written there in a format that preserves its
  layers and frames

#### Scenario: Saved to the sprite's existing path

- **WHEN** `save_sprite` is called with no path, on a sprite that was opened
  from or previously saved to a file
- **THEN** the sprite is saved back to that same path

#### Scenario: Never-saved sprite with no path given

- **WHEN** `save_sprite` is called with no path, on a sprite that has never
  been saved
- **THEN** the call fails with an error naming that requirement, rather than
  attempting to save to an empty path

### Requirement: Open sprites can be enumerated and switched between

The plugin MUST report every currently open sprite and MUST be able to change
which one is active, so a caller can work with more than one sprite without
losing track of which is which.

#### Scenario: Sprites listed

- **WHEN** `list_sprites` is called
- **THEN** every open sprite is reported with its index, filename,
  dimensions, modified state, and whether it is the active sprite

#### Scenario: Nothing open

- **WHEN** `list_sprites` is called with no sprite open
- **THEN** it returns an empty list rather than an error

#### Scenario: Active sprite changed

- **WHEN** `set_active_sprite` is called with a valid index
- **THEN** that sprite becomes the active sprite, and a subsequent draw or
  read tool operates on it

#### Scenario: Index out of range

- **WHEN** `set_active_sprite` is called with an index outside the current
  open-sprite count
- **THEN** the call fails with an error naming the valid range

### Requirement: A sprite can be closed, refusing to discard unsaved work by default

The plugin MUST refuse to close a modified sprite unless explicitly forced, so
that unsaved work is not silently discarded and so that closing a sprite
cannot trigger an interactive confirmation dialog that would hang the bridge.

#### Scenario: Unmodified sprite closed

- **WHEN** `close_sprite` is called on a sprite with no unsaved changes
- **THEN** it closes without requiring `force`

#### Scenario: Modified sprite refused

- **WHEN** `close_sprite` is called on a sprite with unsaved changes and
  `force` is not set
- **THEN** the call fails with an error naming `save_sprite` or `force` as the
  ways forward, and the sprite remains open

#### Scenario: Modified sprite closed with force

- **WHEN** `close_sprite` is called with `force` true on a sprite with unsaved
  changes
- **THEN** the sprite closes, discarding those changes

### Requirement: A sprite sheet can be exported

The plugin MUST be able to export every frame of the active sprite as a single
image arranged in a grid, so an animation can be shared as one file without a
caller assembling frames by hand.

#### Scenario: Spritesheet exported

- **WHEN** `export_spritesheet` is called with a path
- **THEN** a single image containing every frame is written to that path

#### Scenario: Column count controls the grid

- **WHEN** `export_spritesheet` is called with a `columns` value
- **THEN** the exported grid uses that many columns

### Requirement: The active sprite can be exported to a PNG file, one file per call

`export_png` MUST composite the requested frame with `Image(sprite,
frameNumber):saveAs(path)` rather than `Sprite:saveCopyAs`, and MUST accept an
optional frame number defaulting to the active frame, so that exporting a
multi-frame sprite writes exactly one file at the requested path instead of a
numbered sequence that never includes that path.

#### Scenario: Single-frame sprite exported

- **WHEN** `export_png` is called on a sprite with one frame
- **THEN** a PNG of that frame is written at the requested path, as before

#### Scenario: Multi-frame sprite exports exactly one file

- **WHEN** `export_png` is called on a sprite with more than one frame
- **THEN** exactly one PNG is written, at the requested path, composited from
  the active frame or the frame explicitly requested — not a numbered
  sequence

#### Scenario: An explicit frame is exported

- **WHEN** `export_png` is called with a `frame` parameter
- **THEN** the exported PNG composites that frame rather than the active one

#### Scenario: Frame number out of range

- **WHEN** `export_png` is called with a `frame` value outside the sprite's
  current frame count
- **THEN** the call fails with an error naming the valid range
