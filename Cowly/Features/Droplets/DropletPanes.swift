import AVFoundation
import AppKit
import SwiftUI

/// Grid of every droplet, plus the detail pane for the selected one.
struct DropletsPane: View {
    @Environment(\.shelfLayout) private var layout
    @State private var selected: Droplet?
    @State private var filter: Filter = .all
    var prefs = Preferences.shared

    enum Filter: String, CaseIterable, Identifiable {
        case all, onShelf
        var id: String { rawValue }
        var title: String { self == .all ? "All" : "On shelf" }
    }

    private var visible: [Droplet] {
        switch filter {
        case .all: Droplet.all
        case .onShelf: Droplet.all.filter { prefs.isDropletEnabled($0.id) }
        }
    }

    var body: some View {
        Group {
            if let selected {
                detail(for: selected)
            } else {
                grid
            }
        }
        .animation(Motion.snappy, value: selected)
    }

    private var grid: some View {
        VStack(spacing: layout.blockSpacing - 4) {
            HStack(spacing: 8) {
                Text("Droplets")
                    .font(Theme.Typo.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                // Plain tappable chips rather than a segmented Picker: AppKit
                // controls have a history of misbehaving inside this
                // non-activating panel, and this needs to be dependable.
                HStack(spacing: 3) {
                    ForEach(Filter.allCases) { option in
                        Text(option.title)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(filter == option ? .white : Theme.Palette.tertiaryText)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(.white.opacity(filter == option ? 0.18 : 0))
                            )
                            .contentShape(Capsule())
                            .onTapGesture {
                                withAnimation(Motion.snappy) { filter = option }
                            }
                    }
                }
                .padding(2)
                .background(Capsule().fill(.white.opacity(0.05)))
                Spacer()
                ShelfButton(symbol: "gearshape", title: "Droplet settings") {
                    SettingsWindowController.shared.show()
                }
            }

            if visible.isEmpty {
                EmptyHint(symbol: "square.grid.2x2", text: "Nothing on the shelf yet")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: layout.gridColumns),
                        spacing: 8
                    ) {
                        ForEach(visible) { droplet in
                            DropletTile(
                                droplet: droplet,
                                open: { droplet.hasPane ? selected = droplet : toggle(droplet) },
                                toggle: { toggle(droplet) }
                            )
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
    }

    private func toggle(_ droplet: Droplet) {
        prefs.setDroplet(droplet.id, enabled: !prefs.isDropletEnabled(droplet.id))
        Haptics.tap(.levelChange)
    }

    @ViewBuilder
    private func detail(for droplet: Droplet) -> some View {
        VStack(spacing: layout.blockSpacing - 4) {
            HStack(spacing: 8) {
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 24)
                        .foregroundStyle(Theme.Palette.secondaryText)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Label(droplet.name, systemImage: droplet.symbol)
                    .font(Theme.Typo.title)
                    .foregroundStyle(Theme.Palette.primaryText)
                Spacer()
                // Looking at a droplet must never be what puts it on your shelf,
                // so adding it is an explicit, separate action.
                Button(prefs.isDropletEnabled(droplet.id) ? "On shelf ✓" : "Add to shelf") {
                    toggle(droplet)
                }
                .buttonStyle(MiniPillStyle())
            }

            Group {
                switch droplet.id {
                case "clipboard": ClipboardPane()
                case "pomodoro": PomodoroPane()
                case "timer": TimerPane()
                case "notes": NotesPane()
                case "calendar": CalendarPane()
                case "weather": WeatherPane()
                case "stats": StatsPane()
                case "emoji": EmojiPane()
                case "camera": CameraPane()
                case "audio": AudioPane()
                case "aiusage": AIUsagePane()
                default: Text("Nothing to configure.").foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// One droplet in the grid.
///
/// The two actions live in their own rows rather than stacked on top of each
/// other. Overlapping hit areas are how the old add/remove badge ended up
/// unreachable — a nested `Button` never sees the click, and even plain
/// gestures are a coin toss when they cover the same pixels.
struct DropletTile: View {
    let droplet: Droplet
    let open: () -> Void
    let toggle: () -> Void

    var prefs = Preferences.shared
    @State private var isHovering = false
    @State private var hoveringBadge = false

    private var isOn: Bool { prefs.isDropletEnabled(droplet.id) }

    var body: some View {
        VStack(spacing: 1) {
            badgeRow
            infoRow
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 7)
        .padding(.top, 3)
        .background(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .fill(.white.opacity(isOn ? 0.12 : (isHovering ? 0.08 : 0.045)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(isOn ? droplet.tint.opacity(0.5) : .white.opacity(0.07), lineWidth: 0.8)
        )
        .onHover { isHovering = $0 }
        .animation(Motion.snappy, value: isOn)
        .animation(Motion.snappy, value: isHovering)
        .contextMenu {
            if droplet.hasPane { Button("Open", action: open) }
            Button(isOn ? "Remove from shelf" : "Add to shelf", action: toggle)
        }
        .help(droplet.summary)
    }

    /// Top row: nothing but the add/remove control.
    private var badgeRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: isOn ? "checkmark.circle.fill" : "plus.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Theme.Palette.pasture : Theme.Palette.tertiaryText)
                .frame(width: 26, height: 19)
                .background(
                    Circle()
                        .fill(.white.opacity(hoveringBadge ? 0.14 : 0))
                        .frame(width: 22, height: 22)
                )
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
                .onHover { hoveringBadge = $0 }
                .help(isOn ? "Remove from shelf" : "Add to shelf")
        }
    }

    /// Everything below it opens the droplet.
    private var infoRow: some View {
        VStack(spacing: 3) {
            Image(systemName: droplet.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOn ? droplet.tint : Theme.Palette.tertiaryText)
                .frame(height: 19)
            Text(droplet.name)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(isOn ? Theme.Palette.primaryText : Theme.Palette.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

// MARK: - Clipboard pane

struct ClipboardPane: View {
    @Bindable var store = ClipboardStore.shared

    var body: some View {
        Guarded(.clipboard) {
            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.tertiaryText)
                    TextField("Search clipboard", text: $store.query)
                        .textFieldStyle(.plain)
                        .font(Theme.Typo.subtitle)
                        .foregroundStyle(Theme.Palette.primaryText)
                        .focusableInShelf()
                    if !store.query.isEmpty {
                        Button { store.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                    Button("Clear") { store.clear() }
                        .buttonStyle(MiniPillStyle())
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .controlBubble(radius: Radius.chip, fill: 0.07)

                if store.filtered.isEmpty {
                    EmptyHint(symbol: "doc.on.clipboard", text: "Nothing copied yet")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 5) {
                            ForEach(store.filtered) { item in
                                ClipboardRow(item: item)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    var store = ClipboardStore.shared
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 9) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(item.preview)
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.kindLabel)
                    if let app = item.sourceApp { Text("· \(app)") }
                    Text("· \(item.createdAt.relativeShort)")
                }
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if isHovering {
                HStack(spacing: 4) {
                    Button("Paste") { store.paste(item) }.buttonStyle(MiniPillStyle())
                    Button("Copy") { store.copy(item) }.buttonStyle(MiniPillStyle())
                }
                .transition(.opacity)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.10 : 0.045))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Motion.content, value: isHovering)
        .onTapGesture(count: 2) { store.paste(item) }
        .contextMenu {
            Button("Paste") { store.paste(item) }
            Button("Copy") { store.copy(item) }
            Button("Send to Tray") { store.sendToTray(item) }
            if item.kind == .link, let url = item.url {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(item) }
            Button("Delete", role: .destructive) { store.remove(item) }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if item.kind == .color, let color = item.color {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.2), lineWidth: 0.6))
        } else if item.kind == .image, let url = item.url, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: item.symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Palette.secondaryText)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.07)))
        }
    }
}

// MARK: - Pomodoro pane

struct PomodoroPane: View {
    var engine = PomodoroEngine.shared

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                ProgressRing(progress: engine.progress, tint: engine.phase.tint, lineWidth: 6)
                    .frame(width: 92, height: 92)
                VStack(spacing: 0) {
                    Text(engine.remaining.clockLabel)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.primaryText)
                    Text(engine.phase.label)
                        .font(Theme.Typo.caption)
                        .foregroundStyle(Theme.Palette.tertiaryText)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Button(engine.isRunning ? "Pause" : "Start") { engine.toggle() }
                        .buttonStyle(MiniPillStyle())
                    Button("Reset") { engine.reset() }.buttonStyle(MiniPillStyle())
                    Button("Skip") { engine.skip() }.buttonStyle(MiniPillStyle())
                }
                Text("\(engine.completedRounds) rounds completed today")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                HStack(spacing: 10) {
                    MinuteStepper(label: "Focus", value: Binding(
                        get: { engine.focusMinutes }, set: { engine.focusMinutes = $0; engine.reset() }
                    ))
                    MinuteStepper(label: "Break", value: Binding(
                        get: { engine.shortBreakMinutes }, set: { engine.shortBreakMinutes = $0 }
                    ))
                    MinuteStepper(label: "Long", value: Binding(
                        get: { engine.longBreakMinutes }, set: { engine.longBreakMinutes = $0 }
                    ))
                }
            }
            Spacer()
        }
    }
}

