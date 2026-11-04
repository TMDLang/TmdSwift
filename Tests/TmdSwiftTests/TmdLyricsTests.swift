import Foundation
import Testing

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
}
