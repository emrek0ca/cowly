import AppKit
import SwiftUI

/// Everything we need to know about the screen we are living on.
struct NotchGeometry: Equatable, Sendable {
    /// Size of the physical notch, or the size of the fake island when there is none.
    var closedSize: CGSize
    var openSize: CGSize
    /// True when the Mac actually has a hardware notch on this screen.
    var hasHardwareNotch: Bool
    /// Frame of the whole panel window in screen coordinates.
    var windowFrame: CGRect
    var screenID: CGDirectDisplayID

    static let fallback = NotchGeometry(
        closedSize: CGSize(width: Theme.Metrics.closedIslandWidth, height: Theme.Metrics.closedIslandHeight),
        openSize: CGSize(width: Theme.Metrics.openWidth, height: Theme.Metrics.openHeight),
        hasHardwareNotch: false,
        windowFrame: .zero,
        screenID: 0
    )

    /// Rect of the closed shelf inside the window, in SwiftUI (top-left) coordinates.
    var closedRect: CGRect {
        CGRect(
            x: (windowFrame.width - closedSize.width) / 2,
            y: 0,
            width: closedSize.width,
            height: closedSize.height
        )
    }

    var openRect: CGRect {
        CGRect(
            x: (windowFrame.width - openSize.width) / 2,
            y: 0,
            width: openSize.width,
            height: openSize.height
        )
    }

    static func measure(for screen: NSScreen, widthScale: Double, islandFraction: Double) -> NotchGeometry {
        let frame = screen.frame
        let displayID = screen.displayID

        var notchWidth: CGFloat = 0
        var notchHeight: CGFloat = 0

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = frame.width - left.width - right.width
            notchHeight = max(left.height, right.height)
        }
        if notchHeight <= 0 {
            notchHeight = screen.safeAreaInsets.top
        }

        let hasNotch = notchWidth > 40 && notchHeight > 10
        // Pixel-exact to the hardware cut-out: anything else shows as a ledge
        // sticking out from under the bezel. On a display without one, the fake
        // island is sized from the screen so a 27" monitor does not get the
        // same sliver as a 13" laptop.
        let closed: CGSize
        if hasNotch {
            closed = CGSize(width: notchWidth.rounded(), height: notchHeight.rounded())
        } else {
            let width = min(max(frame.width * islandFraction, 150), 320).rounded()
            closed = CGSize(width: width, height: Theme.Metrics.closedIslandHeight)
        }

        // The open shelf is a multiple of the notch, so it always looks like the
        // same object growing rather than an unrelated panel.
        let scale = widthScale
        let openWidth = min((closed.width * scale).rounded(), frame.width - 40)
        // The stored height is the roomiest a shelf can get; each tab then asks
        // for exactly what it needs inside that envelope.
        let layout = ShelfLayout(width: openWidth)
        let topInset = hasNotch ? closed.height + 2 : 12
        let tallest = ShelfTab.allCases
            .map { layout.contentHeight(for: $0, topInset: topInset, hasShelfWidgets: true) }
            .max() ?? Theme.Metrics.openHeight
        let open = CGSize(width: openWidth, height: tallest.rounded())

        // The panel is always big enough for the widest state plus a hover gutter,
        // and hangs from the very top edge of the screen.
        let panelWidth = max(open.width, closed.width) + 160
        let panelHeight = open.height + 160
        let panelFrame = CGRect(
            x: frame.midX - panelWidth / 2,
            y: frame.maxY - panelHeight,
            width: panelWidth,
            height: panelHeight
        )

        return NotchGeometry(
            closedSize: closed,
            openSize: open,
            hasHardwareNotch: hasNotch,
            windowFrame: panelFrame,
            screenID: displayID
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// The screen the pointer is currently on, falling back to the built-in one.
    @MainActor
    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(location) } ?? .main
    }

    @MainActor
    static var preferred: NSScreen? {
        let allowed = DisplayRegistry.shared.enabledScreens
        guard !allowed.isEmpty else { return nil }
        if Preferences.shared.followMouseScreen,
           let under = underMouse, allowed.contains(under) {
            return under
        }
        return allowed.first { $0.safeAreaInsets.top > 0 }
            ?? allowed.first { $0 == .main }
            ?? allowed.first
    }
}
