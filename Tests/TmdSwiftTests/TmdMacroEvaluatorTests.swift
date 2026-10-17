import Foundation
import Testing
import TmdABC
import TmdAudio
import TmdMIDI
import TmdMusicXML

@testable import TmdSwift

@Suite("Macro Evaluator & S-Expression Tests")
struct MacroEvaluatorTests {

    @Test("Parses abstract paragraphs declared without instrument bindings (Theme { ... })")
    func testParseAbstractEntry() throws {
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
        #expect(sheet.entries.count == 1)
        let p = sheet.entries[0]
        #expect(p.name == "Theme")
        #expect(p.assignment == nil)  // A nil assignment indicates an abstract prototype
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
        #expect(sheet.playback.count == 1)
        guard case .macro(let expr) = sheet.playback[0] else {
            Issue.record("Expected .macro order but got \(sheet.playback[0])")
            return
        }
        let expected = SExpr.list([
            .symbol("canon"),
            .symbol("Theme"),
            .list([.symbol("Violin1"), .symbol("Violin2")]),
            .number(2),
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
        let playback = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
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
        let playback = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Cello")
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
                3^ 2^ 1^ 7 | 6 5 6 7 | 1^ 7 6 5 | 4 3 4 2
            }

            -> (canon Theme (Violin1 Violin2 Violin3) 2) ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        let v1 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let v3 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin3")

        #expect(v1.events[0].position == 0)
        #expect(v2.events[0].position == 8)  // 2 measures * 4 beats
        #expect(v3.events[0].position == 16)  // 4 measures * 4 beats

        #expect(v1.events.count == 16)
        #expect(v2.events.count == 16)
        #expect(v3.events.count == 16)
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
        let v1 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let f1 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Flute1")
        let f2 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Flute2")

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

        let cello = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Cello")
        let v1 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let v3 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin3")

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

    @Test("Passes TmdMeasureChecker and exports MIDI / WAV seamlessly")
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
        let issues = TmdMeasureChecker.check(source: input)
        #expect(issues.isEmpty)

        // 2. MIDI generation produces valid bytes without throwing
        let sheet = try #require(TmdParser.parse(string: input))
        let midiBytes = try TmdMIDIGenerator.generateMIDI(from: sheet)
        #expect(midiBytes.count > 50)

        // 3. WAV synthesis produces valid RIFF WAV data
        #if os(macOS)
            let wavBytes = try TmdWAVRenderer.renderWAV(from: sheet)
            #expect(wavBytes.count > 44)
            let header = String(data: wavBytes.subdata(in: 0..<4), encoding: .ascii)
            #expect(header == "RIFF")
        #endif
    }

    @Test(
        "Supports multiple sequential themes in canon and loop: (canon (Theme1 Theme2) ...) and (loop (Bass1 Bass2) ...)"
    )
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

        let v1 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin1")
        let v2 = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin2")
        let cello = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Cello")

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
        let v = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
        #expect(v.events.count == 4)

        let pitches = v.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
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
        let v = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
        let pitches = v.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
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
        let v = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Violin")
        let pitches = v.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
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
                 (canon (vary Subject reverse -12) (Cello Bass) 1)) ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        let violin = TmdPlaybackRenderer.render(sheet: sheet, instrument: "SoloViolin")
        let flute = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Flute")
        let cello = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Cello")
        let bass = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Bass")

        let violinPitches = violin.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(violinPitches == [60, 62, 64, 67])

        let flutePitches = flute.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(flutePitches == [79, 81, 83, 86])

        let celloPitches = cello.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(celloPitches == [55, 52, 50, 48])
        #expect(cello.events[0].position == 0)

        let bassPitches = bass.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(bassPitches == [55, 52, 50, 48])
        #expect(bass.events[0].position == 4)
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
        let playback = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
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
        let minorPlayback = TmdPlaybackRenderer.render(sheet: sheet, instrument: "MinorPiano")
        let minorPitches = minorPlayback.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(minorPitches == [60, 62, 63, 65, 67, 68, 70, 72])

