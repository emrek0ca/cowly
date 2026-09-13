import AppKit
import SwiftUI
import Foundation
import Observation

/// Watches system volume and display brightness and mirrors changes as a
/// notch HUD, so the feedback appears where your eyes already are.
@MainActor
@Observable
final class HUDController {
    static let shared = HUDController()

    private var timer: Timer?
    private var lastVolume: Float = AudioOutput.readVolume()
    private var lastBrightness: Float = Brightness.current()
    private var primed = false

    private init() {}

    /// True when Cowly owns the keys and macOS shows no overlay of its own.
    var isReplacingSystemHUD: Bool { MediaKeyTap.shared.isActive }

    /// Why the system overlay is still showing, if it is.
    var interceptionStatus: String {
        guard Preferences.shared.hudEnabled else { return "Cowly's HUD is off." }
        guard Preferences.shared.interceptMediaKeys else {
            return "Cowly mirrors the system overlay instead of replacing it."
        }
        if MediaKeyTap.shared.isActive {
            return "Cowly handles the keys, so macOS shows no overlay of its own."
        }
        return MediaKeyTap.shared.canActivate
            ? "The key tap could not start. Try toggling this off and on."
            : "Grant Accessibility permission to replace the macOS overlay."
    }

    func start() {
        MediaKeyTap.shared.onVolume = { [weak self] value, muted in
            self?.lastVolume = value
            self?.presentVolume(value, muted: muted)
        }
        MediaKeyTap.shared.onBrightness = { [weak self] value in
            self?.lastBrightness = value
            self?.presentBrightness(value)
        }
        refreshInterception()
        startFallbackPolling()
        // Skip the very first comparison so we do not flash a HUD at launch.
        Task { try? await Task.sleep(for: .seconds(1)); self.primed = true }
    }

    func stop() {
        MediaKeyTap.shared.stop()
        timer?.invalidate()
        timer = nil
    }

    /// Turns key interception on or off to match the preference, and keeps the
    /// polling fallback running only while it is needed.
    func refreshInterception() {
        let wants = Preferences.shared.hudEnabled && Preferences.shared.interceptMediaKeys
        if wants {
            MediaKeyTap.shared.start()
        } else {
            MediaKeyTap.shared.stop()
        }
        startFallbackPolling()
    }

    /// Without the key tap there is nothing to intercept, so the next best
    /// thing is to watch the values and show a HUD alongside the system's.
    private func startFallbackPolling() {
        let needed = Preferences.shared.hudEnabled && !MediaKeyTap.shared.isActive
        guard needed else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        lastVolume = AudioOutput.readVolume()
        lastBrightness = Brightness.current()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.08
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func poll() {
        guard Preferences.shared.hudEnabled, primed else { return }

        let volume = AudioOutput.readVolume()
        if abs(volume - lastVolume) > 0.005 {
            lastVolume = volume
            presentVolume(volume, muted: AudioOutput.isMuted())
        }

        let brightness = Brightness.current()
        if abs(brightness - lastBrightness) > 0.005 {
            lastBrightness = brightness
            presentBrightness(brightness)
        }
    }

    private func presentVolume(_ value: Float, muted: Bool) {
        present(
            id: Self.volumeActivity,
            symbol: muted || value <= 0.001 ? "speaker.slash.fill" : symbolForVolume(value),
            tint: muted ? Theme.Palette.danger : Theme.Palette.accent,
            title: muted ? "Muted" : "Volume",
            value: muted ? 0 : value
        )
    }

    private func presentBrightness(_ value: Float) {
        present(
            id: Self.brightnessActivity,
            symbol: "sun.max.fill",
            tint: Theme.Palette.warning,
            title: "Brightness",
            value: value
        )
    }

    private func symbolForVolume(_ value: Float) -> String {
        switch value {
        case ..<0.33: "speaker.wave.1.fill"
        case ..<0.66: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }

    /// A stable id per kind so repeated presses update one pill instead of
    /// stacking a new one on every keystroke.
    private static let volumeActivity = UUID()
    private static let brightnessActivity = UUID()

    private func present(id: UUID, symbol: String, tint: Color, title: String, value: Float) {
        NotchViewModel.shared.present(
            LiveActivity(
                id: id,
                style: .expanded,
                leadingSymbol: symbol,
                leadingTint: tint,
                title: title,
                subtitle: nil,
                progress: Double(value),
                trailingText: "\(Int((value * 100).rounded()))%",
                duration: 1.6
            )
        )
    }
}

/// Display brightness through the private DisplayServices shim, with a no-op
/// fallback on hardware that does not expose it.
enum Brightness {
    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private nonisolated(unsafe) static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    private nonisolated(unsafe) static let getter: GetBrightness? = {
        guard let handle, let pointer = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(pointer, to: GetBrightness.self)
    }()

    private nonisolated(unsafe) static let setter: SetBrightness? = {
        guard let handle, let pointer = dlsym(handle, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(pointer, to: SetBrightness.self)
    }()

    static var isSupported: Bool { getter != nil }

    static func current(display: CGDirectDisplayID = CGMainDisplayID()) -> Float {
        guard let getter else { return 0 }
        var value: Float = 0
        guard getter(display, &value) == 0 else { return 0 }
        return value
    }

    @discardableResult
    static func set(_ value: Float, display: CGDirectDisplayID = CGMainDisplayID()) -> Bool {
        guard let setter else { return false }
        return setter(display, min(max(value, 0), 1)) == 0
    }
}
