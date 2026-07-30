-- Tests for the shape tools' `fill` parameter.
--
-- resolve_shape_tool is pure: it maps a shape and a fill flag onto the tool id
-- string app.useTool expects, without calling useTool, which exists only inside
-- the editor. The handler passes the id straight through, so the mapping is
-- testable here and only the one-line useTool call is not.
--
-- The filled variants are separate tool ids rather than a parameter on one tool
-- — `filled_rectangle` fills with nothing else supplied — so this mapping is the
-- whole of the fill decision, which is why it is worth pinning.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")
local eq, throws = h.eq, h.throws

local plugin = h.plugin()
local resolve = plugin.resolve_shape_tool

local tests = {}

tests["fill true selects the filled variant"] = function()
  eq(resolve("rect", true), "filled_rectangle", "filled rect did not map")
  eq(resolve("ellipse", true), "filled_ellipse", "filled ellipse did not map")
end

tests["fill false selects the outline variant"] = function()
  eq(resolve("rect", false), "rectangle", "outlined rect did not map")
  eq(resolve("ellipse", false), "ellipse", "outlined ellipse did not map")
end

tests["an omitted fill defaults to the outline"] = function()
  -- The schema defaults fill to false, but a caller can leave it out entirely
  -- and the decoder yields nil. Defaulting to filled would paint over work the
  -- caller could not see was at risk.
  eq(resolve("rect", nil), "rectangle", "nil fill did not default to outline")
  eq(resolve("ellipse", nil), "ellipse", "nil fill did not default to outline")
end

tests["matching is case-insensitive"] = function()
  eq(resolve("RECT", true), "filled_rectangle", "uppercase RECT rejected")
  eq(resolve("Ellipse", false), "ellipse", "mixed-case Ellipse rejected")
end

tests["an unknown shape is rejected, naming the accepted values"] = function()
  throws(function() resolve("triangle", false) end,
         "invalid shape: triangle", "unknown shape was accepted")
  throws(function() resolve("triangle", false) end,
         "expected rect or ellipse", "error did not name the accepted shapes")
end

tests["a near-miss spelling is rejected rather than guessed"] = function()
  -- useTool raises on a bad id too, but its message does not name what the
  -- caller passed, so guessing here would cost the caller the diagnosis.
  throws(function() resolve("rectangle", false) end,
         "invalid shape", "the useTool id was accepted as a shape name")
  throws(function() resolve("circle", true) end,
         "invalid shape", "circle was silently accepted as an ellipse")
  throws(function() resolve("square", false) end,
         "invalid shape", "square was silently accepted as a rect")
end

tests["a non-string shape is rejected, not concatenated into a crash"] = function()
  throws(function() resolve(4, false) end,
         "invalid shape: 4", "a number was accepted as a shape")
  throws(function() resolve(nil, false) end,
         "invalid shape: nil", "nil was accepted as a shape")
end

tests["line is not a shape this resolver handles"] = function()
  -- draw_line passes the "line" id as a literal: it takes two endpoints rather
  -- than a bounding box, and has no filled variant to choose between.
  throws(function() resolve("line", false) end,
         "invalid shape: line", "line leaked into the fill mapping")
end

return tests
