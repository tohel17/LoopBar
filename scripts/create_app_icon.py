#!/usr/bin/env python3
"""Create LoopBar macOS icon assets from the master PNG.

Produces:
  - a loose .icns (Finder / Dock fallback)
  - an AppIcon.appiconset under Assets.xcassets (source for actool → Assets.car)

Notification Center on modern macOS resolves the banner logo from the compiled
asset catalog (Assets.car + CFBundleIconName), not from a loose .icns alone.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
from pathlib import Path


def _retina(name: str) -> str:
    """Build iconset retina filenames without embedding a raw @ in source literals."""
    return name + chr(64) + "2x.png"


# (point size, scale, filename) for macOS AppIcon.appiconset / .iconset
ICON_SLOTS: list[tuple[int, int, str]] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, _retina("icon_16x16")),
    (32, 1, "icon_32x32.png"),
    (32, 2, _retina("icon_32x32")),
    (128, 1, "icon_128x128.png"),
    (128, 2, _retina("icon_128x128")),
    (256, 1, "icon_256x256.png"),
    (256, 2, _retina("icon_256x256")),
    (512, 1, "icon_512x512.png"),
    (512, 2, _retina("icon_512x512")),
]


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def render_slot(source: Path, destination: Path, pixels: int) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Write via a temp path first — sips warns on retina (@2x) suffixes.
    with tempfile.TemporaryDirectory() as tmp:
        temp_out = Path(tmp) / "slot.png"
        run(
            [
                "sips",
                "-s",
                "format",
                "png",
                "--resampleHeightWidth",
                str(pixels),
                str(pixels),
                str(source),
                "--out",
                str(temp_out),
            ]
        )
        shutil.copy2(temp_out, destination)


def write_appiconset(source: Path, appiconset: Path) -> None:
    if appiconset.exists():
        shutil.rmtree(appiconset)
    appiconset.mkdir(parents=True)

    for points, scale, filename in ICON_SLOTS:
        render_slot(source, appiconset / filename, points * scale)

    contents = {
        "images": [
            {
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{points}x{points}",
                "filename": filename,
            }
            for points, scale, filename in ICON_SLOTS
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (appiconset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def write_xcassets(source: Path, xcassets: Path) -> Path:
    if xcassets.exists():
        shutil.rmtree(xcassets)
    xcassets.mkdir(parents=True)
    (xcassets / "Contents.json").write_text(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n"
    )
    appiconset = xcassets / "AppIcon.appiconset"
    write_appiconset(source, appiconset)
    return appiconset


def write_icns(appiconset: Path, destination: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for _, _, filename in ICON_SLOTS:
            shutil.copy2(appiconset / filename, iconset / filename)
        destination.parent.mkdir(parents=True, exist_ok=True)
        run(["iconutil", "-c", "icns", str(iconset), "-o", str(destination)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Master square PNG")
    parser.add_argument("destination", type=Path, help="Output .icns path")
    parser.add_argument(
        "--xcassets",
        type=Path,
        default=None,
        help="Output Assets.xcassets directory (default: <destination-parent>/Assets.xcassets)",
    )
    parser.add_argument(
        "--skip-icns",
        action="store_true",
        help="Only write Assets.xcassets (skip iconutil .icns generation)",
    )
    args = parser.parse_args()

    if not args.source.is_file():
        raise FileNotFoundError(f"Missing source icon: {args.source}")

    probe = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", str(args.source)],
        check=True,
        capture_output=True,
        text=True,
    )
    width = height = None
    for line in probe.stdout.splitlines():
        if "pixelWidth:" in line:
            width = int(line.split(":")[-1].strip())
        if "pixelHeight:" in line:
            height = int(line.split(":")[-1].strip())
    if width is None or height is None:
        raise ValueError(f"Could not read dimensions for {args.source}")
    if width != height:
        raise ValueError("The source icon must be square.")

    xcassets = args.xcassets or (args.destination.parent / "Assets.xcassets")
    appiconset = write_xcassets(args.source, xcassets)
    if args.skip_icns:
        print(f"Wrote {appiconset} (--skip-icns)")
        return
    write_icns(appiconset, args.destination)
    print(f"Wrote {args.destination}")
    print(f"Wrote {appiconset}")


if __name__ == "__main__":
    main()
