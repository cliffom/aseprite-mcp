# Lua sandbox probe — task 3.1

Open question from `proposal.md`: *"Whether the plugin can read an environment
variable at all is unverified. Aseprite's Lua sandbox may not expose
`os.getenv`."*

**Answer: `os.getenv` is exposed and works.** The plugin reads the environment
directly; the `plugin/package.json` constant fallback described in Decision 4 is
not needed.

## Method

`aseprite.exe -b --script probe.lua` against the local build
(`C:\Users\ADMIN\Documents\aseprite\build\bin\aseprite.exe`), with
`ASEPRITE_MCP_PROBE=hello-from-env` set in the launching shell.

## Output

```
=== ColorMode ===
ColorMode.RGB = 0
ColorMode.GRAYSCALE = 1
ColorMode.INDEXED = 2
ColorMode.TILEMAP = 4
ColorMode.Grayscale = nil
ColorMode.Indexed = nil
=== app.version ===
type(app.version)  = userdata
tostring(app.version) = 1.0-dev
fields: major=1 minor=0 patch=0 prereleaseLabel=dev
app.apiVersion = 40
=== os / environment ===
type(os) = table
os fields: clock, date, difftime, execute, exit, getenv, remove, rename,
           setlocale, time, tmpname
type(os.getenv) = function
os.getenv('ASEPRITE_MCP_PROBE') -> ok=true value=hello-from-env
os.getenv('APPDATA') -> ok=true value=C:\Users\ADMIN\AppData\Roaming
```

## What else this settled

- **`ColorMode` keys are upper-case.** `ColorMode.Grayscale` is `nil`;
  `ColorMode.GRAYSCALE` is `1`. `resolve_color_mode` therefore returns the
  upper-case key, and `create_sprite` indexes the enum with it (task 2.1).
- **`app.version` is userdata, not a string.** The JSON encoder has no case for
  userdata and would send `null`, so the handshake sends `tostring(app.version)`
  (task 2.3).

## Caveat

Probed against one self-built `1.0-dev` binary on Windows. `os.getenv` is
standard Lua that Aseprite has not removed, so it is unlikely to vary by
platform — but a packaged release build was not available here to confirm.
