import Foundation
import Testing
import TmdABC
import TmdBraille
import TmdChordPro
import TmdLSP
import TmdLilyPond
import TmdMIDI
import TmdMusicXML
import TmdUTAU
import TmdVocaloid

@testable import TmdSwift

@Suite("TMD Lyrics Tests")
struct TmdLyricsTests {
    @Test("Parses interleaved L| and multi-stanza L1|..L64| lyric lines with lenient syntax, transparent punctuation, groups, and playback selectors")
    func testParseLyricsASTAndRoundTripFormat() throws {
        let source = """
            ::SCORE::
            ** Lyric AST Test **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                1 2 3 0 | (1 1)%(--) 3 -
                L1 | 「 我 愛 你 」 0 | (你 好) 嗎？ -
                L2 | yes- ter- day 0 | (in the) end -
            }

            TigerTheme {
                <4*>
                | 1 2 3 1 |
                L| 兩 隻 老 虎 |
            }

            -> verse[ L1 ] -> verse[ L2 ] ->#
            """

        let sheet = try #require(TmdParser.parse(string: source))
        #expect(sheet.entries.count == 2)

        let verse = sheet.entries[0]
        let section = try #require(verse.sections.first)
        #expect(section.lyrics.count == 2)
        #expect(section.activeStanzaBitmask == 0b11)

        let stanza1 = section.lyrics[0]
        #expect(stanza1.stanza == 1)
        #expect(stanza1.measures.count == 2)

        let m1Units = stanza1.measures[0].flatSoundingUnits
        #expect(m1Units.count == 4)
        #expect(m1Units[0] == .syllable(LyricSyllable(rawText: "「我", cleanWord: "我", hasTrailingHyphen: false)))
        #expect(m1Units[1] == .syllable(LyricSyllable(rawText: "愛", cleanWord: "愛", hasTrailingHyphen: false)))
        #expect(m1Units[2] == .syllable(LyricSyllable(rawText: "你」", cleanWord: "你", hasTrailingHyphen: false)))
        #expect(m1Units[3] == .rest)

        let m2Slots = stanza1.measures[1].slots
        #expect(m2Slots.count == 3)
        #expect(
            m2Slots[0]
                == .group([
                    .syllable(LyricSyllable(rawText: "你", cleanWord: "你", hasTrailingHyphen: false)),
                    .syllable(LyricSyllable(rawText: "好", cleanWord: "好", hasTrailingHyphen: false)),
                ]))
        #expect(m2Slots[1] == .unit(.syllable(LyricSyllable(rawText: "嗎？", cleanWord: "嗎", hasTrailingHyphen: false))))
        #expect(m2Slots[2] == .unit(.tie))

        let stanza2 = section.lyrics[1]
        #expect(stanza2.stanza == 2)
        let s2m1 = stanza2.measures[0].flatSoundingUnits
        #expect(s2m1.count == 4)
        #expect(s2m1[0] == .syllable(LyricSyllable(rawText: "yes-", cleanWord: "yes", hasTrailingHyphen: true)))
        #expect(s2m1[0].syllable?.displaySyllable == "yes")
        #expect(s2m1[1] == .syllable(LyricSyllable(rawText: "ter-", cleanWord: "ter", hasTrailingHyphen: true)))
        #expect(s2m1[2] == .syllable(LyricSyllable(rawText: "day", cleanWord: "day", hasTrailingHyphen: false)))
        #expect(s2m1[3] == .rest)

        // Prototype also supports lyrics
        let proto = sheet.entries[1]
        #expect(proto.isPrototype)
        #expect(proto.sections[0].lyrics.count == 1)
        #expect(proto.sections[0].lyrics[0].stanza == nil)

        // Playback selectors
        #expect(sheet.playback.count == 2)
        #expect(sheet.playback[0] == .name("verse[L1]"))
        #expect(sheet.playback[0].sectionName == "verse")
        #expect(sheet.playback[0].stanzaSelector == 1)
        #expect(sheet.playback[1] == .name("verse[L2]"))
        #expect(sheet.playback[1].sectionName == "verse")
        #expect(sheet.playback[1].stanzaSelector == 2)

