import AppKit
import SwiftUI

/// Renders the shelf offscreen to a PNG. Used during development to check
/// layout without needing a screen recording of the real notch.
///
/// `Cowly.app/Contents/MacOS/Cowly --render-preview <folder>`
@MainActor
enum PreviewRenderer {
    static var requestedPath: String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--render-preview"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func run(into folder: String) {
        let vm = NotchViewModel.shared
        vm.refreshGeometry(for: NSScreen.main)
        // Development harness only: never leave the real shelf changed behind.
        let originalStyle = Preferences.shared.glassStyle
        let preexistingTrayIDs = Set(TrayStore.shared.items.map(\.id))
        TrayStore.shared.add(urls: sampleFiles())

        // Native Liquid Glass and ScrollView content cannot be rasterised
        // offscreen, so the audit pass uses the tinted material instead.
        Preferences.shared.glassStyle = .tinted

        renderAudit(into: folder)
        renderDensities(into: folder)
        renderLayoutDebug(into: folder)

        let shots: [(String, () -> Void)] = [
            ("home", { vm.tab = .home; vm.state = .open }),
            ("tray", { vm.tab = .tray; vm.state = .open }),
            ("droplets", { vm.tab = .droplets; vm.state = .open }),
            ("activity", {
                vm.state = .closed
                vm.present(LiveActivity(
                    leadingSymbol: "bolt.fill", leadingTint: Theme.Palette.positive,
                    title: "Charging", subtitle: "1h 12m to full",
                    progress: 0.62, trailingText: "62%", duration: nil
                ))
            })
        ]

        for (name, configure) in shots {
            configure()
            let size = vm.geometry.windowFrame.size
            let renderer = ImageRenderer(
                content: NotchRootView()
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.13, blue: 0.26), Color(red: 0.07, green: 0.10, blue: 0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .environment(\.colorScheme, .dark)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = URL(fileURLWithPath: folder).appendingPathComponent("shelf-\(name).png")
            try? png.write(to: url)
        }
        for item in TrayStore.shared.items where !preexistingTrayIDs.contains(item.id) {
            TrayStore.shared.remove(item)
        }
        Preferences.shared.glassStyle = originalStyle
        exit(0)
    }

