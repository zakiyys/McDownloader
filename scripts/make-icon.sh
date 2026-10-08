#!/bin/bash
# Generates a placeholder AppIcon.icns.
#
# This is an honest placeholder (DESIGN.md sec.10): a neutral squircle with the
# "McD" wordmark and a download arrow. Replace it with real artwork later by
# dropping a 1024x1024 PNG in and re-running iconutil.
set -euo pipefail

OUT="${1:-assets/AppIcon.icns}"
WORK="$(mktemp -d)"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET" "$(dirname "$OUT")"

# Draw the master image with CoreGraphics via a tiny Swift program. No design
# tool or Python imaging library is required on the runner.
cat > "$WORK/draw.swift" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Squircle tile with macOS-like margins.
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius: CGFloat = rect.width * 0.2237
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Neutral charcoal, flat. No gradient, no glow.
NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
path.fill()

// A thin inner border for definition on light backgrounds.
NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08).setStroke()
path.lineWidth = 4
path.stroke()

// Wordmark "McD" centered.
let title = "McD"
let titleFont = NSFont.systemFont(ofSize: 320, weight: .semibold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor.white
]
let titleSize = title.size(withAttributes: titleAttrs)
let titleRect = CGRect(
    x: rect.midX - titleSize.width / 2,
    y: rect.midY - titleSize.height / 2 + 60,
    width: titleSize.width,
    height: titleSize.height
)
title.draw(in: titleRect, withAttributes: titleAttrs)

// Download arrow beneath the wordmark, using a simple path.
ctx.setStrokeColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92).cgColor)
ctx.setLineWidth(34)
ctx.setLineCap(.round)
let cx = rect.midX
let top = rect.midY - 120
let bottom = rect.midY - 240
ctx.move(to: CGPoint(x: cx, y: top))
ctx.addLine(to: CGPoint(x: cx, y: bottom))
ctx.strokePath()
ctx.move(to: CGPoint(x: cx - 70, y: bottom + 70))
ctx.addLine(to: CGPoint(x: cx, y: bottom))
ctx.addLine(to: CGPoint(x: cx + 70, y: bottom + 70))
ctx.strokePath()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to render icon\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swiftc -O "$WORK/draw.swift" -o "$WORK/draw"
"$WORK/draw" "$WORK/icon_1024.png"

# Build the .iconset the way iconutil expects.
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$WORK/icon_1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT"
