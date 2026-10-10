import Foundation
import Testing
import TmdMusicXML

@testable import TmdSwift

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

        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)

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
        let sheet = try TmdParserIO.parseThrowing(data: data)

        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
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

        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        let xmlData = Data(xml.utf8)

        #if os(macOS)
            let doc = try XMLDocument(data: xmlData, options: [])
            guard let root = doc.rootElement() else {
                Issue.record("No root element")
                return
            }

            let divisions = 48
            let expectedMeasureDuration = 4 * divisions  // 4 beats * 48 = 192

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
                            let dur = Int(durStr)
                        {
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
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        let xmlData = Data(xml.utf8)

        #if os(macOS)
            let doc = try XMLDocument(data: xmlData, options: [])
            guard let root = doc.rootElement() else {
                Issue.record("No root element")
                return
            }

            let divisions = 48
            let expectedMeasureDuration = 4 * divisions  // 4 beats * 48 = 192

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
                            let dur = Int(durStr)
                        {
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
                        let output = String(
                            data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let output, !output.isEmpty,
                            FileManager.default.isExecutableFile(atPath: output)
                        {
                            mscorePath = output
                        }
                    }
                } catch {
                    // Ignore process failure
                }
            }
            if mscorePath == nil
                && FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mscore")
            {
                mscorePath = "/opt/homebrew/bin/mscore"
            }
            if mscorePath == nil
                && FileManager.default.isExecutableFile(
                    atPath: "/Applications/MuseScore 4.app/Contents/MacOS/mscore")
            {
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
        let sheet = try TmdParserIO.parseThrowing(url: sampleURL)

        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        let tempXMLURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "mscore_test_\(UUID().uuidString).musicxml")
        let tempOutURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "mscore_test_\(UUID().uuidString).mscz")

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
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)

        let xmlData = Data(xml.utf8)
        #if os(macOS)
            let doc = try XMLDocument(data: xmlData, options: [])
            guard doc.rootElement() != nil else {
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
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)

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
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)

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
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)

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
        let xmlCompound = TmdMusicXMLGenerator.generateMusicXML(from: sheetCompound)

        // Initial tempo in 6/8: quarter BPM 120 -> dotted quarter BPM 80
        #expect(
            xmlCompound.contains(
                "<beat-unit>quarter</beat-unit>\n            <beat-unit-dot/>\n            <per-minute>80</per-minute>"
            ))
        // Directive tempo in 6/8: quarter BPM 150 -> dotted quarter BPM 100
        #expect(
            xmlCompound.contains(
                "<beat-unit>quarter</beat-unit><beat-unit-dot/><per-minute>100</per-minute>"))
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
        let xmlCutTime = TmdMusicXMLGenerator.generateMusicXML(from: sheetCutTime)

        // Half note beat unit: quarter BPM 120 -> half note BPM 60
        #expect(
            xmlCutTime.contains(
                "<beat-unit>half</beat-unit>\n            <per-minute>60</per-minute>"))

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
        let xmlEighthTime = TmdMusicXMLGenerator.generateMusicXML(from: sheetEighthTime)

        // Eighth note beat unit: quarter BPM 120 -> eighth note BPM 240
        #expect(
            xmlEighthTime.contains(
                "<beat-unit>eighth</beat-unit>\n            <per-minute>240</per-minute>"))
    }

    @Test func testExplicitKeyAndDynamicsInMusicXML() throws {
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
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)

        // Header declared key= Bm -> 2 sharps, minor mode
        #expect(xml.contains("<fifths>2</fifths>\n            <mode>minor</mode>"))

        // Section inline dynamics
        #expect(xml.contains("<dynamics>\n          <p/>\n        </dynamics>"))
        #expect(xml.contains("<dynamics>\n          <f/>\n        </dynamics>"))

        // Inline directive {key= F#m} -> 3 sharps, minor mode
        #expect(xml.contains("<key><fifths>3</fifths><mode>minor</mode></key>"))
    }

    @Test func testMusicXMLFlatKeyAndAccidentalSpelling() throws {
        // In F major (1 flat: Bb), degree 4 is Bb4 (step B, alter -1, octave 4), not A#4.
        // Also test explicit flat 3, (Ab4 in F major) and Cb4 (1, in C major -> step C, alter -1, octave 4).
        let tmdF = """
            ::SCORE::
            ** Flat Key Spelling **
            != 120
            ?= F
            key= F
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
                | [4] - [Bb/D] - |
            }
            -> A ->#
            """
        let sheetF = try TmdParser.parseThrowing(string: tmdF)
        let xmlF = TmdMusicXMLGenerator.generateMusicXML(from: sheetF)

        #expect(xmlF.contains("<fifths>-1</fifths>"))
        // Degree 4 in F major must be B flat (step B, alter -1, octave 4), never A# (step A, alter 1)
        #expect(
            xmlF.contains(
                "<step>B</step>\n            <alter>-1</alter>\n            <octave>4</octave>"))
        #expect(!xmlF.contains("<step>A</step>\n            <alter>1</alter>"))
        // Chord [4] and [Bb/D] root must also be B flat (root-step B, root-alter -1)
        #expect(
            xmlF.contains("<root-step>B</root-step>\n          <root-alter>-1</root-alter>"))
        #expect(!xmlF.contains("<root-step>A</root-step>\n          <root-alter>1</root-alter>"))

        // Boundary octave test: 1, in C major is Cb4 (step C, alter -1, octave 4) and 7' is B#4 (step B, alter 1, octave 4)
        let tmdBoundary = """
            ::SCORE::
            ** Octave Boundary Accidentals **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1, 7, 7' 1 |
            }
            -> A ->#
            """
        let sheetBoundary = try TmdParser.parseThrowing(string: tmdBoundary)
        let xmlBoundary = TmdMusicXMLGenerator.generateMusicXML(from: sheetBoundary)
        #expect(
            xmlBoundary.contains(
                "<step>C</step>\n            <alter>-1</alter>\n            <octave>4</octave>"))
        #expect(
            xmlBoundary.contains(
                "<step>B</step>\n            <alter>-1</alter>\n            <octave>4</octave>"))
        #expect(
            xmlBoundary.contains(
                "<step>B</step>\n            <alter>1</alter>\n            <octave>4</octave>"))
    }

    @Test func testMusicXMLAccidentalTagEmissionAndStateMachine() throws {
        // 1. Intra-measure accidental state machine in C major: | 1' 1 1, 7' |
        let tmdC = """
            ::SCORE::
            ** MusicXML Accidental State Machine **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1' 1 1, 7' |
            }
            -> A ->#
            """
        let sheetC = try TmdParser.parseThrowing(string: tmdC)
        let xmlC = TmdMusicXMLGenerator.generateMusicXML(from: sheetC)

        // 1' (C#4) -> <accidental>sharp</accidental>
        // 1  (C4)  -> <accidental>natural</accidental> (cancels prior C#4 in same measure)
        // 1, (Cb4) -> <accidental>flat</accidental>
        // 7' (B#4) -> <accidental>sharp</accidental>
        #expect(xmlC.contains("<accidental>sharp</accidental>"))
        #expect(xmlC.contains("<accidental>natural</accidental>"))
        #expect(xmlC.contains("<accidental>flat</accidental>"))

        // 2. Re-sharping a key-signature sharp after a natural in D major: | 7_ 7,_ 7_ 1 |
        // In D major (F#, C#):
        // - First 7_ (C#4) matches key signature -> no <accidental>
        // - 7,_ (C4 natural) cancels key signature -> <accidental>natural</accidental>
        // - Second 7_ (C#4) re-sharps after natural -> <accidental>sharp</accidental>
        let tmdD = """
            ::SCORE::
            ** MusicXML Key Cancellation and Re-sharp **
            != 120
            ?= D
            key= D
            <4/4>

            A:Piano@|0|{
                <4*>
                | 7_ 7,_ 7_ 1 |
            }
            -> A ->#
            """
        let sheetD = try TmdParser.parseThrowing(string: tmdD)
        let xmlD = TmdMusicXMLGenerator.generateMusicXML(from: sheetD)
        #expect(xmlD.components(separatedBy: "<accidental>natural</accidental>").count - 1 == 1)
        #expect(xmlD.components(separatedBy: "<accidental>sharp</accidental>").count - 1 == 1)

        // 3. Divergence between movable-do ?= D and inline {key= F#m}:
        // Degree 4 in ?= D is G4 natural, while F#m has G# in its key signature -> must emit <accidental>natural</accidental>
        let tmdDiverge = """
            ::SCORE::
            ** MusicXML Key Divergence **
            != 120
            ?= D
            <4/4>

            A:Piano@|0|{
                <4*>
                | {key= F#m} 1 2 3 4 |
            }
            -> A ->#
            """
        let sheetDiverge = try TmdParser.parseThrowing(string: tmdDiverge)
        let xmlDiverge = TmdMusicXMLGenerator.generateMusicXML(from: sheetDiverge)
        #expect(xmlDiverge.contains("<accidental>natural</accidental>"))
    }
}
