#!/usr/bin/env python3
"""Install the generated LoopBar icon in a macOS .app bundle before signing."""

from __future__ import annotations

import argparse
import plistlib
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Path to LoopBar.app")
    parser.add_argument(
        "--icon",
        type=Path,
        default=Path("Assets/AppIcon.icns"),
        help="Source .icns file (default: Assets/AppIcon.icns)",
    )
    args = parser.parse_args()

    contents = args.bundle / "Contents"
    info_path = contents / "Info.plist"
    resources = contents / "Resources"
    if not info_path.is_file():
        raise FileNotFoundError(f"Missing bundle Info.plist: {info_path}")
    if not args.icon.is_file():
        raise FileNotFoundError(f"Missing icon asset: {args.icon}")

    resources.mkdir(exist_ok=True)
    shutil.copy2(args.icon, resources / "AppIcon.icns")

    with info_path.open("rb") as file:
        info = plistlib.load(file)
    info["CFBundleIconFile"] = "AppIcon"
    with info_path.open("wb") as file:
        plistlib.dump(info, file, sort_keys=False)


if __name__ == "__main__":
    main()
