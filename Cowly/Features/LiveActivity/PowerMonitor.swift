import AppKit
import SwiftUI
import Foundation
import IOKit.ps
import Observation

struct BatteryState: Equatable, Sendable {
    var percentage: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var isPresent: Bool
    var minutesRemaining: Int?

    static let unknown = BatteryState(
        percentage: 100, isCharging: false, isPluggedIn: true, isPresent: false, minutesRemaining: nil
    )

    var symbol: String {
        guard isPresent else { return "powerplug.fill" }
        if isCharging { return "battery.100.bolt" }
        switch percentage {
        case ..<10: return "battery.0"
        case ..<35: return "battery.25"
        case ..<60: return "battery.50"
        case ..<85: return "battery.75"
        default: return "battery.100"
        }
    }

    var tint: Color {
        if isCharging { return Theme.Palette.positive }
        switch percentage {
        case ..<10: return Theme.Palette.danger
        case ..<25: return Theme.Palette.warning
        default: return .white
        }
    }

    var timeLabel: String? {
        guard let minutesRemaining, minutesRemaining > 0 else { return nil }
        let h = minutesRemaining / 60
        let m = minutesRemaining % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

/// Battery percentage plus the plug-in / low-battery live activities.
@MainActor
@Observable
final class PowerMonitor {
    static let shared = PowerMonitor()

    private(set) var battery: BatteryState = .unknown
    private var timer: Timer?
    private var lastPluggedIn: Bool?
    private var warnedAt: Set<Int> = []

    private init() {}

    func start() {
        guard timer == nil else { return }
        battery = Self.read()
        lastPluggedIn = battery.isPluggedIn
        let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let next = Self.read()
        defer { battery = next }
        guard Preferences.shared.batteryAlerts, next.isPresent else { return }

        if let last = lastPluggedIn, last != next.isPluggedIn {
            NotchViewModel.shared.present(
                LiveActivity(
                    style: .expanded,
                    leadingSymbol: next.isPluggedIn ? "bolt.fill" : "battery.50",
                    leadingTint: next.isPluggedIn ? Theme.Palette.positive : .white,
                    title: next.isPluggedIn ? "Charging" : "On battery",
                    subtitle: next.timeLabel.map { next.isPluggedIn ? "\($0) to full" : "\($0) left" },
                    progress: Double(next.percentage) / 100,
                    trailingText: "\(next.percentage)%",
                    duration: 3.0
                )
            )
        }
        lastPluggedIn = next.isPluggedIn

        // One warning per threshold per discharge cycle.
        if next.isPluggedIn {
            warnedAt.removeAll()
        } else {
            for threshold in [20, 10, 5] where next.percentage <= threshold && !warnedAt.contains(threshold) {
                warnedAt.insert(threshold)
                NotchViewModel.shared.present(
                    LiveActivity(
                        style: .expanded,
                        leadingSymbol: "battery.25",
                        leadingTint: Theme.Palette.danger,
                        title: "Battery low",
                        subtitle: "Tap to turn on Low Power Mode",
                        progress: Double(next.percentage) / 100,
                        trailingText: "\(next.percentage)%",
                        duration: 6
                    )
                )
                break
            }
        }
    }

    static func read() -> BatteryState {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unknown
        }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let type = info[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType else { continue }
            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let state = info[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue
            let remaining = charging
                ? info[kIOPSTimeToFullChargeKey] as? Int
                : info[kIOPSTimeToEmptyKey] as? Int
            return BatteryState(
                percentage: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0,
                isCharging: charging,
                isPluggedIn: plugged,
                isPresent: true,
                minutesRemaining: (remaining ?? -1) > 0 ? remaining : nil
            )
        }
        return .unknown
    }

    /// Opens the Battery pane; toggling Low Power Mode itself needs admin rights.
    func openLowPowerSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            NSWorkspace.shared.open(url)
        }
    }
}
