# Share session bridge

**Created:** 2026-10-20
**Capabilities:** mcp-server, distribution

## Why

Every stdio session currently binds the plugin port. The first session owns it,
preventing subsequent sessions from connecting to the same editor.

## What

Keep the existing client command while automatically starting or reusing a
background bridge. Independent stdio frontends share one editor connection.
The approved conversational plan supplies the requirements; no idea one-pager
was created.

## Impact

- **Adds:** concurrent MCP sessions, automatic bridge discovery and startup.
- **Changes:** the editor connection outlives the first session; calls serialize.
- **Out of scope:** isolated editor state, multiple editors, sequence-level locks,
  tool changes, version bumps, and publishing a release.

## Open questions

None. Shared access and automatic startup were explicitly selected.
