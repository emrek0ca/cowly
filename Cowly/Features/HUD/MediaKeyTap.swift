import AppKit
import Foundation

/// Intercepts the volume, mute and brightness keys.
///
/// macOS draws its own volume and brightness overlay from `OSDUIHelper`, and
/// there is no API to turn that off. Killing the helper — the usual trick — is
/// a fight you keep having, because it respawns. The honest way is to take the
/// key press before the system sees it: Cowly applies the change itself and
/// shows its own HUD, so the system overlay is never asked to appear.
///
/// This needs Accessibility permission. Without it the tap cannot be created,
/// and Cowly falls back to watching the values and mirroring the system HUD
/// instead of replacing it.
@MainActor
final class MediaKeyTap {
    static let shared = MediaKeyTap()

    private(set) var isActive = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// Called with the new value so the HUD can show it.
    var onVolume: ((Float, Bool) -> Void)?
    var onBrightness: ((Float) -> Void)?

    private init() {}

    // Keys carried inside an NX_SYSDEFINED event.
    private enum Key: Int32 {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    var canActivate: Bool { AXIsProcessTrusted() }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard canActivate else { return false }

        // NX_SYSDEFINED is event type 14; media keys arrive as subtype 8.
        let mask = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in
                // The tap callback runs on the run loop that installed it,
                // which is the main one, so the hop is an assertion not a jump.
                nonisolated(unsafe) let incoming = event
                let handled = MainActor.assumeIsolated { MediaKeyTap.shared.handle(incoming) }
                return handled ? nil : Unmanaged.passUnretained(incoming)
            },
            userInfo: nil
        ) else {
            log.notice("Media key tap could not be created; system HUD stays in charge.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        isActive = true
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        source = nil
        isActive = false
    }

    /// Returns true when Cowly handled the key and the system must not see it.
    private func handle(_ event: CGEvent) -> Bool {
        guard Preferences.shared.hudEnabled, Preferences.shared.interceptMediaKeys else { return false }
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == 8 else { return false }

        let data = nsEvent.data1
        let keyCode = Int32((data & 0xFFFF_0000) >> 16)
        let flags = data & 0x0000_FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0x0A
        guard let key = Key(rawValue: keyCode) else { return false }

        // Only act on the press; swallow the matching release so nothing else
        // reacts to half an event.
        guard isDown else { return true }

        // Option-Shift is the system's own fine-adjust gesture; match it.
        let fine = nsEvent.modifierFlags.contains([.option, .shift])
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0

        switch key {
        case .soundUp, .soundDown:
            let current = AudioOutput.readVolume()
            let next = min(max(current + (key == .soundUp ? step : -step), 0), 1)
            AudioOutput.writeVolume(next)
            if next > 0 { AudioOutput.setMuted(false) }
            onVolume?(next, AudioOutput.isMuted())
            return true

        case .mute:
            let muted = !AudioOutput.isMuted()
            AudioOutput.setMuted(muted)
            onVolume?(AudioOutput.readVolume(), muted)
            return true

        case .brightnessUp, .brightnessDown:
            // Never swallow a brightness key on hardware where the change
            // cannot actually be applied — that would just break brightness.
            guard Brightness.isSupported else { return false }
            let current = Brightness.current()
            let next = min(max(current + (key == .brightnessUp ? step : -step), 0), 1)
            guard Brightness.set(next) else { return false }
            onBrightness?(next)
            return true
        }
    }
}
