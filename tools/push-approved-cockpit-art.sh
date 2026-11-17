#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "This installs the approved art onto main. Run: git switch main"; exit 1
fi

git fetch origin main
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Please sync main first: git pull --ff-only origin main"; exit 1
fi
# Avoid mixing uncommitted work into the asset commit.
if [[ -n "$(git diff --name-only)" || -n "$(git diff --cached --name-only)" ]]; then
  echo "Tracked local changes found. Commit or stash them first."; exit 1
fi

name="VectorSiege_Clean_Shell_Approved.png"
destination="Resources/CockpitV5/$name"
if [[ ! -f "$destination" ]]; then
  file="$(find "$HOME/Downloads" -maxdepth 5 -type f -name "$name" -print -quit 2>/dev/null)"
  if [[ -z "$file" ]]; then
    echo "Cannot find the approved shell artwork: $name"
    echo "Download the PNG from this ChatGPT conversation into Downloads, then retry."
    exit 1
  fi
  mkdir -p "$(dirname "$destination")"
  cp "$file" "$destination"
fi

# Python standard library PNG header validation, no PIL dependency.
python3 - "$destination" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, "rb") as file:
    header = file.read(24)
if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
    raise SystemExit("Artwork is not a valid PNG: " + path)
size = struct.unpack(">II", header[16:24])
if size != (1600, 256):
    raise SystemExit("Incorrect PNG dimensions: %s (expected 1600x256)" % (size,))
print("Approved lower cockpit artwork verified: %s, %s" % (path, size))
PY

git add -f "$destination"
if git diff --cached --quiet; then
  echo "The approved PNG is already tracked; nothing to commit."
else
  git commit -m "Track approved lower cockpit shell artwork (1600x256 PNG)"
  git push origin main
fi
echo "Main now includes the approved lower shell PNG."
