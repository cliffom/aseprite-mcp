"""Entry point for `python -m aseprite_mcp` and the `aseprite-mcp` console script."""

from __future__ import annotations

import asyncio
import sys

from .server import main as _serve
from .server import resolve_port


def main() -> None:
    """Run the WebSocket bridge and the MCP stdio transport until interrupted."""
    # Resolved before the event loop starts so a misconfigured port fails with
    # one line rather than a traceback out of asyncio.run.
    try:
        port = resolve_port()
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2) from None

    try:
        asyncio.run(_serve(port))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
