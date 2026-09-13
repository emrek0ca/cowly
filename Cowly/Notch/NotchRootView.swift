import SwiftUI

/// The whole shelf: a notch-shaped surface pinned to the top of the screen,
/// with a detached tab switcher floating underneath when it is open.
///
/// This view owns the single Liquid Glass layer for the notch panel. Everything
/// rendered inside it is a plain translucent card — glass inside glass has
/// nothing left to refract.
struct NotchRootView: View {
    @Bindable var vm = NotchViewModel.shared
    var prefs = Preferences.shared
    var media = MediaController.shared

    @State private var sheenPhase: Double = 0

    private var layout: ShelfLayout { ShelfLayout(width: vm.geometry.openSize.width) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 13) {
                surface
                if vm.state == .open {
                    ShelfTabBar()
                        .transition(.scale(scale: 0.82, anchor: .top).combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.shelfLayout, layout)
        .animation(Motion.island, value: vm.state)
        .animation(Motion.activity, value: vm.activity)
        .animation(Motion.island, value: vm.geometry)
        .onChange(of: vm.state) { _, state in
            // Let the light sweep across the slab as it settles into its new
            // shape, then stop — nothing animates while the shelf is idle.
            guard state == .open else { return }
            sheenPhase = 0
            withAnimation(.easeOut(duration: 0.65)) { sheenPhase = 1 }
        }
    }

    private var size: CGSize { vm.currentSize }

    private var tint: Color? {
        guard prefs.tintFromArtwork, vm.state == .open else { return nil }
        return media.artworkTint?.opacity(0.42)
    }

    /// A bare closed shelf sits right on top of the hardware notch, so it has to
    /// be pure black there — glass would show up as a lighter rectangle.
    private var effectiveStyle: GlassStyle {
        if vm.state == .closed, vm.activity == nil, vm.geometry.hasHardwareNotch, !vm.showsIdleMusic {
            return .solid
        }
        return prefs.glassStyle
    }

    private var shape: NotchShape {
        NotchShape(topRadius: vm.cornerTop, bottomRadius: vm.cornerBottom)
    }

    /// A notch is a hole in the display: any translucency across it reads as a
    /// seam between the hardware and the app. So the shelf is opaque black for
    /// exactly the height of the cut-out and dissolves into glass on the way
    /// down. This happens in every appearance style — the reason is physical,
    /// not decorative.
    /// Only a real cut-out needs an opaque head. A floating island has no bezel
    /// to disappear into, so blacking out a third of it would just make it look
    /// switched off.
    private var blendTop: CGFloat { vm.geometry.hasHardwareNotch ? vm.topInset : 0 }
    private var blendFalloff: CGFloat {
        guard vm.state == .open else { return vm.geometry.hasHardwareNotch ? 14 : 10 }
        return 46
    }
    private var blendTotal: CGFloat { max(blendTop + blendFalloff, 1) }

    /// Hides anything glassy — rim, sheen — across the black head, fading it in
    /// exactly where the black gives way to glass.
    private var blendMask: some View {
        let height = max(vm.panelHeight, 1)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: min(1, blendTop / height)),
                .init(color: .black, location: min(1, blendTotal / height)),
                .init(color: .black, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var surface: some View {
        // Explicit layers. An earlier version attached a `glassEffectID` to a
        // view that carried no `glassEffect`; inside a `GlassEffectContainer`
        // that orphaned id made the native material render nothing *and*
        // swallow the content behind it, so the shelf came out blank. The
        // surface is a plain stack now, and `GlassSurface` draws a verifiable
        // material of its own on top of the system one.
        ZStack(alignment: .top) {
            Color.clear
                .glassSurface(shape, style: effectiveStyle, tint: tint)

            // Opaque black where the shelf meets the bezel, dissolving into the
            // glass below it.
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0.001, blendTop / blendTotal)),
                    .init(color: .black.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: blendTotal)
            .allowsHitTesting(false)

            GlassSheen(shape: shape, phase: sheenPhase).mask(blendMask)

            // No rim across the black head: an edge line up there outlines the
            // shelf as a separate part stuck under the notch.
            GlassRim(shape: shape, intensity: effectiveStyle == .solid ? 0.3 : 1)
                .mask(blendMask)

            if vm.isDropTargeted {
                shape
                    .stroke(Theme.Palette.accent, lineWidth: 2)
                    .shadow(color: Theme.Palette.accent.opacity(0.7), radius: 12)
                    .allowsHitTesting(false)
            }

            Group {
                switch vm.state {
                case .open:
                    OpenShelfView()
                        .islandTransition()
                case .closed, .peek:
                    ClosedShelfView()
                        .islandTransition()
                }
            }
        }
        .frame(width: size.width, height: vm.panelHeight, alignment: .top)
        .clipShape(shape)
        .shadow(color: .black.opacity(vm.state == .open ? 0.45 : 0), radius: 26, y: 12)
        .contentShape(shape)
        .onDrop(of: DropHandling.acceptedTypes, isTargeted: dropBinding) { providers in
            Task {
                let count = await DropHandling.receive(providers: providers)
                if count > 0 { vm.open(tab: .tray) }
            }
            return true
        }
        // Only the closed shelf is click-to-open; an open shelf must let every
        // click reach the control underneath it.
        .modifier(TapToOpen(isEnabled: vm.state != .open))
    }

    private var dropBinding: Binding<Bool> {
        Binding(
            get: { vm.isDropTargeted },
            set: { targeted in targeted ? vm.dragEntered() : vm.dragExited() }
        )
    }
}

/// The pill that floats under the open shelf. It is its own floating object, so
/// unlike the cards inside the shelf it does get a glass layer.
struct ShelfTabBar: View {
    @Bindable var vm = NotchViewModel.shared
    var prefs = Preferences.shared
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            pinButton
            Divider().frame(height: 16).overlay(Theme.Palette.separator)
            ForEach(ShelfTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(5)
        .glassSurface(
            RoundedRectangle(cornerRadius: Radius.chip + 7, style: .continuous),
            style: prefs.glassStyle,
            interactive: false
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip + 7, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
        .animation(Motion.snappy, value: vm.tab)
    }

    private var pinButton: some View {
        Button {
            vm.togglePin()
        } label: {
            Image(systemName: vm.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 30)
                .foregroundStyle(vm.isPinned ? Theme.Palette.muzzle : Theme.Palette.tertiaryText)
                .rotationEffect(.degrees(vm.isPinned ? 0 : -28))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(vm.isPinned ? "Unpin the shelf" : "Keep the shelf open")
    }

    private func tabButton(_ tab: ShelfTab) -> some View {
        Button {
            vm.select(tab)
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 38, height: 30)
                .foregroundStyle(vm.tab == tab ? Color.white : Theme.Palette.secondaryText)
                .background {
                    if vm.tab == tab {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.22))
                            .matchedGeometryEffect(id: "tabSelection", in: namespace)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}

private struct TapToOpen: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.onTapGesture { NotchViewModel.shared.open() }
        } else {
            content
        }
    }
}
