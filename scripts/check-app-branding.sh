#!/bin/bash
# Acceptance gate: verify the real macOS .app contains a decodable .icns.
set -euo pipefail
APP_NAME="${1:?Pass the Xcode target app name, e.g. FunCity}"
ROOT="${2:-$HOME/Library/Developer/Xcode/DerivedData}"
if [[ ! -d "$ROOT" ]]; then echo "DerivedData missing: $ROOT" >&2; exit 1; fi
APP="$(find "$ROOT" -path "*/Build/Products/Debug/${APP_NAME}.app" -type d -print -quit)"
if [[ -z "$APP" ]]; then APP="$(find "$ROOT" -path "*/Build/Products/Release/${APP_NAME}.app" -type d -print -quit)"; fi
if [[ -z "$APP" ]]; then echo "No built ${APP_NAME}.app found" >&2; exit 1; fi
INFO="$APP/Contents/Info.plist"
ICON="$APP/Contents/Resources/AppIcon.icns"
test -s "$INFO" || { echo "Missing bundled Info.plist" >&2; exit 1; }
test -s "$ICON" || { echo "Missing or empty bundled AppIcon.icns" >&2; exit 1; }
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$INFO")"
[[ "$ICON_NAME" == "AppIcon" || "$ICON_NAME" == "AppIcon.icns" ]] || { echo "Incorrect CFBundleIconFile: $ICON_NAME" >&2; exit 1; }
test -n "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")" || { echo "Missing bundle identifier" >&2; exit 1; }
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
/usr/bin/iconutil -c iconset "$ICON" -o "$temp/AppIcon.iconset"
test -s "$temp/AppIcon.iconset/icon_512x512@2x.png" || { echo "Invalid icon content" >&2; exit 1; }
echo "PASS: $APP"
echo "PASS: bundled AppIcon.icns is valid and registered in Info.plist"
