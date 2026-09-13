import AppKit
import Foundation

/// Best-effort bridge to the system-wide Now Playing service so browser and
/// third-party playback can show up too.
///
/// Recent macOS releases restrict this service to entitled apps. When that is
/// the case every call simply returns nothing and the AppleScript providers
/// carry the feature — nothing here is load-bearing.
final class MediaRemoteProvider: MediaProvider, @unchecked Sendable {
    let bundleID = "system.nowplaying"
    let displayName = "Now Playing"

    private typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    private typealias SendCommand = @convention(c) (Int, [String: Any]?) -> Bool

    private let handle: UnsafeMutableRawPointer?
    private let getInfo: GetInfo?
    private let sendCommand: SendCommand?

    private let lock = NSLock()
    private var latest: [String: Any] = [:]
    private var lastFetch: Date = .distantPast

    private(set) var isAvailable = false

    init() {
        handle = dlopen(
            "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
            RTLD_LAZY
        )
        let library = handle
        func sym<T>(_ name: String, as: T.Type) -> T? {
            guard let library, let pointer = dlsym(library, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }
        getInfo = sym("MRMediaRemoteGetNowPlayingInfo", as: GetInfo.self)
        sendCommand = sym("MRMediaRemoteSendCommand", as: SendCommand.self)
        isAvailable = getInfo != nil
    }

    var isRunning: Bool { isAvailable }

    func snapshot(currentArtworkKey: String) -> MediaSnapshot? {
        guard let getInfo else { return nil }
        // The callback is asynchronous, so we read the previous answer and
        // immediately request the next one. At a 1 Hz poll that is invisible.
        if Date.now.timeIntervalSince(lastFetch) > 0.4 {
            lastFetch = .now
            getInfo(DispatchQueue.global(qos: .userInitiated)) { [weak self] info in
                guard let self else { return }
                self.lock.lock()
                self.latest = info
                self.lock.unlock()
            }
        }

        lock.lock()
        let info = latest
        lock.unlock()
        guard !info.isEmpty else { return nil }

        let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        guard !title.isEmpty else { return nil }
        let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
        let rate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
        var elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        if let stamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date, rate > 0 {
            elapsed += Date.now.timeIntervalSince(stamp)
        }
        let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        let key = "\(title)|\(artist)|\(artworkData?.count ?? 0)"

        return MediaSnapshot(
            title: title,
            artist: artist.isEmpty ? "—" : artist,
            album: album,
            isPlaying: rate > 0,
            duration: duration,
            elapsed: min(elapsed, duration > 0 ? duration : elapsed),
            appName: displayName,
            bundleID: bundleID,
            artworkKey: key,
            artwork: artworkData.flatMap(NSImage.init(data:))
        )
    }

    func send(_ command: MediaCommand) {
        guard let sendCommand else { return }
        // Values from MRCommand; stable across releases.
        switch command {
        case .playPause: _ = sendCommand(2, nil)
        case .next: _ = sendCommand(4, nil)
        case .previous: _ = sendCommand(5, nil)
        case .seek(let time):
            _ = sendCommand(25, ["kMRMediaRemoteOptionPlaybackPosition": time])
        }
    }

    deinit { if let handle { dlclose(handle) } }
}
