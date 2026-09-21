import Testing
import Foundation
@testable import TmdSwift

@Suite("TMD Measure Check Tests")
struct TmdMeasureCheckTests {
    @Test func testValidMeasuresReportNoErrors() throws {
        let input = """
        ::SCORE::
        ** Valid Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
            | 1 2 3 4 |
            | [C] - - - |
        }

        -> verse ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.isEmpty)
    }

    @Test func testMeasureWithIncorrectBeatsReportsIssue() throws {
        let input = """
        ::SCORE::
        ** Mismatched Measure Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
            | 1 2 3 |
            | 1 2 3 4 5 |
        }

        -> verse ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.count == 2)

        // Issue 1: 3 units instead of 4
        #expect(issues[0].actualUnits == 3)
        #expect(issues[0].expectedUnits == 4)
        #expect(issues[0].paragraphName == "verse")
        #expect(issues[0].instrument == "Piano")
        #expect(issues[0].measureIndex == 2)

        // Issue 2: 5 units instead of 4
        #expect(issues[1].actualUnits == 5)
        #expect(issues[1].expectedUnits == 4)
        #expect(issues[1].measureIndex == 3)
    }

    @Test func testPickupMeasureAtStartAllowed() throws {
        let input = """
        ::SCORE::
        ** Song with Pickup **
        != 120
        ?= C
        <4/4>

        verse:Piano@|-1|{
            <4*>
            | 5 |
            | 1 2 3 4 |
            | 1 2 3 4 |
        }

        -> verse ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.isEmpty)
    }

    @Test func testSixteenthNoteGridMeasureCheck() throws {
        let input = """
        ::SCORE::
        ** 16th Note Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <16*>
            | 1- 1- 1- 1- 1- 1- 1- 1- |
            | 1 2 3 4 |
        }

        -> verse ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        // Measure 1 has 16 sixteenth units: valid
        // Measure 2 has 4 sixteenth units (needs 16): invalid
        #expect(issues.count == 1)
        #expect(issues[0].expectedUnits == 16)
        #expect(issues[0].actualUnits == 4)
        #expect(issues[0].measureIndex == 2)
    }

    @Test func testCLICheckCommand() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let badTmd = tempDir.appendingPathComponent("bad.tmd")
        let badContent = """
        ::SCORE::
        ** Bad Measure Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 |
        }
        -> verse ->#
        """
        try badContent.write(to: badTmd, atomically: true, encoding: .utf8)

        guard let tmdURL = TmdTestHelper.findTmdExecutable() else {
            Issue.record("tmd binary must be built and available")
            return
        }

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = tmdURL
        proc.arguments = ["check", badTmd.path]
        proc.standardError = pipe
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()

        #expect(proc.terminationStatus != 0)
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let outputStr = String(data: outputData, encoding: .utf8) ?? ""
        #expect(outputStr.contains("Expected 4"))
        #expect(outputStr.contains("found 3"))
    }

    @Test func testSectionInstrumentLengthAllowsStaggeredEntrancesAndEarlyExits() throws {
        let input = """
        ::SCORE::
        ** Layered Section Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
        }

        verse:Bass@|0|{
            <4*>
            | 1 - - - |
            | 1 - - - |
        }

        verse:Chorus@|+2|{
            <4*>
            | 1 2 3 4 |
        }

        -> verse ->#
        """

        // Bass exits early (2 measures out of 4), Chorus enters at +2 and exits at 3.
        // In TMD, these are valid staggered entrances / early exits without reporting error.
        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.isEmpty)
    }

    @Test func testSectionInstrumentLengthWithDelayedStartMatches() throws {
        let input = """
        ::SCORE::
        ** Delayed Start Section Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
        }

        verse:Chorus@|+2|{
            <4*>
            | 1 2 3 4 |
            | 1 2 3 4 |
        }

        -> verse ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        // verse:Piano ends at 0 + 4 = 4 measures.
        // verse:Chorus starts at 2 and has 2 measures -> ends at 2 + 2 = 4 measures.
        // Both end at measure 4, so no mismatch.
        #expect(issues.isEmpty)
    }

    @Test func testSectionInstrumentLengthWithPickupMatches() throws {
        let input = """
        ::SCORE::
        ** Pickup Section Song **
        != 120
        ?= C
        <4/4>

        verse:Vocal@|-1|{
            <4*>
            | 5 |
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
        }

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
            | 1 2 3 4 |
        }

        -> verse ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        // Both end at positive measure 4, so no mismatch.
        #expect(issues.isEmpty)
    }

    @Test func testRecognizesPercussionTokensAndGroups() throws {
        let input = """
        ::SCORE::
        ** Drum Song **
        != 120
        ?= C
        <4/4>

        v2:Drum-Kick@|0| {
            <4*>
            | D - - - | D - - - | D - - - | D - - - |
            | D - - - | D - - - | D - - - | D - x X |
        }

        intro:Drum@|0| {
            <4*>
            | - - - - |
            | (xxxx) - - - |
        }

        -> v2 ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.isEmpty)
    }

    @Test func testReportsIssueWhenExecutionOrderRefersToUndefinedSection() throws {
        let input = """
        ::SCORE::
        ** Undefined Order Section Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
        }

        -> verse -> chorus -> #
        """

        let issues = TMDMeasureChecker.check(source: input)
        // 'chorus' is undefined, but '#' should be considered valid terminator and not reported!
        #expect(issues.count == 1)
        guard let issue = issues.first else { return }
        #expect(issue.paragraphName == "chorus")
        #expect(issue.instrument == "Order")
        #expect(issue.measureIndex == 0)
        #expect(issue.description.contains("Undefined section 'chorus' in playback order"))
    }

    @Test func testReportsIssueWhenPlaybackOrderIsMissing() throws {
        let input = """
        ::SCORE::
        ** No Order Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
        }
        """

        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.count == 1)
        guard let issue = issues.first else { return }
        #expect(issue.instrument == "Order")
        #expect(issue.description.contains("Missing playback order"))
    }

    @Test func testReportsIssueWhenPlaybackOrderDoesNotEndWithHash() throws {
        let input = """
        ::SCORE::
        ** Unterminated Order Song **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            | 1 2 3 4 |
        }

        -> verse
        """

        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.count == 1)
        guard let issue = issues.first else { return }
        #expect(issue.instrument == "Order")
        #expect(issue.description.contains("Playback order must terminate with '#'"))
    }

    @Test func testAccuratelyChecksPipelessMeasuresAndMixedPipeParagraphs() throws {
        let code = """
        ::SCORE::
        ** Pipeless Measure Test **
        != 120
        ?= C
        <4/4>

        intro:CHORD@|0|{
        <2*>
        |[1] - | - [7,] |
        |[1] - | - [7,] |
        |[1] - | - [7,] |
        |[1] - | - [7,] |

        <4*>
        [1]-----[7,]-
        [1]-----[7,]-
        }

        -> intro ->#
        """
        // intro:CHORD has 8 measures of <2*> (16 half notes = 32 quarter notes = 8 measures)
        // plus 2 measures of <4*> (8 quarter notes = 2 measures)
        // total 10 measures. Should have 0 issues.
        let issues = TMDMeasureChecker.check(source: code)
        #expect(issues.isEmpty)
    }

    @Test func testAcceptsLayeredIntroPatternWithoutFalseErrors() throws {
        let code = """
        ::SCORE::
        ** 三天三夜 Intro Test **
        != 133
        ?= A'
        <4/4>

        intro:CHORD@|0|{
        <2*>
        |[1] - | - [7,] |
        |[1] - | - [7,] |
        |[1] - | - [7,] |
        |[1] - | - [7,] |

        <4*>
        [1]-----[7,]-
        [1]-----[7,]-
        }
        intro:Chorus-1@|+4|{
        <16*>
        1_- 1_ - 1_ - - 1_ - 1_ - 1_ 1_ - - -
        1_- 1_ - 1_ - - 1_ - 1_ - 1_ 1_ - - -
        1_- 1_ - 1_ - - 1_ - 1_ - 1_ 1_ - - -
        1_- 1_ - 1_ - - 1_ - 1_ - 1_ 1_ - - -
        }

        intro:Chorus-2@|+6|{
        <16*>
        3_- 3_ - 3_ - - 3_ - 3_ - 3_ 3_ - - -
        3_- 3_ - 3_ - - 3_ - 3_ - 3_ 3_ - - -
        3_- 3_ - 3_ - - 3_ - 3_ - 3_ 3_ - - -
        }
        intro:Chorus-3@|+8|{
        <16*>
        5_- 5_ - 5_ - - 5_ - 5_ - 5_ 5_ - - -
        5_- 5_ - 5_ - - 5_ - 5_ - 5_ 5_ - - -
        }

        intro:Guitar@{
        <16*>
        (7,1)%(--) 1 (7,1)%(--) 1 (7,1)%(--)1 (7,1)%(--) 6 7, 6 7, 6 
        (7,1)%(--) 1 (7,1)%(--) 1 (7,1)%(--)1 (7,1)%(--) 6 7, 6 7, 6  
        (7,1)%(--) 1 (7,1)%(--) 1 (7,1)%(--)1 (7,1)%(--) 6 7, 6 7, 6 
        (7,1)%(--) 1 (7,1)%(--) 1 (7,1)%(--)1 (7,1)%(--) 6 7, 6 7, 6 
        }

        -> intro ->#
        """
        let issues = TMDMeasureChecker.check(source: code)
        #expect(issues.isEmpty)
    }
}



