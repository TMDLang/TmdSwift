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

    @Test func testInspectSongDynamicTempoAndMeter() throws {
        let tmd = """
        ::SCORE::
        ** Inspector Tempo **
        != 60
        ?= C
        <4/4>

        A:Vocal@|0|{
            <4*>
            1 2 3 4
            {!=120}
            5 6 7 1^
        }

        -> A ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet, targetInstrument: "Vocal")

        #expect(abs(profile.timing.totalDurationSeconds - 6.0) < 0.00001)
        #expect(abs(profile.timing.sections[0].durationSeconds - 6.0) < 0.00001)
        let vocal = try #require(profile.vocalRange)
        #expect(abs(vocal.highestNote.timeSeconds - 5.5) < 0.00001)
    }

    @Test func testInspectSongTonalityAndKeyProfile() throws {
        let tmd = """
        ::SCORE::
        ** Tonality Test Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            1 3 5 1^
            [C] - [G] -
        }

        chorus:Piano@|0|{
            <4*>
            1 4 5 1^
            [D] - [A] -
        }

        -> verse -> {?+2} -> chorus ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet)

        let tonality = try #require(profile.tonality)

        // 1. Sections Tonality
        #expect(tonality.sections.count == 2)

        let verseSec = tonality.sections[0]
        #expect(verseSec.sectionName == "verse")
        #expect(verseSec.declaredKey == "C")
        #expect(verseSec.keyOffset == 0)
        #expect(verseSec.fifthsPosition == 0)
        #expect(verseSec.pitchClasses.diatonicRatio > 0.99)
        #expect(verseSec.correlation.declaredKeyCorrelation > 0.8)
        #expect(verseSec.correlation.stability == .high)
        #expect(verseSec.nonDiatonicNotes.isEmpty)

        let chorusSec = tonality.sections[1]
        #expect(chorusSec.sectionName == "chorus")
        #expect(chorusSec.declaredKey == "D")
        #expect(chorusSec.keyOffset == 2)
        #expect(chorusSec.fifthsPosition == 2)
        #expect(chorusSec.pitchClasses.diatonicRatio > 0.99)
        #expect(chorusSec.correlation.declaredKeyCorrelation > 0.8)

        // 2. Global Fifths Path
        #expect(tonality.circleOfFifthsPath == [0, 2])

        // 3. Human-readable Producer Report
        let report = TMDSongInspector.generateReport(profile)
        #expect(report.contains("🗝  調性診斷："))
        #expect(report.contains("五度圈歷程:"))
        #expect(report.contains("+0 -> +2"))
        #expect(tonality.modulationStory.contains("轉至 D 大調"))
        #expect(tonality.moodDescription.contains("大調"))
    }

    @Test func testInspectSongChromaticismAndAmbiguousKey() throws {
        let tmd = """
        ::SCORE::
        ** Blues Chromatic Song **
        != 100
        ?= C
        <4/4>

        verse:Vocal@|0|{
            <4*>
            1 3, 4 4' 5 7,
            [C7] - [F7] -
        }

        -> verse ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet)

        let tonality = try #require(profile.tonality)
        let verseSec = tonality.sections[0]

        // Contains flat-3 (Eb), sharp-4 (F#), flat-7 (Bb)
        #expect(!verseSec.nonDiatonicNotes.isEmpty)
        #expect(verseSec.nonDiatonicNotes.contains("D#") || verseSec.nonDiatonicNotes.contains("F#") || verseSec.nonDiatonicNotes.contains("A#"))
        #expect(verseSec.pitchClasses.chromaticRatio > 0.1)

        let report = TMDSongInspector.generateReport(profile)
        #expect(report.contains("調外音:"))
    }

    @Test func testTonalityUsesInitialKeyOffsetOnlyOnce() throws {
        let tmd = """
        ::SCORE::
        ** Initial D Tonality **
        != 120
        ?= D
        <4/4>

        verse:Piano@|0|{
            <4*>
            1 3 5 1^
            [D] - [A] -
        }

        -> verse ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet)
        let tonality = try #require(profile.tonality)
        let section = try #require(tonality.sections.first)

        #expect(section.declaredKey == "D")
        #expect(section.keyOffset == 2)
        #expect(section.fifthsPosition == 2)
        #expect(section.nonDiatonicNotes.isEmpty)
        #expect(tonality.modulationStory == "全曲維持單一調性（未轉調）")
    }

    @Test func testTonalityReportsRelativeModulationFromNonCInitialKey() throws {
        let tmd = """
        ::SCORE::
        ** D To E Tonality **
        != 120
        ?= D
        <4/4>

        verse:Piano@|0|{
            <4*>
            1 3 5 1^
            [D] - [A] -
        }

        chorus:Piano@|0|{
            <4*>
            1 3 5 1^
            [E] - [B] -
        }

        -> verse -> {?+2} -> chorus ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet)
        let tonality = try #require(profile.tonality)

        #expect(tonality.sections.map(\.declaredKey) == ["D", "E"])
        #expect(tonality.sections.map(\.keyOffset) == [2, 4])
        #expect(tonality.modulationStory.contains("D 大調起奏"))
        #expect(tonality.modulationStory.contains("轉至 E 大調 (+2 半音"))
    }

    @Test func testTonalityVisualizerSVGAndHTMLGeneration() throws {
        let tmd = """
        ::SCORE::
        ** Visualizer Test Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            1 3 5 1^
            [C] - [G] -
        }

        chorus:Piano@|0|{
            <4*>
            1 4 5 1^
            [D] - [A] -
        }

        -> verse -> {?+2} -> chorus ->#
        """

        let sheet = try #require(TmdParser.parse(string: tmd))
        let profile = TMDSongInspector.inspect(sheet: sheet)

        // 1. SVG Generation
        let svg = TMDTonalityVisualizer.generateSVG(profile)
        #expect(svg.contains("<svg"))
        #expect(svg.contains("Circle of Fifths Trajectory"))
        #expect(svg.contains("12-Tone Pitch Class Distribution"))
        #expect(svg.contains("Timeline Keyscape Ribbon"))
        #expect(svg.contains("Visualizer Test Song"))

        // 2. HTML Generation
        let html = TMDTonalityVisualizer.generateHTML(profile)
        #expect(html.contains("<!DOCTYPE html>"))
        #expect(html.contains("<svg"))
        #expect(html.contains("Detailed Text Analysis"))
    }
}