    /// Draws the real OpenShelfView at its real size with every block outlined,
    /// which is the only reliable way to see where vertical space is going.
    private static func renderLayoutDebug(into folder: String) {
        let vm = NotchViewModel.shared
        for (width, tab) in [(320.0, ShelfTab.home), (470.0, .home), (640.0, .home),
                             (470.0, .tray), (470.0, .droplets)] {
            NotchViewModel.shared.tab = tab
            let layout = ShelfLayout(width: width)
            let height = layout.contentHeight(for: tab, topInset: 12, hasShelfWidgets: true)
            print(String(
                format: "%@ %.0fpt (%@): sides %.0f, top %.0f+%.0f, bottom %.0f, blocks %.0f → content %.0f×%.0f",
                tab.rawValue, width, String(describing: layout.density),
                layout.contentPadding, 12.0, layout.topPadding, layout.bottomPadding,
                layout.blockSpacing,
                width - layout.contentPadding * 2,
                height - 12 - layout.topPadding - layout.bottomPadding
            ))
            let content = OpenShelfView()
                .environment(\.shelfLayout, layout)
                .environment(\.layoutDebug, true)
                .frame(width: width, height: height, alignment: .top)
                .background(Color(red: 0.10, green: 0.11, blue: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.shelf, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                )
                .padding(16)
                .background(Color(red: 0.04, green: 0.05, blue: 0.07))
                .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(
                to: URL(fileURLWithPath: folder)
                    .appendingPathComponent("layout-\(tab.rawValue)-\(Int(width)).png")
            )
        }
        _ = vm
    }

    /// Renders the Home pane at each density so the responsive rules can be
    /// checked without resizing anything by hand.
    private static func renderDensities(into folder: String) {
        for width in [330.0, 470.0, 620.0] {
            let layout = ShelfLayout(width: width)
            let content = VStack(alignment: .leading, spacing: 10) {
                Text("width \(Int(width)) · \(String(describing: layout.density))")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(.white.opacity(0.5))
                VStack(spacing: layout.blockSpacing) {
                    MediaWidget()
                    HStack(spacing: layout.widgetSpacing) {
                        ForEach(Array(Droplet.all.filter(\.hasWidget).prefix(3))) {
                            DropletWidget(droplet: $0)
                        }
                    }
                    .frame(height: layout.widgetHeight, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
                .padding(layout.contentPadding)
                .frame(width: width, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.shelf, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.shelf, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
                )
            }
            .environment(\.shelfLayout, layout)
            .padding(20)
            .frame(width: width + 40, alignment: .leading)
            .background(Color(red: 0.07, green: 0.08, blue: 0.12))
            .environment(\.colorScheme, .dark)

            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("density-\(Int(width)).png"))
        }
    }

    /// Same components the shelf uses, laid out without scroll views so the
    /// rasteriser can actually draw them.
    private static func renderAudit(into folder: String) {
        let content = VStack(alignment: .leading, spacing: 18) {
            Text("Droplet widgets").font(Theme.Typo.title).foregroundStyle(.white)
            HStack(spacing: 10) {
                ForEach(Array(Droplet.all.filter(\.hasWidget).prefix(4))) { DropletWidget(droplet: $0) }
            }
            HStack(spacing: 10) {
                ForEach(Array(Droplet.all.filter(\.hasWidget).dropFirst(4).prefix(4))) { DropletWidget(droplet: $0) }
            }
            Text("Tray cards").font(Theme.Typo.title).foregroundStyle(.white)
            HStack(spacing: 10) {
                StackHandle(items: TrayStore.shared.sorted)
                ForEach(TrayStore.shared.sorted) { TrayCard(item: $0) }
            }
            Text("Droplet tiles").font(Theme.Typo.title).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(Droplet.all) { droplet in
                    DropletTile(droplet: droplet, open: {}, toggle: {})
                }
            }
            Text("Pomodoro pane").font(Theme.Typo.title).foregroundStyle(.white)
            PomodoroPane()
            Text("Cow mark").font(Theme.Typo.title).foregroundStyle(.white)
            HStack(alignment: .center, spacing: 26) {
                ForEach([18.0, 28.0, 44.0, 72.0], id: \.self) { size in
                    VStack(spacing: 6) {
                        CowFace(size: size)
                        Text("\(Int(size))").font(Theme.Typo.caption).foregroundStyle(.white)
                    }
                }
                VStack(spacing: 6) {
                    Image(nsImage: CowMark.statusItemImage(size: 18))
                        .renderingMode(.template)
                        .foregroundStyle(.white)
                    Text("menu bar").font(Theme.Typo.caption).foregroundStyle(.white)
                }
                CowFace(size: 44, tint: Theme.Palette.accent)
            }

            Text("Shelf rail").font(Theme.Typo.title).foregroundStyle(.white)
            HStack(spacing: ShelfLayout.fallback.widgetSpacing) {
                ForEach(Array(Droplet.all.filter(\.hasWidget).prefix(4))) { DropletWidget(droplet: $0) }
            }
            Text("Lock overlay").font(Theme.Typo.title).foregroundStyle(.white)
            LockOverlay(scope: .tray).frame(height: 150)
        }
        .padding(22)
        .frame(width: 760, alignment: .leading)
        .background(Color(red: 0.07, green: 0.08, blue: 0.12))
        .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("audit.png"))
    }

    private static func sampleFiles() -> [URL] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cowly-preview", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let names = ["Vakantie.jpg", "Demo reel.mov", "Invoice.pdf", "Notes.txt"]
        return names.compactMap { name in
            let url = dir.appendingPathComponent(name)
            try? Data(repeating: 0, count: 2048).write(to: url)
            return url
        }
    }
}
