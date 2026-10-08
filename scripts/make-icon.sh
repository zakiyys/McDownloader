#!/bin/bash
# Generates AppIcon.icns from the project's master icon PNG.
#
# Usage: scripts/make-icon.sh [OUT.icns] [MASTER.png]
#
# The master defaults to assets/icon.png (a 1024x1024 PNG rendered from
# docs/branding/icon.svg). If the master is missing, a simple charcoal
# placeholder is drawn with CoreGraphics so the release pipeline never breaks.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO_ROOT/assets/AppIcon.icns}"
MASTER="${2:-$REPO_ROOT/assets/icon.png}"

WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET" "$(dirname "$OUT")"

if [[ ! -f "$MASTER" ]]; then
  echo "warning: $MASTER not found; drawing a placeholder instead" >&2
  cat > "$WORK/draw.swift" <<'SWIFT'
import AppKit
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)
NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
path.fill()
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 320, weight: .semibold),
    .foregroundColor: NSColor.white
]
let t = "McD" as NSString
let ts = t.size(withAttributes: attrs)
t.draw(at: CGPoint(x: rect.midX - ts.width / 2, y: rect.midY - ts.height / 2),
       withAttributes: attrs)
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
  swiftc -O "$WORK/draw.swift" -o "$WORK/draw"
  "$WORK/draw" "$WORK/icon_1024.png"
else
  cp "$MASTER" "$WORK/icon_1024.png"
fi

# Build the .iconset the way iconutil expects.
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$WORK/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
