#!/usr/bin/env python3
"""Inspect and safely stage the approved Vector Siege v5.3 cockpit prototype ZIP.

This script deliberately does not synthesize artwork, overwrite the playable
cockpit, or invent a mapping between prototype assets and v5 manifest IDs.
It inventories the original 13+ RGBA exports so integration can use them
directly after confirming layout and source identity.
"""
import argparse
import hashlib
import json
import pathlib
import struct
import sys
import zipfile

MAX_FILE_BYTES = 40 * 1024 * 1024
MAX_ARCHIVE_BYTES = 300 * 1024 * 1024
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def png_info(data):
    if len(data) < 33 or not data.startswith(PNG_SIGNATURE):
        return None
    chunk_len = struct.unpack(">I", data[8:12])[0]
    if data[12:16] != b"IHDR" or chunk_len != 13:
        return None
    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", data[16:29]
    )
    return {
        "width": width, "height": height,
        "bit_depth": bit_depth, "color_type": color_type,
        "rgba": color_type in (4, 6),
        "interlaced": bool(interlace),
    }


def inspect(archive):
    images = []
    total = 0
    with zipfile.ZipFile(archive) as package:
        members = package.infolist()
        for member in members:
            if member.is_dir():
                continue
            if member.file_size > MAX_FILE_BYTES:
                raise ValueError("Oversized ZIP member: " + member.filename)
            total += member.file_size
            if total > MAX_ARCHIVE_BYTES:
                raise ValueError("Archive exceeds permitted unpacked size")
            if not member.filename.lower().endswith(".png"):
                continue
            # Never extract arbitrary ZIP paths.
            parts = pathlib.PurePosixPath(member.filename).parts
            if not parts or any(part in ("", ".", "..") for part in parts):
                raise ValueError("Unsafe archive member path")
            raw = package.read(member)
            info = png_info(raw)
            if not info:
                raise ValueError("Invalid PNG: " + member.filename)
            info.update({
                "source": member.filename,
                "bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
            })
            images.append(info)
    rgba = [item for item in images if item["rgba"]]
    return {"archive": str(archive), "png_count": len(images),
            "rgba_count": len(rgba), "images": sorted(images, key=lambda x: x["source"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip_path", type=pathlib.Path)
    parser.add_argument("--report", type=pathlib.Path,
                        help="Write JSON inventory; no original files are modified")
    args = parser.parse_args()
    if not args.zip_path.is_file():
        parser.error("Cockpit ZIP not found: " + str(args.zip_path))
    try:
        report = inspect(args.zip_path)
    except (ValueError, zipfile.BadZipFile, OSError) as error:
        parser.error(str(error))
    print(f"Archive: {report['archive']}")
    print(f"PNG images: {report['png_count']} | RGBA/grayscale-alpha images: {report['rgba_count']}")
    for item in report["images"]:
        tag = "ALPHA" if item["rgba"] else "OPAQUE"
        print(f"{tag:6} {item['width']:5}x{item['height']:<5} {item['source']}")
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
        print("Inventory written:", args.report)
    if report["rgba_count"] < 13:
        print("WARNING: Fewer than 13 alpha-capable PNGs; verify this is the full v5.3 package.",
              file=sys.stderr)


if __name__ == "__main__":
    main()
