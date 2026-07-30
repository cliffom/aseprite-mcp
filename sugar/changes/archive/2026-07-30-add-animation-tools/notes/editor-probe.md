# Editor probe — tasks 1.1, 1.2 and 1.3

Three open questions from `proposal.md` gated groups 2 and 3:

1. Where does `Sprite:newFrame(n)` / `newEmptyFrame(n)` put the new frame
   relative to `n`, does `newFrame` copy cels on every layer, and does the new
   frame become active?
2. What does `Sprite:deleteFrame` do when asked to delete a sprite's only
   frame, and what happens to `app.activeFrame` when a frame before it goes?
3. Does `Frame.duration` read and write seconds, and what does a zero or
   negative value do?

**Answers: `newFrame(n)` inserts at `n + 1` but `newEmptyFrame(n)` inserts at
`n`, an asymmetry `add_frame` has to absorb; `deleteFrame` on the only frame is
a silent no-op, so the guard has to be ours; `duration` is seconds, clamped to
[0.001, 65.535], and a non-positive value silently becomes 1 ms. A fourth
finding fell out: the naive `ms / 1000` conversion loses a millisecond on 741
of 65535 values, and `(ms + 0.5) / 1000` loses none.**

## Method

`aseprite.exe -b --script <probe>.lua` against the same local build the two
prior probes used (`C:\Users\ADMIN\Documents\aseprite\build\bin\aseprite.exe`,
`1.0-dev`, `app.apiVersion` 40), four scripts: frame insertion/deletion/
duration, then a targeted re-run to settle insertion position, then a sweep of
the whole 1–65535 ms range, then the conversion candidates.

Frames are tagged by **duration**, not pixel content. A duplicate frame holds
the same pixels as its source and sits next to it, so no cel map can tell
"inserted at `n`" from "inserted at `n + 1`" — both produce the identical
sequence. Durations are per-frame, survive duplication, and can be made unique
per frame, so they are what the position claims below rest on.

## Output — frame insertion (task 1.1)

```
── newFrame(n) ────────────────────────────────────────────────────────────
before                         frames=3 [1:0.111 2:0.222 3:0.333] active=3
newFrame(1)                    frames=4 [1:0.111 2:0.111 3:0.222 4:0.333] active=2
                                                  ↑ copy landed at 2, not 1
  returned FrameObj.frameNumber = 1        ← the SOURCE frame, not the new one
  tagging the returned obj      frames=4 [1:0.999 2:0.111 3:0.222 4:0.333]
                                          ↑ confirms: the return is frame 1

active set to 1                frames=4 [1:0.111 2:0.111 3:0.222 4:0.333] active=1
newFrame(3)                    frames=5 [1:0.111 2:0.111 3:0.222 4:0.222 5:0.333] active=4
                                                          ↑ copy at 4 = n + 1

── newEmptyFrame(n) ───────────────────────────────────────────────────────
before                         frames=3 [1:0.111 2:0.222 3:0.333] active=3
newEmptyFrame(2)               frames=4 [1:0.111 2:0.111 3:0.222 4:0.333] active=2
  returned FrameObj.frameNumber = 2        ← correct here
  tagging the returned obj      frames=4 [1:0.111 2:0.999 3:0.222 4:0.333]
                                                ↑ the new frame IS at 2 = n

── "insert after N" recipe, verified for both ─────────────────────────────
before                         frames=3 [1:0.111 2:0.222 3:0.333] active=3
newFrame(2)                    frames=4 [1:0.111 2:0.222 3:0.222 4:0.333] active=3
before                         frames=3 [1:0.111 2:0.222 3:0.333] active=3
newEmptyFrame(3)               frames=4 [1:0.111 2:0.222 3:0.222 4:0.333] active=3
   cels: 1=cel 2=- 3=- 4=-             ← and the new frame 3 is genuinely blank

── out of range ───────────────────────────────────────────────────────────
newFrame(0)                    ok=false  frame index out of bounds 0
newFrame(-1)                   ok=false  frame index out of bounds -1
newFrame(99)   on 5 frames     ok=true   frames=100   ← PADS up to n + 1
newFrame(5)    on 1 frame      ok=true   frames=6     ← pads
newEmptyFrame(50) on 6 frames  ok=true   frames=7     ← clamps to append
newEmptyFrame(6)  on 3 frames  ok=true   frames=4     ← clamps

── cels, groups, activity, transactions ───────────────────────────────────
newFrame duplicates cels on a flat layer AND a layer inside a group:
  flat  : f1=true f2=true
  inner : f1=true f2=true      inner f2 pixel = FF141414  (source's colour)
A layer with no cel on the source frame gets none on the copy.
The new frame becomes app.activeFrame, for both calls.
app.transaction(function() spr:newFrame(1) end)  ok, one undo step.
```

**Settles:** `newFrame(n)` inserts the copy at **n + 1**; `newEmptyFrame(n)`
inserts the blank at **n**. So one `add_frame(after = N)` maps onto
`newFrame(N)` for the duplicate and `newEmptyFrame(N + 1)` for the empty — both
then land at `N + 1` and become active, which is where the result string's
frame number comes from.

**Do not use either call's return value to name the new frame.** `newFrame`
returns the *source* `FrameObj` — `frameNumber` reads `n`, and writing through
it modifies frame `n`. `newEmptyFrame`'s return is correct, but relying on one
and not the other buys nothing when `after + 1` is already known.

**Validation is not optional.** `newFrame(99)` on a 5-frame sprite does not
raise — it pads the sprite out to 100 frames. A caller's typo would otherwise
silently produce 95 blank frames.

## Output — frame deletion (task 1.2)

