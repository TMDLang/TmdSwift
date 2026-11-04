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
}
