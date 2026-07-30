#!/usr/bin/env python3
"""
Build the extension bundle and install it into the local Aseprite extensions
directory — the development shortcut for "open the bundle with Aseprite".

    python scripts/install_plugin.py

Restart Aseprite afterwards; it loads extensions only at startup.

Set ASEPRITE_EXTENSIONS_DIR to override the location if your Aseprite keeps
its configuration somewhere non-standard.
"""

from __future__ import annotations

import json
import os
import sys
import zipfile
from pathlib import Path

from build_extension import BUNDLED_FILES, PLUGIN_DIR, build

# Aseprite records what it unpacked so it can uninstall cleanly. Match that
# format so an extension installed by this script can still be removed from
# Aseprite's own preferences UI.
INFO_FILE = "__info.json"


def extensions_dir() -> Path:
    """The per-user Aseprite extensions directory for this platform."""
    override = os.environ.get("ASEPRITE_EXTENSIONS_DIR")
    if override:
        return Path(override)

    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        if not appdata:
            raise RuntimeError("APPDATA is not set; use ASEPRITE_EXTENSIONS_DIR")
        return Path(appdata) / "Aseprite" / "extensions"

    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Aseprite" / "extensions"

    return Path.home() / ".config" / "aseprite" / "extensions"


def _remove_stale(target: Path, keep: set[str]) -> list[str]:
    """
    Delete files a previous install left behind that this bundle no longer
    ships. Driven by the recorded manifest rather than wiping the directory,
    so nothing outside our own install is ever removed.
    """
    info_path = target / INFO_FILE
    if not info_path.is_file():
        return []

    try:
        previous = json.loads(info_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        # An unreadable manifest is not a licence to delete the directory.
        print(f"warning: {info_path} is not valid JSON; leaving old files in place",
              file=sys.stderr)
        return []

    removed = []
    for name in previous.get("installedFiles", []):
        if name in keep or name == INFO_FILE:
            continue
        stale = target / name
        if stale.is_file():
            stale.unlink()
            removed.append(name)
    return removed


def install() -> Path:
    bundle = build()

    manifest = json.loads((PLUGIN_DIR / "package.json").read_text(encoding="utf-8"))
    target = extensions_dir() / manifest["name"]

    keep = set(BUNDLED_FILES)
    if target.exists():
        for name in _remove_stale(target, keep):
            print(f"  - {name} (no longer bundled)")

    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(bundle) as archive:
        archive.extractall(target)

    (target / INFO_FILE).write_text(
        json.dumps({"installedFiles": list(BUNDLED_FILES)}),
        encoding="utf-8",
    )

    return target


def main() -> int:
    try:
        target = install()
    except (FileNotFoundError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"install failed: {exc}", file=sys.stderr)
        return 1

    print(f"installed to {target}")
    for name in BUNDLED_FILES:
        print(f"  + {name}")
    print("\nRestart Aseprite to load the new version.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
