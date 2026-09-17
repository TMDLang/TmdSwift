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

        var tmdURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent().appendingPathComponent("tmd")
        if !FileManager.default.isExecutableFile(atPath: tmdURL.path) {
            let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/out/Products/Debug/tmd")
            if FileManager.default.isExecutableFile(atPath: fallbackURL.path) {
                tmdURL = fallbackURL
            }
        }
        #expect(FileManager.default.isExecutableFile(atPath: tmdURL.path), "tmd binary must be built and available")
        guard FileManager.default.isExecutableFile(atPath: tmdURL.path) else { return }

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
}
