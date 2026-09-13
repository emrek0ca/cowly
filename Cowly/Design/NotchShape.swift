import SwiftUI

/// The signature Dynamic-Island silhouette: concave shoulders at the top so the
/// panel melts into the hardware notch, generous rounding at the bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    init(topRadius: CGFloat = 12, bottomRadius: CGFloat = 22) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        // The straight sides sit `top` inside the frame and the shoulders flare
        // out to the frame edge. Drawing outside the rect — as this used to —
        // made the shelf render wider than the notch it was supposed to match.
        let top = max(0, min(topRadius, rect.width / 2))
        let bottom = max(0, min(bottomRadius, min((rect.width - top * 2) / 2, rect.height / 2)))
        let left = rect.minX + top
        let right = rect.maxX - top

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        if top > 0 {
            path.addQuadCurve(
                to: CGPoint(x: left, y: rect.minY + top),
                control: CGPoint(x: left, y: rect.minY)
            )
        }
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: left + bottom, y: rect.maxY),
            control: CGPoint(x: left, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: right, y: rect.maxY - bottom),
            control: CGPoint(x: right, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + top))
        if top > 0 {
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: right, y: rect.minY)
            )
        }
        path.closeSubpath()
        return path
    }
}
