import Foundation
import Testing
import TmdLSP

@testable import TmdSwift

@Suite("Score Validator & Semantic Linter Tests")
struct ScoreValidatorTests {

    @Test func testCatchesSyntaxAndMeasureErrors() throws {
        // Invalid ?= Am movable-do key
        let invalidSyntax = """
            ::SCORE::
            ** Invalid Key **
            != 120
            ?= Am
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
            }
            -> A ->#
            """
        let syntaxDiagnostics = TmdScoreValidator.validate(source: invalidSyntax)
        #expect(syntaxDiagnostics.contains { $0.rule == .syntax && $0.severity == .error })

        // Measure beat discrepancy
        let invalidMeasure = """
            ::SCORE::
            ** Bad Measure **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 |
            }
            -> A ->#
            """
        let measureDiagnostics = TmdScoreValidator.validate(source: invalidMeasure)
        #expect(measureDiagnostics.contains { $0.rule == .measureBeat && $0.severity == .error })
    }

    @Test func testCatchesMacroExpansionOverlapAndTempoConflicts() throws {
        // 1. Unknown macro prototype -> E-MACRO-EXPAND
        let badMacro = """
            ::SCORE::
            ** Bad Macro **
            != 120
            ?= C
            <4/4>

            Theme {
                <4*>
                | 1 2 3 4 |
            }
            -> (canon NonExistent (Piano Violin) 1 0) ->#
            """
        let macroDiags = TmdScoreValidator.validate(source: badMacro)
        #expect(macroDiags.contains { $0.rule == .macroExpand && $0.severity == .error })

        // 2. Same-instrument timeline overlap -> E-TIMELINE-OVERLAP
        let overlapScore = """
            ::SCORE::
            ** Overlap **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 | 5 6 7 1^ |
            }
            A:Piano@|+1|{
                <4*>
                | 1 2 3 4 |
            }
            -> A ->#
            """
        let overlapDiags = TmdScoreValidator.validate(source: overlapScore)
        #expect(overlapDiags.contains { $0.rule == .timelineOverlap && $0.severity == .error })

        // 3. Simultaneous tempo conflict -> E-TEMPO-CONFLICT
        let tempoConflictScore = """
            ::SCORE::
            ** Tempo Conflict **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | {!= 140} 1 2 3 4 |
            }
            A:Violin@|0|{
                <4*>
                | {!= 100} 1 2 3 4 |
            }
            -> A ->#
            """
        let tempoDiags = TmdScoreValidator.validate(source: tempoConflictScore)
        #expect(tempoDiags.contains { $0.rule == .tempoConflict && $0.severity == .error })
    }

