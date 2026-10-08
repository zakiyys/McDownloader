#!/bin/bash
# Builds a simple drag-to-Applications DMG for McDownloader.
set -euo pipefail

APP="${1:?usage: make-dmg.sh McDownloader.app out.dmg [version]}"
DMG="${2:?missing output dmg path}"
VERSION="${3:-1.0.0}"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$(dirname "$DMG")"
rm -f "$DMG"

hdiutil create \
  -volname "McDownloader $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

echo "wrote $DMG"
