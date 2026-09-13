import AppKit
import Quartz
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// The file shelf: drop anything in, drag anything back out.
struct TrayPane: View {
    @Environment(\.shelfLayout) private var layout
    var store = TrayStore.shared
    var vm = NotchViewModel.shared

    var body: some View {
        Guarded(.tray) {
            VStack(spacing: layout.blockSpacing) {
                header
                if store.isEmpty {
                    DropZone()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            StackHandle(items: store.sorted)
                            ForEach(store.sorted) { item in
                                TrayCard(item: item)
                            }
                        }
                        .padding(.horizontal, 1)
                        .padding(.vertical, 2)
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Tray")
                .font(Theme.Typo.title)
                .foregroundStyle(Theme.Palette.primaryText)
            if !store.isEmpty {
                Text("\(store.items.count) · \(store.totalSize.byteLabel)")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
            Spacer()
            if !store.isEmpty {
                ShelfButton(symbol: "square.and.arrow.up", title: "Share") {
                    SharePresenter.present(urls: store.sorted.map(\.url))
                }
                ShelfButton(symbol: "arrow.down.circle", title: "Save all to Downloads") {
                    for item in store.sorted { store.saveToDownloads(item) }
                    Haptics.tap(.levelChange)
                }
                ShelfButton(symbol: "trash", title: "Clear tray", tint: Theme.Palette.danger) {
                    clearTray()
                }
            }
        }
    }

    private func clearTray() {
        Task {
            if BiometricGate.shared.requiresAuth(for: .destructive) {
                guard await BiometricGate.shared.authenticate(.destructive) else { return }
            }
            store.removeAll()
        }
    }
}

/// Dashed target shown when the tray is empty.
struct DropZone: View {
    var vm = NotchViewModel.shared

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(vm.isDropTargeted ? Theme.Palette.accent : Theme.Palette.tertiaryText)
            Text("Drop files onto the notch")
                .font(Theme.Typo.subtitle)
                .foregroundStyle(Theme.Palette.secondaryText)
            Text("They stay here until you drag them out")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                )
                .foregroundStyle(vm.isDropTargeted ? Theme.Palette.accent : Color.white.opacity(0.14))
        )
        .animation(Motion.snappy, value: vm.isDropTargeted)
    }
}

/// Grab-everything handle: dragging it carries the whole tray.
struct StackHandle: View {
    @Environment(\.shelfLayout) private var layout
    let items: [TrayItem]
    var store = TrayStore.shared

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.10 + Double(index) * 0.05))
                        .frame(width: 26, height: 32)
                        .rotationEffect(.degrees(Double(index - 1) * 7))
                        .offset(x: CGFloat(index - 1) * 3)
                }
            }
            .frame(height: 34)
            Text("All")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
        .frame(width: layout.trayCardWidth - 20, height: 68)
        .card(radius: Radius.bubble(forHeight: 68))
        .onDrag {
            let provider = NSItemProvider()
            for item in items {
                provider.registerFileRepresentation(
                    forTypeIdentifier: item.typeIdentifier,
                    fileOptions: .openInPlace,
                    visibility: .all
                ) { completion in
                    completion(item.url, true, nil)
                    return nil
                }
            }
            return provider
        }
        .help("Drag every file out at once")
    }
}

/// One file in the tray.
struct TrayCard: View {
    @Environment(\.shelfLayout) private var layout
    let item: TrayItem
    var store = TrayStore.shared
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.Palette.warning)
                        .padding(3)
                }
            }
            Text(item.name)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: layout.trayCardWidth - 8)
        }
        .frame(width: layout.trayCardWidth, height: 68)
        .card(radius: Radius.bubble(forHeight: 68), fill: isHovering ? 0.11 : 0.07)
        .overlay(alignment: .topLeading) {
            if isHovering {
                Button {
                    remove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(isHovering ? 1.04 : 1)
        .animation(Motion.snappy, value: isHovering)
        .onHover { isHovering = $0 }
        .onDrag {
            Haptics.tap(.generic)
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        } preview: {
            thumbnail.frame(width: 64, height: 44)
        }
        .onTapGesture(count: 2) { store.open(item) }
        .onTapGesture { QuickLookPresenter.preview(url: item.url) }
        .contextMenu { menu }
        .help("\(item.name) · \(item.sizeLabel)")
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06))
            if let image = store.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(3)
            } else {
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
        }
        .frame(width: layout.trayCardWidth - 8, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    @ViewBuilder
    private var menu: some View {
        Button("Quick Look") { QuickLookPresenter.preview(url: item.url) }
        Button("Open") { store.open(item) }
        Button("Reveal in Finder") { store.revealInFinder(item) }
        Divider()
        Button("Copy") { store.copyToPasteboard([item]) }
        Button("Save to Downloads") { store.saveToDownloads(item) }
        Button("Share…") { SharePresenter.present(urls: [item.url]) }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(item) }
        Button("Remove", role: .destructive) { remove() }
    }

    private func remove() {
        Task {
            if BiometricGate.shared.requiresAuth(for: .destructive) {
                guard await BiometricGate.shared.authenticate(.destructive) else { return }
            }
            store.remove(item)
        }
    }
}

/// Small pill button used across the shelf headers.
struct ShelfButton: View {
    let symbol: String
    var title: String
    var tint: Color = Theme.Palette.secondaryText
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isHovering ? .white : tint)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
                .controlBubble(radius: 9, tint: isHovering ? tint : nil)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(title)
    }
}

/// Presents the system share sheet (AirDrop, Messages, Mail…) from the shelf.
@MainActor
enum SharePresenter {
    private static var keepAlive: SharePickerDelegate?

    static func present(urls: [URL]) {
        guard !urls.isEmpty, let window = NotchWindowController.shared.panel,
              let view = window.contentView else { return }
        NotchViewModel.shared.open(tab: .tray)
        NotchViewModel.shared.beginInteraction()

        let picker = NSSharingServicePicker(items: urls)
        let delegate = SharePickerDelegate()
        picker.delegate = delegate
        keepAlive = delegate
        picker.show(
            relativeTo: CGRect(x: view.bounds.midX, y: 40, width: 1, height: 1),
            of: view,
            preferredEdge: .minY
        )
    }

    private final class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
        func sharingServicePicker(
            _ picker: NSSharingServicePicker,
            didChoose service: NSSharingService?
        ) {
            MainActor.assumeIsolated {
                NotchViewModel.shared.endInteraction()
                SharePresenter.keepAlive = nil
            }
        }
    }
}

/// Quick Look, driven straight from the shelf.
@MainActor
final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    fileprivate static let shared = QuickLookPresenter()
    private var urls: [URL] = []

    static func preview(url: URL) { preview(urls: [url]) }

    static func preview(urls: [URL]) {
        shared.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = shared
        panel.delegate = shared
        // Quick Look steals key focus, so hold the shelf open until it closes.
        NotchViewModel.shared.beginInteraction()
        shared.observeClose(of: panel)
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
    }

    private var closeObserver: (any NSObjectProtocol)?

    private func observeClose(of panel: QLPreviewPanel) {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            NotchViewModel.shared.endInteraction()
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NotchViewModel.shared.endInteraction()
                if let token = QuickLookPresenter.shared.closeObserver {
                    NotificationCenter.default.removeObserver(token)
                    QuickLookPresenter.shared.closeObserver = nil
                }
            }
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }
}
