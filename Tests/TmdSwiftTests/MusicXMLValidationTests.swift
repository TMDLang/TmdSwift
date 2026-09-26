import Testing
import Foundation
@testable import TmdSwift
import TmdMusicXML

@Suite("MusicXML Validation Tests")
struct MusicXMLValidationTests {

    @Test func testPrototypeOnlySheetDoesNotCreateImplicitPianoPart() throws {
        let tmd = """
        ::SCORE::
        ** Prototype Only **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)

        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)

        #expect(xml.contains("<score-partwise"))
        #expect(!xml.contains("<score-part id=\"P1\">"))
        #expect(!xml.contains("<part id=\"P1\">"))
    }

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

    @Test func testMusicXMLPercussionMappingAndClefs() throws {
        let tmd = """
        ::SCORE::
        ** Percussion and Clef Test **
        != 120
        ?= C
        <4/4>

        A:Drums@|0|{
            <4*>
            (D S X O) (T C B S) - -
        }
        A:Cello@|0|{
            <4*>
            1 2 3 4
        }
        -> A ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)

        // Drum clef
        #expect(xml.contains("<sign>percussion</sign>"))

        // Cello / Bass clef
        #expect(xml.contains("<sign>F</sign>"))
        #expect(xml.contains("<line>4</line>"))

        // Drum notes display steps for kick (F4), snare (D5), hi-hat (F5), open hi-hat (G5), tom (A4), crash (A5)
        #expect(xml.contains("<display-step>F</display-step>"))
        #expect(xml.contains("<display-step>D</display-step>"))
        #expect(xml.contains("<display-step>G</display-step>"))
        #expect(xml.contains("<display-step>A</display-step>"))
    }

    @Test func testMusicXMLHarmonyStandardFormattingAndSlashChords() throws {
        let tmd = """
        ::SCORE::
        ** Harmony Test **
        != 120
        ?= C
        <4/4>

        A:CHORD@|0|{
            <4*>
            [C] [Am7] [C/E] [1/3]
        }
        -> A ->#
        """
        let sheet = try TmdParser.parseThrowing(string: tmd)
        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)

        // Standard root-step (should be single letter C, A, etc.)
        #expect(xml.contains("<root-step>C</root-step>"))
        #expect(xml.contains("<root-step>A</root-step>"))

        // Slash chord bass
        #expect(xml.contains("<bass-step>E</bass-step>"))
    }

    @Test func testMusicXMLRelativeKeyDirectiveModulation() throws {
        let tmd = """
        ::SCORE::
        ** Relative Key Test **
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
        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)

        // Original key C has fifths = 0
        #expect(xml.contains("<fifths>0</fifths>"))

        // Modulated key (C + 2 semitones = D major) has fifths = 2
        #expect(xml.contains("<fifths>2</fifths>"))
    }

    @Test func testMusicXMLTempoBeatUnitBasedOnTimeSignature() throws {
        // Compound meter: 6/8 -> dotted-quarter beat unit
        let tmdCompound = """
        ::SCORE::
        ** Compound Meter Test **
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
        let xmlCompound = TMDMusicXMLGenerator.generateMusicXML(from: sheetCompound)

        // Initial tempo in 6/8: quarter BPM 120 -> dotted quarter BPM 80
        #expect(xmlCompound.contains("<beat-unit>quarter</beat-unit>\n            <beat-unit-dot/>\n            <per-minute>80</per-minute>"))
        // Directive tempo in 6/8: quarter BPM 150 -> dotted quarter BPM 100
        #expect(xmlCompound.contains("<beat-unit>quarter</beat-unit><beat-unit-dot/><per-minute>100</per-minute>"))
        // Sound tempo remains in quarter notes per minute for MIDI/playback engine compliance
        #expect(xmlCompound.contains("<sound tempo=\"120\"/>"))
        #expect(xmlCompound.contains("<sound tempo=\"150.0\"/>"))

        // Cut time / 2/2 -> half note beat unit
        let tmdCutTime = """
        ::SCORE::
        ** Cut Time Test **
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
        let xmlCutTime = TMDMusicXMLGenerator.generateMusicXML(from: sheetCutTime)

        // Half note beat unit: quarter BPM 120 -> half note BPM 60
        #expect(xmlCutTime.contains("<beat-unit>half</beat-unit>\n            <per-minute>60</per-minute>"))

        // 3/8 -> eighth note beat unit
        let tmdEighthTime = """
        ::SCORE::
        ** Simple Triple Eighth Test **
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
        let xmlEighthTime = TMDMusicXMLGenerator.generateMusicXML(from: sheetEighthTime)

        // Eighth note beat unit: quarter BPM 120 -> eighth note BPM 240
        #expect(xmlEighthTime.contains("<beat-unit>eighth</beat-unit>\n            <per-minute>240</per-minute>"))
    }
}

