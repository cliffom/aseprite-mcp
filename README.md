# aseprite-mcp

An [MCP](https://modelcontextprotocol.io) server that lets an AI assistant draw
in [Aseprite](https://www.aseprite.org/) — live, in the real editor, on your
canvas.

<p align="center">
  <img src="output/clawd.png" width="192" alt="A 32x32 pixel-art fox drawn by Claude through aseprite-mcp" style="image-rendering: pixelated">
</p>

<p align="center">
  <em>32×32, drawn by Claude in four tool calls.</em>
</p>

## Install

Two pieces: the **server** (Python, talks to your assistant) and the **plugin**
(Lua, lives inside Aseprite). You need both. Aseprite 1.3 or newer.

### 1. The server

Point your MCP client at `uvx` — there is nothing to install ahead of time.

Claude Code:

```bash
claude mcp add aseprite -- uvx aseprite-mcp
```

Claude Desktop, or any client with a JSON config:

```json
{
  "mcpServers": {
    "aseprite": {
      "command": "uvx",
      "args": ["aseprite-mcp"]
    }
  }
}
```

### 2. The plugin

Download `aseprite-mcp.aseprite-extension` from the
[latest release](https://github.com/giangdvdotdev/aseprite-mcp/releases), then
double-click it — or add it from **Edit → Preferences → Extensions → Add
Extension**.

**Restart Aseprite.** Extensions load only at startup. Aseprite's console
(**View → Console**) prints `[MCP] Connected.` once the bridge is up. Either end
can start first; the plugin retries until the server is there and reconnects on
its own afterwards.

### From a clone

```bash
git clone https://github.com/giangdvdotdev/aseprite-mcp.git
cd aseprite-mcp
pip install -e ".[dev]"
python scripts/install_plugin.py    # build + install the plugin, then restart Aseprite
```

## Usage

Open Aseprite and ask:

- *"Draw me a 32×32 pixel-art fox."*
- *"Make it blink — duplicate the frame, close the eyes, 120ms each."*
- *"Export the spritesheet to ~/art/fox-sheet.png."*

Thirty tools, all acting on Aseprite's active sprite: drawing (pixels, batches,
lines, rects, ellipses, flood fill, erase), reading back (canvas image, pixels,
regions, layers, selection), undo and redo, frames, open sprites, and PNG or
spritesheet export.

**→ [Full tool reference](docs/TOOLS.md)**

## Configuration

The bridge runs on `127.0.0.1:9876`. To move it, set `ASEPRITE_MCP_PORT` for
**both** ends — nothing negotiates the port, and if only one side changes they
never meet:

```json
"env": { "ASEPRITE_MCP_PORT": "9877" }
```

Aseprite reads its environment at launch, so set the variable before starting
the editor. [Details per platform](docs/TROUBLESHOOTING.md#setting-the-port).

## Troubleshooting

Nearly everything is one of three things: Aseprite is not running, the plugin
was not installed or Aseprite was not restarted after installing it, or the two
ends are on different ports.

**→ [Troubleshooting guide](docs/TROUBLESHOOTING.md)** — every error message the
tools produce, and what to do about it.

## Security

The WebSocket listener is **unauthenticated**. It binds `127.0.0.1` only, so it
is not reachable from other machines, but any process on your own machine can
connect while the server is running and drive Aseprite through it. `export_png`,
`save_sprite`, and `export_spritesheet` write to whatever absolute path they are
given, overwriting what is there. If that is not acceptable in your environment,
do not run the server.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Both test suites are fast and neither
needs Aseprite running:

```bash
pytest                    # server
lua tests/lua/run.lua     # plugin
```

## License

[MIT](LICENSE).
