import Testing
import TmdABC
import TmdLilyPond
import TmdMusicXML

@testable import TmdSwift

@Suite("Engraving repeat export tests")
struct EngravingRepeatTests {
    private let source = """
        ::SCORE::
        ** Engraving Repeat **
        != 120
        ?= C
        <4/4>

        verse:Vocal@|0|{
            <4*>
            | 1 2 3 4 |
            L1| la li lu le |
            L2| sa si su se |
        }

        -> verse[L1] -> verse[L2] ->#
        """

    @Test("folds consecutive stanza-selected playback into notation repeats")
    func foldsConsecutiveStanzaPlayback() throws {
        let sheet = try #require(TmdParser.parse(string: source))
        let abc = TmdABCGenerator.generateABC(from: sheet)
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        #expect(abc.contains("|:") && abc.contains(":|"))
        #expect(abc.contains("w: 1.") && abc.contains("w: 2."))
        #expect(xml.contains("<repeat direction=\"backward\""))
        #expect(!xml.contains("<ending number=\"1\""))
        #expect(lily.contains("\\repeat volta 2"))
        #expect(lily.contains("\\set stanza = \"1.\""))
        #expect(lily.contains("\\set stanza = \"2.\""))
    }

    @Test("marks section transitions and score endings")
    func marksSectionTransitionsAndEndings() throws {
        let sheet = try #require(TmdParser.parse(string: source.replacingOccurrences(of: "-> verse[L1] -> verse[L2] ->#", with: "-> verse[L1] ->#")))
        let abc = TmdABCGenerator.generateABC(from: sheet)
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        #expect(abc.contains("|]"))
        #expect(xml.contains("<bar-style>light-heavy</bar-style>"))
        #expect(!lily.contains("\\repeat volta 2"))
        #expect(lily.contains("\\bar \"|.\""))
    }

    @Test("renders two volta endings around a repeated section")
    func rendersVoltaEndings() throws {
        let tmd = """
            ::SCORE::
            ** Volta **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{ <4*> 1 2 3 4 }
            ending1:Piano@|0|{ <4*> 5 6 7 1 }
            ending2:Piano@|0|{ <4*> 2 3 4 5 }
            -> A -> ending1 -> A -> ending2 ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        #expect(TmdABCGenerator.generateABC(from: sheet).contains("|1"))
        #expect(TmdABCGenerator.generateABC(from: sheet).contains("|2"))
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        #expect(xml.contains("<ending number=\"1\""))
        #expect(xml.contains("<ending number=\"2\""))
        #expect(TmdLilyPondGenerator.generateLilyPond(from: sheet).contains("\\alternative"))
        #expect(xml.components(separatedBy: "<barline location=\"right\">").count - 1 == 3)
        #expect(TmdLilyPondGenerator.generateLilyPond(from: sheet).contains("\\bar \"|.\""))
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet)
        #expect(lily.contains("} }"))
        #expect(!lily.hasSuffix("} }\n"))
    }

    @Test("recognizes short non-conventional sections as volta endings")
    func recognizesShortTailVoltaEndings() throws {
        let tmd = """
            ::SCORE::
            ** Short Tail Volta **
            != 120
            ?= C
            <4/4>
            body:Piano@|0|{ <4*> | 1 2 3 4 | 5 6 7 1 | }
            firstTail:Piano@|0|{ <4*> 5 6 7 1 }
            secondTail:Piano@|0|{ <4*> 2 3 4 5 }
            -> body -> firstTail -> body -> secondTail ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")

        #expect(measures.contains { $0.voltaStartNumber == 1 })
        #expect(measures.contains { $0.voltaStartNumber == 2 })
        #expect(TmdLilyPondGenerator.generateLilyPond(from: sheet).contains("\\alternative"))
    }

    @Test("places repeat end metadata on the last measure and keeps ordinary repeats free of endings")
    func placesRepeatEndOnLastMeasure() throws {
        let tmd = """
            ::SCORE::
            ** Multi Measure Repeat **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{ <4*> | 1 2 3 4 | 5 6 7 1 | }
            -> A -> A ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")
        #expect(measures.filter { !$0.foldedIntoRepeat }.count == 2)
        #expect(measures.first?.repeatStart == true)
        #expect(measures.first?.repeatEndCount == 0)
        #expect(measures.contains { $0.repeatEndCount == 2 })
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        #expect(!xml.contains("<ending number=\"1\""))
    }

    @Test("does not classify a full song form as a volta")
    func doesNotClassifyFullSongFormAsVolta() throws {
        let tmd = """
            ::SCORE::
            ** Full Form **
            != 120
            ?= C
            <4/4>
            verse:Piano@|0|{ <4*> 1 2 3 4 }
            chorus:Piano@|0|{ <4*> 5 6 7 1 }
            bridge:Piano@|0|{ <4*> 2 3 4 5 }
            -> verse -> chorus -> verse -> bridge ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        #expect(!TmdLilyPondGenerator.generateLilyPond(from: sheet).contains("\\alternative"))
    }

