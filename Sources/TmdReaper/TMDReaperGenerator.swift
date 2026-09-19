import Foundation
import TmdSwift
import TmdMIDI

private struct TempoSegment {
    var quarterStart: Double
    var secondStart: Double
    var bpm: Double
    var timeSignature: Beat
}

/// Exporter for REAPER project files (.rpp) with tempo maps, markers, and inline MIDI data.
public struct TMDReaperGenerator {
    public static let defaultPPQ: UInt16 = 960

    /// Generates REAPER project file content (.rpp) from a Sheet.
    public static func generateRPP(from sheet: Sheet, ppq: UInt16 = defaultPPQ) -> String {
        let distinctInstruments = sheet.distinctInstruments()
        let timelineInstrument = sheet.paragraphs.first {
            $0.sections.contains { !$0.directives.isEmpty }
        }?.instrument ?? distinctInstruments.first ?? "Piano"

        let conductorTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: timelineInstrument)

        // Build timeline tempo segments
        let initialBpm = sheet.speed > 0 ? sheet.speed : 120
        let initialTimeSig = sheet.beat

        var segments: [TempoSegment] = [
            TempoSegment(
                quarterStart: 0,
                secondStart: 0,
                bpm: initialBpm,
                timeSignature: initialTimeSig
            )
        ]

        let sortedDirectives = conductorTimeline.directives.sorted { $0.position < $1.position }

        for directive in sortedDirectives {
            switch directive.kind {
            case .tempo, .relativeTempo, .timeSignature:
                let last = segments[segments.count - 1]
                if directive.position > last.quarterStart {
                    let deltaQuarters = directive.position - last.quarterStart
                    let deltaSeconds = deltaQuarters * (60.0 / last.bpm)
                    let secondStart = last.secondStart + deltaSeconds
                    segments.append(TempoSegment(
                        quarterStart: directive.position,
                        secondStart: secondStart,
                        bpm: directive.state.tempo,
                        timeSignature: directive.state.timeSignature
                    ))
                } else if directive.position == last.quarterStart {
                    segments[segments.count - 1].bpm = directive.state.tempo
                    segments[segments.count - 1].timeSignature = directive.state.timeSignature
                }
            case .absoluteKey, .relativeKey:
                break
            }
        }

        let quarterToSeconds: (Double) -> Double = { quarter in
            if quarter <= 0 { return 0 }
            var seg = segments[0]
            for s in segments.reversed() {
                if quarter >= s.quarterStart {
                    seg = s
                    break
                }
            }
            let deltaQuarters = quarter - seg.quarterStart
            return seg.secondStart + deltaQuarters * (60.0 / seg.bpm)
        }

        // Section markers
        let orders: [Order] = !sheet.orders.isEmpty
            ? sheet.orders
            : sheet.paragraphs.map(\.name).reduce(into: [String]()) { names, name in
                if !names.contains(name) { names.append(name) }
            }.map(Order.name)

        var currentQuarter = 0.0
        var markerId = 1
        var markerLines: [String] = []

        for order in orders {
            if case .name(let name) = order {
                let paragraphDuration = TMDPlaybackRenderer.duration(of: name, in: sheet)
                let secondPos = quarterToSeconds(currentQuarter)
                markerLines.append(String(format: "  MARKER %d %.8f \"%@\" 0", markerId, secondPos, name))
                markerId += 1
                currentQuarter += paragraphDuration
            }
        }

        // Build Tempo Envelope Points (PT)
        var ptLines: [String] = []
        for seg in segments {
            let timesigEncoded = (seg.timeSignature.noteValue << 16) | seg.timeSignature.count
            ptLines.append(String(format: "    PT %.8f %.8f 0 %d", seg.secondStart, seg.bpm, timesigEncoded))
        }

        // Build Tracks
        var trackChunks: [String] = []
        var melodyChannel: UInt8 = 0

        for instrument in distinctInstruments {
            let midiInst = MIDIInstrument.resolve(instrument)
            let channel: UInt8
            if midiInst.isPercussion {
                channel = 9
            } else {
                if melodyChannel == 9 { melodyChannel += 1 }
                channel = melodyChannel % 16
                melodyChannel += 1
            }

            // Pan
            var pan: Double = 0.0
            let lower = instrument.lowercased()
            if lower.contains("left") || lower.contains("-l") {
                pan = -0.8
            } else if lower.contains("right") || lower.contains("-r") {
                pan = 0.8
            }

            // Color
            let color = getTrackColor(midiInst)

            // Render track events
            let instTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: instrument)
            let events: [MIDIEvent] = TMDMIDIGenerator.instrumentEvents(
                timeline: instTimeline,
                instrument: instrument,
                midiInstrument: midiInst,
                channel: channel,
                ticksPerQuarter: ppq
            )

            let totalDurationQuarters = max(instTimeline.duration, currentQuarter)
            let totalTrackSeconds = max(1.0, quarterToSeconds(totalDurationQuarters))

