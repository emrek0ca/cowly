import AppKit
import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, appearance, displays, droplets, docks, security, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .displays: "Displays"
            case .droplets: "Droplets"
            case .docks: "Side Docks"
            case .security: "Touch ID"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "paintbrush"
            case .displays: "display.2"
            case .droplets: "square.grid.2x2"
            case .docks: "dock.rectangle"
            case .security: "touchid"
            case .about: "info.circle"
            }
        }
    }

    @State private var pane: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 172, max: 200)
        } detail: {
            ScrollView {
                Group {
                    switch pane {
                    case .general: GeneralSettings()
                    case .appearance: AppearanceSettings()
                    case .displays: DisplaySettingsPane()
                    case .droplets: DropletSettings()
                    case .docks: DockSettings()
                    case .security: SecuritySettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(pane.title)
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var prefs = Preferences.shared
    var vm = NotchViewModel.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    private var openWidth: CGFloat { vm.geometry.openSize.width }
    private var layout: ShelfLayout { ShelfLayout(width: openWidth) }

    private var densityIcon: String {
        switch layout.density {
        case .compact: "arrow.left.and.right.square"
        case .regular: "rectangle.split.2x1"
        case .roomy: "rectangle.split.3x1"
        }
    }

    private var densityDescription: String {
        let notch = vm.geometry.closedSize.width
        let base = "\(Int(notch))pt notch → \(Int(openWidth))pt open shelf."
        switch layout.density {
        case .compact:
            return base + " Compact: the album line, source badge, remaining time and the device name are hidden so rows still fit."
        case .regular:
            return base + " Regular: everything but the album line and the app badge text."
        case .roomy:
            return base + " Roomy: every detail is shown."
        }
    }


    var body: some View {
        SettingsSection("Startup") {
            Toggle("Launch Cowly at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.isEnabled = newValue }
        }

        SettingsSection("Opening the shelf") {
            Toggle("Open on hover", isOn: $prefs.openOnHover)
            HStack {
                Text("Hover delay")
                Slider(value: $prefs.hoverDelay, in: 0...0.6, step: 0.02)
                Text("\(prefs.hoverDelay, specifier: "%.2f")s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
            .disabled(!prefs.openOnHover)
            Toggle("Open when a file is dragged onto the notch", isOn: $prefs.openOnDrag)
            Toggle("Haptic feedback (trackpad)", isOn: $prefs.haptics)
            LabeledContent("Keyboard shortcut") {
                Text("⌥⌘C")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }

        SettingsSection("Shelf size") {
            HStack {
                Text("Open width")
                Slider(value: $prefs.shelfWidthScale, in: 1.0...5.0, step: 0.1)
                Text("\(prefs.shelfWidthScale, specifier: "%.1f")×")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
            }
            // Tell people what the multiplier actually costs them, rather than
            // leaving them to discover a cramped layout by feel.
            HStack(spacing: 6) {
                Image(systemName: densityIcon)
                    .foregroundStyle(.secondary)
                Text(densityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("The closed shelf always matches your Mac's notch exactly; the open shelf is a multiple of it, so it grows out of the same shape.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Let the closed shelf widen to show artwork while playing", isOn: $prefs.showNowPlayingPeek)
        }

        SettingsSection("Displays") {
            Toggle("Follow the display the pointer is on", isOn: $prefs.followMouseScreen)
            Toggle("Show a floating island on Macs without a notch", isOn: $prefs.islandOnNotchless)
        }

        SettingsSection("Features") {
            Toggle("Floating basket when you jiggle a drag", isOn: $prefs.basketEnabled)
            Toggle("Clipboard history", isOn: $prefs.clipboardEnabled)
            Stepper("Keep \(prefs.clipboardLimit) clipboard items", value: $prefs.clipboardLimit, in: 20...1000, step: 20)
                .disabled(!prefs.clipboardEnabled)
            Toggle("Volume and brightness HUD in the notch", isOn: $prefs.hudEnabled)
            Toggle("Replace the macOS overlay (take the media keys)", isOn: $prefs.interceptMediaKeys)
                .disabled(!prefs.hudEnabled)
            HStack(spacing: 6) {
                Image(systemName: HUDController.shared.isReplacingSystemHUD ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(HUDController.shared.isReplacingSystemHUD ? .green : .secondary)
                Text(HUDController.shared.interceptionStatus)
                    .font(.caption).foregroundStyle(.secondary)
                if !MediaKeyTap.shared.canActivate {
                    Button("Open Accessibility") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            }
            Toggle("Battery and charging alerts", isOn: $prefs.batteryAlerts)
        }

        SettingsSection("Media") {
            Picker("Now Playing source", selection: $prefs.mediaSource) {
                ForEach(MediaSourcePreference.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)
            Text("Automatic prefers whichever app is actually playing. Apple Music and Spotify need permission to send Apple Events the first time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Bindable var prefs = Preferences.shared

    var body: some View {
        SettingsSection("Material") {
            Picker("Shelf surface", selection: $prefs.glassStyle) {
                ForEach(GlassStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            if #available(macOS 26.0, *) {
                Text("Liquid Glass uses the system material introduced in macOS 26.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("This Mac renders a hand-tuned glass stack; Liquid Glass needs macOS 26 or later.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Tint the shelf with the album artwork", isOn: $prefs.tintFromArtwork)
            HStack {
                Text("Dimming")
                Slider(value: $prefs.glassDimming, in: 0...0.8, step: 0.02)
                Text("\(Int(prefs.glassDimming * 100))%")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
            }
            Text("Pure Liquid Glass is nearly clear, so a bright window behind the shelf shows straight through it. This is the dark backing that keeps the shelf readable.")
                .font(.caption).foregroundStyle(.secondary)
        }

        SettingsSection("Preview") {
            ShelfPreview()
        }
    }
}

private struct ShelfPreview: View {
    var prefs = Preferences.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.28, green: 0.18, blue: 0.32)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack {
                let shape = NotchShape(topRadius: 12, bottomRadius: 24)
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.14))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Capsule().fill(.white.opacity(0.8)).frame(width: 110, height: 8)
                        Capsule().fill(.white.opacity(0.35)).frame(width: 70, height: 6)
                    }
                    Spacer()
                }
                .padding(14)
                .frame(width: 320, height: 78)
                .clipShape(shape)
                .glassSurface(shape, style: prefs.glassStyle)
                .overlay(GlassRim(shape: shape))
                .padding(.top, 16)
                Spacer()
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .preferredColorScheme(.dark)
    }
}

// MARK: - Droplets

struct DropletSettings: View {
    @Bindable var prefs = Preferences.shared

    var body: some View {
        Text("Droplets are free extensions built into Cowly. They stay inert until you switch them on.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)

        ShelfWidgetEditor()

        ForEach(Droplet.byCategory, id: \.0) { category, droplets in
            SettingsSection(category.rawValue) {
                ForEach(droplets) { droplet in
                    DropletSettingsRow(droplet: droplet)
                }
            }
        }
    }
}

/// The Home rail, editable without touching a drag gesture.
///
/// Dragging a card is the quick way to rearrange the shelf, but it must not be
/// the *only* way: a gesture that misses leaves the feature looking broken.
struct ShelfWidgetEditor: View {
    @Bindable var prefs = Preferences.shared

    private var onShelf: [Droplet] { prefs.orderedShelfDroplets }
    private var available: [Droplet] {
        Droplet.all.filter { $0.hasWidget && !prefs.isDropletEnabled($0.id) }
    }

    var body: some View {
        SettingsSection("Home shelf") {
            Text("Widgets on the rail under the player, in order. Drag them on the shelf itself, or use these controls.")
                .font(.caption).foregroundStyle(.secondary)

            if onShelf.isEmpty {
                Text("No widgets yet — add one below.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(onShelf.enumerated()), id: \.element.id) { index, droplet in
                    HStack(spacing: 9) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)
                        Image(systemName: droplet.symbol)
                            .foregroundStyle(droplet.tint)
                            .frame(width: 18)
                        Text(droplet.name)
                        Spacer()
                        Button { prefs.moveDroplet(droplet.id, by: -1) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button { prefs.moveDroplet(droplet.id, by: 1) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == onShelf.count - 1)
                        Button { prefs.setDroplet(droplet.id, enabled: false) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove from the shelf")
                    }
                }
            }

            HStack {
                if available.isEmpty {
                    Text("Every widget is already on the shelf.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Menu("Add widget…") {
                        ForEach(available) { droplet in
                            Button {
                                prefs.setDroplet(droplet.id, enabled: true)
                            } label: {
                                Label(droplet.name, systemImage: droplet.symbol)
                            }
                        }
                    }
                    .frame(width: 170)
                }
                Spacer()
                Button("Reset order") { prefs.resetShelfOrder() }
                    .disabled(prefs.shelfOrder.isEmpty)
            }
        }
    }
}

/// One droplet's on/off switch plus whatever it lets you tune.
struct DropletSettingsRow: View {
    let droplet: Droplet
    @Bindable var prefs = Preferences.shared
    @State private var isExpanded = false

    private var isOn: Bool { prefs.isDropletEnabled(droplet.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Toggle(isOn: Binding(
                    get: { isOn },
                    set: { prefs.setDroplet(droplet.id, enabled: $0) }
                )) {
                    HStack(spacing: 9) {
                        Image(systemName: droplet.symbol)
                            .foregroundStyle(droplet.tint)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(droplet.name)
                            Text(droplet.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                if hasOptions {
                    Button {
                        withAnimation(.snappy) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!isOn)
                }
            }

            if isExpanded, isOn {
                options
                    .padding(.leading, 30)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var hasOptions: Bool {
        ["pomodoro", "weather", "stats", "timer", "clipboard", "highalert", "aiusage", "shortcuts", "calendar"].contains(droplet.id)
    }

    @ViewBuilder
    private var options: some View {
        switch droplet.id {
        case "pomodoro":
            Stepper("Focus: \(prefs.pomodoroFocus) min", value: $prefs.pomodoroFocus, in: 1...120)
            Stepper("Short break: \(prefs.pomodoroShortBreak) min", value: $prefs.pomodoroShortBreak, in: 1...60)
            Stepper("Long break: \(prefs.pomodoroLongBreak) min", value: $prefs.pomodoroLongBreak, in: 1...90)
            Stepper("Long break every \(prefs.pomodoroRounds) rounds", value: $prefs.pomodoroRounds, in: 2...10)
        case "weather":
            Picker("Units", selection: $prefs.useFahrenheit) {
                Text("Celsius").tag(false)
                Text("Fahrenheit").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            Button("Refresh now") { WeatherStore.shared.requestLocation() }
        case "stats":
            HStack {
                Text("Refresh every")
                Slider(value: $prefs.statsInterval, in: 0.5...10, step: 0.5)
                    .frame(width: 160)
                Text("\(prefs.statsInterval, specifier: "%.1f")s")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .onChange(of: prefs.statsInterval) { _, newValue in
                SystemStats.shared.restart(interval: newValue)
            }
        case "timer":
            Text("Quick presets shown on the widget")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([1, 3, 5, 10, 15, 25, 45, 60], id: \.self) { minutes in
                    Toggle("\(minutes)m", isOn: Binding(
                        get: { prefs.timerPresets.contains(minutes) },
                        set: { on in
                            var presets = prefs.timerPresets
                            if on { presets.append(minutes) } else { presets.removeAll { $0 == minutes } }
                            prefs.timerPresets = presets.sorted()
                        }
                    ))
                    .toggleStyle(.button)
                    .controlSize(.small)
                }
            }
        case "clipboard":
            Stepper("Keep \(prefs.clipboardLimit) items", value: $prefs.clipboardLimit, in: 20...1000, step: 20)
            Toggle("Ask for Touch ID before opening", isOn: $prefs.lockClipboard)
            Button("Clear history now") { ClipboardStore.shared.clear() }
        case "aiusage":
            Text("Codex reports its real quota, so that bar is exact. Claude Code stores no quota locally — give Cowly your own estimate of a 5-hour block and it will show a percentage against it.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text("Claude 5h budget")
                TextField("0 = off", value: $prefs.claudeBlockBudget, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                Text("tokens").foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach([0, 20_000_000, 50_000_000, 100_000_000, 200_000_000], id: \.self) { value in
                    Button(value == 0 ? "Off" : value.compactTokenLabel) { prefs.claudeBlockBudget = value }
                        .controlSize(.small)
                }
            }
            Button("Refresh now") { AIUsageMonitor.shared.refresh() }
        case "shortcuts":
            Text("Pick up to four actions for the widget.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(QuickActionKind.catalog) { action in
                Toggle(isOn: Binding(
                    get: { prefs.chosenQuickActions.contains(action) },
                    set: { on in
                        var ids = prefs.chosenQuickActions.map(\.id)
                        if on {
                            guard ids.count < 4 else { return }
                            ids.append(action.id)
                        } else {
                            ids.removeAll { $0 == action.id }
                        }
                        prefs.quickActionIDs = ids
                    }
                )) {
                    Label(action.title, systemImage: action.symbol)
                }
                .disabled(prefs.chosenQuickActions.count >= 4 && !prefs.chosenQuickActions.contains(action))
            }
        case "calendar":
            Stepper("Look ahead \(prefs.calendarDaysAhead) days", value: $prefs.calendarDaysAhead, in: 1...30)
            Button("Reload events") { CalendarStore.shared.reload() }
        case "highalert":
            Toggle("Also keep the display awake", isOn: Binding(
                get: { HighAlertEngine.shared.keepDisplayAwake },
                set: { HighAlertEngine.shared.keepDisplayAwake = $0 }
            ))
            Stepper(
                HighAlertEngine.shared.autoOffMinutes == 0
                    ? "Stay awake until turned off"
                    : "Turn off after \(HighAlertEngine.shared.autoOffMinutes) min",
                value: Binding(
                    get: { HighAlertEngine.shared.autoOffMinutes },
                    set: { HighAlertEngine.shared.autoOffMinutes = $0 }
                ),
                in: 0...480, step: 15
            )
        default:
            EmptyView()
        }
    }
}

// MARK: - Displays

struct DisplaySettingsPane: View {
    var registry = DisplayRegistry.shared
    @Bindable var prefs = Preferences.shared

    var body: some View {
        SettingsSection("Which display") {
            Toggle("Follow the display the pointer is on", isOn: $prefs.followMouseScreen)
            Text(prefs.followMouseScreen
                 ? "The shelf moves to whichever enabled display your pointer is on."
                 : "The shelf stays on the first enabled display that has a notch, or the main one.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Rescan displays") { registry.refresh() }
                Spacer()
                Text("\(registry.attached.count) attached")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        ForEach(registry.attached) { screen in
            DisplayProfileEditor(screen: screen)
        }

        let stale = registry.profiles.filter { profile in
            !registry.attached.contains { $0.id == profile.id }
        }
        if !stale.isEmpty {
            SettingsSection("Remembered, not attached") {
                Text("Settings for displays you have used before. They come back automatically when you plug the display in again.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(stale) { profile in
                    HStack {
                        Image(systemName: "display").foregroundStyle(.secondary)
                        Text(profile.name)
                        Spacer()
                        Button("Forget") { registry.forget(profile.id) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

struct DisplayProfileEditor: View {
    let screen: DisplayRegistry.ScreenInfo
    var registry = DisplayRegistry.shared
    var prefs = Preferences.shared

    private var profile: DisplayProfile { registry.profile(forID: screen.id, name: screen.name) }

    private func edit(_ change: (inout DisplayProfile) -> Void) {
        var next = profile
        change(&next)
        next.name = screen.name
        registry.update(next)
    }

    /// A binding that writes nil when the override is switched off.
    private func override(
        _ keyPath: WritableKeyPath<DisplayProfile, Double?>,
        fallback: Double
    ) -> Binding<Double> {
        Binding(
            get: { profile[keyPath: keyPath] ?? fallback },
            set: { value in edit { $0[keyPath: keyPath] = value } }
        )
    }

    var body: some View {
        SettingsSection(screen.name) {
            HStack(spacing: 10) {
                Image(systemName: screen.hasNotch ? "menubar.dock.rectangle" : "display")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(screen.frame.width)) × \(Int(screen.frame.height)) pt")
                    Text(detail)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Use Cowly here", isOn: Binding(
                    get: { profile.isEnabled },
                    set: { value in edit { $0.isEnabled = value } }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            Group {
                overrideRow(
                    label: "Open width",
                    isOn: profile.widthScale != nil,
                    toggle: { on in edit { $0.widthScale = on ? prefs.shelfWidthScale : nil } }
                ) {
                    HStack {
                        Slider(value: override(\.widthScale, fallback: prefs.shelfWidthScale), in: 1.0...5.0, step: 0.1)
                        Text("\(profile.widthScale ?? prefs.shelfWidthScale, specifier: "%.1f")×")
                            .monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                }

                if !screen.hasNotch {
                    overrideRow(
                        label: "Island size",
                        isOn: profile.islandFraction != nil,
                        toggle: { on in edit { $0.islandFraction = on ? 0.11 : nil } }
                    ) {
                        HStack {
                            Slider(value: override(\.islandFraction, fallback: 0.11), in: 0.06...0.24, step: 0.005)
                            Text("\(Int((profile.islandFraction ?? 0.11) * (screen.frame.width))) pt")
                                .monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                        }
                    }
                }

                overrideRow(
                    label: "Glass dimming",
                    isOn: profile.glassDimming != nil,
                    toggle: { on in edit { $0.glassDimming = on ? prefs.glassDimming : nil } }
                ) {
                    HStack {
                        Slider(value: override(\.glassDimming, fallback: prefs.glassDimming), in: 0...0.8, step: 0.02)
                        Text("\(Int((profile.glassDimming ?? prefs.glassDimming) * 100))%")
                            .monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                    }
                }

                HStack {
                    Text("Opens on")
                    Picker("", selection: Binding(
                        get: { profile.defaultTab ?? "" },
                        set: { value in edit { $0.defaultTab = value.isEmpty ? nil : value } }
                    )) {
                        Text("Last used").tag("")
                        ForEach(ShelfTab.allCases) { tab in
                            Text(tab.title).tag(tab.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    Spacer()
                }
            }
            .disabled(!profile.isEnabled)
        }
    }

    private var detail: String {
        var parts: [String] = []
        if let notch = screen.notchSize {
            parts.append("notch \(Int(notch.width))×\(Int(notch.height))")
        } else {
            parts.append("no notch — floating island")
        }
        if screen.isMain { parts.append("main display") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func overrideRow<Control: View>(
        label: String,
        isOn: Bool,
        toggle: @escaping (Bool) -> Void,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(get: { isOn }, set: toggle)) {
                Text(label).frame(width: 104, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            control()
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.45)
        }
    }
}

// MARK: - Side docks

struct DockSettings: View {
    var controller = SideDockController.shared

    var body: some View {
        Text("Docks pin droplet widgets to the edges of your screen. They can stay visible, or tuck away until you push the pointer into the edge.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)

        ForEach(DockEdge.allCases) { edge in
            DockEdgeSettings(edge: edge)
        }
    }
}

struct DockEdgeSettings: View {
    let edge: DockEdge
    var controller = SideDockController.shared

    private var config: DockConfiguration { controller.configuration(for: edge) }

    /// Widget-capable droplets that are not already on this dock.
    private var available: [Droplet] {
        Droplet.all.filter { $0.hasWidget && !config.dropletIDs.contains($0.id) }
    }

    var body: some View {
        SettingsSection("\(edge.label) dock") {
            Toggle(isOn: Binding(
                get: { config.isEnabled },
                set: { controller.setEnabled($0, for: edge) }
            )) {
                Label("Show a dock on the \(edge.label.lowercased()) edge", systemImage: edge.symbol)
            }

            Toggle(isOn: Binding(
                get: { config.autoHide },
                set: { var next = config; next.autoHide = $0; controller.update(next) }
            )) {
                Text("Hide until the pointer reaches the edge")
            }
            .disabled(!config.isEnabled)

            HStack {
                Text("Position")
                Slider(
                    value: Binding(
                        get: { config.position },
                        set: { var next = config; next.position = $0; controller.update(next) }
                    ),
                    in: 0...1
                )
                Text(positionLabel)
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .trailing)
            }
            .disabled(!config.isEnabled)

            Divider()

            if config.droplets.isEmpty {
                Text("No widgets yet — add one below.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(config.droplets) { droplet in
                    HStack(spacing: 9) {
                        Image(systemName: droplet.symbol)
                            .foregroundStyle(droplet.tint)
                            .frame(width: 18)
                        Text(droplet.name)
                        Spacer()
                        Button { controller.move(droplet.id, by: -1, on: edge) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(config.dropletIDs.first == droplet.id)
                        Button { controller.move(droplet.id, by: 1, on: edge) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(config.dropletIDs.last == droplet.id)
                        Button { controller.remove(droplet.id, from: edge) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if !available.isEmpty {
                Menu("Add widget…") {
                    ForEach(available) { droplet in
                        Button(droplet.name) { controller.add(droplet.id, to: edge) }
                    }
                }
                .frame(width: 180)
                .disabled(!config.isEnabled)
            }
        }
    }

    private var positionLabel: String {
        switch config.position {
        case ..<0.2: edge.isVertical ? "Top" : "Left"
        case ..<0.45: edge.isVertical ? "Upper" : "Left of centre"
        case ..<0.55: "Centre"
        case ..<0.8: edge.isVertical ? "Lower" : "Right of centre"
        default: edge.isVertical ? "Bottom" : "Right"
        }
    }
}

// MARK: - Security

struct SecuritySettings: View {
    @Bindable var prefs = Preferences.shared
    var gate = BiometricGate.shared
    @State private var testResult: String?

    var body: some View {
        SettingsSection("This Mac") {
            HStack(spacing: 12) {
                Image(systemName: gate.activeMethodSymbol)
                    .font(.system(size: 30))
                    .foregroundStyle(available ? Theme.Palette.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gate.activeMethodLabel)
                        .font(.headline)
                    Text(availabilityDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Test") {
                    Task {
                        let ok = await gate.authenticate(.settings)
                        testResult = ok ? "Authenticated ✓" : (gate.lastError ?? "Cancelled")
                    }
                }
            }
            if let testResult {
                Text(testResult).font(.caption).foregroundStyle(.secondary)
            }
        }

        SettingsSection("Screen cover") {
            Label(
                "macOS does not let any third-party app add a biometric method to the real login window — Touch ID, Apple Watch and your password are the only ways to unlock the Mac itself.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("What Cowly can do is pull a full-screen curtain over your desktop that lifts with Touch ID or your password. It hides your work; it does not secure the Mac.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cover screen now") { LockScreenController.shared.present() }
                Text("⌥⌘L").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            }
        }

        SettingsSection("Require authentication for") {
            Toggle("Opening the file tray", isOn: $prefs.lockTray)
            Toggle("Opening clipboard history", isOn: $prefs.lockClipboard)
            Toggle("Opening these settings", isOn: $prefs.lockSettings)
            Toggle("Deleting tray items", isOn: $prefs.confirmDeletesWithBiometrics)
        }

        SettingsSection("Auto-lock") {
            Picker("Re-lock after", selection: $prefs.autoLockMinutes) {
                Text("Immediately").tag(0)
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("1 hour").tag(60)
            }
            Text("Cowly also re-locks whenever your Mac sleeps or the screen locks.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Lock everything now") { gate.lockAll() }
                .disabled(gate.unlocked.isEmpty)
        }
    }

    private var available: Bool {
        if case .unavailable = gate.availability { return false }
        return true
    }

    private var availabilityDetail: String {
        switch gate.availability {
        case .biometrics:
            "Locked panes ask for a fingerprint, with your login password as fallback."
        case .passwordOnly:
            "No biometric sensor found. Locked panes will ask for your login password."
        case .unavailable(let message):
            message
        }
    }
}

// MARK: - About

struct AboutSettings: View {
    var permissions = PermissionCenter.shared

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CowFace(size: 44, tint: Theme.Palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cowly").font(.largeTitle.bold())
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Text("Free. Local-first. No account, no telemetry.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SettingsSection("Permissions") {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets Cowly take the volume and brightness keys, so the macOS overlay never appears. Also powers ⌥⌘C and real pasting.",
                    state: permissions.accessibility,
                    request: { permissions.requestAccessibility() },
                    openSettings: { permissions.openAccessibilitySettings() }
                )
                PermissionRow(
                    title: "Calendar",
                    detail: "Shows your next events on the shelf.",
                    state: permissions.calendar,
                    request: { permissions.requestCalendar() },
                    openSettings: { openPrivacy("Privacy_Calendars") }
                )
                PermissionRow(
                    title: "Location",
                    detail: "Local weather, fetched from Open-Meteo without an account.",
                    state: permissions.location,
                    request: { permissions.requestLocation() },
                    openSettings: { openPrivacy("Privacy_LocationServices") }
                )
                PermissionRow(
                    title: "Camera",
                    detail: "The camera droplet's live preview.",
                    state: permissions.camera,
                    request: { permissions.requestCamera() },
                    openSettings: { openPrivacy("Privacy_Camera") }
                )
                Text("Cowly asks for each of these when it first needs them. Accessibility is the only one macOS never prompts for on its own, so Cowly requests it at launch and starts using it the moment you grant it — no restart.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsSection("Where your data lives") {
                LabeledContent("Application Support") {
                    Button(Paths.container.lastPathComponent) {
                        NSWorkspace.shared.open(Paths.container)
                    }
                    .buttonStyle(.link)
                }
                Text("Tray files, clipboard history and notes never leave this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func openPrivacy(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let state: PermissionCenter.State
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                Text("Granted").font(.caption).foregroundStyle(.secondary)
            case .notAsked:
                Button("Allow…", action: request)
            case .denied:
                Button("Open Settings", action: openSettings)
            }
        }
        .onAppear { PermissionCenter.shared.refresh() }
    }

    private var tint: Color {
        switch state {
        case .granted: .green
        case .denied: .orange
        case .notAsked: .secondary
        }
    }
}

// MARK: - Shared chrome

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(0.5)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .padding(.bottom, 16)
    }
}