    @Test func testChordMultiNoteErrorAndCustomWarning() throws {
        // [1 3 5] -> E-CHORD-MULTINOTE (error) with suggestion '1+3+5'
        let multiNoteChordScore = """
            ::SCORE::
            ** MultiNote Chord Typo **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | [1 3 5] - - - |
            }
            -> A ->#
            """
        let multiDiags = TmdScoreValidator.validate(source: multiNoteChordScore)
        let chordErr = multiDiags.first { $0.rule == .chordMultiNote }
        #expect(chordErr != nil)
        #expect(chordErr?.severity == .error)
        #expect(chordErr?.suggestion?.contains("1+3+5") == true)

        // [Cmaj13sharp11] -> W-CHORD-CUSTOM (warning), while [Cmaj9] / [Cadd9] -> valid (no warning)
        let customChordScore = """
            ::SCORE::
            ** Custom Chord Warning **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | [Cadd9] - [Cweirdquality] - |
            }
            -> A ->#
            """
        let customDiags = TmdScoreValidator.validate(source: customChordScore)
        #expect(!customDiags.contains { $0.message.contains("Cadd9") })
        #expect(
            customDiags.contains {
                $0.rule == .chordCustom && $0.severity == .warning
                    && $0.message.contains("Cweirdquality")
            })
    }

    @Test func testUnusedEntriesPrototypesAndInstrumentWarnings() throws {
        let score = """
            ::SCORE::
            ** Unused and Instrument Warnings **
            != 120
            ?= C
            <4/4>

            UnusedProto {
                <4*>
                | 1 2 3 4 |
            }

            A:nylonGuitar@|0|{
                <4*>
                | 1 2 3 4 |
            }

            A:UnknownMartianZorg@|0|{
                <4*>
                | 1 2 3 4 | 5 6 7 1^ |
            }

            Bridge:Nylon_Guitar@|0|{
                <4*>
                | 1 2 3 4 |
            }

            -> A ->#
            """
        let diags = TmdScoreValidator.validate(source: score)

        // Bridge is unused -> W-UNUSED-ENTRY
        #expect(
            diags.contains {
                $0.rule == .unusedEntry && $0.severity == .warning && $0.message.contains("Bridge")
            })
        // UnusedProto is unused -> W-UNUSED-PROTOTYPE
        #expect(
            diags.contains {
                $0.rule == .unusedPrototype && $0.severity == .warning
                    && $0.message.contains("UnusedProto")
            })
        // nylonGuitar vs Nylon_Guitar -> W-INSTRUMENT-INCONSISTENT
        #expect(
            diags.contains {
                $0.rule == .instrumentInconsistent && $0.severity == .warning
            })
        // UnknownMartianZorg -> W-INSTRUMENT-UNKNOWN
        #expect(
            diags.contains {
                $0.rule == .instrumentUnknown && $0.severity == .warning
                    && $0.message.contains("UnknownMartianZorg")
            })
        // In section A, nylonGuitar has 1 measure while UnknownMartianZorg has 2 measures -> W-SECTION-LENGTH-MISMATCH
        #expect(
            diags.contains {
                $0.rule == .sectionLengthMismatch && $0.severity == .warning
            })
    }

    @Test func testMarkdownSnippetExtractionAndLSPIntegration() throws {
        let markdown = """
            # TMD Guide

            Here is a full score:
            ```tmd
            ::SCORE::
            ** Embedded Score **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | [1 3 5] - - - |
            }
            -> A ->#
            ```

            And a partial snippet without header:
            ```tmd
            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
            }
            ```
            """
        let mdDiags = TmdScoreValidator.validateMarkdown(source: markdown, file: "guide.md")
        // Full score has [1 3 5] on line 13 of guide.md, while partial snippet has 0 errors and does not warn about unused A
        #expect(mdDiags.count == 1)
        #expect(mdDiags.first?.rule == .chordMultiNote)
        #expect(mdDiags.first?.line == 13)

        // LSP integration maps error to severity 1 and warning to severity 2
        let lspDiags = TmdLSPDiagnosticEngine.diagnose(
            source: """
                ::SCORE::
                ** LSP Check **
                != 120
                ?= C
                <4/4>
                A:Piano@|0|{
                    <4*>
                    | [1 3 5] - - - |
                }
                Unused:Piano@|0|{
                    <4*>
                    | 1 2 3 4 |
                }
                -> A ->#
                """)
        #expect(lspDiags.contains { $0.severity == 1 })
        #expect(lspDiags.contains { $0.severity == 2 })
    }

    @Test func testValidationAndTransformSSOT() throws {
        // 1. ChordSymbol.extendedChordQualities / isRecognizedExtendedQuality (unified with tmd-ts)
        #expect(ChordSymbol.extendedChordQualities.contains("add9"))
        #expect(ChordSymbol.extendedChordQualities.contains("m7b5"))
        #expect(ChordSymbol.extendedChordQualities.contains("m(maj7)"))
        #expect(ChordSymbol.extendedChordQualities.contains("min9"))
        #expect(ChordSymbol.extendedChordQualities.contains("aug7"))
        #expect(ChordSymbol.isRecognizedExtendedQuality("7#11"))
        #expect(ChordSymbol.isRecognizedExtendedQuality("69"))
        #expect(!ChordSymbol.isRecognizedExtendedQuality("weirdquality"))

        // 2. MIDIInstrument.isRecognized (including GM, CJK, vocal, and role keywords)
        #expect(MIDIInstrument.isRecognized("Piano"))
        #expect(MIDIInstrument.isRecognized("prog:40"))
        #expect(MIDIInstrument.isRecognized("Perc"))
        #expect(MIDIInstrument.isRecognized("Gtr"))
        #expect(MIDIInstrument.isRecognized("Uke"))
        #expect(MIDIInstrument.isRecognized("Vox"))
        #expect(MIDIInstrument.isRecognized("Miku"))
        #expect(MIDIInstrument.isRecognized("鋼琴"))
        #expect(MIDIInstrument.isRecognized("電吉他"))
        #expect(MIDIInstrument.isRecognized("古箏"))
        #expect(!MIDIInstrument.isRecognized("Unknown"))
        #expect(!MIDIInstrument.isRecognized("UnknownMartianZorg"))

        // 3. Section.mapNotes / [Section].mapNotes
        let sheet = try TmdParser.parseThrowing(
            string: """
                ::SCORE::
                != 120
                ?= C
                <4/4>
                A:Piano@|0|{
                    <4*>
                    | 1 2+4 [C] 0 |
                }
                -> A ->#
                """)
        let sec = try #require(sheet.entries.first?.sections.first)
        let shiftedSections = [sec].mapNotes { note in
            TmdRefactor.transposeNoteDiatonicSteps(note, steps: 2)
        }
        let formattedSection = shiftedSections.first?.format() ?? ""
        #expect(formattedSection.contains("3 4+6 [C] 0"))

        // 4. TmdScoreValidator source does not duplicate knownInstrumentKeywords or extendedChordQualities
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let validatorSrc = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/TmdSwift/Validation/TmdScoreValidator.swift"),
            encoding: .utf8
        )
        #expect(!validatorSrc.contains("knownInstrumentKeywords"))
        #expect(!validatorSrc.contains("private static let extendedChordQualities"))
    }

    @Test func testPlaybackTimelineAndExporterSSOT() throws {
        // 1. Sheet.effectivePlaybackOrders fallback when playback is empty
        let sheetNoOrders = try TmdParser.parseThrowing(
            string: """
                ::SCORE::
                != 120
                ?= C
                <4/4>
                Intro:Piano@|0|{
                    <4*>
                    | 1 2 3 4 |
                }
                Verse:Piano@|0|{
                    <4*>
                    | 5 6 7 1^ |
                }
                ->#
                """)
        #expect(sheetNoOrders.effectivePlaybackOrders == [.name("Intro"), .name("Verse")])

        // 2. TmdPlaybackRenderer.buildTempoSegments and quarterToSeconds
        let tempoSheet = try TmdParser.parseThrowing(
            string: """
                ::SCORE::
                != 120
                ?= C
                <4/4>
                A:Piano@|0|{
                    <4*>
                    | 1 2 3 4 | {!= 60} 1 2 3 4 |
                }
                -> A ->#
                """)
        let conductor = TmdPlaybackRenderer.renderConductor(sheet: tempoSheet)
        let segments = TmdPlaybackRenderer.buildTempoSegments(
            initialTempo: tempoSheet.speed,
            initialBeat: tempoSheet.beat,
            directives: conductor.directives
        )
        #expect(segments.count == 2)
        // First 4 beats at 120 BPM = 2.0s; next 4 beats at 60 BPM = 4.0s -> total 6.0s at beat 8
        let secAt8 = TmdPlaybackRenderer.quarterToSeconds(8.0, segments: segments)
        #expect(abs(secAt8 - 6.0) < 1e-6)

        // 3. MIDIInstrument.allocateChannel and stereoPanHeuristic
        var nextMelody: UInt8 = 8
        let ch1 = MIDIInstrument.piano.allocateChannel(nextMelodicChannel: &nextMelody)
        let ch2 = MIDIInstrument.violin.allocateChannel(nextMelodicChannel: &nextMelody)
        let chPerc = MIDIInstrument.percussion.allocateChannel(nextMelodicChannel: &nextMelody)
        #expect(ch1 == 8)
        #expect(ch2 == 10)  // Skips channel 9
        #expect(chPerc == 9)
        #expect(MIDIInstrument.stereoPanHeuristic(for: "Guitar-L") == .left)
        #expect(MIDIInstrument.stereoPanHeuristic(for: "Piano_Right") == .right)
        #expect(MIDIInstrument.stereoPanHeuristic(for: "Lead") == .center)

        // 4. Beat.metronomeTempo (compound meter 6/8 at 120 quarter BPM -> dotted quarter = 80)
        let compound = Beat(count: 6, noteValue: 8).metronomeTempo(forQuarterBPM: 120)
        #expect(compound.beatUnit == "quarter")
        #expect(compound.lilyPondUnit == "4.")
        #expect(compound.abcUnit == "3/8")
        #expect(compound.isDotted == true)
        #expect(compound.perMinute == 80)
    }

    @Test func testNonFourFourPickupAndPolymeterAlignment() throws {
        let score = """
            ::SCORE::
            ** Odd Meter Pickups & Polymeter **
            != 120
            ?= C
            <4/4>

            Intro:Flute@|0|{
                <4*>
                | 1 2 3 4 | 1 2 3 4 |
            }
            Intro:Clarinet@|0|{
                <4*>
                | 1 2 3 4 | 1 2 3 4 |
            }

            M5:Clarinet@|-1|{
                <4*>
                | {<5/4>} 0 0 0 0 5, |
                | 1 2 3 4 5 | 5 4 3 2 1 |
                | 1 3 5 3 1 | 2 5, 1 - - |
            }
            M5:Flute@|0|{
                <4*>
                | {<5/4>} 3 4 5 6 7 | 1^ 7 6 5 4 |
                | 3 5 1^ 5 3 | 4 2 3 - - |
            }

            M7:Flute@|-1|{
                <8*>
                | {<7/8>} 0 0 0 0 5 6 7 |
                | 1 2 3 4 5 6 7 | 1^ 7 6 5 4 3 2 |
                | 1 3 5 1^ 7 5 3 | 2 4 3 2 1 - - |
            }
            M7:Clarinet@|0|{
                <8*>
                | {<7/8>} 1, - 5, - 1 - 5, | 4, - 1 - 4 - 1 |
                | 5, - 2 - 5 - 2 | 1, - 5, - 1 - - |
            }

            M11:Oboe@|-1|{
                <8*>
                | {<11/8>} 0 0 0 0 0 0 0 0 5 6 7 |
                | 1 2 3 4 5 6 7 1^ 2^ 3^ 2^ | 1^ 7 6 5 4 3 2 1 2 3 4 |
                | 5 6 7 1^ 2^ 1^ 7 6 5 4 3 | 2 3 4 5 3 1 5, 1 - - - |
            }
            M11:Flute@|0|{
                <8*>
                | {<11/8>} 3 4 5 6 7 1^ 2^ 3^ 4^ 5^ 4^ | 3^ 2^ 1^ 7 6 5 4 3 4 5 6 |
                | 7 1^ 2^ 3^ 4^ 3^ 2^ 1^ 7 6 5 | 4 5 6 7 5 3 2 3 - - - |
            }

            M13:Violin@|-1|{
                <8*>
                | {<13/8>} 0 0 0 0 0 0 0 0 0 5 6 7 2^ |
                | 1^ 7 6 5 4 3 2 1 2 3 4 5 6 | 5 6 7 1^ 2^ 3^ 4^ 5^ 4^ 3^ 2^ 1^ 7 |
                | 1^ 5 3 1 6 4 2 7, 5 3 1 2 7, | 1 - - 5, - - 1 - - - - - - |
            }
            M13:Flute@|0|{
                <8*>
                | {<13/8>} 3^ 2^ 1^ 7 6 5 4 3 4 5 6 7 1^ | 7 1^ 2^ 3^ 4^ 5^ 6^ 7^ 6^ 5^ 4^ 3^ 2^ |
                | 3^ 1^ 5 3 1^ 6 4 2 7 5 3 4 2 | 3 - - 1 - - 3 - - - - - - |
            }

            Poly:Flute@|0|{
                <8*>
                | {<5/8>} 1 2 3 4 5 | 6 5 4 3 2 | 1 3 5 3 1 | 2 4 6 4 2 |
                | 3 5 1^ 5 3 | 4 6 2^ 6 4 | 5 4 3 2 1 |
            }
            Poly:Clarinet@|0|{
                <8*>
                | {<7/8>} 1, 5, 1 3 5 3 1 | 4, 1 4 6 1^ 6 4 |
                | 5, 2 5 7 2^ 7 5 | 6, 3 6 1^ 3^ 1^ 6 |
                | 5, 2 5 7 1^ - - |
            }

            -> Intro -> M5 -> M7 -> M11 -> M13 -> Poly ->#
            """

        // 1. Validator should emit 0 errors and 0 W-SECTION-LENGTH-MISMATCH warnings
        let diags = TmdScoreValidator.validate(source: score)
        let mismatchDiags = diags.filter { $0.rule == .sectionLengthMismatch }
        #expect(mismatchDiags.isEmpty)
        #expect(diags.filter { $0.severity == .error }.isEmpty)

        // 2. Section durations (from downbeat bar 0 to end of section) must reflect entry-local time signatures
        let sheet = try TmdParser.parseThrowing(string: score)
        #expect(abs(TmdPlaybackRenderer.duration(of: "M5", in: sheet) - 20.0) < 1e-6)
        #expect(abs(TmdPlaybackRenderer.duration(of: "M7", in: sheet) - 14.0) < 1e-6)
        #expect(abs(TmdPlaybackRenderer.duration(of: "M11", in: sheet) - 22.0) < 1e-6)
        #expect(abs(TmdPlaybackRenderer.duration(of: "M13", in: sheet) - 26.0) < 1e-6)

        // 3. Playback timeline downbeat alignment:
        // Intro is 8.0 beats, M5 is 20.0 beats -> M7 downbeat is at 28.0 beats.
        // Flute's M7 pickup starts 3.5 beats before 28.0 (= 24.5), and its bar 0 downbeat note (degree 1) is at 28.0,
        // matching Clarinet's M7 bar 0 downbeat note (degree 1,) at 28.0.
        let fluteTimeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Flute")
        let clarinetTimeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Clarinet")
        let fluteM7PickupEvent = fluteTimeline.events.first { abs($0.position - 24.5) < 1e-6 }
        let fluteM7DownbeatEvent = fluteTimeline.events.first { abs($0.position - 28.0) < 1e-6 }
        let clarinetM7DownbeatEvent = clarinetTimeline.events.first { abs($0.position - 28.0) < 1e-6 }
        #expect(fluteM7PickupEvent != nil)
        #expect(fluteM7DownbeatEvent != nil)
        #expect(clarinetM7DownbeatEvent != nil)

        // 4. Measure renderer slices Flute's M7 pickup at 24.5..<28.0 with 7/8 time signature
        let fluteMeasures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Flute")
        let pickupMeasure = fluteMeasures.first { abs($0.startTime - 24.5) < 1e-6 }
        #expect(pickupMeasure != nil)
        #expect(pickupMeasure?.timeSignature == Beat(count: 7, noteValue: 8))
        #expect(abs((pickupMeasure?.nominalDuration ?? 0) - 3.5) < 1e-6)
    }
}
