import Testing
import Foundation
@testable import TmdSwift
import TmdMIDI
import TmdReaper

@Suite("TMDReaperGenerator Tests")
struct TMDReaperGeneratorTests {

    @Test func testBasicProjectHeaderAndMarkers() throws {
        let tmd = """
        ::SCORE::
        ** REAPER Demo **
        != 120
        ?= C
        <4/4>

        Intro:Piano@|0|{
            <4*>
            1 - - -
        }

        Verse:Piano@|0|{
            <4*>
            3 - - -
        }
        -> Intro -> Verse ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let rpp = TMDReaperGenerator.generateRPP(from: sheet)

        // Project structure
        #expect(rpp.contains("<REAPER_PROJECT"))
        #expect(rpp.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(">"))

        // Tempo envelope with 120 BPM and 4/4 time signature ((4 << 16) | 4 = 262148)
        #expect(rpp.contains("<TEMPOENVEX"))
        #expect(rpp.range(of: #"PT 0\.00000000 120(\.0+)? 0 262148"#, options: .regularExpression) != nil)

        // Section markers on timeline
        // Intro at 0s, Verse at measure 1 (4 quarter notes at 120 BPM = 2.0s)
        #expect(rpp.range(of: #"MARKER 1 0\.00000000 "Intro" 0"#, options: .regularExpression) != nil)
        #expect(rpp.range(of: #"MARKER 2 2\.00000000 "Verse" 0"#, options: .regularExpression) != nil)
    }

    @Test func testDynamicTempoChangesWithoutHardcodedBPM() throws {
        let tmd = """
        ::SCORE::
        ** Dynamic Tempo Demo **
        != 60
        ?= C
        <4/4>

        A:Piano@|0|{
            <4*>
            1 - - -
            {!=120} 2 - - -
        }
        -> A ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let rpp = TMDReaperGenerator.generateRPP(from: sheet)

        // Initial tempo: 60 BPM at 0.0s
        #expect(rpp.range(of: #"PT 0\.00000000 60(\.0+)? 0 262148"#, options: .regularExpression) != nil)

        // Measure 1 is 4 quarter notes at 60 BPM = 4.0 seconds
        // At 4.0s, tempo changes to 120 BPM
        #expect(rpp.range(of: #"PT 4\.00000000 120(\.0+)? 0 262148"#, options: .regularExpression) != nil)
    }

    @Test func testMarkersUseMeterStateForParagraphStartOffsets() throws {
        let tmd = """
        ::SCORE::
        ** Meter-Aware Markers **
        != 120
        ?= C
        <4/4>

        A:Piano@|0|{
            <4*>
            1 - - -
            {<3/4>}
        }

        B:Piano@|1|{
            <4*>
            1 - - -
        }

        C:Piano@|0|{
            <4*>
            1 - - -
        }
        -> A -> B -> C ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let rpp = TMDReaperGenerator.generateRPP(from: sheet)

        // A = 4 quarters, B starts 1 bar later in the active 3/4 meter and lasts 4 quarters.
        // C therefore starts at 11 quarters = 5.5 seconds at 120 BPM.
        #expect(rpp.range(of: #"MARKER 3 5\.50000000 "C" 0"#, options: .regularExpression) != nil)
    }

    @Test func testTrackConfigurationPanningColorsAndInlineMIDI() throws {
        let tmd = """
        ::SCORE::
        ** Multi-track Demo **
        != 120
        ?= C
        <4/4>

        A:Piano-L@|0|{
            <4*>
            1 2 3 4
        }

        A:Piano-R@|0|{
            <4*>
            5 6 7 1^
        }

        A:Drums@|0|{
            <4*>
            D S - -
        }
        -> A ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let rpp = TMDReaperGenerator.generateRPP(from: sheet)

        // Tracks exist
        #expect(rpp.contains("NAME \"Piano-L\""))
        #expect(rpp.contains("NAME \"Piano-R\""))
        #expect(rpp.contains("NAME \"Drums\""))

        // Stereo Panning
        // Piano-L: -0.8 (left), Piano-R: 0.8 (right), Drums: 0.0 (center)
        #expect(rpp.range(of: #"NAME "Piano-L"[\s\S]*?VOLPAN 1(\.0+)? -0\.80*"#, options: .regularExpression) != nil)
        #expect(rpp.range(of: #"NAME "Piano-R"[\s\S]*?VOLPAN 1(\.0+)? 0\.80*"#, options: .regularExpression) != nil)
        #expect(rpp.range(of: #"NAME "Drums"[\s\S]*?VOLPAN 1(\.0+)? 0(\.0+)? 1 -1 1"#, options: .regularExpression) != nil)

        // Instrument colors (PEAKCOL)
        #expect(rpp.range(of: #"NAME "Drums"[\s\S]*?PEAKCOL \d+"#, options: .regularExpression) != nil)
        #expect(rpp.range(of: #"NAME "Piano-L"[\s\S]*?PEAKCOL \d+"#, options: .regularExpression) != nil)

        // Inline MIDI item chunks with 960 PPQ
        #expect(rpp.contains("<SOURCE MIDI"))
        #expect(rpp.contains("HASDATA 1 960 QN"))

        // Pitch assertions:
        // C key, Note 1 = C4 = MIDI 60 (0x3c)
        // Note On channel 0: 90 3c
        #expect(rpp.range(of: #"E \d+ 90 3c [0-9a-f]{2}"#, options: .regularExpression) != nil)
        // Drums: D (Kick) = MIDI 36 (0x24) on channel 9 (0x99)
        #expect(rpp.range(of: #"E \d+ 99 24 [0-9a-f]{2}"#, options: .regularExpression) != nil)
        // Drums: S (Snare) = MIDI 38 (0x26) on channel 9 (0x99)
        #expect(rpp.range(of: #"E \d+ 99 26 [0-9a-f]{2}"#, options: .regularExpression) != nil)
    }

    @Test func testSampleScoreExport() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let sheet = try TmdParser.parseThrowing(filePathOrURL: sampleURL.path)
        let rpp = TMDReaperGenerator.generateRPP(from: sheet)

        #expect(rpp.contains("<REAPER_PROJECT"))
        #expect(rpp.contains("<TEMPOENVEX"))
        #expect(rpp.contains("NAME \"Guitar\""))
        #expect(rpp.contains("NAME \"GROOVE\""))
        #expect(rpp.contains("<SOURCE MIDI"))
        #expect(rpp.contains("HASDATA 1 960 QN"))
    }
}
