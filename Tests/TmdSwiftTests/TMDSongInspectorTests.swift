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
        #expect(vocalProfile.difficulty == .difficult)
        #expect(vocalProfile.suitableVoiceTypes.contains(.soprano))

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

    @Test func testInspectSongRepeatedSectionsMeasureAndTime() throws {
        let tmd = """
        ::SCORE::
        ** Modulation & Repeated Verse Song **
        != 120.0
        ?= C
        <4/4>

        verse:Vocal@|0|{
            <4*>
            1 2 3 4
            [C] - - -
        }

        chorus:Vocal@|0|{
            <4*>
            5 1^ 3^ 5^
            [G] - - -
        }

        -> verse -> chorus -> {?+2} -> verse -> chorus ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet)

        let vocal = try #require(profile.vocalRange)
        // In verse #1: 1 2 3 4 in C -> C4 (60), D4 (62), E4 (64), F4 (65)
        // In chorus #1: 5 1^ 3^ 5^ in C -> G4 (67), C5 (72), E5 (76), G5 (79)
        // In verse #2 (after ?+2 = D): 1 2 3 4 in D -> D4 (62), E4 (64), F#4 (66), G4 (67)
        // In chorus #2 (after ?+2 = D): 5 1^ 3^ 5^ in D -> A4 (69), D5 (74), F#5 (78), A5 (81)
        // Lowest note: C4 (60) in verse #1 at m.1, 0:00 (0.0s)
        // Highest note: A5 (81) in chorus #2 at m.7, 0:12 (12.0s)
        #expect(vocal.lowestNote.midiPitch == 60)
        #expect(vocal.lowestNote.sectionName == "verse")
        #expect(vocal.lowestNote.sectionOccurrence == 1)
        #expect(vocal.lowestNote.measure == 1)
        #expect(abs(vocal.lowestNote.timeSeconds - 0.0) < 0.01)

        #expect(vocal.highestNote.midiPitch == 81)
        #expect(vocal.highestNote.sectionName == "chorus")
        #expect(vocal.highestNote.sectionOccurrence == 2)
        #expect(vocal.highestNote.measure == 7)
        #expect(abs(vocal.highestNote.timeSeconds - 13.5) < 0.01)

        let report = TMDSongInspector.generateReport(profile)
        // Check report string formatting for occurrence, measure, and timestamp
        #expect(report.contains("in [verse #1 @ m.1, 0:00]"))
        #expect(report.contains("in [chorus #2 @ m.7, 0:13]"))
    }
}

