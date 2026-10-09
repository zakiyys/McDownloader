#!/bin/bash
# Assemble McDownloader.app from a built binary plus the engine binaries.
#
# Usage:
#   scripts/package-app.sh --binary <path> --out <dir> [--aria2 <path>] \
#       [--torrent-helper <path>] [--host <path>] [--icon <AppIcon.icns>] [--version 1.0.0]
#
# The engines and the native messaging host are copied into Contents/ (Resources
# for the engines, MacOS for the host), which is what EngineLocator and the
# browser expect at runtime. The browser extension is copied into
# Contents/Resources/extension so the app can open it for the user.
set -euo pipefail

BINARY=""
OUT="dist"
ARIA2=""
HELPER=""
HOST=""
ICON=""
VERSION="1.0.0"
COMMIT="unknown"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --binary) BINARY="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --aria2) ARIA2="$2"; shift 2 ;;
    --torrent-helper) HELPER="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
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

# The native messaging host lives next to the main binary: the browser manifest
# points at Contents/MacOS/mcdownloader-host.
if [[ -n "$HOST" && -f "$HOST" ]]; then
  cp "$HOST" "$MACOS/mcdownloader-host"
  chmod +x "$MACOS/mcdownloader-host"
fi

# Ship the extension inside the app so "Connect browser" can reveal it.
if [[ -d "$REPO_ROOT/Extension" ]]; then
  rm -rf "$RES/extension"
  cp -R "$REPO_ROOT/Extension" "$RES/extension"
fi

if [[ -n "$ICON" && -f "$ICON" ]]; then
  cp "$ICON" "$RES/AppIcon.icns"
fi

# Sign inside-out. `codesign --deep` on a universal binary can sign only the
# slice matching the build machine (arm64 on CI), leaving the Intel slice with no
# signature at all. Sign each engine and the host explicitly first (an explicit
# sign covers every slice), then seal the bundle WITHOUT --deep so the seal does
# not re-touch the engines.
#
# Ad-hoc signing only: this lets the app launch on the build machine and on any
# Mac after the user clears quarantine. Notarization is a separate step.
SIGN=(--force --sign -)
if [[ -f "$RES/aria2c" ]]; then codesign "${SIGN[@]}" "$RES/aria2c" 2>/dev/null || echo "warning: codesign aria2c failed"; fi
if [[ -f "$RES/mcdownloader-torrentd" ]]; then codesign "${SIGN[@]}" "$RES/mcdownloader-torrentd" 2>/dev/null || echo "warning: codesign torrent helper failed"; fi
if [[ -f "$MACOS/mcdownloader-host" ]]; then codesign "${SIGN[@]}" "$MACOS/mcdownloader-host" 2>/dev/null || echo "warning: codesign host failed"; fi
codesign "${SIGN[@]}" "$APP" 2>/dev/null || echo "warning: ad-hoc codesign failed"

echo "built $APP"
