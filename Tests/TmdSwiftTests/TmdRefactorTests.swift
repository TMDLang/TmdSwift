import Testing
import Foundation
@testable import TmdSwift

@Suite("TMD Refactor Tests")
struct TmdRefactorTests {
    @Test func testFormatTMDDocumentPreservesCommentsAndFormatting() throws {
        let input = """
        ::SCORE::
        /* Header Comment */
        ** My Song **
        !=   120
        ?=  C
        <4/4>

        intro:Piano@|0|{
        <4*>
        |[1]  -   |   -  [7,]   |  /* bar comment */
        1   2   3   4
        (1' 2,  3^ 4_)%(--)
        }

        -> intro   ->#
        """

        let formatted = TMDRefactor.format(input)
        #expect(formatted.contains("/* Header Comment */"))
        #expect(formatted.contains("/* bar comment */"))
        #expect(formatted.contains("intro:Piano@|0|{"))
        #expect(formatted.contains("    <4*>"))
        #expect(formatted.contains("    | [1] - | - [7,] |"))
        #expect(formatted.contains("    1 2 3 4"))
        #expect(formatted.contains("    (1' 2, 3^ 4_)%(--)"))
        #expect(formatted.contains("}"))
        #expect(formatted.contains("-> intro ->#"))
        // Check that reparsing the formatted string yields the exact same Sheet
        let origSheet = try #require(TmdParser.parse(string: input))
        let newSheet = try #require(TmdParser.parse(string: formatted))
        #expect(origSheet.name == newSheet.name)
        #expect(origSheet.paragraphs.count == newSheet.paragraphs.count)
        #expect(origSheet.orders.count == newSheet.orders.count)
    }

    @Test func testRenameInstrumentInTMDDocument() throws {
        let input = """
        ::SCORE::
        ** Test Song **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
        <4*>
        1 2 3 4
        }

        verse:Guitar@|0|{
        <4*>
        [C] - - -
        }

        outro:Piano@|0|{
        <4*>
        5 6 7 1^
        }

        -> intro -> verse -> outro ->#
        """

        let result = try TMDRefactor.renameInstrument(in: input, from: "Piano", to: "GrandPiano")
        #expect(result.contains("intro:GrandPiano@|0|{"))
        #expect(result.contains("outro:GrandPiano@|0|{"))
        #expect(result.contains("verse:Guitar@|0|{"))
        #expect(!result.contains(":Piano@"))

        // Sheet inspection
        let sheet = try #require(TmdParser.parse(string: result))
        #expect(sheet.paragraphs[0].instrument == "GrandPiano")
        #expect(sheet.paragraphs[1].instrument == "Guitar")
        #expect(sheet.paragraphs[2].instrument == "GrandPiano")
    }

    @Test func testRenameSectionInTMDDocumentUpdatesParagraphsAndOrders() throws {
        let input = """
        ::SCORE::
        ** Test Song **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
        <4*>
        1 2 3 4
        }

        verse:Piano@|0|{
        <4*>
        1 3 5 1^
        }

        verse:Bass@|0|{
        <4*>
        1_ - - -
        }

        -> intro -> verse -> {?+2} -> verse ->#
        """

        let result = try TMDRefactor.renameSection(in: input, from: "verse", to: "A")
        #expect(result.contains("intro:Piano@|0|{"))
        #expect(result.contains("A:Piano@|0|{"))
        #expect(result.contains("A:Bass@|0|{"))
        #expect(!result.contains("verse:Piano@"))
        #expect(!result.contains("verse:Bass@"))
        #expect(result.contains("-> intro -> A -> {?+2} -> A ->#"))

        let sheet = try #require(TmdParser.parse(string: result))
        #expect(sheet.paragraphs[1].name == "A")
        #expect(sheet.paragraphs[2].name == "A")
        #expect(sheet.orders == [.name("intro"), .name("A"), .relative("+2"), .name("A")])
    }

