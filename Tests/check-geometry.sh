#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="$(mktemp -t vector-siege-geometry.XXXXXX)"
trap 'rm -f "$TARGET"' EXIT
swiftc Sources/BattlefieldMath.swift Tests/geometry_smoke.swift -o "$TARGET"
"$TARGET"