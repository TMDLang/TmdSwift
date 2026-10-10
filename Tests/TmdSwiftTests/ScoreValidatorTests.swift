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
}
