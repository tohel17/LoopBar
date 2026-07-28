#!/usr/bin/env python3
"""Install LoopBar icon assets into a macOS .app bundle before signing.

Copies AppIcon.icns for Finder/Dock, and when possible compiles Assets.car from
Assets.xcassets so Notification Center can resolve the app logo. Sets
CFBundleIconFile always, and CFBundleIconName only when Assets.car is present.
"""

from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def compile_assets_car(xcassets: Path, resources: Path, deployment_target: str) -> bool:
    """Compile Assets.car into resources. Returns True on success."""
    actool = shutil.which("actool") or "/usr/bin/actool"
    if not Path(actool).is_file():
        print("warning: actool not found; skipping Assets.car (notifications may show a blank icon)")
        return False

    with tempfile.TemporaryDirectory() as tmp:
        partial = Path(tmp) / "partial.plist"
        compile_dir = Path(tmp) / "out"
        compile_dir.mkdir()
        result = subprocess.run(
            [
                actool,
                str(xcassets),
                "--compile",
                str(compile_dir),
                "--platform",
                "macosx",
                "--minimum-deployment-target",
                deployment_target,
                "--app-icon",
                "AppIcon",
                "--output-partial-info-plist",
                str(partial),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print("warning: actool failed; skipping Assets.car")
            if result.stderr.strip():
                print(result.stderr.strip())
            if result.stdout.strip():
                print(result.stdout.strip())
            return False

        car = compile_dir / "Assets.car"
        if not car.is_file():
            print("warning: actool produced no Assets.car; skipping")
            return False

        shutil.copy2(car, resources / "Assets.car")
        return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Path to LoopBar.app")
    parser.add_argument(
        "--icon",
        type=Path,
        default=Path("Assets/AppIcon.icns"),
        help="Source .icns file (default: Assets/AppIcon.icns)",
    )
    parser.add_argument(
        "--xcassets",
        type=Path,
        default=Path("Assets/Assets.xcassets"),
        help="Asset catalog source (default: Assets/Assets.xcassets)",
    )
    parser.add_argument(
        "--deployment-target",
        default="14.0",
        help="macOS deployment target for actool (default: 14.0)",
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

    has_car = False
    if args.xcassets.is_dir() and (args.xcassets / "AppIcon.appiconset").is_dir():
        has_car = compile_assets_car(args.xcassets, resources, args.deployment_target)
    else:
        print(f"warning: missing asset catalog at {args.xcassets}; skipping Assets.car")

    with info_path.open("rb") as file:
        info = plistlib.load(file)
    info["CFBundleIconFile"] = "AppIcon"
    if has_car:
        info["CFBundleIconName"] = "AppIcon"
    else:
        info.pop("CFBundleIconName", None)
    with info_path.open("wb") as file:
        plistlib.dump(info, file, sort_keys=False)

    if has_car:
        print(f"Installed AppIcon.icns + Assets.car into {args.bundle}")
    else:
        print(f"Installed AppIcon.icns into {args.bundle} (no Assets.car)")


if __name__ == "__main__":
    main()