private struct MinuteStepper: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.tertiaryText)
            HStack(spacing: 5) {
                Button { value = max(1, value - 1) } label: { Image(systemName: "minus") }
                    .buttonStyle(MiniPillStyle())
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.primaryText)
                    .frame(width: 18)
                Button { value = min(90, value + 1) } label: { Image(systemName: "plus") }
                    .buttonStyle(MiniPillStyle())
            }
        }
    }
}

// MARK: - Timers pane

struct TimerPane: View {
    var engine = TimerEngine.shared
    @State private var customMinutes = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Preferences.shared.timerPresets, id: \.self) { minutes in
                    Button("\(minutes)m") { engine.add(minutes: minutes) }
                        .buttonStyle(MiniPillStyle())
                }
                Spacer()
            }
            if engine.entries.isEmpty {
                EmptyHint(symbol: "hourglass", text: "No timers running")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(engine.entries) { entry in
                            HStack(spacing: 9) {
                                ProgressRing(progress: entry.progress, tint: .orange)
                                    .frame(width: 20, height: 20)
                                Text(entry.label)
                                    .font(Theme.Typo.subtitle)
                                    .foregroundStyle(Theme.Palette.primaryText)
                                Spacer()
                                Text(entry.remaining.clockLabel)
                                    .font(Theme.Typo.mono)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Palette.secondaryText)
                                Button {
                                    engine.togglePause(entry)
                                } label: {
                                    Image(systemName: entry.isPaused ? "play.fill" : "pause.fill")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(MiniPillStyle())
                                Button {
                                    engine.remove(entry)
                                } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                .buttonStyle(MiniPillStyle())
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Notes pane

struct NotesPane: View {
    @Bindable var store = NotesStore.shared

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                TextField("Write a quick note…", text: $store.draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .focusableInShelf()
                    .onSubmit { store.commitDraft() }
                Button("Add") { store.commitDraft() }.buttonStyle(MiniPillStyle())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .controlBubble(radius: Radius.chip, fill: 0.07)

            if store.notes.isEmpty {
                EmptyHint(symbol: "note.text", text: "Your notes live here")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(store.notes) { note in
                            HStack(spacing: 8) {
                                Button {
                                    store.toggle(note)
                                } label: {
                                    Image(systemName: note.isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(note.isDone ? Theme.Palette.positive : Theme.Palette.tertiaryText)
                                }
                                .buttonStyle(.plain)
                                Text(note.text)
                                    .font(Theme.Typo.subtitle)
                                    .strikethrough(note.isDone)
                                    .foregroundStyle(note.isDone ? Theme.Palette.tertiaryText : Theme.Palette.primaryText)
                                    .lineLimit(2)
                                Spacer()
                                Button {
                                    store.remove(note)
                                } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                                .buttonStyle(MiniPillStyle())
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.05)))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Calendar pane

struct CalendarPane: View {
    var store = CalendarStore.shared

    var body: some View {
        Group {
            if !store.accessGranted {
                VStack(spacing: 8) {
                    EmptyHint(symbol: "calendar", text: store.errorMessage ?? "Cowly needs calendar access")
                    Button("Grant access") { Task { await store.requestAccess() } }
                        .buttonStyle(MiniPillStyle())
                }
            } else if store.events.isEmpty {
                EmptyHint(symbol: "calendar", text: "Nothing in the next \(Preferences.shared.calendarDaysAhead) days")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(store.events) { event in
                            HStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: event.colorHex) ?? Theme.Palette.accent)
                                    .frame(width: 3, height: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title)
                                        .font(Theme.Typo.subtitle)
                                        .foregroundStyle(Theme.Palette.primaryText)
                                        .lineLimit(1)
                                    Text("\(event.timeLabel) · \(event.calendarName)")
                                        .font(Theme.Typo.caption)
                                        .foregroundStyle(Theme.Palette.tertiaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if event.isNow {
                                    Text("NOW")
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Capsule().fill(Theme.Palette.positive.opacity(0.25)))
                                        .foregroundStyle(Theme.Palette.positive)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.05)))
                        }
                    }
                }
            }
        }
        .onAppear { CalendarStore.shared.start() }
    }
}