    @Test func testExtractInstrumentFromTMDDocument() throws {
        let input = """
        ::SCORE::
        ** Full Band Song **
        != 130
        ?= G
        <4/4>
        ~ "Composer: Alice"

        intro:Piano@|0|{
        <4*>
        1 2 3 4
        }

        intro:Bass@|0|{
        <4*>
        1_ - - -
        }

        verse:Piano@|0|{
        <4*>
        3 4 5 6
        }

        verse:Drums@|0|{
        <4*>
        XsTt
        }

        -> intro -> verse ->#
        """

        let extracted = try TMDRefactor.extractInstrument(from: input, instrument: "Piano")
        #expect(extracted.contains("** Full Band Song **"))
        #expect(extracted.contains("!= 130"))
        #expect(extracted.contains("?= G"))
        #expect(extracted.contains("<4/4>"))
        #expect(extracted.contains("intro:Piano@|0|{"))
        #expect(extracted.contains("verse:Piano@|0|{"))
        #expect(!extracted.contains(":Bass@"))
        #expect(!extracted.contains(":Drums@"))
        #expect(extracted.contains("-> intro -> verse ->#"))

        let sheet = try #require(TmdParser.parse(string: extracted))
        #expect(sheet.name == "Full Band Song")
        #expect(sheet.paragraphs.count == 2)
        #expect(sheet.paragraphs.allSatisfy { $0.instrument == "Piano" })
        #expect(sheet.orders == [.name("intro"), .name("verse")])
    }

    @Test func testCLISubcommandsFormatAndRefactor() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleTmd = tempDir.appendingPathComponent("score.tmd")
        let formattedOutput = tempDir.appendingPathComponent("formatted.tmd")
        let extractedOutput = tempDir.appendingPathComponent("extracted.tmd")

        let content = """
        ::SCORE::
        ** Subcommand Test **
        !=   100
        ?=  D
        <4/4>

        verse:Violin@|0|{
        <4*>
        1   2   3   4
        }

        verse:Cello@|0|{
        <4*>
        1_  -   -   -
        }

        -> verse ->#
        """
        try content.write(to: sampleTmd, atomically: true, encoding: .utf8)

        var tmdURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent().appendingPathComponent("tmd")
        if !FileManager.default.isExecutableFile(atPath: tmdURL.path) {
            // Check current directory .build/out/Products/Debug/tmd
            let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/out/Products/Debug/tmd")
            if FileManager.default.isExecutableFile(atPath: fallbackURL.path) {
                tmdURL = fallbackURL
            }
        }
        #expect(FileManager.default.isExecutableFile(atPath: tmdURL.path), "tmd binary must be built and available")
        guard FileManager.default.isExecutableFile(atPath: tmdURL.path) else { return }

        // 1. Test `tmd format -o <out>`
        let formatProc = Process()
        formatProc.executableURL = tmdURL
        formatProc.arguments = ["format", sampleTmd.path, "-o", formattedOutput.path]
        try formatProc.run()
        formatProc.waitUntilExit()
        #expect(formatProc.terminationStatus == 0)
        let fmtContent = try String(contentsOf: formattedOutput, encoding: .utf8)
        #expect(fmtContent.contains("!= 100"))
        #expect(fmtContent.contains("1 2 3 4"))

        // 2. Test `tmd refactor rename-instrument --from Violin --to Fiddle -i`
        let renameInstProc = Process()
        renameInstProc.executableURL = tmdURL
        renameInstProc.arguments = ["refactor", "rename-instrument", sampleTmd.path, "--from", "Violin", "--to", "Fiddle", "-i"]
        try renameInstProc.run()
        renameInstProc.waitUntilExit()
        #expect(renameInstProc.terminationStatus == 0)
        let renamedInstContent = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(renamedInstContent.contains("verse:Fiddle@|0|{"))
        #expect(!renamedInstContent.contains("verse:Violin@|0|{"))

        // 3. Test `tmd refactor rename-section --from verse --to Chorus -i`
        let renameSecProc = Process()
        renameSecProc.executableURL = tmdURL
        renameSecProc.arguments = ["refactor", "rename-section", sampleTmd.path, "--from", "verse", "--to", "Chorus", "-i"]
        try renameSecProc.run()
        renameSecProc.waitUntilExit()
        #expect(renameSecProc.terminationStatus == 0)
        let renamedSecContent = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(renamedSecContent.contains("Chorus:Fiddle@|0|{"))
        #expect(renamedSecContent.contains("Chorus:Cello@|0|{"))
        #expect(renamedSecContent.contains("-> Chorus ->#"))

        // 4. Test `tmd refactor extract-instrument --instrument Cello -o <out>`
        let extractProc = Process()
        extractProc.executableURL = tmdURL
        extractProc.arguments = ["refactor", "extract-instrument", sampleTmd.path, "--instrument", "Cello", "-o", extractedOutput.path]
        try extractProc.run()
        extractProc.waitUntilExit()
        #expect(extractProc.terminationStatus == 0)
        let extractedContent = try String(contentsOf: extractedOutput, encoding: .utf8)
        #expect(extractedContent.contains("Chorus:Cello@|0|{"))
        #expect(!extractedContent.contains("Fiddle"))
    }
}
