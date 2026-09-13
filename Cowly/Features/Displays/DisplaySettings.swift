import AppKit
import Observation
import SwiftUI

/// Per-display overrides.
///
/// Keyed by the display's stable identifier rather than its index, so
/// unplugging a monitor and plugging it back in — or swapping the order in
/// System Settings — keeps each screen's own setup.
struct DisplayProfile: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Whether the shelf may appear on this display at all.
    var isEnabled: Bool
    /// nil means "use the global width scale".
    var widthScale: Double?
    /// Island width for a display with no notch, as a fraction of its width.
    var islandFraction: Double?
    var glassDimming: Double?
    /// Tab the shelf opens on for this display.
    var defaultTab: String?

    static func makeDefault(id: String, name: String) -> DisplayProfile {
        DisplayProfile(
            id: id, name: name, isEnabled: true,
            widthScale: nil, islandFraction: nil, glassDimming: nil, defaultTab: nil
        )
    }

    var tab: ShelfTab? { defaultTab.flatMap(ShelfTab.init(rawValue:)) }
}

/// Knows every screen currently attached and the settings that belong to each.
@MainActor
@Observable
final class DisplayRegistry {
    static let shared = DisplayRegistry()

    private(set) var profiles: [DisplayProfile]
    /// Screens attached right now, newest listing first.
    private(set) var attached: [ScreenInfo] = []

    struct ScreenInfo: Identifiable, Sendable, Equatable {
        let id: String
        let name: String
        let frame: CGRect
        let hasNotch: Bool
        let isMain: Bool
        var notchSize: CGSize?
    }

    private init() {
        profiles = Disk.load([DisplayProfile].self, from: Paths.displayStore) ?? []
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { DisplayRegistry.shared.refresh() }
        }
    }

    func refresh() {
        attached = NSScreen.screens.map { screen in
            let left = screen.auxiliaryTopLeftArea
            let right = screen.auxiliaryTopRightArea
            var notch: CGSize?
            if let left, let right {
                let width = screen.frame.width - left.width - right.width
                let height = max(left.height, right.height)
                if width > 40, height > 10 { notch = CGSize(width: width, height: height) }
            }
            return ScreenInfo(
                id: screen.cowlyIdentifier,
                name: screen.localizedName,
                frame: screen.frame,
                hasNotch: notch != nil,
                isMain: screen == NSScreen.main,
                notchSize: notch
            )
        }
        // Make sure every attached screen has a profile to edit.
        for screen in attached where !profiles.contains(where: { $0.id == screen.id }) {
            profiles.append(.makeDefault(id: screen.id, name: screen.name))
        }
        persist()
    }

    func profile(for screen: NSScreen) -> DisplayProfile {
        profile(forID: screen.cowlyIdentifier, name: screen.localizedName)
    }

    func profile(forID id: String, name: String = "Display") -> DisplayProfile {
        profiles.first { $0.id == id } ?? .makeDefault(id: id, name: name)
    }

    func update(_ profile: DisplayProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        persist()
        NotchViewModel.shared.refreshGeometry(for: nil, force: true)
    }

    func forget(_ id: String) {
        profiles.removeAll { $0.id == id }
        persist()
    }

    /// Screens the shelf is allowed to live on.
    var enabledScreens: [NSScreen] {
        NSScreen.screens.filter { profile(for: $0).isEnabled }
    }

    private func persist() { Disk.save(profiles, to: Paths.displayStore) }
}

extension NSScreen {
    /// Stable across reconnects: the display's serial/vendor identity when the
    /// window server exposes it, falling back to the transient number.
    var cowlyIdentifier: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return "unknown"
        }
        let id = CGDirectDisplayID(number.uint32Value)
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)
        if vendor != 0 || model != 0 {
            return "v\(vendor)-m\(model)-s\(serial)"
        }
        return "id\(id)"
    }
}
