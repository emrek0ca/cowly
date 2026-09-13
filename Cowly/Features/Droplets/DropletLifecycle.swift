import Foundation

/// Starts and stops the engines behind the droplets.
///
/// Each droplet is backed by something that polls, watches or asks for a
/// permission, and none of that should run for a droplet that is switched off.
/// The engines used to be started once at launch from whatever happened to be
/// enabled then, which meant a droplet you turned on later never had anything
/// feeding it — it sat there showing an empty state forever. Every change to
/// the enabled set now runs through here.
@MainActor
enum DropletLifecycle {
    /// Brings every engine in line with what is currently switched on.
    static func sync() {
        let prefs = Preferences.shared

        set(prefs.isDropletEnabled("calendar")) {
            CalendarStore.shared.start()
        } stop: {
            CalendarStore.shared.stop()
        }

        set(prefs.isDropletEnabled("weather")) {
            WeatherStore.shared.start()
        } stop: {
            WeatherStore.shared.stop()
        }

        set(prefs.isDropletEnabled("stats")) {
            SystemStats.shared.start(interval: prefs.statsInterval)
        } stop: {
            SystemStats.shared.stop()
        }

        set(prefs.isDropletEnabled("aiusage")) {
            AIUsageMonitor.shared.start()
        } stop: {
            AIUsageMonitor.shared.stop()
        }

        // The battery widget and the charge alerts share one monitor.
        set(prefs.isDropletEnabled("battery") || prefs.batteryAlerts) {
            PowerMonitor.shared.start()
        } stop: {
            PowerMonitor.shared.stop()
        }

        // Same for the clipboard droplet and the global history switch.
        set(prefs.isDropletEnabled("clipboard") && prefs.clipboardEnabled) {
            ClipboardStore.shared.start()
        } stop: {
            ClipboardStore.shared.stop()
        }
    }

    /// Engines are idempotent about start/stop, so this stays a plain switch.
    private static func set(_ isOn: Bool, start: () -> Void, stop: () -> Void) {
        isOn ? start() : stop()
    }

    /// Anything a droplet needs the moment it is switched on — a permission
    /// prompt, a first fetch — so its widget has real data immediately rather
    /// than after the next poll.
    static func primeAfterEnabling(_ id: String) {
        switch id {
        case "calendar":
            Task { await CalendarStore.shared.requestAccess() }
        case "weather":
            WeatherStore.shared.requestLocation()
        case "aiusage":
            AIUsageMonitor.shared.refresh()
        case "audio":
            AudioOutput.shared.refresh()
        default:
            break
        }
    }
}
