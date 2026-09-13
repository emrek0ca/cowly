import AppKit
import SwiftUI

/// Menu-bar item: a way in when the notch is busy, plus the usual app commands.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let item: NSStatusItem

    override init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.image = CowMark.statusItemImage()
            button.image?.accessibilityDescription = "Cowly"
            button.toolTip = "Cowly"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(action("Open Shelf", key: "d") { NotchViewModel.shared.open(tab: .home) })
        menu.addItem(action("Open Tray") { NotchViewModel.shared.open(tab: .tray) })
        menu.addItem(action("Open Droplets") { NotchViewModel.shared.open(tab: .droplets) })
        menu.addItem(.separator())

        let tray = TrayStore.shared
        let trayInfo = NSMenuItem(
            title: tray.isEmpty ? "Tray is empty" : "\(tray.items.count) files · \(tray.totalSize.byteLabel)",
            action: nil, keyEquivalent: ""
        )
        trayInfo.isEnabled = false
        menu.addItem(trayInfo)
        if !tray.isEmpty {
            menu.addItem(action("Share Tray…") { SharePresenter.present(urls: tray.sorted.map(\.url)) })
            menu.addItem(action("Clear Tray") { tray.removeAll() })
        }
        menu.addItem(.separator())

        let alert = HighAlertEngine.shared
        menu.addItem(action(alert.isActive ? "Turn off High Alert" : "Keep Mac Awake") { alert.toggle() })

        let docks = NSMenu()
        for edge in DockEdge.allCases {
            let config = SideDockController.shared.configuration(for: edge)
            let item = action("\(edge.label) dock") {
                SideDockController.shared.setEnabled(!config.isEnabled, for: edge)
            }
            item.state = config.isEnabled ? .on : .off
            docks.addItem(item)
        }
        docks.addItem(.separator())
        docks.addItem(action("Configure docks…") { SettingsWindowController.shared.show() })
        let docksItem = NSMenuItem(title: "Side Docks", action: nil, keyEquivalent: "")
        docksItem.submenu = docks
        menu.addItem(docksItem)

        menu.addItem(action("Cover Screen (⌥⌘L)") { LockScreenController.shared.present() })

        let gate = BiometricGate.shared
        if !gate.unlocked.isEmpty {
            menu.addItem(action("Lock Cowly Now") { gate.lockAll() })
        }
        menu.addItem(.separator())

        menu.addItem(action("Settings…", key: ",") { SettingsWindowController.shared.show() })
        menu.addItem(action("Quit Cowly", key: "q") { NSApp.terminate(nil) })
    }

    private func action(_ title: String, key: String = "", handler: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire(_:)), keyEquivalent: key)
        let target = MenuAction(handler: handler)
        item.target = target
        item.representedObject = target
        return item
    }
}

/// Keeps a closure alive for the lifetime of its menu item.
private final class MenuAction: NSObject {
    private let handler: () -> Void
    init(handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler() }
}
