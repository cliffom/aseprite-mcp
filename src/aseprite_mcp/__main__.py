"""Entry point for `python -m aseprite_mcp` and the `aseprite-mcp` console script."""

from __future__ import annotations

import argparse
import asyncio
import sys

from .server import main as _serve
from .server import PORT_ENV_VAR, resolve_port


def main() -> None:
    """Run a stdio frontend, or the internal detached bridge process."""
    parser = argparse.ArgumentParser(description="MCP frontend for a shared Aseprite bridge")
    parser.add_argument("--bridge", type=int, metavar="PORT", help=argparse.SUPPRESS)
    args = parser.parse_args()
    # Resolved before the event loop starts so a misconfigured port fails with
    # one line rather than a traceback out of asyncio.run.
    try:
        port = resolve_port() if args.bridge is None else resolve_port({PORT_ENV_VAR: str(args.bridge)})
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2) from None

    try:
        if args.bridge is not None:
            from .transport import bridge_main

            asyncio.run(bridge_main(port))
        else:
            asyncio.run(_serve(port))
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(2) from None
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
