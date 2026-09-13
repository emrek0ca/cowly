import AppKit
import Observation
import SwiftUI

enum DockEdge: String, CaseIterable, Codable, Sendable, Identifiable {
    case left, right, bottom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        case .bottom: "Bottom"
        }
    }

    var symbol: String {
        switch self {
        case .left: "rectangle.lefthalf.inset.filled"
        case .right: "rectangle.righthalf.inset.filled"
        case .bottom: "rectangle.bottomhalf.inset.filled"
        }
    }

    var isVertical: Bool { self != .bottom }
}

/// One edge dock: which side it lives on, what is in it, and how it behaves.
struct DockConfiguration: Codable, Sendable, Identifiable, Equatable {
    var id: String { edge.rawValue }
    var edge: DockEdge
    var isEnabled: Bool
    var dropletIDs: [String]
    /// Slides out of sight until the pointer touches the edge.
    var autoHide: Bool
    /// 0...1 along the edge; 0.5 is centred.
    var position: Double

    static func `default`(for edge: DockEdge) -> DockConfiguration {
        DockConfiguration(
            edge: edge,
            isEnabled: false,
            dropletIDs: edge == .bottom ? ["stats", "aiusage"] : ["pomodoro", "timer"],
            autoHide: true,
            position: 0.5
        )
    }

    var droplets: [Droplet] { dropletIDs.compactMap(Droplet.find) }
}

/// Docks that live on the edges of the screen, holding the same droplet widgets
/// the notch shelf uses. Handy for the widgets you want visible all the time
/// rather than a hover away.
@MainActor
@Observable
final class SideDockController {
    static let shared = SideDockController()

    private(set) var configurations: [DockConfiguration]
    /// Edges whose dock is currently slid out and visible.
    private(set) var revealed: Set<DockEdge> = []

    private var panels: [DockEdge: NSPanel] = [:]
    private var pollTimer: Timer?

    private init() {
        let stored = Disk.load([DockConfiguration].self, from: Paths.dockStore)
        configurations = DockEdge.allCases.map { edge in
            stored?.first { $0.edge == edge } ?? .default(for: edge)
        }
    }

    func configuration(for edge: DockEdge) -> DockConfiguration {
        configurations.first { $0.edge == edge } ?? .default(for: edge)
    }

    func update(_ configuration: DockConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.edge == configuration.edge }) else { return }
        configurations[index] = configuration
        persist()
        rebuild(edge: configuration.edge)
    }

    func setEnabled(_ enabled: Bool, for edge: DockEdge) {
        var config = configuration(for: edge)
        config.isEnabled = enabled
        update(config)
    }

    func add(_ dropletID: String, to edge: DockEdge) {
        var config = configuration(for: edge)
        guard !config.dropletIDs.contains(dropletID) else { return }
        config.dropletIDs.append(dropletID)
        update(config)
        Haptics.tap(.levelChange)
    }

    func remove(_ dropletID: String, from edge: DockEdge) {
        var config = configuration(for: edge)
        config.dropletIDs.removeAll { $0 == dropletID }
        update(config)
    }

    func move(_ dropletID: String, by offset: Int, on edge: DockEdge) {
        var config = configuration(for: edge)
        guard let from = config.dropletIDs.firstIndex(of: dropletID) else { return }
        let to = from + offset
        guard config.dropletIDs.indices.contains(to) else { return }
        config.dropletIDs.remove(at: from)
        config.dropletIDs.insert(dropletID, at: to)
        update(config)
    }

    // MARK: - Lifecycle

    func start() {
        for edge in DockEdge.allCases { rebuild(edge: edge) }
        guard pollTimer == nil else { return }
        // Auto-hiding docks peek out when the pointer reaches the screen edge.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateReveal() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for panel in panels.values { panel.orderOut(nil) }
        panels.removeAll()
    }

    private func rebuild(edge: DockEdge) {
        let config = configuration(for: edge)
        guard config.isEnabled, !config.droplets.isEmpty else {
            panels[edge]?.orderOut(nil)
            panels[edge] = nil
            revealed.remove(edge)
            return
        }

        let panel = panels[edge] ?? makePanel(for: edge)
        panels[edge] = panel
        layout(panel: panel, edge: edge, config: config)
        panel.orderFrontRegardless()
    }

    private func makePanel(for edge: DockEdge) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(rootView: SideDockView(edge: edge))
        return panel
    }

    /// Docks always use the roomy widget size: they have the whole edge to
    /// themselves and are never squeezed the way the notch shelf is.
    static let layout = ShelfLayout(width: 600)

    func size(for config: DockConfiguration) -> CGSize {
        let count = CGFloat(max(config.droplets.count, 1))
        let padding: CGFloat = 18
        let spacing = Self.layout.widgetSpacing
        let unit = Self.layout.widgetWidth
        let thickness = Self.layout.widgetHeight

        if config.edge.isVertical {
            return CGSize(
                width: unit + padding,
                height: count * thickness + (count - 1) * spacing + padding
            )
        }
        return CGSize(
            width: count * unit + (count - 1) * spacing + padding,
            height: thickness + padding
        )
    }

    private func layout(panel: NSPanel, edge: DockEdge, config: DockConfiguration) {
        guard let screen = NSScreen.preferred ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = size(for: config)
        let hidden = !revealed.contains(edge) && config.autoHide
        // When hidden, all but a thin grab strip is pushed off screen.
        let peek: CGFloat = 5

        var origin = CGPoint.zero
        switch edge {
        case .left:
            origin.x = hidden ? visible.minX - size.width + peek : visible.minX + 8
            origin.y = visible.minY + (visible.height - size.height) * config.position
        case .right:
            origin.x = hidden ? visible.maxX - peek : visible.maxX - size.width - 8
            origin.y = visible.minY + (visible.height - size.height) * config.position
        case .bottom:
            origin.x = visible.minX + (visible.width - size.width) * config.position
            origin.y = hidden ? visible.minY - size.height + peek : visible.minY + 8
        }

        let frame = CGRect(origin: origin, size: size)
        if panel.frame != frame {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    /// Reveals a dock while the pointer is at its edge or over the dock itself.
    private func updateReveal() {
        guard !panels.isEmpty else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let trigger: CGFloat = 3

        for edge in DockEdge.allCases {
            let config = configuration(for: edge)
            guard config.isEnabled, panels[edge] != nil else { continue }
            guard config.autoHide else {
                if !revealed.contains(edge) {
                    revealed.insert(edge)
                    rebuild(edge: edge)
                }
                continue
            }

            let atEdge: Bool
            switch edge {
            case .left: atEdge = mouse.x <= visible.minX + trigger
            case .right: atEdge = mouse.x >= visible.maxX - trigger
            case .bottom: atEdge = mouse.y <= visible.minY + trigger
            }
            let overDock = panels[edge]?.frame.insetBy(dx: -12, dy: -12).contains(mouse) ?? false
            let shouldReveal = atEdge || overDock

            if shouldReveal, !revealed.contains(edge) {
                revealed.insert(edge)
                rebuild(edge: edge)
                Haptics.tap(.alignment)
            } else if !shouldReveal, revealed.contains(edge) {
                revealed.remove(edge)
                rebuild(edge: edge)
            }
        }
    }

    private func persist() { Disk.save(configurations, to: Paths.dockStore) }
}
