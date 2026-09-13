import AppKit
import SwiftUI

/// A normal, resizable settings window — the one place Cowly looks like a
/// regular Mac app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        Task {
            if BiometricGate.shared.requiresAuth(for: .settings) {
                guard await BiometricGate.shared.unlock(.settings) else { return }
            }
            present()
        }
    }

    private func present() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Cowly Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 720, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