        let majorPlayback = TmdPlaybackRenderer.render(sheet: sheet, instrument: "MajorPiano")
        let majorPitches = majorPlayback.events.compactMap { e -> Int? in
            if case .note(let note) = e.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: e.state.keyOffset)
            }
            return nil
        }
        #expect(majorPitches == [60, 62, 64, 65, 67, 69, 71, 72])
    }

    @Test("Validates canon_in_d_macro.tmd end-to-end score")
    func testCanonInDMacroSample() throws {
        let sampleURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("sample/basic/canon_in_d_macro.tmd")
        let sheet = try TmdParserIO.parseThrowing(url: sampleURL)
        #expect(sheet.name.contains("Canon in D"))

        // Measure consistency check: 0 errors
        let issues = TmdMeasureChecker.check(
            source: try String(contentsOf: sampleURL, encoding: .utf8))
        #expect(issues.isEmpty)

        // MIDI export
        let midi = try TmdMIDIGenerator.generateMIDI(from: sheet)
        #expect(midi.count > 1000)

        // MusicXML export
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        #expect(xml.contains("<score-partwise"))

        // ABC export
        let abc = TmdABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("X:1"))

        // WAV rendering on macOS
        #if os(macOS)
            let wav = try TmdWAVRenderer.renderWAV(from: sheet)
            #expect(wav.count > 1000)
        #endif
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
        #expect(throws: TmdParseError.self) {
            try TmdParser.parseThrowing(string: input)
        }
    }

    @Test("Explicit notation keys do not transpose playback pitches")
    func testExplicitKeyIsPitchNeutral() throws {
        let input = """
            ::SCORE::
            ** Explicit Key Metadata **
            != 120
            ?= C
            key= C
            <4/4>

            Intro:Piano@|0|{
                <4*>
                1 2 3 4 | {key= F#m} 1 2 3 4
            }

            -> Intro ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        let playback = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
        let pitches = playback.events.compactMap { event -> Int? in
            if case .note(let note) = event.content {
                return TmdMIDIGenerator.noteToMIDIPitch(note, keyOffset: event.state.keyOffset)
            }
            return nil
        }

        #expect(pitches == [60, 62, 64, 65, 60, 62, 64, 65])
        #expect(playback.events.dropFirst(4).allSatisfy { $0.state.keyOffset == 0 })
    }

    @Test("Concrete sections are not valid macro sources")
    func testConcreteSectionCannotBeMacroSource() throws {
        let input = """
            ::SCORE::
            ** Concrete Macro Source **
            != 120
            ?= C
            <4/4>

            Intro:Piano@|0|{
                <4*>
                1 2 3 4
            }

            -> (play Intro Violin) ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        #expect(throws: TmdMacroError.self) {
            try TmdMacroEvaluator.expandThrowing(sheet)
        }
    }

    @Test("Loop requires an explicit instrument and positive iteration count")
    func testLoopRequiresInstrumentAndPositiveCount() throws {
        let input = """
            ::SCORE::
            ** Invalid Loop **
            != 120
            ?= C
            <4/4>

            Theme {
                <4*>
                1 2 3 4
            }

            -> (loop Theme 0) ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        #expect(throws: TmdMacroError.self) {
            try TmdMacroEvaluator.expandThrowing(sheet)
        }
    }

    @Test("Canon rejects voices that enter after the prototype ends")
    func testCanonRejectsEntryAfterPrototypeDuration() throws {
        let input = """
            ::SCORE::
            ** Canon Duration Bound **
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
        #expect(throws: TmdMacroError.self) {
            try TmdMacroEvaluator.expandThrowing(sheet)
        }
    }

    @Test("Empty layer and sequence expressions are rejected")
    func testEmptyCompositionExpressionsAreRejected() throws {
        for expression in ["(layer)", "(seq)"] {
            let input = """
                ::SCORE::
                ** Empty Composition **
                != 120
                ?= C
                <4/4>

                Theme {
                    <4*>
                    1 2 3 4
                }

                -> \(expression) ->#
                """
            let sheet = try #require(TmdParser.parse(string: input))
            #expect(throws: TmdMacroError.self) {
                try TmdMacroEvaluator.expandThrowing(sheet)
            }
        }
    }

    @Test("Non-throwing expansion delegates to the throwing canonical engine")
    func testNonThrowingExpansionMatchesThrowingExpansion() throws {
        let input = """
            ::SCORE::
            ** Expansion API parity **
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
        let throwingResult = try TmdMacroEvaluator.expandThrowing(sheet)
        let compatibilityResult = TmdMacroEvaluator.expandOrTrap(sheet)

        #expect(compatibilityResult == throwingResult)

    }

    @Test("Issue #39: TmdMacroEvaluator.expandThrowing preserves declaredKey")
    func testMacroEvaluatorPreservesDeclaredKey() throws {
        let input = """
            ::SCORE::
            ** Declared Key Preservation **
            != 120
            ?= C
            key= Am
            <4/4>

            Theme {
                <4*>
                6, 7, 1 2
            }

            -> (play Theme Violin) ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        #expect(sheet.declaredKey == "Am")
        let expanded = try TmdMacroEvaluator.expandThrowing(sheet)
        #expect(expanded.declaredKey == "Am")
    }

    @Test(
        "Issue #39: TmdMeasureRenderer preserves tempo and keyOffset on rest-only measures and avoids extra measures on time-sig expansion"
    )
    func testMeasureRendererStateRetentionAndTimeSignatureChange() throws {
        let input = """
            ::SCORE::
            ** Measure Renderer State & TimeSig **
            != 100
            ?= C
            <2/4>

            PartA:Piano@|0|{
                <4*>
                {!= 140} {?+2} 1 2 | {<4/4>} 0 0 0 0
            }

            -> PartA ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")
        // Measure 0 is 2/4 (2 beats), Measure 1 is 4/4 (4 beats) = 6 beats total -> exactly 2 measures
        #expect(measures.count == 2)
        #expect(measures[0].tempo == 140)
        #expect(measures[0].keyOffset == 2)
        // Measure 1 is rest-only (0 0 0 0) and must retain tempo=140 and keyOffset=2
        #expect(measures[1].tempo == 140)
        #expect(measures[1].keyOffset == 2)
        #expect(measures[1].events.allSatisfy { $0.state.tempo == 140 && $0.state.keyOffset == 2 })
    }

    @Test("Issue #39: Trailing key directive in fixedPitch paragraph does not shift keyOffset")
    func testTrailingDirectiveInFixedPitchParagraph() throws {
        let input = """
            ::SCORE::
            ** Fixed Pitch Trailing Directive **
            != 120
            ?= C
            <4/4>

            PartA:Piano [pitchMode=fixed] @|0|{
                <4*>
                1 2 3 4 {?+5}
            }

            -> PartA ->#
            """
        let sheet = try #require(TmdParser.parse(string: input))
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
        let trailingKeyDir = try #require(timeline.directives.last)
        #expect(trailingKeyDir.state.keyOffset == 0)
    }

    @Test("Issue #39: Lexer rolls back unquoted ~ without consuming subsequent note token")
    func testLexerUnquotedTildeRollback() throws {
        let lexer = Lexer(string: "~ 1 2")
        let tokens = lexer.tokenize()
        #expect(tokens.count == 4)  // .identifier("~"), .note(1), .note(2), .eof
        #expect(tokens[0] == Token.identifier("~"))
        if case .note(let n1) = tokens[1] {
            #expect(n1.degree.rawValue == 1)
        } else {
            Issue.record("Expected second token to be .note(1)")
        }
    }

    @Test(
        "Issue #39: Parser reports accurate source line on {?=fixed} and PitchMapping.parseKeyModeAndFifths supports min suffix"
    )
    func testParserFixedDirectiveFailurePositionAndMinSuffix() throws {
        let invalidInput = """
            ::SCORE::
            ** Fixed Directive Diagnostic **
            != 120
            ?= C
            <4/4>

            PartA:Piano@|0|{
                <4*>
                {?=fixed} 1 2 3 4
            }

            -> PartA ->#
            """
        do {
            _ = try TmdParser.parseThrowing(string: invalidInput)
            Issue.record("Expected TmdParseError for {?=fixed}")
        } catch let error as TmdParseError {
            #expect(error.range.start.line == 9)
        }

        let amin = PitchMapping.parseKeyModeAndFifths("Amin")
        #expect(amin.fifths == 0)
        #expect(amin.mode == "minor")
        let fSharpMin = PitchMapping.parseKeyModeAndFifths("F# min")
        #expect(fSharpMin.fifths == 3)
        #expect(fSharpMin.mode == "minor")
    }

    @Test(
        "Issue #45: Validator, Inspector, and CLI do not SIGTRAP when macro expansion fails on a score with concrete entries"
    )
    func testIssue45ValidatorAndInspectorDoNotTrapOnMacroErrorWithConcreteEntries() throws {
        let scoreWithMacroError = """
            ::SCORE::
            ** Macro Error With Concrete Entry **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
            }

            -> A
            -> (play A Violin)
            ->#
            """
        let sheet = try TmdParser.parseThrowing(string: scoreWithMacroError)
        #expect(throws: TmdMacroError.self) {
            try TmdMacroEvaluator.expandThrowing(sheet)
        }

        // Non-throwing expandOrTrap must skip the invalid macro without SIGTRAP
        let bestEffort = TmdMacroEvaluator.expandOrTrap(sheet)
        #expect(bestEffort.playback == [.name("A")])

        // Validator must return E-MACRO-EXPAND without trapping in Stage 2c validateTempoConflicts
        let diagnostics = TmdScoreValidator.validate(source: scoreWithMacroError)
        #expect(diagnostics.contains { $0.rule == .macroExpand && $0.severity == .error })

        // Inspector must not trap on unexpandable macros
        let profile = TmdSongInspector.inspect(sheet: sheet)
        #expect(profile.title == "Macro Error With Concrete Entry")
    }

    @Test("Issue #45: (layer (seq ...)) advances bar offsets across sequential child expressions")
    func testIssue45LayerWithNestedSeqAdvancesBarOffsets() throws {
        let score = """
            ::SCORE::
            ** Layer Seq Offset **
            != 120
            ?= C
            <4/4>

            WeirdMotif {
                <8*>
                | 6_ 1 2' 3 6 5 2' 1 | 7_ 1 2' 6_ 3 - 0 0 |
            }

            WeirdPulse {
                <8*>
                | 6_ 0 6'_ 0 6_ 0 5_ 1 | 2_ 0 2'_ 0 3_ - 0 0 |
            }

            -> (layer
                (seq
                    (play (reverse WeirdMotif) Harpsichord)
                    (play (flip WeirdMotif) Flute)
                    (play (transpose WeirdMotif 5) Harpsichord))
                (loop WeirdPulse PizzicatoStrings 3))
            ->#
            """
        let sheet = try TmdParser.parseThrowing(string: score)
        let expanded = try TmdMacroEvaluator.expandThrowing(sheet)

        let layerEntries = expanded.entries.filter { $0.name.hasPrefix("__layer_") }
        #expect(layerEntries.count == 4)

        let harpsichordEntries = layerEntries.filter { $0.assignment == "Harpsichord" }.sorted {
            $0.start < $1.start
        }
        let fluteEntry = try #require(layerEntries.first { $0.assignment == "Flute" })
        let pizzEntry = try #require(layerEntries.first { $0.assignment == "PizzicatoStrings" })

        #expect(harpsichordEntries.count == 2)
        #expect(harpsichordEntries[0].start == 0)
        #expect(fluteEntry.start == 2)
        #expect(harpsichordEntries[1].start == 4)
        #expect(pizzEntry.start == 0)

        // And ScoreValidator must not report any E-TIMELINE-OVERLAP for the two Harpsichord steps in (seq ...)
        let diagnostics = TmdScoreValidator.validate(source: score)
        let errors = diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty)
    }
}
