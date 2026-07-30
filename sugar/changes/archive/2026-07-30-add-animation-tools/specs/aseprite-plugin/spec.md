## ADDED Requirements

### Requirement: Frames can be added, as a duplicate or empty

The plugin MUST be able to insert a new frame into the active sprite, either
duplicating an existing frame's cels across every layer or leaving it
completely empty.

#### Scenario: Frame added as a duplicate

- **WHEN** `add_frame` is called with `duplicate` true or omitted
- **THEN** a new frame is inserted whose cels match the reference frame's,
  on every layer that had a cel there

#### Scenario: Frame added empty

- **WHEN** `add_frame` is called with `duplicate` false
- **THEN** a new frame is inserted holding no cels on any layer

#### Scenario: Reference frame out of range

- **WHEN** `add_frame` is called with an `after` value outside the sprite's
  current frame count
- **THEN** the call fails with an error naming the valid range, rather than
  inserting relative to an out-of-range position

### Requirement: Frames can be removed

The plugin MUST be able to delete a frame from the active sprite by number,
and MUST refuse to remove a sprite's only remaining frame.

#### Scenario: Frame deleted

- **WHEN** `delete_frame` is called with a valid frame number and the sprite
  has more than one frame
- **THEN** that frame is removed and every later frame's number decreases by
  one

#### Scenario: Only frame cannot be deleted

- **WHEN** `delete_frame` is called on a sprite that has exactly one frame
- **THEN** the call fails with an error naming that condition, rather than
  leaving the sprite with zero frames

### Requirement: A frame's playback duration can be set and read

The plugin MUST accept and report frame duration in milliseconds, converting
to and from Aseprite's native seconds-based `Frame.duration` at the boundary.

#### Scenario: Duration set

- **WHEN** `set_frame_duration` is called with a frame number and a positive
  millisecond value
- **THEN** that frame's duration is updated, and reading it back through
  `list_frames` reports the same millisecond value

#### Scenario: Non-positive duration rejected

- **WHEN** `set_frame_duration` is called with a duration of zero or less
- **THEN** the call fails with an error naming that requirement, rather than
  setting an unplayable duration

### Requirement: The active frame can be changed

The plugin MUST be able to change which frame is active, so that every
existing draw and read tool — which all operate on the active frame — can
target a frame other than the sprite's first.

#### Scenario: Active frame changed

- **WHEN** `set_active_frame` is called with a valid frame number
- **THEN** that frame becomes the active frame, and a subsequent draw
  operation with no frame parameter of its own lands there

#### Scenario: Frame number out of range

- **WHEN** `set_active_frame` is called with a frame number outside the
  sprite's current frame count
- **THEN** the call fails with an error naming the valid range

### Requirement: Frames can be enumerated

The plugin MUST report every frame of the active sprite with its duration and
whether it is currently active, so a caller can see the animation's structure
without guessing at frame numbers.

#### Scenario: Frames listed

- **WHEN** `list_frames` is called with a sprite open
- **THEN** each frame is reported with its frame number, its duration in
  milliseconds, and whether it is the active frame

#### Scenario: Exactly one frame reports active

- **WHEN** `list_frames` is called
- **THEN** exactly one entry in the result has `isActive` true
