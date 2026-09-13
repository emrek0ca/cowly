import AppKit
import SwiftUI

/// Cowly's mark, defined once as proportions of its canvas.
///
/// The same geometry draws the 1024pt app icon, the 18pt menu bar template and
/// the in-app glyph, so the three can never drift apart. Everything is a
/// fraction of the canvas, measured from the top-left, and flipped once where
/// Core Graphics needs it.
enum CowGeometry {
    static let headWidth: CGFloat = 0.355
    static let headHeight: CGFloat = 0.345
    static let headCenterY: CGFloat = 0.535

    static let earWidth: CGFloat = 0.158
    static let earHeight: CGFloat = 0.092
    static let earOffsetX: CGFloat = 0.222
    static let earCenterY: CGFloat = 0.436
    static let earTilt: CGFloat = -0.26

    static let hornRadius: CGFloat = 0.043
    static let hornOffsetX: CGFloat = 0.088
    static let hornCenterY: CGFloat = 0.325
    static let stalkWidth: CGFloat = 0.026

    static let eyeRadius: CGFloat = 0.0225
    static let eyeOffsetX: CGFloat = 0.0725
    static let eyeCenterY: CGFloat = 0.484

    static let muzzleWidth: CGFloat = 0.200
    static let muzzleHeight: CGFloat = 0.132
    static let muzzleCenterY: CGFloat = 0.618

    static let nostrilWidth: CGFloat = 0.020
    static let nostrilHeight: CGFloat = 0.044
    static let nostrilOffsetX: CGFloat = 0.0525

    /// Head, ears, horns and stalks as one filled shape.
    /// `flipped` is true for Core Graphics contexts whose origin is bottom-left.
    static func silhouette(in rect: CGRect, flipped: Bool) -> CGPath {
        let s = min(rect.width, rect.height)
        func x(_ f: CGFloat) -> CGFloat { rect.midX + f * s }
        func y(_ f: CGFloat) -> CGFloat { flipped ? rect.maxY - f * s : rect.minY + f * s }

        let path = CGMutablePath()

        for side in [CGFloat(-1), 1] {
            // Stalk first, cap second: the join disappears inside the circle.
            let hornY = y(hornCenterY)
            let baseY = y(headCenterY - headHeight / 2 + 0.02)
            let cx = x(side * hornOffsetX)
            let width = stalkWidth * s
            path.addRoundedRect(
                in: CGRect(
                    x: cx - width / 2,
                    y: min(hornY, baseY),
                    width: width,
                    height: abs(hornY - baseY)
                ),
                cornerWidth: width / 2,
                cornerHeight: width / 2
            )
            path.addEllipse(in: CGRect(
                x: cx - hornRadius * s,
                y: hornY - hornRadius * s,
                width: hornRadius * 2 * s,
                height: hornRadius * 2 * s
            ))
        }

        for side in [CGFloat(-1), 1] {
            let ear = CGRect(
                x: -earWidth * s / 2,
                y: -earHeight * s / 2,
                width: earWidth * s,
                height: earHeight * s
            )
            let tilt = flipped ? -side * earTilt : side * earTilt
            let transform = CGAffineTransform(
                translationX: x(side * earOffsetX),
                y: y(earCenterY)
            ).rotated(by: tilt)
            path.addEllipse(in: ear, transform: transform)
        }

        let headTop = y(headCenterY - headHeight / 2)
        let headBottom = y(headCenterY + headHeight / 2)
        let head = CGRect(
            x: x(-headWidth / 2),
            y: min(headTop, headBottom),
            width: headWidth * s,
            height: abs(headBottom - headTop)
        )
        path.addRoundedRect(
            in: head,
            cornerWidth: head.width * 0.40,
            cornerHeight: head.width * 0.40
        )
        return path
    }

