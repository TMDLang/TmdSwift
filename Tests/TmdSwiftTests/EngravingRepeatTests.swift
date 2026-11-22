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

    @Test("flattens repeated notation and emits one lyric stream without stanza numbering")
    func flattensRepeatedNotation() throws {
        let sheet = try #require(TmdParser.parse(string: source))
        let options = TmdNotationExportOptions(flattenRepeats: true)
        let abc = TmdABCGenerator.generateABC(from: sheet, options: options)
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet, options: options)
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet, options: options)

        #expect(!abc.contains("|:"))
        #expect(!abc.contains(":|"))
        #expect(!abc.contains("w: 1."))
        #expect(!abc.contains("w: 2."))
        #expect(!xml.contains("<repeat direction="))
        #expect(!xml.contains("<lyric number=\"2\""))
        #expect(!lily.contains("\\repeat volta"))
        #expect(!lily.contains("\\set stanza = \"1.\""))
        #expect(!lily.contains("\\set stanza = \"2.\""))
    }

    @Test("flattens an implicit repeat spanning multiple measures")
    func flattensMultiMeasureImplicitRepeat() throws {
        let sheet = try #require(TmdParser.parse(string: """
            ::SCORE::
            ** Multi-Measure Repeat **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
              <4*>
              | 1 2 3 4 | 5 6 7 1 |
              L1| la li lu le | lo la li lu |
              L2| sa si su se | so sa si su |
            }

            -> verse ->#
            """))
        let abc = TmdABCGenerator.generateABC(
            from: sheet, options: TmdNotationExportOptions(flattenRepeats: true))
        let xml = TmdMusicXMLGenerator.generateMusicXML(
            from: sheet, options: TmdNotationExportOptions(flattenRepeats: true))
        let lily = TmdLilyPondGenerator.generateLilyPond(
            from: sheet, options: TmdNotationExportOptions(flattenRepeats: true))

        #expect(abc.contains("la li lu le"))
        #expect(abc.contains("sa si su se"))
        #expect(!abc.contains("|:"))
        #expect(!xml.contains("<repeat direction="))
        #expect(!lily.contains("\\repeat volta"))
    }

    @Test("preserves a score-level pickup when flattening repeats")
    func preservesScoreLevelPickupWhenFlatteningRepeats() throws {
        let sheet = try #require(TmdParser.parse(string: """
            ::SCORE::
            ** Pickup Repeat **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|-1|{
              <4*>
              | 5 | 1 2 3 4 |
              L1| la | li lu le |
              L2| sa | si su se |
            }

            -> verse[L1] -> verse[L2] ->#
            """))
        let measures = TmdMeasureRenderer.renderMeasures(
            sheet: sheet, instrument: "Vocal", flattenRepeats: true)
        let options = TmdNotationExportOptions(flattenRepeats: true)
        let abc = TmdABCGenerator.generateABC(from: sheet, options: options)
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet, options: options)
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet, options: options)

        #expect(measures.first?.isPickup == true)
        #expect(measures.first?.nominalDuration == 1)
        #expect(xml.contains("<measure number=\"1\" implicit=\"yes\">"))
        #expect(lily.contains("\\partial 4"))
        #expect(abc.contains("G4 |"))
        #expect(abc.contains("w: la"))
        #expect(!TmdMusicXMLGenerator.generateMusicXML(from: sheet).contains("implicit=\"yes\""))
    }

    @Test("ties equal notes across a flattened pickup section boundary")
    func tiesEqualNotesAcrossFlattenedPickupBoundary() throws {
        let sheet = try #require(TmdParser.parse(string: """
            ::SCORE::
            ** Pickup Boundary Tie **
            != 120
            ?= C
            <4/4>

            Verse2:Vocal@|0|{
              <4*>
              | 5 - - - |
            }

            Chorus1:Vocal@|-1|{
              <4*>
              | 0 0 0 0 | 5 - - - |
            }

            -> Verse2 -> Chorus1 ->#
            """))
        let measures = TmdMeasureRenderer.renderMeasures(
            sheet: sheet, instrument: "Vocal", flattenRepeats: true)
        let xml = TmdMusicXMLGenerator.generateMusicXML(
            from: sheet, options: TmdNotationExportOptions(flattenRepeats: true))

        #expect(measures[0].events[0].tieStart)
        #expect(measures[1].events[0].tieStop)
        #expect(xml.contains("<tie type=\"start\"/>"))
        #expect(xml.contains("<tie type=\"stop\"/>"))
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

    @Test("keeps lyric and lyric-less accompaniment tracks aligned when flattening")
    func keepsMultitrackStanzaExpansionAligned() throws {
        let sheet = try #require(TmdParser.parse(string: """
            ::SCORE::
            ** Suzume Multitrack Repeat **
            != 100
            ?= F
            <2/4>

            Main:PianoRH@|0|{
                <16*>
                | 1 - 3 - 2 - 1 - | 5 - 5 - 5 - 0 - |
                L1| ア - チ - ラ - ノ - | ヤ - ネ - デ - _ - |
                L2| コ - チ - ラ - ノ - | ヤ - ネ - デ - _ - |
            }

            Main:PianoLH@|0|{
                <8*>
                | [1] - [5_] - | [1] - [1] 0 |
            }

            -> Main[L1] -> Main[L2] -> #
            """))

        let tracks = TmdMeasureRenderer.renderMeasuresByInstrument(
            sheet: sheet, flattenRepeats: true)

        #expect(tracks["PianoRH"]?.count == 4)
        #expect(tracks["PianoLH"]?.count == 4)
    }

    @Test("preserves all explicit stanza selectors in a four-verse arrangement")
    func preservesFourExplicitStanzas() throws {
        let sheet = try #require(TmdParser.parse(string: """
            ::SCORE::
            ** Four Stanza Repeat **
            != 100
            ?= F
            <2/4>

            Main:PianoRH@|0|{
                <8*>
                | 1 2 3 4 |
                L1| イ ロ ハ ニ |
                L2| ホ ヘ ト チ |
                L3| リ ヌ ル ヲ |
                L4| ワ カ ヨ タ |
            }

            Main:PianoLH@|0|{ <8*> | [1] [1] [1] [1] }

            -> Main[L1] -> Main[L2] -> Main[L3] -> Main[L4] -> #
            """))

        let xml = TmdMusicXMLGenerator.generateMusicXML(
            from: sheet, options: TmdNotationExportOptions(flattenRepeats: true))

        let notationMeasures = TmdMeasureRenderer.renderMeasures(
            sheet: sheet, instrument: "PianoRH")
        #expect(notationMeasures.filter { !$0.foldedIntoRepeat }.count == 1)

        for lyric in ["イ", "ホ", "リ", "ワ"] {
            #expect(xml.contains("<text>\(lyric)</text>"))
        }
    }

    @Test("renders three generalized volta endings")
    func rendersThreeVoltaEndings() throws {
        let tmd = """
            ::SCORE::
            ** Three Volta Endings **
            != 120
            ?= C
            <4/4>
            body:Piano@|0|{ <4*> | 1 2 3 4 | 5 6 7 1 | }
            ending1:Piano@|0|{ <4*> 5 6 7 1 }
            ending2:Piano@|0|{ <4*> 2 3 4 5 }
            ending3:Piano@|0|{ <4*> 6 7 1 2 }
            -> body -> ending1 -> body -> ending2 -> body -> ending3 ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")

        #expect(measures.contains { $0.voltaStartNumber == 1 })
        #expect(measures.contains { $0.voltaStartNumber == 2 })
        #expect(measures.contains { $0.voltaStartNumber == 3 })
        #expect(measures.contains { $0.voltaEndNumber == 3 })
        #expect(TmdABCGenerator.generateABC(from: sheet).contains("|3"))
        #expect(TmdMusicXMLGenerator.generateMusicXML(from: sheet).contains("number=\"3\""))
        #expect(TmdLilyPondGenerator.generateLilyPond(from: sheet).contains("\\repeat volta 3"))
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

    @Test("requires engraving equivalence across all active tracks")
    func requiresCrossTrackEngravingEquivalence() throws {
        let tmd = """
            ::SCORE::
            ** Cross Track Engraving State **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{ <4*> 1 2 3 4 }
            A:Bass@|0|{ <4*> 1 2 3 4 {!= 140} }
            -> A -> A ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let piano = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")
        let bass = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Bass")
        let batched = TmdMeasureRenderer.renderMeasuresByInstrument(sheet: sheet)

        #expect(!piano.contains { $0.repeatStart })
        #expect(!bass.contains { $0.repeatStart })
        #expect(batched["Piano"] == piano)
        #expect(batched["Bass"] == bass)
    }

    @Test("does not fold unrelated sections in a multi-track score")
    func doesNotFoldUnrelatedMultiTrackSections() throws {
        let tmd = """
            ::SCORE::
            ** Multi Track No Repeat Candidate **
            != 120
            ?= C
            <4/4>
            A:Piano@|0|{ <4*> 1 2 3 4 }
            B:Piano@|0|{ <4*> 5 6 7 1 }
            A:Bass@|0|{ <4*> 0 0 0 0 }
            B:Bass@|0|{ <4*> 0 0 0 0 }
            -> A -> B ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let piano = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Piano")
        let bass = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Bass")

        #expect(piano.filter { !$0.foldedIntoRepeat }.count == 2)
        #expect(bass.filter { !$0.foldedIntoRepeat }.count == 2)
        #expect(!piano.contains { $0.repeatStart })
        #expect(!bass.contains { $0.repeatStart })
    }

    @Test("preserves section boundaries while merging repeated lyrics")
    func preservesSectionBoundaryDuringLyricMerge() throws {
        let tmd = """
            ::SCORE::
            ** Repeat Boundary Preservation **
            != 120
            ?= C
            <4/4>
            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L1| la |
                L2| lu |
            }
            chorus:Vocal@|0|{ <4*> 5 6 7 1 }
            -> verse[L1] -> verse[L2] -> chorus ->#
            """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: "Vocal")
        let visible = measures.filter { !$0.foldedIntoRepeat }

        #expect(visible.first?.repeatStart == true)
        #expect(visible.first?.sectionEnd == true)
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
