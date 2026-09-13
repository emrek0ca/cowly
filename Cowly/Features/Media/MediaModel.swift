import AppKit
import SwiftUI

/// One frame of "what is playing right now", whoever is playing it.
struct MediaSnapshot: Equatable, Sendable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: TimeInterval
    var elapsed: TimeInterval
    var appName: String
    var bundleID: String
    var artworkKey: String
    /// Not part of equality: artwork is compared by `artworkKey` instead.
    var artwork: NSImage?

    static let idle = MediaSnapshot(
        title: "Not Playing", artist: "—", album: "", isPlaying: false,
        duration: 0, elapsed: 0, appName: "", bundleID: "", artworkKey: "", artwork: nil
    )

    var isIdle: Bool { bundleID.isEmpty }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var remaining: TimeInterval { max(0, duration - elapsed) }

    static func == (lhs: MediaSnapshot, rhs: MediaSnapshot) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying && lhs.bundleID == rhs.bundleID
            && lhs.artworkKey == rhs.artworkKey
            && abs(lhs.duration - rhs.duration) < 0.5
            && abs(lhs.elapsed - rhs.elapsed) < 0.5
    }
}

enum MediaCommand: Sendable {
    case playPause
    case next
    case previous
    case seek(TimeInterval)
}

/// Anything that can report and control playback.
protocol MediaProvider: Sendable {
    var bundleID: String { get }
    var displayName: String { get }
    var isRunning: Bool { get }
    /// Pass the artwork key already on screen so providers can skip the
    /// expensive artwork read when the track has not changed.
    func snapshot(currentArtworkKey: String) -> MediaSnapshot?
    func send(_ command: MediaCommand)
}
