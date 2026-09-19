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

    @Test func testFormatMultiLineBlockCommentsWithConsistentIndentation() throws {
        let input = """
        ::SCORE::
        /*
         * Header multi-line comment
         * line 2
         */
        ** My Song **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
        <4*>
            /*
             * Section multi-line comment
             * line 2
             */
        1 2 3 4
        }

        -> intro ->#
        """

        let formatted = TMDRefactor.format(input)
        // At root level, comments should not have leading indentation on any line
        #expect(formatted.contains("/*\n * Header multi-line comment\n * line 2\n */"))

        // Inside paragraph (indentLevel = 1, 4 spaces), every line of comment should be indented with 4 spaces
        #expect(formatted.contains("    /*\n     * Section multi-line comment\n     * line 2\n     */"))
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

        guard let tmdURL = TmdTestHelper.findTmdExecutable() else {
            Issue.record("tmd binary must be built and available")
            return
        }

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

    @Test func testDoubleGridAndHalveGridResolution() throws {
        let input = """
        ::SCORE::
        ** Grid Test **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
            | [C] - 0 D |
        }

        -> verse ->#
        """

        let doubled = try TMDRefactor.doubleGrid(source: input)
        #expect(doubled.contains("<8*>"))
        #expect(doubled.contains("| 1 - 2 - 3 - 4 - |"))
        #expect(doubled.contains("| [C] - - - 0 - D - |"))

        let doubleIssues = TMDMeasureChecker.check(source: doubled)
        #expect(doubleIssues.isEmpty)

        let halved = try TMDRefactor.halveGrid(source: doubled)
        #expect(halved.contains("<4*>"))
        #expect(halved.contains("| 1 2 3 4 |"))
        #expect(halved.contains("| [C] - 0 D |"))

        let halveIssues = TMDMeasureChecker.check(source: halved)
        #expect(halveIssues.isEmpty)
    }

    @Test func testDoubleAndHalveGridWithTupletsAndSpacedSyntax() throws {
        let input = """
        ::SCORE::
        ** Tuplet Grid Test **
        != 120
        ?= C
        <4/4>

        Intro:vocal@|0|{
            <4*>
            | 1 2 3 1 | 1 2 (3 1) % (-) 1 |
        }

        -> Intro ->#
        """

        let doubled = try TMDRefactor.doubleGrid(source: input)
        #expect(doubled.contains("<8*>"))
        #expect(doubled.contains("(3 1)%(--)"))
        let doubleIssues = TMDMeasureChecker.check(source: doubled)
        #expect(doubleIssues.isEmpty)

        let halved = try TMDRefactor.halveGrid(source: doubled)
        #expect(halved.contains("<4*>"))
        #expect(halved.contains("(3 1)%(-)"))
        let halveIssues = TMDMeasureChecker.check(source: halved)
        #expect(halveIssues.isEmpty)
    }

    @Test func testHalveGridThrowsErrorOnIndivisibleMeasure() throws {
        let input = """
        ::SCORE::
        ** Indivisible Test **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <8*>
            | 1 2 3 4 5 6 7 8 |
        }

        -> verse ->#
        """

        #expect(throws: Error.self) {
            _ = try TMDRefactor.halveGrid(source: input)
        }
    }

    @Test func testDuplicateTrack() throws {
        let input = """
        ::SCORE::
        ** Dup Test **
        != 120
        ?= C
        <4/4>

        verse:Lead@|0|{
            <4*>
            | 1 2 3 5 |
        }

        -> verse ->#
        """

        let duped = try TMDRefactor.duplicateTrack(
            source: input,
            sourceInstrument: "Lead",
            targetInstrument: "Synth",
            octaveShift: -1
        )
        #expect(duped.contains("verse:Lead@|0|{"))
        #expect(duped.contains("verse:Synth@|0|{"))
        #expect(duped.contains("1_ 2_ 3_ 5_"))

        let issues = TMDMeasureChecker.check(source: duped)
        #expect(issues.isEmpty)
    }

    @Test func testDuplicateTrackRestrictedToSection() throws {
        let input = """
        ::SCORE::
        ** Multi-Section Dup Test **
        != 120
        ?= C
        <4/4>

        verse:Lead@|0|{
            <4*>
            | 1 2 3 4 |
        }

        chorus:Lead@|0|{
            <4*>
            | 5 6 7 1^ |
        }

        -> verse -> chorus ->#
        """

        let duped = try TMDRefactor.duplicateTrack(
            source: input,
            sourceInstrument: "Lead",
            targetInstrument: "Synth",
            section: "chorus",
            octaveShift: 1
        )
        #expect(duped.contains("chorus:Synth@|0|{"))
        #expect(duped.contains("5^ 6^ 7^ 1^^"))
        #expect(!duped.contains("verse:Synth@"))

        let issues = TMDMeasureChecker.check(source: duped)
        #expect(issues.isEmpty)
    }

    @Test func testGenerateHarmony() throws {
        let input = """
        ::SCORE::
        ** Harmony Test **
        != 120
        ?= C
        <4/4>

        verse:Vocal@|0|{
            <4*>
            | 1 2 3 1 | [C] - - - |
        }

        -> verse ->#
        """

        let harmonized = try TMDRefactor.generateHarmony(
            source: input,
            sourceInstrument: "Vocal",
            harmonyInstrument: "Harmony",
            intervalSteps: 2
        )
        #expect(harmonized.contains("verse:Vocal@|0|{"))
        #expect(harmonized.contains("verse:Harmony@|0|{"))
        #expect(harmonized.contains("3 4 5 3"))
        #expect(harmonized.contains("[C] - - -"))

        let issues = TMDMeasureChecker.check(source: harmonized)
        #expect(issues.isEmpty)
    }

    @Test func testInlineOrders() throws {
        let input = """
        ::SCORE::
        ** Unroll Test **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
            <4*>
            | 1 2 3 4 |
        }

        verse:Piano@|0|{
            <4*>
            | 5 6 7 1^ |
        }

        -> intro -> verse -> intro ->#
        """

        let inlined = try TMDRefactor.inlineOrders(source: input)
        #expect(inlined.contains("linear:Piano@|0|{"))
        #expect(inlined.contains("-> linear ->#"))
        #expect(inlined.contains("1 2 3 4"))
        #expect(inlined.contains("5 6 7 1^"))

        let sheet = try #require(TmdParser.parse(string: inlined))
        #expect(sheet.paragraphs.count == 1)
        #expect(sheet.paragraphs[0].sections[0].unitGroups.count == 12)
    }

    @Test func testDuplicateTrackPreservesComments() throws {
        let input = """
        ::SCORE::
        /* Header comment */
        ** My Song **
        != 120
        ?= C
        <4/4>

        verse:Lead@|0|{
            <4*>
            | 1 2 3 4 | /* bar comment */
        }

        -> verse -># /* order comment */
        """

        let duped = try TMDRefactor.duplicateTrack(source: input, sourceInstrument: "Lead", targetInstrument: "Synth", octaveShift: 1)
        #expect(duped.contains("/* Header comment */"))
        #expect(duped.contains("/* bar comment */"))
        #expect(duped.contains("/* order comment */"))
        #expect(duped.contains("verse:Lead@|0|{"))
        #expect(duped.contains("verse:Synth@|0|{"))
        #expect(duped.contains("1^ 2^ 3^ 4^"))

        let issues = TMDMeasureChecker.check(source: duped)
        #expect(issues.isEmpty)
    }

    @Test func testGenerateHarmonyPreservesComments() throws {
        let input = """
        ::SCORE::
        /* Header comment */
        ** Harmony Song **
        != 120
        ?= C
        <4/4>

        verse:Vocal@|0|{
            <4*>
            | 1 2 3 1 | /* bar comment */
        }

        -> verse -># /* order comment */
        """

        let harmonized = try TMDRefactor.generateHarmony(source: input, sourceInstrument: "Vocal", harmonyInstrument: "Backing", intervalSteps: 2)
        #expect(harmonized.contains("/* Header comment */"))
        #expect(harmonized.contains("/* bar comment */"))
        #expect(harmonized.contains("/* order comment */"))
        #expect(harmonized.contains("verse:Vocal@|0|{"))
        #expect(harmonized.contains("verse:Backing@|0|{"))
        #expect(harmonized.contains("3 4 5 3"))

        let issues = TMDMeasureChecker.check(source: harmonized)
        #expect(issues.isEmpty)
    }

    @Test func testExtractInstrumentPreservesComments() throws {
        let input = """
        ::SCORE::
        /* Header Comment */
        ** Full Song **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
            <4*>
            | 1 2 3 4 | /* piano comment */
        }

        intro:Bass@|0|{
            <4*>
            | 1_ - - - | /* bass comment */
        }

        verse:Piano@|0|{
            <4*>
            | 5 6 7 1^ | /* verse piano */
        }

        -> intro -> verse -># /* order comment */
        """

        let extracted = try TMDRefactor.extractInstrument(from: input, instrument: "Piano")
        #expect(extracted.contains("/* Header Comment */"))
        #expect(extracted.contains("/* piano comment */"))
        #expect(extracted.contains("/* verse piano */"))
        #expect(!extracted.contains(":Bass@"))
        #expect(!extracted.contains("/* bass comment */"))
        #expect(extracted.contains("/* order comment */"))
    }
}
