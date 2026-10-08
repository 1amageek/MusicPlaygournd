import CoreMIDI
import Darwin
import Foundation
import Synchronization
@testable import MusicPlayground

final class MIDIProbeCapture: Sendable {
    let words = Mutex<[UInt32]>([])
}

private func captureProbe(_ context: UnsafeMutableRawPointer?, _ time: MIDITimeStamp, _ message: MIDIUniversalMessage) {
    guard let context else { return }
    let capture = Unmanaged<MIDIProbeCapture>.fromOpaque(context).takeUnretainedValue()
    let word: UInt32
    if message.type == .channelVoice1 {
        let voice = message.channelVoice1
        word = 0x20000000 | ((voice.status.rawValue << 4) | UInt32(voice.channel)) << 16
            | UInt32(voice.note.number) << 8 | UInt32(voice.note.velocity)
    } else { word = message.unknown.words.0 }
    capture.words.withLock { if $0.count < 4096 { $0.append(word) } }
}

@MainActor
final class NativeMIDIProbe {
    private var client: MIDIClientRef = 0
    private var source: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0
    let capture = MIDIProbeCapture()
    private let midiProtocol = MIDIProtocolID(rawValue: 1)!
    init() throws {
        try check(MIDIClientCreateWithBlock("iPad parity probe" as CFString, &client, nil))
        do {
            try check(MIDISourceCreateWithProtocol(client, "Parity input" as CFString, midiProtocol, &source))
            let capture = capture
            try check(MIDIDestinationCreateWithProtocol(client, "Parity output" as CFString, midiProtocol, &destination) { @Sendable list, _ in
                // CoreMIDI owns list during this callback. The closure retains the capture owner;
                // the visitor borrows its pointer only until ForEachEvent returns.
                MIDIEventListForEachEvent(list, captureProbe, Unmanaged.passUnretained(capture).toOpaque())
            })
        } catch { close(); throw error }
    }
    var input: MIDIEndpointID { get throws { try id(source) } }
    var output: MIDIEndpointID { get throws { try id(destination) } }
    func inject(_ words: [UInt32], spacing: UInt64 = 0) throws {
        let now = mach_absolute_time()
        for (index, word) in words.enumerated() {
            var list = MIDIEventList(), value = word
            let packet = MIDIEventListInit(&list, midiProtocol)
            // One UMP word fits the stack-owned list's packet storage; the fixed SDK
            // exposes a nonoptional next-packet pointer, not a nullable failure result.
            _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet,
                now + UInt64(index) * spacing, 1, &value)
            try check(MIDIReceivedEventList(source, &list))
        }
    }
    func close() {
        if source != 0 { MIDIEndpointDispose(source); source = 0 }
        if destination != 0 { MIDIEndpointDispose(destination); destination = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }
    private func id(_ endpoint: MIDIEndpointRef) throws -> MIDIEndpointID {
        var raw: MIDIUniqueID = 0
        try check(MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &raw))
        return try MIDIEndpointID(rawValue: raw)
    }
    private func check(_ status: OSStatus) throws { if status != noErr { throw MIDIError.coreMIDIStatus(status) } }
}
