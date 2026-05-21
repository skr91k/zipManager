#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building ZipManager..."
swift build

BINARY=".build/debug/ZipManager"
# Stable install path — TCC remembers permissions per bundle path + identifier
APPS="$HOME/Applications"
APP="$APPS/ZipManager.app"
CONTENTS="$APP/Contents"

mkdir -p "$APPS"

# Only rebuild bundle when binary actually changed (keeps TCC identity stable)
PREV_HASH=""
CURR_HASH=$(md5 -q "$BINARY")
HASH_FILE=".build/.zipmanager_binary_hash"
[ -f "$HASH_FILE" ] && PREV_HASH=$(cat "$HASH_FILE")

if [ "$CURR_HASH" != "$PREV_HASH" ] || [ ! -d "$APP" ]; then
  echo "Installing to $APP..."
  rm -rf "$APP"
  mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
  cp "$BINARY"              "$CONTENTS/MacOS/ZipManager"
  cp "Resources/Info.plist" "$CONTENTS/"

  # Sign with entitlements — disables sandbox so no per-click prompts
  codesign --force --deep --sign - \
    --entitlements "ZipManager.entitlements" \
    "$APP"

  echo "$CURR_HASH" > "$HASH_FILE"
  echo "Installed."
fi

echo "Launching ZipManager..."
if [ $# -gt 0 ]; then
  open "$APP" --args "$@"
else
  open -a "$APP"
fi
