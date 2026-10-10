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

    @Test("Worked Example 2: Playback Demo with Canon, Modulation, Fixed Pitch, and Show Filtering matches Section 9.3")
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

    @Test("Supports Bar-over-Bar layout, intra-measure accidentals, flat keys, and multi-pitch chords")
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
}