// MARK: - Weather pane

struct WeatherPane: View {
    var store = WeatherStore.shared

    var body: some View {
        Group {
            if let snapshot = store.snapshot {
                HStack(spacing: 22) {
                    VStack(spacing: 2) {
                        Image(systemName: snapshot.symbol)
                            .font(.system(size: 40))
                            .foregroundStyle(.white, .cyan)
                        Text(snapshot.description)
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.display(snapshot.temperature))
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.Palette.primaryText)
                        Text("Feels like " + snapshot.display(snapshot.apparent))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                        Text("H " + snapshot.display(snapshot.high) + "  L " + snapshot.display(snapshot.low))
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Label(snapshot.place, systemImage: "location.fill")
                            .font(Theme.Typo.subtitle)
                            .foregroundStyle(Theme.Palette.secondaryText)
                        Text("Updated \(snapshot.updatedAt.relativeShort)")
                            .font(Theme.Typo.caption)
                            .foregroundStyle(Theme.Palette.tertiaryText)
                        Button("Refresh") { store.requestLocation() }.buttonStyle(MiniPillStyle())
                    }
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    EmptyHint(symbol: "cloud.sun.fill", text: store.errorMessage ?? "Fetching weather…")
                    Button("Enable location") { store.requestLocation() }.buttonStyle(MiniPillStyle())
                }
            }
        }
        .onAppear { WeatherStore.shared.start() }
    }
}

