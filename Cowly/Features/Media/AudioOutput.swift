import AppKit
import AudioToolbox
import CoreAudio
import Observation

/// 'vmvc' — the virtual main volume the Sound pane drives.
private let virtualMainVolume = AudioObjectPropertySelector(0x766D7663)

struct AudioDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
    let isDefault: Bool

    var symbol: String {
        let lower = name.lowercased()
        if lower.contains("airpod") { return "airpods" }
        if lower.contains("headphone") || lower.contains("beats") { return "headphones" }
        if lower.contains("display") || lower.contains("monitor") { return "display" }
        if lower.contains("homepod") || lower.contains("tv") { return "hifispeaker.fill" }
        if lower.contains("bluetooth") { return "hifispeaker" }
        return "speaker.wave.2.fill"
    }
}

/// System audio: which device is playing, what else is available, and volume.
@MainActor
@Observable
final class AudioOutput {
    static let shared = AudioOutput()

    private(set) var devices: [AudioDevice] = []
    private(set) var currentName: String = "—"
    var volume: Float = 0.5

    private var listenerInstalled = false
    private var suppressWrite = false

    private init() { refresh() }

    func start() {
        refresh()
        installListeners()
    }

    func refresh() {
        devices = Self.outputDevices()
        currentName = devices.first(where: \.isDefault)?.name ?? "—"
        suppressWrite = true
        volume = Self.readVolume()
        suppressWrite = false
    }

    func select(_ device: AudioDevice) {
        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID
        )
        if status == noErr {
            Haptics.tap(.levelChange)
            refresh()
        }
    }

    func setVolume(_ value: Float) {
        guard !suppressWrite else { return }
        Self.writeVolume(value)
    }

    // MARK: - CoreAudio plumbing

    private static func outputDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        let defaultID = defaultOutputDeviceID()
        return ids.compactMap { id in
            guard hasOutputStreams(id), let name = deviceName(id) else { return nil }
            return AudioDevice(id: id, name: name, isDefault: id == defaultID)
        }
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr else { return nil }
        let value = name as String
        return value.isEmpty ? nil : value
    }

    static func readVolume() -> Float {
        let id = defaultOutputDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: virtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(id, &address),
              AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    static func isMuted() -> Bool {
        let id = defaultOutputDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(id, &address),
              AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return false }
        return value == 1
    }

    static func setMuted(_ muted: Bool) {
        let id = defaultOutputDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    static func writeVolume(_ newValue: Float) {
        let id = defaultOutputDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: virtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float32(min(max(newValue, 0), 1))
        guard AudioObjectHasProperty(id, &address) else { return }
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private func installListeners() {
        guard !listenerInstalled else { return }
        listenerInstalled = true
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { _, _ in
            MainActor.assumeIsolated { AudioOutput.shared.refresh() }
        }
    }
}
