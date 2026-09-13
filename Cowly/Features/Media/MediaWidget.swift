import AppKit
import SwiftUI

/// The player: artwork, metadata, a real scrubber, transport controls and the
/// system output picker.
///
/// The shelf is sized from the hardware notch and the user can narrow it
/// further, so this drops detail in a fixed order as space runs out: album
/// line first, then the source badge and the visualiser, then the output
/// device name.
struct MediaWidget: View {
    @Environment(\.shelfLayout) private var layout
    var media = MediaController.shared
    var audio = AudioOutput.shared

    private var snapshot: MediaSnapshot { media.now }

    var body: some View {
        VStack(spacing: layout.blockSpacing) {
            header
            scrubber
            controls
        }
        // Natural height, never absorbing the shelf's spare space, and never
        // letting a long title or device name push a row past the edge.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var header: some View {
        HStack(spacing: layout.density == .compact ? 9 : 12) {
            ArtworkView(
                image: snapshot.artwork,
                size: layout.artworkSize,
                corner: Radius.bubble(forHeight: layout.artworkSize, cap: 16)
            )
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(Theme.Typo.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                Text(snapshot.artist)
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .lineLimit(1)
                if layout.showsAlbum, !snapshot.album.isEmpty {
                    Text(snapshot.album)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.content, value: snapshot.title)

            if layout.showsVisualiser {
                AudioBars(isActive: snapshot.isPlaying, tint: media.artworkTint ?? .white)
                    .frame(width: 20, height: 17)
                    .opacity(snapshot.isIdle ? 0.25 : 1)
            }
        }
    }

    private var scrubber: some View {
        HStack(spacing: 9) {
            Text(media.displayedElapsed.clockLabel)
                .font(Theme.Typo.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(width: layout.elapsedLabelWidth, alignment: .leading)

            ScrubBar(
                progress: media.displayedProgress,
                isEnabled: snapshot.duration > 0,
                tint: media.artworkTint ?? .white,
                onChanged: { media.beginScrub($0) },
                onEnded: { media.commitScrub($0) }
            )
            .frame(height: layout.scrubberHeight)

            if layout.showsRemaining {
                Text(snapshot.duration > 0 ? "-\(snapshot.remaining.clockLabel)" : "--:--")
                    .font(Theme.Typo.caption)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            outputPicker
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: layout.transportSpacing) {
                TransportButton(symbol: "backward.fill", size: layout.transportSize - 4) { media.previous() }
                TransportButton(
                    symbol: snapshot.isPlaying ? "pause.fill" : "play.fill",
                    size: layout.transportSize
                ) { media.playPause() }
                TransportButton(symbol: "forward.fill", size: layout.transportSize - 4) { media.next() }
            }
            .disabled(snapshot.isIdle)
            .opacity(snapshot.isIdle ? 0.4 : 1)

            if layout.showsSourceBadge {
                sourceBadge
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
    }

    private var outputPicker: some View {
        ShelfMenuButton {
            var items = audio.devices.map { device in
                ShelfMenu.Item(
                    title: device.name,
                    symbol: device.symbol,
                    isOn: device.isDefault,
                    action: { audio.select(device) }
                )
            }
            items.append(.separator)
            items.append(ShelfMenu.Item(title: "Sound Settings…", symbol: "gearshape") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            })
            return items
        } label: {
            HStack(spacing: 5) {
                Image(systemName: audio.devices.first(where: \.isDefault)?.symbol ?? "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                if layout.showsOutputName {
                    Text(audio.currentName)
                        .font(Theme.Typo.caption)
                        .lineLimit(1)
                        .frame(maxWidth: layout.density == .roomy ? 96 : 66, alignment: .leading)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.55)
            }
            .foregroundStyle(Theme.Palette.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .controlBubble(radius: Radius.chip)
            .contentShape(Rectangle())
        }
        .fixedSize()
        .onAppear { audio.refresh() }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if !snapshot.isIdle {
            HStack(spacing: 5) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 13, height: 13)
                if layout.density == .roomy {
                    Text(snapshot.appName)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .controlBubble(radius: 9, fill: 0.07)
        }
    }

    private var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: snapshot.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        }
        return NSImage(systemSymbolName: "waveform", accessibilityDescription: nil) ?? NSImage()
    }
}

struct TransportButton: View {
    let symbol: String
    var size: CGFloat
    let action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button {
            isPressed = true
            action()
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                isPressed = false
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.Palette.primaryText)
                .frame(width: size + 16, height: size + 12)
                .background {
                    Circle()
                        .fill(.white.opacity(isHovering ? 0.12 : 0))
                        .frame(width: size + 16, height: size + 16)
                }
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.86 : (isHovering ? 1.1 : 1))
                .animation(Motion.snappy, value: isHovering)
                .animation(.spring(response: 0.2, dampingFraction: 0.55), value: isPressed)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// Draggable progress bar that grows under the pointer.
struct ScrubBar: View {
    var progress: Double
    var isEnabled: Bool
    var tint: Color
    var onChanged: (Double) -> Void
    var onEnded: (Double) -> Void

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let active = isHovering || isDragging
            let height: CGFloat = active ? 8 : 5
            let filled = width * min(max(progress, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(tint.opacity(0.95))
                    .frame(width: filled)
                if active {
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.45), radius: 3)
                        .offset(x: filled - 6)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: active)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        isDragging = true
                        onChanged(min(max(value.location.x / width, 0), 1))
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        isDragging = false
                        onEnded(min(max(value.location.x / width, 0), 1))
                    }
            )
            .onHover { isHovering = $0 && isEnabled }
        }
    }
}
