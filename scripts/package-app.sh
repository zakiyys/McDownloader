#!/bin/bash
# Assemble McDownloader.app from a built binary plus the engine binaries.
#
# Usage:
#   scripts/package-app.sh --binary <path> --out <dir> [--aria2 <path>] \
#       [--torrent-helper <path>] [--icon <AppIcon.icns>] [--version 1.0.0]
#
# The engines are copied into Contents/Resources, which is what EngineLocator
# searches first at runtime.
set -euo pipefail

BINARY=""
OUT="dist"
ARIA2=""
HELPER=""
ICON=""
VERSION="1.0.0"
COMMIT="unknown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary) BINARY="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --aria2) ARIA2="$2"; shift 2 ;;
    --torrent-helper) HELPER="$2"; shift 2 ;;
    --icon) ICON="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --commit) COMMIT="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$BINARY" && -x "$BINARY" ]] || { echo "missing --binary" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$OUT/McDownloader.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

cp "$BINARY" "$MACOS/McDownloader"
chmod +x "$MACOS/McDownloader"

# Info.plist with the version and commit stamped in.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$REPO_ROOT/App/Info.plist" >/dev/null 2>&1 || true
cp "$REPO_ROOT/App/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :McGITCommit string $COMMIT" "$CONTENTS/Info.plist" >/dev/null 2>&1 || \
  /usr/libexec/PlistBuddy -c "Set :McGITCommit $COMMIT" "$CONTENTS/Info.plist"

printf 'APPL????' > "$CONTENTS/PkgInfo"

if [[ -n "$ARIA2" && -f "$ARIA2" ]]; then
  cp "$ARIA2" "$RES/aria2c"
  chmod +x "$RES/aria2c"
fi

if [[ -n "$HELPER" && -f "$HELPER" ]]; then
  cp "$HELPER" "$RES/mcdownloader-torrentd"
  chmod +x "$RES/mcdownloader-torrentd"
fi

if [[ -n "$ICON" && -f "$ICON" ]]; then
  cp "$ICON" "$RES/AppIcon.icns"
fi

# Ad-hoc sign so the app launches on the build machine and on any Mac after the
# user clears quarantine. Not a Developer ID signature; notarization is separate.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "warning: ad-hoc codesign failed"

echo "built $APP"
