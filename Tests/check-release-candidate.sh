#!/usr/bin/env bash
# Validate an unsigned local Release product's identity and contents.
# This is a CI preflight, not a signing, notarization or Gatekeeper test.
set -euo pipefail

APP="${1:-}"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "Usage: bash Tests/check-release-candidate.sh /path/to/VectorSiege.app" >&2
  exit 2
fi
if [[ "$(basename "$APP")" != "VectorSiege.app" ]]; then
  echo "Expected VectorSiege.app, got $(basename "$APP")" >&2
  exit 1
fi

INFO="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/VectorSiege"
[[ -f "$INFO" ]] || { echo "Missing Info.plist" >&2; exit 1; }
[[ -x "$EXECUTABLE" ]] || { echo "Missing app executable" >&2; exit 1; }
/usr/bin/plutil -lint "$INFO"

read_property() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO"
}
BUNDLE_ID="$(read_property CFBundleIdentifier)"
PACKAGE_TYPE="$(read_property CFBundlePackageType)"
EXECUTABLE_NAME="$(read_property CFBundleExecutable)"
[[ "$BUNDLE_ID" == "io.vectorsiege.game" ]] || {
  echo "Fun City bundle ID mismatch: $BUNDLE_ID" >&2; exit 1;
}
[[ "$PACKAGE_TYPE" == "APPL" ]] || {
  echo "Unexpected macOS package type: $PACKAGE_TYPE" >&2; exit 1;
}
[[ "$EXECUTABLE_NAME" == "VectorSiege" ]] || {
  echo "Unexpected executable name: $EXECUTABLE_NAME" >&2; exit 1;
}
# Ensure bundle is nontrivial; a stub launcher must never pass preflight.
[[ $(stat -f '%z' "$EXECUTABLE") -gt 100000 ]] || {
  echo "VectorSiege executable is unexpectedly small" >&2; exit 1;
}
echo "Release preflight PASS: $BUNDLE_ID / $EXECUTABLE_NAME"
echo "Unsigned build validated for development/testing only."
