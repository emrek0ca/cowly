import Foundation
import SwiftUI

/// Parses the coding agents' local logs without re-reading them from scratch.
///
/// Claude Code transcripts grow to hundreds of megabytes across projects, so
/// every file is remembered by its size and only the bytes appended since the
/// last pass are parsed. A file that shrank (rotated or replaced) is re-read.
final class IncrementalLogReader: @unchecked Sendable {
    private struct Entry {
        var offset: UInt64
        /// Token totals bucketed by hour, so old hours can be dropped cheaply.
        var buckets: [Date: Int]
        var lastActivity: Date?
    }

    private var entries: [String: Entry] = [:]
    private let lock = NSLock()
    private let home = FileManager.default.homeDirectoryForCurrentUser

    // MARK: - Claude Code

    func claudeUsage(claudeBlockBudget: Int) -> AIUsage {
        let root = home.appendingPathComponent(".claude/projects", isDirectory: true)
        var usage = AIUsage(
            id: "claude", name: "Claude Code", symbol: "asterisk",
            tint: Color(red: 0.85, green: 0.52, blue: 0.33),
            isInstalled: FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path(percentEncoded: false))
        )
        guard usage.isInstalled else { return usage }

        let cutoff = Date.now.addingTimeInterval(-8 * 3600)
        let files = transcripts(in: root, modifiedAfter: cutoff)
        var lastActivity: Date?
        for file in files {
            if let stamp = ingestClaude(file: file) {
                lastActivity = max(lastActivity ?? stamp, stamp)
            }
        }

        // Claude's allowance runs in rolling five-hour blocks that start with
        // the first message of the block, rounded down to the hour.
        let blockStart = Self.currentBlockStart(from: allBuckets())
        let windowTokens = tokens(since: blockStart)
        let todayTokens = tokens(since: Calendar.current.startOfDay(for: .now))

