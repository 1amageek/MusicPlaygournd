import CoreAudio
import Foundation

public struct CueOutputDevice: Identifiable, Sendable, Equatable {
    public let id: AudioDeviceID
    public let name: String

    public static func available() throws -> [Self] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size))
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !ids.isEmpty else { return [] }
        try ids.withUnsafeMutableBytes { bytes in
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!))
        }
        var result: [Self] = []
        for id in ids {
            var alive: UInt32 = 0
            var aliveSize = UInt32(MemoryLayout<UInt32>.size)
            address.mSelector = kAudioDevicePropertyDeviceIsAlive
            try check(AudioObjectGetPropertyData(id, &address, 0, nil, &aliveSize, &alive))
            guard alive != 0 else { continue }
            address.mSelector = kAudioDevicePropertyStreamConfiguration
            address.mScope = kAudioDevicePropertyScopeOutput
            try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size))
            // CoreAudio owns the returned format; this scoped allocation is UI discovery only.
            let storage = UnsafeMutableRawPointer.allocate(byteCount: max(Int(size), MemoryLayout<AudioBufferList>.size), alignment: MemoryLayout<AudioBufferList>.alignment)
            defer { storage.deallocate() }
            try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage))
            let list = UnsafeMutableAudioBufferListPointer(storage.bindMemory(to: AudioBufferList.self, capacity: 1))
            guard list.reduce(0, { $0 + $1.mNumberChannels }) >= 2 else { address.mScope = kAudioObjectPropertyScopeGlobal; continue }
            address.mSelector = kAudioObjectPropertyName
            address.mScope = kAudioObjectPropertyScopeGlobal
            var name: Unmanaged<CFString>?
            size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name))
            guard let name else { throw PlaybackError.audioSetupFailed("Audio device has no name.") }
            result.append(Self(id: id, name: name.takeRetainedValue() as String))
        }
        return result
    }

    internal static func check(_ status: OSStatus) throws {
        guard status == noErr else { throw PlaybackError.audioSetupFailed("Headphone output failed (CoreAudio \(status)).") }
    }
}
