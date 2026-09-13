import AppKit
import SwiftUI

/// AppKit-backed pop-up menu.
///
/// SwiftUI's `Menu` misbehaves inside a non-activating panel — it opens under
/// the shelf or dismisses on the first move — so the shelf drives NSMenu
/// directly and holds itself open for as long as the menu is tracking.
@MainActor
enum ShelfMenu {
    struct Item {
        var title: String
        var symbol: String?
        var isOn: Bool = false
        var isSeparator: Bool = false
        var action: (() -> Void)?

        static var separator: Item { Item(title: "", isSeparator: true) }
    }

    static func present(_ items: [Item]) {
        guard let panel = NotchWindowController.shared.panel,
              let view = panel.contentView else { return }

        let menu = NSMenu()
        menu.font = .systemFont(ofSize: 13)
        var holders: [MenuActionHolder] = []

        for item in items {
            if item.isSeparator {
                menu.addItem(.separator())
                continue
            }
            let menuItem = NSMenuItem(
                title: item.title,
                action: item.action == nil ? nil : #selector(MenuActionHolder.fire),
                keyEquivalent: ""
            )
            if let symbol = item.symbol {
                menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menuItem.state = item.isOn ? .on : .off
            if let action = item.action {
                let holder = MenuActionHolder(action: action)
                holders.append(holder)
                menuItem.target = holder
                menuItem.representedObject = holder
            }
            menu.addItem(menuItem)
        }

        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = view.convert(windowPoint, from: nil)
        // NSMenu.popUp runs its own event loop, so the shelf is unpinned again
        // as soon as it returns.
        NotchViewModel.shared.beginInteraction()
        defer { NotchViewModel.shared.endInteraction() }
        menu.popUp(positioning: nil, at: viewPoint, in: view)
        withExtendedLifetime(holders) {}
    }
}

private final class MenuActionHolder: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

/// Button that opens a `ShelfMenu` when clicked.
struct ShelfMenuButton<Label: View>: View {
    var items: () -> [ShelfMenu.Item]
    @ViewBuilder var label: () -> Label

    init(items: @escaping () -> [ShelfMenu.Item], @ViewBuilder label: @escaping () -> Label) {
        self.items = items
        self.label = label
    }

    var body: some View {
        Button {
            ShelfMenu.present(items())
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}
