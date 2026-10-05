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
        let sheet = try TMDParser.parseThrowing(string: tmdContent)
        let vsqData = TMDVSQGenerator.generateVSQ(
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
        let sheet = try TMDParser.parseThrowing(string: tmdContent)
        let vsqx = TMDVSQXGenerator.generateVSQX(
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
}
