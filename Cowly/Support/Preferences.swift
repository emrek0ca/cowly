import Foundation
import Observation
import SwiftUI

/// Every user-facing setting lives here and writes straight through to
/// UserDefaults, so changing a toggle updates the shelf on the next frame.
@MainActor
@Observable
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private init() {
        defaults.register(defaults: Self.registrations)
        glassStyle = GlassStyle(rawValue: defaults.string(forKey: Keys.glassStyle) ?? "") ?? .liquid
        openOnHover = defaults.bool(forKey: Keys.openOnHover)
        // A delay longer than this reads as the shelf being broken, and the
        // slider no longer offers it, so bring stored values back in range.
        hoverDelay = min(defaults.double(forKey: Keys.hoverDelay), 0.6)
        openOnDrag = defaults.bool(forKey: Keys.openOnDrag)
        haptics = defaults.bool(forKey: Keys.haptics)
        islandOnNotchless = defaults.bool(forKey: Keys.islandOnNotchless)
        followMouseScreen = defaults.bool(forKey: Keys.followMouseScreen)
        tintFromArtwork = defaults.bool(forKey: Keys.tintFromArtwork)
        basketEnabled = defaults.bool(forKey: Keys.basketEnabled)
        clipboardEnabled = defaults.bool(forKey: Keys.clipboardEnabled)
        clipboardLimit = defaults.integer(forKey: Keys.clipboardLimit)
        hudEnabled = defaults.bool(forKey: Keys.hudEnabled)
        interceptMediaKeys = defaults.bool(forKey: Keys.interceptKeys)
        batteryAlerts = defaults.bool(forKey: Keys.batteryAlerts)
        mediaSource = MediaSourcePreference(rawValue: defaults.string(forKey: Keys.mediaSource) ?? "") ?? .automatic
        lockTray = defaults.bool(forKey: Keys.lockTray)
        lockClipboard = defaults.bool(forKey: Keys.lockClipboard)
        lockSettings = defaults.bool(forKey: Keys.lockSettings)
        autoLockMinutes = defaults.integer(forKey: Keys.autoLockMinutes)
        confirmDeletesWithBiometrics = defaults.bool(forKey: Keys.confirmDeletes)
        enabledDroplets = Set(defaults.stringArray(forKey: Keys.enabledDroplets) ?? [])
        shelfOrder = defaults.stringArray(forKey: Keys.shelfOrder) ?? []
        pomodoroFocus = defaults.integer(forKey: Keys.pomodoroFocus)
        pomodoroShortBreak = defaults.integer(forKey: Keys.pomodoroShort)
        pomodoroLongBreak = defaults.integer(forKey: Keys.pomodoroLong)
        pomodoroRounds = defaults.integer(forKey: Keys.pomodoroRounds)
        useFahrenheit = defaults.bool(forKey: Keys.fahrenheit)
        statsInterval = defaults.double(forKey: Keys.statsInterval)
        timerPresets = defaults.array(forKey: Keys.timerPresets) as? [Int] ?? [1, 5, 10, 25]
        shelfWidthScale = defaults.double(forKey: Keys.shelfWidthScale)
        showNowPlayingPeek = defaults.bool(forKey: Keys.nowPlayingPeek)
        claudeBlockBudget = defaults.integer(forKey: Keys.claudeBudget)
        glassDimming = defaults.double(forKey: Keys.glassDimming)
        quickActionIDs = defaults.stringArray(forKey: Keys.quickActions) ?? []
        calendarDaysAhead = defaults.integer(forKey: Keys.calendarDays)
    }

    // MARK: - Appearance
    var glassStyle: GlassStyle { didSet { defaults.set(glassStyle.rawValue, forKey: Keys.glassStyle) } }
    var tintFromArtwork: Bool { didSet { defaults.set(tintFromArtwork, forKey: Keys.tintFromArtwork) } }
    /// How much dark backing sits under the glass. Pure Liquid Glass is almost
    /// clear, which makes the shelf unreadable over a bright window.
    var glassDimming: Double { didSet { defaults.set(glassDimming, forKey: Keys.glassDimming) } }
    var islandOnNotchless: Bool { didSet { defaults.set(islandOnNotchless, forKey: Keys.islandOnNotchless) } }
    var followMouseScreen: Bool { didSet { defaults.set(followMouseScreen, forKey: Keys.followMouseScreen) } }
    /// Open width as a multiple of the notch width. 1.0 keeps it notch-sized.
    var shelfWidthScale: Double {
        didSet {
            defaults.set(shelfWidthScale, forKey: Keys.shelfWidthScale)
            NotchViewModel.shared.refreshGeometry(for: nil, force: true)
        }
    }
    /// Lets the closed shelf grow past the notch to show artwork and bars.
    var showNowPlayingPeek: Bool { didSet { defaults.set(showNowPlayingPeek, forKey: Keys.nowPlayingPeek) } }

    /// Your own estimate of how many tokens a Claude 5-hour block holds. Claude
    /// Code does not publish this, so a percentage is only shown once you set
    /// one from experience. 0 means "just show the token count".
    var claudeBlockBudget: Int {
        didSet {
            defaults.set(claudeBlockBudget, forKey: Keys.claudeBudget)
            AIUsageMonitor.shared.refresh()
        }
    }

    // MARK: - Behaviour
    var openOnHover: Bool { didSet { defaults.set(openOnHover, forKey: Keys.openOnHover) } }
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) } }
    var openOnDrag: Bool { didSet { defaults.set(openOnDrag, forKey: Keys.openOnDrag) } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: Keys.haptics) } }

    // MARK: - Features
    var basketEnabled: Bool { didSet { defaults.set(basketEnabled, forKey: Keys.basketEnabled) } }
    var clipboardEnabled: Bool {
        didSet {
            defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled)
            DropletLifecycle.sync()
        }
    }
    var clipboardLimit: Int { didSet { defaults.set(clipboardLimit, forKey: Keys.clipboardLimit) } }
    var hudEnabled: Bool { didSet { defaults.set(hudEnabled, forKey: Keys.hudEnabled) } }
    /// Take the volume and brightness keys before macOS does, so its own
    /// overlay never appears and Cowly's HUD is the only one on screen.
    var interceptMediaKeys: Bool {
        didSet {
            defaults.set(interceptMediaKeys, forKey: Keys.interceptKeys)
            HUDController.shared.refreshInterception()
        }
    }
    var batteryAlerts: Bool {
        didSet {
            defaults.set(batteryAlerts, forKey: Keys.batteryAlerts)
            DropletLifecycle.sync()
        }
    }
    var mediaSource: MediaSourcePreference { didSet { defaults.set(mediaSource.rawValue, forKey: Keys.mediaSource) } }

    // MARK: - Touch ID
    var lockTray: Bool { didSet { defaults.set(lockTray, forKey: Keys.lockTray) } }
    var lockClipboard: Bool { didSet { defaults.set(lockClipboard, forKey: Keys.lockClipboard) } }
    var lockSettings: Bool { didSet { defaults.set(lockSettings, forKey: Keys.lockSettings) } }
    var autoLockMinutes: Int { didSet { defaults.set(autoLockMinutes, forKey: Keys.autoLockMinutes) } }
    var confirmDeletesWithBiometrics: Bool { didSet { defaults.set(confirmDeletesWithBiometrics, forKey: Keys.confirmDeletes) } }

    // MARK: - Droplets
    var enabledDroplets: Set<String> {
        didSet {
            defaults.set(Array(enabledDroplets), forKey: Keys.enabledDroplets)
            // A droplet is only as good as the engine behind it, and that engine
            // has to follow the switch.
            DropletLifecycle.sync()
        }
    }
    var shelfOrder: [String] { didSet { defaults.set(shelfOrder, forKey: Keys.shelfOrder) } }

    // MARK: - Per-droplet options
    var pomodoroFocus: Int { didSet { defaults.set(pomodoroFocus, forKey: Keys.pomodoroFocus) } }
    var pomodoroShortBreak: Int { didSet { defaults.set(pomodoroShortBreak, forKey: Keys.pomodoroShort) } }
    var pomodoroLongBreak: Int { didSet { defaults.set(pomodoroLongBreak, forKey: Keys.pomodoroLong) } }
    var pomodoroRounds: Int { didSet { defaults.set(pomodoroRounds, forKey: Keys.pomodoroRounds) } }
    var useFahrenheit: Bool { didSet { defaults.set(useFahrenheit, forKey: Keys.fahrenheit) } }
    var statsInterval: Double { didSet { defaults.set(statsInterval, forKey: Keys.statsInterval) } }
    var timerPresets: [Int] { didSet { defaults.set(timerPresets, forKey: Keys.timerPresets) } }
    var quickActionIDs: [String] { didSet { defaults.set(quickActionIDs, forKey: Keys.quickActions) } }
    var calendarDaysAhead: Int {
        didSet {
            defaults.set(calendarDaysAhead, forKey: Keys.calendarDays)
            CalendarStore.shared.reload()
        }
    }

    var chosenQuickActions: [QuickActionKind] {
        let picked = quickActionIDs.compactMap(QuickActionKind.find)
        return picked.isEmpty ? Array(QuickActionKind.catalog.prefix(4)) : picked
    }

    /// Slides a shelf widget `offset` places left or right. Returns false when
    /// it is already at the end, so the drag keeps its accumulated travel.
    @discardableResult
    func moveDroplet(_ id: String, by offset: Int) -> Bool {
        guard offset != 0 else { return false }
        var order = orderedShelfDroplets.map(\.id)
        guard let from = order.firstIndex(of: id) else { return false }
        let to = from + offset
        guard order.indices.contains(to) else { return false }
        order.remove(at: from)
        order.insert(id, at: to)
        shelfOrder = order
        Haptics.tap(.alignment)
        return true
    }

    func resetShelfOrder() { shelfOrder = [] }

    func isDropletEnabled(_ id: String) -> Bool { enabledDroplets.contains(id) }

    func setDroplet(_ id: String, enabled: Bool) {
        guard isDropletEnabled(id) != enabled else { return }
        if enabled { enabledDroplets.insert(id) } else { enabledDroplets.remove(id) }
        if enabled { DropletLifecycle.primeAfterEnabling(id) }
    }

    // MARK: - Storage keys
    private enum Keys {
        static let glassStyle = "appearance.glassStyle"
        static let tintFromArtwork = "appearance.tintFromArtwork"
        static let glassDimming = "appearance.glassDimming"
        static let islandOnNotchless = "appearance.islandOnNotchless"
        static let followMouseScreen = "appearance.followMouseScreen"
        static let shelfWidthScale = "appearance.shelfWidthScale"
        static let nowPlayingPeek = "appearance.nowPlayingPeek"
        static let claudeBudget = "droplet.ai.claudeBudget"
        static let openOnHover = "behaviour.openOnHover"
        static let hoverDelay = "behaviour.hoverDelay"
        static let openOnDrag = "behaviour.openOnDrag"
        static let haptics = "behaviour.haptics"
        static let basketEnabled = "feature.basket"
        static let clipboardEnabled = "feature.clipboard"
        static let clipboardLimit = "feature.clipboardLimit"
        static let hudEnabled = "feature.hud"
        static let interceptKeys = "feature.interceptMediaKeys"
        static let batteryAlerts = "feature.batteryAlerts"
        static let mediaSource = "feature.mediaSource"
        static let lockTray = "security.lockTray"
        static let lockClipboard = "security.lockClipboard"
        static let lockSettings = "security.lockSettings"
        static let autoLockMinutes = "security.autoLockMinutes"
        static let confirmDeletes = "security.confirmDeletes"
        static let enabledDroplets = "droplets.enabled"
        static let shelfOrder = "droplets.shelfOrder"
        static let pomodoroFocus = "droplet.pomodoro.focus"
        static let pomodoroShort = "droplet.pomodoro.short"
        static let pomodoroLong = "droplet.pomodoro.long"
        static let pomodoroRounds = "droplet.pomodoro.rounds"
        static let fahrenheit = "droplet.weather.fahrenheit"
        static let statsInterval = "droplet.stats.interval"
        static let timerPresets = "droplet.timer.presets"
        static let quickActions = "droplet.quickActions"
        static let calendarDays = "droplet.calendar.days"
    }

    private static let registrations: [String: Any] = [
        Keys.glassStyle: GlassStyle.liquid.rawValue,
        Keys.tintFromArtwork: true,
        Keys.glassDimming: 0.28,
        Keys.islandOnNotchless: true,
        Keys.followMouseScreen: true,
        Keys.shelfWidthScale: 3.0,
        Keys.nowPlayingPeek: false,
        Keys.claudeBudget: 0,
        Keys.openOnHover: true,
        Keys.hoverDelay: 0.06,
        Keys.openOnDrag: true,
        Keys.haptics: true,
        Keys.basketEnabled: true,
        Keys.clipboardEnabled: true,
        Keys.clipboardLimit: 200,
        Keys.hudEnabled: true,
        Keys.interceptKeys: true,
        Keys.batteryAlerts: true,
        Keys.mediaSource: MediaSourcePreference.automatic.rawValue,
        Keys.lockTray: false,
        Keys.lockClipboard: false,
        Keys.lockSettings: false,
        Keys.autoLockMinutes: 5,
        Keys.confirmDeletes: false,
        Keys.enabledDroplets: ["pomodoro", "highalert", "stats", "aiusage", "notes", "timer"],
        Keys.shelfOrder: [],
        Keys.pomodoroFocus: 25,
        Keys.pomodoroShort: 5,
        Keys.pomodoroLong: 15,
        Keys.pomodoroRounds: 4,
        Keys.fahrenheit: false,
        Keys.statsInterval: 2.0,
        Keys.timerPresets: [1, 5, 10, 25],
        Keys.quickActions: ["screenshot", "finder", "cover", "lock"],
        Keys.calendarDays: 7
    ]
}

enum MediaSourcePreference: String, CaseIterable, Sendable {
    case automatic
    case appleMusic
    case spotify

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }
}
