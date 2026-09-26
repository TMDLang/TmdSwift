import Testing
import Foundation
@testable import TmdSwift
import TmdChordPro

@Suite("ChordPro Validation Tests")
struct ChordProValidationTests {

    @Test func testStandardChordProMetadataDirectives() throws {
        let tmd = """
        ::SCORE::
        ** Amazing Grace **
        != 80
        ?= G
        <3/4>
        ~ "詞：John Newton"
        ~ "曲：Traditional"
        ~ "編：Arranger Person"
        =~:__artist__= "Traditional Artist"
        =~:__subtitle__= "Folk Hymn"

        A:Guitar@|0|{
            <4*>
            [G] . .
        }
        -> A ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let cho = TMDChordProGenerator.generateChordPro(from: sheet)

        #expect(cho.contains("{title: Amazing Grace}"))
        #expect(cho.contains("{tempo: 80}"))
        #expect(cho.contains("{time: 3/4}"))
        #expect(cho.contains("{key: G}"))
        #expect(cho.contains("{composer: Traditional}"))
        #expect(cho.contains("{lyricist: John Newton}"))
        #expect(cho.contains("{arranger: Arranger Person}"))
        #expect(cho.contains("{artist: Traditional Artist}"))
        #expect(cho.contains("{subtitle: Folk Hymn}"))
    }

    @Test func testRenderChordProgressionWithMeasureBars() throws {
        let tmd = """
        ::SCORE::
        ** 12 Bar Blues **
        != 120
        ?= C
        <4/4>

        Verse:Guitar@|0|{
            <4*>
            [C] - - -
            [F] - - -
            [C] - [G] -
        }
        -> Verse ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let cho = TMDChordProGenerator.generateChordPro(from: sheet)

        #expect(cho.contains("{comment: Verse}"))
        #expect(cho.contains("| [C] | [F] | [C] [G] |"))
    }

    @Test func testSectionsAndOrderSequencing() throws {
        let tmd = """
        ::SCORE::
        ** Structure Demo **
        != 100
        ?= D
        <4/4>

        Intro:Guitar@|0|{
            <4*>
            [D] . . .
        }

        Chorus:Guitar@|0|{
            <4*>
            [G] . [A] .
        }

        -> Intro -> Chorus -> Intro ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let cho = TMDChordProGenerator.generateChordPro(from: sheet)

        let introMatches = cho.components(separatedBy: "{comment: Intro}").count - 1
        #expect(introMatches == 2)
        let chorusMatches = cho.components(separatedBy: "{comment: Chorus}").count - 1
        #expect(chorusMatches == 1)
    }

    @Test func testRepeatedSectionChordsFollowOrderModulation() throws {
        let tmd = """
        ::SCORE::
        ** Modulated ChordPro **
        != 120
        ?= C
        <4/4>

        Verse:Guitar@|0|{
            <4*>
            [1] - - -
        }
        -> Verse -> {?+2} -> Verse ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let cho = TMDChordProGenerator.generateChordPro(from: sheet)

        #expect(cho.components(separatedBy: "[C]").count - 1 == 1)
        #expect(cho.components(separatedBy: "[D]").count - 1 == 1)
    }

    @Test func testCustomMeasuresPerLine() throws {
        let tmd = """
        ::SCORE::
        ** Long Progression **
        != 120
        ?= C
        <4/4>

        Verse:Guitar@|0|{
            <4*>
            [C] - - -
            [Dm] - - -
            [Em] - - -
            [F] - - -
            [G] - - -
        }
        -> Verse ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let options = ChordProOptions(measuresPerLine: 4)
        let cho = TMDChordProGenerator.generateChordPro(from: sheet, options: options)

        let measureLines = cho.split(separator: "\n").filter { $0.hasPrefix("|") }
        #expect(measureLines.count == 2)
        #expect(measureLines[0].trimmingCharacters(in: .whitespaces) == "| [C] | [Dm] | [Em] | [F] |")
        #expect(measureLines[1].trimmingCharacters(in: .whitespaces) == "| [G] |")
    }

    @Test func testTargetInstrumentSelectionPrioritizesChordsOrGuitar() throws {
        let tmd = """
        ::SCORE::
        ** Multi Track **
        != 120
        ?= C
        <4/4>

        Verse:Drums@|0|{
            <4*>
            Xs . . .
        }

        Verse:AcousticGuitar@|0|{
            <4*>
            [C] - - -
        }
        -> Verse ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let cho = TMDChordProGenerator.generateChordPro(from: sheet)

        #expect(cho.contains("{comment: Verse}"))
        #expect(cho.contains("| [C] |"))
    }

    @Test func testCLIExportChordPro() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tmdFile = tempDir.appendingPathComponent("test.tmd")
        let choFile = tempDir.appendingPathComponent("test.cho")

        let tmdContent = """
        ::SCORE::
        ** CLI Test Song **
        != 90
        ?= F
        <4/4>
        Verse:Guitar@|0|{
            <4*>
            [F] . [C] .
        }
        -> Verse ->#
        """
        try tmdContent.write(to: tmdFile, atomically: true, encoding: .utf8)

        let testBundleDir = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent()
        let tmdURL = testBundleDir.appendingPathComponent("tmd")
        guard FileManager.default.isExecutableFile(atPath: tmdURL.path) else {
            return
        }

        let proc = Process()
        proc.executableURL = tmdURL
        proc.arguments = ["--chordpro-output", choFile.path, tmdFile.path]
        try proc.run()
        proc.waitUntilExit()

        #expect(proc.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: choFile.path))
        let choContent = try String(contentsOf: choFile, encoding: .utf8)
        #expect(choContent.contains("{title: CLI Test Song}"))
        #expect(choContent.contains("{key: F}"))
        #expect(choContent.contains("| [F] [C] |"))
    }
}
