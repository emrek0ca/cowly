import SwiftUI

/// Compact rail card: one bar per agent that reports a quota.
struct AIUsageWidget: View {
    var monitor = AIUsageMonitor.shared

    private var visible: [AIUsage] {
        let installed = monitor.tools.filter(\.isInstalled)
        return installed.isEmpty ? Array(monitor.tools.prefix(2)) : Array(installed.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Palette.accent)
                Text("AI LIMITS")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .tracking(0.6)
            }
            ForEach(visible) { tool in
                HStack(spacing: 6) {
                    Text(tool.name.prefix(1))
                        .font(.system(size: 8, weight: .black, design: .rounded))
                        .foregroundStyle(tool.tint)
                        .frame(width: 9)
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(barTint(for: tool))
                                    .frame(width: geo.size.width * (tool.barFraction ?? 0))
                                    .animation(Motion.activity, value: tool.barFraction)
                            }
                        }
                    Text(tool.headline)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .frame(width: 46, alignment: .trailing)
                        .lineLimit(1)
                }
            }
        }
        .onAppear { AIUsageMonitor.shared.start() }
    }

    private func barTint(for tool: AIUsage) -> Color {
        guard let fraction = tool.barFraction else { return tool.tint.opacity(0.5) }
        switch fraction {
        case ..<0.6: return Theme.Palette.pasture
        case ..<0.85: return Theme.Palette.warning
        default: return Theme.Palette.danger
        }
    }
}

/// Full pane: every agent, both windows, and where the number comes from.
struct AIUsagePane: View {
    var monitor = AIUsageMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(monitor.lastRefresh.map { "Updated \($0.relativeShort)" } ?? "Reading logs…")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Spacer()
                Button("Refresh") { monitor.refresh() }
                    .buttonStyle(MiniPillStyle())
                    .disabled(monitor.isRefreshing)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(monitor.tools) { tool in
                        AIUsageRow(tool: tool)
                    }
                }
            }
        }
        .onAppear { AIUsageMonitor.shared.start() }
    }
}

struct AIUsageRow: View {
    let tool: AIUsage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tool.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tool.isInstalled ? tool.tint : Theme.Palette.tertiaryText)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tool.name)
                        .font(Theme.Typo.subtitle)
                        .foregroundStyle(tool.isInstalled ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                    Spacer()
                    Text(tool.headline)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.secondaryText)
                }

                if let primary = tool.primary {
                    windowRow(primary)
                }
                if let secondary = tool.secondary {
                    windowRow(secondary)
                }
                if let note = tool.note {
                    Text(note)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(tool.isInstalled ? 0.06 : 0.03))
        )
    }

    @ViewBuilder
    private func windowRow(_ window: AIUsage.Window) -> some View {
        HStack(spacing: 7) {
            Text(window.label)
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .frame(width: 62, alignment: .leading)

            if let fraction = window.usedFraction {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(fraction < 0.85 ? Theme.Palette.pasture : Theme.Palette.danger)
                                .frame(width: geo.size.width * fraction)
                                .animation(Motion.activity, value: fraction)
                        }
                    }
                Text("\(Int(fraction * 100))% used")
                    .font(Theme.Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(width: 62, alignment: .trailing)
            } else if let tokens = window.tokens {
                Text("\(tokens.compactTokenLabel) tokens")
                    .font(Theme.Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.secondaryText)
                Spacer()
            }

            if let reset = window.resetLabel {
                Text(reset)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .frame(width: 96, alignment: .trailing)
            }
        }
    }
}
