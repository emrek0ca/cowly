import AppKit
import SwiftUI

/// Content of the expanded shelf, one pane per tab.
struct OpenShelfView: View {
    @Environment(\.shelfLayout) private var layout
    var vm = NotchViewModel.shared

    /// The physical notch covers the top-centre of the panel, so nothing may be
    /// laid out underneath it.
    private var topInset: CGFloat { vm.topInset }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset + layout.topPadding)
            Group {
                switch vm.tab {
                case .home: HomePane()
                case .tray: TrayPane()
                case .droplets: DropletsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(y: 8)),
                removal: .opacity
            ))
            .id(vm.tab)
        }
        .padding(.horizontal, layout.contentPadding)
        .padding(.bottom, layout.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Home: the player plus whatever droplet widgets are switched on.
struct HomePane: View {
    @Environment(\.shelfLayout) private var layout
    var prefs = Preferences.shared

    var body: some View {
        VStack(spacing: layout.blockSpacing) {
            MediaWidget().debugBlock(.cyan)
            if !prefs.orderedShelfDroplets.isEmpty {
                DropletShelfRow().debugBlock(.orange)
            }
        }
        .debugBlock(.green)
    }
}

/// The Home rail: every enabled widget, scrollable, and rearrangeable by
/// picking a card up and sliding it past its neighbours.
struct DropletShelfRow: View {
    @Environment(\.shelfLayout) private var layout
    var prefs = Preferences.shared

    @State private var draggingID: String?
    @State private var dragOffset: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var isHovering = false

    private var droplets: [Droplet] { prefs.orderedShelfDroplets }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = CGFloat(droplets.count) * layout.widgetStep - layout.widgetSpacing
            let maxScroll = max(0, contentWidth - geo.size.width)

            // The stack keeps its natural width — constraining it to the
            // viewport would squeeze the fixed-size cards until they overlap.
            ZStack(alignment: .leading) {
                Color.clear
                HStack(spacing: layout.widgetSpacing) {
                    ForEach(droplets) { droplet in
                        DropletWidget(droplet: droplet, isDragging: draggingID == droplet.id)
                            .offset(x: draggingID == droplet.id ? dragOffset : 0)
                            .zIndex(draggingID == droplet.id ? 1 : 0)
                            .gesture(reorderGesture(for: droplet))
                    }
                }
                .fixedSize()
                .offset(x: -scrollOffset)
            }
            .frame(width: geo.size.width, height: layout.widgetHeight, alignment: .leading)
            .animation(Motion.snappy, value: scrollOffset)
            .animation(Motion.snappy, value: prefs.shelfOrder)
            .mask(edgeFade(leading: scrollOffset > 1, trailing: scrollOffset < maxScroll - 1))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .overlay(alignment: .leading) { arrow(.backward, enabled: scrollOffset > 1, maxScroll: maxScroll) }
            .overlay(alignment: .trailing) { arrow(.forward, enabled: scrollOffset < maxScroll - 1, maxScroll: maxScroll) }
            .onScrollWheel(isEnabled: isHovering) { delta in
                scrollOffset = min(max(0, scrollOffset + delta), maxScroll)
            }
            .onChange(of: maxScroll) { _, limit in
                scrollOffset = min(scrollOffset, limit)
            }
        }
        .frame(height: layout.widgetHeight)
    }

    /// Soft edges so a scrolled-off card dissolves instead of being guillotined
    /// by the shelf's corner.
    private func edgeFade(leading: Bool, trailing: Bool) -> some View {
        let fade: CGFloat = 26
        return HStack(spacing: 0) {
            LinearGradient(
                colors: leading ? [.clear, .black] : [.black, .black],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: fade)
            Rectangle().fill(.black)
            LinearGradient(
                colors: trailing ? [.black, .clear] : [.black, .black],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: fade)
        }
    }

    private enum Direction { case backward, forward }

    @ViewBuilder
    private func arrow(_ direction: Direction, enabled: Bool, maxScroll: CGFloat) -> some View {
        if isHovering, enabled {
            Button {
                scrollOffset = direction == .forward
                    ? min(scrollOffset + layout.widgetStep, maxScroll)
                    : max(scrollOffset - layout.widgetStep, 0)
            } label: {
                Image(systemName: direction == .forward ? "chevron.right" : "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .fill(.black.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.6)
                    )
            }
            .buttonStyle(.plain)
            .transition(.opacity.combined(with: .scale(scale: 0.85)))
        }
    }

    /// Picking a card up shifts it under the pointer; whenever it passes a
    /// neighbour's midpoint the two swap, so the rail reorders live.
    private func reorderGesture(for droplet: Droplet) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if draggingID == nil {
                    draggingID = droplet.id
                    NotchViewModel.shared.beginInteraction()
                    Haptics.tap(.generic)
                }
                guard draggingID == droplet.id else { return }
                dragOffset = value.translation.width
                let shift = Int((dragOffset / layout.widgetStep).rounded())
                guard shift != 0 else { return }
                if prefs.moveDroplet(droplet.id, by: shift) {
                    dragOffset -= CGFloat(shift) * layout.widgetStep
                }
            }
            .onEnded { _ in
                guard draggingID == droplet.id else { return }
                withAnimation(Motion.snappy) { dragOffset = 0 }
                draggingID = nil
                NotchViewModel.shared.endInteraction()
                Haptics.tap(.levelChange)
            }
    }
}

/// Scroll-wheel handling for a plain SwiftUI view.
///
/// A backing NSView cannot do this: to let clicks through it must return nil
/// from `hitTest`, and a view that fails hit-testing never receives
/// `scrollWheel`. A local event monitor, live only while the row is hovered,
/// gets both right.
private struct ScrollWheelMonitor: ViewModifier {
    var isEnabled: Bool
    var onScroll: (CGFloat) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: isEnabled) { _, enabled in
                enabled ? install() : remove()
            }
            .onDisappear(perform: remove)
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { event in
            // Horizontal gestures win; a vertical flick still scrolls the row,
            // which is what people expect from a single line of cards.
            let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
                ? -event.scrollingDeltaX
                : -event.scrollingDeltaY
            guard delta != 0 else { return event }
            onScroll(delta * (event.hasPreciseScrollingDeltas ? 1.0 : 8.0))
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

extension View {
    func onScrollWheel(isEnabled: Bool, _ handler: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollWheelMonitor(isEnabled: isEnabled, onScroll: handler))
    }
}
