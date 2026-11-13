#!/usr/bin/env python3
"""Contract checks for Cockpit V5 artwork and layout; no third-party packages.

Draft mode validates design and code bindings without needing final images.
--strict additionally requires every exported PNG, validates 2x size and RGBA.
--svg PATH exports a precisely aligned *wire-layout registration sheet*, not
production art. Designers overlay it with candidate assets before approval.
"""
import argparse
import json
from pathlib import Path
import struct
import sys
import xml.sax.saxutils as xml

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/cockpit_v5/asset_manifest.json"

def fatal(message):
    raise ValueError(message)

def rect(obj):
    if not isinstance(obj, dict) or not all(key in obj for key in ("x","y","width","height")):
        fatal(f"Missing x/y/width/height: {obj}")
    if not all(isinstance(obj[k], (int,float)) for k in ("x","y","width","height")):
        fatal(f"Non-numeric rectangle: {obj}")
    if obj["width"] <= 0 or obj["height"] <= 0:
        fatal(f"Non-positive dimensions: {obj}")
    return obj

def inside(inner, outer, name):
    if not (inner["x"] >= outer["x"] and inner["y"] >= outer["y"]
            and inner["x"] + inner["width"] <= outer["x"] + outer["width"]
            and inner["y"] + inner["height"] <= outer["y"] + outer["height"]):
        fatal(f"{name} lies outside container")

def intersects(a,b):
    return (a["x"] < b["x"]+b["width"] and b["x"] < a["x"]+a["width"] and
            a["y"] < b["y"]+b["height"] and b["y"] < a["y"]+a["height"])

def png_metadata(path):
    with open(path,"rb") as stream:
        head=stream.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        fatal(f"{path}: not a valid PNG IHDR")
    width,height,depth,color,compression,filter_method,interlace=struct.unpack(">IIBBBBB",head[16:29])
    if color != 6 or depth != 8:
        fatal(f"{path}: expected 8-bit RGBA PNG; got depth {depth}, color type {color}")
    return width,height

def validate(manifest, strict):
    assert manifest["schema_version"].startswith("5.")
    W=manifest["design_space"]["width"]
    H=manifest["design_space"]["height"]
    canvas={"x":0,"y":0,"width":W,"height":H}
    regions=manifest["regions"]
    for name, region in regions.items():
        inside(rect(region),canvas,name)
    if not regions["battlefield"]["min_visible_fraction"] <= regions["battlefield"]["height"]/H:
        fatal("Battlefield is shorter than the minimum visibility contract")
    screens=manifest["screens"]
    names=[screen["id"] for screen in screens]
    if len(names) != len(set(names)) or len(screens) != 4:
        fatal("Expected four uniquely named screens")
    assets={entry["id"]:entry for entry in manifest["artwork"]}
    if len(assets) != len(manifest["artwork"]):
        fatal("Duplicate artwork IDs")
    for i,screen in enumerate(screens):
        r=rect(screen["rect"])
        inside(r,regions["top_instruments"],screen["id"])
        for previous in screens[:i]:
            if intersects(r,previous["rect"]): fatal(f"Screen overlap: {screen['id']}")
        if screen["asset_frame"] not in assets: fatal(f"Missing physical bezel for {screen['id']}")
        inside(r,rect(assets[screen["asset_frame"]]["rect"]),screen["id"] + " bezel")
        if not screen["dynamic_fields"]: fatal(f"Unbound screen: {screen['id']}")
    for entry in manifest["artwork"]:
        if entry.get("contains_text"): fatal(f"Artwork bakes in live text: {entry['id']}")
        location=entry["path"]
        if not location.startswith("Resources/CockpitV5/") or not location.endswith(".png"):
            fatal(f"Nonstandard asset path: {location}")
        target=ROOT/location
        if entry.get("rect") is not None:
            r=rect(entry["rect"])
            inside(r,canvas,entry["id"])
            expected=[int(r["width"]*entry["pixel_scale"]),
                      int(r["height"]*entry["pixel_scale"])]
            if expected != entry["dimensions_px"]: fatal(f"Wrong expected 2x dimensions for {entry['id']}")
        if strict or target.exists():
            if not target.exists(): fatal(f"Missing required art: {target}")
            actual=png_metadata(target)
            if list(actual) != entry["dimensions_px"]:
                fatal(f"{target}: expected {entry['dimensions_px']}, got {actual}")
    if any("engine_health" in field or "fuel_percent" in field
           for screen in screens for field in screen["dynamic_fields"]):
        fatal("Nonexistent gameplay systems may not be shown as live telemetry")
    return True

def export_registration_svg(manifest, destination):
    W=manifest["design_space"]["width"]
    H=manifest["design_space"]["height"]
    pieces=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
            '<rect width="100%" height="100%" fill="#0e1116"/>']
    for key,region in manifest["regions"].items():
        pieces.append(f'<rect x="{region["x"]}" y="{region["y"]}" width="{region["width"]}" height="{region["height"]}" fill="#13272b" stroke="#6d8c91" stroke-width="2"/>')
        pieces.append(f'<text x="{region["x"]+10}" y="{region["y"]+22}" fill="#d3dbd9" font-family="monospace" font-size="16">{xml.escape(key.upper())}</text>')
    for entry in manifest["artwork"]:
        r=entry.get("rect")
        if r is None: continue
        pieces.append(f'<rect x="{r["x"]}" y="{r["y"]}" width="{r["width"]}" height="{r["height"]}" fill="none" stroke="#c68d47" stroke-dasharray="8 5" stroke-width="2"/>')
        pieces.append(f'<text x="{r["x"]+5}" y="{r["y"]+r["height"]-7}" fill="#d5a86c" font-family="monospace" font-size="11">{xml.escape(entry["id"])}</text>')
    for screen in manifest["screens"]:
        r=screen["rect"]
        pieces.append(f'<rect x="{r["x"]}" y="{r["y"]}" width="{r["width"]}" height="{r["height"]}" fill="#102329" fill-opacity=".85" stroke="#6cb8a5" stroke-width="2"/>')
        pieces.append(f'<text x="{r["x"]+12}" y="{r["y"]+30}" fill="#a7e4d6" font-family="monospace" font-size="21">{xml.escape(screen["title"])}</text>')
        pieces.append(f'<text x="{r["x"]+12}" y="{r["y"]+55}" fill="#91a7a7" font-family="monospace" font-size="13">LIVE CONTENT SLOT</text>')
    pieces.append('</svg>')
    destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text("\n".join(pieces),encoding="utf-8")

if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="Require final RGBA artwork exports")
    parser.add_argument("--svg", type=Path, help="Output annotated registration sheet SVG")
    args=parser.parse_args()
    try:
        data=json.loads(MANIFEST.read_text(encoding="utf-8"))
        validate(data,args.strict)
        if args.svg:
            export_registration_svg(data,args.svg)
            print(f"Registration SVG: {args.svg}")
        print("Cockpit v5 contract PASS" + (" (artwork strict)" if args.strict else " (draft)"))
    except (ValueError, KeyError, OSError, AssertionError) as exc:
        print(f"Cockpit v5 contract FAIL: {exc}",file=sys.stderr)
        sys.exit(1)
