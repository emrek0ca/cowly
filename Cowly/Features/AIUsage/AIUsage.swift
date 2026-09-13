import Foundation
import Observation
import SwiftUI

/// What one coding agent reports about how much of its allowance is gone.
struct AIUsage: Identifiable, Sendable {
    struct Window: Sendable {
        var label: String
        /// 0...1 when the tool actually reports a quota.
        var usedFraction: Double?
        var resetsAt: Date?
        /// Set when we derived the number from local logs rather than a quota.
        var tokens: Int?

        var resetLabel: String? {
            guard let resetsAt else { return nil }
            let remaining = resetsAt.timeIntervalSinceNow
            guard remaining > 0 else { return "resetting" }
            let hours = Int(remaining) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
        }
    }

    let id: String
    var name: String
    var symbol: String
    var tint: Color
    var isInstalled: Bool
    var primary: Window?
    var secondary: Window?
    /// Explains the number when it is not a quota, or why there is none.
    var note: String?
    var lastActivity: Date?

    var headline: String {
        guard isInstalled else { return "Not installed" }
        if let fraction = primary?.usedFraction {
            return "\(Int((1 - fraction) * 100))% left"
        }
        if let tokens = primary?.tokens {
            return tokens.compactTokenLabel
        }
        return "No local data"
    }

    var barFraction: Double? { primary?.usedFraction }
}

extension Int {
    /// 1234567 -> "1.2M", 45300 -> "45.3K"
    var compactTokenLabel: String {
        switch self {
        case 1_000_000...: String(format: "%.1fM", Double(self) / 1_000_000)
        case 1_000...: String(format: "%.1fK", Double(self) / 1_000)
        default: "\(self)"
        }
    }
}

/// Reads the coding agents' own local logs to show how much of each allowance
/// is left.
///
/// Codex writes real quota numbers into its session log, so those are exact.
/// Claude Code does not record a quota locally, so its figure is the tokens it
/// has actually spent in the current five-hour block, derived from the session
/// transcripts. Gemini and Cursor keep nothing usable on disk, so they are only
/// reported as present.
@MainActor
@Observable
final class AIUsageMonitor {
    static let shared = AIUsageMonitor()

    private(set) var tools: [AIUsage] = []
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    private var timer: Timer?
    private let reader = IncrementalLogReader()

    private init() {
        tools = Self.placeholders()
    }

    var anyInstalled: Bool { tools.contains(where: \.isInstalled) }

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let reader = self.reader
        // Everything the parse needs is read here, on the main actor. Reaching
        // back for preferences from the background queue used to trap.
        let budget = Preferences.shared.claudeBlockBudget
        Task.detached(priority: .utility) {
            let claude = reader.claudeUsage(claudeBlockBudget: budget)
            let codex = reader.codexUsage()
            let gemini = reader.simplePresence(
                id: "gemini", name: "Gemini CLI", symbol: "sparkle",
                directory: ".gemini",
                note: "Gemini keeps no usage figures on this Mac."
            )
            let cursor = reader.simplePresence(
                id: "cursor", name: "Cursor", symbol: "cursorarrow.rays",
                directory: ".cursor",
                note: "Cursor reports usage in-app only."
            )
            let result = [claude, codex, gemini, cursor]
            await MainActor.run {
                AIUsageMonitor.shared.apply(result)
            }
        }
    }

    private func apply(_ result: [AIUsage]) {
        tools = result
        lastRefresh = .now
        isRefreshing = false
    }

    private static func placeholders() -> [AIUsage] {
        [
            AIUsage(id: "claude", name: "Claude Code", symbol: "asterisk", tint: Color(red: 0.85, green: 0.52, blue: 0.33), isInstalled: false),
            AIUsage(id: "codex", name: "Codex", symbol: "chevron.left.forwardslash.chevron.right", tint: .white, isInstalled: false),
            AIUsage(id: "gemini", name: "Gemini CLI", symbol: "sparkle", tint: Color(red: 0.40, green: 0.60, blue: 0.98), isInstalled: false),
            AIUsage(id: "cursor", name: "Cursor", symbol: "cursorarrow.rays", tint: Color(red: 0.55, green: 0.75, blue: 0.95), isInstalled: false)
        ]
    }
}
