import AppKit
import Observation
import SwiftUI

/// Cowly's own full-screen cover.
///
/// Worth being precise about what this is: macOS does not let a third-party app
/// take part in the real login window. This is a privacy curtain you pull when
/// you step away — it hides your desktop on every display and lifts on Touch ID.
/// It is not a security boundary, and it never locks you out.
@MainActor
@Observable
final class LockScreenController {
    static let shared = LockScreenController()

    private(set) var isPresented = false
    private(set) var failureCount = 0
    private var windows: [NSWindow] = []

    private init() {}

    func toggle() { isPresented ? dismiss() : present() }

    func present() {
        guard !isPresented else { return }
        isPresented = true
        failureCount = 0
        BiometricGate.shared.lockAll()
        NotchViewModel.shared.close(force: true)

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: LockScreenView(isPrimary: screen == NSScreen.main))
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                window.animator().alphaValue = 1
            }
            windows.append(window)
        }
    }

    func dismiss() {
        isPresented = false
        let closing = windows
        windows.removeAll()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            for window in closing { window.animator().alphaValue = 0 }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(240))
            for window in closing { window.orderOut(nil) }
        }
    }

    /// Touch ID / password — always available, so the curtain can never trap you.
    func unlockWithSystem() {
        Task {
            if await BiometricGate.shared.authenticate(.settings) {
                dismiss()
            }
        }
    }
}

struct LockScreenView: View {
    var isPrimary: Bool
    var controller = LockScreenController.shared
    var media = MediaController.shared

    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            background
            if isPrimary {
                VStack(spacing: 0) {
                    Spacer()
                    clockBlock
                    Spacer()
                    if !media.now.isIdle { mediaBlock }
                    unlockBlock
                        .padding(.top, 26)
                    Spacer(minLength: 40)
                }
                .padding(40)
            } else {
                CowFace(size: 120, tint: .white.opacity(0.28))
            }
        }
        .onReceive(clock) { now = $0 }
        .onExitCommand { controller.unlockWithSystem() }
    }

    private var background: some View {
        ZStack {
            if let artwork = media.now.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 90, opaque: true)
                    .overlay(Color.black.opacity(0.55))
            } else {
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.18, blue: 0.16), Color(red: 0.04, green: 0.06, blue: 0.08)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            CowSpots(opacity: 0.035)
        }
        .ignoresSafeArea()
    }

    private var clockBlock: some View {
        VStack(spacing: 4) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 92, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var mediaBlock: some View {
        HStack(spacing: 14) {
            ArtworkView(image: media.now.artwork, size: 54, corner: 13)
            VStack(alignment: .leading, spacing: 2) {
                Text(media.now.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(media.now.artist)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)
            HStack(spacing: 20) {
                TransportButton(symbol: "backward.fill", size: 15) { media.previous() }
                TransportButton(symbol: media.now.isPlaying ? "pause.fill" : "play.fill", size: 19) { media.playPause() }
                TransportButton(symbol: "forward.fill", size: 15) { media.next() }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: media.artworkTint?.opacity(0.4))
        .frame(maxWidth: 520)
    }

    private var unlockBlock: some View {
        VStack(spacing: 12) {
            Button {
                controller.unlockWithSystem()
            } label: {
                Label("Unlock with Touch ID", systemImage: BiometricGate.shared.activeMethodSymbol)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .controlBubble(radius: Radius.floating, fill: 0.14)
            }
            .buttonStyle(.plain)

            Text("This curtain hides your desktop. Your Mac itself is still unlocked — use ⌃⌘Q for the real lock screen.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.top, 4)
        }
    }

}
