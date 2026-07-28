#!/usr/bin/env python3
"""Install LoopBar icon assets into a macOS .app bundle before signing.

Notification Center uses the LEFT banner icon from the app bundle
(Assets.car + CFBundleIconName), not from UNNotificationAttachment (which
appears on the RIGHT).

On macOS 26+, prefer a Liquid Glass Icon Composer document (Assets/AppIcon.icon).
A flat PNG appiconset alone lands in Tahoe "icon jail" (blank left banner icon).
"""

from __future__ import annotations

import argparse
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path


def resolve_actool() -> Path | None:
    candidates = [
        shutil.which("actool"),
        "/Applications/Xcode.app/Contents/Developer/usr/bin/actool",
        "/usr/bin/actool",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return Path(candidate)
    return None


def compile_icons(source: Path, resources: Path, deployment_target: str) -> bool:
    """Compile Assets.car (+ matching AppIcon.icns when actool emits it).

    `source` may be an Icon Composer `.icon` bundle or an `.xcassets` catalog.
    """
    actool = resolve_actool()
    if actool is None:
        print("warning: actool not found; skipping Assets.car (notifications may show a blank left icon)")
        return False

    with tempfile.TemporaryDirectory() as tmp:
        partial = Path(tmp) / "partial.plist"
        compile_dir = Path(tmp) / "out"
        compile_dir.mkdir()
        command = [
            str(actool),
            str(source),
            "--compile",
            str(compile_dir),
            "--platform",
            "macosx",
            "--minimum-deployment-target",
            deployment_target,
            "--app-icon",
            "AppIcon",
            "--include-all-app-icons",
            "--output-partial-info-plist",
            str(partial),
            "--enable-on-demand-resources",
            "NO",
            "--development-region",
            "en",
            "--target-device",
            "mac",
        ]
        # Required so Icon Composer stacks compile instead of being stripped.
        if source.suffix == ".icon" or source.name.endswith(".icon"):
            command.append("--enable-icon-stack-fallback-generation=disabled")

        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"warning: actool failed for {source}; skipping Assets.car")
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
        actool_icns = compile_dir / "AppIcon.icns"
        if actool_icns.is_file():
            shutil.copy2(actool_icns, resources / "AppIcon.icns")
        return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Path to LoopBar.app")
    parser.add_argument(
        "--icon",
        type=Path,
        default=Path("Assets/AppIcon.icns"),
        help="Fallback .icns if actool does not emit one (default: Assets/AppIcon.icns)",
    )
    parser.add_argument(
        "--composer-icon",
        type=Path,
        default=Path("Assets/AppIcon.icon"),
        help="Icon Composer document for macOS 26+ (default: Assets/AppIcon.icon)",
    )
    parser.add_argument(
        "--xcassets",
        type=Path,
        default=Path("Assets/Assets.xcassets"),
        help="Legacy asset catalog fallback (default: Assets/Assets.xcassets)",
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

    resources.mkdir(exist_ok=True)

    # Seed a fallback .icns first; actool may overwrite with a matching one.
    if args.icon.is_file():
        shutil.copy2(args.icon, resources / "AppIcon.icns")
    elif not (resources / "AppIcon.icns").is_file():
        raise FileNotFoundError(f"Missing icon asset: {args.icon}")

    has_car = False
    composer = args.composer_icon
    if composer.is_dir() and (composer / "icon.json").is_file():
        has_car = compile_icons(composer, resources, args.deployment_target)
        if has_car:
            print(f"Compiled Liquid Glass icon from {composer}")
    if not has_car and args.xcassets.is_dir() and (args.xcassets / "AppIcon.appiconset").is_dir():
        print(f"warning: falling back to flat xcassets at {args.xcassets} (blank left icon on macOS 26)")
        has_car = compile_icons(args.xcassets, resources, args.deployment_target)
    if not has_car:
        print("warning: no Assets.car installed")

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
