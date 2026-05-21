#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building ZipManager..."
swift build

BINARY=".build/debug/ZipManager"
APP=".build/ZipManager.app"
CONTENTS="$APP/Contents"

# Assemble minimal .app bundle (required for SwiftUI windows + macOS activation)
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY"          "$CONTENTS/MacOS/ZipManager"
cp "Resources/Info.plist" "$CONTENTS/"

echo "Launching ZipManager..."
if [ $# -gt 0 ]; then
  open "$APP" --args "$@"
else
  open "$APP"
fi
