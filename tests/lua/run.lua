-- Zero-dependency Lua test runner.
--
--   lua tests/lua/run.lua
--
-- Loads every *_test.lua in this directory. Each test file returns a table of
-- name -> function; a function that returns without erroring has passed.
-- Exits non-zero if anything fails, so CI can gate on it.

local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local is_windows = package.config:sub(1, 1) == "\\"

-- Lua has no directory listing in the standard library, and requiring LuaFileSystem
-- would defeat the point of a dependency-free runner. Ask the shell instead.
local function test_files()
  local command = is_windows
    and ('dir /b "' .. here:gsub("/", "\\") .. '*_test.lua" 2>nul')
    or  ("ls " .. here .. "*_test.lua 2>/dev/null")

  local pipe = assert(io.popen(command), "could not list " .. here)
  local names = {}
  for line in pipe:lines() do
    -- `dir /b` prints bare filenames; `ls` prints the path it was given.
    names[#names + 1] = line:match("([^/\\]+)$")
  end
  pipe:close()

  table.sort(names)
  return names
end

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local files = test_files()
if #files == 0 then
  io.stderr:write("no *_test.lua files found in " .. here .. "\n")
  os.exit(1)
end

local passed, failed = 0, 0

for _, file in ipairs(files) do
  print("── " .. file)

  local loaded, tests = pcall(dofile, here .. file)
  if not loaded then
    failed = failed + 1
    print("   FAIL  <could not load file>\n         " .. tostring(tests))
  elseif type(tests) ~= "table" then
    failed = failed + 1
    print("   FAIL  <file did not return a table of tests>")
  else
    for _, name in ipairs(sorted_keys(tests)) do
      local ok, err = pcall(tests[name])
      if ok then
        passed = passed + 1
        print("   ok    " .. name)
      else
        failed = failed + 1
        print("   FAIL  " .. name .. "\n         " .. tostring(err):gsub("\n", "\n         "))
      end
    end
  end
end

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