        // Sheet.format() round-trip
        let formatted = sheet.format()
        #expect(formatted.contains("    L1| 「 我 愛 你 」 0 | (你 好) 嗎？ - |\n"))
        #expect(formatted.contains("    L2| yes- ter- day 0 | (in the) end - |\n"))
        #expect(formatted.contains("-> verse[L1] -> verse[L2] ->#\n"))
        #expect(TmdRefactor.format(formatted) == formatted)
    }

    @Test("Validates 1:1 grid slot counting, dyads, transparent punctuation, groups, and stanza diagnostics")
    func testLyricsSemanticValidationAndDiagnostics() {
        // 1. Valid multi-stanza score with dyads, transparent tokens, and groups
        let validSource = """
            ::SCORE::
            ** Valid Lyrics **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1+3 2 3 0 | (1 2)%(--) 3 - |
                L1| 「 哈 愛 你 」 0 | (你 好) 嗎 - |
                L2| yes- ter- day 0 | (in the) end - |
            }

            -> verse[L1] -> verse[L2] ->#
            """
        let validDiags = TmdScoreValidator.validate(source: validSource)
        #expect(validDiags.isEmpty)

        // 2. E-LYRIC-COUNT / E-LYRIC-SLOT-MISMATCH
        let countMismatchSource = """
            ::SCORE::
            ** Slot Mismatch **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L| a b c |
            }

            -> verse ->#
            """
        let countDiags = TmdScoreValidator.validate(source: countMismatchSource)
        #expect(countDiags.contains { $0.rule == .lyricCount && $0.rule == .lyricSlotMismatch })

        // 3. E-LYRIC-DIRECTIVE
        let directiveSource = """
            ::SCORE::
            ** Directive in Lyrics **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L| {mp} a b c d |
            }

            -> verse ->#
            """
        let directiveDiags = TmdScoreValidator.validate(source: directiveSource)
        #expect(directiveDiags.contains { $0.rule == .lyricDirective })

        // 4. E-LYRIC-GROUP
        let groupMismatchSource = """
            ::SCORE::
            ** Group Mismatch **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | (1 2)%(--) 3 4 |
                L| (a b c) d e |
            }

            -> verse ->#
            """
        let groupDiags = TmdScoreValidator.validate(source: groupMismatchSource)
        #expect(groupDiags.contains { $0.rule == .lyricGroup })

        // 5. E-LYRIC-TOKEN-UNSEPARATED
        let unseparatedSource = """
            ::SCORE::
            ** Unseparated CJK **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L| 你好喔喔 |
            }

            -> verse ->#
            """
        let unseparatedDiags = TmdScoreValidator.validate(source: unseparatedSource)
        #expect(unseparatedDiags.contains { $0.rule == .lyricTokenUnseparated })

        // 6. E-STANZA-ZERO & E-STANZA-RANGE & E-STANZA-DUPLICATE
        let stanzaErrorsSource = """
            ::SCORE::
            ** Stanza Errors **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L0| a b c d |
                L1| a b c d |
                L1| e f g h |
                L65| i j k l |
            }

            -> verse[L1] ->#
            """
        let stanzaErrDiags = TmdScoreValidator.validate(source: stanzaErrorsSource)
        #expect(stanzaErrDiags.contains { $0.rule == .stanzaZero })
        #expect(stanzaErrDiags.contains { $0.rule == .stanzaRange })
        #expect(stanzaErrDiags.contains { $0.rule == .stanzaDuplicate })

        // 7. E-STANZA-INCONSISTENT, W-STANZA-GAP, W-STANZA-FALLBACK
        let stanzaWarnAndInconsistentSource = """
            ::SCORE::
            ** Stanza Gap, Inconsistent, Fallback **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L1| a b c d |
                L3| e f g h |
                | 5 6 7 1^ |
                L1| i j k l |
            }

            -> verse ->#
            """
        let stanzaWarnDiags = TmdScoreValidator.validate(source: stanzaWarnAndInconsistentSource)
        #expect(stanzaWarnDiags.contains { $0.rule == .stanzaGap && $0.severity == .warning })
        #expect(stanzaWarnDiags.contains { $0.rule == .stanzaInconsistent && $0.severity == .error })
        #expect(stanzaWarnDiags.contains { $0.rule == .stanzaFallback && $0.severity == .warning })
    }

    @Test("Routes multi-stanza selectors across lead/backing tracks on playback timeline and clones prototype lyrics in canon macros")
    func testPlaybackTimelineMultiStanzaBroadcastAndCanonMacros() throws {
        let source = """
            ::SCORE::
            ** Stanza Broadcast & Canon Lyrics **
            != 120
            ?= C
            <4/4>

            verse:LeadVocal@|0|{
                <4*>
                | 1 2 3 0 |
                L1| 春 風 吹 0 |
                L2| 秋 雨 落 0 |
            }

            verse:BackingVocal@|0|{
                <4*>
                | 3 4 5 0 |
                L| 啦 啦 啦 0 |
            }

            TigerTheme {
                <4*>
                | 1 2 3 1 |
                L| 兩 隻 老 虎 |
            }

            -> verse[L1] -> verse[L2] -> (canon TigerTheme (instruments Soprano Alto) (offsets 0 1)) ->#
            """

        let sheet = try #require(TmdParser.parse(string: source))
        let leadTimeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "LeadVocal")
        let leadWords = leadTimeline.events.compactMap { $0.lyric?.cleanWord }
        #expect(leadWords == ["春", "風", "吹", "秋", "雨", "落"])

        let backingTimeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "BackingVocal")
        let backingWords = backingTimeline.events.compactMap { $0.lyric?.cleanWord }
        #expect(backingWords == ["啦", "啦", "啦", "啦", "啦", "啦"])

        let sopranoTimeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Soprano")
        let sopranoNotes = sopranoTimeline.events.filter { $0.content.isNote }
        #expect(sopranoNotes.map { $0.lyric?.cleanWord } == ["兩", "隻", "老", "虎"])
        #expect(sopranoNotes.first?.position == 8.0)

        let altoTimeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Alto")
        let altoNotes = altoTimeline.events.filter { $0.content.isNote }
        #expect(altoNotes.map { $0.lyric?.cleanWord } == ["兩", "隻", "老", "虎"])
        #expect(altoNotes.first?.position == 12.0)
    }

    @Test("Exports cleanWord lyrics and merges melisma durations in MIDI (0xFF 0x05), VOCALOID (.vsq/.vsqx), and UTAU (.ust)")
    func testVoiceSynthesisExportersMIDIAndVocaloidAndUTAU() throws {
        let source = """
            ::SCORE::
            ** Voice Synthesis Lyrics **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 - 3 |
                L| 「拉」 咪 - 索！ |
            }

            -> verse ->#
            """

        let sheet = try #require(TmdParser.parse(string: source))

        // 1. MIDI 0xFF 0x05 Lyric Meta Event at note-on ticks using cleanWord
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Vocal")
        let midiEvents = TmdMIDIGenerator.instrumentEvents(
            timeline: timeline,
            instrument: "Vocal",
            midiInstrument: MIDIInstrument.resolve("Vocal"),
            channel: 0,
            ticksPerQuarter: 480
        )
        let lyricMetaEvents = midiEvents.filter {
            if case .lyric = $0.message { return true }
            return false
        }
        #expect(lyricMetaEvents.count == 3)
        #expect(lyricMetaEvents[0] == MIDIEvent(tick: 0, message: .lyric("拉")))
        #expect(lyricMetaEvents[1] == MIDIEvent(tick: 480, message: .lyric("咪")))
        #expect(lyricMetaEvents[2] == MIDIEvent(tick: 1440, message: .lyric("索")))

        let midiData = try TmdMIDIGenerator.generateMIDI(from: sheet)
        // Verify 0xFF 0x05 meta event header is encoded in SMF binary
        #expect(midiData.range(of: Data([0xFF, 0x05])) != nil)

        // 2. VOCALOID .vsqx (cleanWord without punctuation, melisma duration = 960 ticks)
        let vsqx = TmdVSQXGenerator.generateVSQX(from: sheet)
        #expect(vsqx.contains("<y><![CDATA[拉]]></y>"))
        #expect(vsqx.contains("<y><![CDATA[咪]]></y>"))
        #expect(vsqx.contains("<y><![CDATA[索]]></y>"))
        #expect(!vsqx.contains("「"))
        #expect(!vsqx.contains("！"))
        #expect(vsqx.contains("<dur>960</dur>"))

        // 3. VOCALOID .vsq
        let vsqData = TmdVSQGenerator.generateVSQ(from: sheet)
        #expect(!vsqData.isEmpty)

        // 4. UTAU .ust (cleanWord without punctuation, melisma Length=960)
        let ust = TmdUSTGenerator.generateUST(from: sheet)
        #expect(ust.contains("Lyric=拉\r\n"))
        #expect(ust.contains("Length=960\r\nLyric=咪\r\n"))
        #expect(ust.contains("Lyric=索\r\n"))
    }

    @Test("Exports rawText lyrics, multi-stanza verses, hyphenation, and melismas in MusicXML, LilyPond, ABC, ChordPro, and Music Braille")
    func testSheetEngravingExportersMusicXMLLilyPondABCChordProBraille() throws {
        let source = """
            ::SCORE::
            ** Sheet Engraving Lyrics **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L1| 「我 愛」 你 - |
                L2| yes- ter- day - |
            }

            verse:Chord@|0|{
                <4*>
                | [C] - [G] - |
            }

            -> verse[L1] -> verse[L2] ->#
            """

        let sheet = try #require(TmdParser.parse(string: source))

        // 1. MusicXML (<lyric number="1">, <lyric number="2">, <syllabic>, <text>, <extend/>)
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        #expect(xml.contains("<lyric number=\"1\">"))
        #expect(xml.contains("<text>「我</text>"))
        #expect(xml.contains("<text>愛」</text>"))
        #expect(xml.contains("<text>你</text>"))
        #expect(xml.contains("<lyric number=\"2\">"))
        #expect(xml.contains("<syllabic>begin</syllabic>"))
        #expect(xml.contains("<text>yes</text>"))
        #expect(xml.contains("<syllabic>middle</syllabic>"))
        #expect(xml.contains("<text>ter</text>"))
        #expect(xml.contains("<syllabic>end</syllabic>"))
        #expect(xml.contains("<text>day</text>"))
        #expect(xml.contains("<extend"))

        // 2. LilyPond (\addlyrics, hyphenation --, melisma __)
        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)
        #expect(ly.contains("\\addlyrics"))
        #expect(ly.contains("「我"))
        #expect(ly.contains("yes\" -- \"ter\" -- \"day"))
        #expect(ly.contains("__"))

        // 3. ABC Notation (w: lyric lines with hyphenation and melisma _)
        let abc = TmdABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("w:"))
        #expect(abc.contains("「我 愛」 你 _"))
        #expect(abc.contains("yes- ter- day _"))

        // 4. ChordPro (inline [C] / [G] chords above/before lyrics)
        let cho = TmdChordProGenerator.generateChordPro(from: sheet)
        #expect(cho.contains("[C]「我 愛」 [G]你"))
        #expect(cho.contains("[C]yes- ter- [G]day"))

        // 5. Music Braille (literary braille lyrics alongside braille music)
        let brf = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .ascii)
        )
        #expect(brf.contains("YES-TER-DAY") || brf.contains("YES"))
    }

    @Test("Offers stanza selectors L1, L2 when auto-completing inside -> verse[")
    func testLSPAutoCompletionOffersStanzaSelectors() throws {
        let source = """
            ::SCORE::
            ** LSP Stanza Completion **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L1| 春 風 吹 過 |
                L2| 秋 雨 落 下 |
            }

            -> verse[
            """

        // Line 13 is "-> verse[" (character 9 is right after "[")
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 13, character: 9)
        )
        let labels = items.map(\.label)
        #expect(labels == ["L1", "L2"])
        #expect(items.first?.insertText == "L1]")

        // Reuse existing closing bracket if present: "-> verse[]" with cursor at character 9
        let sourceWithClosingBracket = source + "]"
        let itemsReusingBracket = TmdLSPCompletionEngine.complete(
            source: sourceWithClosingBracket,
            position: TmdLSPPosition(line: 13, character: 9)
        )
        #expect(itemsReusingBracket.map(\.label) == ["L1", "L2"])
        #expect(itemsReusingBracket.first?.insertText == "L1")
    }

    @Test("Handles unmatched closing delimiters, overflowing stanza numbers, inline block comments, selector range diagnostics, and per-measure trailing rest omission")
    func testBatch1LexerParserAndValidatorEdgeCases() throws {
        // 1. Unmatched ')' and '}' in LyricLine.parseMeasure must not hang
        let measureWithUnmatchedClose = LyricLine.parseMeasure("a ) b } c")
        #expect(measureWithUnmatchedClose.flatSoundingUnits.count == 3)

        // 2. Inline block comment inside lyric line must not truncate remainder of line
        let inlineCommentScore = """
            ::SCORE::
            ** Inline Lyric Comment **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L| a /* inline comment */ b ) c d |
            }

            -> verse ->#
            """
        let commentSheet = try #require(TmdParser.parse(string: inlineCommentScore))
        let commentUnits = commentSheet.entries.first?.sections.first?.lyrics.first?.measures.first?
            .flatSoundingUnits
        #expect(commentUnits?.count == 4)
        let commentDiags = TmdScoreValidator.validate(source: inlineCommentScore)
        #expect(commentDiags.filter { $0.severity == .error }.isEmpty)

        // 3. Overflowing stanza index on lyric line and playback selector must emit E-STANZA-RANGE / E-STANZA-ZERO
        let overflowScore = """
            ::SCORE::
            ** Overflow Stanza **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L999999999999999999999999999999| a b c d |
            }

            -> verse[L0] -> verse[L65] -> verse[L999999999999999999999999999999] ->#
            """
        let overflowDiags = TmdScoreValidator.validate(source: overflowScore)
        let stanzaZeroDiags = overflowDiags.filter { $0.rule == .stanzaZero }
        let stanzaRangeDiags = overflowDiags.filter { $0.rule == .stanzaRange }
        #expect(stanzaZeroDiags.count == 1)
        #expect(stanzaRangeDiags.count == 3)

        // 4. Per-measure trailing rest omission alignment (| 1 2 0 0 | 3 4 5 6 | with L| a b | c d e f |)
        let trailingRestScore = """
            ::SCORE::
            ** Trailing Rest Omission **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 0 0 | 3 4 5 6 |
                L| a b | c d e f |
            }

            -> verse ->#
            """
        let trailingRestDiags = TmdScoreValidator.validate(source: trailingRestScore)
        #expect(trailingRestDiags.filter { $0.severity == .error }.isEmpty)

        let trailingRestSheet = try #require(TmdParser.parse(string: trailingRestScore))
        let timeline = TmdPlaybackRenderer.render(sheet: trailingRestSheet, instrument: "Vocal")
        let noteEvents = timeline.events.filter { $0.content.isNote }
        #expect(noteEvents.map { $0.lyric?.cleanWord } == ["a", "b", "c", "d", "e", "f"])
        #expect(noteEvents[2].position == 4.0)
        #expect(noteEvents[2].lyric?.cleanWord == "c")
    }

    @Test("Preserves stanza selectors in renameSection/inlineOrders, completes Unicode section stanzas in LSP, validates canon explicit offsets, and reverses lyrics in reverse macro")
    func testBatch2RefactorLSPAndMacroLyrics() throws {
        let source = """
            ::SCORE::
            ** Batch 2 Refactor & Macro Lyrics **
            != 120
            ?= C
            <4/4>

            副歌:Vocal@|0|{
                <4*>
                | 1 2 3 0 |
                L1| 春 風 吹 0 |
                L2| 秋 雨 落 0 |
            }

            -> 副歌[L1] -> 副歌[L2] ->#
            """

        // 1. renameSection updates `-> 副歌[L1]` to `-> chorus[L1]`
        let renamed = try TmdRefactor.renameSection(in: source, from: "副歌", to: "chorus")
        #expect(renamed.contains("chorus:Vocal@|0|{"))
        #expect(renamed.contains("-> chorus[L1] -> chorus[L2] ->#"))

        // 2. inlineOrders resolves `副歌[L1]` and `副歌[L2]` and preserves merged lyrics across sections
        let inlined = try TmdRefactor.inlineOrders(source: source)
        let inlinedSheet = try #require(TmdParser.parse(string: inlined))
        let inlinedTimeline = TmdPlaybackRenderer.render(sheet: inlinedSheet, instrument: "Vocal")
        let inlinedWords = inlinedTimeline.events.filter { $0.content.isNote }.compactMap {
            $0.lyric?.cleanWord
        }
        #expect(inlinedWords == ["春", "風", "吹", "秋", "雨", "落"])

        // 3. LSP auto-completion supports Unicode section names (`-> 副歌[`)
        let lspSource = """
            ::SCORE::
            ** Unicode LSP **
            != 120
            ?= C
            <4/4>

            副歌:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L1| 春 風 吹 過 |
                L2| 秋 雨 落 下 |
            }

            -> 副歌[
            """
        let utf16Count = "-> 副歌[".utf16.count
        let lspItems = TmdLSPCompletionEngine.complete(
            source: lspSource,
            position: TmdLSPPosition(line: 13, character: utf16Count)
        )
        #expect(lspItems.map(\.label) == ["L1", "L2"])

        // 4. Canon explicit (offsets ...) count mismatch and out-of-bounds first voice must throw
        let mismatchCanonScore = """
            ::SCORE::
            ** Mismatch Canon **
            != 120
            ?= C
            <4/4>

            Theme {
                <4*>
                | 1 2 3 4 |
            }

            -> (canon Theme (instruments V1 V2 V3) (offsets 1 0)) ->#
            """
        let mismatchSheet = try #require(TmdParser.parse(string: mismatchCanonScore))
        #expect(throws: TmdMacroError.self) {
            _ = try TmdMacroEvaluator.expandThrowing(mismatchSheet)
        }

        let lateFirstVoiceCanonScore = """
            ::SCORE::
            ** Late First Voice Canon **
            != 120
            ?= C
            <4/4>

            Theme {
                <4*>
                | 1 2 3 4 |
            }

            -> (canon Theme (instruments V1 V2) (offsets 2 0)) ->#
            """
        let lateSheet = try #require(TmdParser.parse(string: lateFirstVoiceCanonScore))
        #expect(throws: TmdMacroError.self) {
            _ = try TmdMacroEvaluator.expandThrowing(lateSheet)
        }

        // 5. Reverse macro reverses lyric slots so (1:a, 2:b, 3:c, 0:0) becomes (0:0, 3:c, 2:b, 1:a)
        let reverseScore = """
            ::SCORE::
            ** Reverse Lyrics **
            != 120
            ?= C
            <4/4>

            Theme {
                <4*>
                | 1 2 3 0 |
                L| a b c 0 |
            }

            -> (play (reverse Theme) Vocal) ->#
            """
        let reverseSheet = try #require(TmdParser.parse(string: reverseScore))
        let reverseTimeline = TmdPlaybackRenderer.render(sheet: reverseSheet, instrument: "Vocal")
        let reverseNotes = reverseTimeline.events.filter { $0.content.isNote }
        #expect(reverseNotes.map { $0.lyric?.cleanWord } == ["c", "b", "a"])
    }

    @Test("Preserves pitch/tempo changes across melismas in VSQX/UST, emits MusicXML extend stop, consumes untied melisma notes in LilyPond, binds ABC stanza numbers with ~, and emits Braille lyrics in all layouts")
    func testBatch3ExporterMelismaAndAlignmentEdgeCases() throws {
        let source = """
            ::SCORE::
            ** Batch 3 Exporter Edge Cases **
            != 120
            ?= C
            <4/4>

            verse:Vocal@|0|{
                <4*>
                | 1 2 3 4 |
                L1| la - - end |
                L2| go - - now |
            }

            -> verse[L1] ->#
            """

        let sheet = try #require(TmdParser.parse(string: source))

        // 1. Pitch-changing melisma (1 -> 2 -> 3) must NOT swallow notes 2 and 3 in monophonicEvents / VSQX / UST
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Vocal")
        let monoNotes = timeline.monophonicEvents(mergeMelisma: true).filter { $0.content.isNote }
        #expect(monoNotes.count == 4)

        let vsqx = TmdVSQXGenerator.generateVSQX(from: sheet)
        #expect(vsqx.contains("<y><![CDATA[la]]></y>"))
        #expect(vsqx.contains("<y><![CDATA[-]]></y>"))
        #expect(vsqx.contains("<y><![CDATA[end]]></y>"))

        let ust = TmdUSTGenerator.generateUST(from: sheet)
        #expect(ust.contains("Lyric=la\r\n"))
        #expect(ust.contains("Lyric=-\r\n"))
        #expect(ust.contains("Lyric=end\r\n"))

        // 2. MusicXML emits <extend type="start"/>, <extend type="continue"/>, and <extend type="stop"/>
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        #expect(xml.contains("<extend type=\"start\"/>"))
        #expect(xml.contains("<extend type=\"continue\"/>"))
        #expect(xml.contains("<extend type=\"stop\"/>"))

        // 3. LilyPond emits extender `__` and note-consuming skip `_` for each untied melisma note
        let ly = TmdLilyPondGenerator.generateLilyPond(from: sheet)
        #expect(ly.contains("\"la\" __ _ _ \"end\""))
        #expect(ly.contains("\"go\" __ _ _ \"now\""))

        // 4. ABC Notation binds multi-stanza prefix with `~` (`w: 1.~la _ _ end`)
        let abc = TmdABCGenerator.generateABC(from: sheet)
        #expect(abc.contains("w: 1.~la _ _ end"))
        #expect(abc.contains("w: 2.~go _ _ now"))

        // 5. Music Braille outputs lyrics when lineWidth is nil and in .barOverBar layout
        let brfUnwrapped = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .partByPart, lineWidth: nil)
        )
        #expect(brfUnwrapped.contains(";2 LA END"))

        let brfBarOverBar = TmdBrailleGenerator.generateBraille(
            from: sheet,
            options: TmdBrailleOptions(encoding: .ascii, layout: .barOverBar)
        )
        #expect(brfBarOverBar.contains(";2 LA END"))
    }
}