            // Serialize inline MIDI events
            let sortedEvents = events.sorted { $0.tick < $1.tick }
            var lastTick: UInt32 = 0
            var eventLines: [String] = []

            func toHex2(_ n: UInt8) -> String {
                String(format: "%02x", n)
            }

            for evt in sortedEvents {
                let delta = evt.tick >= lastTick ? evt.tick - lastTick : 0
                lastTick = evt.tick
                switch evt.message {
                case .noteOn(let ch, let note, let velocity):
                    let status = toHex2(0x90 | (ch & 0x0F))
                    let data1 = toHex2(note & 0x7F)
                    let data2 = toHex2(velocity & 0x7F)
                    eventLines.append("        E \(delta) \(status) \(data1) \(data2)")
                case .noteOff(let ch, let note):
                    let status = toHex2(0x80 | (ch & 0x0F))
                    let data1 = toHex2(note & 0x7F)
                    eventLines.append("        E \(delta) \(status) \(data1) 00")
                case .programChange(let ch, let prog):
                    let status = toHex2(0xC0 | (ch & 0x0F))
                    let data1 = toHex2(prog & 0x7F)
                    eventLines.append("        E \(delta) \(status) \(data1)")
                case .controlChange(let ch, let ctrl, let val):
                    let status = toHex2(0xB0 | (ch & 0x0F))
                    let data1 = toHex2(ctrl & 0x7F)
                    let data2 = toHex2(val & 0x7F)
                    eventLines.append("        E \(delta) \(status) \(data1) \(data2)")
                case .trackName, .tempo, .timeSignature, .endOfTrack, .text, .customMeta:
                    break
                }
            }

            if !events.isEmpty {
                let status = toHex2(0xB0 | (channel & 0x0F))
                eventLines.append("        E 0 \(status) 7b 00")
            }

            var trackChunkLines = [
                "  <TRACK",
                "    NAME \"\(instrument)\"",
                "    PEAKCOL \(color)",
                String(format: "    VOLPAN 1.00000000 %.8f 1 -1 1", pan),
                "    <ITEM",
                "      POSITION 0.00000000",
                "      SNAPOFFS 0.00000000",
                String(format: "      LENGTH %.8f", totalTrackSeconds),
                "      LOOP 0",
                "      ALLTAKES 0",
                "      NAME \"\(instrument)\"",
                "      <SOURCE MIDI",
                "        HASDATA 1 \(ppq) QN",
            ]
            trackChunkLines.append(contentsOf: eventLines)
            trackChunkLines.append("      >")
            trackChunkLines.append("    >")
            trackChunkLines.append("  >")

            trackChunks.append(trackChunkLines.joined(separator: "\n"))
        }

        var lines: [String] = [
            "<REAPER_PROJECT 0.1 \"7.0\" 0 0",
            "  <TEMPOENVEX",
            "    ACT 1",
            "    VIS 1 0 1",
            "    LANEHEIGHT 0 0",
            "    ARM 1",
            "    DEFSHAPE 0 -1 -1",
        ]
        lines.append(contentsOf: ptLines)
        lines.append("  >")
        lines.append(contentsOf: markerLines)
        lines.append(contentsOf: trackChunks)
        lines.append(">")
        lines.append("")

        return lines.joined(separator: "\n")
    }

    private static func getTrackColor(_ midiInst: MIDIInstrument) -> UInt32 {
        var r: UInt32 = 120, g: UInt32 = 140, b: UInt32 = 160
        if midiInst.isPercussion {
            r = 230; g = 80; b = 50
        } else {
            switch midiInst.program {
            case 0...7: // Piano & Keys
                r = 150; g = 70; b = 210
            case 8...15, 112...119: // Chromatic Percussion & Percussive
                r = 230; g = 80; b = 50
            case 16...23: // Organ
                r = 150; g = 70; b = 210
            case 24...31: // Guitar
                r = 50; g = 180; b = 80
            case 32...39: // Bass
                r = 30; g = 130; b = 230
            case 40...51: // Strings & Ensemble
                r = 230; g = 160; b = 30
            case 52...55: // Choir & Voices
                r = 220; g = 100; b = 180
            case 56...63: // Brass
                r = 230; g = 200; b = 30
            case 64...71: // Reeds
                r = 30; g = 180; b = 180
            case 72...79: // Pipes
                r = 30; g = 180; b = 180
            case 80...87: // Synth Lead
                r = 240; g = 80; b = 160
            case 88...95: // Synth Pad
                r = 220; g = 100; b = 180
            case 96...103, 120...127: // FX & Sound FX
                r = 100; g = 200; b = 220
            case 104...111: // Ethnic
                r = 200; g = 140; b = 60
            default:
                break
            }
        }
        let native = (r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16)
        return 0x1000000 | native
    }
}
