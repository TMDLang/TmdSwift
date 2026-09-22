import Testing
import Foundation
@testable import TmdSwift
import TmdMusicXML

@Suite("MusicXML Validation Tests")
struct MusicXMLValidationTests {

    @Test func testMusicXMLWellFormedXML() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let data = try Data(contentsOf: sampleURL)
        let sheet = try TmdParser.parseThrowing(data: data)

        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)
        let xmlData = Data(xml.utf8)

        #if os(macOS)
        let doc = try XMLDocument(data: xmlData, options: [])
        #expect(doc.rootElement()?.name == "score-partwise")
        #else
        #expect(xml.contains("<score-partwise"))
        #expect(xml.contains("</score-partwise>"))
        #endif
    }

    @Test func testMusicXMLMeasureDurationsConserved() throws {
        let tmd = """
        ::SCORE::
        ** Measure Invariant Test **
        != 120
        ?= C
        <4/4>

        A:Piano@|0|{
            <4*>
            1 2 3 -
            1 - - -
            1 2 3 4
        }
        -> A ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)

        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)
        let xmlData = Data(xml.utf8)

        #if os(macOS)
        let doc = try XMLDocument(data: xmlData, options: [])
        guard let root = doc.rootElement() else {
            Issue.record("No root element")
            return
        }

        let divisions = 48
        let expectedMeasureDuration = 4 * divisions // 4 beats * 48 = 192

        let parts = root.elements(forName: "part")
        #expect(!parts.isEmpty)
        for part in parts {
            let measures = part.elements(forName: "measure")
            #expect(!measures.isEmpty)
            for (idx, measure) in measures.enumerated() {
                var totalDuration = 0
                for child in measure.children ?? [] {
                    guard let el = child as? XMLElement, el.name == "note" else { continue }
                    if el.elements(forName: "chord").first != nil { continue }
                    if let durStr = el.elements(forName: "duration").first?.stringValue,
                       let dur = Int(durStr) {
                        totalDuration += dur
                    }
                }
                #expect(
                    totalDuration == expectedMeasureDuration,
                    "Measure \(idx + 1) in part \(part.attribute(forName: "id")?.stringValue ?? "") duration \(totalDuration) does not equal expected \(expectedMeasureDuration)"
                )
            }
        }
        #else
        #expect(xml.contains("<score-partwise"))
        #expect(xml.contains("<measure number=\"1\">"))
        #expect(xml.contains("</score-partwise>"))
        #endif
    }

    @Test func testMusicXMLTupletMeasureDurationConserved() throws {
        let tmd = """
        ::SCORE::
        ** Tuplet Test **
        != 120
        ?= C
        <4/4>

        intro:Horn@|0|{
            <8*>
            | 6_ - - - - - (1_ 3_ 5_)%(--) |
        }
        -> intro ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)
        let xmlData = Data(xml.utf8)

        #if os(macOS)
        let doc = try XMLDocument(data: xmlData, options: [])
        guard let root = doc.rootElement() else {
            Issue.record("No root element")
            return
        }

        let divisions = 48
        let expectedMeasureDuration = 4 * divisions // 4 beats * 48 = 192

        let parts = root.elements(forName: "part")
        #expect(!parts.isEmpty)
        for part in parts {
            let measures = part.elements(forName: "measure")
            #expect(!measures.isEmpty)
            for (idx, measure) in measures.enumerated() {
                var totalDuration = 0
                for child in measure.children ?? [] {
                    guard let el = child as? XMLElement, el.name == "note" else { continue }
                    if el.elements(forName: "chord").first != nil { continue }
                    if let durStr = el.elements(forName: "duration").first?.stringValue,
                       let dur = Int(durStr) {
                        totalDuration += dur
                    }
                }
                #expect(
                    totalDuration == expectedMeasureDuration,
                    "Measure \(idx + 1) in part \(part.attribute(forName: "id")?.stringValue ?? "") duration \(totalDuration) does not equal expected \(expectedMeasureDuration)"
                )
            }
        }
        #else
        #expect(xml.contains("<score-partwise"))
        #endif
    }

    @Test func testMusicXMLMuseScoreCLIImport() throws {
        var mscorePath: String?

        #if !os(Windows)
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/which") {
            let whichMScore = Process()
            whichMScore.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichMScore.arguments = ["mscore"]
            let pipe = Pipe()
            whichMScore.standardOutput = pipe
            do {
                try whichMScore.run()
                whichMScore.waitUntilExit()
                if whichMScore.terminationStatus == 0 {
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let output, !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
                        mscorePath = output
                    }
                }
            } catch {
                // Ignore process failure
            }
        }
        if mscorePath == nil && FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mscore") {
            mscorePath = "/opt/homebrew/bin/mscore"
        }
        if mscorePath == nil && FileManager.default.isExecutableFile(atPath: "/Applications/MuseScore 4.app/Contents/MacOS/mscore") {
            mscorePath = "/Applications/MuseScore 4.app/Contents/MacOS/mscore"
        }
        #endif

        guard let executable = mscorePath else {
            return
        }

        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/三天三夜.tmd")
        let sheet = try TmdParser.parseThrowing(url: sampleURL)

        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)
        let tempXMLURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mscore_test_\(UUID().uuidString).musicxml")
        let tempOutURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mscore_test_\(UUID().uuidString).mscz")

        defer {
            try? FileManager.default.removeItem(at: tempXMLURL)
            try? FileManager.default.removeItem(at: tempOutURL)
        }

        try xml.write(to: tempXMLURL, atomically: true, encoding: .utf8)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = ["-F", "-t", "--no-audio", tempXMLURL.path, "-o", tempOutURL.path]
        try proc.run()
        proc.waitUntilExit()

        #expect(
            FileManager.default.fileExists(atPath: tempOutURL.path),
            "mscore failed to generate output file"
        )
        let outputSize = (try? Data(contentsOf: tempOutURL).count) ?? 0
        #expect(outputSize > 100, "mscore output is empty or invalid (size: \(outputSize) bytes)")
    }

    @Test func testMusicXMLNoteTypeAndTupletTimeModification() throws {
        let tmd = """
        ::SCORE::
        ** Note Type and Tuplet Test **
        != 120
        ?= C
        <4/4>

        A:Trumpet@|0|{
            <4*>
            | (1 3 5)%(-) 1^ - - |
        }
        -> A ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)

        let xmlData = Data(xml.utf8)
        #if os(macOS)
        let doc = try XMLDocument(data: xmlData, options: [])
        guard let root = doc.rootElement() else {
            Issue.record("No root element")
            return
        }

        // Verify type elements exist
        let typeElements = try doc.nodes(forXPath: "//note/type")
        #expect(!typeElements.isEmpty, "MusicXML should generate <type> elements for notes")

        // Verify time-modification for tuplet notes
        let timeModElements = try doc.nodes(forXPath: "//note/time-modification")
        #expect(timeModElements.count >= 3, "Triplet notes should have <time-modification>")
        for tm in timeModElements {
            guard let elem = tm as? XMLElement else { continue }
            let actual = elem.elements(forName: "actual-notes").first?.stringValue
            let normal = elem.elements(forName: "normal-notes").first?.stringValue
            #expect(actual == "3")
            #expect(normal == "2")
        }
        #else
        #expect(xml.contains("<type>eighth</type>"))
        #expect(xml.contains("<time-modification>"))
        #expect(xml.contains("<actual-notes>3</actual-notes>"))
        #expect(xml.contains("<normal-notes>2</normal-notes>"))
        #endif
    }
}

