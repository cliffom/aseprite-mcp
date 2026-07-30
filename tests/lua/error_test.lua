-- Error message formatting.
--
-- Validation messages are a contract: docs/TROUBLESHOOTING.md quotes them
-- verbatim, so a "<file>:<line>: " prefix in front of one both breaks that
-- match and leaks an absolute local path across the bridge. These guard the
-- `fail` helper that suppresses it — and the other half of the split, that a
-- genuine fault still carries the position that makes it locatable.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")
local p = h.plugin()

-- Plain-text find, so the ':%d' is spelled out rather than pattern-matched.
local function has_position(msg)
  return tostring(msg):find("main.lua:", 1, true) ~= nil
end

local function message_of(fn, ...)
  local args = table.pack(...)
  local ok, err = pcall(function() return fn(table.unpack(args, 1, args.n)) end)
  h.is_true(not ok, "expected the call to raise")
  return tostring(err)
end

return {
  ["a validation message carries no file:line prefix"] = function()
    local msg = message_of(p.resolve_shape_tool, "hexagon", false)
    h.is_true(not has_position(msg),
      "expected no position prefix, got: " .. msg)
  end,

  ["a validation message is exactly the text, nothing prepended"] = function()
    local msg = message_of(p.resolve_shape_tool, "hexagon", false)
    h.eq(msg, "invalid shape: hexagon (expected rect or ellipse)",
      "the message should stand alone")
  end,

  ["the colour-mode message is unprefixed too"] = function()
    local msg = message_of(p.resolve_color_mode, "cmyk")
    h.is_true(not has_position(msg),
      "expected no position prefix, got: " .. msg)
  end,

  ["the pixel-mode message is unprefixed too"] = function()
    local msg = message_of(p.resolve_pixel, 0, "nonsense")
    h.is_true(not has_position(msg),
      "expected no position prefix, got: " .. msg)
  end,

  -- The other half of the split. A real bug must stay locatable, so this
  -- asserts the position is still there rather than stripped everywhere.
  ["a genuine runtime fault keeps its file and line"] = function()
    -- `app` is nil outside Aseprite, so the handler faults on indexing it.
    local msg = message_of(p.handlers.undo, nil)
    h.is_true(has_position(msg),
      "a real fault should keep its position, got: " .. msg)
  end,
}
