import SwiftUI

/// The Miaw paw mark, traced from the project's brand SVGs
/// (`docs/branding/paw-mark-light.svg` / `paw-mark-dark.svg`): a bridge ellipse,
/// four toe pads and a main pad, fused into one puffy silhouette by a thick
/// round stroke, the whole thing tilted -45 degrees like the originals.
///
/// Drawn as vectors, not a bitmap: it tints with any colour (including the
/// engine-state tint) and stays crisp at any size, and the app needs no image
/// asset, so it still builds from source with the command line tools alone.
struct PawMark: View {
    /// Side of the mark's square.
    var size: CGFloat = 26
    /// Tint. Default is a quiet label colour so the mark reads as a signature,
    /// not as a control.
    var color: Color = Color(nsColor: .tertiaryLabelColor)

    private let design: CGFloat = 220   // the SVGs' 220x220 viewBox
    private let union: CGFloat = 26     // the SVGs' silhouette stroke-width
    private let tilt: CGFloat = -45     // the SVGs' rotate(-45)

    var body: some View {
        ZStack {
            // One path for the whole silhouette, filled and stroked once, so
            // the overlaps merge into a single puffy outline with no seams.
            silhouette
                .fill(color)
            silhouette
                .stroke(color, style: StrokeStyle(lineWidth: union, lineCap: .round, lineJoin: .round))

            // A soft inset in the toes and pad, so the paw keeps its shape at
            // small sizes instead of reading as a solid blob. One fill, so
            // overlaps do not compound. `.primary` adapts to light and dark.
            pads.fill(Color.primary.opacity(0.12))
        }
        .frame(width: design, height: design)
        .rotationEffect(.degrees(tilt))
        .scaleEffect(size / design, anchor: .center)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// The six shapes the SVGs compose, as a single path in view coordinates
    /// (the viewBox shifted by +110 so nothing draws off-canvas).
    private var silhouette: Path {
        var path = Path()
        for part in shapes { path.addPath(part) }
        return path
    }

    /// The inner toe pads and main pad, a touch inset from the silhouette. The
    /// bridge is not repeated here, matching the source SVGs.
    private var pads: Path {
        var path = Path()
        for part in shapes.dropFirst() { path.addPath(part) }
        return path
    }

    private var shapes: [Path] {
        let c = design / 2

        func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ degrees: CGFloat) -> Path {
            let rect = CGRect(x: c + x - rx, y: c + y - ry, width: 2 * rx, height: 2 * ry)
            let path = Path(ellipseIn: rect)
            guard degrees != 0 else { return path }
            let angle = degrees * .pi / 180
            let spin = CGAffineTransform(translationX: c + x, y: c + y)
                .rotated(by: angle)
                .translatedBy(x: -(c + x), y: -(c + y))
            return path.applying(spin)
        }

        var pad = Path()
        pad.move(to: CGPoint(x: c + 0, y: c + 6))
        pad.addCurve(to: CGPoint(x: c + 40, y: c + 28),
                     control1: CGPoint(x: c + 16, y: c + 6),
                     control2: CGPoint(x: c + 26, y: c + 20))
        pad.addCurve(to: CGPoint(x: c + 38, y: c + 62),
                     control1: CGPoint(x: c + 54, y: c + 36),
                     control2: CGPoint(x: c + 52, y: c + 56))
        pad.addCurve(to: CGPoint(x: c + 0, y: c + 62),
                     control1: CGPoint(x: c + 26, y: c + 67),
                     control2: CGPoint(x: c + 12, y: c + 62))
        pad.addCurve(to: CGPoint(x: c - 38, y: c + 62),
                     control1: CGPoint(x: c - 12, y: c + 62),
                     control2: CGPoint(x: c - 26, y: c + 67))
        pad.addCurve(to: CGPoint(x: c - 40, y: c + 28),
                     control1: CGPoint(x: c - 52, y: c + 56),
                     control2: CGPoint(x: c - 54, y: c + 36))
        pad.addCurve(to: CGPoint(x: c + 0, y: c + 6),
                     control1: CGPoint(x: c - 26, y: c + 20),
                     control2: CGPoint(x: c - 16, y: c + 6))
        pad.closeSubpath()

        return [
            ellipse(0, -2, 50, 30, 0),      // bridge
            ellipse(-62, -4, 17, 22, -25),  // outer-left toe
            ellipse(-24, -40, 18, 24, -10), // inner-left toe
            ellipse(24, -40, 18, 24, 10),   // inner-right toe
            ellipse(62, -4, 17, 22, 25),    // outer-right toe
            pad,                            // main pad
        ]
    }
}
