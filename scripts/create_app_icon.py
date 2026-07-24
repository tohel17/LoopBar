#!/usr/bin/env python3
"""Create a macOS .icns icon from LoopBar's master PNG."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


ICON_SIZES = [(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Master square PNG")
    parser.add_argument("destination", type=Path, help="Output .icns path")
    args = parser.parse_args()

    with Image.open(args.source) as source:
        image = source.convert("RGBA")
        if image.width != image.height:
            raise ValueError("The source icon must be square.")
        args.destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(args.destination, format="ICNS", sizes=ICON_SIZES)


if __name__ == "__main__":
    main()
