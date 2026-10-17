import Foundation
import Testing
import TmdBraille

@testable import TmdSwift

@Suite("TmdBraille Generator Validation Tests")
struct BrailleValidationTests {
    @Test("Worked Example 1: Single-section Canon Excerpt matches Section 9.2 Unicode and BRF")
    func workedExample1CanonExcerpt() throws {
        let source = """
            ::SCORE::
            ** Canon Excerpt **
            != 56
            ?= D
            key= D
            <4/4>

            intro:Violin1@|0|{
                <4*>
                {mf} 3^ 2^ 1^ 7 | 1+3+5 - - - |
            }

            intro:Cello@|0|{
                <4*>
                {p} 1_ 5__ 6__ 3__ | 4__ - 5__ - |
            }

            -> intro ->#
            """
        let sheet = try TmdParser.parseThrowing(string: source)

        let unicodeOutput = TmdBrailleGenerator.generateBraille(from: sheet)
        let expectedUnicode = """
            ⠠⠉⠁⠝⠕⠝ ⠠⠑⠭⠉⠑⠗⠏⠞
            ⠹⠶⠼⠑⠋ ⠩⠩⠼⠙⠲
            ⠜⠧⠇⠂⠄ ⠜⠍⠋⠨⠻⠫⠱⠹ ⠐⠵⠬⠔⠣⠅
            ⠜⠧⠉⠄ ⠜⠏⠸⠱⠘⠪⠺⠻ ⠗⠎⠣⠅

            """
        #expect(unicodeOutput == expectedUnicode)

        let brfOutput = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart)
        )
        let expectedBrf = """
            ,CANON ,EXCERPT
            ?7#EF %%#D4
            >VL1' >MF.]$:? "Z+9<K
            >VC' >P_:^[W] RS<K

            """
        #expect(brfOutput == expectedBrf)
    }

    @Test(
        "Worked Example 2: Playback Demo with Canon, Modulation, Fixed Pitch, and Show Filtering matches Section 9.3"
    )
    func workedExample2PlaybackDemo() throws {
        let source = """
            ::SCORE::
            ** Playback Demo **
            != 120
            ?= C
            <4/4>

            /* Unbound prototype (excluded unless bound by playback) */
            Theme {
                <2*>
                1 3 |
            }

            outro:Violin1@|0|{
                <1*>
                1 |
            }

            outro:Chord@|+1|{
                <1*>
                [1] |
            }

            outro:Timpani[pitchMode=fixed]@|0|{
                <1*>
                1_ - |
            }

            show:Lighting@outro{
            \"\"\"
            cue blackout
            \"\"\"
            }

            -> (canon Theme (Violin1 Violin2) 1)
            -> {?+2}
            -> outro
            ->#
            """
        let sheet = try TmdParser.parseThrowing(string: source)
        let unicodeOutput = TmdBrailleGenerator.generateBraille(from: sheet)
        let expectedUnicode = """
            ⠠⠏⠇⠁⠽⠃⠁⠉⠅ ⠠⠙⠑⠍⠕
            ⠹⠶⠼⠁⠃⠚ ⠼⠙⠲
            ⠜⠧⠇⠂⠄ ⠐⠝⠏ ⠍ ⠩⠩ ⠐⠵ ⠍⠣⠅
            ⠜⠧⠇⠆⠄ ⠍ ⠐⠝⠏ ⠍⠍⠣⠅
            ⠒⠜ ⠍⠍⠍ ⠠⠙⠸⠄⠣⠅
            ⠜⠞⠊⠍⠄ ⠍⠍ ⠸⠽⠈⠉⠽⠣⠅

            """
        #expect(unicodeOutput == expectedUnicode)

        let brfOutput = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart)
        )
        let expectedBrf = """
            ,PLAYBACK ,DEMO
            ?7#ABJ #D4
            >VL1' "NP M %% "Z M<K
            >VL2' M "NP MM<K
            3> MMM ,D_'<K
            >TIM' MM _Y@CY<K

            """
        #expect(brfOutput == expectedBrf)
        #expect(!unicodeOutput.contains("Lighting"))
    }

    @Test(
        "Supports Bar-over-Bar layout, intra-measure accidentals, flat keys, and multi-pitch chords"
    )
    func barOverBarAndAccidentalsAndChords() throws {
        let source = """
            ::SCORE::
            ** Flat Key Demo **
            != 100
            ?= F
            <4/4>

            verse:Piano@|0|{
                <4*>
                1+3+5 4' 7, 0 |
            }

            verse:Bass@|0|{
                <4*>
                1_ - 5_ - |
            }

            -> verse ->#
            """
        let sheet = try TmdParser.parseThrowing(string: source)
        let barOverBar = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .unicode, layout: .barOverBar)
        )
        #expect(barOverBar.contains("⠣⠼⠙⠲"))
        #expect(barOverBar.contains("⠼⠁"))
        #expect(barOverBar.contains("  ⠜⠏⠝⠄ "))
        #expect(barOverBar.contains("  ⠜⠃⠎⠄ "))
        // 1+3+5 in F major -> F4(4th octave) + A4(3rd) + C5(5th) -> ⠐⠻⠬⠔ and #4 (B natural in F major!) -> ⠡
        #expect(barOverBar.contains("⠐⠻⠬⠔"))
        #expect(barOverBar.contains("⠡"))
    }

    @Test(
        "Issue #59: Solo treble vs bass chord interval direction, #A prefix, centered headers, and single .C chord tie"
    )
    func soloVsEnsembleLayoutChordDirectionAndChordTie() throws {
        let soloTrebleSource = """
            ::SCORE::
            ** Test Score **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
                | 1+3+5 - - - | - 0 0 - |
            }
            -> A ->#
            """
        let soloTrebleSheet = try TmdParser.parseThrowing(string: soloTrebleSource)
        let soloBrf = TmdBrailleGenerator.generateBraille(
            from: soloTrebleSheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart)
        )
        let soloLines = soloBrf.split(separator: "\n", omittingEmptySubsequences: false).map(
            String.init)
        // Centered title (at least 3 leading spaces), blank line, centered header, and #A paragraph start
        #expect(soloLines.count >= 4)
        #expect(soloLines[0].hasPrefix("   "))
        #expect(soloLines[0].trimmingCharacters(in: .whitespaces) == ",TEST ,SCORE")
        #expect(soloLines[1].isEmpty)
        #expect(soloLines[2].hasPrefix("   "))
        #expect(soloLines[2].trimmingCharacters(in: .whitespaces) == "?7#ABJ #D4")
        // Solo treble: starts with #A, and 1+3+5 (C4+E4+G4) is top-down: G4 base note (`(` whole, `\` quarter) + `+9`
        // Cross-bar tied chord uses single `.C` (not `.C.C`)
        #expect(soloLines[3] == "#A \"?:$] (+9.C\\+9VU<K")

        // Solo bass-clef instrument (Cello) uses bottom-up intervals (`Y+9.C?+9`)
        let soloBassSource = """
            ::SCORE::
            ** Bass Solo **
            != 120
            ?= C
            <4/4>

            A:Cello@|0|{
                <4*>
                | 1_+3_+5_ - - - | - 0 0 - |
            }
            -> A ->#
            """
        let soloBassSheet = try TmdParser.parseThrowing(string: soloBassSource)
        let soloBassBrf = TmdBrailleGenerator.generateBraille(
            from: soloBassSheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart)
        )
        #expect(soloBassBrf.contains("#A _Y+9.C?+9VU<K"))
    }

    @Test(
        "Issue #59: Tuplets (2 and _n'), 16th-note beat grouping (Par. 8.1), value distinction signs (,<1 / ^<1), and inline key naturals (*)"
    )
    func tupletsGroupingValueDistinctionAndKeyNaturals() throws {
        // 1. Triplets (`2`) and Quintuplets (`_5'`) preserve written face values
        let tupletSource = """
            ::SCORE::
            != 120
            ?= C
            <4/4>

            A:Flute@|0|{
                <4*>
                | (1 2 3)%(--) 1 2 |
                | (1 2 3 4 5)%(--) 1 2 |
            }
            -> A ->#
            """
        let tupletSheet = try TmdParser.parseThrowing(string: tupletSource)
        let tupletBrf = TmdBrailleGenerator.generateBraille(
            from: tupletSheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart, lineWidth: nil)
        )
        // Measure 1: triplet of quarter notes `2"?:$` followed by two quarter notes `?:`
        // Measure 2: quintuplet of eighth notes `_5'DEFGH` (D4 -> C4 is a 2nd, so no octave mark needed) followed by `?:`
        #expect(tupletBrf.contains("#A 2\"?:$?: _5'DEFGH?:<K"))

        // 2. 16th-note grouping (BANA Par. 8.1): four 16th notes in beat 1 -> first is 16th (`Y`), next 3 are 8th (`EFG`)
        let groupingSource = """
            ::SCORE::
            != 120
            ?= C
            <4/4>

            A:Violin@|0|{
                <16*>
                | 1 2 3 4 <4*> 5 4 3 |
            }
            -> A ->#
            """
        let groupingSheet = try TmdParser.parseThrowing(string: groupingSource)
        let groupingBrf = TmdBrailleGenerator.generateBraille(
            from: groupingSheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart, lineWidth: nil)
        )
        #expect(groupingBrf.contains("#A \"YEFG\\]$<K"))

        // 3. Value distinction sign `,<1` (⠠⠣⠂) when large and small values of the same class could be confused, plus forceOctave
        let distinctionSource = """
            ::SCORE::
            != 120
            ?= C
            <4/4>

            A:Violin@|0|{
                <2*>
                | 1 <32*> 1 2 3 4 5 6 7 1^ 2^ 3^ 4^ 5^ 6^ 7^ 1^^ 2^^ |
            }
            -> A ->#
            """
        let distinctionSheet = try TmdParser.parseThrowing(string: distinctionSource)
        let distinctionBrf = TmdBrailleGenerator.generateBraille(
            from: distinctionSheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart, lineWidth: nil)
        )
        #expect(distinctionBrf.contains(",<1\""))

        // 4. Inline key signature changes emit natural cancellation `*` (including back to C major)
        let keyModSource = """
            ::SCORE::
            != 120
            ?= D
            key= D
            <4/4>

            A:Violin@|0|{
                <1*>
                | 1 |
                | {key= G} 1 |
                | {key= C} 1 |
            }
            -> A ->#
            """
        let keyModSheet = try TmdParser.parseThrowing(string: keyModSource)
        let keyModBrf = TmdBrailleGenerator.generateBraille(
            from: keyModSheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart, lineWidth: nil)
        )
        // D major (2 sharps %%) -> G major (1 sharp: cancel 1 sharp + 1 sharp = `*%`) -> C major (0 sharps: cancel 1 sharp = `*`)
        #expect(keyModBrf.contains("#A \"Z *% \"Z * \"Z<K"))
    }

    @Test(
        "Issue #59: 40-cell line wrapping with 2-space continuation indent and mandatory octave mark on new line (Par. CN-4)"
    )
    func fortyCellLineWrappingAndOctaveReset() throws {
        let longSource = """
            ::SCORE::
            ** Long Solo **
            != 120
            ?= C
            <4/4>

            A:Piano@|0|{
                <4*>
                | 1 2 3 4 | 5 4 3 2 | 1 2 3 4 | 5 4 3 2 |
                | 1 2 3 4 | 5 4 3 2 | 1 2 3 4 | 1 - - - |
            }
            -> A ->#
            """
        let sheet = try TmdParser.parseThrowing(string: longSource)
        let wrappedBrf = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart, lineWidth: 40)
        )
        let lines = wrappedBrf.split(separator: "\n", omittingEmptySubsequences: true).map(
            String.init)
        for line in lines {
            #expect(line.count <= 40)
        }
        let musicLines = lines.filter {
            $0.hasPrefix("#A ") || ($0.hasPrefix("  ") && !$0.hasPrefix("   "))
        }
        #expect(musicLines.count >= 2)
        // Continuation line must start with 2 spaces followed immediately by an octave mark `"` on C4 (`"Y<K`)
        #expect(musicLines[1] == "  \"Y<K")

        // Unwrapped (`lineWidth: nil`) puts all measures on a single line
        let unwrappedBrf = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart, lineWidth: nil)
        )
        let unwrappedMusicLines = unwrappedBrf.split(separator: "\n").filter { $0.hasPrefix("#A ") }
        #expect(unwrappedMusicLines.count == 1)
    }
}
