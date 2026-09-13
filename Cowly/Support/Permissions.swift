import AppKit
import AVFoundation
import CoreLocation
import EventKit
import Observation

/// Asks for the permissions Cowly needs, rather than leaving them to be found.
///
/// Most of them prompt on first use through their own frameworks. Accessibility
/// is the exception: nothing prompts for it automatically, and without it the
/// media keys cannot be taken from macOS. So it is requested explicitly, and
/// then watched — the moment it is granted the key tap starts, with no restart.
@MainActor
@Observable
final class PermissionCenter {
    static let shared = PermissionCenter()

    enum State: Equatable {
        case granted
        case denied
        case notAsked

        var symbol: String {
            switch self {
            case .granted: "checkmark.circle.fill"
            case .denied: "exclamationmark.triangle.fill"
            case .notAsked: "circle.dashed"
            }
        }
    }

    private(set) var accessibility: State = .notAsked
    private var watchTask: Task<Void, Never>?

    private init() {}

    func start() {
        refresh()
        // Ask once, up front, for the one permission that never prompts itself.
        if accessibility != .granted, Preferences.shared.interceptMediaKeys {
            requestAccessibility()
        }
        watchAccessibility()
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
    }

    func refresh() {
        accessibility = AXIsProcessTrusted() ? .granted : (hasAskedForAccessibility ? .denied : .notAsked)
    }

    /// Shows the system's "open Accessibility settings" prompt.
    func requestAccessibility() {
        hasAskedForAccessibility = true
        // The constant is a global `var` in the C header, so reach for the key
        // by name instead of touching shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refresh()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The permission is granted outside the app, so nothing tells us when it
    /// lands. Poll gently until it does, then wire everything up.
    private func watchAccessibility() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                let wasGranted = self.accessibility == .granted
                self.refresh()
                if trusted, !wasGranted {
                    HUDController.shared.refreshInterception()
                }
            }
        }
    }

    private var hasAskedForAccessibility: Bool {
        get { UserDefaults.standard.bool(forKey: "permissions.askedAccessibility") }
        set { UserDefaults.standard.set(newValue, forKey: "permissions.askedAccessibility") }
    }

    // MARK: - The rest, for the settings list

    var camera: State {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    var calendar: State {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    var location: State {
        switch CLLocationManager().authorizationStatus {
        case .authorized, .authorizedAlways: .granted
        case .notDetermined: .notAsked
        default: .denied
        }
    }

    func requestCamera() { AVCaptureDevice.requestAccess(for: .video) { _ in } }
    func requestCalendar() { Task { await CalendarStore.shared.requestAccess() } }
    func requestLocation() { WeatherStore.shared.requestLocation() }
}
