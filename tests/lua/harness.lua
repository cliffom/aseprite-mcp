-- Assertions and plugin loading for the Lua test files.
-- Zero dependencies: usable from `lua tests/lua/run.lua` or by running a
-- single test file directly.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"

local M = {}

-- Load plugin/main.lua and return its export table. The plugin only opens a
-- WebSocket when the Aseprite `WebSocket` global exists, so this is safe.
function M.plugin()
  return dofile(here .. "../../plugin/main.lua")
end

function M.eq(actual, expected, label)
  if actual ~= expected then
    error(string.format(
      "%s\n    expected: %s\n    actual:   %s",
      label, tostring(expected), tostring(actual)
    ), 2)
  end
end

function M.is_true(value, label)
  if value ~= true then
    error(label .. "\n    expected: true\n    actual:   " .. tostring(value), 2)
  end
end

-- Assert that fn errors, and that the message contains `pattern` (plain text).
function M.throws(fn, pattern, label)
  local ok, err = pcall(fn)
  if ok then
    error(label .. "\n    expected an error, but the call succeeded", 2)
  end
  if pattern and not tostring(err):find(pattern, 1, true) then
    error(string.format(
      "%s\n    expected error containing: %s\n    actual error:             %s",
      label, pattern, tostring(err)
    ), 2)
  end
end

return M
