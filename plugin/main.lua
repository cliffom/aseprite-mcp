-- aseprite-mcp/plugin/main.lua
-- WebSocket client bridge: connects Aseprite to the Python MCP server.
-- Protocol: receives JSON commands, dispatches to handler, sends JSON responses.

local PLUGIN_VER   = "0.6.0"
local DEFAULT_PORT = 9876

-- Both ends of the bridge read ASEPRITE_MCP_PORT and must agree on it; nothing
-- negotiates the port, so a mismatch presents as "Aseprite not connected".
-- Aseprite's Lua sandbox does expose os.getenv — verified against a live editor.
--
-- An unusable value falls back to the default with a warning rather than
-- erroring: raising here would abort loading the extension, and the server
-- refuses to start on the same bad value anyway, so there is nothing to miss.
local function resolve_port()
  local raw = os.getenv("ASEPRITE_MCP_PORT")
  if not raw or raw == "" then return DEFAULT_PORT end

  local port = tonumber(raw)
  if not port or port ~= math.floor(port) or port < 1 or port > 65535 then
    print("[MCP] ASEPRITE_MCP_PORT is not a port number: " .. tostring(raw)
          .. " - falling back to " .. DEFAULT_PORT)
    return DEFAULT_PORT
  end

  return math.floor(port)
end

local WS_URL = "ws://127.0.0.1:" .. resolve_port()

-- Raise a validation message with no position information attached.
--
-- Lua's error() prepends "<file>:<line>: " at the default level, so a handler
-- calling error("no active sprite") reaches the caller as
-- "…/extensions/aseprite-mcp/main.lua:405: no active sprite". These strings are
-- a contract — docs/TROUBLESHOOTING.md quotes them verbatim, and the
-- prefix both breaks that match and leaks an absolute local path across the
-- bridge. Level 0 suppresses it.
--
-- Deliberate messages only. A genuine runtime fault still raises through plain
-- error() and keeps its file and line, which is what makes it debuggable.
local function fail(msg)
  error(msg, 0)
end

