import Foundation
import TmdSwift
import TmdMIDI

/// Exporter for VOCALOID3 / VOCALOID4 `.vsqx` XML format.
///
/// `.vsqx` is an XML-based format compatible with VOCALOID3, VOCALOID4, VOCALOID5, VOCALOID6,
/// and Crypton's Piapro Studio.
public struct TMDVSQXGenerator: Sendable {
    public static let ticksPerQuarter: UInt16 = 480

    /// Generates VOCALOID4 `.vsqx` XML string from a TMD `Sheet`.
    public static func generateVSQX(
        from sheet: Sheet,
        targetInstrument: String? = nil,
        options: VocaloidExportOptions = VocaloidExportOptions()
    ) -> String {
        let selectedInstrument = resolveTargetInstrument(sheet: sheet, requested: targetInstrument)
        let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: selectedInstrument)

        let bpm = sheet.speed > 0 ? sheet.speed : 120.0
        let tempoVal = Int(round(bpm * 100)) // VSQX tempo is scaled by 100 (e.g. 120 BPM = 12000)
        let beatCount = sheet.beat.count > 0 ? sheet.beat.count : 4
        let beatNoteVal = sheet.beat.noteValue > 0 ? sheet.beat.noteValue : 4
        let preMeasure = options.preMeasure

        // PreMeasure ticks: preMeasure bars of time signature
        // 1 bar in ticks = (beatCount * 4 * ticksPerQuarter) / beatNoteVal
        let ticksPerBar = (beatCount * 4 * Int(ticksPerQuarter)) / beatNoteVal
        let preMeasureTicks = preMeasure * ticksPerBar

        // Collect musical part notes
        struct VSQXNote {
            let posTick: Int
            let durTick: Int
            let noteNum: Int
            let lyric: String
            let phnm: String
        }

        var notes: [VSQXNote] = []
        var maxTick = 0
        for event in timeline.events {
            guard case .note(let note) = event.content else { continue }
            let tick = preMeasureTicks + Int((event.position * Double(ticksPerQuarter)).rounded())
            let dur = max(1, Int((event.duration * Double(ticksPerQuarter)).rounded()))
            let pitch = TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: event.state.keyOffset)
            guard (0...127).contains(pitch) else { continue }
            let lyric = options.defaultLyric
            let phnm = VocaloidPhoneme.resolvePhoneme(for: lyric)
            notes.append(VSQXNote(posTick: tick, durTick: dur, noteNum: pitch, lyric: lyric, phnm: phnm))
            maxTick = max(maxTick, tick + dur)
        }

        let totalPartDuration = max(ticksPerBar * 4, maxTick + ticksPerBar)

        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <vsq4 xmlns="http://www.yamaha.co.jp/vocaloid/schema/vsq4/"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://www.yamaha.co.jp/vocaloid/schema/vsq4/ vsq4.xsd">
          <vender><![CDATA[Yamaha corporation]]></vender>
          <version><![CDATA[4.0.0.3]]></version>
          <vVoiceTable>
            <vVoice>
              <bs>0</bs>
              <pc>0</pc>
              <id><![CDATA[BCLRA48FS2TRCPC6]]></id>
              <name><![CDATA[\(escapeCDATA(options.singerName))]]></name>
              <vPrm>
                <bre>0</bre>
                <bri>0</bri>
                <cle>0</cle>
                <gen>0</gen>
                <ope>0</ope>
              </vPrm>
            </vVoice>
          </vVoiceTable>
          <mixer>
            <masterUnit>
              <oDev>0</oDev>
              <rLvl>0</rLvl>
              <vol>0</vol>
            </masterUnit>
            <vsUnit>
              <tNo>0</tNo>
              <iGin>0</iGin>
              <sLvl>-898</sLvl>
              <sEnable>0</sEnable>
              <m>0</m>
              <s>0</s>
              <pan>64</pan>
              <vol>0</vol>
            </vsUnit>
            <monoUnit>
              <iGin>0</iGin>
              <sLvl>-898</sLvl>
              <sEnable>0</sEnable>
              <m>0</m>
              <s>0</s>
              <pan>64</pan>
              <vol>0</vol>
            </monoUnit>
            <stUnit>
              <iGin>0</iGin>
              <m>0</m>
              <s>0</s>
              <vol>0</vol>
            </stUnit>
          </mixer>
          <masterTrack>
            <seqName><![CDATA[\(escapeCDATA(sheet.name.isEmpty ? "TMD Score" : sheet.name))]]></seqName>
            <comment><![CDATA[Exported by TmdSwift]]></comment>
            <resolution>480</resolution>
            <preMeasure>\(preMeasure)</preMeasure>
            <timeSig>
              <m>0</m>
              <nu>\(beatCount)</nu>
              <de>\(beatNoteVal)</de>
            </timeSig>
            <tempo>
              <t>0</t>
              <v>\(tempoVal)</v>
            </tempo>
          </masterTrack>
          <vsTrack>
            <tNo>0</tNo>
            <name><![CDATA[\(escapeCDATA(selectedInstrument))]]></name>
            <comment><![CDATA[Track 1]]></comment>
            <vsPart>
              <t>0</t>
              <playTime>\(totalPartDuration)</playTime>
              <name><![CDATA[\(escapeCDATA(selectedInstrument))]]></name>
              <comment><![CDATA[Part 1]]></comment>
              <sPlug>
                <id><![CDATA[GLB1Q310S0000000]]></id>
                <name><![CDATA[VOCALOID2 Compatibility]]></name>
                <version><![CDATA[1.0.0.1]]></version>
              </sPlug>
              <pStyle>
                <v id="accent">50</v>
                <v id="bendDep">0</v>
                <v id="bendLen">0</v>
                <v id="decay">50</v>
                <v id="fallPort">0</v>
                <v id="opening">127</v>
                <v id="risePort">0</v>
              </pStyle>
              <singer>
                <t>0</t>
                <bs>0</bs>
                <pc>0</pc>
              </singer>

        """

        for note in notes {
            xml += """
                  <note>
                    <t>\(note.posTick)</t>
                    <dur>\(note.durTick)</dur>
                    <n>\(note.noteNum)</n>
                    <v>64</v>
                    <y><![CDATA[\(escapeCDATA(note.lyric))]]></y>
                    <p><![CDATA[\(escapeCDATA(note.phnm))]]></p>
                    <nStyle>
                      <v id="accent">50</v>
                      <v id="bendDep">0</v>
                      <v id="bendLen">0</v>
                      <v id="decay">50</v>
                      <v id="fallPort">0</v>
                      <v id="opening">127</v>
                      <v id="risePort">0</v>
                    </nStyle>
                  </note>

            """
        }

        xml += """
              <plane>0</plane>
            </vsPart>
          </vsTrack>
        </vsq4>

        """

        return xml
    }

    private static func resolveTargetInstrument(sheet: Sheet, requested: String?) -> String {
        sheet.resolveVocalInstrument(requested: requested)
    }

    private static func escapeCDATA(_ text: String) -> String {
        text.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
    }
}