// MARK: - Stats pane

struct StatsPane: View {
    var stats = SystemStats.shared

    var body: some View {
        HStack(spacing: 16) {
            Sparkline(values: stats.cpuHistory, tint: .mint)
                .frame(width: 150, height: 66)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.05)))

            VStack(alignment: .leading, spacing: 8) {
                BigMetric(label: "CPU", value: "\(Int(stats.cpuUsage * 100))%", fraction: stats.cpuUsage, tint: .mint)
                BigMetric(label: "Memory", value: stats.memoryLabel, fraction: stats.memoryFraction, tint: Theme.Palette.accent)
                BigMetric(label: "Disk", value: stats.diskLabel, fraction: stats.diskFraction, tint: .orange)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Uptime")
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Text(stats.uptimeLabel)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Palette.primaryText)
            }
        }
        .onAppear { SystemStats.shared.start() }
    }
}

private struct BigMetric: View {
    let label: String
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(Theme.Typo.caption)
                    .foregroundStyle(Theme.Palette.tertiaryText)
                Spacer(minLength: 6)
                Text(value)
                    .font(Theme.Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.secondaryText)
            }
            Capsule()
                .fill(Color.white.opacity(0.10))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule()
                            .fill(tint)
                            .frame(width: geo.size.width * min(max(fraction, 0), 1), height: 5)
                    }
                }
        }
    }
}

