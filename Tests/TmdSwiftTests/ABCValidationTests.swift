import Foundation
import Testing
import TmdABC

@testable import TmdSwift

@Suite("ABC Validation Tests")
struct ABCValidationTests {

    @Test func testABCHeadersAndVoices() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let sheet = try TmdParserIO.parseThrowing(url: sampleURL)

        let abc = TmdABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("X:1"))
        #expect(abc.contains("T:三天三夜"))
        #expect(abc.contains("M:4/4"))
        #expect(abc.contains("L:1/16"))
        #expect(abc.contains("K:Bb"))
        #expect(abc.contains("V:V1 name=\"CHORD\""))
    }

    @Test func testABCBarlinesAndMeasureDurations() throws {
        let tmd = """
            ::SCORE::
            ** ABC Measure Test **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                1 2 3 4
                5 6 7 1^
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)

        let abc = TmdABCGenerator.generateABC(from: sheet)

        let v1Section = abc.components(separatedBy: "[V:V1]").last ?? ""
        let body = v1Section.components(separatedBy: "[V:").first ?? ""
        let measures =
            body
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        #expect(
            measures.count >= 2,
            "Expected at least 2 measures separated by barlines, got \(measures.count)")

        let noteRegex = try NSRegularExpression(pattern: #"(?:[A-Ga-gz\^=_]+|"[^"]*"z)(\d*)"#)

        for (mIdx, measureStr) in measures.enumerated() {
            let nsStr = measureStr as NSString
            let matches = noteRegex.matches(
                in: measureStr, range: NSRange(location: 0, length: nsStr.length))
            var totalUnits = 0
            for match in matches {
                let numStr = nsStr.substring(with: match.range(at: 1))
                let count = numStr.isEmpty ? 1 : (Int(numStr) ?? 1)
                totalUnits += count
            }
            #expect(
                totalUnits == 16,
                "Measure \(mIdx + 1) in ABC has \(totalUnits) units of 1/16, expected 16"
            )
        }
    }

    @Test func testABCPitchInKeySignatures() throws {
        // In G major, F is naturally sharped by K:G
        let tmdG = """
            ::SCORE::
            ** Key G Test **
            != 120
            ?= G
            <4/4>

            A:Piano@|0|{
                <4*>
                1 7 7, 1
            }
            -> A ->#
            """
        let sheetG = try TmdParser.parseThrowing(string: tmdG)
        let abcG = TmdABCGenerator.generateABC(from: sheetG)
        #expect(abcG.contains("K:G"))
        // Degree 7 in G major is F# -> under K:G written as f4 (not ^f4)
        // Degree 7, in G major is F natural -> under K:G written as =f4
        #expect(abcG.contains("f4") || abcG.contains("F4"))
        #expect(!abcG.contains("^f4") && !abcG.contains("^F4"))
        #expect(abcG.contains("=f4") || abcG.contains("=F4"))

        // For A' (Bb), ABC should use standard K:Bb instead of non-standard K:A#
        let tmdBb = """
            ::SCORE::
            ** Key Bb Test **
            != 120
            ?= A'
            <4/4>

            A:Piano@|0|{
                <4*>
                1 2 3 4
            }
            -> A ->#
            """
        let sheetBb = try TmdParser.parseThrowing(string: tmdBb)
        let abcBb = TmdABCGenerator.generateABC(from: sheetBb)
        #expect(abcBb.contains("K:Bb"))
        // In K:Bb, Degree 1 is Bb -> under K:Bb it is written as b4 / B4 without ^ or _
        #expect(abcBb.contains("b4") || abcBb.contains("B4"))
        #expect(!abcBb.contains("^a4") && !abcBb.contains("^A4"))
    }

    @Test func testABCRelativeKeyModulation() throws {
        let tmd = """
            ::SCORE::
            ** ABC Relative Key **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                1 2 3 4
                {?+2}
                1 2 3 4
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let abc = TmdABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("K:C"))
        #expect(abc.contains("K:D"))
    }

    @Test func testABCTempoBeatUnitBasedOnTimeSignature() throws {
        // Compound meter: 6/8 -> Q:3/8=80
        let tmdCompound = """
            ::SCORE::
            ** Compound Meter ABC **
            != 120
            ?= C
            <6/8>

            A:Piano@|0|{
                <8*>
                1 2 3 4 5 6
                {!= 150}
                1 2 3 4 5 6
            }
            -> A ->#
            """
        let sheetCompound = try TmdParser.parseThrowing(string: tmdCompound)
        let abcCompound = TmdABCGenerator.generateABC(from: sheetCompound)

        #expect(abcCompound.contains("Q:3/8=80"))
        #expect(abcCompound.contains("Q:3/8=100"))

        // Cut time: 2/2 -> Q:1/2=60
        let tmdCutTime = """
            ::SCORE::
            ** Cut Time ABC **
            != 120
            ?= C
            <2/2>

            A:Piano@|0|{
                <2*>
                1 2
            }
            -> A ->#
            """
        let sheetCutTime = try TmdParser.parseThrowing(string: tmdCutTime)
        let abcCutTime = TmdABCGenerator.generateABC(from: sheetCutTime)

        #expect(abcCutTime.contains("Q:1/2=60"))

        // 3/8 -> Q:1/8=240
        let tmdEighthTime = """
            ::SCORE::
            ** Simple Triple Eighth ABC **
            != 120
            ?= C
            <3/8>

            A:Piano@|0|{
                <8*>
                1 2 3
            }
            -> A ->#
            """
        let sheetEighthTime = try TmdParser.parseThrowing(string: tmdEighthTime)
        let abcEighthTime = TmdABCGenerator.generateABC(from: sheetEighthTime)

        #expect(abcEighthTime.contains("Q:1/8=240"))
    }

    @Test func testExplicitKeyAndDynamicsInABC() throws {
        let tmd = """
            ::SCORE::
            ** Explicit Key & Dynamics **
            != 120
            ?= D
            key= Bm
            <4/4>

            A:Piano@|0|{
                <4*>
                | {p} 1 2 {f} 3 4 |
                | {key= F#m} 1 2 3 4 |
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let abc = TmdABCGenerator.generateABC(from: sheet)

        // Header declared key= Bm -> K:Bm
        #expect(abc.contains("K:Bm"))

        // Section dynamics directives
        #expect(abc.contains("!p!"))
        #expect(abc.contains("!f!"))

        // Section inline directive {key= F#m} -> K:F#m
        #expect(abc.contains("K:F#m"))
        // In measure 2 under K:F#m (3 sharps: F#, C#, G#), degree 4 in ?= D is G4 natural -> must emit =G4
        #expect(abc.contains("=G4"))
    }

    @Test func testABCOctaveAndIntraMeasureAccidentalMemory() throws {
        // 1. In ?= D, degree 7_ is C#4 (C4) and 7,_ is C4 natural (=C4, NOT =C,4 in octave 3 from double-counted delta).
        let tmdD = """
            ::SCORE::
            ** ABC Octave in D **
            != 120
            ?= D
            <4/4>

            A:Piano@|0|{
                <4*>
                | 7_ 7,_ 7_ 1 |
            }
            -> A ->#
            """
        let sheetD = try TmdParser.parseThrowing(string: tmdD)
        let abcD = TmdABCGenerator.generateABC(from: sheetD)
        // First 7_ is C4, second 7,_ is =C4 (octave 4, not =C,4), third 7_ in same measure must re-sharp as ^C4!
        #expect(abcD.contains("C4 =C4 ^C4 D4"))

        // 2. Intra-measure accidental cancellation and octave boundary in C major:
        // | 1' 1 1, 7' | -> ^C4 =C4 _C4 ^B4
        let tmdC = """
            ::SCORE::
            ** ABC Intra-Measure Memory **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1' 1 1, 7' |
                | 1_ 1 1^ 1^^ |
            }
            -> A ->#
            """
        let sheetC = try TmdParser.parseThrowing(string: tmdC)
        let abcC = TmdABCGenerator.generateABC(from: sheetC)
        #expect(abcC.contains("^C4 =C4 _C4 ^B4"))
        #expect(abcC.contains("C,4 C4 c4 c'4"))
    }

    @Test(
        "Issue #41: ABC preserves simultaneous chord + note events and recognizes min/maj key suffixes"
    )
    func testABCSimultaneousChordAndNoteAndMinKey() throws {
        let tmd = """
            ::SCORE::
            != 120
            ?= C
            key= Amin
            <4/4>

            A:Piano@|0|{
                <4*>
                | [C] 2 3 4 |
            }
            A:Piano@|0|{
                <4*>
                | 5 - - - |
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let abc = TmdABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("K:Am"))
        #expect(abc.contains("\"C\"z4"))
        #expect(abc.contains("G"))
    }

    @Test(
        "Issue #57: ABC preserves sub-16th durations, tuplets, bracketed inline directives, and golden_case measure conservation"
    )
    func testABCSub16thTupletsInlineBracketsAndGoldenCaseConservation() throws {
        // 1. Sub-16th durations (<32*>, <64*>, <1024*>), tuplets (3:1, 5:3, 7:5, 11:7), and inline directives
        let tmd = """
            ::SCORE::
            ** Sub-16th & Tuplet ABC Test **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <32*>
                1 2 3 4
                <64*>
                1 2 3 4 5 6 7 1^
                <4*>
                1 2 3
                | (1 2 3)%(-) (1 2 3 4 5)%(---) |
                | {<5/4>} {!= 150} {?= D} 1 2 3 4 5 |
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let abc = TmdABCGenerator.generateABC(from: sheet)

        // Sub-16th notes: <32*> = 1/2 of L:1/16 -> "/2", <64*> = 1/4 of L:1/16 -> "/4"
        #expect(abc.contains("C/2 D/2 E/2 F/2"))
        #expect(abc.contains("C/4 D/4 E/4 F/4 G/4 A/4 B/4 c/4"))

        // Tuplets: (1 2 3)%(-) in <4*> -> each note is 1/3 quarter = 4/3 of L:1/16 -> "4/3"
        // (1 2 3 4 5)%(---) in <4*> -> each note is 3/5 quarter = 12/5 of L:1/16 -> "12/5"
        #expect(abc.contains("C4/3 D4/3 E4/3"))
        #expect(abc.contains("C12/5 D12/5 E12/5 F12/5 G12/5"))

        // Inline directives in tune body must be bracketed per ABC v2.1 Section 3.2
        #expect(abc.contains("[M:5/4]"))
        #expect(abc.contains("[Q:1/4=150]"))
        #expect(abc.contains("[K:D]"))

        // 2. Full golden_case.tmd measure duration conservation across all voices and measures
        let goldenURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/golden_case/golden_case.tmd")
        let goldenSheet = try TmdParserIO.parseThrowing(url: goldenURL)
        let goldenABC = TmdABCGenerator.generateABC(from: goldenSheet)

        let voiceBlocks = goldenABC.components(separatedBy: "[V:").dropFirst()
        #expect(!voiceBlocks.isEmpty)

        // Regex matching an ABC event (chord group [...], quoted chord "..."z, or single note/rest) with optional p/q or /q or p suffix
        let eventRegex = try NSRegularExpression(
            pattern: #"(?:\[[A-Ga-gz\^=_',]+\]|"[^"]*"z|[A-Ga-gz\^=_',]+)(\d+)?(?:/(\d+))?-?"#
        )
        let meterRegex = try NSRegularExpression(pattern: #"\[M:(\d+)/(\d+)\]"#)
        let inlineFieldRegex = try NSRegularExpression(pattern: #"\[[A-Za-z]:[^\]]*\]"#)
        let decorationRegex = try NSRegularExpression(pattern: #"![^!]+!"#)

        for block in voiceBlocks {
            let lines = block.components(separatedBy: .newlines)
            let voiceId = lines.first?.replacingOccurrences(of: "]", with: "") ?? ""
            let musicBody = lines.dropFirst()
                .filter { !$0.hasPrefix("%%") }
                .joined(separator: " ")
            let measures =
                musicBody
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var expectedSixteenths = 16.0  // Initial M:4/4 -> 16 sixteenth notes
            for (mIdx, measureStr) in measures.enumerated() {
                let nsMeasure = measureStr as NSString
                let meterMatches = meterRegex.matches(
                    in: measureStr, range: NSRange(location: 0, length: nsMeasure.length))
                for mMatch in meterMatches {
                    if let num = Double(nsMeasure.substring(with: mMatch.range(at: 1))),
                        let den = Double(nsMeasure.substring(with: mMatch.range(at: 2))),
                        den > 0
                    {
                        expectedSixteenths = num * 16.0 / den
                    }
                }

                // Strip bracketed inline fields and !decorations! before scanning note events
                var stripped = inlineFieldRegex.stringByReplacingMatches(
                    in: measureStr,
                    range: NSRange(location: 0, length: nsMeasure.length),
                    withTemplate: " "
                )
                stripped = decorationRegex.stringByReplacingMatches(
                    in: stripped,
                    range: NSRange(location: 0, length: (stripped as NSString).length),
                    withTemplate: " "
                )

                let nsStripped = stripped as NSString
                let eventMatches = eventRegex.matches(
                    in: stripped, range: NSRange(location: 0, length: nsStripped.length))
                var totalSixteenths = 0.0
                for evMatch in eventMatches {
                    let numRange = evMatch.range(at: 1)
                    let denRange = evMatch.range(at: 2)
                    let num =
                        numRange.location != NSNotFound
                        ? (Double(nsStripped.substring(with: numRange)) ?? 1.0) : 1.0
                    let den =
                        denRange.location != NSNotFound
                        ? (Double(nsStripped.substring(with: denRange)) ?? 1.0) : 1.0
                    totalSixteenths += num / den
                }

                #expect(
                    abs(totalSixteenths - expectedSixteenths) < 0.05,
                    "Voice \(voiceId) measure \(mIdx + 1) has \(totalSixteenths) sixteenths, expected \(expectedSixteenths): \(measureStr.prefix(80))"
                )
            }
        }
    }

    @Test("ABC leaves composer blank when score has no composer metadata")
    func testABCComposerHeaderOmittedWhenNotSpecified() throws {
        let tmdWithoutComposer = """
            ::SCORE::
            ** No Composer Song **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
            }
            -> A ->#
            """
        let sheetWithoutComposer = try TmdParser.parseThrowing(string: tmdWithoutComposer)
        let abcWithoutComposer = TmdABCGenerator.generateABC(from: sheetWithoutComposer)
        #expect(!abcWithoutComposer.contains("aguai"))
        #expect(!abcWithoutComposer.contains("\nC:"))

        let tmdWithComposer = """
            ::SCORE::
            ** Custom Composer Song **
            ~ "曲：王小明"
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
            }
            -> A ->#
            """
        let sheetWithComposer = try TmdParser.parseThrowing(string: tmdWithComposer)
        let abcWithComposer = TmdABCGenerator.generateABC(from: sheetWithComposer)
        #expect(abcWithComposer.contains("\nC:曲：王小明\n"))
    }

    @Test("Issue #63: ABC output never contains blank lines inside the tune")
    func testABCNeverContainsBlankLinesInsideTune() throws {
        // 1. Multi-track score (without composer metadata)
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let sampleSheet = try TmdParserIO.parseThrowing(url: sampleURL)
        let sampleABC = TmdABCGenerator.generateABC(from: sampleSheet)
        #expect(
            !sampleABC.contains("\n\n"),
            "ABC tune must not contain blank lines that prematurely terminate the tune"
        )

        // 2. Score where composer metadata contains trailing/blank lines or tracks have empty sections
        let tmdWithNewlineMetadata = """
            ::SCORE::
            ** Blank Line ABC Test **
            ~ "曲：王小明
            "
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
            }
            -> A ->#
            """
        let newlineMetaSheet = try TmdParser.parseThrowing(string: tmdWithNewlineMetadata)
        let newlineMetaABC = TmdABCGenerator.generateABC(from: newlineMetaSheet)
        #expect(
            !newlineMetaABC.contains("\n\n"),
            "ABC tune must not emit blank lines even when metadata contains trailing newlines"
        )
    }
}



