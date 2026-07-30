#!/usr/bin/env python3
"""
Build the Aseprite extension bundle.

    python scripts/build_extension.py

An `.aseprite-extension` file is a zip archive containing `package.json` and
the scripts it references. `plugin/` is the only source of truth for those
files — never edit a copy inside Aseprite's extensions directory, because the
two drift apart silently.
"""

from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PLUGIN_DIR = REPO_ROOT / "plugin"
DIST_DIR = REPO_ROOT / "dist"
BUNDLE_NAME = "aseprite-mcp.aseprite-extension"

# Everything Aseprite needs, and nothing else.
BUNDLED_FILES = ("package.json", "main.lua")


def build(dist_dir: Path = DIST_DIR) -> Path:
    """Zip `plugin/` into `<dist_dir>/aseprite-mcp.aseprite-extension`."""
    missing = [name for name in BUNDLED_FILES if not (PLUGIN_DIR / name).is_file()]
    if missing:
        raise FileNotFoundError(
            f"missing from {PLUGIN_DIR}: {', '.join(missing)}"
        )

    # Fail loudly on a malformed manifest here rather than having Aseprite
    # reject the bundle with no explanation.
    manifest_path = PLUGIN_DIR / "package.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for key in ("name", "version", "contributes"):
        if key not in manifest:
            raise ValueError(f"{manifest_path} has no '{key}' key")

    dist_dir.mkdir(parents=True, exist_ok=True)
    bundle = dist_dir / BUNDLE_NAME

    with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in BUNDLED_FILES:
            # Store flat: Aseprite expects package.json at the archive root.
            archive.write(PLUGIN_DIR / name, arcname=name)

    return bundle


def main() -> int:
    try:
        bundle = build()
    except (FileNotFoundError, ValueError, json.JSONDecodeError) as exc:
        print(f"build failed: {exc}", file=sys.stderr)
        return 1

    size_kb = bundle.stat().st_size / 1024
    print(f"built {bundle.relative_to(REPO_ROOT)} ({size_kb:.1f} KiB)")
    for name in BUNDLED_FILES:
        print(f"  + {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