// MARK: - Emoji pane

struct EmojiPane: View {
    @State private var query = ""

    private var results: [(String, String)] {
        guard !query.isEmpty else { return EmojiCatalog.all }
        return EmojiCatalog.all.filter { $0.1.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Palette.tertiaryText)
                TextField("Search emoji", text: $query)
                    .textFieldStyle(.plain)
                    .font(Theme.Typo.subtitle)
                    .foregroundStyle(Theme.Palette.primaryText)
                    .focusableInShelf()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .controlBubble(radius: Radius.chip, fill: 0.07)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 14), spacing: 3) {
                    ForEach(results, id: \.0) { emoji, name in
                        Button {
                            let pb = NSPasteboard.general
                            pb.clearContents()
                            pb.setString(emoji, forType: .string)
                            Haptics.tap(.generic)
                            NotchViewModel.shared.close(force: true)
                            Task {
                                try? await Task.sleep(for: .milliseconds(120))
                                KeyboardSimulator.sendCommandV()
                            }
                        } label: {
                            Text(emoji).font(.system(size: 17))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
        }
    }
}

enum EmojiCatalog {
    static let all: [(String, String)] = [
        ("😀","grin"),("😃","smile"),("😄","happy"),("😁","beam"),("😆","laugh"),("😅","sweat smile"),
        ("🤣","rofl"),("😂","joy"),("🙂","slight smile"),("🙃","upside down"),("😉","wink"),("😊","blush"),
        ("😇","halo"),("🥰","love"),("😍","heart eyes"),("🤩","star struck"),("😘","kiss"),("😗","kissing"),
        ("😚","kissing closed"),("😙","kissing smile"),("🥲","tear"),("😋","yum"),("😛","tongue"),("😜","wink tongue"),
        ("🤪","zany"),("😝","squint tongue"),("🤑","money"),("🤗","hug"),("🤭","hand over mouth"),("🤫","shush"),
        ("🤔","thinking"),("🤐","zipper"),("🤨","raised brow"),("😐","neutral"),("😑","expressionless"),("😶","no mouth"),
        ("😏","smirk"),("😒","unamused"),("🙄","eye roll"),("😬","grimace"),("🤥","lying"),("😌","relieved"),
        ("😔","pensive"),("😪","sleepy"),("🤤","drool"),("😴","sleep"),("😷","mask"),("🤒","thermometer"),
        ("🤕","bandage"),("🤢","nauseated"),("🤮","vomit"),("🤧","sneeze"),("🥵","hot"),("🥶","cold"),
        ("🥴","woozy"),("😵","dizzy"),("🤯","mind blown"),("🤠","cowboy"),("🥳","party"),("😎","cool"),
        ("🤓","nerd"),("🧐","monocle"),("😕","confused"),("😟","worried"),("🙁","frown"),("😮","open mouth"),
        ("😯","hushed"),("😲","astonished"),("😳","flushed"),("🥺","pleading"),("😦","frowning"),("😧","anguished"),
        ("😨","fearful"),("😰","anxious"),("😥","sad"),("😢","cry"),("😭","sob"),("😱","scream"),
        ("😖","confounded"),("😣","persevere"),("😞","disappointed"),("😓","downcast"),("😩","weary"),("😫","tired"),
        ("🥱","yawn"),("😤","triumph"),("😡","pout"),("😠","angry"),("🤬","cursing"),("😈","devil"),
        ("💀","skull"),("💩","poop"),("🤡","clown"),("👻","ghost"),("👽","alien"),("🤖","robot"),
        ("❤️","red heart"),("🧡","orange heart"),("💛","yellow heart"),("💚","green heart"),("💙","blue heart"),
        ("💜","purple heart"),("🖤","black heart"),("🤍","white heart"),("💔","broken heart"),("💯","hundred"),
        ("✨","sparkles"),("⭐️","star"),("🔥","fire"),("💥","boom"),("⚡️","zap"),("🌈","rainbow"),
        ("👍","thumbs up"),("👎","thumbs down"),("👏","clap"),("🙌","raised hands"),("🙏","pray"),("🤝","handshake"),
        ("💪","muscle"),("👀","eyes"),("🧠","brain"),("🫶","heart hands"),("✌️","victory"),("🤞","fingers crossed"),
        ("👋","wave"),("🤙","call me"),("🖖","vulcan"),("✍️","writing"),("🫡","salute"),("🤌","pinched"),
        ("🚀","rocket"),("🛠","tools"),("💻","laptop"),("🖥","desktop"),("⌨️","keyboard"),("🖱","mouse"),
        ("📱","phone"),("💾","floppy"),("📦","package"),("📎","paperclip"),("📌","pin"),("🗂","folders"),
        ("📝","memo"),("📅","calendar"),("⏰","alarm"),("⏳","hourglass"),("🔒","lock"),("🔑","key"),
        ("🎯","target"),("🏆","trophy"),("🎉","tada"),("🎈","balloon"),("🎵","note"),("🎧","headphones"),
        ("☕️","coffee"),("🍕","pizza"),("🍔","burger"),("🍎","apple"),("🌮","taco"),("🍺","beer"),
        ("🌙","moon"),("☀️","sun"),("☁️","cloud"),("🌊","wave"),("🌱","seedling"),("🍀","clover")
    ]
}

