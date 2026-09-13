import SwiftUI

/// Covers any locked pane with a Touch ID prompt.
struct LockOverlay: View {
    let scope: ProtectedScope
    var gate = BiometricGate.shared
    @State private var isWorking = false

    init(scope: ProtectedScope) { self.scope = scope }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Palette.accent.opacity(0.16))
                    .frame(width: 56, height: 56)
                Image(systemName: gate.activeMethodSymbol)
                    .font(.system(size: 25, weight: .regular))
                    .foregroundStyle(Theme.Palette.accent)
                    .symbolEffect(.pulse, isActive: isWorking)
            }

            VStack(spacing: 3) {
                Text(scope.title)
                    .font(Theme.Typo.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Text(unlockHint)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Button {
                authenticate()
            } label: {
                Label("Unlock", systemImage: gate.activeMethodSymbol)
                    .font(Theme.Typo.subtitle)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .controlBubble(radius: Radius.chip, tint: Theme.Palette.accent)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            if let error = gate.lastError {
                Text(error)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.danger)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { authenticate() }
    }

    private var unlockHint: String {
        switch gate.availability {
        case .biometrics(let type):
            switch type {
            case .faceID: "Look at your Mac to \(scope.reason)."
            case .opticID: "Use Optic ID to \(scope.reason)."
            default: "Touch the sensor to \(scope.reason)."
            }
        case .passwordOnly:
            "Enter your login password to \(scope.reason)."
        case .unavailable(let message):
            message
        }
    }

    private func authenticate() {
        guard !isWorking, !gate.isPrompting else { return }
        isWorking = true
        Task {
            await gate.unlock(scope)
            isWorking = false
        }
    }
}

/// Wraps any pane so it only renders once its scope is unlocked.
struct Guarded<Content: View>: View {
    let scope: ProtectedScope
    @ViewBuilder var content: () -> Content

    var gate = BiometricGate.shared

    init(_ scope: ProtectedScope, @ViewBuilder content: @escaping () -> Content) {
        self.scope = scope
        self.content = content
    }

    var body: some View {
        if gate.isUnlocked(scope) {
            content()
        } else {
            LockOverlay(scope: scope)
        }
    }
}
