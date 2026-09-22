import Testing
import Foundation
@testable import TmdSwift
import TmdMIDI
import TmdAudio
import TmdMusicXML
import TmdABC

@Suite("Macro Evaluator & S-Expression Tests")
struct MacroEvaluatorTests {

    @Test("Parses abstract paragraphs declared without instrument bindings (Theme { ... })")
    func testParseAbstractParagraph() throws {
        let input = """
        ::SCORE::
        ** Abstract Prototype **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }

        -> Theme ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        #expect(sheet.paragraphs.count == 1)
        let p = sheet.paragraphs[0]
        #expect(p.name == "Theme")
        #expect(p.instrument.isEmpty) // Empty instrument indicates abstract prototype
        #expect(p.start == 0)
        #expect(p.sections.count == 1)
        #expect(p.sections[0].unitGroups.count == 4)
    }

    @Test("Parses S-expressions in playback orders (-> (canon Theme (Violin1 Violin2) 2) ->#)")
    func testParseSExprInOrder() throws {
        let input = """
        ::SCORE::
        ** S-Expression Order **
        != 120
        ?= C
        <4/4>

        Theme:Piano@|0|{
            <4*>
            1 2 3 4
        }

        -> (canon Theme (Violin1 Violin2) 2) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        #expect(sheet.orders.count == 1)
        guard case .macro(let expr) = sheet.orders[0] else {
            Issue.record("Expected .macro order but got \(sheet.orders[0])")
            return
        }
        let expected = SExpr.list([
            .symbol("canon"),
            .symbol("Theme"),
            .list([.symbol("Violin1"), .symbol("Violin2")]),
            .number(2)
        ])
        #expect(expr == expected)
    }

    @Test("Formats S-expression macro orders back to TMD string")
    func testFormatMacroOrder() throws {
        let input = """
        ::SCORE::
        ** Format Macro Test **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }

        -> (canon Theme (Violin1 Violin2) 2) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let formatted = sheet.format()
        #expect(formatted.contains("Theme {\n"))
        #expect(formatted.contains("-> (canon Theme (Violin1 Violin2) 2) ->#"))
    }

    @Test("Evaluates (play Theme Violin) by binding abstract theme to instrument")
    func testPlayCombinator() throws {
        let input = """
        ::SCORE::
        ** Play Combinator **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }

