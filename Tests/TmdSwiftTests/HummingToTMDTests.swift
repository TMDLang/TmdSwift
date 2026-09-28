import Foundation
import Testing
@testable import TmdSwift

@Test("MIDI pitches map to Jianpu relative to the tonic")
func midiPitchMapsToJianpu() {
    #expect(HummingQuantizer.jianpu(forMIDI: 60, key: "C") == "1")
    #expect(HummingQuantizer.jianpu(forMIDI: 62, key: "C") == "2")
    #expect(HummingQuantizer.jianpu(forMIDI: 72, key: "C") == "1^")
    #expect(HummingQuantizer.jianpu(forMIDI: 48, key: "C") == "1_")
    #expect(HummingQuantizer.jianpu(forMIDI: 61, key: "C") == "1'")
    #expect(HummingQuantizer.jianpu(forMIDI: 67, key: "G") == "1")
    #expect(HummingQuantizer.jianpu(forMIDI: 72, key: "G") == "4")
}

@Test("Quantization preserves rests, ties, and measure boundaries")
func quantizesNoteEventsIntoTMD() throws {
    let events = [
        HummingNoteEvent(startTimeSeconds: 0, durationSeconds: 0.5, pitchMIDI: 60, amplitude: 0.9),
        HummingNoteEvent(startTimeSeconds: 0.75, durationSeconds: 0.25, pitchMIDI: 67, amplitude: 0.9),
    ]
    let result = HummingQuantizer.quantize(
        events,
        options: HummingQuantizationOptions(sectionName: "verse", instrument: "Vocal", bpm: 120, grid: 8, key: "C")
    )

    #expect(result == """
verse:Vocal@|0|{
    <8*>
    | 1 - 0 5 0 0 0 0 |
}
""".trimmingCharacters(in: .whitespacesAndNewlines))

    let sheet = try #require(TmdParser.parse(string: "::SCORE::\n<4/4>\n\(result)"))
    let section = try #require(sheet.entries.first?.sections.first)
    #expect(section.noteLength == 8)
    #expect(section.unitGroups.count == 8)
    #expect(section.unitGroups[0].units == [.note(Note(degree: 1))])
    #expect(section.unitGroups[1].units == [.tie])
    #expect(section.unitGroups[2].units == [.rest])
    #expect(section.unitGroups[3].units == [.note(Note(degree: 5))])
}

@Test("Automatic tonic detection and scale snapping follow the TS reference")
func detectsTonicAndSnapsAccidentals() {
    let events = [
        HummingNoteEvent(startTimeSeconds: 0, durationSeconds: 1, pitchMIDI: 67, amplitude: 0.9),
        HummingNoteEvent(startTimeSeconds: 1, durationSeconds: 0.5, pitchMIDI: 69, amplitude: 0.8),
        HummingNoteEvent(startTimeSeconds: 1.5, durationSeconds: 0.5, pitchMIDI: 71, amplitude: 0.8),
        HummingNoteEvent(startTimeSeconds: 2, durationSeconds: 0.5, pitchMIDI: 72, amplitude: 0.8),
        HummingNoteEvent(startTimeSeconds: 2.5, durationSeconds: 1, pitchMIDI: 74, amplitude: 0.9),
        HummingNoteEvent(startTimeSeconds: 3.5, durationSeconds: 1.5, pitchMIDI: 67, amplitude: 0.9),
    ]

    #expect(HummingQuantizer.detectTonic(events) == "G")
    #expect(HummingQuantizer.jianpu(forMIDI: 61, key: "C", snapToScale: true) == "1")
    #expect(HummingQuantizer.jianpu(forMIDI: 63, key: "C", snapToScale: true) == "2")
}

@Test("Empty or unusable input produces one rest measure")
func emptyInputProducesRestMeasure() {
    let result = HummingQuantizer.quantize(
        [],
        options: HummingQuantizationOptions(sectionName: "empty", bpm: 100, grid: 4)
    )

    #expect(result.contains("empty:Vocal@|0|{"))
    #expect(result.contains("<4*>"))
    #expect(result.hasSuffix("    0\n}"))
}
