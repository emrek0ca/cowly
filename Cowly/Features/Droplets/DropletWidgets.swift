import AppKit
import SwiftUI

/// A single droplet's small card on the Home rail.
///
/// Every widget is the same size, which keeps the rail tidy and turns
/// reordering into plain index arithmetic while one is being dragged.
struct DropletWidget: View {
    @Environment(\.shelfLayout) private var layout

    let droplet: Droplet
    var isDragging: Bool = false
    @State private var isHovering = false

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: layout.widgetWidth, height: layout.widgetHeight, alignment: .leading)
            .card(
                radius: Radius.bubble(forHeight: layout.widgetHeight),
                fill: isHovering ? 0.11 : 0.07,
                stroke: isDragging ? 0 : 0.09
            )
            .overlay {
                if isDragging {
                    RoundedRectangle(cornerRadius: Radius.bubble(forHeight: layout.widgetHeight), style: .continuous)
                        .strokeBorder(Theme.Palette.muzzle.opacity(0.85), lineWidth: 1.4)
                }
            }
            .overlay(alignment: .topTrailing) { grip }
            .scaleEffect(isDragging ? 1.06 : (isHovering ? 1.02 : 1))
            .shadow(color: .black.opacity(isDragging ? 0.5 : 0), radius: 14, y: 6)
            .animation(Motion.snappy, value: isHovering)
            .animation(Motion.snappy, value: isDragging)
            .onHover { isHovering = $0 }
            .contextMenu {
                Button("Move left") { Preferences.shared.moveDroplet(droplet.id, by: -1) }
                Button("Move right") { Preferences.shared.moveDroplet(droplet.id, by: 1) }
                Divider()
                Button("Hide from shelf") {
                    Preferences.shared.setDroplet(droplet.id, enabled: false)
                }
                Button("Reset shelf order") { Preferences.shared.resetShelfOrder() }
                Button("Shelf settings…") { SettingsWindowController.shared.show() }
            }
    }

    /// Purely an affordance — the whole card is draggable.
    @ViewBuilder
    private var grip: some View {
        if isHovering || isDragging {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .padding(4)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    /// Each droplet renders its own miniature; the frame around them is shared.
    @ViewBuilder
    private var content: some View {
        switch droplet.id {
        case "pomodoro": PomodoroWidget()
        case "timer": TimerWidget()
        case "notes": NotesWidget()
        case "calendar": CalendarWidget()
        case "clipboard": ClipboardWidget()
        case "highalert": HighAlertWidget()
        case "stats": StatsWidget()
        case "battery": BatteryWidget()
        case "weather": WeatherWidget()
        case "audio": AudioWidget()
        case "aiusage": AIUsageWidget()
        case "shortcuts": ShortcutsWidget()
        default: EmptyView()
        }
    }
}

/// Shared chrome so every widget reads as part of the same family.
private struct WidgetFrame<Content: View>: View {
    let symbol: String
    let title: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .tracking(0.6)
                    .lineLimit(1)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .clipped()
    }
}

// MARK: - Pomodoro

struct PomodoroWidget: View {
    @Environment(\.shelfLayout) private var layout
    var engine = PomodoroEngine.shared

