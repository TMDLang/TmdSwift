import Foundation
import TmdSwift

public enum MIDIMessage: Equatable, Sendable {
    case trackName(String)
    case tempo(Double)
    case timeSignature(Beat)
    case endOfTrack
    case text(String)
    case customMeta(type: UInt8, data: Data)
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8)
    case programChange(channel: UInt8, program: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
}

public struct MIDIEvent: Equatable, Sendable {
    public var tick: UInt32
    public var message: MIDIMessage

    public init(tick: UInt32, message: MIDIMessage) {
        self.tick = tick
        self.message = message
    }
}

/// Encodes typed MIDI content into Standard MIDI File binary data.
public final class TmdMIDIEncoder {
    public static func encodeFile(tracks: [Data], ticksPerQuarter: UInt16) -> Data {
        let encodedTracks = tracks.prefix(Int(UInt16.max))
        let header =
            Data("MThd".utf8)
            + Data(UInt32(6).bigEndianBytes)
            + Data(UInt16(1).bigEndianBytes)
            + Data(UInt16(encodedTracks.count).bigEndianBytes)
            + Data(ticksPerQuarter.bigEndianBytes)
        return encodedTracks.reduce(into: header) { midi, track in
            midi.append(contentsOf: "MTrk".utf8)
            midi.append(contentsOf: UInt32(clamping: track.count).bigEndianBytes)
            midi.append(track)
        }
    }

    public static func encodeTrack(events: [MIDIEvent]) -> Data {
        var sorted = events.sorted { $0.tick < $1.tick }
        let lastTick = sorted.last?.tick ?? 0
        sorted.append(MIDIEvent(tick: lastTick, message: .endOfTrack))

        return sorted.reduce(into: (data: Data(), lastTick: UInt32(0))) { result, event in
            let delta = event.tick >= result.lastTick ? event.tick - result.lastTick : 0
            result.data.append(contentsOf: variableLengthQuantity(delta))
            result.data.append(event.message.encodedBytes)
            result.lastTick = event.tick
        }.data
    }

    fileprivate static func metaEvent(type: UInt8, data: Data) -> Data {
        Data([0xFF, type]) + Data(variableLengthQuantity(UInt32(clamping: data.count))) + data
    }

    fileprivate static func clampedUInt32(_ value: Double) -> UInt32 {
        guard value.isFinite else { return value.sign == .minus ? 0 : UInt32.max }
        return UInt32(min(max(0, value), Double(UInt32.max)))
    }

    private static func variableLengthQuantity(_ value: UInt32) -> [UInt8] {
        var buffer = [UInt8(value & 0x7F)]
        var value = value >> 7
        while value > 0 {
            buffer.append(UInt8((value & 0x7F) | 0x80))
            value >>= 7
        }
        return buffer.reversed()
    }
}

private extension MIDIMessage {
    var encodedBytes: Data {
        switch self {
        case .trackName(let name):
            return TmdMIDIEncoder.metaEvent(type: 0x03, data: Data(name.utf8))
        case .tempo(let bpm):
            let mpqn = TmdMIDIEncoder.clampedUInt32(60_000_000.0 / max(1, bpm))
            let data = Data([
                UInt8((mpqn >> 16) & 0xFF), UInt8((mpqn >> 8) & 0xFF), UInt8(mpqn & 0xFF),
            ])
            return TmdMIDIEncoder.metaEvent(type: 0x51, data: data)
        case .timeSignature(let beat):
            let denominator = UInt8(round(log2(Double(max(1, beat.noteValue)))))
            return TmdMIDIEncoder.metaEvent(
                type: 0x58, data: Data([UInt8(clamping: max(1, beat.count)), denominator, 24, 8]))
        case .endOfTrack:
            return TmdMIDIEncoder.metaEvent(type: 0x2F, data: Data())
        case .text(let text):
            return TmdMIDIEncoder.metaEvent(type: 0x01, data: Data(text.utf8))
        case .customMeta(let type, let data):
            return TmdMIDIEncoder.metaEvent(type: type, data: data)
        case .noteOn(let channel, let note, let velocity):
            return Data([0x90 | channel, note, velocity])
        case .noteOff(let channel, let note):
            return Data([0x80 | channel, note, 0])
        case .programChange(let channel, let program):
            return Data([0xC0 | channel, program])
        case .controlChange(let channel, let controller, let value):
            return Data([0xB0 | channel, controller, value])
        }
    }
}

extension FixedWidthInteger {
    fileprivate var bigEndianBytes: [UInt8] {
        var value = bigEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