    @Test("closes a volta alternative before the following section")
    func closesAlternativeBeforeFollowingSection() throws {
        let tmd = """
            ::SCORE::
            ** Volta Followed By Outro **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{ <4*> 1 2 3 4 }
            ending1:Piano@|0|{ <4*> 5 6 7 1 }
            ending2:Piano@|0|{ <4*> 2 3 4 5 }
            outro:Piano@|0|{ <4*> 6 7 1 2 }
            -> A -> ending1 -> A -> ending2 -> outro ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet)
        #expect(lily.contains("} }"))
        #expect(!lily.hasSuffix("} }\n"))
    }

    @Test("folds a repeated two-section tuple")
    func foldsRepeatedTuple() throws {
        let tmd = """
            ::SCORE::
            ** Tuple Repeat **
            != 120
            ?= C
            <4/4>
            verse:Piano@|0|{ <4*> 1 2 3 4 }
            chorus:Piano@|0|{ <4*> 5 6 7 1 }
            -> verse[L1] -> chorus -> verse[L2] -> chorus ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")
        #expect(measures.filter { !$0.foldedIntoRepeat }.count == 2)
        #expect(measures.first?.repeatStart == true)
        #expect(measures.contains { $0.repeatEndCount == 2 })
    }

    @Test("does not fold an ordinary alternating song form as a tuple repeat")
    func doesNotFoldOrdinaryAlternatingForm() throws {
        let tmd = """
            ::SCORE::
            ** Alternating Form **
            != 120
            ?= C
            <4/4>
            verse:Piano@|0|{ <4*> 1 2 3 4 }
            chorus:Piano@|0|{ <4*> 5 6 7 1 }
            -> verse -> chorus -> verse -> chorus ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")
        #expect(measures.filter { !$0.foldedIntoRepeat }.count == 4)
        #expect(!measures.contains { $0.repeatEndCount == 2 })
    }

    @Test("does not fold a repeated section across a playback modulation")
    func doesNotFoldAcrossPlaybackModulation() throws {
        let tmd = """
            ::SCORE::
            ** Modulated Repeat **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{ <4*> 1 2 3 4 }
            -> A -> {?+2} -> A ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")

        #expect(measures.filter { !$0.foldedIntoRepeat }.count == 2)
        #expect(!measures.contains { $0.repeatStart })
        #expect(!measures.contains { $0.repeatEndCount > 0 })
    }

    @Test("does not fold rest-only measures across a playback modulation")
    func doesNotFoldRestOnlyMeasureAcrossPlaybackModulation() throws {
        let tmd = """
            ::SCORE::
            ** Rest Modulated Repeat **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{
                <4*>
                | 1 2 3 4 |
                | 0 0 0 0 |
            }
            -> A -> {?+2} -> A ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")

        #expect(measures.filter { !$0.foldedIntoRepeat }.count == 4)
        #expect(!measures.contains { $0.repeatStart })
        #expect(!measures.contains { $0.repeatEndCount > 0 })
    }

    @Test("carries the declared notation key through playback state")
    func carriesDeclaredKeyThroughPlaybackState() throws {
        let tmd = """
            ::SCORE::
            ** Declared Key State **
            != 120
            ?= C
            key= Am
            <4/4>
            A:Piano@|0|{ <4*> 1 2 3 4 }
            -> A ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Piano")

        #expect(timeline.events.first?.state.declaredKey == "Am")
    }

    @Test("updates the declared notation key for an inline explicit-key directive")
    func updatesInlineDeclaredKeyInPlaybackState() throws {
        let tmd = """
            ::SCORE::
            ** Inline Declared Key State **
            != 120
            ?= C
            key= C
            <4/4>
            A:Piano@|0|{ <4*> {key= D} 1 2 3 4 }
            -> A ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Piano")

        #expect(timeline.events.first?.state.declaredKey == "D")
        #expect(timeline.events.first?.state.keyOffset == sheet.keySignature.semitoneOffset)
    }

    @Test("exposes the active declared notation key on rendered measures")
    func exposesDeclaredKeyOnRenderedMeasures() throws {
        let tmd = """
            ::SCORE::
            ** Declared Key Measure State **
            != 120
            ?= C
            key= Am
            <4/4>
            A:Piano@|0|{ <4*> 0 0 0 0 }
            -> A ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")

        #expect(measures.first?.declaredKey == "Am")
    }

    @Test("exposes explicit left and right engraving barline metadata")
    func exposesEngravingBarlineMetadata() throws {
        let tmd = """
            ::SCORE::
            ** Barline Metadata **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{ <4*> 1 2 3 4 }
            B:Piano@|0|{ <4*> 5 6 7 1 }
            -> A -> B ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")

        #expect(measures[0].leftBarline == .regular)
        #expect(measures[0].rightBarline == .sectionDouble)
        #expect(measures[1].rightBarline == .finalHeavy)
    }

    @Test("exposes repeat barline metadata on folded repeats")
    func exposesRepeatBarlineMetadata() throws {
        let sheet = try #require(TmdParser.parse(string: source))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Vocal")
        let visible = measures.filter { !$0.foldedIntoRepeat }

        #expect(visible.first?.leftBarline == .repeatForward)
        #expect(visible.last?.rightBarline == .repeatBackward(times: 2))
    }

    @Test("bridges instrumental measures inside an intra-section stanza repeat span")
    func bridgesInstrumentalMeasuresInsideStanzaRepeatSpan() throws {
        let tmd = """
            ::SCORE::
            ** Stanza Span With Instrumental Measure **
            != 120
            ?= C
            <4/4>
            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L| intro - - - |
                | 5 6 7 1 |
                L1| spring - - - |
                L2| autumn - - - |
                | 2 3 4 5 |
                | 6 7 1 2 |
                L1| river - - - |
                L2| mountain - - - |
                | 3 4 5 6 |
                L| outro - - - |
            }
            -> verse ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Vocal")

        #expect(measures.filter { $0.repeatStart }.count == 1)
        #expect(measures.filter { $0.repeatEndCount == 2 }.count == 1)
        #expect(measures.first(where: { $0.repeatStart })?.index == 1)
        #expect(measures.first(where: { $0.repeatEndCount == 2 })?.index == 3)
    }
}
