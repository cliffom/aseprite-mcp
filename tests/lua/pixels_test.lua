-- Tests for the pixel encodings in both directions: parse_pixels decodes the
-- batch write payload "x,y,RRGGBB;...", resolve_pixel decodes what getPixel
-- hands back on the way out.
--
-- Both are pure. Clipping against the cel bounds stays in the handler, because
-- only the handler knows the canvas geometry.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")
local eq, throws = h.eq, h.throws

local plugin = h.plugin()
local parse   = plugin.parse_pixels
local resolve = plugin.resolve_pixel

local tests = {}

tests["well-formed entries parse with no skips"] = function()
  local entries, skipped = parse("9,3,5C2E1A;22,3,5C2E1A")
  eq(#entries, 2, "wrong entry count")
  eq(skipped, 0, "well-formed input reported skips")
  eq(entries[1].x, 9, "x wrong")
  eq(entries[1].y, 3, "y wrong")
  eq(entries[1].r, 0x5C, "red wrong")
  eq(entries[1].g, 0x2E, "green wrong")
  eq(entries[1].b, 0x1A, "blue wrong")
end

tests["a single entry parses"] = function()
  local entries, skipped = parse("0,0,FF0000")
  eq(#entries, 1, "wrong entry count")
  eq(skipped, 0, "single entry reported a skip")
  eq(entries[1].r, 255, "red wrong")
  eq(entries[1].g, 0, "green wrong")
  eq(entries[1].b, 0, "blue wrong")
end

tests["a trailing semicolon is not counted as an entry"] = function()
  local entries, skipped = parse("1,1,FFFFFF;")
  eq(#entries, 1, "trailing semicolon produced an extra entry")
  eq(skipped, 0, "trailing semicolon counted as malformed")
end

tests["lowercase hex is accepted"] = function()
  local entries, skipped = parse("2,2,ff00aa")
  eq(#entries, 1, "lowercase hex rejected")
  eq(skipped, 0, "lowercase hex counted as malformed")
  eq(entries[1].b, 0xAA, "blue wrong")
end

tests["a non-hex colour is skipped and counted"] = function()
  local entries, skipped = parse("0,0,FF0000;1,1,ZZZZZZ;2,2,00FF00")
  eq(#entries, 2, "well-formed entries were dropped")
  eq(skipped, 1, "malformed entry was not counted")
  eq(entries[2].x, 2, "surviving entries are in the wrong order")
end

tests["short and long colours are skipped"] = function()
  local _, short_skipped = parse("0,0,FFF")
  eq(short_skipped, 1, "3-digit colour was accepted")
  local _, long_skipped = parse("0,0,FF0000AA")
  eq(long_skipped, 1, "8-digit colour was accepted")
end

tests["a hash prefix on the colour is skipped"] = function()
  local entries, skipped = parse("0,0,#FF0000")
  eq(#entries, 0, "hash-prefixed colour was accepted")
  eq(skipped, 1, "hash-prefixed colour was not counted")
end

tests["entries with too few or too many fields are skipped"] = function()
  local _, few = parse("0,FF0000")
  eq(few, 1, "two-field entry was accepted")
  local _, many = parse("0,0,0,FF0000")
  eq(many, 1, "four-field entry was accepted")
end

tests["negative coordinates are skipped"] = function()
  local entries, skipped = parse("-1,0,FF0000;0,-1,FF0000;3,4,FF0000")
  eq(#entries, 1, "negative coordinates were accepted")
  eq(skipped, 2, "negative coordinates were not counted")
  eq(entries[1].x, 3, "wrong entry survived")
end

tests["entries with spaces are skipped"] = function()
  local entries, skipped = parse("0, 0, FF0000")
  eq(#entries, 0, "spaced entry was accepted")
  eq(skipped, 1, "spaced entry was not counted")
end

tests["large coordinates parse — clipping is the handler's job"] = function()
  local entries, skipped = parse("9999,9999,FF0000")
  eq(#entries, 1, "large coordinate was rejected by the parser")
  eq(skipped, 0, "large coordinate was counted as malformed")
  eq(entries[1].x, 9999, "x wrong")
end

tests["an all-malformed payload yields no entries"] = function()
  local entries, skipped = parse("garbage;more garbage")
  eq(#entries, 0, "garbage produced entries")
  eq(skipped, 2, "garbage was not counted")
end

-- ── resolve_pixel ─────────────────────────────────────────────────────────
--
-- The packed layouts are verified against a live editor, not inferred: an
-- opaque black Color has rgbaPixel 4278190080, and graya(128, 255) reads back
-- as 65408. See the change's notes/editor-probe.md.

local function rgba(r, g, b, a)
  return r + g * 256 + b * 65536 + a * 16777216
end

tests["an RGB value resolves to hex and alpha"] = function()
  local colour, alpha = resolve(rgba(0x5C, 0x2E, 0x1A, 255), "rgb")
  eq(colour, "#5C2E1A", "RGB channels are in the wrong order")
  eq(alpha, 255, "alpha wrong")
end

tests["an RGB value keeps its alpha"] = function()
  local colour, alpha = resolve(rgba(255, 0, 0, 0), "rgb")
  eq(colour, "#FF0000", "colour lost when transparent")
  eq(alpha, 0, "transparent pixel did not report alpha 0")
end

tests["a grayscale value resolves to a grey hex"] = function()
  local colour, alpha = resolve(128 + 255 * 256, "grayscale")
  eq(colour, "#808080", "grayscale value was not mirrored across the channels")
  eq(alpha, 255, "grayscale alpha wrong")
end

tests["a transparent grayscale value reports alpha 0"] = function()
  local colour, alpha = resolve(64, "grayscale")
  eq(colour, "#404040", "grayscale value wrong")
  eq(alpha, 0, "grayscale alpha wrong")
end

tests["an indexed value resolves through the palette"] = function()
  -- A palette index means nothing on its own, so the caller gets the colour it
  -- stands for rather than the number.
  local palette = {
    getColor = function(_, index)
      eq(index, 5, "the raw value was not used as the palette index")
      return { red = 0x12, green = 0x34, blue = 0x56, alpha = 200 }
    end,
  }
  local colour, alpha = resolve(5, "indexed", palette)
  eq(colour, "#123456", "palette colour lost")
  eq(alpha, 200, "palette alpha lost")
end

tests["an unsupported colour mode errors rather than guessing"] = function()
  throws(function() resolve(0, "tilemap") end,
         "unsupported color mode: tilemap", "tilemap was decoded as a colour")
  throws(function() resolve(0, nil) end,
         "unsupported color mode: nil", "a missing colour mode was accepted")
end

tests["an empty pixels payload is rejected by the handler"] = function()
  -- The handler checks for an active sprite first, so stub the minimum.
  local saved = _G.app
  _G.app = { activeSprite = {} }
  local ok, err = pcall(function()
    throws(function() plugin.handlers.draw_pixels_batch({ pixels = "" }) end,
           "pixels is required", "empty payload was accepted")
    throws(function() plugin.handlers.draw_pixels_batch({}) end,
           "pixels is required", "missing payload was accepted")
  end)
  _G.app = saved
  if not ok then error(err, 0) end
end

return tests
