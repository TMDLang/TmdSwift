import Foundation
import TmdSwift

/// MusicXML generator for TMD Sheets.
///
/// Exports the Sheet AST into W3C MusicXML (Partwise) format for use with notation software
/// such as MuseScore, Finale, Sibelius, Dorico, or web renderers like OpenSheetMusicDisplay.
public struct TMDMusicXMLGenerator {

    /// Generates MusicXML UTF-8 string from a Sheet.
    public static func generateMusicXML(from sheet: Sheet) -> String {
        let metadataCreators = sheet.metadata.sorted { $0.key < $1.key }.map { key, value in
            let type = key.lowercased() == "lyrics" ? "lyricist" : (key.lowercased() == "arranger" ? "arranger" : "composer")
            return "    <creator type=\"\(type)\">\(escapeXML(value))</creator>"
        }.joined(separator: "\n")
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
        <score-partwise version="4.0">
          <work>
            <work-title>\(escapeXML(sheet.name.isEmpty ? "Untitled Score" : sheet.name))</work-title>
          </work>
          <identification>
            <creator type="composer">TMD</creator>
        \(metadataCreators)
            <encoding>
              <software>TmdSwift MusicXML Exporter</software>
            </encoding>
          </identification>

        """

        let instruments = sheet.distinctInstruments()

        // Part List
        xml += "  <part-list>\n"
        for (idx, inst) in instruments.enumerated() {
            let partID = "P\(idx + 1)"
            xml += """
                <score-part id="\(partID)">
                  <part-name>\(escapeXML(inst))</part-name>
                </score-part>

            """
        }
        xml += "  </part-list>\n"

        let divisions = 16 // 16 divisions per quarter note gives high subdivision precision

        // Generate <part> for each instrument
        for (idx, inst) in instruments.enumerated() {
            let partID = "P\(idx + 1)"
            xml += "  <part id=\"\(partID)\">\n"
            xml += generatePartMeasures(
                instrument: inst,
                sheet: sheet,
                divisions: divisions
            )
            xml += "  </part>\n"
        }

        xml += "</score-partwise>\n"
        return xml
    }

    private static func generatePartMeasures(
        instrument: String,
        sheet: Sheet,
        divisions: Int
    ) -> String {
        let measures = TMDMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        var xml = ""

        for measure in measures {
            var content = ""
            if measure.index == 0 {
                content += generateAttributesXML(sheet: sheet, divisions: divisions)
            }
            for directive in measure.directives {
                content += generatePlaybackDirectiveXML(directive)
            }

            for event in measure.events {
                let duration = max(1, Int((event.duration * Double(divisions)).rounded()))
                switch event.content {
                case .note(let note):
                    content += generateNoteXML(
                        note: note,
                        duration: duration,
                        keyOffset: event.state.keyOffset,
                        tieStart: event.tieStart,
                        tieStop: event.tieStop
                    )
                case .chord(let chord):
                    content += generateChordXML(
                        chordName: chord.description,
                        duration: duration,
                        keyOffset: event.state.keyOffset
                    )
                case .rest:
                    content += generateRestXML(duration: duration)
                case .percussion(let pattern):
                    content += generatePercussionXML(pattern: pattern, duration: duration)
                }
            }
            xml += "    <measure number=\"\(measure.index + 1)\">\n\(content)    </measure>\n\n"
        }
        return xml
    }

    private static func generateRestXML(duration: Int) -> String {
        """
                <note>
                  <rest/>
                  <duration>\(max(1, duration))</duration>
                </note>

        """
    }

    private static func generatePlaybackDirectiveXML(_ directive: PlaybackDirectiveEvent) -> String {
        switch directive.kind {
        case .tempo, .relativeTempo:
            return """
                    <direction placement=\"above\">
                      <direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>\(Int(directive.state.tempo.rounded()))</per-minute></metronome></direction-type>
                      <sound tempo=\"\(directive.state.tempo)\"/>
                    </direction>

            """
        case .timeSignature(let beat):
            return """
                    <attributes><time><beats>\(beat.count)</beats><beat-type>\(beat.noteValue)</beat-type></time></attributes>

            """
        case .absoluteKey(let key):
            return "        <attributes><key><fifths>\(keySignatureToFifths(key))</fifths></key></attributes>\n"
        case .relativeKey:
            return "        <!-- TMD relative key modulation -->\n"
        }
    }

    private static func generatePercussionXML(pattern: String, duration: Int) -> String {
        let notes = pattern.compactMap { character -> (String, Int)? in
            switch character {
            case "X", "x": return ("F", 5) // closed hi-hat, MIDI 42
            case "T", "t": return ("A", 4) // low tom, MIDI 45
            case "S", "s": return ("D", 5) // snare, MIDI 38
            default: return nil
            }
        }
        if notes.isEmpty {
            return generateRestXML(duration: duration)
        }
        let count = notes.count
        let base = duration / count
        let remainder = duration % count
        var xml = ""
        for (i, (step, octave)) in notes.enumerated() {
            let noteDur = base + (i < remainder ? 1 : 0)
            xml += """
                    <note>
                      <unpitched>
                        <display-step>\(step)</display-step>
                        <display-octave>\(octave)</display-octave>
                      </unpitched>
                      <duration>\(noteDur)</duration>
                    </note>

            """
        }
        return xml
    }

    private static func generateAttributesXML(sheet: Sheet, divisions: Int) -> String {
        return """
              <attributes>
                <divisions>\(divisions)</divisions>
                <key>
                  <fifths>\(keySignatureToFifths(sheet.keySignature.description))</fifths>
                </key>
                <time>
                  <beats>\(sheet.beat.count)</beats>
                  <beat-type>\(sheet.beat.noteValue)</beat-type>
                </time>
                <clef>
                  <sign>G</sign>
                  <line>2</line>
                </clef>
              </attributes>
              <direction placement="above">
                <direction-type>
                  <metronome>
                    <beat-unit>quarter</beat-unit>
                    <per-minute>\(Int(sheet.speed > 0 ? sheet.speed : 120))</per-minute>
                  </metronome>
                </direction-type>
                <sound tempo="\(Int(sheet.speed > 0 ? sheet.speed : 120))"/>
              </direction>

        """
    }

    private static func generateNoteXML(
        note: Note,
        duration: Int,
        keyOffset: Int,
        tieStart: Bool = false,
        tieStop: Bool = false
    ) -> String {
        let (step, alter, octave) = pitchToStepAlterOctave(note: note, keyOffset: keyOffset)
        var xml = """
                <note>
                  <pitch>
                    <step>\(step)</step>

        """
        if alter != 0 {
            xml += "            <alter>\(alter)</alter>\n"
        }
        xml += """
                    <octave>\(octave)</octave>
                  </pitch>
                  <duration>\(duration)</duration>

        """
        if tieStop {
            xml += "          <tie type=\"stop\"/>\n"
        }
        if tieStart {
            xml += "          <tie type=\"start\"/>\n"
        }
        if tieStart || tieStop {
            xml += "          <notations>\n"
            if tieStop {
                xml += "            <tied type=\"stop\"/>\n"
            }
            if tieStart {
                xml += "            <tied type=\"start\"/>\n"
            }
            xml += "          </notations>\n"
        }
        xml += "        </note>\n\n"
        return xml
    }

    private static func generateChordXML(chordName: String, duration: Int, keyOffset: Int) -> String {
        // Output chord harmony symbol & note representation
        let xml = """
              <harmony>
                <root>
                  <root-step>\(escapeXML(chordName))</root-step>
                </root>
                <kind text="\(escapeXML(chordName))">other</kind>
              </harmony>
              <note>
                <rest/>
                <duration>\(duration)</duration>
              </note>

        """
        return xml
    }

    // MARK: - Musical Conversion Helpers

    private static func pitchToStepAlterOctave(note: Note, keyOffset: Int) -> (step: String, alter: Int, octave: Int) {
        let degree = note.degree.rawValue
        guard (1...7).contains(degree) else { return ("C", 0, 4) }
        var midiPitch = 60 + keyOffset + note.degree.semitoneOffset
        switch note.accidental {
        case .sharp: midiPitch += 1
        case .flat: midiPitch -= 1
        case .natural: break
        }
        midiPitch += note.octave * 12

        // Convert MIDI pitch to Step + Alter + Octave
        let semitone = ((midiPitch % 12) + 12) % 12
        let step = PitchMapping.musicXMLSteps[semitone]
        let alter = PitchMapping.musicXMLAlters[semitone]
        let octave = (midiPitch / 12) - 1

        return (step, alter, octave)
    }

    private static func keySignatureToFifths(_ key: String) -> Int {
        let trimmed = key.trimmingCharacters(in: .whitespaces).uppercased()
        switch trimmed {
        case "C": return 0
        case "G": return 1
        case "D": return 2
        case "A": return 3
        case "E": return 4
        case "B": return 5
        case "F#", "F'": return 6
        case "F": return -1
        case "BB", "B,": return -2
        case "EB", "E,": return -3
        case "AB", "A,", "A'": return 3 // A major = 3 sharps
        case "DB", "D,": return -5
        case "GB", "G,": return -6
        default: return 0
        }
    }

    private static func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