        let budget = claudeBlockBudget
        usage.lastActivity = lastActivity
        usage.primary = AIUsage.Window(
            label: "5h block",
            usedFraction: budget > 0 ? min(Double(windowTokens) / Double(budget), 1) : nil,
            resetsAt: blockStart?.addingTimeInterval(5 * 3600),
            tokens: windowTokens
        )
        usage.secondary = AIUsage.Window(label: "Today", usedFraction: nil, resetsAt: nil, tokens: todayTokens)
        usage.note = budget > 0
            ? "Measured against the block budget you set in Settings. Includes cache reads."
            : "Claude Code stores no quota locally, so this is tokens actually spent (cache reads included). Set a block budget in Settings to see a percentage."
        return usage
    }

    private func transcripts(in root: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modified = values?.contentModificationDate, modified >= cutoff else { continue }
            files.append(url)
        }
        return files
    }

    /// Reads only the bytes appended since last time and returns the newest
    /// timestamp seen.
    @discardableResult
    private func ingestClaude(file: URL) -> Date? {
        let path = file.path(percentEncoded: false)
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0

        lock.lock()
        var entry = entries[path] ?? Entry(offset: 0, buckets: [:], lastActivity: nil)
        if size < entry.offset { entry = Entry(offset: 0, buckets: [:], lastActivity: nil) }
        let start = entry.offset
        lock.unlock()

        guard size > start else { return entry.lastActivity }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return entry.lastActivity }
        defer { try? handle.close() }
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return entry.lastActivity }

        var consumed = start
        var lastNewline = data.range(of: Data([0x0A]), options: .backwards)
        // Never consume a half-written trailing line.
        let usable: Data
        if let lastNewline {
            usable = data.subdata(in: data.startIndex..<lastNewline.upperBound)
            consumed += UInt64(usable.count)
        } else {
            return entry.lastActivity
        }
        lastNewline = nil

        var buckets = entry.buckets
        var newest = entry.lastActivity
        let decoder = JSONDecoder()

        usable.split(separator: 0x0A).forEach { slice in
            // Cheap pre-filter: most lines are tool output with no usage block.
            guard slice.count > 40, slice.range(of: Data("\"usage\"".utf8)) != nil else { return }
            guard let record = try? decoder.decode(ClaudeRecord.self, from: Data(slice)),
                  let usage = record.message?.usage,
                  let stamp = record.date else { return }
            let total = usage.input_tokens + usage.output_tokens
                + (usage.cache_creation_input_tokens ?? 0) + (usage.cache_read_input_tokens ?? 0)
            guard total > 0 else { return }
            let hour = stamp.hourBucket
            buckets[hour, default: 0] += total
            if newest == nil || stamp > newest! { newest = stamp }
        }

        lock.lock()
        entries[path] = Entry(offset: consumed, buckets: buckets, lastActivity: newest)
        lock.unlock()
        return newest
    }

    private func allBuckets() -> [Date: Int] {
        lock.lock()
        defer { lock.unlock() }
        var merged: [Date: Int] = [:]
        for entry in entries.values {
            for (hour, tokens) in entry.buckets { merged[hour, default: 0] += tokens }
        }
        return merged
    }

    private func tokens(since date: Date?) -> Int {
        guard let date else { return 0 }
        return allBuckets().filter { $0.key >= date.hourBucket }.values.reduce(0, +)
    }

    /// The start of the five-hour block we are currently inside.
    private static func currentBlockStart(from buckets: [Date: Int]) -> Date? {
        let active = buckets.filter { $0.value > 0 }.keys.sorted()
        guard var blockStart = active.first else { return nil }
        for hour in active {
            if hour.timeIntervalSince(blockStart) >= 5 * 3600 {
                blockStart = hour
            }
        }
        // A block that already expired means nothing is currently counting.
        guard Date.now.timeIntervalSince(blockStart) < 5 * 3600 else { return nil }
        return blockStart
    }

    private struct ClaudeRecord: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int
                let output_tokens: Int
                let cache_creation_input_tokens: Int?
                let cache_read_input_tokens: Int?
            }
            let usage: Usage?
        }
        let message: Message?
        let timestamp: String?

        var date: Date? {
            guard let timestamp else { return nil }
            // Fractional seconds are usual but not guaranteed.
            return ISO8601DateFormatter.cowlyInternet.date(from: timestamp)
                ?? ISO8601DateFormatter.cowlyPlain.date(from: timestamp)
        }
    }

    // MARK: - Codex

    /// Codex writes its real rate limits into the session log, so this is the
    /// only agent where the percentage is authoritative rather than derived.
    func codexUsage() -> AIUsage {
        let root = home.appendingPathComponent(".codex", isDirectory: true)
        var usage = AIUsage(
            id: "codex", name: "Codex", symbol: "chevron.left.forwardslash.chevron.right",
            tint: .white,
            isInstalled: FileManager.default.fileExists(atPath: root.path(percentEncoded: false))
        )
        guard usage.isInstalled else { return usage }

        guard let file = newestCodexSession(in: root.appendingPathComponent("sessions")) else {
            usage.note = "No Codex sessions yet."
            return usage
        }
        guard let payload = lastRateLimits(in: file) else {
            usage.note = "Codex has not reported limits in this session yet."
            return usage
        }

        usage.lastActivity = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        usage.primary = payload.primary.map(Self.window)
        usage.secondary = payload.secondary.map(Self.window)
        return usage
    }

    private static func window(_ limit: CodexLimit) -> AIUsage.Window {
        AIUsage.Window(
            label: limit.windowLabel,
            usedFraction: min(max(limit.used_percent / 100, 0), 1),
            resetsAt: limit.resets_at.map { Date(timeIntervalSince1970: $0) },
            tokens: nil
        )
    }

    private func newestCodexSession(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return nil }
        var newest: (URL, Date)?
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            else { continue }
            if newest == nil || modified > newest!.1 { newest = (url, modified) }
        }
        return newest?.0
    }

    /// Only the tail matters: limits are re-reported on every turn.
    private func lastRateLimits(in file: URL) -> CodexRateLimits? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let tailLength = 512 * 1024
        let offset = max(0, size - tailLength)
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.readToEnd() else { return nil }

        let decoder = JSONDecoder()
        var latest: CodexRateLimits?
        for slice in data.split(separator: 0x0A) {
            guard slice.range(of: Data("\"rate_limits\"".utf8)) != nil else { continue }
            guard let record = try? decoder.decode(CodexRecord.self, from: Data(slice)),
                  let limits = record.payload?.rate_limits else { continue }
            latest = limits
        }
        return latest
    }

    private struct CodexRecord: Decodable {
        struct Payload: Decodable { let rate_limits: CodexRateLimits? }
        let payload: Payload?
    }

    // MARK: - Presence only

    func simplePresence(id: String, name: String, symbol: String, directory: String, note: String) -> AIUsage {
        let url = home.appendingPathComponent(directory, isDirectory: true)
        let installed = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        var usage = AIUsage(
            id: id, name: name, symbol: symbol,
            tint: id == "gemini" ? Color(red: 0.40, green: 0.60, blue: 0.98) : Color(red: 0.55, green: 0.75, blue: 0.95),
            isInstalled: installed
        )
        usage.note = installed ? note : nil
        usage.lastActivity = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return usage
    }
}

struct CodexRateLimits: Decodable, Sendable {
    let primary: CodexLimit?
    let secondary: CodexLimit?
}

struct CodexLimit: Decodable, Sendable {
    let used_percent: Double
    let window_minutes: Int?
    let resets_at: Double?

    var windowLabel: String {
        guard let window_minutes else { return "Limit" }
        switch window_minutes {
        case ..<120: return "\(window_minutes)m window"
        case ..<2880: return "\(window_minutes / 60)h window"
        default: return "\(window_minutes / 1440)d window"
        }
    }
}

extension Date {
    /// Truncated to the hour, the bucket granularity used for token totals.
    var hourBucket: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: self)) ?? self
    }
}

extension ISO8601DateFormatter {
    // Only ever read from the reader's own serial parsing, never mutated.
    nonisolated(unsafe) static let cowlyInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) static let cowlyPlain = ISO8601DateFormatter()
}
