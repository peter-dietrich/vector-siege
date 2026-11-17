#!/usr/bin/env python3
"""Reject a Vector Siege signed release if approved cockpit artwork is missing.

Checks original upper artwork in source and in the macOS .app Resources folder.
The approved lower cockpit is an actual artwork asset. Signed releases
must include its exact 1600x256 PNG; the obsolete procedural renderer does not
satisfy this requirement.
This checks package completeness, not human visual approval.
"""
import argparse
import json
from pathlib import Path
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = json.loads((ROOT / "docs/cockpit_v5/release_required_art.json").read_text())["required_pngs"]
SOURCE_DIR = ROOT / "Resources/CockpitV5"
LOWER_IMAGE = "VectorSiege_Clean_Shell_Approved.png"
LOWER_HOST = ROOT / "Sources/CockpitV53LowerDeck.swift"
XCODE_PROJECT = ROOT / "VectorSiege.xcodeproj/project.pbxproj"
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
    # The live lower cockpit requires the approved image, not the old fallback.
    lower_file = SOURCE_DIR / LOWER_IMAGE
    if not lower_file.is_file():
        problems.append("MISSING APPROVED LOWER COCKPIT " + str(lower_file))
    else:
        with lower_file.open("rb") as stream:
            header = stream.read(26)
        try:
            w, h = struct.unpack(">II", header[16:24])
            if header[:8] != PNG_SIGNATURE or (w, h) != (1600, 256):
                problems.append("INVALID LOWER ART / EXPECTED 1600x256 PNG " + str(lower_file))
        except struct.error:
            problems.append("INVALID APPROVED LOWER ART " + str(lower_file))
    if not LOWER_HOST.is_file() or LOWER_IMAGE not in LOWER_HOST.read_text():
        problems.append("LOWER LIVE RENDERER DOES NOT REQUIRE APPROVED ART")
    if args.app and not args.source_only:
        candidates = [
            args.app / "Contents/Resources/CockpitV5",
            args.app / "Contents/Resources/Resources/CockpitV5",
        ]
        match = next((p for p in candidates if p.is_dir()), candidates[0])
        problems += validate(match)
        lower_bundle = match / LOWER_IMAGE
        if not lower_bundle.is_file():
            problems.append("APP BUNDLE MISSING APPROVED LOWER ART " + str(lower_bundle))
    if problems:
        for error in problems:
            print("::error::" + error, file=sys.stderr)
        print(
            "\nRELEASE BLOCKED: required approved upper and lower cockpit "
            "artwork is missing or invalid. All 13 upper PNGs and the "
            "1600x256 lower shell PNG must be packaged.",
            file=sys.stderr,
        )
        return 1
    print("PASS: 13 recovered upper cockpit PNGs present in source" +
          (" and app bundle." if args.app else "."))
    print("PASS: approved 1600x256 lower shell PNG is tracked and required by renderer.")
    print("Manual visual smoke test against the approved mockup is still required.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