        -> (play Theme Violin) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let playback = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
        #expect(playback.events.count == 4)
        #expect(playback.events[0].position == 0)
        #expect(playback.duration == 4)
    }

    @Test("Evaluates (loop Theme Cello 3) by repeating theme sequentially")
    func testLoopCombinator() throws {
        let input = """
        ::SCORE::
        ** Loop Combinator **
        != 120
        ?= C
        <4/4>

        Bass {
            <4*>
            1 5, 6, 3,
        }

        -> (loop Bass Cello 3) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let playback = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Cello")
        // 4 beats * 3 iterations = 12 events across 12 beats
        #expect(playback.events.count == 12)
        #expect(playback.duration == 12)
    }

    @Test("Evaluates (canon Theme (Violin1 Violin2 Violin3) 2) with exact staggered entries")
    func testCanonCombinator() throws {
        let input = """
        ::SCORE::
        ** Canon Combinator **
        != 120
        ?= D
        <4/4>

        Theme {
            <4*>
            3^ 2^ 1^ 7 | 6 5 6 7
        }

        -> (canon Theme (Violin1 Violin2 Violin3) 2) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let v1 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let v3 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin3")

        #expect(v1.events[0].position == 0)
        #expect(v2.events[0].position == 8)  // 2 measures * 4 beats
        #expect(v3.events[0].position == 16) // 4 measures * 4 beats

        #expect(v1.events.count == 8)
        #expect(v2.events.count == 8)
        #expect(v3.events.count == 8)
    }

    @Test("Evaluates nested canon (canon (canon Theme (Violin1 Violin2) 1) (Flute1 Flute2) 4)")
    func testNestedCanonCombinator() throws {
        let input = """
        ::SCORE::
        ** Nested Canon Test **
        != 120
        ?= D
        <4/4>

        Theme {
            <4*>
            1' - 7 - | 6 - 5 -
        }

        -> (canon
             (canon Theme (Violin1 Violin2) 1)
             (Flute1 Flute2)
             4
           ) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let v1 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let f1 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Flute1")
        let f2 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Flute2")

        // Inner canon: Violin1 enters at 0, Violin2 enters at 1 bar (4 beats)
        #expect(v1.events.count == 4)
        #expect(v1.events[0].position == 0)
        #expect(v2.events.count == 4)
        #expect(v2.events[0].position == 4)

        // Outer canon: Flute1 enters at 4 bars (16 beats), Flute2 enters at 4 + 1 = 5 bars (20 beats)
        #expect(f1.events.count == 4)
        #expect(f1.events[0].position == 16)
        #expect(f2.events.count == 4)
        #expect(f2.events[0].position == 20)
    }

    @Test("Evaluates (layer (canon ...) (loop ...)) combining polyphonic canon with ground bass")
    func testLayerWithCanonAndLoop() throws {
        let input = """
        ::SCORE::
        ** Pachelbel Canon Macro Demo **
        != 56
        ?= D
        <4/4>

        Bass {
            <4*>
            1_ 5__ 6__ 3__ | 4__ 1__ 4__ 5__
        }

        Theme {
            <4*>
            3^ 2^ 1^ 7 | 6 5 6 7 | 1^ 7 6 5 | 4 3 4 2
        }

        -> (layer
             (canon Theme (Violin1 Violin2 Violin3) 2)
             (loop Bass Cello 4)) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))

        let cello = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Cello")
        let v1 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let v3 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin3")

        // Cello: 4 iterations * 2 measures * 4 beats = 32 beats
        #expect(cello.duration == 32)
        #expect(cello.events.count == 32)

        // Violin 1 enters at 0, plays 16 beats
        #expect(v1.events[0].position == 0)
        #expect(v1.events.count == 16)

        // Violin 2 enters at 8, plays 16 beats
        #expect(v2.events[0].position == 8)
        #expect(v2.events.count == 16)

        // Violin 3 enters at 16, plays 16 beats
        #expect(v3.events[0].position == 16)
        #expect(v3.events.count == 16)
    }

    @Test("Evaluates (layer A (loop B 10)) with concrete paragraphs without requiring explicit instrument arguments")
    func testLayerBareConcreteParagraphAndTwoArgLoop() throws {
        let input = """
        ::SCORE::
        ** Layer Bare Concrete Paragraph & 2-arg Loop **
        != 120
        ?= C
        <4/4>

        A:Piano@|0|{
            <4*>
            1 2 3 4
        }

        B:Bass@|0|{
            <4*>
            1_ - 5_ -
        }

        -> (layer
             A
             (loop B 10)) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let expanded = TMDMacroEvaluator.expand(sheet)

        #expect(expanded.orders.count == 1)

        let piano = TMDPlaybackRenderer.render(sheet: expanded, instrument: "Piano")
        let bass = TMDPlaybackRenderer.render(sheet: expanded, instrument: "Bass")

        #expect(piano.duration == 40)
        #expect(piano.events.count == 4)

        // Bass loops 10 times * 4 beats = 40 beats
        #expect(bass.duration == 40)
        #expect(bass.events.count == 20)
    }

    @Test("Passes TMDMeasureChecker and exports MIDI / WAV seamlessly")
    func testMeasureCheckerAndExportIntegration() throws {
        let input = """
        ::SCORE::
        ** Macro Export & Check **
        != 120
        ?= D
        <4/4>

        Bass {
            <4*>
            1_ 5__ 6__ 3__ | 4__ 1__ 4__ 5__
        }

        Theme {
            <4*>
            3^ 2^ 1^ 7 | 6 5 6 7 | 1^ 7 6 5 | 4 3 4 2
        }

        -> (layer
             (canon Theme (Violin1 Violin2) 2)
             (loop Bass Cello 3)) ->#
        """
        // 1. Measure check passes with 0 issues
        let issues = TMDMeasureChecker.check(source: input)
        #expect(issues.isEmpty)

        // 2. MIDI generation produces valid bytes without throwing
        let sheet = try #require(TmdParser.parse(string: input))
        let midiBytes = TMDMIDIGenerator.generateMIDI(from: sheet)
        #expect(midiBytes.count > 50)

        // 3. WAV synthesis produces valid RIFF WAV data
        #if os(macOS)
        let wavBytes = try TMDWAVRenderer.renderWAV(from: sheet)
        #expect(wavBytes.count > 44)
        let header = String(data: wavBytes.subdata(in: 0..<4), encoding: .ascii)
        #expect(header == "RIFF")
        #endif
    }

    @Test("Supports multiple sequential themes in canon and loop: (canon (Theme1 Theme2) ...) and (loop (Bass1 Bass2) ...)")
    func testMultiThemeSequentialCanonAndLoop() throws {
        let input = """
        ::SCORE::
        ** Multi-Theme Sequential Canon & Loop **
        != 120
        ?= C
        <4/4>

        ThemeA {
            <4*>
            1 2 3 4 |
        }

        ThemeB {
            <4*>
            5 6 7 1^ |
        }

        BassA {
            <4*>
            1_ 5_ 6_ 3_ |
        }

        BassB {
            <4*>
            4_ 1_ 4_ 5_ |
        }

        -> (layer
             (canon (ThemeA ThemeB) (Violin1 Violin2) 2)
             (loop (BassA BassB) Cello 2)) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))

        let v1 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let cello = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Cello")

        #expect(v1.events.count == 8)
        #expect(v1.events[0].position == 0)
        #expect(v1.events[4].position == 4)

        #expect(v2.events[0].position == 8)
        #expect(v2.events[4].position == 12)

        #expect(v1.duration == 16)
        #expect(v2.duration == 16)

        #expect(cello.duration == 16)
        #expect(cello.events.count == 16)
    }

    @Test("Evaluates (transpose Theme semitones) shifting pitch chromatically")
    func testTransposeCombinator() throws {
        let input = """
        ::SCORE::
        ** Transpose Variation **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }

        -> (play (transpose Theme 2) Violin) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let v = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
        #expect(v.events.count == 4)

        let pitches = v.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(pitches == [62, 64, 66, 67])
    }

    @Test("Evaluates (reverse Theme) reversing note sequence within bars")
    func testReverseCombinator() throws {
        let input = """
        ::SCORE::
        ** Reverse Variation **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4 | 5 6 7 1^
        }

        -> (play (reverse Theme) Violin) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let v = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
        let pitches = v.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(pitches == [72, 71, 69, 67, 65, 64, 62, 60])
    }

    @Test("Evaluates (flip Theme) inverting melodic contours around the first note")
    func testFlipCombinator() throws {
        let input = """
        ::SCORE::
        ** Flip (Inversion) Variation **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 3 5 1^
        }

        -> (play (flip Theme) Violin) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let v = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
        let pitches = v.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(pitches == [60, 56, 53, 48])
    }

    @Test("Evaluates (vary Theme ...) chaining transformations")
    func testVaryCombinator() throws {
        let input = """
        ::SCORE::
        ** Variation Suite Demo **
        != 120
        ?= C
        <4/4>

        Subject {
            <4*>
            1 2 3 5 |
        }

        -> (layer
             (play Subject SoloViolin)
             (play (vary Subject +19) Flute)
             (canon (vary Subject reverse -12) (Cello Bass) 2)) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let violin = TMDPlaybackRenderer.render(sheet: sheet, instrument: "SoloViolin")
        let flute = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Flute")
        let cello = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Cello")
        let bass = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Bass")

        let violinPitches = violin.events.compactMap { e -> Int? in
            if case .note(let note) = e.content { return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset) }
            return nil
        }
        #expect(violinPitches == [60, 62, 64, 67])

        let flutePitches = flute.events.compactMap { e -> Int? in
            if case .note(let note) = e.content { return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset) }
            return nil
        }
        #expect(flutePitches == [79, 81, 83, 86])

        let celloPitches = cello.events.compactMap { e -> Int? in
            if case .note(let note) = e.content { return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset) }
            return nil
        }
        #expect(celloPitches == [55, 52, 50, 48])
        #expect(cello.events[0].position == 0)

        let bassPitches = bass.events.compactMap { e -> Int? in
            if case .note(let note) = e.content { return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset) }
            return nil
        }
        #expect(bassPitches == [55, 52, 50, 48])
        #expect(bass.events[0].position == 8)
    }

    @Test("Evaluates (seq ...) chronologically chaining expressions")
    func testSeqCombinator() throws {
        let input = """
        ::SCORE::
        ** Seq Combinator Test **
        != 120
        ?= C
        <4/4>

        ThemeA {
            <4*>
            1 2 3 4
        }
        ThemeB {
            <4*>
            5 6 7 1^
        }

        -> (seq (play ThemeA Piano) (play ThemeB Piano)) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let playback = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
        #expect(playback.events.count == 8)
        #expect(playback.events[0].position == 0)
        #expect(playback.events[4].position == 4)
        #expect(playback.duration == 8)
    }

    @Test("Evaluates (minor Theme) and (major Theme)")
    func testModalConversions() throws {
        let input = """
        ::SCORE::
        ** Modal Conversion Test **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4 | 5 6 7 1^
        }

        -> (play (minor Theme) MinorPiano)
        -> (play (major (minor Theme)) MajorPiano) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let minorPlayback = TMDPlaybackRenderer.render(sheet: sheet, instrument: "MinorPiano")
        let minorPitches = minorPlayback.events.compactMap { e -> Int? in
            if case .note(let note) = e.content { return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset) }
            return nil
        }
        #expect(minorPitches == [60, 62, 63, 65, 67, 68, 70, 72])

        let majorPlayback = TMDPlaybackRenderer.render(sheet: sheet, instrument: "MajorPiano")
        let majorPitches = majorPlayback.events.compactMap { e -> Int? in
            if case .note(let note) = e.content { return TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset) }
            return nil
        }
        #expect(majorPitches == [60, 62, 64, 65, 67, 69, 71, 72])
    }

    @Test("Validates canon_in_d_macro.tmd end-to-end score")
    func testCanonInDMacroSample() throws {
        let samplePath = "/Users/zonble/Work/TmdSwiftDev/sample/basic/canon_in_d_macro.tmd"
        let sheet = try TmdParser.parseThrowing(filePathOrURL: samplePath)
        #expect(sheet.name.contains("Canon in D"))

        // Measure consistency check: 0 errors
        let issues = TMDMeasureChecker.check(source: try String(contentsOfFile: samplePath))
        #expect(issues.isEmpty)

        // MIDI export
        let midi = TMDMIDIGenerator.generateMIDI(from: sheet)
        #expect(midi.count > 1000)

        // MusicXML export
        let xml = TMDMusicXMLGenerator.generateMusicXML(from: sheet)
        #expect(xml.contains("<score-partwise"))

        // ABC export
        let abc = TMDABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("X:1"))

        // WAV rendering on macOS
        #if os(macOS)
        let wav = try TMDWAVRenderer.renderWAV(from: sheet)
        #expect(wav.count > 1000)
        #endif
    }

    @Test("Evaluates (layer A (loop B 10)) with concrete paragraphs without requiring explicit instrument arguments")
    func testLayerWithBareConcreteParagraphsAndTwoArgLoop() throws {
        let input = """
        ::SCORE::
        ** Layer Bare Concrete Paragraph & 2-arg Loop **
        != 120
        ?= C
        <4/4>

        A:Piano@|0|{
            <4*>
            1 2 3 4
        }

        B:Bass@|0|{
            <4*>
            1_ - 5_ -
        }

        -> (layer
             A
             (loop B 10)) ->#
        """
        let sheet = try #require(TmdParser.parse(string: input))
        let expanded = try TMDMacroEvaluator.expandThrowing(sheet)

        #expect(expanded.orders.count == 1)
        if case .name(let orderName) = expanded.orders[0] {
            #expect(orderName.hasPrefix("__layer_"))
        } else {
            Issue.record("Expected Order.name for expanded layer")
        }

        let piano = TMDPlaybackRenderer.render(sheet: expanded, instrument: "Piano")
        let bass = TMDPlaybackRenderer.render(sheet: expanded, instrument: "Bass")

        #expect(piano.duration == 40.0)
        #expect(piano.events.count == 4)

        #expect(bass.duration == 40.0)
        #expect(bass.events.count == 20)
    }

    @Test("Throwing parser rejects unclosed S-expression macro parenthesis before arrow")
    func testThrowingParserRejectsUnclosedMacroParen() throws {
        let input = """
        ::SCORE::
        ** Unclosed Macro Paren **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }

        -> (play Theme Piano ->#
        """
        #expect(throws: TMDParseError.self) {
            try TmdParser.parseThrowing(string: input)
        }
    }
}
