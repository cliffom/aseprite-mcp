-- Tests for the create_sprite `mode` parameter.
--
-- resolve_color_mode is pure: it maps the caller's string onto a key of
-- Aseprite's ColorMode enum without touching the enum itself, which exists only
-- inside the editor. The handler does the ColorMode[key] lookup, so the mapping
-- is testable here and only the one-line indexing is not.
--
-- The keys are upper-case because that is how Aseprite spells them —
-- ColorMode.Grayscale is nil, ColorMode.GRAYSCALE is 1.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")
local eq, throws = h.eq, h.throws

local plugin = h.plugin()
local resolve = plugin.resolve_color_mode

local tests = {}

tests["each documented spelling maps to its ColorMode key"] = function()
  eq(resolve("RGB"), "RGB", "RGB did not map")
  eq(resolve("Grayscale"), "GRAYSCALE", "Grayscale did not map")
  eq(resolve("Indexed"), "INDEXED", "Indexed did not map")
end

tests["matching is case-insensitive"] = function()
  eq(resolve("rgb"), "RGB", "lowercase rgb rejected")
  eq(resolve("grayscale"), "GRAYSCALE", "lowercase grayscale rejected")
  eq(resolve("INDEXED"), "INDEXED", "uppercase INDEXED rejected")
  eq(resolve("gRaYsCaLe"), "GRAYSCALE", "mixed-case grayscale rejected")
  eq(resolve("Rgb"), "RGB", "mixed-case rgb rejected")
end

tests["an omitted mode defaults to RGB"] = function()
  eq(resolve(nil), "RGB", "nil did not default to RGB")
  -- The decoder yields "" for an explicitly empty parameter; the rest of the
  -- plugin treats empty as absent, so this does too.
  eq(resolve(""), "RGB", "empty string did not default to RGB")
end

tests["an unknown mode is rejected, naming the accepted values"] = function()
  throws(function() resolve("sepia") end,
         "invalid color mode: sepia", "unknown mode was accepted")
  throws(function() resolve("sepia") end,
         "expected RGB, Grayscale, or Indexed", "error did not name the accepted values")
end

tests["a near-miss spelling is rejected rather than guessed"] = function()
  -- Silently falling back to RGB would produce the wrong sprite with no signal.
  throws(function() resolve("greyscale") end,
         "invalid color mode", "the British spelling was silently accepted")
  throws(function() resolve("index") end,
         "invalid color mode", "a truncated mode was silently accepted")
  throws(function() resolve("RGBA") end,
         "invalid color mode", "RGBA was silently accepted")
end

tests["a non-string mode is rejected, not concatenated into a crash"] = function()
  throws(function() resolve(8) end,
         "invalid color mode: 8", "a number was accepted as a mode")
  throws(function() resolve(true) end,
         "invalid color mode: true", "a boolean was accepted as a mode")
end

return tests
