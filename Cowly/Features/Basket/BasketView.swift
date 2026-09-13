import SwiftUI

/// The floating catcher that appears when you jiggle a drag.
struct BasketView: View {
    var controller = BasketController.shared
    var store = TrayStore.shared

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Image(systemName: "basket.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(controller.isTargeted ? Theme.Palette.accent : .white)
                    .scaleEffect(controller.isTargeted ? 1.12 : 1)
                if store.items.count > 0 {
                    Text("\(store.items.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Palette.accent))
                        .foregroundStyle(.white)
                        .offset(x: 20, y: -16)
                }
            }
            Text(controller.isTargeted ? "Release to keep" : "Drop here")
                .font(Theme.Typo.subtitle)
                .foregroundStyle(controller.isTargeted ? Theme.Palette.primaryText : Theme.Palette.secondaryText)
        }
        .frame(width: 150, height: 150)
        .glassSurface(
            RoundedRectangle(cornerRadius: 32, style: .continuous),
            style: Preferences.shared.glassStyle,
            tint: controller.isTargeted ? Theme.Palette.accent.opacity(0.5) : nil,
            interactive: false
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    controller.isTargeted ? Theme.Palette.accent : Color.white.opacity(0.16),
                    style: StrokeStyle(lineWidth: controller.isTargeted ? 2 : 1, dash: controller.isTargeted ? [] : [6, 4])
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
        .padding(9)
        .animation(Motion.basket, value: controller.isTargeted)
        .onDrop(of: DropHandling.acceptedTypes, isTargeted: targetBinding) { providers in
            controller.accept(providers: providers)
            return true
        }
    }

    private var targetBinding: Binding<Bool> {
        Binding(
            get: { controller.isTargeted },
            set: { controller.setTargeted($0) }
        )
    }
}
