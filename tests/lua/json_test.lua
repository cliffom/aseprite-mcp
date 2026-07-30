-- Tests for the command protocol's pure halves.
--
-- Parsing itself is Aseprite's: json.decode exists only inside the editor, so
-- it cannot be exercised here. What is testable is everything around it —
-- to_plain, which copies the JsonObj userdata json.decode returns into a plain
-- table, and normalize_command, which decides whether the result is a command
-- at all. Plus the encoder, which stayed hand-rolled.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")
local eq, is_true = h.eq, h.is_true

local plugin = h.plugin()
local normalize = plugin.normalize_command
local to_plain  = plugin.to_plain

local tests = {}

-- ── normalize_command ─────────────────────────────────────────────────────

tests["a well-formed command normalizes to id, tool and params"] = function()
  local cmd = normalize({
    id     = "abc-123",
    tool   = "draw_pixels_batch",
    params = { pixels = "0,0,FF0000;1,1,00FF00" },
  })
  eq(cmd.id, "abc-123", "id lost")
  eq(cmd.tool, "draw_pixels_batch", "tool lost")
  eq(cmd.params.pixels, "0,0,FF0000;1,1,00FF00", "params payload lost")
end

tests["a command without an id is rejected"] = function()
  eq(normalize({ tool = "draw_pixel", params = {} }), nil,
     "command without an id was accepted")
end

tests["a command without a tool is rejected"] = function()
  eq(normalize({ id = "abc-123", params = {} }), nil,
     "command without a tool was accepted")
end

tests["a non-string id is rejected"] = function()
  eq(normalize({ id = 42, tool = "draw_pixel" }), nil,
     "numeric id was accepted")
  eq(normalize({ id = "abc", tool = 42 }), nil,
     "numeric tool was accepted")
end

tests["absent params become an empty table, not nil"] = function()
  local cmd = normalize({ id = "abc-123", tool = "get_sprite_info" })
  is_true(type(cmd.params) == "table", "params is not a table")
  eq(next(cmd.params), nil, "params is not empty")
end

tests["non-table params are rejected"] = function()
  eq(normalize({ id = "abc", tool = "draw_pixel", params = "x=1" }), nil,
     "string params were accepted")
end

tests["a decoded value that is not a table is rejected"] = function()
  -- `null` is the one input json.decode accepts without raising.
  eq(normalize(nil), nil, "nil was accepted")
  eq(normalize("draw_pixel"), nil, "a bare string was accepted")
  eq(normalize(7), nil, "a bare number was accepted")
end

-- ── to_plain ──────────────────────────────────────────────────────────────

tests["integral floats become integers"] = function()
  -- json.decode returns every number as a float, so 5 arrives as 5.0 and
  -- concatenates as "5.0" — which would show up in "pixel drawn at 5.0,5.0".
  local p = to_plain({ x = 5.0, y = -3.0 })
  eq(tostring(p.x), "5", "5.0 was not narrowed to an integer")
  eq(tostring(p.y), "-3", "-3.0 was not narrowed to an integer")
end

tests["genuine fractions are left alone"] = function()
  eq(to_plain({ scale = 1.5 }).scale, 1.5, "a fraction was mangled")
end

tests["strings, booleans and nested values survive the copy"] = function()
  local p = to_plain({
    pixels = "0,0,FF0000;1,1,00FF00",
    flag   = true,
    nested = { deep = { n = 2.0 } },
    arr    = { 10.0, 20.0, 30.0 },
  })
  eq(p.pixels, "0,0,FF0000;1,1,00FF00", "delimited payload mangled")
  eq(p.flag, true, "boolean mangled")
  eq(tostring(p.nested.deep.n), "2", "nested value lost")
  eq(#p.arr, 3, "array length lost")
  eq(tostring(p.arr[2]), "20", "array element lost")
end

tests["an empty container copies to an empty table"] = function()
  local p = to_plain({})
  is_true(type(p) == "table", "empty container did not copy to a table")
  eq(next(p), nil, "empty container gained keys")
end

-- ── json_encode ───────────────────────────────────────────────────────────

tests["encoding round-trips a string with quotes and backslashes"] = function()
  eq(plugin.json_encode([[a"b\c]]), [["a\"b\\c"]], "encoder escaping is wrong")
  eq(plugin.json_encode(7), "7", "integer encoding is wrong")
  is_true(plugin.json_encode(true) == "true", "boolean encoding is wrong")
end

tests["a table with no keys encodes as an object, not an array"] = function()
  -- An empty table satisfies both branches of the array check. A structured
  -- result with no fields is still a result, so it has to encode as {}.
  eq(plugin.json_encode({}), "{}", "empty table encoded as an array")
end

tests["a populated array still encodes as an array"] = function()
  eq(plugin.json_encode({ 1, 2, 3 }), "[1,2,3]", "array encoding is wrong")
end

return tests