// MARK: - Camera pane

struct CameraPane: View {
    var body: some View {
        VStack(spacing: 6) {
            CameraPreview()
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 0.7))
            Text("Live preview · nothing is recorded or sent anywhere")
                .font(Theme.Typo.caption)
                .foregroundStyle(Theme.Palette.tertiaryText)
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView() }
    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) { nsView.stop() }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dev.emrekoca.Cowly.camera")
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func configure() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            DispatchQueue.main.async { self?.startSession() }
        }
    }

    private func startSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = bounds
        layer?.addSublayer(preview)
        previewLayer = preview

        // AVCaptureSession blocks while it spins up, so never on the main queue.
        nonisolated(unsafe) let capture = session
        sessionQueue.async { capture.startRunning() }
    }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    func stop() {
        guard session.isRunning else { return }
        nonisolated(unsafe) let capture = session
        sessionQueue.async { capture.stopRunning() }
    }
}

// MARK: - Audio pane

struct AudioPane: View {
    var audio = AudioOutput.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(Theme.Palette.secondaryText)
                ShelfSlider(
                    value: Binding(
                        get: { Double(audio.volume) },
                        set: { audio.volume = Float($0); audio.setVolume(Float($0)) }
                    ),
                    tint: .purple
                )
                Text("\(Int(audio.volume * 100))%")
                    .font(Theme.Typo.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .frame(width: 34, alignment: .trailing)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(audio.devices) { device in
                        Button {
                            audio.select(device)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: device.symbol)
                                    .foregroundStyle(device.isDefault ? Theme.Palette.accent : Theme.Palette.secondaryText)
                                Text(device.name)
                                    .font(Theme.Typo.subtitle)
                                    .foregroundStyle(Theme.Palette.primaryText)
                                Spacer()
                                if device.isDefault {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.Palette.accent)
                                }
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(device.isDefault ? 0.10 : 0.045)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { audio.refresh() }
    }
}

// MARK: - Shared

struct EmptyHint: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Theme.Palette.tertiaryText)
            Text(text)
                .font(Theme.Typo.subtitle)
                .foregroundStyle(Theme.Palette.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
