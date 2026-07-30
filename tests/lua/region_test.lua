-- Tests for the region read-back encoding: rows delimited by "|", runs within
-- a row as "count,RRGGBB" delimited by ";".
--
-- encode_region is pure — it takes a flat, row-major list of colours and knows
-- nothing about the canvas. Clipping and the pixel cap stay in the handler,
-- because only the handler knows the sprite geometry.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")
local eq = h.eq

local plugin = h.plugin()
local encode = plugin.encode_region

local tests = {}

tests["a row of one colour collapses to a single run"] = function()
  eq(encode({ "FF0000", "FF0000", "FF0000", "FF0000" }, 4, 1),
     "4,FF0000", "flat row did not collapse")
end

tests["a single pixel encodes as a run of one"] = function()
  eq(encode({ "00FF00" }, 1, 1), "1,00FF00", "single pixel encoding is wrong")
end

tests["alternating pixels encode as runs of one"] = function()
  eq(encode({ "FF0000", "00FF00", "FF0000", "00FF00" }, 4, 1),
     "1,FF0000;1,00FF00;1,FF0000;1,00FF00", "alternating pixels mis-encoded")
end

tests["runs break where the colour changes"] = function()
  eq(encode({ "FF0000", "FF0000", "FF0000", "000000" }, 4, 1),
     "3,FF0000;1,000000", "run boundary is wrong")
end

tests["rows are delimited and encoded independently"] = function()
  eq(encode({ "FF0000", "FF0000",
              "00FF00", "0000FF" }, 2, 2),
     "2,FF0000|1,00FF00;1,0000FF", "row delimiter or row contents wrong")
end

tests["a run does not continue across a row boundary"] = function()
  -- Same colour throughout: two rows of two, not one run of four. Rows encode
  -- separately so a caller can index by y without counting.
  eq(encode({ "FF0000", "FF0000",
              "FF0000", "FF0000" }, 2, 2),
     "2,FF0000|2,FF0000", "a run leaked across rows")
end

tests["a single column encodes as one run per row"] = function()
  eq(encode({ "FF0000", "FF0000", "FF0000" }, 1, 3),
     "1,FF0000|1,FF0000|1,FF0000", "single column mis-encoded")
end

tests["a zero-area region encodes as an empty string"] = function()
  eq(encode({}, 0, 0), "", "zero-area region produced output")
  eq(encode({}, 4, 0), "", "zero height produced output")
  eq(encode({}, 0, 4), "", "zero width produced output")
end

return tests
