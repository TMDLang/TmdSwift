import Testing
import Foundation
@testable import TmdSwift

@Suite("TMD Song Profile & Inspector Tests")
struct TMDSongInspectorTests {

    @Test func testInspectSongBasicProfile() throws {
        let tmd = """
        ::SCORE::
        ** Inspector Test Song **
        != 120.0
        ?= C
        <4/4>

        intro:Piano@|0|{
            <4*>
            1 2 3 4
            [C] - [G] -
        }

        verse:Vocal@|0|{
            <4*>
            1 3 5 1^
            [Am] - [F] -
        }

        verse:Bass@|0|{
            <4*>
            1_ - 5_ -
            6_ - 4_ -
        }

        chorus:Vocal@|0|{
            <4*>
            5 1^ 3^ 5^
            [C] - [G] -
        }

        chorus:Bass@|0|{
            <4*>
            1_ - - -
            5_ - - -
        }

        -> intro -> verse -> {?+2} -> chorus ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet)

        // 1. Basic Metadata & Keys
        #expect(profile.title == "Inspector Test Song")
        #expect(profile.initialTempo == 120.0)
        #expect(profile.initialKey == "C")
        #expect(profile.initialTimeSignature == "4/4")

        // 2. Playback Timing
        // intro (2 bars @ 4/4 @ 120bpm = 4s)
        // verse (2 bars @ 4/4 @ 120bpm = 4s)
        // chorus (2 bars @ 4/4 @ 120bpm = 4s)
        // Total: 6 bars = 12.0 seconds
        #expect(profile.timing.totalMeasures == 6)
        #expect(abs(profile.timing.totalDurationSeconds - 12.0) < 0.01)
        #expect(profile.timing.sections.count == 3)
        #expect(profile.timing.sections[0].name == "intro")
        #expect(abs(profile.timing.sections[0].durationSeconds - 4.0) < 0.01)
        #expect(profile.timing.sections[1].name == "verse")
        #expect(profile.timing.sections[2].name == "chorus")

        // 3. Vocal Pitch Range & Tessitura (under {?+2} modulation)
        // Vocal appears in:
        // - verse in key C (keyOffset = 0): notes 1, 3, 5, 1^ -> MIDI 60 (C4), 64 (E4), 67 (G4), 72 (C5)
        // - chorus in key C + 2 semitones = D (keyOffset = 2): notes 5, 1^, 3^, 5^
        //   5 in D = 67 + 2 = 69 (A4)
        //   1^ in D = 72 + 2 = 74 (D5)
        //   3^ in D = 76 + 2 = 78 (F#5)
        //   5^ in D = 79 + 2 = 81 (A5)
        let vocalProfile = try #require(profile.vocalRange)
        #expect(vocalProfile.instrument == "Vocal")
        #expect(vocalProfile.lowestNote.midiPitch == 60) // C4
        #expect(vocalProfile.lowestNote.noteName == "C4")
        #expect(vocalProfile.highestNote.midiPitch == 81) // A5
        #expect(vocalProfile.highestNote.noteName == "A5")
        #expect(vocalProfile.spanSemitones == 21) // 81 - 60 = 21 semitones
        #expect(abs(vocalProfile.spanOctaves - 1.75) < 0.01)
        #expect(vocalProfile.highestNote.sectionName == "chorus")

        // 4. Track Ranges
        #expect(profile.instrumentRanges.count >= 2)
        let bassRange = try #require(profile.instrumentRanges.first { $0.instrument == "Bass" })
        #expect(bassRange.lowestNote.midiPitch < 60) // Low bass note

        // 5. Harmony & Chords
        // Chords parsed across paragraphs: C, G, Am, F
        #expect(profile.harmony.distinctChords.contains("[C]"))
        #expect(profile.harmony.distinctChords.contains("[G]"))
        #expect(profile.harmony.distinctChords.contains("[Am]"))
        #expect(profile.harmony.distinctChords.contains("[F]"))

        // 6. Arrangement Energy & Density
        // intro: 1 track (Piano)
        // verse: 2 tracks (Vocal, Bass)
        // chorus: 2 tracks (Vocal, Bass)
        #expect(profile.density.maxConcurrentTracks == 2)
        #expect(profile.density.sectionDensities.first { $0.sectionName == "intro" }?.trackCount == 1)
        #expect(profile.density.sectionDensities.first { $0.sectionName == "verse" }?.trackCount == 2)

        // 7. Text Report Output
        let report = TMDSongInspector.generateReport(profile)
        #expect(report.contains("Inspector Test Song"))
        #expect(report.contains("12.0s") || report.contains("12s"))
        #expect(report.contains("C4"))
        #expect(report.contains("A5"))
        #expect(report.contains("21 semitones"))
        #expect(report.contains("1.8 octaves"))
    }
}
