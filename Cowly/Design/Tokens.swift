import SwiftUI

/// One corner-radius scale for the whole app.
///
/// Cowly's shapes are "bubbles": the radius is always a large fraction of the
/// element's height, so nothing reads as a plain rectangle. Small controls go
/// fully capsule; cards and panels use continuous curvature.
enum Radius {
    static let chip: CGFloat = 11
    static let card: CGFloat = 17
    static let shelf: CGFloat = 34
    /// Concave flare where the open shelf meets the notch.
    static let shoulder: CGFloat = 15
    static let floating: CGFloat = 26

    /// A bubble radius proportional to the element's height, clamped so tall
    /// cards do not turn into stadiums.
    static func bubble(forHeight height: CGFloat, cap: CGFloat = 22) -> CGFloat {
        min(height * 0.34, cap)
    }
}

/// Glass is a *window into what is behind it*, so glass inside glass has
/// nothing new to refract and just muddies both layers. Exactly one glass layer
/// is allowed per floating window — the shelf, a dock, the basket, the tab bar
/// — and everything drawn inside one of those uses the flat helpers below.
extension View {
    /// A card inside a glass surface: translucent fill, hairline edge, no glass.
    func card(
        radius: CGFloat = Radius.card,
        fill: Double = 0.07,
        stroke: Double = 0.09,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape
                .fill(.white.opacity(fill))
                .overlay(shape.fill(tint?.opacity(0.16) ?? .clear))
        }
        .overlay(shape.strokeBorder(.white.opacity(stroke), lineWidth: 0.7))
        .clipShape(shape)
    }

    /// A small control inside a glass surface — always a bubble.
    func controlBubble(
        radius: CGFloat = Radius.chip,
        fill: Double = 0.10,
        tint: Color? = nil
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(tint?.opacity(0.28) ?? .white.opacity(fill))
        }
        .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 0.6))
        .clipShape(shape)
    }
}

/// Width-driven layout decisions for everything inside the shelf.
///
/// The shelf is sized from the hardware notch, which differs a lot between
/// Macs and can be narrowed further by the user, so no pane may assume it has
/// room. Each one reads the density and drops detail in a defined order.
struct ShelfLayout: Equatable, Sendable {
    enum Density: Sendable {
        case compact, regular, roomy
    }

    var width: CGFloat
    var density: Density

    init(width: CGFloat) {
        self.width = width
        density = switch width {
        case ..<400: .compact
        case ..<540: .regular
        default: .roomy
        }
    }

    static let fallback = ShelfLayout(width: Theme.Metrics.openWidth)

    // MARK: - Spacing

    /// Side inset. The shelf's bottom corners are a 34pt curve, so content that
    /// only respects a flat padding still collides with the curve — the bottom
    /// inset has to clear the radius, not just look even on a ruler.
    var contentPadding: CGFloat {
        switch density {
        case .compact: 24
        case .regular: 30
        case .roomy: 36
        }
    }

    var bottomPadding: CGFloat { max(contentPadding, Radius.shelf * 0.8) }

    /// Air between the notch cut-out (or the top edge) and the first row.
    var topPadding: CGFloat {
        switch density {
        case .compact: 10
        case .regular: 14
        case .roomy: 18
        }
    }

    var blockSpacing: CGFloat {
        switch density {
        case .compact: 14
        case .regular: 17
        case .roomy: 20
        }
    }

    // MARK: - Media

    var artworkSize: CGFloat {
        switch density {
        case .compact: 42
        case .regular: 52
        case .roomy: 62
        }
    }

    var showsAlbum: Bool { density == .roomy }
    /// The "-2:41" counter is the first thing to go: elapsed time alone still
    /// tells you where you are in the track.
    var showsRemaining: Bool { density != .compact }
    var elapsedLabelWidth: CGFloat { density == .compact ? 34 : 38 }
    var showsSourceBadge: Bool { density != .compact }
    var showsOutputName: Bool { density != .compact }
    var showsVisualiser: Bool { density != .compact }

    var transportSize: CGFloat {
        switch density {
        case .compact: 17
        case .regular: 19
        case .roomy: 21
        }
    }

    var transportSpacing: CGFloat {
        switch density {
        case .compact: 16
        case .regular: 19
        case .roomy: 23
        }
    }

    // MARK: - Widgets