    var body: some View {
        WidgetFrame(symbol: "timer", title: "Pomodoro", tint: engine.phase.tint) {
            HStack(spacing: 8) {
                ProgressRing(progress: engine.progress, tint: engine.phase.tint)
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(engine.remaining.clockLabel)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(Motion.content, value: engine.remaining)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(engine.phase.label)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
                if layout.widgetShowsAccessory {
                    Button {
                        engine.toggle()
                    } label: {
                        Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(.white.opacity(0.14)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Timers

struct TimerWidget: View {
    @Environment(\.shelfLayout) private var layout
    var engine = TimerEngine.shared

    var body: some View {
        WidgetFrame(symbol: "hourglass", title: "Timer", tint: .orange) {
            if let soonest = engine.soonest {
                HStack(spacing: 8) {
                    ProgressRing(progress: soonest.progress, tint: .orange)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(soonest.remaining.clockLabel)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(Motion.content, value: soonest.remaining)
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text(soonest.label)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(spacing: 5) {
                    ForEach(Preferences.shared.timerPresets.prefix(layout.widgetShowsAccessory ? 3 : 2), id: \.self) { minutes in
                        Button("\(minutes)m") { engine.add(minutes: minutes) }
                            .buttonStyle(MiniPillStyle())
                            .fixedSize()
                    }
                }
            }
        }
    }
}

// MARK: - Notes

struct NotesWidget: View {
    var store = NotesStore.shared

    var body: some View {
        WidgetFrame(symbol: "note.text", title: "Notes", tint: .yellow) {
            if let latest = store.notes.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text(latest.text)
                        .font(Theme.Typo.subtitle)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(2)
                    Text("\(store.notes.count) notes")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            } else {
                Text("No notes yet")
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
    }
}

// MARK: - Calendar

struct CalendarWidget: View {
    var store = CalendarStore.shared

    var body: some View {
        WidgetFrame(symbol: "calendar", title: "Next up", tint: .pink) {
            if let next = store.next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.title)
                        .font(Theme.Typo.subtitle)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(1)
                    Text(next.isNow ? "Now · \(next.calendarName)" : "\(next.timeLabel) · in \(next.minutesUntil)m")
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
            } else {
                Text(store.accessGranted ? "Nothing scheduled" : "Grant calendar access")
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Clipboard

struct ClipboardWidget: View {
    var store = ClipboardStore.shared

    var body: some View {
        WidgetFrame(symbol: "doc.on.clipboard", title: "Clipboard", tint: Theme.Palette.accent) {
            if let latest = store.items.first {
                HStack(spacing: 7) {
                    Image(systemName: latest.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.secondaryText)
                    Text(latest.preview)
                        .font(Theme.Typo.subtitle)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .lineLimit(2)
                }
            } else {
                Text("Nothing copied yet")
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .onTapGesture { NotchViewModel.shared.select(.droplets) }
    }
}

// MARK: - High Alert

struct HighAlertWidget: View {
    var engine = HighAlertEngine.shared

    var body: some View {
        WidgetFrame(symbol: "cup.and.saucer.fill", title: "High Alert", tint: .brown) {
            Button {
                engine.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: engine.isActive ? "eye.fill" : "eye.slash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(engine.isActive ? Theme.Palette.pasture : Theme.Palette.tertiaryText)
                        .symbolEffect(.pulse, isActive: engine.isActive)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(engine.isActive ? "Awake" : "Off")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Palette.primaryText)
                        if engine.isActive {
                            Text(engine.elapsedLabel)
                                .font(Theme.Typo.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.tertiaryText)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Stats

struct StatsWidget: View {
    @Environment(\.shelfLayout) private var layout
    var stats = SystemStats.shared

    var body: some View {
        WidgetFrame(symbol: "chart.bar.fill", title: "System", tint: .mint) {
            HStack(spacing: 8) {
                // The sparkline is the first thing to go: in a compact rail it
                // leaves the meters too narrow to read.
                if layout.widgetShowsAccessory {
                    Sparkline(values: stats.cpuHistory, tint: .mint)
                        .frame(width: 34, height: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    MetricRow(label: "CPU", value: stats.cpuUsage, tint: .mint)
                    MetricRow(label: "RAM", value: stats.memoryFraction, tint: Theme.Palette.accent)
                }
            }
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.tertiaryText)
                .frame(width: 22, alignment: .leading)
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(minWidth: 18, idealHeight: 4, maxHeight: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * min(max(value, 0), 1), height: 4)
                            .animation(Motion.content, value: value)
                    }
                }
            Text("\(Int(value * 100))%")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Motion.content, value: value)
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: geo.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: geo.size.height * (1 - CGFloat(min(max(value, 0), 1)))
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geo.size.height))
                    path.addLine(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Battery

struct BatteryWidget: View {
    var power = PowerMonitor.shared

    var body: some View {
        WidgetFrame(symbol: power.battery.symbol, title: "Battery", tint: power.battery.tint) {
            HStack(spacing: 8) {
                ProgressRing(progress: Double(power.battery.percentage) / 100, tint: power.battery.tint)
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(power.battery.percentage)%")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Motion.content, value: power.battery.percentage)
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(power.battery.timeLabel ?? (power.battery.isPluggedIn ? "Plugged in" : "On battery"))
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Weather

struct WeatherWidget: View {
    var store = WeatherStore.shared

    var body: some View {
        WidgetFrame(symbol: store.snapshot?.symbol ?? "cloud.sun.fill", title: "Weather", tint: .cyan) {
            if let snapshot = store.snapshot {
                HStack(spacing: 8) {
                    Image(systemName: snapshot.symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(.white, .cyan)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(snapshot.display(snapshot.temperature))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text(snapshot.place)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                            .lineLimit(1)
                    }
                }
            } else {
                Text(store.errorMessage == nil ? "Loading…" : "Location off")
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                    .lineLimit(2)
            }
        }
        .onAppear { WeatherStore.shared.start() }
    }
}

// MARK: - Audio

struct AudioWidget: View {
    var audio = AudioOutput.shared

    var body: some View {
        WidgetFrame(symbol: "speaker.wave.2.fill", title: "Volume", tint: .purple) {
            HStack(spacing: 8) {
                ShelfSlider(
                    value: Binding(
                        get: { Double(audio.volume) },
                        set: { newValue in
                            audio.volume = Float(newValue)
                            audio.setVolume(Float(newValue))
                        }
                    ),
                    tint: .purple,
                    height: 4
                )
                .frame(width: 88)
                Text("\(Int(audio.volume * 100))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(width: 22, alignment: .trailing)
            }
        }
    }
}

// MARK: - Quick actions

struct ShortcutsWidget: View {
    var prefs = Preferences.shared

    var body: some View {
        WidgetFrame(symbol: "bolt.square.fill", title: "Quick", tint: .teal) {
            HStack(spacing: 6) {
                ForEach(prefs.chosenQuickActions.prefix(4)) { action in
                    QuickAction(symbol: action.symbol, help: action.title) { action.perform() }
                }
            }
        }
    }
}

private struct QuickAction: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(Theme.Palette.primaryText)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct MiniPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(Theme.Palette.primaryText)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.24 : 0.11))
            )
    }
}

/// System actions that do not need extra entitlements. Pick which four of
/// these sit on the Quick Actions widget in Settings › Droplets.
struct QuickActionKind: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String

    @MainActor
    func perform() { QuickActions.run(id) }

    static let catalog: [QuickActionKind] = [
        QuickActionKind(id: "screenshot", title: "Screenshot selection", symbol: "camera.viewfinder"),
        QuickActionKind(id: "screenshotWindow", title: "Screenshot a window", symbol: "macwindow.badge.plus"),
        QuickActionKind(id: "finder", title: "Open Finder", symbol: "folder"),
        QuickActionKind(id: "sleepDisplay", title: "Sleep display", symbol: "moon.fill"),
        QuickActionKind(id: "lock", title: "Lock screen", symbol: "lock.fill"),
        QuickActionKind(id: "cover", title: "Cover screen", symbol: "eye.slash.fill"),
        QuickActionKind(id: "missionControl", title: "Mission Control", symbol: "square.grid.3x2"),
        QuickActionKind(id: "emptyClipboard", title: "Clear clipboard history", symbol: "eraser"),
        QuickActionKind(id: "newNote", title: "New note", symbol: "square.and.pencil"),
        QuickActionKind(id: "toggleDock", title: "Toggle right dock", symbol: "dock.rectangle")
    ]

    static func find(_ id: String) -> QuickActionKind? { catalog.first { $0.id == id } }
}

@MainActor
enum QuickActions {
    static func run(_ id: String) {
        switch id {
        case "screenshot": capture(["-i", "-c"])
        case "screenshotWindow": capture(["-i", "-w", "-c"])
        case "finder": NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
        case "sleepDisplay": shell("/usr/bin/pmset", ["displaysleepnow"])
        case "lock": shell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"])
        case "cover": LockScreenController.shared.present()
        case "missionControl": shell("/usr/bin/open", ["-a", "Mission Control"])
        case "emptyClipboard": ClipboardStore.shared.clear()
        case "newNote": NotchViewModel.shared.open(tab: .droplets)
        case "toggleDock":
            let enabled = SideDockController.shared.configuration(for: .right).isEnabled
            SideDockController.shared.setEnabled(!enabled, for: .right)
        default: break
        }
    }

    private static func capture(_ arguments: [String]) {
        NotchViewModel.shared.close(force: true)
        shell("/usr/sbin/screencapture", arguments)
    }

    private static func shell(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}
