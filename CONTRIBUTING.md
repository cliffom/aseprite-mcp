# Contributing

Thanks for taking a look. This is a small project — two moving parts and a
socket between them — so getting set up should take a few minutes.

## Layout

```
src/aseprite_mcp/     the MCP server (Python)
plugin/               the Aseprite plugin (Lua) — the only source of truth
scripts/              build and install the .aseprite-extension bundle
tests/                pytest suite for the server
tests/lua/            Lua suite for the plugin's pure functions
```

## Setup

```bash
git clone https://github.com/giangdvdotdev/aseprite-mcp.git
cd aseprite-mcp
make install
```

`make install` needs [Poetry](https://python-poetry.org/) 2.x. It creates a
project-local `.venv` and installs the package with its dev extras there;
nothing touches your global Python. Every other Python target runs inside that
venv via `poetry run`. Run `make` on its own to list the targets.

For the Lua tests you also need a **Lua 5.4** interpreter on `PATH`. No
LuaRocks, no `busted` — the runner is plain Lua on purpose.

| Platform | Install |
| --- | --- |
| Windows | `winget install DEVCOM.Lua` |
| macOS | `brew install lua` |
| Debian/Ubuntu | `sudo apt install lua5.4` |

## Running the tests

Both suites are fast and neither needs Aseprite running.

```bash
make test        # both suites
make test-py     # server: dispatch, timeouts, registry, drift
make test-lua    # plugin: JSON decoding, pixel parsing
```

Both must pass before a pull request. Each exits non-zero on failure, so they
drop straight into CI.

### What the tests cover

The Python suite exercises the dispatch path with a mocked WebSocket: request
UUIDs matched to replies, the 10-second timeout, disconnects, and errors coming
back from Aseprite. Two tests guard the contract rather than the behaviour —
one asserts the registered tool set, and one asserts that every tool the server
registers has a handler of the same name in `plugin/main.lua`. Add a tool
without a handler and the suite tells you, instead of Aseprite answering
`unknown tool` at runtime.

The Lua suite covers the pure functions in `plugin/main.lua`: the JSON
parameter decoder and `parse_pixels`. Anything touching `app`, `Sprite`, or
`Image` needs a real editor and is deliberately out of scope — those paths are
verified by hand.

### Writing a Lua test

A test file is any `tests/lua/*_test.lua` returning a table of name → function.
A function that returns without erroring has passed:

```lua
local here = debug.getinfo(1, "S").source:match("@(.*[/\\])") or "./"
local h = dofile(here .. "harness.lua")

local tests = {}

tests["it does the thing"] = function()
  h.eq(1 + 1, 2, "arithmetic is broken")
end

return tests
```

`harness.lua` gives you `eq`, `is_true`, `throws`, and `plugin()`, which loads
`plugin/main.lua` and returns its export table.

## Working on the plugin

Edit `plugin/main.lua`, never the copy inside Aseprite's extensions directory —
that copy is generated, and hand-editing it is how the two drifted apart in the
first place. To try a change in the real editor:

```bash
make install-plugin
```

Then restart Aseprite; extensions load only at startup.

`main.lua` loads cleanly in a bare Lua interpreter — it only opens a WebSocket
when Aseprite's `WebSocket` global exists — and it ends with an export table so
tests can reach its internals. Keep both properties when you change it.

That export table is returned **only** when the `WebSocket` global is absent.
Returning a value from an extension script makes Aseprite tear down the
script's Lua context: the socket still connects and even retries, but the
`onreceive` closure is gone, so no handshake or command reply is ever sent and
every tool call times out. The bare `return` inside the `if WebSocket` branch
is load-bearing — do not tidy it away.

## Manual verification

Anything involving the canvas needs a human. Before a release, at minimum:
start the server, start Aseprite, and confirm `create_sprite` followed by a
`draw_pixels_batch` produces the sprite you expect, then `export_png` writes it.

## Style

Match the file you are in. The Python is typed and uses `from __future__ import
annotations`; the Lua is `local`-scoped with aligned comment banners. Comments
explain why something is the way it is — the non-obvious constraint, not the
line beneath them.

## Versions

Three version strings have to agree:

- `version` in `pyproject.toml`
- `version` in `plugin/package.json`
- `PLUGIN_VER` in `plugin/main.lua`

Bump them together, then run `make check-versions` — it compares all three and
fails on a mismatch.
