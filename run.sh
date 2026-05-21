#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PACKAGE_MODE=false
[ "${1:-}" = "p" ] && PACKAGE_MODE=true

APP_NAME="ZipManager"
APPS="$HOME/Applications"
APP="$APPS/$APP_NAME.app"
CONTENTS="$APP/Contents"

# ── Build ──────────────────────────────────────────────────────────────────────
if $PACKAGE_MODE; then
  echo "Building $APP_NAME (release)..."
  swift build -c release
  BINARY=".build/release/$APP_NAME"
else
  echo "Building $APP_NAME..."
  swift build
  BINARY=".build/debug/$APP_NAME"
fi

# ── Assemble .app bundle (only when binary changed) ────────────────────────────
mkdir -p "$APPS"
CURR_HASH=$(md5 -q "$BINARY")
HASH_FILE=".build/.zipmanager_binary_hash"
PREV_HASH=""; [ -f "$HASH_FILE" ] && PREV_HASH=$(cat "$HASH_FILE")

if [ "$CURR_HASH" != "$PREV_HASH" ] || [ ! -d "$APP" ]; then
  echo "Installing to $APP..."
  rm -rf "$APP"
  mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
  cp "$BINARY"              "$CONTENTS/MacOS/$APP_NAME"
  cp "Resources/Info.plist" "$CONTENTS/"
  codesign --force --deep --sign - \
    --entitlements "ZipManager.entitlements" \
    "$APP"
  echo "$CURR_HASH" > "$HASH_FILE"
fi

# ── Package → DMG ─────────────────────────────────────────────────────────────
if $PACKAGE_MODE; then
  DMG_PATH="$(pwd)/$APP_NAME.dmg"
  STAGING=$(mktemp -d)
  trap 'rm -rf "$STAGING"' EXIT

  echo "Creating DMG..."
  cp -r "$APP" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"

  rm -f "$DMG_PATH"
  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -quiet \
    "$DMG_PATH"

  echo "Done → $DMG_PATH"
  open "$DMG_PATH"

# ── Dev run ───────────────────────────────────────────────────────────────────
else
  echo "Launching $APP_NAME..."
  open -a "$APP"
fi