    /// Eyes and muzzle, punched out of the silhouette.
    static func faceHoles(in rect: CGRect, flipped: Bool) -> CGPath {
        let s = min(rect.width, rect.height)
        func x(_ f: CGFloat) -> CGFloat { rect.midX + f * s }
        func y(_ f: CGFloat) -> CGFloat { flipped ? rect.maxY - f * s : rect.minY + f * s }

        let path = CGMutablePath()
        for side in [CGFloat(-1), 1] {
            path.addEllipse(in: CGRect(
                x: x(side * eyeOffsetX) - eyeRadius * s,
                y: y(eyeCenterY) - eyeRadius * s,
                width: eyeRadius * 2 * s,
                height: eyeRadius * 2 * s
            ))
        }
        let top = y(muzzleCenterY - muzzleHeight / 2)
        let bottom = y(muzzleCenterY + muzzleHeight / 2)
        let muzzle = CGRect(
            x: x(-muzzleWidth / 2),
            y: min(top, bottom),
            width: muzzleWidth * s,
            height: abs(bottom - top)
        )
        path.addRoundedRect(
            in: muzzle,
            cornerWidth: muzzle.height * 0.44,
            cornerHeight: muzzle.height * 0.44
        )
        return path
    }

    static func nostrils(in rect: CGRect, flipped: Bool) -> CGPath {
        let s = min(rect.width, rect.height)
        func x(_ f: CGFloat) -> CGFloat { rect.midX + f * s }
        func y(_ f: CGFloat) -> CGFloat { flipped ? rect.maxY - f * s : rect.minY + f * s }

        let path = CGMutablePath()
        for side in [CGFloat(-1), 1] {
            let w = nostrilWidth * s
            let h = nostrilHeight * s
            path.addRoundedRect(
                in: CGRect(
                    x: x(side * nostrilOffsetX) - w / 2,
                    y: y(muzzleCenterY) - h / 2,
                    width: w, height: h
                ),
                cornerWidth: w / 2, cornerHeight: w / 2
            )
        }
        return path
    }
}

enum CowMark {
    /// Template image for the status item. Below about 20pt the nostrils close
    /// up into a smudge, so they are dropped and the eyes carry the face.
    static func statusItemImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
        ctx.setAllowsAntialiasing(true)

        // The mark is drawn edge to edge: the menu bar supplies its own margin.
        let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: -size * 0.07, dy: -size * 0.07)

        ctx.setFillColor(.black)
        ctx.addPath(CowGeometry.silhouette(in: rect, flipped: true))
        ctx.fillPath()

        ctx.setBlendMode(.clear)
        ctx.addPath(CowGeometry.faceHoles(in: rect, flipped: true))
        ctx.fillPath()
        ctx.setBlendMode(.normal)

        if size >= 20 {
            ctx.setFillColor(.black)
            ctx.addPath(CowGeometry.nostrils(in: rect, flipped: true))
            ctx.fillPath()
        }

        image.isTemplate = true
        return image
    }
}

/// The mark as a SwiftUI view, for empty states and the basket.
struct CowFace: View {
    var size: CGFloat = 44
    var tint: Color = .white

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            // Canvas is top-left origin, so no flip here.
            context.fill(Path(CowGeometry.silhouette(in: rect, flipped: false)), with: .color(tint))
            context.blendMode = .destinationOut
            context.fill(Path(CowGeometry.faceHoles(in: rect, flipped: false)), with: .color(.black))
            context.blendMode = .normal
            if canvasSize.width >= 26 {
                context.fill(Path(CowGeometry.nostrils(in: rect, flipped: false)), with: .color(tint))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Cowly")
    }
}

/// Lazy cow-hide spots, used to keep empty states from looking blank.
struct CowSpots: View {
    var opacity: Double = 0.05

    var body: some View {
        Canvas { context, size in
            let spots: [(CGFloat, CGFloat, CGFloat)] = [
                (0.12, 0.28, 0.16), (0.74, 0.18, 0.12),
                (0.46, 0.72, 0.13), (0.88, 0.66, 0.10)
            ]
            for (x, y, r) in spots {
                let radius = size.width * r
                let rect = CGRect(
                    x: size.width * x - radius / 2,
                    y: size.height * y - radius / 2,
                    width: radius * 1.35,
                    height: radius
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: radius * 0.48, style: .continuous),
                    with: .color(.white.opacity(opacity))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
