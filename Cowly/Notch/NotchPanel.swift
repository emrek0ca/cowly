import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Only text fields should pull key focus. Forcing it on every click made
        // the panel grab focus mid-press and swallow the click.
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        // The shelf is a dark surface no matter what the system appearance is.
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

/// Hosting view that only swallows clicks inside the live shelf silhouette;
/// every other pixel of the (much larger) panel stays click-through so the
/// desktop underneath keeps working.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    /// Interactive area in view coordinates (origin top-left, matching SwiftUI).
    var interactiveRect: CGRect = .zero

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Without this the very first click on an inactive window is spent just
    /// focusing it, which reads as "the buttons do nothing".
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        // Convert AppKit's bottom-left point into the SwiftUI top-left space.
        let local = convert(point, from: superview)
        let flipped = CGPoint(x: local.x, y: bounds.height - local.y)
        guard interactiveRect.contains(flipped) else { return nil }
        return super.hitTest(point)
    }
}
