# Manual verification — tasks 6.1, 6.2 and 6.3

Everything touching `app`, `Sprite`, or `Frame` is out of scope for the two
automated suites, so the five handlers' editor-facing halves are verified here.

## Method

Rather than driving the UI by hand, the script loads **`plugin/main.lua`
itself** and calls the **real handlers** against a live sprite:

```lua
WebSocket = nil
local plugin = dofile(".../plugin/main.lua")
local H = plugin.handlers
```

Nilling `WebSocket` makes `main.lua` take its export-table branch instead of
opening a socket — the same split `tests/lua/harness.lua` relies on — so the
handlers under test are the shipped ones, not a paraphrase. Run with
`aseprite.exe -b --script verify_frames.lua` against the same local build the
probes used (`1.0-dev`, `app.apiVersion` 40).

This covers the handler, its validation, and its result string. What it does
not cover is the WebSocket transport and the Python half, which
`tests/test_server.py` already owns.

## 6.1 — `add_frame` duplicates every layer; `duplicate=false` is blank

A 16×16 sprite with three drawable layers, one of them nested in a group, each
holding a distinct pixel on frame 1.

```
  ok   add_frame{duplicate=true}   -> added frame 2 (duplicated frame 1)
  ok   sprite now has 2 frames   frames=2
  ok   the new frame became active   active=2
  ok   base   layer art copied to frame 2
  ok   top    layer art copied to frame 2
  ok   nested layer art copied to frame 2 (inside a group)
  ok   add_frame{duplicate=false}   -> added empty frame 3
  ok   empty frame landed at 3 and is active   active=3
  ok   base   layer has NO cel on frame 3
  ok   top    layer has NO cel on frame 3
  ok   nested layer has NO cel on frame 3
  ok   add_frame{after=1}   -> added frame 2 (duplicated frame 1)
  ok   result names the inserted position
  ok   insert landed at 2, pushing the rest back
```

The `after=1` case is what the two calls' insertion asymmetry would break: it
confirms the duplicate lands at `after + 1` and the result string names that
number, not the source's.

## 6.2 — `set_active_frame` retargets the existing draw and read tools

```
  ok   set_active_frame{frame=2}   -> active frame set to 2
  ok   app.activeFrame moved   active=2
  ok   draw_pixel on frame 2   -> pixel drawn at 5,5
  ok   frame 2 holds the pixel   #FF0000 alpha=255
  ok   set_active_frame{frame=1}   -> active frame set to 1
  ok   frame 1 was NOT drawn on   #000000 alpha=0
  ok   set_active_frame{frame=3}   -> active frame set to 3
  ok   frame 3 was NOT drawn on   errored: no cel at the active layer and frame
  ok   draw_pixels_batch on frame 3   -> drew 2 pixels
  ok   draw_rect on frame 3   -> drew rect at 11,11 3x3
  ok   batch landed on frame 3   #00FF00
  ok   batch did NOT land on frame 2   alpha=0
  ok   set_active_frame{frame=2} again   -> active frame set to 2
  ok   still frame 2
```

Three of the untouched tools — `draw_pixel`, `draw_pixels_batch`, `draw_rect` —
follow the active frame with no change to any of them, which is the whole point
of the change. `get_pixel` reading frame 3 raises `no cel at the active layer
and frame` rather than reporting transparency; that is its existing documented
behaviour for a layer that has never been drawn on, and it is a *stronger*
confirmation that nothing landed there.

Setting the already-active frame is not special-cased and succeeds.

## 6.3 — `delete_frame` renumbers; durations round-trip in milliseconds

```
  ok   set_frame_duration   -> frame 1 duration set to 100ms
  ok   set_frame_duration   -> frame 2 duration set to 83ms
  ok   set_frame_duration   -> frame 3 duration set to 1001ms
  ok   set_frame_duration   -> frame 4 duration set to 65535ms
       list_frames: 1:100 2:83 3:1001 4:65535*
  ok   durations round-trip exactly, including 1001 and 65535
  ok   exactly one frame reports isActive   count=1
  ok   durationMs is an integer, not a float
  ok   delete_frame{frame=2}   -> deleted frame 2
       list_frames: 1:100 2:1001* 3:65535
  ok   count dropped to 3   count=3
  ok   later frames renumbered down (1001ms is now frame 2)
  ok   active frame followed its content to its new number   active=2
  ok   retimed frame reads back 41ms
```

**1001 ms is deliberate** — it is the first value the naive `ms / 1000` loses,
so this is the end-to-end confirmation that the `+ 0.5` nudge works through a
real `Frame`, not just in the unit test's model of one. 65535 confirms the
ceiling survives the nudge without overshooting.

`durationMs` comes back an integer, which matters because `json_encode` prints
a non-integer with `%g` — a float would reach the caller as `83.0`.

## Error paths — every message matches the README verbatim

```
  ok   delete_frame out of range      frame must be between 1 and 3
  ok   set_active_frame frame 0       frame must be between 1 and 3
  ok   set_active_frame non-integer   frame must be between 1 and 3
  ok   set_active_frame with no frame frame must be between 1 and 3
  ok   add_frame after out of range   after must be between 1 and 3
  ok   duration 0                     duration must be between 1 and 65535 milliseconds
  ok   duration negative              duration must be between 1 and 65535 milliseconds
  ok   duration above ceiling         duration must be between 1 and 65535 milliseconds
  ok   duration fractional            duration must be between 1 and 65535 milliseconds
  ok   delete_frame on the only frame cannot delete the only frame
  ok   the sprite still has its frame
  ok   add_frame          with no sprite open   no active sprite
  ok   delete_frame       with no sprite open   no active sprite
  ok   set_frame_duration with no sprite open   no active sprite
  ok   set_active_frame   with no sprite open   no active sprite
  ok   list_frames        with no sprite open   no active sprite
```

Every message arrives with **no `main.lua:NNN:` prefix**, confirming all five
handlers raise through `fail` rather than `error` — which is what keeps the
README's troubleshooting headings matching and keeps an absolute local path off
the wire.

The only-frame case is checked for its side effect too, not just its message:
the sprite still has its frame afterwards.
