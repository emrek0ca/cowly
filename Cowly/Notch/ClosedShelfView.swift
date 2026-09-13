import SwiftUI

/// What the shelf shows while it is closed: nothing at all over the bare notch,
/// a live-activity pill, or a slim now-playing peek.
struct ClosedShelfView: View {
    var vm = NotchViewModel.shared
    var media = MediaController.shared
    var timers = TimerEngine.shared

    var body: some View {
        ZStack {
            if let activity = vm.activity {
                ActivityPill(activity: activity, notchWidth: vm.geometry.closedSize.width)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if vm.showsIdleMusic {
                musicPeek
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 15)
        .padding(.vertical, 6)
    }

    private var musicPeek: some View {
        HStack(spacing: 0) {
            ArtworkView(image: media.now.artwork, size: 20, corner: 6)
            Spacer(minLength: vm.geometry.closedSize.width - 8)
            AudioBars(isActive: media.now.isPlaying, tint: media.artworkTint ?? .white)
                .frame(width: 18, height: 14)
        }
    }
}

/// The expanded pill: glyph, title, optional progress, trailing value.
struct ActivityPill: View {
    let activity: LiveActivity
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: activity.leadingSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activity.leadingTint)
                    .frame(width: 18)
                    .transition(.scale.combined(with: .opacity))
                    .id(activity.leadingSymbol)
                if activity.style == .expanded {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activity.title)
                            .font(Theme.Typo.subtitle)
                            .foregroundStyle(Theme.Palette.primaryText)
                            .lineLimit(1)
                        if let subtitle = activity.subtitle {
                            Text(subtitle)
                                .font(Theme.Typo.caption)
                                .foregroundStyle(Theme.Palette.tertiaryText)
                                .lineLimit(1)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }

            // The physical notch sits between the two halves of the pill, so
            // the gap has to be at least as wide as the cut-out.
            Spacer(minLength: notchWidth - 22)

            HStack(spacing: 9) {
                if let progress = activity.progress {
                    ProgressRing(progress: progress, tint: activity.leadingTint)
                        .frame(width: 16, height: 16)
                }
                if let trailing = activity.trailingText {
                    Text(trailing)
                        .font(Theme.Typo.mono)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Motion.content, value: trailing)
                }
            }
        }
    }
}

/// Thin circular progress used by activities and the Pomodoro widget.
struct ProgressRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.content, value: progress)
        }
    }
}

/// Four bars that bounce while something is playing.
struct AudioBars: View {
    var isActive: Bool
    var tint: Color = .white

    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isActive)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let offset = Double(index) * 0.7
                    let height = isActive
                        ? 0.35 + 0.65 * abs(sin(t * 3.2 + offset))
                        : 0.25
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.9))
                        .frame(height: max(2, 14 * height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// Album art with a graceful placeholder.
struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var corner: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.6)
        )
    }
}