```
4-frame sprite                 frames=4 [1..4]  cels: 1=0A 2=14 3=1E 4=28
app.frame = 3, then deleteFrame(2):
deleteFrame(2)                 ok=true  ret=nil
after                          frames=3         cels: 1=0A 2=1E 3=28
  -> active frame now 2, its pixel = FF1E1E1E
     ← the active frame FOLLOWS ITS CONTENT: it was showing 1E before and
       still is, at its new number

deleteFrame(1) ×2 down to 1 frame       ok=true each time
deleteFrame(1) ON THE ONLY FRAME        ok=true  ret=nil  frames still 1
deleteFrame(frames[1]) ON THE ONLY FRAME ok=true          frames still 1
                                        ← SILENT NO-OP, not an error

deleteFrame(0)                 ok=false  frame index out of bounds 0
deleteFrame(-1)                ok=false  frame index out of bounds -1
deleteFrame(99)                ok=false  frame index out of bounds 99
deleteFrame(Frame obj)         ok=true
```

**Settles:** deleting the only frame succeeds and does nothing, so
`delete_frame` must read `#spr.frames` and refuse first — otherwise it would
report `deleted frame 1` on a sprite that still has frame 1. The
`cannot delete the only frame` message from `design.md` stands as written;
there is no Aseprite error to surface instead.

Out-of-range numbers *do* raise, but as `frame index out of bounds N` carrying
the caller's file and line — the exact shape `fail` exists to keep off the
wire. Range-check before calling, same as everywhere else.

Frame numbers after the deleted one shift down by one, and `app.activeFrame`
tracks the frame it was on rather than the number. Nothing to compensate for.

## Output — duration (task 1.3)

```
default duration          = 0.100000        type = number (seconds)

set -1         -> 0.001000 s  (1 ms)      ← non-positive silently becomes 1 ms
set 0          -> 0.001000 s  (1 ms)
set 0.0001     -> 0.001000 s  (1 ms)
set 0.001      -> 0.001000 s  (1 ms)      ← the floor
set 65.535     -> 65.535000 s (65535 ms)  ← the ceiling
set 65.536     -> 65.535000 s (65535 ms)
set 70         -> 65.535000 s (65535 ms)
set 1000000    -> 65.535000 s (65535 ms)

durations are per-frame independent; setting one inside app.transaction is one
undo step and app.undo() restores the previous value.
```

**Settles:** seconds, floats, clamped to **[0.001, 65.535] s = [1, 65535] ms** —
a 16-bit millisecond count. Zero and negative do not raise; they silently
become 1 ms, which is exactly the case `duration must be positive` has to catch
so the tool does not report success for a value it did not set. The upper bound
folds into the same check.

## Output — the millisecond conversion (fell out of 1.3)

Sweeping every integer millisecond from 1 to 65535, setting
`duration = ms / 1000` and reading back `floor(duration * 1000 + 0.5)`:

```
with floor(d*1000 + 0.5): 741 / 65535 values off
with floor(d*1000):       741 / 65535 values off   ← rounding is not the cause
  first offenders: 1001 1003 1005 1007 1009 1011 1013 1015 1017 1019 1021 1023

set  1000 ms -> stored 1.000000000000 s
set  1001 ms -> stored 1.000000000000 s   ← a millisecond gone on the way IN
set  1002 ms -> stored 1.002000000000 s
set  1003 ms -> stored 1.002000000000 s
```

The loss is on the write, not the read — `1.001` is already `1.000` once
stored — so no choice of rounding on the way out recovers it. Aseprite keeps
the duration as an integer millisecond count and converts the seconds it is
handed through a narrower float, which lands just under the integer and
truncates down.

Nudging the value half a millisecond up before dividing puts it safely inside
the target integer:

```
ms / 1000                      741 / 65535 off   first: 1001->1000
(ms + 0.5) / 1000                0 / 65535 off
(ms + 0.25) / 1000               0 / 65535 off
(ms + 0.1) / 1000                0 / 65535 off
ms / 1000 + 1e-6                 0 / 65535 off
ms * 0.001                     433 / 65535 off   first: 4007->4006

values reading back HIGHER than requested (with +0.5): 0
  set     1 ms -> 0.001000000 s -> back 1 ms       ← floor still lands right
  set  1001 ms -> 1.001000000 s -> back 1001 ms
  set 65535 ms -> 65.535000000 s -> back 65535 ms  ← ceiling still lands right
```

**Settles:** `set_frame_duration` writes `(ms + 0.5) / 1000` and `list_frames`
reads `floor(duration * 1000 + 0.5)`. Every value in 1–65535 ms round-trips
exactly, and the nudge never overshoots, including at both clamp boundaries.
`ms / 1000` is the obvious expression and it is wrong for 741 inputs — which is
what makes this pair worth extracting as named functions with a test rather
than inlining, so the `+ 0.5` is not tidied away by someone who reads it as
noise.

## What this changes in the plan

- `add_frame` calls `newFrame(after)` or `newEmptyFrame(after + 1)`, not the
  same number for both, and reports `after + 1` as the new frame's number
  rather than trusting either return value.
- `add_frame` must range-check `after` against `1..#spr.frames` before calling,
  because a too-large number pads the sprite instead of raising.
- `delete_frame` must refuse the only-frame case itself; Aseprite will not.
- `set_frame_duration` validates `1 <= duration <= 65535` — the lower bound
  because non-positive values silently become 1 ms, the upper because anything
  larger silently becomes 65535 ms.
- The ms/seconds conversion becomes a pair of pure functions with a Lua test
  (task 4.1's "more than a single arithmetic expression" branch), on the
  strength of the 741-value discrepancy.
