#!/usr/bin/env python3
"""Verify install_app_icon installs Assets.car + CFBundleIconName for notifications."""

from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
INSTALL = REPO / "scripts" / "install_app_icon.py"
CREATE = REPO / "scripts" / "create_app_icon.py"
MASTER = REPO / "Assets" / "LoopBar-AppIcon-v7.png"
EXISTING_ICNS = REPO / "Assets" / "AppIcon.icns"


class InstallAppIconTests(unittest.TestCase):
    def test_install_adds_asset_catalog_for_notifications(self) -> None:
        self.assertTrue(INSTALL.is_file(), f"missing {INSTALL}")
        self.assertTrue(MASTER.is_file(), f"missing {MASTER}")
        self.assertTrue(EXISTING_ICNS.is_file(), f"missing {EXISTING_ICNS}")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            assets = work / "Assets"
            assets.mkdir()
            icns = assets / "AppIcon.icns"
            xcassets = assets / "Assets.xcassets"
            shutil.copy2(EXISTING_ICNS, icns)

            # iconutil is unavailable in some sandboxes; xcassets is what actool needs.
            create = subprocess.run(
                [
                    sys.executable,
                    str(CREATE),
                    str(MASTER),
                    str(icns),
                    "--xcassets",
                    str(xcassets),
                    "--skip-icns",
                ],
                cwd=REPO,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                create.returncode,
                0,
                f"create_app_icon failed:\n{create.stdout}\n{create.stderr}",
            )
            self.assertTrue((xcassets / "AppIcon.appiconset" / "Contents.json").is_file())

            bundle = work / "LoopBar.app"
            contents = bundle / "Contents"
            resources = contents / "Resources"
            resources.mkdir(parents=True)
            info_path = contents / "Info.plist"
            with info_path.open("wb") as file:
                plistlib.dump(
                    {
                        "CFBundleIdentifier": "com.loopbar.test",
                        "CFBundleName": "LoopBar",
                        "CFBundleExecutable": "LoopBar",
                        "CFBundlePackageType": "APPL",
                    },
                    file,
                )

            install = subprocess.run(
                [
                    sys.executable,
                    str(INSTALL),
                    str(bundle),
                    "--icon",
                    str(icns),
                    "--xcassets",
                    str(xcassets),
                    # Force the flat-catalog path; the repo also has AppIcon.icon.
                    "--composer-icon",
                    str(work / "missing.AppIcon.icon"),
                ],
                cwd=REPO,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                install.returncode,
                0,
                f"install_app_icon failed:\n{install.stdout}\n{install.stderr}",
            )

            self.assertTrue((resources / "AppIcon.icns").is_file())
            self.assertTrue(
                (resources / "Assets.car").is_file(),
                "Notification Center needs Assets.car; loose .icns alone shows a blank banner icon",
            )

            with info_path.open("rb") as file:
                info = plistlib.load(file)
            self.assertEqual(info.get("CFBundleIconFile"), "AppIcon")
            self.assertEqual(
                info.get("CFBundleIconName"),
                "AppIcon",
                "CFBundleIconName is required for Notification Center to resolve Assets.car",
            )

    def test_install_prefers_liquid_glass_composer_icon(self) -> None:
        composer = REPO / "Assets" / "AppIcon.icon"
        self.assertTrue((composer / "icon.json").is_file(), f"missing {composer}")
        self.assertTrue(EXISTING_ICNS.is_file(), f"missing {EXISTING_ICNS}")

        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            bundle = work / "LoopBar.app"
            contents = bundle / "Contents"
            resources = contents / "Resources"
            resources.mkdir(parents=True)
            info_path = contents / "Info.plist"
            with info_path.open("wb") as file:
                plistlib.dump(
                    {
                        "CFBundleIdentifier": "com.loopbar.test",
                        "CFBundleName": "LoopBar",
                        "CFBundleExecutable": "LoopBar",
                        "CFBundlePackageType": "APPL",
                    },
                    file,
                )

            install = subprocess.run(
                [
                    sys.executable,
                    str(INSTALL),
                    str(bundle),
                    "--icon",
                    str(EXISTING_ICNS),
                    "--composer-icon",
                    str(composer),
                    "--xcassets",
                    str(work / "missing.xcassets"),
                ],
                cwd=REPO,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                install.returncode,
                0,
                f"install_app_icon failed:\n{install.stdout}\n{install.stderr}",
            )
            car = resources / "Assets.car"
            self.assertTrue(car.is_file())

            assetutil = shutil.which("assetutil") or "/usr/bin/assetutil"
            info = subprocess.run(
                [assetutil, "--info", str(car)],
                capture_output=True,
                text=True,
            )
            if info.returncode != 0:
                self.skipTest(f"assetutil unavailable: {info.stderr}")
            self.assertIn(
                "IconImageStack",
                info.stdout,
                "macOS 26 Notification Center needs IconImageStack in Assets.car",
            )


if __name__ == "__main__":
    unittest.main()
