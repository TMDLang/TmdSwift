import Foundation
import Testing

@testable import TmdMIDI
@testable import TmdSwift
@testable import TmdUTAU

@Suite("UTAU Exporter Tests")
struct UTAUTests {

    @Test("Test basic UTAU (.ust) generation domain invariants")
    func testBasicUSTGeneration() throws {
        let tmdContent = """
            ::SCORE::
            ** Kasane Teto Song **
            != 120
            ?= C
            <4/4>
            Intro:Vocal@|0|{
                <4*>
                1 2 3 4
                [あ い う え]
            }
            """
        let sheet = try TmdParser.parseThrowing(string: tmdContent)
        let ust = TmdUSTGenerator.generateUST(
            from: sheet,
            options: USTExportOptions(
                projectName: "Kasane Teto Song", lyrics: ["あ", "い", "う", "え"])
        )

        // Verify Header invariants
        #expect(ust.contains("[#SETTING]"))
        #expect(ust.contains("Tempo=120.00"))
        #expect(ust.contains("Tracks=1"))
        #expect(ust.contains("ProjectName=Kasane Teto Song"))
        #expect(ust.contains("Mode2=True"))
        #expect(ust.contains("Charset=UTF-8"))

        // Verify Note sequence invariants (4 quarter notes at 480 ticks each)
        #expect(ust.contains("[#0000]"))
        #expect(ust.contains("Length=480"))
        #expect(ust.contains("Lyric=あ"))
        #expect(ust.contains("NoteNum=60"))

        #expect(ust.contains("[#0001]"))
        #expect(ust.contains("Lyric=い"))
        #expect(ust.contains("NoteNum=62"))

        #expect(ust.contains("[#0002]"))
        #expect(ust.contains("Lyric=う"))
        #expect(ust.contains("NoteNum=64"))

        #expect(ust.contains("[#0003]"))
        #expect(ust.contains("Lyric=え"))
        #expect(ust.contains("NoteNum=65"))

        // Verify footer
        #expect(ust.contains("[#TRACKEND]"))
    }

    @Test("Test UTAU rest insertion and sustained notes")
    func testUSTWithRestsAndTies() throws {
        let tmdContent = """
            ::SCORE::
            != 130
            ?= G
            <4/4>
            Melody:Sing@|0|{
                <4*>
                1 - 0 1
                [お _ _ か]
            }
            """
        let sheet = try TmdParser.parseThrowing(string: tmdContent)
        let ust = TmdUSTGenerator.generateUST(
            from: sheet, options: USTExportOptions(lyrics: ["お", "か"]))

        #expect(ust.contains("Tempo=130.00"))

        // G4 is MIDI pitch 67 (Key of G: 1 = G4 = 67).
        // First note is sustained for 2 beats = 960 ticks.
        #expect(ust.contains("[#0000]"))
        #expect(ust.contains("Length=960"))
        #expect(ust.contains("Lyric=お"))
        #expect(ust.contains("NoteNum=67"))

        // Second note is a rest (0) for 1 beat = 480 ticks with Lyric=R.
        #expect(ust.contains("[#0001]"))
        #expect(ust.contains("Length=480"))
        #expect(ust.contains("Lyric=R"))

        // Third note is 1 beat = 480 ticks, lyric か, NoteNum=67.
        #expect(ust.contains("[#0002]"))
        #expect(ust.contains("Length=480"))
        #expect(ust.contains("Lyric=か"))
        #expect(ust.contains("NoteNum=67"))

        #expect(ust.contains("[#TRACKEND]"))
    }

    @Test("Test UTAU mid-score tempo changes")
    func testUSTMidScoreTempoChange() throws {
        let tmdContent = """
            ::SCORE::
            != 100
            ?= C
            <4/4>
            PartA:Voice@|0|{
                <4*>
                1 2
                [a b]
            }
            PartB:Voice@|0|{
                <4*>
                {!=150}
                3 4
                [c d]
            }
            """
        let sheet = try TmdParser.parseThrowing(string: tmdContent)
        let ust = TmdUSTGenerator.generateUST(from: sheet)

        // PartB should have Tempo=150.00 attached to its first note
        #expect(ust.contains("Tempo=100.00"))
        #expect(ust.contains("Tempo=150.00"))
    }

    @Test("Test UTAU monophonic reduction of simultaneous multi-notes (1+3+5 picks highest pitch 5=67)")
    func testUSTMonophonicMultiNoteReduction() throws {
        let tmdContent = """
            ::SCORE::
            != 120
            ?= C
            <4/4>
            Verse:Vocal@|0|{
                <4*>
                1+3+5 2
            }
            """
        let sheet = try TmdParser.parseThrowing(string: tmdContent)
        let ust = TmdUSTGenerator.generateUST(
            from: sheet, options: USTExportOptions(lyrics: ["あ", "い"]))

        #expect(ust.contains("[#0000]\r\nLength=480\r\nLyric=あ\r\nNoteNum=67"))
        #expect(ust.contains("[#0001]\r\nLength=480\r\nLyric=い\r\nNoteNum=62"))
        #expect(!ust.contains("[#0002]"))
    }
}
