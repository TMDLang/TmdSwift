import Testing
import Foundation
@testable import TmdSwift
import TmdABC

@Suite("ABC Validation Tests")
struct ABCValidationTests {

    @Test func testABCHeadersAndVoices() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let sheet = try TmdParser.parseThrowing(url: sampleURL)

        let abc = TMDABCGenerator.generateABC(from: sheet)
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

        let abc = TMDABCGenerator.generateABC(from: sheet)

        let v1Section = abc.components(separatedBy: "[V:V1]").last ?? ""
        let body = v1Section.components(separatedBy: "[V:").first ?? ""
        let measures = body
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        #expect(measures.count >= 2, "Expected at least 2 measures separated by barlines, got \(measures.count)")

        let noteRegex = try NSRegularExpression(pattern: #"(?:[A-Ga-gz\^=_]+|"[^"]*"z)(\d*)"#)

        for (mIdx, measureStr) in measures.enumerated() {
            let nsStr = measureStr as NSString
            let matches = noteRegex.matches(in: measureStr, range: NSRange(location: 0, length: nsStr.length))
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
        let abcG = TMDABCGenerator.generateABC(from: sheetG)
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
        let abcBb = TMDABCGenerator.generateABC(from: sheetBb)
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
        let abc = TMDABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("K:C"))
        #expect(abc.contains("K:D"))
    }
}

