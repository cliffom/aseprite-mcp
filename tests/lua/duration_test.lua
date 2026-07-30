-- Tests for the frame-duration conversion.
--
-- Duration crosses the bridge in milliseconds; Frame.duration is seconds. The
-- pair is pure — neither function touches a Frame — so the conversion is
-- testable here and only the one-line property assignment is not.
--
-- It is pinned because the obvious expression is wrong. Aseprite keeps the
-- duration as an integer millisecond count derived from the seconds it is
-- given, and that derivation truncates: `ms / 1000` loses a millisecond on 741
-- of the 65535 valid inputs, 1001 among them. The `+ 0.5` nudge is what fixes
-- it, it reads like a typo, and nothing else in the file would catch its
-- removal — the handler would keep reporting the duration the caller asked for
-- while the frame held one a millisecond short.
--
-- NOTE the two functions are NOT inverses on their own: to_ms(to_duration(1))
-- is 2, because the nudge is still there. The editor's truncation is what
-- removes it, so `store` below stands in for that step. It is not a guess —
-- it reproduces the live sweep exactly, 741 offenders starting at 1001, 1003,
-- 1005. See the change's notes/editor-probe.md.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")
local eq, is_true = h.eq, h.is_true

local plugin = h.plugin()
local to_duration, to_ms = plugin.ms_to_duration, plugin.duration_to_ms

-- Stands in for Frame.duration: seconds in, an integer millisecond count back
-- out, expressed in seconds.
local function store(seconds)
  return math.floor(seconds * 1000) / 1000
end

local tests = {}

tests["milliseconds convert to seconds"] = function()
  -- Nudged half a millisecond up, which is the whole point: the value has to
  -- land inside the target integer millisecond, not on its lower edge.
  eq(to_duration(100), 0.1005, "100ms did not convert")
  eq(to_duration(1000), 1.0005, "1000ms did not convert")
  eq(to_duration(1), 0.0015, "1ms did not convert")
end

tests["the nudge is half a millisecond, not a whole one"] = function()
  -- A full millisecond would store as the next value up; anything at or below
  -- zero reintroduces the truncation this exists to avoid.
  is_true(to_duration(50) > 0.050, "the nudge is missing — 50ms is not above 0.050s")
  is_true(to_duration(50) < 0.051, "the nudge overshoots into the next millisecond")
end

tests["seconds convert back to milliseconds"] = function()
  eq(to_ms(0.1), 100, "0.1s did not convert back")
  eq(to_ms(1), 1000, "1s did not convert back")
  eq(to_ms(0.001), 1, "the 1ms floor did not convert back")
  eq(to_ms(65.535), 65535, "the 65535ms ceiling did not convert back")
end

tests["reading back rounds rather than truncates"] = function()
  -- A duration set in the editor rather than through this bridge arrives as
  -- whatever float Aseprite holds, so a value a hair under the integer must not
  -- come back a millisecond short.
  eq(to_ms(0.0829999), 83, "a value just under 83ms truncated to 82")
  eq(to_ms(0.0830001), 83, "a value just over 83ms rounded up to 84")
  eq(to_ms(1.0009999), 1001, "a value just under 1001ms truncated to 1000")
end

tests["a millisecond is a whole number on the way back"] = function()
  -- list_frames reports durationMs straight into JSON, and the encoder prints a
  -- non-integer with %g — "83.0" rather than 83. math.floor keeps it integral.
  local ms = to_ms(0.083)
  eq(ms, math.floor(ms), "durationMs came back fractional")
end

tests["every millisecond in the range round-trips through storage"] = function()
  -- set_frame_duration then list_frames, with the editor's truncation in
  -- between. The live sweep covered all 65535 against a real Frame; this covers
  -- the arithmetic, which is the half that can regress in this repo.
  for ms = 1, 65535 do
    eq(to_ms(store(to_duration(ms))), ms, "round-trip lost " .. ms .. "ms")
  end
end

tests["the boundary values round-trip"] = function()
  eq(to_ms(store(to_duration(1))), 1, "the 1ms floor did not round-trip")
  eq(to_ms(store(to_duration(65535))), 65535, "the 65535ms ceiling did not round-trip")
  eq(to_ms(store(to_duration(1001))), 1001, "1001ms — the first value ms/1000 loses")
end

tests["the nudge never overshoots"] = function()
  -- Reading back HIGHER than requested would be the failure mode of nudging too
  -- far, and it is the one a caller could not diagnose from the result string.
  for ms = 1, 65535 do
    is_true(to_ms(store(to_duration(ms))) <= ms,
            ms .. "ms read back longer than it was set")
  end
end

tests["the naive conversion would fail this suite"] = function()
  -- Guards the guard: if `+ 0.5` were dropped, the round-trip above has to
  -- actually catch it. Reproduced rather than trusted, so the sweep cannot
  -- quietly become a test of nothing. 741 and 1001 are the live editor's
  -- numbers, so a drift in `store` shows up here rather than passing silently.
  local naive = function(ms) return ms / 1000 end
  local lost, first = 0, nil
  for ms = 1, 65535 do
    if to_ms(store(naive(ms))) ~= ms then
      lost = lost + 1
      if not first then first = ms end
    end
  end
  eq(lost, 741, "ms/1000 lost a different number of values than the editor did")
  eq(first, 1001, "ms/1000 first lost a different value than the editor did")
end

return tests
