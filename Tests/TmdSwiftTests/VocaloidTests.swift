import Foundation
import Testing

@testable import TmdMIDI
@testable import TmdSwift
@testable import TmdVocaloid

@Suite("VOCALOID Exporter Tests")
struct VocaloidTests {

    @Test("Test Japanese kana and romaji to X-SAMPA phoneme resolution")
    func testPhonemeResolution() {
        #expect(VocaloidPhoneme.resolvePhoneme(for: "a") == "a")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "あ") == "a")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "mi") == "m' i")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "み") == "m' i")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "ku") == "k M")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "く") == "k M")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "ra") == "4 a")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "ら") == "4 a")
        #expect(VocaloidPhoneme.resolvePhoneme(for: "unknown_xyz") == "a")
    }

    @Test("Test VOCALOID2 (.vsq) SMF Format 1 generation")
    func testVSQGeneration() throws {
        let tmdContent = """
            ::SCORE::
            ** Miku Song **
            != 120
            ?= C
            <4/4>
            Intro:Vocal@|0|{
                <4*>
                1 2 3 4
            }
            """
        let sheet = try TmdParser.parseThrowing(string: tmdContent)
        let vsqData = TmdVSQGenerator.generateVSQ(
            from: sheet, options: VocaloidExportOptions(singerName: "Miku"))

        #expect(vsqData.count > 100)
        // Check MIDI header "MThd"
        let header = String(data: vsqData.prefix(4), encoding: .ascii)
        #expect(header == "MThd")

        // Track count should be 2 (conductor + vocal)
        let trackCount = UInt16(vsqData[10]) << 8 | UInt16(vsqData[11])
        #expect(trackCount == 2)
    }

    @Test("Test VOCALOID3/4 (.vsqx) XML structure generation")
    func testVSQXGeneration() throws {
        let tmdContent = """
            ::SCORE::
            ** Miku Vocaloid Song **
            != 135
            ?= D
            <4/4>
            Verse:Vocal@|0|{
                <4*>
                1 3 5 1^
            }
            """
        let sheet = try TmdParser.parseThrowing(string: tmdContent)
        let vsqx = TmdVSQXGenerator.generateVSQX(
            from: sheet, options: VocaloidExportOptions(singerName: "Hatsune Miku"))

        #expect(vsqx.contains("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\"?>"))
        #expect(vsqx.contains("<vsq4 xmlns=\"http://www.yamaha.co.jp/vocaloid/schema/vsq4/\""))
        #expect(vsqx.contains("<masterTrack>"))
        #expect(vsqx.contains("<vsTrack>"))
        #expect(vsqx.contains("<name><![CDATA[Hatsune Miku]]></name>"))
        #expect(vsqx.contains("<note>"))
        #expect(vsqx.contains("<dur>"))
        #expect(vsqx.contains("<n>"))
    }

    @Test("Test monophonic reduction of simultaneous multi-notes (1+3+5 picks highest pitch 5=67)")
    func testMonophonicMultiNoteReduction() throws {
        let tmdContent = """
            ::SCORE::
            ** Poly Vocal Test **
            != 120
            ?= C
            <4/4>
            Verse:Vocal@|0|{
                <4*>
                1+3+5 2
            }
            """
        let sheet = try TmdParser.parseThrowing(string: tmdContent)

        // VSQX should emit exactly 2 <note> elements: first with <n>67</n> (G4), second with <n>62</n> (D4)
        let vsqx = TmdVSQXGenerator.generateVSQX(from: sheet)
        let noteCount = vsqx.components(separatedBy: "<note>").count - 1
        #expect(noteCount == 2)
        #expect(vsqx.contains("<n>67</n>"))
        #expect(vsqx.contains("<n>62</n>"))
        #expect(!vsqx.contains("<n>60</n>"))
        #expect(!vsqx.contains("<n>64</n>"))

        // VSQ INI text inside SMF should have 2 extracted notes (67 and 62) and no ID#0003
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: "Vocal")
        let extracted = VocaloidNoteItem.extractNotes(
            from: timeline, preMeasureTicks: 7680, ticksPerQuarter: 480, defaultLyric: "a")
        #expect(extracted.count == 2)
        #expect(extracted[0].pitch == 67)
        #expect(extracted[1].pitch == 62)

        let vsqData = TmdVSQGenerator.generateVSQ(from: sheet)
        let vsqAscii = String(decoding: vsqData, as: UTF8.self)
        #expect(vsqAscii.contains("Note#=67"))
        #expect(!vsqAscii.contains("Note#=60"))
        #expect(!vsqAscii.contains("[ID#0003]"))
    }
}
