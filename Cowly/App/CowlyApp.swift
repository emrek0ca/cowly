import AppKit
import SwiftUI

@main
struct CowlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Everything lives in the notch panel and the menu bar, so the app
        // itself owns no regular windows.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var hotKeyMonitor: Any?
    private var localKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let folder = PreviewRenderer.requestedPath {
            PreviewRenderer.run(into: folder)
            return
        }
        if HitTestProbe.isRequested {
            HitTestProbe.run()
            return
        }
        if AIUsageProbe.isRequested {
            AIUsageProbe.run()
            return
        }
        if PreferencesProbe.isRequested {
            PreferencesProbe.run()
            return
        }
        if LayerDump.isRequested {
            LayerDump.run()
            return
        }

        NotchWindowController.shared.install()
        menuBar = MenuBarController()

        // Always-on services: the shelf itself depends on these.
        MediaController.shared.start()
        AudioOutput.shared.start()
        HUDController.shared.start()
        BasketController.shared.start()
        SideDockController.shared.start()

        // Everything droplet-backed follows the enabled set, now and whenever
        // it changes.
        DropletLifecycle.sync()
        PermissionCenter.shared.start()

        installHotKey()
        showWelcomeIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyMonitor { NSEvent.removeMonitor(hotKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        PermissionCenter.shared.stop()
        HighAlertEngine.shared.deactivate()
        ClipboardStore.shared.stop()
        BasketController.shared.stop()
        SideDockController.shared.stop()
        MediaController.shared.stop()
        HUDController.shared.stop()
        NotchWindowController.shared.teardown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotchViewModel.shared.open()
        return false
    }

    /// ⌥⌘C toggles the shelf from anywhere (needs Accessibility permission);
    /// Escape closes it while it has focus.
    private func installHotKey() {
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .option] else { return }
            switch event.keyCode {
            case 8: MainActor.assumeIsolated { NotchViewModel.shared.toggle() }
            case 37: MainActor.assumeIsolated { LockScreenController.shared.toggle() }
            default: break
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 /* Escape */ {
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard NotchViewModel.shared.state == .open else { return false }
                    NotchViewModel.shared.close(force: true)
                    return true
                }
                if handled { return nil }
            }
            if event.modifierFlags.contains([.command, .option]), event.keyCode == 8 {
                MainActor.assumeIsolated { NotchViewModel.shared.toggle() }
                return nil
            }
            if event.modifierFlags.contains([.command, .option]), event.keyCode == 37 /* L */ {
                MainActor.assumeIsolated { LockScreenController.shared.toggle() }
                return nil
            }
            return event
        }
    }

    private func showWelcomeIfNeeded() {
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            NotchViewModel.shared.present(
                LiveActivity(
                    style: .expanded,
                    leadingSymbol: "sparkles",
                    leadingTint: Theme.Palette.accent,
                    title: "Moo — Cowly is grazing",
                    subtitle: "Hover the notch, or drop a file on it",
                    duration: 5
                )
            )
        }
    }
}
