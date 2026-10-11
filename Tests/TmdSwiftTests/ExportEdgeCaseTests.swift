import Foundation
import Testing
import TmdAudio
import TmdMIDI

@testable import TmdSwift

@Suite("MIDI and WAV Export Edge Cases")
struct ExportEdgeCaseTests {

    private func makeSheet() throws -> Sheet {
        try TmdParser.parseThrowing(string: """
            ::SCORE::
            ** Edge Case **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
            }
            -> A ->#
            """)
    }

    @Test("WAV rendering rejects non-finite and invalid sample rates")
    func rejectsInvalidSampleRates() throws {
        let sheet = try makeSheet()

        #expect(throws: TmdAudioError.self) {
            _ = try TmdWAVRenderer.renderWAV(from: sheet, sampleRate: .nan)
        }
        #expect(throws: TmdAudioError.self) {
            _ = try TmdWAVRenderer.renderWAV(from: sheet, sampleRate: 7_999)
        }
    }

    @Test("MIDI file encoding never writes a zero division")
    func normalizesZeroTicksPerQuarter() {
        let data = TmdMIDIEncoder.encodeFile(
            tracks: [TmdMIDIEncoder.encodeTrack(events: [])], ticksPerQuarter: 0)
        let division = UInt16(data[12]) << 8 | UInt16(data[13])
        #expect(division == TmdMIDIGenerator.defaultTicksPerQuarterNote)
    }

    @Test("MIDI encoding emits note-off before note-on at the same tick")
    func ordersSameTickEventsDeterministically() {
        let data = TmdMIDIEncoder.encodeTrack(events: [
            MIDIEvent(tick: 480, message: .noteOn(channel: 0, note: 60, velocity: 80)),
            MIDIEvent(tick: 480, message: .noteOff(channel: 0, note: 60)),
        ])
        let noteOffIndex = data.firstIndex(of: 0x80)
        let noteOnIndex = data.firstIndex(of: 0x90)
        #expect(noteOffIndex != nil)
        #expect(noteOnIndex != nil)
        #expect(noteOnIndex! > noteOffIndex!)
    }

    @Test("MIDI channel allocation rejects distinct programs after melodic channels are exhausted")
    func rejectsMelodicChannelExhaustion() throws {
        var nextChannel: UInt8 = 0
        var assignedPrograms: [UInt8: UInt8] = [:]

        for program in 0..<15 {
            _ = try MIDIInstrument.generic(program: UInt8(program)).allocateChannel(
                nextMelodicChannel: &nextChannel, assignedPrograms: &assignedPrograms)
        }

        #expect(throws: MIDIChannelAllocationError.self) {
            _ = try MIDIInstrument.generic(program: 15).allocateChannel(
                nextMelodicChannel: &nextChannel, assignedPrograms: &assignedPrograms)
        }
    }
}
