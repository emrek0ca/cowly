import AppKit
import Observation
import SwiftUI

/// Watches for a "jiggled" drag anywhere on screen and flies a floating basket
/// in under the cursor so the drag has somewhere to land.
@MainActor
@Observable
final class BasketController {
    static let shared = BasketController()

    private(set) var isVisible = false
    private(set) var isTargeted = false
    /// Number of items currently parked in the basket this session.
    var caughtCount = 0

    private var panel: NSPanel?
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var downMonitor: Any?

    private var dragBaselineChangeCount = 0
    private var isDragSession = false
    private var lastPoint: CGPoint = .zero
    private var lastDirection: Int = 0
    private var reversals: [Date] = []
    private var hideTask: Task<Void, Never>?

    private init() {}

    // MARK: - Monitoring

    func start() {
        guard dragMonitor == nil else { return }
        dragBaselineChangeCount = NSPasteboard(name: .drag).changeCount

        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetSession() }
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleDrag(event) }
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseUp() }
        }
    }

    func stop() {
        [dragMonitor, upMonitor, downMonitor].compactMap { $0 }.forEach(NSEvent.removeMonitor)
        dragMonitor = nil
        upMonitor = nil
        downMonitor = nil
        hide()
    }

    private func resetSession() {
        isDragSession = false
        reversals.removeAll()
        lastDirection = 0
        lastPoint = NSEvent.mouseLocation
        dragBaselineChangeCount = NSPasteboard(name: .drag).changeCount
    }

    private func handleDrag(_ event: NSEvent) {
        guard Preferences.shared.basketEnabled else { return }
        let point = NSEvent.mouseLocation

        if !isDragSession {
            // A real drag session bumps the dedicated drag pasteboard.
            isDragSession = NSPasteboard(name: .drag).changeCount != dragBaselineChangeCount
            lastPoint = point
            guard isDragSession else { return }
        }

        let dx = point.x - lastPoint.x
        guard abs(dx) > 6 else { return }
        let direction = dx > 0 ? 1 : -1
        if lastDirection != 0, direction != lastDirection {
            reversals.append(.now)
        }
        lastDirection = direction
        lastPoint = point

        // Three direction changes inside 700 ms reads as a deliberate shake.
        let cutoff = Date.now.addingTimeInterval(-0.7)
        reversals.removeAll { $0 < cutoff }
        if reversals.count >= 3, !isVisible {
            reversals.removeAll()
            show(near: point)
        }
    }

    private func handleMouseUp() {
        isDragSession = false
        reversals.removeAll()
        lastDirection = 0
        guard isVisible, !isTargeted else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    // MARK: - Panel

    private func show(near point: CGPoint) {
        hideTask?.cancel()
        let size = CGSize(width: 168, height: 168)
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        // Sit just below-right of the cursor, nudged back on screen if needed.
        var origin = CGPoint(x: point.x + 26, y: point.y - size.height - 12)
        origin.x = min(max(visible.minX + 12, origin.x), visible.maxX - size.width - 12)
        origin.y = min(max(visible.minY + 12, origin.y), visible.maxY - size.height - 12)

        let frame = CGRect(origin: origin, size: size)
        let panel = self.panel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel
        isVisible = true
        Haptics.tap(.alignment)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        hideTask?.cancel()
        isVisible = false
        isTargeted = false
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: BasketView())
        return panel
    }

    // MARK: - Drop

    func setTargeted(_ targeted: Bool) {
        guard isTargeted != targeted else { return }
        isTargeted = targeted
        if targeted { Haptics.tap(.alignment) }
    }

    func accept(providers: [NSItemProvider]) {
        Task {
            let count = await DropHandling.receive(providers: providers)
            caughtCount += count
            hide()
            if count > 0 { NotchViewModel.shared.open(tab: .tray) }
        }
    }
}