-- ─────────────────────────────────────────────
-- Minimal JSON encoder
-- ─────────────────────────────────────────────
local function json_encode(val)
  local t = type(val)
  if val == nil then
    return "null"
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    -- Integers print without decimal; floats keep precision.
    if val == math.floor(val) then
      return string.format("%d", val)
    else
      return string.format("%g", val)
    end
  elseif t == "string" then
    -- Escape special characters.
    local escaped = val
      :gsub('\\', '\\\\')
      :gsub('"',  '\\"')
      :gsub('\n', '\\n')
      :gsub('\r', '\\r')
      :gsub('\t', '\\t')
    return '"' .. escaped .. '"'
  elseif t == "table" then
    -- Detect array (consecutive integer keys starting at 1).
    local is_array = true
    local max_i    = 0
    for k, _ in pairs(val) do
      if type(k) ~= "number" or k ~= math.floor(k) or k < 1 then
        is_array = false
        break
      end
      if k > max_i then max_i = k end
    end
    -- max_i > 0 excludes the empty table, which satisfies both branches. It
    -- encodes as an object: a structured result with no fields is still a
    -- result, and `[]` would make the server hand the caller a list.
    if is_array and max_i == #val and max_i > 0 then
      local parts = {}
      for i = 1, #val do
        parts[i] = json_encode(val[i])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(val) do
        if type(k) == "string" then
          parts[#parts + 1] = json_encode(k) .. ":" .. json_encode(v)
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    -- Fallback: stringify unsupported types as null.
    return "null"
  end
end

-- ─────────────────────────────────────────────
-- Decoded-value normalisation
-- Aseprite's json.decode returns a `JsonObj` userdata, not a table: indexing,
-- pairs() on objects, and #/ipairs() on arrays all work, but table primitives
-- such as next() reject it. Copying into a plain table at the boundary means
-- nothing downstream has to know that. Pure, so it is testable outside the
-- editor where the json namespace does not exist.
-- ─────────────────────────────────────────────
local function to_plain(value)
  local t = type(value)

  if t == "number" then
    -- json.decode returns every number as a float, so 5 arrives as 5.0 and
    -- concatenates as "5.0". The pattern decoder this replaced used tonumber(),
    -- which gave 5 — and the tools' messages ("pixel drawn at 5,5") show it.
    if value == math.floor(value) then
      return math.tointeger(value) or value
    end
    return value
  end

  if t ~= "table" and t ~= "userdata" then
    return value
  end

  -- Objects and arrays are the same type here, so one of them has to be
  -- identified by behaviour. pairs() is the discriminator: it enumerates a
  -- JSON object and yields *nothing* for a JSON array.
  --
  -- # is not the discriminator, however tempting: on a JsonObj object it
  -- returns the number of keys, not 0, so branching on it reads every command
  -- as a 3-element array of nils. Verified the hard way.
  local out = {}
  local empty = true
  for k, v in pairs(value) do
    out[k] = to_plain(v)
    empty = false
  end

  if empty then
    -- An array, or an empty container of either kind — which copy to the same
    -- thing, so the ambiguity never has to be resolved.
    for i = 1, #value do out[i] = to_plain(value[i]) end
  end

  return out
end

-- Validate a decoded command into {id, tool, params}, or nil if it is not one.
-- Split from parsing so it stays pure: json.decode exists only inside Aseprite,
-- and this is the half with the logic worth testing.
local function normalize_command(obj)
  if type(obj) ~= "table" then return nil end
  if type(obj.id) ~= "string" or type(obj.tool) ~= "string" then return nil end

  local params = obj.params
  if params == nil then params = {} end
  if type(params) ~= "table" then return nil end

  return { id = obj.id, tool = obj.tool, params = params }
end

local function json_decode_command(s)
  -- Returns {id, tool, params} or nil on failure.
  --
  -- json.decode raises on malformed input rather than returning nil (verified —
  -- see sugar/changes/add-canvas-readback/notes/editor-probe.md), so the call is
  -- wrapped rather than checked. The normalisation runs inside the same pcall
  -- because the one input that parses without raising, a bare `null`, decodes to
  -- a value that is not safe to index.
  local ok, cmd = pcall(function()
    return normalize_command(to_plain(json.decode(s)))
  end)
  if not ok then return nil end
  return cmd
end

-- ─────────────────────────────────────────────
-- Colour helper: parse "#RRGGBB" → r, g, b
-- ─────────────────────────────────────────────
local function parse_color(hex)
  if not hex then return nil, "missing color" end
  local h = hex:match("^#?(%x%x%x%x%x%x)$")
  if not h then return nil, "invalid color: " .. tostring(hex) end
  local r = tonumber(h:sub(1,2), 16)
  local g = tonumber(h:sub(3,4), 16)
  local b = tonumber(h:sub(5,6), 16)
  return r, g, b
end

-- ─────────────────────────────────────────────
-- Batch pixel parsing
-- Decodes the "x1,y1,RRGGBB;x2,y2,RRGGBB;..." batch encoding into a list of
-- {x, y, r, g, b} entries. Pure: no canvas access, so it is unit-testable
-- outside Aseprite. Entries that do not match the encoding exactly are
-- skipped and counted, so a typo is visible to the caller instead of
-- silently dropping pixels.
-- ─────────────────────────────────────────────
local function parse_pixels(data)
  local entries = {}
  local skipped = 0

  for entry in (data .. ";"):gmatch("([^;]+);") do
    local xs, ys, hex = entry:match("^(%d+),(%d+),(%x%x%x%x%x%x)$")
    if xs then
      entries[#entries + 1] = {
        x = tonumber(xs),
        y = tonumber(ys),
        r = tonumber(hex:sub(1, 2), 16),
        g = tonumber(hex:sub(3, 4), 16),
        b = tonumber(hex:sub(5, 6), 16),
      }
    else
      skipped = skipped + 1
    end
  end

  return entries, skipped
end

-- ─────────────────────────────────────────────
-- Colour mode resolution
-- Maps the `mode` parameter onto a key of Aseprite's ColorMode enum, accepting
-- any casing and defaulting to RGB when the caller omits it. Returns the key
-- rather than the enum value so it stays pure: ColorMode exists only inside the
-- editor, and the tests run in a bare interpreter.
-- ─────────────────────────────────────────────
local COLOR_MODE_KEYS = {
  rgb       = "RGB",
  grayscale = "GRAYSCALE",
  indexed   = "INDEXED",
}

local function resolve_color_mode(name)
  if name == nil or name == "" then return "RGB" end

  local key = COLOR_MODE_KEYS[tostring(name):lower()]
  if not key then
    fail("invalid color mode: " .. tostring(name)
          .. " (expected RGB, Grayscale, or Indexed)")
  end
  return key
end

-- ─────────────────────────────────────────────
-- Shape tool resolution
-- Maps a shape and a fill flag onto the id app.useTool expects. The filled
-- variants are separate tools, not a parameter on one — `filled_rectangle`
-- fills with nothing else supplied (verified; see the change's
-- notes/editor-probe.md) — so choosing the id is the whole of the fill
-- decision, and it is the one branch in this pair worth pinning in a test.
-- Pure: returns the id string, so it runs outside the editor.
-- ─────────────────────────────────────────────
local SHAPE_TOOLS = {
  rect    = { outline = "rectangle", filled = "filled_rectangle" },
  ellipse = { outline = "ellipse",   filled = "filled_ellipse"   },
}

local function resolve_shape_tool(shape, fill)
  local ids = SHAPE_TOOLS[tostring(shape):lower()]
  if not ids then
    -- useTool raises on an unknown id too, but with a message that does not
    -- name what the caller passed.
    fail("invalid shape: " .. tostring(shape) .. " (expected rect or ellipse)")
  end
  return fill and ids.filled or ids.outline
end

-- ─────────────────────────────────────────────
-- Pixel value resolution
-- getPixel hands back a packed integer whose meaning depends on the colour
-- mode: RGBA bytes low-to-high in RGB mode, value-then-alpha in grayscale, and
-- a bare palette index in indexed mode. Resolving here — with arithmetic rather
-- than app.pixelColor — keeps it pure, so the three branches are unit-tested
-- outside the editor. The byte order is verified: graya(128, 255) reads back as
-- 65408, and an opaque black Color has rgbaPixel 4278190080.
-- ─────────────────────────────────────────────
local function resolve_pixel(value, colorMode, palette)
  if colorMode == "rgb" then
    return string.format("#%02X%02X%02X",
      value % 256, (value // 256) % 256, (value // 65536) % 256),
      (value // 16777216) % 256

  elseif colorMode == "grayscale" then
    local v = value % 256
    return string.format("#%02X%02X%02X", v, v, v), (value // 256) % 256

  elseif colorMode == "indexed" then
    -- The index is meaningless on its own; the palette is what makes it a
    -- colour, so an indexed sprite reads back the same way an RGB one does.
    local c = palette:getColor(value)
    return string.format("#%02X%02X%02X", c.red, c.green, c.blue), c.alpha
  end

  fail("unsupported color mode: " .. tostring(colorMode))
end

-- ─────────────────────────────────────────────
-- Region encoding
-- Row-major run-length encoding of a flat list of "RRGGBB" strings: rows
-- delimited by "|", runs within a row as "count,RRGGBB" delimited by ";".
-- Pixel art is mostly flat runs, so a 64x64 read of four-colour art comes back
-- in a few hundred bytes where a per-pixel dump is 24 KB. The delimiters mirror
-- draw_pixels_batch so callers meet one encoding idiom rather than two.
-- Pure: no canvas access, so it is unit-testable outside Aseprite.
-- ─────────────────────────────────────────────
local function encode_region(pixels, width, height)
  if width < 1 or height < 1 then return "" end

  local rows = {}
  for row = 1, height do
    local base  = (row - 1) * width
    local parts = {}
    local color, run = nil, 0

    for col = 1, width do
      local c = pixels[base + col]
      if c == color then
        run = run + 1
      else
        if color then parts[#parts + 1] = run .. "," .. color end
        color, run = c, 1
      end
    end
    if color then parts[#parts + 1] = run .. "," .. color end

    rows[row] = table.concat(parts, ";")
  end

  return table.concat(rows, "|")
end

-- ─────────────────────────────────────────────
-- Frame duration conversion
-- Duration crosses the bridge in milliseconds; Frame.duration is seconds.
-- Aseprite clamps it to a 16-bit millisecond count, so 1..65535 ms is the whole
-- usable range — below it a value silently becomes 1 ms, above it 65535 ms.
--
-- THE `+ 0.5` IS LOAD-BEARING. Aseprite keeps the duration as an integer
-- millisecond count and converts the seconds it is handed through a narrower
-- float, which for many values lands a hair under the integer and truncates
-- down: the obvious `ms / 1000` loses a millisecond on 741 of the 65535 valid
-- inputs (1001 ms reads back as 1000). Nudging half a millisecond up puts the
-- value safely inside the target integer, round-trips all 65535 exactly, and
-- never overshoots — including at both clamp boundaries. Verified by sweeping
-- the full range against a live editor; see the change's notes/editor-probe.md.
--
-- Named rather than inlined precisely because `(ms + 0.5) / 1000` reads like a
-- typo. Pure, so tests/lua pins both directions outside the editor.
-- ─────────────────────────────────────────────
local MIN_FRAME_MS = 1
local MAX_FRAME_MS = 65535

local function ms_to_duration(ms)
  return (ms + 0.5) / 1000
end

local function duration_to_ms(duration)
  return math.floor(duration * 1000 + 0.5)
end

-- ─────────────────────────────────────────────
-- Enum naming
-- `colorMode` and `blendMode` are bare numbers on the objects, and a reverse
-- map built by iterating the enum is non-deterministic: BlendMode has aliases
-- sharing a value (NORMAL and SRC_OVER are both 3). Resolving through a fixed,
-- ordered list of names picks the same one every time, and still reads the
-- value from the enum so a renumbering cannot silently mislabel anything.
-- ─────────────────────────────────────────────
local COLOR_MODE_NAMES = { "RGB", "GRAYSCALE", "INDEXED", "TILEMAP" }

-- The modes Aseprite offers on a layer, in the order its own menu lists them.
local BLEND_MODE_NAMES = {
  "NORMAL", "DARKEN", "MULTIPLY", "COLOR_BURN", "LIGHTEN", "SCREEN",
  "COLOR_DODGE", "ADDITION", "OVERLAY", "SOFT_LIGHT", "HARD_LIGHT",
  "DIFFERENCE", "EXCLUSION", "SUBTRACT", "DIVIDE", "HSL_HUE",
  "HSL_SATURATION", "HSL_COLOR", "HSL_LUMINOSITY",
}

local function enum_name(enum, names, value)
  if value == nil then return nil end
  for _, key in ipairs(names) do
    if enum[key] == value then return key:lower() end
  end
  return tostring(value)
end

local function color_mode_name(value) return enum_name(ColorMode, COLOR_MODE_NAMES, value) end
local function blend_mode_name(value) return enum_name(BlendMode,  BLEND_MODE_NAMES, value) end

-- Read one pixel of a cel in sprite coordinates. Cel image space is not sprite
-- space — the same cel.position offset draw_pixels_batch applies in reverse.
local function read_cel_pixel(spr, cel, x, y)
  local img = cel.image
  local px  = x - cel.position.x
  local py  = y - cel.position.y

  -- Inside the sprite but outside this cel: the layer holds nothing there, so
  -- it reads as transparent rather than as an error.
  if px < 0 or py < 0 or px >= img.width or py >= img.height then
    return "#000000", 0
  end

  return resolve_pixel(img:getPixel(px, py), color_mode_name(img.colorMode),
                       spr.palettes[1])
end

-- ─────────────────────────────────────────────
-- Read limits
-- ─────────────────────────────────────────────

-- A 10s TOOL_TIMEOUT is the whole budget for a call, and get_region reads one
-- pixel at a time in Lua. 4096 pixels (64x64) stays well inside it, and an
-- error naming the limit is easier to act on than a timeout. It also bounds
-- what a single read can spend of the caller's context.
local MAX_REGION_PIXELS = 4096

-- Bounds the PNG the model receives: a 128x128 sprite at 8x is 1024x1024.
local MAX_SCALE = 8

-- ─────────────────────────────────────────────
-- Tool handlers
-- Each handler receives params table.
-- Returns a result on success — a string for the write tools, a table for the
-- read tools, which dispatch encodes as JSON — or raises a Lua error on
-- failure. The pcall wrapper in dispatch turns that error into {ok=false}.
-- ─────────────────────────────────────────────
local handlers = {}

-- create_sprite(width, height, mode)
handlers.create_sprite = function(params)
  local w = tonumber(params.width)  or 32
  local h = tonumber(params.height) or 32
  if w < 1 or h < 1 then fail("invalid dimensions") end
  local mode = resolve_color_mode(params.mode)
  local spr = Sprite(w, h, ColorMode[mode])
  app.activeSprite = spr
  return "created " .. w .. "x" .. h .. " " .. mode
end

-- draw_pixel(x, y, color)
handlers.draw_pixel = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x = tonumber(params.x)
  local y = tonumber(params.y)
  if not x or not y then fail("x and y are required") end

  local r, g, b = parse_color(params.color)
  if not r then fail(g) end

  -- Use the pencil tool so it auto-creates a cel on new layers and
  -- handles sprite-relative coordinates correctly (cel.image coords differ).
  app.useTool{
    tool   = "pencil",
    color  = Color{ r=r, g=g, b=b, a=255 },
    layer  = app.activeLayer,
    frame  = app.activeFrame,
    points = { Point(x, y) },
  }

  app.refresh()
  return "pixel drawn at " .. x .. "," .. y
end

-- fill_area(x, y, color)
handlers.fill_area = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x = tonumber(params.x)
  local y = tonumber(params.y)
  if not x or not y then fail("x and y are required") end

  local r, g, b = parse_color(params.color)
  if not r then fail(g) end

  app.transaction(function()
    app.useTool{
      tool    = "paint_bucket",
      color   = Color{ r=r, g=g, b=b, a=255 },
      cel     = app.activeCel,
      layer   = app.activeLayer,
      point   = Point(x, y),
    }
  end)

  app.refresh()
  return "filled at " .. x .. "," .. y
end

-- add_layer(name)
handlers.add_layer = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local name = params.name or ("Layer " .. (#spr.layers + 1))

  local layer
  app.transaction(function()
    layer = spr:newLayer()
    layer.name = name
  end)
  app.activeLayer = layer

  app.refresh()
  return layer.name
end

-- draw_pixels_batch(pixels)
-- pixels is encoded as "x1,y1,RRGGBB;x2,y2,RRGGBB;..." to avoid nested JSON parsing
-- Uses cel.image:drawPixel directly — much faster than app.useTool per pixel,
-- and avoids the transaction/useTool nesting conflict.
handlers.draw_pixels_batch = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local data = params.pixels
  if not data or data == "" then fail("pixels is required") end

  local entries, skipped = parse_pixels(data)

  local count = 0
  app.transaction(function()
    local layer = app.activeLayer
    local frame = app.activeFrame

    -- Create a full-size cel on this layer if one doesn't exist yet.
    local cel = layer:cel(frame.frameNumber)
    if not cel then
      local img = Image(spr.width, spr.height, spr.colorMode)
      cel = spr:newCel(layer, frame, img, Point(0, 0))
    end

    local img = cel.image
    local ox  = cel.position.x
    local oy  = cel.position.y

    for _, e in ipairs(entries) do
      local px = e.x - ox
      local py = e.y - oy
      if px >= 0 and py >= 0 and px < img.width and py < img.height then
        img:drawPixel(px, py, app.pixelColor.rgba(e.r, e.g, e.b, 255))
        count = count + 1
      end
    end
  end)

  app.refresh()

  local msg = "drew " .. count .. " pixels"
  if skipped > 0 then
    msg = msg .. " (" .. skipped .. " malformed entries skipped)"
  end
  return msg
end

-- ─────────────────────────────────────────────
-- Shape tools
-- All three go through app.useTool rather than rasterising in Lua: Aseprite's
-- own line stepping and ellipse rasterisation already match what a user gets
-- drawing interactively. It auto-creates the cel and clips to the canvas, so
-- none of these handlers carries bounds logic — a shape entirely off-canvas
-- paints nothing and still succeeds, the same way draw_pixels_batch clips.
-- `points` holds two opposite corners, INCLUSIVE at both ends; the bounding-box
-- tools convert with width - 1. Verified — see the change's notes/editor-probe.md.
-- ─────────────────────────────────────────────

-- draw_line(x1, y1, x2, y2, color)
handlers.draw_line = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x1 = tonumber(params.x1)
  local y1 = tonumber(params.y1)
  local x2 = tonumber(params.x2)
  local y2 = tonumber(params.y2)
  if not x1 or not y1 or not x2 or not y2 then
    fail("x1, y1, x2 and y2 are required")
  end

  local r, g, b = parse_color(params.color)
  if not r then fail(g) end

  app.transaction(function()
    app.useTool{
      tool   = "line",
      color  = Color{ r=r, g=g, b=b, a=255 },
      layer  = app.activeLayer,
      frame  = app.activeFrame,
      points = { Point(x1, y1), Point(x2, y2) },
    }
  end)

  app.refresh()
  -- A zero-length line is one pixel, not an error — the tool handles it.
  return "drew line from " .. x1 .. "," .. y1 .. " to " .. x2 .. "," .. y2
end

-- draw_rect(x, y, width, height, color, fill)
handlers.draw_rect = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x = tonumber(params.x)
  local y = tonumber(params.y)
  local w = tonumber(params.width)
  local h = tonumber(params.height)
  if not x or not y or not w or not h then
    fail("x, y, width and height are required")
  end
  if w < 1 or h < 1 then fail("width and height must be at least 1") end

  local r, g, b = parse_color(params.color)
  if not r then fail(g) end

  -- Resolved before the transaction so an unknown shape cannot raise inside it.
  local tool = resolve_shape_tool("rect", params.fill)

  app.transaction(function()
    app.useTool{
      tool   = tool,
      color  = Color{ r=r, g=g, b=b, a=255 },
      layer  = app.activeLayer,
      frame  = app.activeFrame,
      points = { Point(x, y), Point(x + w - 1, y + h - 1) },
    }
  end)

  app.refresh()
  return "drew rect at " .. x .. "," .. y .. " " .. w .. "x" .. h
end

-- draw_ellipse(x, y, width, height, color, fill)
-- The ellipse is inscribed in the same inclusive bounding box draw_rect uses,
-- so the two tools take identical coordinates and differ only in the shape.
handlers.draw_ellipse = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x = tonumber(params.x)
  local y = tonumber(params.y)
  local w = tonumber(params.width)
  local h = tonumber(params.height)
  if not x or not y or not w or not h then
    fail("x, y, width and height are required")
  end
  if w < 1 or h < 1 then fail("width and height must be at least 1") end

  local r, g, b = parse_color(params.color)
  if not r then fail(g) end

  local tool = resolve_shape_tool("ellipse", params.fill)

  app.transaction(function()
    app.useTool{
      tool   = tool,
      color  = Color{ r=r, g=g, b=b, a=255 },
      layer  = app.activeLayer,
      frame  = app.activeFrame,
      points = { Point(x, y), Point(x + w - 1, y + h - 1) },
    }
  end)

  app.refresh()
  return "drew ellipse at " .. x .. "," .. y .. " " .. w .. "x" .. h
end

-- erase_area(x, y, width, height)
-- Writes transparency straight into the cel image rather than using useTool's
-- eraser: the interactive eraser is mode-dependent — on a background layer it
-- paints the background colour instead of clearing — and its brush and opacity
-- answer to tool settings this bridge has no way to set. A direct write has one
-- behaviour everywhere, including on a background layer, where it reads back
-- alpha 0 and composites transparent. Verified — see notes/editor-probe.md.
handlers.erase_area = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x = tonumber(params.x)
  local y = tonumber(params.y)
  local w = tonumber(params.width)
  local h = tonumber(params.height)
  if not x or not y or not w or not h then
    fail("x, y, width and height are required")
  end
  if w < 1 or h < 1 then fail("width and height must be at least 1") end

  -- Clip to the sprite, then cap the clipped area — a caller names a rectangle
  -- in four integers here, so the per-pixel Lua loop needs the same bound
  -- get_region has, against the same 10s budget.
  local x0 = math.max(x, 0)
  local y0 = math.max(y, 0)
  local x1 = math.min(x + w, spr.width)
  local y1 = math.min(y + h, spr.height)
  local cw = math.max(x1 - x0, 0)
  local ch = math.max(y1 - y0, 0)

  local area = cw * ch
  if area > MAX_REGION_PIXELS then
    fail("region of " .. area .. " pixels exceeds the "
          .. MAX_REGION_PIXELS .. "-pixel limit")
  end

  -- No cel means the layer holds nothing here, which is already what erasing
  -- would leave. Creating one purely to leave it transparent has no observable
  -- effect, so unlike draw_pixels_batch this does not auto-create.
  local cel = app.activeLayer and app.activeLayer:cel(app.activeFrame.frameNumber)
  if not cel then return "erased 0 pixels" end

  local count = 0
  app.transaction(function()
    local img = cel.image
    local ox  = cel.position.x
    local oy  = cel.position.y
    -- Packs to 0, which is also the default spr.transparentColor, so this
    -- clears in indexed mode too — the same packing draw_pixels_batch relies on.
    local clear = app.pixelColor.rgba(0, 0, 0, 0)

    for py = y0, y1 - 1 do
      for px = x0, x1 - 1 do
        local ix = px - ox
        local iy = py - oy
        if ix >= 0 and iy >= 0 and ix < img.width and iy < img.height then
          img:drawPixel(ix, iy, clear)
          count = count + 1
        end
      end
    end
  end)

  app.refresh()
  return "erased " .. count .. " pixels"
end

-- get_canvas_image(path, scale)
-- Writes the composited sprite — visible layers only, active frame — to a path
-- the server owns and deletes; the server base64-encodes it into an image
-- result. `path` is never caller-supplied in practice.
--
-- saveCopyAs is deliberately not used: on a multi-frame sprite it writes
-- <name>1.png, <name>2.png, … and never the path it was given, which would
-- leave the server reading a file that does not exist. Rendering into an Image
-- and saving that writes exactly one file, on single- and multi-frame sprites
-- alike.
--
-- The render is `img:drawSprite`, not `Image(spr, frame)` — see export_png for
-- why. This tool used Image(spr, app.activeFrame.frameNumber) from the day it
-- shipped, which meant it always returned FRAME 1 however the active frame had
-- been moved; on a single-frame sprite the two are the same picture, so it went
-- unnoticed until export_png grew an explicit frame parameter and the frame
-- could finally be seen to be ignored. Verified — see notes/editor-probe.md.
handlers.get_canvas_image = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local path = params.path
  if not path or path == "" then fail("path is required") end

  local scale = tonumber(params.scale) or 1
  if scale ~= math.floor(scale) or scale < 1 or scale > MAX_SCALE then
    fail("scale must be between 1 and " .. MAX_SCALE)
  end

  local img = Image(spr.width, spr.height, spr.colorMode)
  img:drawSprite(spr, app.activeFrame.frameNumber)
  if scale > 1 then
    -- "nearest" keeps pixel art crisp. It is a literal, never caller input:
    -- an unrecognised method silently falls back instead of erroring.
    img:resize{
      width  = spr.width  * scale,
      height = spr.height * scale,
      method = "nearest",
    }
  end
  img:saveAs(path)

  return { path = path, width = img.width, height = img.height }
end

-- get_sprite_info()
handlers.get_sprite_info = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  return {
    width       = spr.width,
    height      = spr.height,
    colorMode   = color_mode_name(spr.colorMode),
    frames      = #spr.frames,
    layers      = #spr.layers,
    activeLayer = app.activeLayer and app.activeLayer.name or nil,
    activeFrame = app.activeFrame and app.activeFrame.frameNumber or nil,
    paletteSize = #spr.palettes[1],
    filename    = spr.filename,
    isModified  = spr.isModified,
  }
end

-- list_layers()
-- Group layers are reported and then descended into, so a layer nested in a
-- group is still listed — otherwise a model would be told a layer it can draw
-- to does not exist. stackIndex is the position within the parent, which is
-- what Aseprite means by it.
local function layer_entries(layers, frame_number, out)
  for _, layer in ipairs(layers) do
    local has_cel = false
    if not layer.isGroup then
      has_cel = layer:cel(frame_number) ~= nil
    end

    out[#out + 1] = {
      name         = layer.name,
      stackIndex   = layer.stackIndex,
      opacity      = layer.opacity,
      blendMode    = blend_mode_name(layer.blendMode),
      isVisible    = layer.isVisible,
      isEditable   = layer.isEditable,
      isGroup      = layer.isGroup,
      isBackground = layer.isBackground,
      hasCel       = has_cel,
    }

    if layer.isGroup then
      layer_entries(layer.layers, frame_number, out)
    end
  end
  return out
end

handlers.list_layers = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  return layer_entries(spr.layers, app.activeFrame.frameNumber, {})
end

-- get_pixel(x, y)
handlers.get_pixel = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x = tonumber(params.x)
  local y = tonumber(params.y)
  if not x or not y then fail("x and y are required") end
  if x < 0 or y < 0 or x >= spr.width or y >= spr.height then
    fail("(" .. x .. ", " .. y .. ") is outside the sprite")
  end

  local cel = app.activeLayer and app.activeLayer:cel(app.activeFrame.frameNumber)
  if not cel then fail("no cel at the active layer and frame") end

  local color, alpha = read_cel_pixel(spr, cel, x, y)
  return { x = x, y = y, color = color, alpha = alpha }
end

-- get_region(x, y, width, height)
handlers.get_region = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local x = tonumber(params.x)
  local y = tonumber(params.y)
  local w = tonumber(params.width)
  local h = tonumber(params.height)
  if not x or not y or not w or not h then
    fail("x, y, width and height are required")
  end
  if w < 1 or h < 1 then fail("width and height must be at least 1") end

  -- Clip to the sprite, then cap what is actually about to be read: a request
  -- that overhangs the canvas should read the part that exists rather than be
  -- refused for pixels that were never there.
  local x0 = math.max(x, 0)
  local y0 = math.max(y, 0)
  local x1 = math.min(x + w, spr.width)
  local y1 = math.min(y + h, spr.height)
  if x1 <= x0 or y1 <= y0 then
    fail("(" .. x .. ", " .. y .. ") is outside the sprite")
  end

  local cw, ch = x1 - x0, y1 - y0
  local area = cw * ch
  if area > MAX_REGION_PIXELS then
    fail("region of " .. area .. " pixels exceeds the "
          .. MAX_REGION_PIXELS .. "-pixel limit")
  end

  local cel = app.activeLayer and app.activeLayer:cel(app.activeFrame.frameNumber)
  if not cel then fail("no cel at the active layer and frame") end

  local pixels = {}
  for py = y0, y1 - 1 do
    for px = x0, x1 - 1 do
      local color = read_cel_pixel(spr, cel, px, py)
      pixels[#pixels + 1] = color:sub(2)  -- runs carry no '#', as in draw_pixels_batch
    end
  end

  return {
    x        = x0,
    y        = y0,
    width    = cw,
    height   = ch,
    encoding = "rle",
    rows     = encode_region(pixels, cw, ch),
  }
end

-- get_selection()
handlers.get_selection = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local sel = spr.selection
  local b   = sel.bounds
  return {
    isEmpty = sel.isEmpty,
    x       = b.x,
    y       = b.y,
    width   = b.width,
    height  = b.height,
  }
end

-- ─────────────────────────────────────────────
-- Undo
-- app.undo() and app.redo() never raise — not on an empty stack, not with no
-- sprite open, not called ten times past the bottom — so "nothing to undo" has
-- to be read off undoHistory *before* the call, or the tool would report
-- "undone" having done nothing. undoHistory is a snapshot table holding exactly
-- undoSteps and redoSteps, so it is read fresh rather than held.
-- Verified — see the change's notes/editor-probe.md.
--
-- These still require an active sprite even though app.undo() tolerates its
-- absence: the step count comes from the sprite, and a tool that silently
-- succeeded with nothing open would be the only one here that does.
-- ─────────────────────────────────────────────

-- undo()
handlers.undo = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  if spr.undoHistory.undoSteps == 0 then return "nothing to undo" end

  app.undo()
  app.refresh()
  return "undone"
end

-- redo()
handlers.redo = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  if spr.undoHistory.redoSteps == 0 then return "nothing to redo" end

  app.redo()
  app.refresh()
  return "redone"
end

-- get_undo_depth()
handlers.get_undo_depth = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local history = spr.undoHistory
  return {
    undoSteps = history.undoSteps,
    redoSteps = history.redoSteps,
  }
end

-- ─────────────────────────────────────────────
-- Frames
-- Every other tool here works on app.activeFrame and none of them can change
-- it, so a sprite is single-frame in practice until set_active_frame exists.
-- These five make the frame axis addressable; nothing else changes.
--
-- Frame numbers are 1-based positions, re-read on every call and never held:
-- delete_frame renumbers everything after the deleted frame, so a number is a
-- position at a moment, not an identity. Same contract as list_layers'
-- stackIndex.
-- ─────────────────────────────────────────────

-- Resolve a 1-based frame number from params, or raise naming the valid range.
local function resolve_frame_number(spr, value, label)
  local count = #spr.frames
  local n = tonumber(value)
  if not n or n ~= math.floor(n) or n < 1 or n > count then
    fail(label .. " must be between 1 and " .. count)
  end
  return math.floor(n)
end

-- add_frame(duplicate, after)
-- The two Aseprite calls do NOT agree on where the new frame goes:
-- newFrame(n) inserts the copy at n + 1, newEmptyFrame(n) inserts the blank at
-- n. So "insert after N" is newFrame(N) for one and newEmptyFrame(N + 1) for
-- the other, and both then land at N + 1. Verified — see the change's
-- notes/editor-probe.md.
--
-- Neither return value names the new frame: newFrame hands back the *source*
-- FrameObj, whose frameNumber reads N and whose fields write through to frame
-- N. The position is computed here instead.
--
-- The range check is load-bearing rather than defensive: newFrame(99) on a
-- 5-frame sprite does not raise, it pads the sprite out to 100 frames.
handlers.add_frame = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local after
  if params.after == nil then
    after = app.activeFrame.frameNumber
  else
    after = resolve_frame_number(spr, params.after, "after")
  end

  -- Absent means duplicate: continuing from the previous frame is the common
  -- case, and an empty frame is the deliberate one.
  local duplicate = params.duplicate
  if duplicate == nil then duplicate = true end

  local added = after + 1
  app.transaction(function()
    if duplicate then
      spr:newFrame(after)
    else
      spr:newEmptyFrame(added)
    end
  end)

  app.refresh()

  if duplicate then
    return "added frame " .. added .. " (duplicated frame " .. after .. ")"
  end
  return "added empty frame " .. added
end

-- delete_frame(frame)
-- The only-frame guard has to be ours. Aseprite does not refuse the last
-- frame: deleteFrame(1) on a one-frame sprite returns normally and leaves the
-- sprite exactly as it was, so without this check the tool would report
-- "deleted frame 1" of a frame that is still there. Verified — see the
-- change's notes/editor-probe.md.
--
-- Frames after the deleted one renumber down by one, and app.activeFrame
-- follows the frame it was showing rather than its number, so there is nothing
-- to compensate for here.
handlers.delete_frame = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local frame = resolve_frame_number(spr, params.frame, "frame")
  if #spr.frames == 1 then fail("cannot delete the only frame") end

  app.transaction(function()
    spr:deleteFrame(frame)
  end)

  app.refresh()
  return "deleted frame " .. frame
end

-- set_frame_duration(frame, duration)
-- duration is milliseconds. The range check is not decoration: Aseprite clamps
-- silently at both ends, so a caller asking for 0 would be told the duration
-- was set while the frame actually holds 1 ms.
handlers.set_frame_duration = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local frame = resolve_frame_number(spr, params.frame, "frame")

  local ms = tonumber(params.duration)
  if not ms or ms ~= math.floor(ms)
     or ms < MIN_FRAME_MS or ms > MAX_FRAME_MS then
    fail("duration must be between " .. MIN_FRAME_MS .. " and "
          .. MAX_FRAME_MS .. " milliseconds")
  end
  ms = math.floor(ms)

  app.transaction(function()
    spr.frames[frame].duration = ms_to_duration(ms)
  end)

  app.refresh()
  return "frame " .. frame .. " duration set to " .. ms .. "ms"
end

-- set_active_frame(frame)
-- The tool the rest of the change exists for: every draw and read handler
-- already targets app.activeFrame, so moving it is the whole of what was
-- missing. Setting it to the frame that is already active is not special-cased
-- — it reaches the same state.
handlers.set_active_frame = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local frame = resolve_frame_number(spr, params.frame, "frame")

  app.frame = spr.frames[frame]

  app.refresh()
  return "active frame set to " .. frame
end

-- list_frames()
-- Uncapped, unlike get_region: a frame count is dozens, not the thousands the
-- pixel cap exists to bound. list_layers has no cap either.
handlers.list_frames = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local active = app.activeFrame and app.activeFrame.frameNumber

  local out = {}
  for i, frame in ipairs(spr.frames) do
    out[i] = {
      frameNumber = i,
      durationMs  = duration_to_ms(frame.duration),
      isActive    = i == active,
    }
  end
  return out
end

-- ─────────────────────────────────────────────
-- Files and sprites
-- Every other tool here works on app.activeSprite, and until now the only way
-- to get one was create_sprite. These five open existing art, write it back,
-- and make the active-sprite pointer movable the way set_active_frame made the
-- frame pointer movable — nothing else changes.
--
-- Two Aseprite calls in this section FAIL WITHOUT RAISING: app.open returns nil
-- and Sprite:saveAs returns normally having written nothing, each printing its
-- real reason to a console Lua cannot read. So both are checked by their
-- effect, not by pcall. Verified — see the change's notes/editor-probe.md.
-- ─────────────────────────────────────────────

-- open_file(path)
handlers.open_file = function(params)
  local path = params.path
  if not path or path == "" then fail("path is required") end

  -- nil covers every failure kind — missing file, unreadable content, an
  -- extension with no decoder — and Aseprite's own explanation goes to the
  -- console. Only one distinction is worth reconstructing here, because only
  -- one is something the caller can act on: is the file there or not?
  local spr = app.open(path)
  if not spr then
    if not app.fs.isFile(path) then fail("no file at " .. path) end
    fail("could not open " .. path .. " — Aseprite cannot read that file")
  end

  -- app.open has already made it active; a failed open leaves the previous
  -- active sprite untouched, so there is no state to unwind above either.
  app.refresh()
  return "opened " .. path .. " (" .. spr.width .. "x" .. spr.height
         .. ", " .. #spr.frames .. " frames)"
end

-- save_sprite(path)
-- Writes .ase/.aseprite ONLY, and the restriction is not conservatism.
-- saveAs infers the format from the extension, and handed a still-image format
-- on a multi-frame sprite it spreads the frames across as many files,
-- incrementing whatever number is already in the base name: a 3-frame sprite
-- saved to "run3.png" writes run3.png, run4.png AND run5.png. That is the same
-- misbehaviour export_png is being fixed for in this change, and passing the
-- caller's extension through would reintroduce it here while reporting
-- "saved to <path>". .ase/.aseprite are also the only formats that keep the
-- layers, frames and tags this tool exists to preserve — .gif and .webp hold
-- every frame in one file but flatten the rest. Flat output is export_png's and
-- export_spritesheet's job.
--
-- The extension is checked BEFORE the call rather than diagnosed after it: a
-- failed saveAs does not raise, and it clears isModified on the way past, which
-- would leave unsaved work flagged as safe for close_sprite to discard.
-- Verified — see the change's notes/editor-probe.md.
local SAVE_EXTENSIONS = { ase = true, aseprite = true }

handlers.save_sprite = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local path = params.path
  if path == nil or path == "" then
    -- A sprite that has never been saved reports a bare name — "Sprite" — not
    -- an empty string, so the test is whether the filename carries a directory.
    if app.fs.filePath(spr.filename) == "" then
      fail("path is required — this sprite has not been saved before")
    end
    path = spr.filename
  end

  -- fileExtension keeps the caller's casing and drops the dot.
  if not SAVE_EXTENSIONS[app.fs.fileExtension(path):lower()] then
    fail("save_sprite writes .ase or .aseprite only — use export_png or "
          .. "export_spritesheet for flat image formats")
  end

  local previous = spr.filename
  spr:saveAs(path)

  -- Validation cannot foresee an unwritable directory or a locked file, and
  -- those fail just as silently. The file itself is the only proof.
  if not app.fs.isFile(path) then
    spr.filename = previous
    fail("could not save to " .. path)
  end

  return "saved to " .. path
end

-- list_sprites()
-- app.sprites is ordered NEWEST FIRST and is stable: changing the active
-- sprite does not reorder it, but opening or creating one pushes it to index 1
-- and shifts everything down, and closing removes and shifts. So an index is a
-- position at a moment, not an identity — the same contract list_layers'
-- stackIndex and the frame numbers carry. Reported in app.sprites' own order so
-- set_active_sprite indexes the same list a caller just read.
--
-- Uncapped, like list_layers and list_frames: open documents are a handful.
--
-- This is the one handler whose list can genuinely be empty — every other tool
-- errors "no active sprite" long before it gets here — so it is also the one
-- place json_encode's empty-table rule shows: nothing open encodes as `{}`,
-- not `[]`. Documented rather than worked around; see CLAUDE.md.
handlers.list_sprites = function(params)
  local active = app.activeSprite

  local out = {}
  for i, spr in ipairs(app.sprites) do
    out[i] = {
      index      = i,
      filename   = spr.filename,
      width      = spr.width,
      height     = spr.height,
      isModified = spr.isModified,
      isActive   = spr == active,
    }
  end
  return out
end

-- set_active_sprite(index)
-- The tool the rest of this section exists for, exactly as set_active_frame was
-- for the frame tools: every draw and read handler already targets
-- app.activeSprite, so moving it is the whole of what was missing.
--
-- Indexes app.sprites directly rather than matching a filename: two files with
-- the same basename in different directories are indistinguishable by name, and
-- an unsaved sprite has no name to match at all. list_sprites reports this same
-- order, and both re-read it every call — see its note on why the number is a
-- position rather than an identity.
handlers.set_active_sprite = function(params)
  local count = #app.sprites
  local n = tonumber(params.index)
  if not n or n ~= math.floor(n) or n < 1 or n > count then
    fail("index must be between 1 and " .. count)
  end

  local spr = app.sprites[math.floor(n)]
  app.sprite = spr

  app.refresh()
  return "active sprite set to " .. spr.filename
end

-- close_sprite(force)
-- The isModified guard is this bridge's, not Aseprite's: Sprite:close() takes
-- no force argument — it accepts and ignores one — and in a batch probe it
-- discards a modified sprite without a word. What a live editor does with a UI
-- attached is the open question, and the reason the default is to refuse: an
-- app.command-style confirmation dialog would block the socket for the full
-- 10s timeout and every call after it. Refusing means the bridge never finds
-- out the hard way.
--
-- WHAT BECOMES ACTIVE AFTER A CLOSE DIFFERS BETWEEN BATCH AND THE GUI. A
-- `-b --script` run leaves app.activeSprite nil even with other sprites still
-- open; a live editor promotes a survivor, because the UI has a focused tab and
-- batch has nothing to focus. So this reports what it actually finds rather
-- than asserting either — a message naming a survivor that is not there, or
-- claiming none when one is active, both mislead the next call. Verified both
-- ways — see notes/editor-probe.md.
handlers.close_sprite = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  if spr.isModified and not params.force then
    fail("sprite has unsaved changes — save_sprite first, or pass force=true")
  end

  -- Read before the close: touching a closed handle raises "Tried to access a
  -- deleted 'doc::Sprite'".
  local name = spr.filename
  spr:close()

  app.refresh()

  local remaining = #app.sprites
  if remaining == 0 then
    return "closed " .. name .. " (no sprites open)"
  end

  local active = app.activeSprite
  if active then
    return "closed " .. name .. " (" .. remaining
           .. " still open, now active: " .. active.filename .. ")"
  end
  return "closed " .. name .. " (" .. remaining
         .. " still open, none active — use set_active_sprite)"
end

-- export_png(path, frame)
-- Lives down here, below the frame section, because it range-checks `frame`
-- through resolve_frame_number — a local declared after the point this handler
-- used to sit at.
--
-- saveCopyAs is deliberately not used: on a multi-frame sprite it writes
-- <name>1.png, <name>2.png, … and never the path it was given. That was latent
-- while every sprite was single-frame and became reachable the moment the frame
-- tools shipped. Rendering into an Image and saving that writes exactly one
-- file, at the requested path, whatever the frame count.
--
-- THE RENDER IS `img:drawSprite(spr, frame)`, NOT `Image(spr, frame)`.
-- Image(sprite, frame) looks like the obvious call and is what this handler was
-- first written against, but it **ignores the frame argument entirely** and
-- always renders frame 1 — a number, a FrameObj, and moving app.frame first all
-- give frame 1's pixels. It does not raise on an out-of-range frame either,
-- which is what let it look like it worked. drawSprite honours the frame and
-- composites the same way: visible layers only, layer opacity applied,
-- untouched areas left transparent. Verified against a live editor — see the
-- change's notes/editor-probe.md. Do not "simplify" this back to Image(spr, f).
handlers.export_png = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local path = params.path
  if not path or path == "" then fail("path is required") end

  local frame
  if params.frame == nil then
    frame = app.activeFrame.frameNumber
  else
    frame = resolve_frame_number(spr, params.frame, "frame")
  end

  local img = Image(spr.width, spr.height, spr.colorMode)
  img:drawSprite(spr, frame)
  img:saveAs(path)

  -- Unchanged: the result is the path, as it has been since this tool existed.
  return path
end

-- export_spritesheet(path, columns)
-- A minimal wrapper, not a passthrough: one PNG, every frame, a grid the caller
-- steers with a column count and nothing else. ExportSpriteSheet's real surface
-- (padding, trim, extrude, tag and layer filtering, a JSON sidecar) is a dozen
-- interacting options for a feature whose common use needs one number.
--
-- `type` is REQUIRED and is passed as the enum value, not a string. Without it
-- every frame lands at 0,0 and `columns` is ignored entirely — the sheet comes
-- out one cell. A string works too, but an unrecognised one does not raise, it
-- degrades to that same one-cell sheet, so this is a literal and never caller
-- input for the same reason get_canvas_image's method="nearest" is.
--
-- Omitting dataFilename is what keeps the JSON sidecar off disk. Aseprite dumps
-- the metadata to View → Console instead; that is cosmetic, and supplying a
-- filename to silence it would write a file nobody asked for.
-- Verified — see the change's notes/editor-probe.md.
handlers.export_spritesheet = function(params)
  local spr = app.activeSprite
  if not spr then fail("no active sprite") end

  local path = params.path
  if not path or path == "" then fail("path is required") end

  -- Aseprite treats 0 as "unlimited" and clamps anything past the frame count,
  -- so neither end needs pre-clamping — but 0 meaning "one row of everything"
  -- is an encoding coincidence, not a contract worth exposing.
  local columns = tonumber(params.columns) or 1
  if columns ~= math.floor(columns) or columns < 1 then
    fail("columns must be at least 1")
  end
  columns = math.floor(columns)

  app.command.ExportSpriteSheet{
    ui              = false,
    type            = SpriteSheetType.ROWS,
    columns         = columns,
    textureFilename = path,
  }

  -- Like saveAs, an extension Aseprite cannot write produces no file and no
  -- error. The file itself is the only proof the export happened.
  if not app.fs.isFile(path) then
    fail("could not write " .. path .. " — Aseprite cannot write that format")
  end

  return "exported spritesheet to " .. path .. " (" .. spr.width .. "x"
         .. spr.height .. " per frame, " .. #spr.frames .. " frames, "
         .. columns .. " columns)"
end

-- ─────────────────────────────────────────────
-- WebSocket dispatch
-- ─────────────────────────────────────────────
local ws  -- forward declaration so onreceive closure can reference it

local function send(tbl)
  if ws then
    ws:sendText(json_encode(tbl))
  end
end

local function dispatch(raw)
  local cmd = json_decode_command(raw)
  if not cmd then
    -- Can't echo back an id if we couldn't parse one; log and drop.
    print("[MCP] Failed to parse command: " .. tostring(raw):sub(1, 120))
    return
  end

  local fn = handlers[cmd.tool]
  if not fn then
    send({ id = cmd.id, ok = false, error = "unknown tool: " .. cmd.tool })
    return
  end

  local ok, result = pcall(fn, cmd.params)
  if ok then
    -- A table travels as a nested JSON structure — send() runs it through
    -- json_encode — and the server turns it into JSON text for the caller.
    -- Every other type keeps the single-line string the write tools return.
    if type(result) ~= "table" then
      result = tostring(result or "ok")
    end
    send({ id = cmd.id, ok = true,  result = result })
  else
    -- result holds the error message when pcall returns false.
    send({ id = cmd.id, ok = false, error = tostring(result) })
  end
end

-- ─────────────────────────────────────────────
-- Entry point
-- ─────────────────────────────────────────────
local function connect()
  -- Keep status punctuation in ASCII so the editor's console does not need
  -- fallback fonts for our separators when laying out consecutive lines.
  print("[MCP] Connecting to " .. WS_URL .. " ...")

  ws = WebSocket{
    url = WS_URL,

    onreceive = function(msgType, data, err)

      -- msgType 1 = OPEN
      if msgType == 1 then
        print("[MCP] Connected.")
        -- app.version is userdata; tostring gives the display form ("1.3.7",
        -- "1.0-dev"). The JSON encoder has no case for userdata and would
        -- otherwise send null.
        send({
          type      = "handshake",
          version   = PLUGIN_VER,
          aseprite  = tostring(app.version),
        })

      -- msgType 0 = TEXT message
      elseif msgType == 0 then
        print("[MCP] RX: " .. tostring(data):sub(1, 200))
        dispatch(data)

      -- msgType 2 = CLOSE
      elseif msgType == 2 then
        -- Deliberately keep `ws`. Aseprite's WebSocket object retries on its
        -- own and fires OPEN again on the same handle; clearing it here left
        -- send() a permanent no-op, so the reconnection completed but no
        -- handshake or command reply was ever transmitted.
        -- Aseprite supplies an empty string when there is no error; unlike
        -- nil, that is truthy in Lua and must not add an empty error suffix.
        print("[MCP] Disconnected" .. (err and err ~= "" and (": " .. tostring(err)) or "."))
      end
    end,
  }

  -- Initiate the connection.
  ws:connect()
end

-- Run on script load, but only inside Aseprite: the `WebSocket` global exists
-- there and nowhere else. Loading this file in a bare Lua interpreter (as the
-- tests do) must have no side effects.
if WebSocket then
  connect()
  -- Return nothing. Aseprite tears down the script's Lua context when an
  -- extension script returns a value, which collects the onreceive closure:
  -- the socket still connects and retries, but no handshake or command reply
  -- is ever sent. Verified against a live editor — do not return a table here.
  return
end

-- Exported for tests, which load this file in a bare interpreter.
return {
  json_encode         = json_encode,
  to_plain            = to_plain,
  normalize_command   = normalize_command,
  json_decode_command = json_decode_command,
  parse_pixels        = parse_pixels,
  resolve_color_mode  = resolve_color_mode,
  resolve_shape_tool  = resolve_shape_tool,
  resolve_pixel       = resolve_pixel,
  encode_region       = encode_region,
  ms_to_duration      = ms_to_duration,
  duration_to_ms      = duration_to_ms,
  handlers            = handlers,
}
