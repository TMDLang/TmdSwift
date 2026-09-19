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

    @Test func testSectionInstrumentLengthMismatchReportsIssue() throws {
        let input = """
        ::SCORE::
        ** Mismatched Section Length Song **
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

        -> verse ->#
        """

        let issues = TMDMeasureChecker.check(source: input)
        // verse:Piano has 4 measures (16 beats).
        // verse:Bass only has 2 measures (8 beats).
        // Should report a section length discrepancy issue.
        let sectionIssues = issues.filter { $0.measureIndex == 0 }
        #expect(sectionIssues.count == 1)
        if let issue = sectionIssues.first {
            #expect(issue.paragraphName == "verse")
            #expect(issue.instrument == "Bass")
            #expect(issue.expectedUnits == 4) // Expected measures
            #expect(issue.actualUnits == 2)   // Actual measures
            #expect(issue.description.contains("Expected 4 measures"))
            #expect(issue.description.contains("found 2 measures"))
        }
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
}


