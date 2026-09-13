import AppKit
import Foundation
import IOKit.pwr_mgt
import Observation
import SwiftUI
import UserNotifications

/// Pomodoro: focus / short break / long break, with the ring living in the notch.
@MainActor
@Observable
final class PomodoroEngine {
    static let shared = PomodoroEngine()

    enum Phase: String, Sendable {
        case focus, shortBreak, longBreak

        var label: String {
            switch self {
            case .focus: "Focus"
            case .shortBreak: "Short break"
            case .longBreak: "Long break"
            }
        }

        var tint: Color {
            switch self {
            case .focus: .red
            case .shortBreak: Theme.Palette.positive
            case .longBreak: Theme.Palette.accent
            }
        }
    }

    var focusMinutes: Int {
        get { Preferences.shared.pomodoroFocus }
        set { Preferences.shared.pomodoroFocus = newValue }
    }
    var shortBreakMinutes: Int {
        get { Preferences.shared.pomodoroShortBreak }
        set { Preferences.shared.pomodoroShortBreak = newValue }
    }
    var longBreakMinutes: Int {
        get { Preferences.shared.pomodoroLongBreak }
        set { Preferences.shared.pomodoroLongBreak = newValue }
    }
    var roundsBeforeLongBreak: Int {
        get { Preferences.shared.pomodoroRounds }
        set { Preferences.shared.pomodoroRounds = newValue }
    }

    private(set) var phase: Phase = .focus
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var isRunning = false
    private(set) var completedRounds = 0

    private var timer: Timer?

    private init() { remaining = Double(Preferences.shared.pomodoroFocus) * 60 }

    var total: TimeInterval {
        switch phase {
        case .focus: Double(focusMinutes) * 60
        case .shortBreak: Double(shortBreakMinutes) * 60
        case .longBreak: Double(longBreakMinutes) * 60
        }
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return 1 - (remaining / total)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Haptics.tap(.levelChange)
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        remaining = total
    }

    func skip() {
        advancePhase(completed: false)
    }

    private func tick() {
        remaining = max(0, remaining - 1)
        if remaining <= 0 { advancePhase(completed: true) }
    }

    private func advancePhase(completed: Bool) {
        pause()
        if phase == .focus {
            if completed { completedRounds += 1 }
            phase = completedRounds % roundsBeforeLongBreak == 0 && completedRounds > 0 ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
        remaining = total
        if completed {
            NSSound(named: "Glass")?.play()
            NotchViewModel.shared.present(
                LiveActivity(
                    style: .expanded, leadingSymbol: "timer", leadingTint: phase.tint,
                    title: "\(phase.label) time", subtitle: "\(completedRounds) rounds done",
                    duration: 5
                )
            )
        }
    }

}

/// High Alert: hold a power assertion so the Mac (and optionally the display)
/// stays awake.
@MainActor
@Observable
final class HighAlertEngine {
    static let shared = HighAlertEngine()

    private(set) var isActive = false
    private(set) var startedAt: Date?
    var keepDisplayAwake = true
    /// 0 means "until I turn it off".
    var autoOffMinutes = 0

    private var assertionID: IOPMAssertionID = 0
    private var autoOffTask: Task<Void, Never>?

    private init() {}

    var elapsedLabel: String {
        guard let startedAt else { return "Off" }
        return Date.now.timeIntervalSince(startedAt).clockLabel
    }

    func toggle() { isActive ? deactivate() : activate() }

    func activate() {
        guard !isActive else { return }
        let type = keepDisplayAwake
            ? kIOPMAssertionTypeNoDisplaySleep as CFString
            : kIOPMAssertionTypeNoIdleSleep as CFString
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type, IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Cowly High Alert" as CFString, &id
        )
        guard result == kIOReturnSuccess else {
            log.error("High Alert assertion failed: \(result)")
            return
        }
        assertionID = id
        isActive = true
        startedAt = .now
        Haptics.tap(.levelChange)
        if autoOffMinutes > 0 {
            autoOffTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(self?.autoOffMinutes ?? 0) * 60))
                guard !Task.isCancelled else { return }
                self?.deactivate()
            }
        }
    }

    func deactivate() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
        startedAt = nil
        autoOffTask?.cancel()
        autoOffTask = nil
        Haptics.tap(.generic)
    }
}

/// Countdown timers that keep ticking in the closed notch.
@MainActor
@Observable
final class TimerEngine {
    static let shared = TimerEngine()

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        var label: String
        var total: TimeInterval
        var endsAt: Date
        var isPaused = false
        var pausedRemaining: TimeInterval = 0

        var remaining: TimeInterval {
            isPaused ? pausedRemaining : max(0, endsAt.timeIntervalSinceNow)
        }

        var progress: Double {
            guard total > 0 else { return 0 }
            return 1 - (remaining / total)
        }
    }

    private(set) var entries: [Entry] = []
    private var timer: Timer?

    private init() {}

    func add(minutes: Int, label: String? = nil) {
        add(seconds: TimeInterval(minutes * 60), label: label ?? "\(minutes) min")
    }

    func add(seconds: TimeInterval, label: String) {
        let entry = Entry(label: label, total: seconds, endsAt: Date.now.addingTimeInterval(seconds))
        entries.append(entry)
        Haptics.tap(.levelChange)
        ensureTicking()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        if entries.isEmpty { stopTicking() }
    }

    func togglePause(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        if entries[index].isPaused {
            entries[index].endsAt = Date.now.addingTimeInterval(entries[index].pausedRemaining)
            entries[index].isPaused = false
        } else {
            entries[index].pausedRemaining = entries[index].remaining
            entries[index].isPaused = true
        }
    }

    private func ensureTicking() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let finished = entries.filter { !$0.isPaused && $0.remaining <= 0 }
        for entry in finished {
            NSSound(named: "Glass")?.play()
            NotchViewModel.shared.present(
                LiveActivity(
                    style: .expanded, leadingSymbol: "hourglass",
                    leadingTint: Theme.Palette.warning, title: entry.label,
                    subtitle: "Timer finished", duration: 6
                )
            )
            entries.removeAll { $0.id == entry.id }
        }
        if entries.isEmpty { stopTicking() }
        // Touch the array so SwiftUI recomputes the countdown labels.
        entries = entries
    }

    /// Timer the closed shelf should surface, if any.
    var soonest: Entry? {
        entries.filter { !$0.isPaused }.min { $0.remaining < $1.remaining }
    }
}
