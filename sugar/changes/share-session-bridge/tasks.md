## 1. Shared transport

- [x] 1.1 Separate editor dispatch from the stdio frontend.
- [x] 1.2 Implement bridge routing, serialization, and session disconnect cleanup.
- [x] 1.3 Implement detached startup, discovery, compatibility checks, and idle exit.
- [x] 1.4 Return explicit disconnect errors and preserve canvas file ownership.

## 2. Tests

- [x] 2.1 Add real stdio and loopback tests for multiple sessions and routing.
- [x] 2.2 Cover launch races, lifetime, reconnects, and protocol rejection.
- [x] 2.3 Verify image cleanup across success, failure, and disconnect.
- [x] 2.4 Run both repository test suites and inspect the final diff.

## 3. Docs

- [x] 3.1 Update setup, tool reference, troubleshooting, and agent guidance.

## Validation

- `make test LUA=/private/tmp/lua-5.4.8/src/lua`: 45 Python tests and 69 Lua tests pass.
- Lua 5.4.8 was built with POSIX support in `/private/tmp`; no system packages changed.
- `git diff --check` passes; CLI help and invalid bridge port behavior checked.
- Tests use real stdio subprocesses and loopback sockets with a fake editor.
- User confirmed the live two-session Aseprite test passes, including continued
  access after the first session closes. Windows process startup was not run.
