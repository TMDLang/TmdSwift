import Foundation
import Testing
import TmdLilyPond

@testable import TmdSwift

@Suite("LilyPond Validation Tests")
struct LilyPondValidationTests {

    @Test func testLilyPondUniqueIdentifiers() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let sheet = try TmdParserIO.parseThrowing(url: sampleURL)

        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        let lines = ly.components(separatedBy: "\n")
        var definedVariables: [String] = []
        let regex = try NSRegularExpression(
            pattern: #"^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(?:\\drummode\s*)?\{"#)

        for line in lines {
            let nsLine = line as NSString
            let matches = regex.matches(
                in: line, range: NSRange(location: 0, length: nsLine.length))
            if let match = matches.first {
                let varName = nsLine.substring(with: match.range(at: 1))
                if varName != "global" {
                    definedVariables.append(varName)
                }
            }
        }

        #expect(!definedVariables.isEmpty)
        let uniqueVariables = Set(definedVariables)
        #expect(
            uniqueVariables.count == definedVariables.count,
            "Found duplicate LilyPond variable identifiers: \(definedVariables)"
        )
    }

    @Test func testLilyPondValidDurationsOnly() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let sheet = try TmdParserIO.parseThrowing(url: sampleURL)

        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        let tokenRegex = try NSRegularExpression(
            pattern: #"(?:[a-g][a-z',]*|>|r|hh|sn|toml)(\d+)(\.*)"#)
        let nsLy = ly as NSString
        let matches = tokenRegex.matches(in: ly, range: NSRange(location: 0, length: nsLy.length))

        let validDurations: Set<Int> = [1, 2, 4, 8, 16, 32, 64, 128]
        var invalidMatches: [String] = []

        for match in matches {
            let durString = nsLy.substring(with: match.range(at: 1))
            if let dur = Int(durString), !validDurations.contains(dur) {
                invalidMatches.append(nsLy.substring(with: match.range))
            }
        }

        #expect(
            invalidMatches.isEmpty,
            "LilyPond generated invalid duration tokens (non-powers-of-2): \(invalidMatches.prefix(10))"
        )
    }

    @Test func testLilyPondMeasureBarlinesPresent() throws {
        let tmd = """
            ::SCORE::
            ** Barline Test **
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

        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)
        let barlineCount = ly.components(separatedBy: "|").count - 1
        #expect(
            barlineCount >= 2,
            "Expected at least 2 barlines in multi-measure LilyPond score, got \(barlineCount)")
    }

    @Test func testLilyPondPercussionMappingAndRelativeKey() throws {
        let tmd = """
            ::SCORE::
            ** Percussion and Relative Key Test **
            != 120
            ?= C
            <4/4>

            A:Drums@|0|{
                <4*>
                | D S X O | T C B S |
            }
            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
                {?+2}
                | 1 2 3 4 |
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        // Drum tokens
        #expect(ly.contains("bd4"))
        #expect(ly.contains("sn4"))
        #expect(ly.contains("hh4"))
        #expect(ly.contains("hho4"))
        #expect(ly.contains("toml4"))
        #expect(ly.contains("cymc4"))

        // Relative key: C + 2 semitones = D major -> \key d \major
        #expect(ly.contains("\\key d \\major"))
    }

    @Test func testLilyPondTempoBeatUnitBasedOnTimeSignature() throws {
        // Compound meter: 6/8 -> \tempo 4. = 80
        let tmdCompound = """
            ::SCORE::
            ** Compound Meter LilyPond **
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
        let lyCompound = TmdLilyPondGenerator.generateLilyPond(from: sheetCompound)

        #expect(lyCompound.contains("\\tempo 4. = 80"))
        #expect(lyCompound.contains("\\tempo 4. = 100"))

        // Cut time: 2/2 -> \tempo 2 = 60
        let tmdCutTime = """
            ::SCORE::
            ** Cut Time LilyPond **
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
        let lyCutTime = TmdLilyPondGenerator.generateLilyPond(from: sheetCutTime)

        #expect(lyCutTime.contains("\\tempo 2 = 60"))

        // 3/8 -> \tempo 8 = 240
        let tmdEighthTime = """
            ::SCORE::
            ** Simple Triple Eighth LilyPond **
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
        let lyEighthTime = TmdLilyPondGenerator.generateLilyPond(from: sheetEighthTime)

        #expect(lyEighthTime.contains("\\tempo 8 = 240"))
    }

    @Test func testExplicitKeyAndDynamicsInLilyPond() throws {
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
        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        // Header declared key= Bm -> \key b \minor
        #expect(ly.contains("\\key b \\minor"))

        // Section dynamics directives
        #expect(ly.contains("\\p"))
        #expect(ly.contains("\\f"))

        // Section inline directive {key= F#m} -> \key fis \minor
        #expect(ly.contains("\\key fis \\minor"))
    }

    @Test func testLilyPondFlatKeyAndAccidentalSpelling() throws {
        let tmd = """
            ::SCORE::
            ** LilyPond Flat Key Spelling **
            != 120
            ?= F
            key= F
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
                | [4] - - - |
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        #expect(ly.contains("\\key f \\major"))
        // In F major, 1 2 3 4 = F4 G4 A4 Bb4 -> f'4 g'4 a'4 bes'4 (never ais'4)
        #expect(ly.contains("f'4 g'4 a'4 bes'4"))
        #expect(!ly.contains("ais'4"))
        // Chord [4] in F major is Bb major triad -> <bes d' f'>1 (never ais)
        #expect(ly.contains("bes"))
        #expect(!ly.contains("ais"))

        // Explicit flat and octave boundary in C major: 1, (Cb4 -> ces') and 7, (Bb4 -> bes')
        let tmdC = """
            ::SCORE::
            ** LilyPond Chromatic Flats **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1, 3, 7, 7' |
            }
            -> A ->#
            """
        let sheetC = try TmdParser.parseThrowing(string: tmdC)
        let lyC = TmdLilyPondGenerator.generateLilyPond(from: sheetC)
        #expect(lyC.contains("ces'4"))
        #expect(lyC.contains("es'4"))
        #expect(lyC.contains("bes'4"))
        #expect(lyC.contains("bis'4"))
    }

    @Test("Issue #41: LilyPond preserves simultaneous chord + note events and recognizes min/maj key suffixes")
    func testLilyPondSimultaneousChordAndNoteAndMinKey() throws {
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
        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)
        #expect(ly.contains("\\key a \\minor"))
        // Beat 1 has simultaneous [C] (<c e g>4) and note 5 (g'1); neither should be dropped!
        #expect(ly.contains("<c e g>4"))
        #expect(ly.contains("g'1"))
    }

    @Test("Issue #58: LilyPond attaches postfix dynamics, divides multi-stroke percussion durations, and conserves sub-64th/tuplet measure durations across golden_case")
    func testLilyPondSub64thTupletsPercussionAndPostfixDynamics() throws {
        let oneLine256 = Array(repeating: "1 2 3 5", count: 64).joined(separator: " ")
        let tmd = """
            ::SCORE::
            ** LilyPond Precision Test **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | {p} 1 2 {f} 3 {ff} 4 |
                | (1 2 3)%(-) (1 2 3 4 5)%(---) |
                <256*>
                | \(oneLine256) |
            }
            A:Drums@|0|{
                <4*>
                | (BS) (XxTS) D S |
                | 0 0 0 0 |
                | 0 0 0 0 |
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        // 1. Postfix dynamics attached directly to note tokens (not standalone prefix \p)
        #expect(ly.contains("c'4\\p d'4 e'4\\f f'4\\ff"))
        #expect(!ly.contains("\\p c'4"))

        // 2. Multi-stroke percussion divides beat duration across strokes
        #expect(ly.contains("bd8 sn8 hh16 hh16 toml16 sn16 bd4 sn4"))

        // 3. Tuplets use exact rational multipliers and <256*> uses 256th notes
        #expect(ly.contains("c'8*2/3 d'8*2/3 e'8*2/3"))
        #expect(ly.contains("c'4*3/5 d'4*3/5 e'4*3/5 f'4*3/5 g'4*3/5"))
        #expect(ly.contains("c'256 d'256 e'256 g'256"))

        // 4. Full golden_case.tmd measure duration conservation across all tracks and measures
        let goldenURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/golden_case/golden_case.tmd")
        let goldenSheet = try TmdParserIO.parseThrowing(url: goldenURL)
        let goldenLy = TmdLilyPondGenerator.generateLilyPond(from: goldenSheet)

        // Extract each track block: VarName = [\drummode] { \global ... }
        let blockRegex = try NSRegularExpression(
            pattern: #"([A-Za-z][A-Za-z0-9_]*)\s*=\s*(?:\\drummode\s*)?\{\s*\\global\s*([\s\S]*?)\n\}"#
        )
        let nsGolden = goldenLy as NSString
        let blockMatches = blockRegex.matches(
            in: goldenLy, range: NSRange(location: 0, length: nsGolden.length))
        #expect(!blockMatches.isEmpty)

        let timeRegex = try NSRegularExpression(pattern: #"\\time\s+(\d+)/(\d+)"#)
        let tokenRegex = try NSRegularExpression(
            pattern: #"(?:<[^>]+>|[a-z]+[,']*)\s*(\d+)(\.*)(?:\*(\d+)/(\d+))?"#
        )
        let stripDirectivesRegex = try NSRegularExpression(
            pattern: #"\\(?:time\s+\d+/\d+|tempo\s+\S+\s*=\s*\d+|key\s+[a-z]+\s+\\[a-z]+|ppp|pp|mp|mf|fff|ff|p|f)\b"#
        )

        for match in blockMatches {
            let trackName = nsGolden.substring(with: match.range(at: 1))
            let body = nsGolden.substring(with: match.range(at: 2))
            let rawMeasures = body.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            var expectedQuarters = 4.0
            for (mIdx, measureStr) in rawMeasures.enumerated() {
                let nsMeasure = measureStr as NSString
                for tMatch in timeRegex.matches(
                    in: measureStr, range: NSRange(location: 0, length: nsMeasure.length))
                {
                    let num = Double(nsMeasure.substring(with: tMatch.range(at: 1))) ?? 4.0
                    let den = Double(nsMeasure.substring(with: tMatch.range(at: 2))) ?? 4.0
                    if den > 0 {
                        expectedQuarters = num * 4.0 / den
                    }
                }

                let stripped = stripDirectivesRegex.stringByReplacingMatches(
                    in: measureStr,
                    range: NSRange(location: 0, length: nsMeasure.length),
                    withTemplate: " "
                )
                let nsStripped = stripped as NSString
                let tokMatches = tokenRegex.matches(
                    in: stripped, range: NSRange(location: 0, length: nsStripped.length))

                var totalQuarters = 0.0
                for tok in tokMatches {
                    let baseDen = Double(nsStripped.substring(with: tok.range(at: 1))) ?? 4.0
                    let dots = nsStripped.substring(with: tok.range(at: 2)).count
                    var q = 4.0 / baseDen
                    var dotAdd = q / 2.0
                    for _ in 0..<dots {
                        q += dotAdd
                        dotAdd /= 2.0
                    }
                    if tok.range(at: 3).location != NSNotFound,
                        tok.range(at: 4).location != NSNotFound
                    {
                        let mNum = Double(nsStripped.substring(with: tok.range(at: 3))) ?? 1.0
                        let mDen = Double(nsStripped.substring(with: tok.range(at: 4))) ?? 1.0
                        if mDen > 0 {
                            q *= mNum / mDen
                        }
                    }
                    totalQuarters += q
                }

                #expect(
                    abs(totalQuarters - expectedQuarters) < 1e-4,
                    "Track \(trackName) measure \(mIdx + 1) expected \(expectedQuarters) quarters, got \(totalQuarters) in: \(measureStr)"
                )
            }
        }
    }
}