    var widgetWidth: CGFloat {
        switch density {
        case .compact: 126
        case .regular: 140
        case .roomy: 152
        }
    }

    var widgetHeight: CGFloat { 68 }
    /// Buttons and secondary rows inside a widget need room that a compact
    /// rail does not have.
    var widgetShowsAccessory: Bool { density != .compact }
    var widgetSpacing: CGFloat { 8 }
    var widgetStep: CGFloat { widgetWidth + widgetSpacing }

    // MARK: - Panes

    var gridColumns: Int {
        switch density {
        case .compact: 4
        case .regular: 5
        case .roomy: 6
        }
    }

    var trayCardWidth: CGFloat {
        switch density {
        case .compact: 62
        case .regular: 70
        case .roomy: 76
        }
    }

    // MARK: - Derived heights

    /// A fixed shelf height either squeezes the rows or leaves a hole under
    /// them, so the panel is measured from the blocks it actually contains.
    var mediaHeight: CGFloat {
        artworkSize + blockSpacing + scrubberHeight + blockSpacing + transportHeight
    }

    var scrubberHeight: CGFloat { 16 }
    var transportHeight: CGFloat { transportSize + 12 }
    var paneHeaderHeight: CGFloat { 24 }
    var tileHeight: CGFloat { 66 }
    /// The droplet grid scrolls; two rows is what the shelf shows at once.
    var gridVisibleRows: Int { 2 }

    func contentHeight(for tab: ShelfTab, topInset: CGFloat, hasShelfWidgets: Bool) -> CGFloat {
        let bottom = bottomPadding
        let body: CGFloat = switch tab {
        case .home:
            mediaHeight + (hasShelfWidgets ? blockSpacing + widgetHeight : 0)
        case .tray:
            paneHeaderHeight + blockSpacing + widgetHeight
        case .droplets:
            paneHeaderHeight + blockSpacing
                + CGFloat(gridVisibleRows) * tileHeight
                + CGFloat(gridVisibleRows - 1) * 7
        }
        return topInset + topPadding + body + bottom
    }
}

private struct ShelfLayoutKey: EnvironmentKey {
    static let defaultValue = ShelfLayout.fallback
}

extension EnvironmentValues {
    var shelfLayout: ShelfLayout {
        get { self[ShelfLayoutKey.self] }
        set { self[ShelfLayoutKey.self] = newValue }
    }
}


/// Outlines each layout block during development renders.
private struct LayoutDebugKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var layoutDebug: Bool {
        get { self[LayoutDebugKey.self] }
        set { self[LayoutDebugKey.self] = newValue }
    }
}

extension View {
    func debugBlock(_ color: Color) -> some View {
        modifier(DebugBlock(color: color))
    }
}

private struct DebugBlock: ViewModifier {
    @Environment(\.layoutDebug) private var isEnabled
    let color: Color

    func body(content: Content) -> some View {
        if isEnabled {
            content.border(color.opacity(0.9), width: 1)
        } else {
            content
        }
    }
}

/// A slider built from a drag gesture rather than `Slider`.
///
/// AppKit-backed controls have repeatedly misbehaved inside Cowly's borderless,
/// non-activating panel — `Menu` opened behind the shelf, a segmented `Picker`
/// refused to draw. A slider is the same class of risk and it is simple enough
/// to own outright, so nothing in the shelf depends on that behaviour.
struct ShelfSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var tint: Color = Theme.Palette.accent
    var height: CGFloat = 5
    var onCommit: ((Double) -> Void)?

    @State private var isActive = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let filled = width * min(max(fraction, 0), 1)
            let thickness = isActive ? height + 3 : height

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule().fill(tint).frame(width: filled)
                if isActive {
                    Circle()
                        .fill(.white)
                        .frame(width: thickness + 5, height: thickness + 5)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .offset(x: filled - (thickness + 5) / 2)
                }
            }
            .frame(height: thickness)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(Motion.snappy, value: isActive)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isActive = true
                        update(to: drag.location.x / width)
                    }
                    .onEnded { drag in
                        isActive = false
                        let next = update(to: drag.location.x / width)
                        onCommit?(next)
                    }
            )
            .onHover { hovering in
                if !hovering, !isActive { isActive = false }
            }
        }
        .frame(height: height + 8)
    }

    @discardableResult
    private func update(to fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        let next = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        value = next
        return next
    }
}
