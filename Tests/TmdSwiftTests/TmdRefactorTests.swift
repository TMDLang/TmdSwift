import Foundation
import Testing

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

        let formatted = TmdRefactor.format(input)
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
        #expect(origSheet.entries.count == newSheet.entries.count)
        #expect(origSheet.playback.count == newSheet.playback.count)
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

        let formatted = TmdRefactor.format(input)
        // At root level, comments should not have leading indentation on any line
        #expect(formatted.contains("/*\n * Header multi-line comment\n * line 2\n */"))

        // Inside paragraph (indentLevel = 1, 4 spaces), every line of comment should be indented with 4 spaces
        #expect(
            formatted.contains("    /*\n     * Section multi-line comment\n     * line 2\n     */"))
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

        let result = try TmdRefactor.renameInstrument(in: input, from: "Piano", to: "GrandPiano")
        #expect(result.contains("intro:GrandPiano@|0|{"))
        #expect(result.contains("outro:GrandPiano@|0|{"))
        #expect(result.contains("verse:Guitar@|0|{"))
        #expect(!result.contains(":Piano@"))

        // Sheet inspection
        let sheet = try #require(TmdParser.parse(string: result))
        #expect(sheet.entries[0].assignment == "GrandPiano")
        #expect(sheet.entries[1].assignment == "Guitar")
        #expect(sheet.entries[2].assignment == "GrandPiano")
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

        let result = try TmdRefactor.renameSection(in: input, from: "verse", to: "A")
        #expect(result.contains("intro:Piano@|0|{"))
        #expect(result.contains("A:Piano@|0|{"))
        #expect(result.contains("A:Bass@|0|{"))
        #expect(!result.contains("verse:Piano@"))
        #expect(!result.contains("verse:Bass@"))
        #expect(result.contains("-> intro -> A -> {?+2} -> A ->#"))

        let sheet = try #require(TmdParser.parse(string: result))
        #expect(sheet.entries[1].name == "A")
        #expect(sheet.entries[2].name == "A")
        #expect(sheet.playback == [.name("intro"), .name("A"), .relative("+2"), .name("A")])
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

        let extracted = try TmdRefactor.extractInstrument(from: input, instrument: "Piano")
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
        #expect(sheet.entries.count == 2)
        #expect(sheet.entries.allSatisfy { $0.assignment == "Piano" })
        #expect(sheet.playback == [.name("intro"), .name("verse")])
    }

    @Test func testCLISubcommandsFormatAndRefactor() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
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
        renameInstProc.arguments = [
            "refactor", "rename-instrument", sampleTmd.path, "--from", "Violin", "--to", "Fiddle",
            "-i",
        ]
        try renameInstProc.run()
        renameInstProc.waitUntilExit()
        #expect(renameInstProc.terminationStatus == 0)
        let renamedInstContent = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(renamedInstContent.contains("verse:Fiddle@|0|{"))
        #expect(!renamedInstContent.contains("verse:Violin@|0|{"))

        // 3. Test `tmd refactor rename-section --from verse --to Chorus -i`
        let renameSecProc = Process()
        renameSecProc.executableURL = tmdURL
        renameSecProc.arguments = [
            "refactor", "rename-section", sampleTmd.path, "--from", "verse", "--to", "Chorus", "-i",
        ]
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
        extractProc.arguments = [
            "refactor", "extract-instrument", sampleTmd.path, "--instrument", "Cello", "-o",
            extractedOutput.path,
        ]
        try extractProc.run()
        extractProc.waitUntilExit()
        #expect(extractProc.terminationStatus == 0)
        let extractedContent = try String(contentsOf: extractedOutput, encoding: .utf8)
        #expect(extractedContent.contains("Chorus:Cello@|0|{"))
        #expect(!extractedContent.contains("Fiddle"))

        // 5. Test `tmd refactor transpose -s 2 -k -i`
        let transposeProc = Process()
        transposeProc.executableURL = tmdURL
        transposeProc.arguments = ["refactor", "transpose", sampleTmd.path, "-s", "2", "-k", "-i"]
        try transposeProc.run()
        transposeProc.waitUntilExit()
        #expect(transposeProc.terminationStatus == 0)
        let transposedContent = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(transposedContent.contains("?= E"))
        #expect(transposedContent.contains("2 3 4' 5"))

        // 6. Test `tmd refactor double-grid -i` and `optimize-grid -i`
        let doubleGridProc = Process()
        doubleGridProc.executableURL = tmdURL
        doubleGridProc.arguments = ["refactor", "double-grid", sampleTmd.path, "-i"]
        try doubleGridProc.run()
        doubleGridProc.waitUntilExit()
        #expect(doubleGridProc.terminationStatus == 0)
        let doubledContent = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(doubledContent.contains("<8*>"))

        let optGridProc = Process()
        optGridProc.executableURL = tmdURL
        optGridProc.arguments = ["refactor", "optimize-grid", sampleTmd.path, "-i"]
        try optGridProc.run()
        optGridProc.waitUntilExit()
        #expect(optGridProc.terminationStatus == 0)
        let optContent = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(optContent.contains("<4*>"))
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

        let doubled = try TmdRefactor.doubleGrid(source: input)
        #expect(doubled.contains("<8*>"))
        #expect(doubled.contains("| 1 - 2 - 3 - 4 - |"))
        #expect(doubled.contains("| [C] - - - 0 - D - |"))

        let doubleIssues = TmdMeasureChecker.check(source: doubled)
        #expect(doubleIssues.isEmpty)

        let halved = try TmdRefactor.halveGrid(source: doubled)
        #expect(halved.contains("<4*>"))
        #expect(halved.contains("| 1 2 3 4 |"))
        #expect(halved.contains("| [C] - 0 D |"))

        let halveIssues = TmdMeasureChecker.check(source: halved)
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

        let doubled = try TmdRefactor.doubleGrid(source: input)
        #expect(doubled.contains("<8*>"))
        #expect(doubled.contains("(3 1)%(--)"))
        let doubleIssues = TmdMeasureChecker.check(source: doubled)
        #expect(doubleIssues.isEmpty)

        let halved = try TmdRefactor.halveGrid(source: doubled)
        #expect(halved.contains("<4*>"))
        #expect(halved.contains("(3 1)%(-)"))
        let halveIssues = TmdMeasureChecker.check(source: halved)
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
            _ = try TmdRefactor.halveGrid(source: input)
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

        let duped = try TmdRefactor.duplicateTrack(
            source: input,
            sourceInstrument: "Lead",
            targetInstrument: "Synth",
            octaveShift: -1
        )
        #expect(duped.contains("verse:Lead@|0|{"))
        #expect(duped.contains("verse:Synth@|0|{"))
        #expect(duped.contains("1_ 2_ 3_ 5_"))

        let issues = TmdMeasureChecker.check(source: duped)
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

        let duped = try TmdRefactor.duplicateTrack(
            source: input,
            sourceInstrument: "Lead",
            targetInstrument: "Synth",
            section: "chorus",
            octaveShift: 1
        )
        #expect(duped.contains("chorus:Synth@|0|{"))
        #expect(duped.contains("5^ 6^ 7^ 1^^"))
        #expect(!duped.contains("verse:Synth@"))

        let issues = TmdMeasureChecker.check(source: duped)
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

        let harmonized = try TmdRefactor.generateHarmony(
            source: input,
            sourceInstrument: "Vocal",
            harmonyInstrument: "Harmony",
            intervalSteps: 2
        )
        #expect(harmonized.contains("verse:Vocal@|0|{"))
        #expect(harmonized.contains("verse:Harmony@|0|{"))
        #expect(harmonized.contains("3 4 5 3"))
        #expect(harmonized.contains("[C] - - -"))
        #expect(harmonized.contains("3 4 5 3 |"))

        let issues = TmdMeasureChecker.check(source: harmonized)
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

        let inlined = try TmdRefactor.inlineOrders(source: input)
        #expect(inlined.contains("linear:Piano@|0|{"))
        #expect(inlined.contains("-> linear ->#"))
        #expect(inlined.contains("1 2 3 4"))
        #expect(inlined.contains("5 6 7 1^"))

        let sheet = try #require(TmdParser.parse(string: inlined))
        #expect(sheet.entries.count == 1)
        #expect(sheet.entries[0].sections[0].unitGroups.count == 12)
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

        let duped = try TmdRefactor.duplicateTrack(
            source: input, sourceInstrument: "Lead", targetInstrument: "Synth", octaveShift: 1)
        #expect(duped.contains("/* Header comment */"))
        #expect(duped.contains("/* bar comment */"))
        #expect(duped.contains("/* order comment */"))
        #expect(duped.contains("verse:Lead@|0|{"))
        #expect(duped.contains("verse:Synth@|0|{"))
        #expect(duped.contains("1^ 2^ 3^ 4^"))

        let issues = TmdMeasureChecker.check(source: duped)
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

        let harmonized = try TmdRefactor.generateHarmony(
            source: input, sourceInstrument: "Vocal", harmonyInstrument: "Backing", intervalSteps: 2
        )
        #expect(harmonized.contains("/* Header comment */"))
        #expect(harmonized.contains("/* bar comment */"))
        #expect(harmonized.contains("/* order comment */"))
        #expect(harmonized.contains("verse:Vocal@|0|{"))
        #expect(harmonized.contains("verse:Backing@|0|{"))
        #expect(harmonized.contains("3 4 5 3"))

        let issues = TmdMeasureChecker.check(source: harmonized)
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

        let extracted = try TmdRefactor.extractInstrument(from: input, instrument: "Piano")
        #expect(extracted.contains("/* Header Comment */"))
        #expect(extracted.contains("/* piano comment */"))
        #expect(extracted.contains("/* verse piano */"))
        #expect(!extracted.contains(":Bass@"))
        #expect(!extracted.contains("/* bass comment */"))
        #expect(extracted.contains("/* order comment */"))
    }

    // MARK: - Optimize Grid Tests

    @Test func testOptimizeGridRepeatedlyUntilMinimalResolution() throws {
        let input = """
            ::SCORE::
            ** Optimize Grid Test **
            != 120
            ? = E
            <4/4>

            b1:Bass@|0| {
                <4*>
                | 4__ - - - | 5__ - - - | 3__ - - - | 6__ - - - |
                | 2__ - - - | 5__ - - - | 1_ - - - | 5__ - - - |
                | 4__ - - - | 5__ - - - | 3__ - - - | 6__ - - - |
                | 2__ - - - | 5__ - - - | 6__ - - - | - - - - |
            }

            -> b1 ->#
            """

        let optimized = TmdRefactor.optimizeGrid(source: input)
        #expect(optimized.contains("<1*>"))
        #expect(optimized.contains("| 4__ | 5__ | 3__ | 6__ |"))
        #expect(optimized.contains("| 2__ | 5__ | 1_ | 5__ |"))
        #expect(optimized.contains("| 4__ | 5__ | 3__ | 6__ |"))
        #expect(optimized.contains("| 2__ | 5__ | 6__ | - |"))

        let issues = TmdMeasureChecker.check(source: optimized)
        #expect(issues.isEmpty)
    }

    @Test func testOptimizeGridRestrictedToSectionOrInstrument() throws {
        let input = """
            ::SCORE::
            ** Multi-Track Optimize Test **
            != 120
            ?= C
            <4/4>

            verse:Bass@|0|{
                <4*>
                | 1_ - - - | 5__ - - - |
            }

            verse:Lead@|0|{
                <4*>
                | 1 2 3 4 | 5 6 7 1^ |
            }

            -> verse ->#
            """

        let optBass = TmdRefactor.optimizeGrid(
            source: input, target: TmdRefactorTarget(instrument: "Bass"))
        #expect(optBass.contains("<1*>"))
        #expect(optBass.contains("| 1_ | 5__ |"))
        #expect(optBass.contains("<4*>"))
        #expect(optBass.contains("| 1 2 3 4 | 5 6 7 1^ |"))
        #expect(TmdMeasureChecker.check(source: optBass).isEmpty)
    }

    @Test func testOptimizeGridGlobalAcrossMultipleParagraphs() throws {
        let input = """
            ::SCORE::
            ** Global Optimize Test **
            != 120
            ?= C
            <4/4>

            verse:Bass@|0|{
                <4*>
                | 1_ - - - | 5__ - - - |
            }

            verse:Lead@|0|{
                <4*>
                | 1 2 3 4 | 5 6 7 1^ |
            }

            -> verse ->#
            """

        let optGlobal = TmdRefactor.optimizeGrid(source: input)
        #expect(optGlobal.contains("verse:Bass@|0|{"))
        #expect(optGlobal.contains("<1*>"))
        #expect(optGlobal.contains("| 1_ | 5__ |"))
        #expect(optGlobal.contains("verse:Lead@|0|{"))
        #expect(optGlobal.contains("<4*>"))
        #expect(optGlobal.contains("| 1 2 3 4 | 5 6 7 1^ |"))
        #expect(TmdMeasureChecker.check(source: optGlobal).isEmpty)
    }

    // MARK: - Transpose Tests

    @Test func testTransposeNotesAndChordsUpBySemitones() throws {
        let input = "| 1 2 3 4 | [C] - [Am] - |"
        let transposed = TmdRefactor.transpose(source: input, semitones: 2, keySignature: "C")
        #expect(transposed.contains("| 2 3 4' 5 |"))
        #expect(transposed.contains("[D] - [Bm] -"))
    }

    @Test func testTransposeNotesAndChordsDownBySemitones() throws {
        let input = "| 1 3 5 1^ | [C] - [G7] - |"
        let transposed = TmdRefactor.transpose(source: input, semitones: -1, keySignature: "C")
        #expect(transposed.contains("| 7_ 2' 4' 7 |"))
        #expect(transposed.contains("[B] - [F#7] -"))
    }

    @Test func testTransposeDiatonically() throws {
        let input = "| 1 2 3 4 | 5 6 7 1^ | [1] - [4] [5] |"
        let transposed = TmdRefactor.transpose(source: input, diatonicSteps: 1)
        #expect(transposed.contains("| 2 3 4 5 | 6 7 1^ 2^ |"))
        #expect(transposed.contains("[2] - [5] [6]"))
    }

    @Test func testTransposeUsesLexerBoundariesForTiedNotes() throws {
        let source = "| 1-- 2^-- |"
        let lexed = Lexer(string: source).tokenize()

        #expect(lexed == [
            .pipe, .note(Note(accidental: .natural, degree: .c, octave: 0)), .tie, .tie,
            .note(Note(accidental: .natural, degree: .d, octave: 1)), .tie, .tie,
            .pipe, .eof,
        ])

        let transposed = TmdRefactor.transpose(source: source, semitones: 2, keySignature: "C")
        #expect(transposed == "| 2-- 3^-- |\n")
    }

    @Test func testTransposeCompleteScoreAndUpdateKeySignature() throws {
        let input = """
            ::SCORE::
            /* My intro comment */
            ** Transpose Song **
            != 120
            ?= C
            <4/4>

            verse:Lead@|0|{
                <4*>
                | 1 2 3 1 | /* bar comment */
                | [C] - [G] - |
            }

            -> verse ->#
            """

        let transposed = TmdRefactor.transpose(
            source: input, semitones: 2, updateKeySignature: true)
        #expect(transposed.contains("?= D"))
        #expect(transposed.contains("/* My intro comment */"))
        #expect(transposed.contains("/* bar comment */"))
        #expect(transposed.contains("verse:Lead@|0|{"))
        #expect(transposed.contains("-> verse ->#"))

        let issues = TmdMeasureChecker.check(source: transposed)
        #expect(issues.isEmpty)
    }

    @Test func testTransposeRestrictedToSectionAndInstrument() throws {
        let input = """
            ::SCORE::
            ** Multi-Track Score **
            != 120
            ?= C
            <4/4>

            verse:Lead@|0|{
                <4*>
                | 1 2 3 4 |
            }

            verse:Bass@|0|{
                <4*>
                | 1_ - 5_ - |
            }

            chorus:Lead@|0|{
                <4*>
                | 5 6 7 1^ |
            }

            -> verse -> chorus ->#
            """

        let transposed = TmdRefactor.transpose(
            source: input,
            semitones: 12,
            target: TmdRefactorTarget(section: "verse", instrument: "Lead")
        )

        #expect(transposed.contains("verse:Lead@|0|{\n    <4*>\n    | 1^ 2^ 3^ 4^ |"))
        #expect(transposed.contains("verse:Bass@|0|{\n    <4*>\n    | 1_ - 5_ - |"))
        #expect(transposed.contains("chorus:Lead@|0|{\n    <4*>\n    | 5 6 7 1^ |"))
    }

    @Test func testRefactorTargetResolveSSOT() {
        #expect(TmdRefactorTarget.resolve(section: nil, instrument: nil) == nil)
        let secOnly = TmdRefactorTarget.resolve(section: "verse", instrument: nil)
        #expect(secOnly?.section == "verse")
        #expect(secOnly?.instrument == nil)
        let instOnly = TmdRefactorTarget.resolve(section: nil, instrument: "Piano")
        #expect(instOnly?.section == nil)
        #expect(instOnly?.instrument == "Piano")
    }

    @Test("Issue #40: Refactoring supports [pitchMode=fixed] headers and key= header formatting")
    func testFixedPitchRefactoringAndKeyHeaderFormatting() throws {
        let input = """
            ::SCORE::
            != 120
            ?= C
            key=Am
            <4/4>

            verse:Drums [pitchMode=fixed] @|0|{
                <4*>
                | 1 2 3 4 |
            }

            -> verse ->#
            """
        let renamed = try TmdRefactor.renameInstrument(in: input, from: "Drums", to: "Percussion")
        #expect(renamed.contains("verse:Percussion[pitchMode=fixed]@|0|{"))

        let doubled = try TmdRefactor.doubleGrid(source: input)
        #expect(doubled.contains("<8*>"))
        #expect(doubled.contains("| 1 - 2 - 3 - 4 - |"))
        #expect(doubled.contains("key= Am"))
    }

    @Test("Issue #40: inlineOrders preserves per-section noteLength, directives, declaredKey, and pitchMode")
    func testInlineOrdersPreservesSectionsDirectivesAndDeclaredKey() throws {
        let input = """
            ::SCORE::
            != 120
            ?= C
            key= Am
            <4/4>

            partA:Piano [pitchMode=fixed] @|0|{
                <4*>
                | {!= 140} 1 2 3 4 |
            }

            partB:Piano [pitchMode=fixed] @|0|{
                <8*>
                | 1 2 3 4 5 6 7 1^ |
            }

            -> partA -> partB ->#
            """
        let inlined = try TmdRefactor.inlineOrders(source: input)
        #expect(inlined.contains("key= Am"))
        #expect(inlined.contains("linear:Piano[pitchMode=fixed]@|0|{"))
        #expect(inlined.contains("<4*>"))
        #expect(inlined.contains("<8*>"))
        #expect(inlined.contains("{!=140}"))
        #expect(TmdMeasureChecker.check(source: inlined).isEmpty)
    }

    @Test("Issue #40: doubleGrid splits compact unspaced note runs like 12 into 1 - 2 -")
    func testDoubleGridSplitsCompactUnspacedNoteRuns() throws {
        let input = """
            ::SCORE::
            != 120
            ?= C
            <4/4>

            verse:Piano@|0|{
                <4*>
                | 12 3 4 |
            }

            -> verse ->#
            """
        let doubled = try TmdRefactor.doubleGrid(source: input)
        #expect(doubled.contains("| 1 - 2 - 3 - 4 - |"))
        #expect(TmdMeasureChecker.check(source: doubled).isEmpty)
    }

    @Test("Issue #40: TmdMeasureLexerFallback handles [pitchMode=fixed], compound percussion/dot-ties, and currentBeat")
    func testMeasureLexerFallbackFixedPitchPercussionAndBeat() {
        // Broken syntax at end (unclosed -> () forces TmdMeasureChecker to use TmdMeasureLexerFallback
        let source = """
            ::SCORE::
            != 120
            ?= C
            <4/4>

            verse:Drums [pitchMode=fixed] @|0|{
                <4*>
                | {<3/4>} X-X- .. |
            }

            -> verse -> (play ->#
            """
        let issues = TmdMeasureChecker.check(source: source)
        #expect(issues.count == 1)
        #expect(issues[0].expectedUnits == 3)
        #expect(issues[0].actualUnits == 6)
        #expect(issues[0].beat == Beat(count: 3, noteValue: 4))
    }

    @Test("Issue #40: TonalityAnalyzer detects [pitchMode=fixed], preserves modulation across insufficient section, and PitchRangeAnalyzer tracks mid-section meter change")
    func testTonalityAndPitchRangeAnalyzersFixedPitchAndModulation() throws {
        let input = """
            ::SCORE::
            != 120
            ?= C
            <2/4>

            secA:Piano [pitchMode=fixed] @|0|{
                <4*>
                | 1 3 | 5 1^ | 1 3 | 5 1^ |
            }

            secEmpty:Piano [pitchMode=fixed] @|0|{
                <4*>
                | 0 0 |
            }

            secB:Piano [pitchMode=fixed] @|0|{
                <4*>
                | 2 4' | {<4/4>} 6 2^ 2 5^ |
            }

            -> secA -> secEmpty -> secB ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        let report = TmdSongInspector.inspect(sheet: sheet)
        let tonality = try #require(report.tonality)
        #expect(tonality.sections[0].playbackContext.fixedPitch == true)
        #expect(!tonality.inferredModulationPath.isEmpty)

        // secA: 4 measures of 2/4 (measures 1..4)
        // secEmpty: 1 measure of 2/4 (measure 5)
        // secB: starts at measure 6 (1 measure of 2/4 = 2 beats), then {<4/4>} measure 7 has 5^ at beat offset 5 (3 beats into measure 7 -> still measure 7, not measure 8!)
        let pianoRange = try #require(report.instrumentRanges.first { $0.instrument == "Piano" })
        #expect(pianoRange.highestNote.measure == 7)
    }

    @Test("Issue #44: CLI refactor accepts negative and quoted integer options (--interval -2, --octave -1, --semitones -2, --diatonic -1) and VS Code extension uses --key=value")
    func testIssue44NegativeRefactorCLIOptionsAndVSCodeExtension() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tmd_issue44_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleTmd = tempDir.appendingPathComponent("song.tmd")
        let initialScore = """
            ::SCORE::
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 3 4 5 6 |
            }

            -> verse ->#
            """
        try initialScore.write(to: sampleTmd, atomically: true, encoding: .utf8)

        guard let tmdURL = TmdTestHelper.findTmdExecutable() else {
            Issue.record("tmd binary must be built and available")
            return
        }

        func runTmd(_ args: [String]) throws -> Int32 {
            let proc = Process()
            proc.executableURL = tmdURL
            proc.arguments = args
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus
        }

        // 1. Space-separated --interval -2
        #expect(try runTmd([
            "refactor", "generate-harmony", sampleTmd.path,
            "--source", "Vocal", "--target", "HarmonyDown", "--interval", "-2", "-i",
        ]) == 0)
        var text = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(text.contains("verse:HarmonyDown@|0|{"))
        #expect(text.contains("1 2 3 4 |"))

        // 2. Quoted --interval "\"-2\""
        #expect(try runTmd([
            "refactor", "generate-harmony", sampleTmd.path,
            "--source", "Vocal", "--target", "HarmonyQuoted", "--interval", "\"-2\"", "-i",
        ]) == 0)
        text = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(text.contains("verse:HarmonyQuoted@|0|{"))

        // 3. Space-separated --octave -1
        #expect(try runTmd([
            "refactor", "duplicate-track", sampleTmd.path,
            "--source", "Vocal", "--target", "VocalLow", "--octave", "-1", "-i",
        ]) == 0)
        text = try String(contentsOf: sampleTmd, encoding: .utf8)
        #expect(text.contains("verse:VocalLow@|0|{"))
        #expect(text.contains("3_ 4_ 5_ 6_ |"))

        // 4. Space-separated --semitones -2 and --diatonic -1
        #expect(try runTmd([
            "refactor", "transpose", sampleTmd.path,
            "--semitones", "-2", "--instrument", "Vocal", "-i",
        ]) == 0)
        #expect(try runTmd([
            "refactor", "transpose", sampleTmd.path,
            "--diatonic", "-1", "--instrument", "Vocal", "-i",
        ]) == 0)

        // 5. VS Code extension.js uses --octave=${oct} and --interval=${interval}
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let extensionJS = try String(
            contentsOf: packageRoot.appendingPathComponent("editor/vscode/extension.js"),
            encoding: .utf8
        )
        #expect(extensionJS.contains("`--octave=${oct}`"))
        #expect(extensionJS.contains("`--interval=${interval}`"))
        #expect(!extensionJS.contains("args.push('--octave',"))
        #expect(!extensionJS.contains("args.push('--interval',"))
    }
}
