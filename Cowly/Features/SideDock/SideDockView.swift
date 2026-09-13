import SwiftUI

/// The dock itself: the same droplet widgets as the shelf, stacked along an
/// edge, with a grab strip that hints where it is hiding.
struct SideDockView: View {
    let edge: DockEdge
    var controller = SideDockController.shared
    var prefs = Preferences.shared

    private var config: DockConfiguration { controller.configuration(for: edge) }
    private var isRevealed: Bool { controller.revealed.contains(edge) || !config.autoHide }

    var body: some View {
        ZStack(alignment: alignment) {
            content
                .padding(9)
                .environment(\.shelfLayout, SideDockController.layout)
                .glassSurface(
                    RoundedRectangle(cornerRadius: Radius.floating, style: .continuous),
                    tint: nil,
                    interactive: false
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.floating, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.7)
                )
                .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
                .opacity(isRevealed ? 1 : 0.85)

            if !isRevealed {
                grabStrip
            }
        }
        .animation(Motion.snappy, value: isRevealed)
        .contextMenu {
            Button("Dock settings…") { SettingsWindowController.shared.show() }
            Button(config.autoHide ? "Keep visible" : "Hide until I reach the edge") {
                var next = config
                next.autoHide.toggle()
                controller.update(next)
            }
            Divider()
            Button("Turn off this dock") { controller.setEnabled(false, for: edge) }
        }
    }

    private var alignment: Alignment {
        switch edge {
        case .left: .trailing
        case .right: .leading
        case .bottom: .top
        }
    }

    @ViewBuilder
    private var content: some View {
        if edge.isVertical {
            VStack(spacing: SideDockController.layout.widgetSpacing) { widgets }
        } else {
            HStack(spacing: SideDockController.layout.widgetSpacing) { widgets }
        }
    }

    private var widgets: some View {
        ForEach(config.droplets) { droplet in
            DropletWidget(droplet: droplet)
                .contextMenu {
                    Button("Move earlier") { controller.move(droplet.id, by: -1, on: edge) }
                    Button("Move later") { controller.move(droplet.id, by: 1, on: edge) }
                    Divider()
                    Button("Remove from dock", role: .destructive) {
                        controller.remove(droplet.id, from: edge)
                    }
                }
        }
    }

    /// The sliver that stays on screen so an auto-hidden dock is discoverable.
    private var grabStrip: some View {
        Capsule()
            .fill(Theme.Palette.muzzle.opacity(0.75))
            .frame(
                width: edge.isVertical ? 3 : 34,
                height: edge.isVertical ? 34 : 3
            )
            .padding(edge.isVertical ? .horizontal : .vertical, 1)
    }
}
