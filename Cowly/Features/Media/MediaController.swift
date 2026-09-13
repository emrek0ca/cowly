import AppKit
import Observation
import SwiftUI

/// Polls every provider, picks the one that is actually playing, and keeps a
/// smooth local clock between polls so the scrubber never stutters.
@MainActor
@Observable
final class MediaController {
    static let shared = MediaController()

    private(set) var now: MediaSnapshot = .idle
    private(set) var artworkTint: Color?
    /// Position the user is dragging, if any. Takes over the UI while scrubbing.
    var scrubPosition: Double?

    private let runner: ScriptRunner
    private let providers: [any MediaProvider]

    private var pollTimer: Timer?
    private var tickTimer: Timer?
    private var activeProvider: (any MediaProvider)?
    private var isRefreshing = false

    private init() {
        let runner = ScriptRunner()
        self.runner = runner
        providers = [
            AppleMusicProvider(runner: runner),
            SpotifyProvider(runner: runner),
            MediaRemoteProvider()
        ]
    }

    func start() {
        guard pollTimer == nil else { return }
        refresh()
        let poll = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        poll.tolerance = 0.3
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        // Between polls the elapsed time is advanced locally at 4 Hz.
        let tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick.tolerance = 0.1
        RunLoop.main.add(tick, forMode: .common)
        tickTimer = tick
    }

    func stop() {
        pollTimer?.invalidate(); pollTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
    }

    // MARK: - Polling

    private func candidates() -> [any MediaProvider] {
        switch Preferences.shared.mediaSource {
        case .automatic: return providers
        case .appleMusic: return providers.filter { $0.bundleID == "com.apple.Music" }
        case .spotify: return providers.filter { $0.bundleID == "com.spotify.client" }
        }
    }

    /// Apple Events are synchronous and can block for a hundred milliseconds or
    /// more. Polling them on the main thread made the whole shelf stutter, so
    /// every query runs on a serial background queue and only the finished
    /// snapshot crosses back.
    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let providers = candidates()
        let wantsArtworkFor = now.artworkKey

        Self.queue.async { [weak self] in
            var best: (any MediaProvider)?
            var bestSnapshot: MediaSnapshot?

            for provider in providers {
                guard provider.isRunning, let snapshot = provider.snapshot(currentArtworkKey: wantsArtworkFor) else { continue }
                // A provider that is actually playing always wins over a paused one.
                if snapshot.isPlaying {
                    best = provider
                    bestSnapshot = snapshot
                    break
                }
                if bestSnapshot == nil {
                    best = provider
                    bestSnapshot = snapshot
                }
            }

            nonisolated(unsafe) let provider = best
            nonisolated(unsafe) let snapshot = bestSnapshot
            Task { @MainActor [weak self] in
                self?.apply(provider: provider, snapshot: snapshot)
            }
        }
    }

    private func apply(provider: (any MediaProvider)?, snapshot: MediaSnapshot?) {
        isRefreshing = false
        activeProvider = provider
        var next = snapshot ?? .idle
        let trackChanged = next.artworkKey != now.artworkKey
        // Artwork is only re-read when the track changes, so carry it forward.
        if !trackChanged, next.artwork == nil { next.artwork = now.artwork }

        if next != now {
            withAnimation(Motion.content) { now = next }
        }
        if trackChanged {
            artworkTint = Preferences.shared.tintFromArtwork ? Color.dominant(from: next.artwork) : nil
        }
    }

    private nonisolated static let queue = DispatchQueue(label: "dev.emrekoca.Cowly.media", qos: .utility)

    private func tick() {
        guard now.isPlaying, scrubPosition == nil, now.duration > 0 else { return }
        now.elapsed = min(now.elapsed + 0.25, now.duration)
    }

    // MARK: - Commands

    func playPause() {
        guard activeProvider != nil else { return }
        Haptics.tap(.generic)
        now.isPlaying.toggle()
        send(.playPause)
    }

    func next() {
        Haptics.tap(.generic)
        send(.next)
    }

    func previous() {
        Haptics.tap(.generic)
        send(.previous)
    }

    private func send(_ command: MediaCommand) {
        guard let activeProvider else { return }
        nonisolated(unsafe) let provider = activeProvider
        Self.queue.async { provider.send(command) }
        scheduleConfirm()
    }

    func beginScrub(_ progress: Double) {
        scrubPosition = progress
    }

    func commitScrub(_ progress: Double) {
        defer { scrubPosition = nil }
        guard now.duration > 0 else { return }
        let target = progress * now.duration
        now.elapsed = target
        send(.seek(target))
    }

    /// Re-reads state shortly after a command so the UI settles on the truth.
    private func scheduleConfirm() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            self?.refresh()
        }
    }

    var displayedProgress: Double { scrubPosition ?? now.progress }

    var displayedElapsed: TimeInterval {
        guard let scrubPosition else { return now.elapsed }
        return scrubPosition * now.duration
    }
}
