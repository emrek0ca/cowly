import AppKit
import Foundation
import OSLog
import ServiceManagement

let log = Logger(subsystem: "dev.emrekoca.Cowly", category: "app")

/// Where the tray keeps copies of dropped files and where state is persisted.
enum Paths {
    static let container: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cowly", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static let trayStore = container.appendingPathComponent("tray.json")
    static let clipboardStore = container.appendingPathComponent("clipboard.json")
    static let notesStore = container.appendingPathComponent("notes.json")
    static let dockStore = container.appendingPathComponent("docks.json")
    static let displayStore = container.appendingPathComponent("displays.json")

    static let trayFiles: URL = {
        let dir = container.appendingPathComponent("TrayFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let clipboardAssets: URL = {
        let dir = container.appendingPathComponent("ClipboardAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
}

/// Tiny JSON-on-disk helper. Everything in Cowly is local-only.
enum Disk {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                } else {
                    if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                }
            } catch {
                log.error("Launch at login toggle failed: \(error.localizedDescription)")
            }
        }
    }
}

enum Haptics {
    @MainActor
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard Preferences.shared.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

extension Int {
    var byteLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

extension TimeInterval {
    var clockLabel: String {
        guard isFinite, self >= 0 else { return "--:--" }
        let total = Int(rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

extension Date {
    var relativeShort: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
