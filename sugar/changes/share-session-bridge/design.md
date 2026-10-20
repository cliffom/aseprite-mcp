# Share session bridge — design

## Architecture

Each `aseprite-mcp` process serves stdio and connects to `/clients` on the
configured loopback WebSocket port. A detached `python -m aseprite_mcp --bridge
<port>` child owns that port. The existing plugin continues to connect at `/`.
The bridge keeps image rendering and temporary-file cleanup in its process.

## Interface contract

The bridge greets frontends with `{"type":"aseprite-mcp-bridge","protocol":1}`.
Frontends send `{id, tool, params}` using UUIDs; replies are `{id, result}` with
`result` serialized from `CallToolResult`. Tool definitions and plugin traffic
remain unchanged. The internal bridge protocol version changes when its wire
contract or tool semantics become incompatible.

Discovery waits up to five seconds, spawning only on connection refusal. Bind
competition elects one child; incompatible services fail clearly and are never
terminated. Each child writes to a uniquely created temporary log file whose
path the launching frontend reports on stderr. Stdout stays exclusive to MCP.
Windows uses detached process flags; POSIX uses a new session.

## Decisions

- Share one bridge per configured port without changing client configuration.
- Serialize individual calls with an asyncio lock; start the ten-second editor
  timeout after acquiring it. Multi-call sequences may interleave.
- After the final frontend disconnects, exit after 60 seconds, waiting for any
  dispatched calls to finish. Plugin connections alone do not prevent exit.
- Cancel queued calls for disconnected frontends; finish dispatched calls and
  discard their results. Always clean up canvas temporary files.
- Return errors on disconnect and reconnect for subsequent calls. Never replay
  an uncertain mutation. Keep second-editor rejection.

## Edge cases

Simultaneous launches may create losing children, which exit on address-in-use.
Existing legacy servers require a one-time stop before upgrading. Malformed
frontend requests close with code 1008. Queued calls have no editor timeout
until dispatched. A plugin reconnect does not change frontend connections.
All sessions share active sprite, layer, frame, selection, and undo history.

## Test plan

Use real loopback sockets and two real stdio processes with a fake plugin to
verify routing, serialization, process independence, launch races, recreation,
idle lifetime, protocol failures, editor reconnection and image cleanup. Run
both repository suites. Live two-Codex/editor verification remains manual.
