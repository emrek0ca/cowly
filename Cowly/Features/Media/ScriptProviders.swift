import AppKit
import Foundation

/// Thin wrapper around NSAppleScript that keeps compiled scripts warm and never
/// throws at the call site — a missing app just means "nothing playing".
final class ScriptRunner: @unchecked Sendable {
    private var cache: [String: NSAppleScript] = [:]
    private let lock = NSLock()

    func run(_ source: String) -> NSAppleEventDescriptor? {
        lock.lock()
        let script: NSAppleScript?
        if let cached = cache[source] {
            script = cached
        } else if let made = NSAppleScript(source: source) {
            cache[source] = made
            script = made
        } else {
            script = nil
        }
        lock.unlock()
        guard let script else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error, let code = error[NSAppleScript.errorNumber] as? Int, code != -1728 {
            // -1728 just means "no current track"; anything else is worth a line.
            log.debug("AppleScript error \(code): \(String(describing: error[NSAppleScript.errorMessage]))")
            return nil
        }
        return result
    }

    func string(_ source: String) -> String? {
        guard let value = run(source)?.stringValue, !value.isEmpty, value != "missing value" else { return nil }
        return value
    }
}

/// Apple Music / iTunes over Apple Events.
struct AppleMusicProvider: MediaProvider {
    let bundleID = "com.apple.Music"
    let displayName = "Music"
    private let runner: ScriptRunner

    init(runner: ScriptRunner) { self.runner = runner }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    func snapshot(currentArtworkKey: String) -> MediaSnapshot? {
        guard isRunning else { return nil }
        let script = """
        tell application "Music"
            if not (exists current track) then return "none"
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to duration of current track
            set p to player position
            set s to (player state as text)
            set pid to (database ID of current track) as text
            return t & "\\n" & a & "\\n" & al & "\\n" & d & "\\n" & p & "\\n" & s & "\\n" & pid
        end tell
        """
        guard let raw = runner.string(script), raw != "none" else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 7 else { return nil }
        let key = "music:\(parts[6])"
        // Reading artwork means shipping a whole JPEG over Apple Events.
        let art = key == currentArtworkKey ? nil : artwork()
        return MediaSnapshot(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: parts[5] == "playing",
            duration: Double(parts[3]) ?? 0,
            elapsed: Double(parts[4]) ?? 0,
            appName: displayName,
            bundleID: bundleID,
            artworkKey: key,
            artwork: art
        )
    }

    private func artwork() -> NSImage? {
        let script = """
        tell application "Music"
            if not (exists current track) then return missing value
            if (count of artworks of current track) is 0 then return missing value
            return data of artwork 1 of current track
        end tell
        """
        guard let descriptor = runner.run(script) else { return nil }
        if let data = descriptor.data as Data?, data.count > 128 {
            return NSImage(data: data)
        }
        return nil
    }

    func send(_ command: MediaCommand) {
        let body: String
        switch command {
        case .playPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "back track"
        case .seek(let time): body = "set player position to \(time)"
        }
        _ = runner.run("tell application \"Music\" to \(body)")
    }
}

/// Spotify over Apple Events.
struct SpotifyProvider: MediaProvider {
    let bundleID = "com.spotify.client"
    let displayName = "Spotify"
    private let runner: ScriptRunner

    init(runner: ScriptRunner) { self.runner = runner }

    var isRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    func snapshot(currentArtworkKey: String) -> MediaSnapshot? {
        guard isRunning else { return nil }
        let script = """
        tell application "Spotify"
            if player state is stopped then return "none"
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set d to (duration of current track) / 1000
            set p to player position
            set s to (player state as text)
            set u to artwork url of current track
            return t & "\\n" & a & "\\n" & al & "\\n" & d & "\\n" & p & "\\n" & s & "\\n" & u
        end tell
        """
        guard let raw = runner.string(script), raw != "none" else { return nil }
        let parts = raw.components(separatedBy: "\n")
        guard parts.count >= 7 else { return nil }
        let artURL = parts[6]
        return MediaSnapshot(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            isPlaying: parts[5] == "playing",
            duration: Double(parts[3]) ?? 0,
            elapsed: Double(parts[4]) ?? 0,
            appName: displayName,
            bundleID: bundleID,
            artworkKey: artURL,
            artwork: ArtworkCache.shared.image(for: artURL)
        )
    }

    func send(_ command: MediaCommand) {
        let body: String
        switch command {
        case .playPause: body = "playpause"
        case .next: body = "next track"
        case .previous: body = "previous track"
        case .seek(let time): body = "set player position to \(time)"
        }
        _ = runner.run("tell application \"Spotify\" to \(body)")
    }
}

/// Downloads and remembers remote cover art so the shelf never blocks on it.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()
    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let lock = NSLock()

    func image(for urlString: String) -> NSImage? {
        guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
        lock.lock()
        if let hit = cache[urlString] { lock.unlock(); return hit }
        let alreadyFetching = inFlight.contains(urlString)
        if !alreadyFetching { inFlight.insert(urlString) }
        lock.unlock()
        guard !alreadyFetching else { return nil }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            let image = data.flatMap(NSImage.init(data:))
            self.lock.lock()
            self.inFlight.remove(urlString)
            if let image { self.cache[urlString] = image }
            self.lock.unlock()
        }.resume()
        return nil
    }
}
