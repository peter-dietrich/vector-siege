#!/usr/bin/env python3
"""Reject a Vector Siege signed release if approved cockpit artwork is missing.

Checks both the tracked source assets and the macOS .app Resources folder.
The 13 upper art files and the separately approved lower chassis are required.
This checks file presence and PNG structure, not human visual approval.
"""
import argparse
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = json.loads((ROOT / "docs/cockpit_v5/release_required_art.json").read_text())["required_pngs"]
SOURCE_DIR = ROOT / "Resources/CockpitV5"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def validate(base: Path) -> list[str]:
    problems = []
    for name in REQUIRED:
        file = base / name
        if not file.is_file():
            problems.append("MISSING " + str(file))
            continue
        try:
            with file.open("rb") as stream:
                header = stream.read(33)
            if len(header) < 33 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
                problems.append("INVALID PNG " + str(file))
                continue
            width, height, bit_depth, color_type = struct.unpack(">IIBB", header[16:26])
            if width < 32 or height < 32 or bit_depth != 8 or color_type != 6:
                problems.append("NOT ORIGINAL 8-bit RGBA PNG " + str(file))
        except (OSError, struct.error) as exc:
            problems.append("UNREADABLE " + str(file) + ": " + str(exc))
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, help="Built VectorSiege.app to validate")
    parser.add_argument("--source-only", action="store_true", help="Validate the tracked source assets only")
    args = parser.parse_args()
    problems = validate(SOURCE_DIR)
    if args.app and not args.source_only:
        candidates = [
            args.app / "Contents/Resources/CockpitV5",
            args.app / "Contents/Resources/Resources/CockpitV5",
        ]
        match = next((p for p in candidates if p.is_dir()), candidates[0])
        problems += validate(match)
    if problems:
        for error in problems:
            print("::error::" + error, file=sys.stderr)
        print(
            "\nRELEASE BLOCKED: GitHub has only the fallback cockpit. "
            "Import the original v5.3 artwork and approved lower panel into "
            "Resources/CockpitV5, commit all 14 PNGs, and rebuild. "
            "Never ship generated stand-ins or the outdated cockpit.",
            file=sys.stderr,
        )
        return 1
    print("PASS: 13 approved upper cockpit images + approved lower panel "
          "are present in source" + (" and app bundle." if args.app else "."))
    print("Manual visual smoke test against the approved mockup is still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
