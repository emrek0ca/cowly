import AppKit
import SwiftUI

/// Owns the notch panel: keeps it on the right screen, sized correctly, and
/// keeps its click-through region in sync with the shelf's current silhouette.
@MainActor
final class NotchWindowController {
    static let shared = NotchWindowController()

    private(set) var panel: NotchPanel?
    private var hostingView: PassthroughHostingView<NotchRootView>?
    private var syncTimer: Timer?

    private init() {}

    func install() {
        guard panel == nil else { return }
        let vm = NotchViewModel.shared
        vm.refreshGeometry(for: NSScreen.preferred)

        let panel = NotchPanel(contentRect: vm.geometry.windowFrame)
        let hosting = PassthroughHostingView(rootView: NotchRootView())
        hosting.frame = CGRect(origin: .zero, size: vm.geometry.windowFrame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setFrame(vm.geometry.windowFrame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.hostingView = hosting

        observeScreenChanges()
        observeMenuTracking()
        startSync()
    }

    func teardown() {
        syncTimer?.invalidate()
        syncTimer = nil
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }

    // MARK: - Keeping in sync

    /// The shelf changes shape constantly; the panel's hit region has to follow
    /// or the pointer either falls through it or blocks the desktop.
    private func startSync() {
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sync() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer

    }

    func forceSync() { sync() }

    private func sync() {
        let vm = NotchViewModel.shared
        if Preferences.shared.followMouseScreen, vm.state == .closed, !vm.isPointerInside,
           let under = NSScreen.underMouse,
           DisplayRegistry.shared.profile(for: under).isEnabled {
            vm.refreshGeometry(for: under)
        }
        guard let panel, let hostingView else { return }
        if panel.frame != vm.geometry.windowFrame {
            panel.setFrame(vm.geometry.windowFrame, display: true)
            hostingView.frame = CGRect(origin: .zero, size: vm.geometry.windowFrame.size)
        }
        hostingView.interactiveRect = vm.interactiveRect
        updatePointer(panel: panel, vm: vm)
    }

    /// SwiftUI's `onHover` fires spuriously whenever the shelf swaps its
    /// content, which used to snap the shelf shut mid-click. Polling the real
    /// pointer position is both simpler and far steadier.
    private func updatePointer(panel: NotchPanel, vm: NotchViewModel) {
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let rect = vm.interactiveRect
        let screenRect = CGRect(
            x: frame.minX + rect.minX,
            y: frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        ).insetBy(dx: -10, dy: -10)
        vm.pointerMoved(inside: screenRect.contains(mouse))
    }

    /// Screen-space rect of the shelf, for anchoring menus and share sheets.
    var shelfScreenRect: CGRect {
        guard let panel else { return .zero }
        let rect = NotchViewModel.shared.currentRect
        let frame = panel.frame
        return CGRect(
            x: frame.minX + rect.minX,
            y: frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Pop-up and context menus draw in their own window, so the pointer leaves
    /// the shelf the moment one opens. Pin the shelf for as long as one is up.
    private func observeMenuTracking() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchViewModel.shared.beginInteraction() }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NotchViewModel.shared.endInteraction() }
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchViewModel.shared.refreshGeometry(for: NSScreen.preferred)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchViewModel.shared.refreshGeometry(for: NSScreen.preferred)
                NotchWindowController.shared.panel?.orderFrontRegardless()
            }
        }
    }
}
