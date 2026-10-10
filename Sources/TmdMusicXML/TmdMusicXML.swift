import Foundation
import TmdSwift

/// MusicXML generator for TMD Sheets.
///
/// Exports the Sheet AST into W3C MusicXML (Partwise) format for use with notation software
/// such as MuseScore, Finale, Sibelius, Dorico, or web renderers like OpenSheetMusicDisplay.
public struct TmdMusicXMLGenerator {

    /// Generates MusicXML UTF-8 string from a Sheet.
    public static func generateMusicXML(from inputSheet: Sheet) -> String {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let metadataCreators = sheet.metadata.sorted { $0.key < $1.key }.map { key, value in
            let type =
                key.lowercased() == "lyrics"
                ? "lyricist" : (key.lowercased() == "arranger" ? "arranger" : "composer")
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

        let instruments = sheet.distinctInstruments(fallbackToDefault: false)

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

        let divisions = 48  // 48 divisions per quarter note gives high subdivision precision and cleanly divides triplets

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
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        var xml = ""

        let initialKey =
            sheet.declaredKey
            ?? PitchMapping.tonicScaleInfo(forKeyOffset: sheet.keySignature.semitoneOffset).name
        var defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: initialKey)

        for measure in measures {
            var content = ""
            var measureStepAlters: [Int: [Int]] = [:]
            if measure.index == 0 {
                content += generateAttributesXML(
                    sheet: sheet, instrument: instrument, divisions: divisions)
            }
            for directive in measure.directives {
                switch directive.kind {
                case .explicitKey(let key):
                    defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: key)
                    measureStepAlters.removeAll()
                case .absoluteKey, .relativeKey:
                    let newKey = PitchMapping.tonicScaleInfo(
                        forKeyOffset: directive.state.keyOffset
                    ).name
                    defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: newKey)
                    measureStepAlters.removeAll()
                case .fixedPitch:
                    defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: "C")
                    measureStepAlters.removeAll()
                default:
                    break
                }
                content += directive.musicXMLString
            }

            let expectedMeasureDuration = max(
                1, Int((measure.nominalDuration * Double(divisions)).rounded()))
            var durations: [Int] = measure.events.map { event in
                max(1, Int((event.duration * Double(divisions)).rounded()))
            }
            // Balance durations to conserve measure nominal duration
            let totalDur = durations.reduce(0, +)
            let diff = expectedMeasureDuration - totalDur
            if diff != 0 && !durations.isEmpty {
                // Adjust the last event or the largest event
                let lastIdx = durations.count - 1
                durations[lastIdx] = max(1, durations[lastIdx] + diff)
            }

            for (idx, event) in measure.events.enumerated() {
                let duration = durations[idx]
                switch event.content {
                case .note(let note):
                    let spelled = PitchMapping.spell(note: note, keyOffset: event.state.keyOffset)
                    var octaveAlters = measureStepAlters[spelled.octave] ?? defaultKeyStepAlters
                    let expectedAlter = octaveAlters[spelled.stepIndex]
                    var accidentalText: String? = nil
                    if spelled.alter != expectedAlter && !event.tieStop {
                        octaveAlters[spelled.stepIndex] = spelled.alter
                        measureStepAlters[spelled.octave] = octaveAlters
                        accidentalText = musicXMLAccidentalName(forAlter: spelled.alter)
                    }
                    content += generateNoteXML(
                        note: note,
                        duration: duration,
                        divisions: divisions,
                        keyOffset: event.state.keyOffset,
                        tieStart: event.tieStart,
                        tieStop: event.tieStop,
                        accidentalText: accidentalText
                    )
                case .chord(let chord):
                    content += generateChordXML(
                        chord: chord,
                        duration: duration,
                        divisions: divisions,
                        keyOffset: event.state.keyOffset
                    )
                case .rest:
                    content += generateRestXML(duration: duration, divisions: divisions)
                case .percussion(let pattern):
                    content += generatePercussionXML(
                        pattern: pattern, duration: duration, divisions: divisions)
                }
            }
            xml += "    <measure number=\"\(measure.index + 1)\">\n\(content)    </measure>\n\n"
        }
        return xml
    }

    private struct NoteDurationInfo {
        let type: String
        let dots: Int
        let timeModification: (actualNotes: Int, normalNotes: Int)?
    }

    private static func durationInfo(duration: Int, divisions: Int) -> NoteDurationInfo? {
        let d = divisions
        // Standard durations
        if duration == 4 * d {
            return NoteDurationInfo(type: "whole", dots: 0, timeModification: nil)
        }
        if duration == 3 * d {
            return NoteDurationInfo(type: "half", dots: 1, timeModification: nil)
        }
        if duration == 2 * d {
            return NoteDurationInfo(type: "half", dots: 0, timeModification: nil)
        }
        if duration == d + d / 2 {
            return NoteDurationInfo(type: "quarter", dots: 1, timeModification: nil)
        }
        if duration == d {
            return NoteDurationInfo(type: "quarter", dots: 0, timeModification: nil)
        }
        if duration == d / 2 + d / 4 {
            return NoteDurationInfo(type: "eighth", dots: 1, timeModification: nil)
        }
        if duration == d / 2 {
            return NoteDurationInfo(type: "eighth", dots: 0, timeModification: nil)
        }
        if duration == d / 4 + d / 8 {
            return NoteDurationInfo(type: "16th", dots: 1, timeModification: nil)
        }
        if duration == d / 4 {
            return NoteDurationInfo(type: "16th", dots: 0, timeModification: nil)
        }
        if duration == d / 8 {
            return NoteDurationInfo(type: "32nd", dots: 0, timeModification: nil)
        }
        if duration == d / 16 {
            return NoteDurationInfo(type: "64th", dots: 0, timeModification: nil)
        }

        // Triplet (3:2) durations: duration = (normalDur * 2) / 3
        if duration == (4 * d * 2) / 3 {
            return NoteDurationInfo(type: "whole", dots: 0, timeModification: (3, 2))
        }
        if duration == (2 * d * 2) / 3 {
            return NoteDurationInfo(type: "half", dots: 0, timeModification: (3, 2))
        }
        if duration == (d * 2) / 3 {
            return NoteDurationInfo(type: "quarter", dots: 0, timeModification: (3, 2))
        }
        if duration == (d / 2 * 2) / 3 {
            return NoteDurationInfo(type: "eighth", dots: 0, timeModification: (3, 2))
        }
        if duration == (d / 4 * 2) / 3 {
            return NoteDurationInfo(type: "16th", dots: 0, timeModification: (3, 2))
        }
        if duration == (d / 8 * 2) / 3 {
            return NoteDurationInfo(type: "32nd", dots: 0, timeModification: (3, 2))
        }

        return nil
    }

    private static func musicXMLAccidentalName(forAlter alter: Int) -> String? {
        switch alter {
        case 0: return "natural"
        case 1: return "sharp"
        case -1: return "flat"
        case 2: return "double-sharp"
        case -2: return "flat-flat"
        default: return alter > 2 ? "double-sharp" : (alter < -2 ? "flat-flat" : nil)
        }
    }

    private static func generateDurationElementsXML(
        duration: Int,
        divisions: Int,
        accidentalText: String? = nil
    ) -> String {
        guard let info = durationInfo(duration: duration, divisions: divisions) else {
            if let accidentalText {
                return "          <accidental>\(accidentalText)</accidental>\n"
            }
            return ""
        }
        var xml = "          <type>\(info.type)</type>\n"
        for _ in 0..<info.dots {
            xml += "          <dot/>\n"
        }
        if let accidentalText {
            xml += "          <accidental>\(accidentalText)</accidental>\n"
        }
        if let tm = info.timeModification {
            xml += """
                          <time-modification>
                            <actual-notes>\(tm.actualNotes)</actual-notes>
                            <normal-notes>\(tm.normalNotes)</normal-notes>
                          </time-modification>

                """
        }
        return xml
    }

    private static func generateRestXML(duration: Int, divisions: Int) -> String {
        var xml = """
                    <note>
                      <rest/>
                      <duration>\(max(1, duration))</duration>

            """
        xml += generateDurationElementsXML(duration: duration, divisions: divisions)
        xml += "        </note>\n\n"
        return xml
    }

    private static func isPercussionInstrument(_ instrument: String, sheet: Sheet) -> Bool {
        let lower = instrument.lowercased()
        let aliases = [
            "drum", "drums", "groove", "percussion", "beat", "drumkit", "cajon", "snare", "kick",
            "hihat",
        ]
        if aliases.contains(where: { lower.contains($0) }) { return true }
        return sheet.entries.filter { $0.assignment == instrument }.contains { paragraph in
            paragraph.sections.contains { section in
                section.unitGroups.contains { group in
                    group.units.contains {
                        if case .percussion = $0 { return true }
                        return false
                    }
                }
            }
        }
    }

    private static func isBassClefInstrument(_ instrument: String) -> Bool {
        let lower = instrument.lowercased()
        let bassKeywords = [
            "bass", "cello", "tuba", "contrabass", "bassoon", "trombone", "baritone", "timpani",
        ]
        return bassKeywords.contains { lower.contains($0) }
    }

    private static func generateClefXML(instrument: String, sheet: Sheet) -> String {
        if isPercussionInstrument(instrument, sheet: sheet) {
            return """
                        <clef>
                          <sign>percussion</sign>
                        </clef>
                """
        } else if isBassClefInstrument(instrument) {
            return """
                        <clef>
                          <sign>F</sign>
                          <line>4</line>
                        </clef>
                """
        } else {
            return """
                        <clef>
                          <sign>G</sign>
                          <line>2</line>
                        </clef>
                """
        }
    }

    public static func semitoneOffsetToFifths(_ semitoneOffset: Int) -> Int {
        let normalized = (semitoneOffset % 12 + 12) % 12
        switch normalized {
        case 0: return 0  // C
        case 1: return -5  // Db
        case 2: return 2  // D
        case 3: return -3  // Eb
        case 4: return 4  // E
        case 5: return -1  // F
        case 6: return 6  // F# / Gb (-6)
        case 7: return 1  // G
        case 8: return -4  // Ab
        case 9: return 3  // A
        case 10: return -2  // Bb
        case 11: return 5  // B
        default: return 0
        }
    }

    public static func resolveMetronome(beat: Beat, quarterBPM: Double) -> (
        beatUnit: String, isDotted: Bool, perMinute: Int
    ) {
        // Compound meter: denominator is 8 and numerator is a multiple of 3 (> 3, e.g. 6/8, 9/8, 12/8)
        if beat.noteValue == 8 && beat.count > 3 && beat.count % 3 == 0 {
            // Beat unit is a dotted-quarter note (value = 1.5 quarters)
            let bpm = quarterBPM / 1.5
            return ("quarter", true, Int(bpm.rounded()))
        }
        // Beat unit based on time signature denominator
        switch beat.noteValue {
        case 2:
            // Half note (value = 2.0 quarters)
            let bpm = quarterBPM / 2.0
            return ("half", false, Int(bpm.rounded()))
        case 8:
            // Eighth note (value = 0.5 quarters)
            let bpm = quarterBPM * 2.0
            return ("eighth", false, Int(bpm.rounded()))
        case 16:
            // 16th note (value = 0.25 quarters)
            let bpm = quarterBPM * 4.0
            return ("16th", false, Int(bpm.rounded()))
        default:
            // Default: quarter note
            return ("quarter", false, Int(quarterBPM.rounded()))
        }
    }

    private static func generatePercussionXML(pattern: String, duration: Int, divisions: Int)
        -> String
    {
        let notes = pattern.compactMap { character -> (String, Int)? in
            switch character {
            case "D", "d", "B", "b": return ("F", 4)  // Bass Drum 1 (Kick) - F4
            case "S", "s": return ("D", 5)  // Acoustic Snare - D5
            case "X", "x": return ("F", 5)  // Closed Hi-Hat - F5
            case "O", "o": return ("G", 5)  // Open Hi-Hat - G5
            case "T", "t": return ("A", 4)  // Low-Mid Tom - A4
            case "C", "c": return ("A", 5)  // Crash Cymbal 1 - A5
            default: return nil
            }
        }
        if notes.isEmpty {
            return generateRestXML(duration: duration, divisions: divisions)
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

                """
            xml += generateDurationElementsXML(duration: noteDur, divisions: divisions)
            xml += "        </note>\n\n"
        }
        return xml
    }

    private static func generateAttributesXML(sheet: Sheet, instrument: String, divisions: Int)
        -> String
    {
        let speed = sheet.speed > 0 ? sheet.speed : 120
        let initialMetronome = resolveMetronome(beat: sheet.beat, quarterBPM: speed)
        let dotTag = initialMetronome.isDotted ? "\n            <beat-unit-dot/>" : ""
        let keyInfo: (fifths: Int, mode: String?)
        if let declaredKey = sheet.declaredKey {
            keyInfo = parseKeyModeAndFifths(declaredKey)
        } else {
            keyInfo = (fifths: keySignatureToFifths(sheet.keySignature.description), mode: nil)
        }
        let modeTag = keyInfo.mode != nil ? "\n            <mode>\(keyInfo.mode!)</mode>" : ""
        return """
                  <attributes>
                    <divisions>\(divisions)</divisions>
                    <key>
                      <fifths>\(keyInfo.fifths)</fifths>\(modeTag)
                    </key>
                    <time>
                      <beats>\(sheet.beat.count)</beats>
                      <beat-type>\(sheet.beat.noteValue)</beat-type>
                    </time>
            \(generateClefXML(instrument: instrument, sheet: sheet))
                  </attributes>
                  <direction placement="above">
                    <direction-type>
                      <metronome>
                        <beat-unit>\(initialMetronome.beatUnit)</beat-unit>\(dotTag)
                        <per-minute>\(initialMetronome.perMinute)</per-minute>
                      </metronome>
                    </direction-type>
                    <sound tempo="\(Int(speed))"/>
                  </direction>

            """
    }

    private static func generateNoteXML(
        note: Note,
        duration: Int,
        divisions: Int,
        keyOffset: Int,
        tieStart: Bool = false,
        tieStop: Bool = false,
        accidentalText: String? = nil
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
        xml += generateDurationElementsXML(
            duration: duration, divisions: divisions, accidentalText: accidentalText)
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

    private static func generateChordXML(
        chord: ChordSymbol, duration: Int, divisions: Int, keyOffset: Int
    ) -> String {
        // Output chord harmony symbol & note representation
        let spelledRoot = PitchMapping.spell(chordRoot: chord.root, keyOffset: keyOffset)
        let rootStep = spelledRoot.step
        let rootAlter = spelledRoot.alter

        let kindText = chord.description
        let kindValue = chord.quality.musicXMLKindValue

        var xml = """
                  <harmony>
                    <root>
                      <root-step>\(escapeXML(rootStep))</root-step>

            """
        if rootAlter != 0 {
            xml += "          <root-alter>\(rootAlter)</root-alter>\n"
        }
        xml += "        </root>\n"
        xml += "        <kind text=\"\(escapeXML(kindText))\">\(kindValue)</kind>\n"

        if let bass = chord.bass {
            let spelledBass = PitchMapping.spell(chordRoot: bass, keyOffset: keyOffset)
            let bassStep = spelledBass.step
            let bassAlter = spelledBass.alter
            xml += """
                        <bass>
                          <bass-step>\(escapeXML(bassStep))</bass-step>

                """
            if bassAlter != 0 {
                xml += "          <bass-alter>\(bassAlter)</bass-alter>\n"
            }
            xml += "        </bass>\n"
        }

        xml += """
                  </harmony>
                  <note>
                    <rest/>
                    <duration>\(duration)</duration>

            """
        xml += generateDurationElementsXML(duration: duration, divisions: divisions)
        xml += "      </note>\n\n"
        return xml
    }

    // MARK: - Musical Conversion Helpers

    private static func pitchToStepAlterOctave(note: Note, keyOffset: Int) -> (
        step: String, alter: Int, octave: Int
    ) {
        let degree = note.degree.rawValue
        guard (1...7).contains(degree) else { return ("C", 0, 4) }
        let spelled = PitchMapping.spell(note: note, keyOffset: keyOffset)
        return (spelled.step, spelled.alter, spelled.octave)
    }

    private static func keySignatureToFifths(_ key: String) -> Int {
        PitchMapping.keySignatureToFifths(key)
    }

    public static func parseKeyModeAndFifths(_ key: String) -> (fifths: Int, mode: String?) {
        PitchMapping.parseKeyModeAndFifths(key)
    }

    private static func escapeXML(_ string: String) -> String {
        return
            string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private extension ChordQuality {
    var musicXMLKindValue: String {
        switch self {
        case .major: "major"
        case .minor: "minor"
        case .dominant7: "dominant"
        case .major7: "major-seventh"
        case .minor7: "minor-seventh"
        case .diminished: "diminished"
        case .halfDiminished: "half-diminished"
        case .augmented: "augmented"
        case .suspended: "suspended-fourth"
        case .power: "power"
        case .custom: "other"
        }
    }
}

private extension PlaybackDirectiveEvent {
    var musicXMLString: String {
        switch kind {
        case .tempo, .relativeTempo:
            let metronome = TmdMusicXMLGenerator.resolveMetronome(
                beat: state.timeSignature, quarterBPM: state.tempo)
            let dotTag = metronome.isDotted ? "<beat-unit-dot/>" : ""
            return """
                        <direction placement=\"above\">
                          <direction-type><metronome><beat-unit>\(metronome.beatUnit)</beat-unit>\(dotTag)<per-minute>\(metronome.perMinute)</per-minute></metronome></direction-type>
                          <sound tempo=\"\(state.tempo)\"/>
                        </direction>

                """
        case .timeSignature(let beat):
            return """
                        <attributes><time><beats>\(beat.count)</beats><beat-type>\(beat.noteValue)</beat-type></time></attributes>

                """
        case .absoluteKey(let key):
            return
                "        <attributes><key><fifths>\(PitchMapping.keySignatureToFifths(key))</fifths></key></attributes>\n"
        case .explicitKey(let key):
            let parsed = TmdMusicXMLGenerator.parseKeyModeAndFifths(key)
            let modeTag = parsed.mode != nil ? "<mode>\(parsed.mode!)</mode>" : ""
            return
                "        <attributes><key><fifths>\(parsed.fifths)</fifths>\(modeTag)</key></attributes>\n"
        case .dynamics(let mark):
            return """
                    <direction placement="below">
                      <direction-type>
                        <dynamics>
                          <\(mark.rawValue)/>
                        </dynamics>
                      </direction-type>
                    </direction>

                """
        case .relativeKey:
            let fifths = TmdMusicXMLGenerator.semitoneOffsetToFifths(state.keyOffset)
            return "        <attributes><key><fifths>\(fifths)</fifths></key></attributes>\n"
        case .fixedPitch:
            return "        <attributes><key><fifths>0</fifths></key></attributes>\n"
        }
    }
}

