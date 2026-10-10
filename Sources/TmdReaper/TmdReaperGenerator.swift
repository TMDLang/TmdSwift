import Foundation
import TmdMIDI
import TmdSwift

/// Exporter for REAPER project files (.rpp) with tempo maps, markers, and inline MIDI data.
public struct TmdReaperGenerator {
    public static let defaultPPQ: UInt16 = 960

    /// Generates REAPER project file content (.rpp) from a Sheet.
    public static func generateRPP(from inputSheet: Sheet, ppq: UInt16 = defaultPPQ) -> String {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let distinctInstruments = sheet.distinctInstruments(fallbackToDefault: false)
        let conductorTimeline = TmdPlaybackRenderer.renderConductor(sheet: sheet)

        // Build timeline tempo segments
        let sortedDirectives = conductorTimeline.directives.sorted { $0.position < $1.position }
        let segments = TmdPlaybackRenderer.buildTempoSegments(
            initialTempo: sheet.speed,
            initialBeat: sheet.beat,
            directives: sortedDirectives
        )

        // Section markers
        let orders = sheet.effectivePlaybackOrders

        var currentQuarter = 0.0
        var markerId = 1
        var markerLines: [String] = []
        var markerTimeSignature = sheet.beat
        var markerDirectiveIndex = 0

        for order in orders {
            if case .name(let name) = order {
                while markerDirectiveIndex < sortedDirectives.count,
                    sortedDirectives[markerDirectiveIndex].position <= currentQuarter
                {
                    if case .timeSignature(let beat) = sortedDirectives[markerDirectiveIndex].kind {
                        markerTimeSignature = beat
                    }
                    markerDirectiveIndex += 1
                }
                let paragraphDuration = TmdPlaybackRenderer.duration(
                    of: name, in: sheet, beat: markerTimeSignature)
                let secondPos = TmdPlaybackRenderer.quarterToSeconds(
                    currentQuarter, segments: segments)
                markerLines.append(
                    String(format: "  MARKER %d %.8f \"%@\" 0", markerId, secondPos, name))
                markerId += 1
                currentQuarter += paragraphDuration
            }
        }

        // Build Tempo Envelope Points (PT)
        var ptLines: [String] = []
        for seg in segments {
            let timesigEncoded = (seg.timeSignature.noteValue << 16) | seg.timeSignature.count
            ptLines.append(
                String(format: "    PT %.8f %.8f 0 %d", seg.secondStart, seg.bpm, timesigEncoded))
        }

        // Build Tracks
        var trackChunks: [String] = []
        var melodyChannel: UInt8 = 0

        for instrument in distinctInstruments {
            let instTimeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: instrument)
            guard instTimeline.events.contains(where: \.content.isSounding) else { continue }
            let midiInst = MIDIInstrument.resolve(instrument)
            let channel = midiInst.allocateChannel(nextMelodicChannel: &melodyChannel)

            // Pan
            let pan: Double = switch MIDIInstrument.stereoPanHeuristic(for: instrument) {
            case .left: -0.8
            case .right: 0.8
            case .center: 0.0
            }

            // Color
            let color = getTrackColor(midiInst)

            // Render track events
            let events: [MIDIEvent] = TmdMIDIGenerator.instrumentEvents(
                timeline: instTimeline,
                instrument: instrument,
                midiInstrument: midiInst,
                channel: channel,
                ticksPerQuarter: ppq
            )

            let totalDurationQuarters = max(instTimeline.duration, currentQuarter)
            let totalTrackSeconds = max(
                1.0, TmdPlaybackRenderer.quarterToSeconds(totalDurationQuarters, segments: segments)
            )

            // Serialize inline MIDI events
            let sortedEvents = events.sorted { $0.tick < $1.tick }
            var lastTick: UInt32 = 0
            var eventLines: [String] = []

            for evt in sortedEvents {
                let delta = evt.tick >= lastTick ? evt.tick - lastTick : 0
                lastTick = evt.tick
                if let line = evt.message.reaperEventLine(delta: delta) {
                    eventLines.append(line)
                }
            }

            if !events.isEmpty {
                let status = String(format: "%02x", 0xB0 | (channel & 0x0F))
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
        var r: UInt32 = 120
        var g: UInt32 = 140
        var b: UInt32 = 160
        if midiInst.isPercussion {
            r = 230
            g = 80
            b = 50
        } else {
            switch midiInst.program {
            case 0...7:  // Piano & Keys
                r = 150
                g = 70
                b = 210
            case 8...15, 112...119:  // Chromatic Percussion & Percussive
                r = 230
                g = 80
                b = 50
            case 16...23:  // Organ
                r = 150
                g = 70
                b = 210
            case 24...31:  // Guitar
                r = 50
                g = 180
                b = 80
            case 32...39:  // Bass
                r = 30
                g = 130
                b = 230
            case 40...51:  // Strings & Ensemble
                r = 230
                g = 160
                b = 30
            case 52...55:  // Choir & Voices
                r = 220
                g = 100
                b = 180
            case 56...63:  // Brass
                r = 230
                g = 200
                b = 30
            case 64...71:  // Reeds
                r = 30
                g = 180
                b = 180
            case 72...79:  // Pipes
                r = 30
                g = 180
                b = 180
            case 80...87:  // Synth Lead
                r = 240
                g = 80
                b = 160
            case 88...95:  // Synth Pad
                r = 220
                g = 100
                b = 180
            case 96...103, 120...127:  // FX & Sound FX
                r = 100
                g = 200
                b = 220
            case 104...111:  // Ethnic
                r = 200
                g = 140
                b = 60
            default:
                break
            }
        }
        let native = (r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16)
        return 0x1000000 | native
    }
}

private extension MIDIMessage {
    func reaperEventLine(delta: UInt32) -> String? {
        switch self {
        case .programChange(let ch, let prog):
            let status = String(format: "%02x", 0xC0 | (ch & 0x0F))
            let d1 = String(format: "%02x", prog & 0x7F)
            return "        E \(delta) \(status) \(d1) 00"
        case .controlChange(let ch, let cc, let val):
            let status = String(format: "%02x", 0xB0 | (ch & 0x0F))
            let d1 = String(format: "%02x", cc & 0x7F)
            let d2 = String(format: "%02x", val & 0x7F)
            return "        E \(delta) \(status) \(d1) \(d2)"
        case .noteOn(let ch, let note, let vel):
            let status = String(format: "%02x", 0x90 | (ch & 0x0F))
            let d1 = String(format: "%02x", note & 0x7F)
            let d2 = String(format: "%02x", vel & 0x7F)
            return "        E \(delta) \(status) \(d1) \(d2)"
        case .noteOff(let ch, let note):
            let status = String(format: "%02x", 0x80 | (ch & 0x0F))
            let d1 = String(format: "%02x", note & 0x7F)
            return "        E \(delta) \(status) \(d1) 00"
        case .trackName, .tempo, .timeSignature, .endOfTrack, .text, .customMeta:
            return nil
        }
    }
}


