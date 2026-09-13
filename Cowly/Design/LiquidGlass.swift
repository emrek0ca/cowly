import AppKit
import SwiftUI

/// How the shelf paints itself. Liquid Glass where the OS has it, a hand-tuned
/// material stack everywhere else, and a pure-black option for people who want
/// the panel to disappear into the hardware bezel.
enum GlassStyle: String, CaseIterable, Codable, Sendable {
    case liquid
    case tinted
    case solid

    var label: String {
        switch self {
        case .liquid: "Liquid Glass"
        case .tinted: "Tinted Glass"
        case .solid: "Solid Black"
        }
    }

    /// The style the user picked, for views that do not override it.
    @MainActor
    static var preferred: GlassStyle { Preferences.shared.glassStyle }
}

/// Paints a floating surface.
///
/// The native `glassEffect` turned out to render nothing inside Cowly's
/// borderless, non-activating panel — and worse, it swallowed the content it
/// was applied to, so the shelf came out completely blank. A layer dump of the
/// real view tree showed no material layer and no fill beneath it.
///
/// So the surface people actually see is built from a blur material and a
/// tuned dark fill, which is verifiable and works in every window kind. The
/// system material is still added *behind* that, never around it, so if it
/// contributes refraction it is a bonus and it can never hide anything.
struct GlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var style: GlassStyle
    var tint: Color?
    var interactive: Bool

    init(shape: S, style: GlassStyle = .liquid, tint: Color? = nil, interactive: Bool = false) {
        self.shape = shape
        self.style = style
        self.tint = tint
        self.interactive = interactive
    }

    private var dimming: Double { NotchViewModel.shared.glassDimming }

    func body(content: Content) -> some View {
        content.background(surface)
    }

    @ViewBuilder
    private var surface: some View {
        switch style {
        case .solid:
            shape.fill(.black)
        case .tinted:
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(.black.opacity(max(dimming, 0.45)))
                if let tint { shape.fill(tint.opacity(0.22)) }
            }
        case .liquid:
            ZStack {
                nativeSlab
                // Frosted body. `.regular` keeps more of what is behind it than
                // `.ultraThin`, which is what makes it read as thick glass.
                shape.fill(.regularMaterial)
                shape.fill(.black.opacity(dimming))
                if let tint { shape.fill(tint.opacity(0.26)) }
                // A vertical brightness ramp: glass is lit from above.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(0.10), .clear, .black.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }
        }
    }

    /// Best-effort native material, layered behind everything so it can only
    /// ever add to the look.
    @ViewBuilder
    private var nativeSlab: some View {
        if #available(macOS 26.0, *) {
            shape
                .fill(.black.opacity(0.01))
                .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: shape)
        }
    }
}

extension View {
    /// Paints a floating surface behind this view.
    ///
    /// `style: nil` follows whatever the user picked in Appearance. Leave
    /// `interactive` off for any surface that *contains* controls: interactive
    /// glass takes the press itself, so the buttons inside it never fire.
    func glassSurface<S: Shape>(
        _ shape: S,
        style: GlassStyle? = nil,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            GlassSurface(
                shape: shape,
                style: style ?? GlassStyle.preferred,
                tint: tint,
                interactive: interactive
            )
        )
    }
}

/// The rim of a glass surface.
///
/// Real Liquid Glass reads as a thick, curved slab: the edge bends the light
/// behind it, so the top catches a bright specular line, the inside of that
/// edge shows the slab's thickness as a darker band, and the bottom lip picks
/// up light bouncing back up. One flat stroke cannot say any of that, so this
/// layers the three separately.
struct GlassRim<S: Shape>: View {
    var shape: S
    var intensity: Double = 1

    var body: some View {
        ZStack {
            // Specular edge: brightest at the top, where the light sits.
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.62 * intensity), location: 0),
                        .init(color: .white.opacity(0.16 * intensity), location: 0.28),
                        .init(color: .white.opacity(0.02 * intensity), location: 0.6),
                        .init(color: .white.opacity(0.10 * intensity), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 1
            )
            .blendMode(.plusLighter)

            // Thickness: a soft dark band just inside the top edge.
            shape.stroke(
                LinearGradient(
                    colors: [.black.opacity(0.34 * intensity), .clear],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 2.5
            )
            .blur(radius: 2)
            .offset(y: 1.5)
            .mask(shape.fill(.black))

            // Bottom lip catching bounced light.
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.55),
                        .init(color: .white.opacity(0.28 * intensity), location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                ),
                lineWidth: 0.8
            )
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

/// A sheen that sweeps across the surface once, the way Liquid Glass catches
/// the light as it settles into a new shape. Driven by a phase rather than a
/// repeating timer so nothing animates while the shelf is just sitting there.
struct GlassSheen<S: Shape>: View {
    var shape: S
    var phase: Double

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, phase - 0.26)),
                        .init(color: .white.opacity(0.16), location: phase),
                        .init(color: .clear, location: min(1, phase + 0.26))
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
            .opacity(phase <= 0 || phase >= 1 ? 0 : 1)
    }
}


/// SwiftUI text fields inside a non-activating panel only receive keystrokes
/// once the app is frontmost, so claim focus the moment one is clicked.
struct FocusableField: ViewModifier {
    func body(content: Content) -> some View {
        content.onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            NotchWindowController.shared.panel?.makeKeyAndOrderFront(nil)
            NotchViewModel.shared.isPinned = true
        }
    }
}

extension View {
    func focusableInShelf() -> some View { modifier(FocusableField()) }
}
