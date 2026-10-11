import Foundation
import TmdSwift

/// MusicXML generator for TMD Sheets.
///
/// Exports the Sheet AST into W3C MusicXML (Partwise) format for use with notation software
/// such as MuseScore, Finale, Sibelius, Dorico, or web renderers like OpenSheetMusicDisplay.
public struct TmdMusicXMLGenerator {

    /// Generates MusicXML UTF-8 string from a Sheet.
    public static func generateMusicXML(from inputSheet: Sheet) -> String {
        let (sheet, instruments) = inputSheet.preparedForExport()
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

        let partMeasures: [(instrument: String, measures: [Measure])] = instruments.map { inst in
            (instrument: inst, measures: TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: inst))
        }
        let divisions = resolveDivisions(for: partMeasures.map(\.measures))

        // Generate <part> for each instrument
        for (idx, entry) in partMeasures.enumerated() {
            let partID = "P\(idx + 1)"
            xml += "  <part id=\"\(partID)\">\n"
            xml += generatePartMeasures(
                instrument: entry.instrument,
                measures: entry.measures,
                sheet: sheet,
                divisions: divisions
            )
            xml += "  </part>\n"
        }

        xml += "</score-partwise>\n"
        return xml
    }

    private static func resolveDivisions(for allPartMeasures: [[Measure]]) -> Int {
        var divisions = 48
        var needsFactor5 = false
        var needsFactor7 = false
        for measures in allPartMeasures {
            for measure in measures {
                for event in measure.events {
                    let q = event.duration
                    let in48 = q * 48.0
                    if abs(in48.rounded() - in48) > 1e-3 {
                        let in240 = q * 240.0
                        if abs(in240.rounded() - in240) < 1e-3 {
                            needsFactor5 = true
                        }
                        let in336 = q * 336.0
                        if abs(in336.rounded() - in336) < 1e-3 {
                            needsFactor7 = true
                        }
                    }
                }
            }
        }
        if needsFactor5 { divisions *= 5 }
        if needsFactor7 { divisions *= 7 }
        return divisions
    }

    private static func generatePartMeasures(
        instrument: String,
        measures: [Measure],
        sheet: Sheet,
        divisions: Int
    ) -> String {
        var xml = ""

        let initialKey =
            sheet.declaredKey
            ?? PitchMapping.tonicScaleInfo(forKeyOffset: sheet.keySignature.semitoneOffset).name
        var defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: initialKey)
        var currentBeat = measures.first?.timeSignature ?? sheet.beat
        var currentLocalBeat: Beat? = nil

        for measure in measures {
            var content = ""
            var measureStepAlters: [Int: [Int]] = [:]
            if measure.index == 0 {
                currentBeat = measure.timeSignature
                content += generateAttributesXML(
                    sheet: sheet,
                    instrument: instrument,
                    divisions: divisions,
                    initialBeat: measure.timeSignature
                )
            } else if measure.timeSignature != currentBeat {
                currentBeat = measure.timeSignature
                content += """
                            <attributes><time><beats>\(currentBeat.count)</beats><beat-type>\(currentBeat.noteValue)</beat-type></time></attributes>

                    """
            }

            for directive in measure.directives {
                switch directive.kind {
                case .timeSignature:
                    // Handled canonically per measure via measure.timeSignature above
                    continue
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

            if let soundingEvent = measure.events.first(where: { $0.content.isSounding }) {
                let localBeat = soundingEvent.state.timeSignature
                if localBeat != measure.timeSignature {
                    if currentLocalBeat != localBeat {
                        content += """
                                <direction placement="above">
                                  <direction-type>
                                    <words>[\(localBeat.count)/\(localBeat.noteValue)]</words>
                                  </direction-type>
                                </direction>

                            """
                        currentLocalBeat = localBeat
                    }
                } else {
                    currentLocalBeat = nil
                }
            } else {
                currentLocalBeat = nil
            }

            let expectedMeasureDuration = max(
                1, Int((measure.nominalDuration * Double(divisions)).rounded()))
            let eventGroups = measure.simultaneousEventGroups
            var durations: [Int] = eventGroups.enumerated().map { idx, group in
                let nonChordEvents = group.filter {
                    if case .chord = $0.content { return false }
                    return true
                }
                let pool = nonChordEvents.isEmpty ? group : nonChordEvents
                let poolDur = pool.map(\.duration).max() ?? 0
                let startOffset = group.first?.startOffset ?? 0
                let nextOffset =
                    (idx + 1 < eventGroups.count)
                    ? (eventGroups[idx + 1].first?.startOffset ?? measure.nominalDuration)
                    : measure.nominalDuration
                let maxSpan = max(0.0, nextOffset - startOffset)
                let groupDur = maxSpan > 1e-6 ? min(poolDur, maxSpan) : poolDur
                return max(1, Int((groupDur * Double(divisions)).rounded()))
            }
            // Balance durations to conserve measure nominal duration
            let totalDur = durations.reduce(0, +)
            let diff = expectedMeasureDuration - totalDur
            if diff != 0 && !durations.isEmpty {
                let lastIdx = durations.count - 1
                durations[lastIdx] = max(1, durations[lastIdx] + diff)
            }

            for (idx, group) in eventGroups.enumerated() {
                let duration = durations[idx]
                let hasNonChordInGroup = group.contains {
                    if case .chord = $0.content { return false }
                    return true
                }
                let chunks = decomposeDivisions(duration, divisions: divisions)
                for (chunkIdx, chunkDur) in chunks.enumerated() {
                    let isFirstChunk = (chunkIdx == 0)
                    let isLastChunk = (chunkIdx == chunks.count - 1)
                    var emittedNoteInGroup = false
                    for event in group {
                        switch event.content {
                        case .note(let note):
                            var accidentalText: String? = nil
                            if isFirstChunk {
                                let spelled = PitchMapping.spell(
                                    note: note, keyOffset: event.state.keyOffset)
                                var octaveAlters =
                                    measureStepAlters[spelled.octave] ?? defaultKeyStepAlters
                                let expectedAlter = octaveAlters[spelled.stepIndex]
                                if spelled.alter != expectedAlter && !event.tieStop {
                                    octaveAlters[spelled.stepIndex] = spelled.alter
                                    measureStepAlters[spelled.octave] = octaveAlters
                                    accidentalText = musicXMLAccidentalName(forAlter: spelled.alter)
                                }
                            }
                            let subTieStop = isFirstChunk ? event.tieStop : true
                            let subTieStart = isLastChunk ? event.tieStart : true
                            content += generateNoteXML(
                                note: note,
                                duration: chunkDur,
                                divisions: divisions,
                                keyOffset: event.state.keyOffset,
                                tieStart: subTieStart,
                                tieStop: subTieStop,
                                accidentalText: accidentalText,
                                isChordContinuation: emittedNoteInGroup
                            )
                            emittedNoteInGroup = true
                        case .chord(let chord):
                            if isFirstChunk {
                                content += generateChordXML(
                                    chord: chord,
                                    duration: chunkDur,
                                    divisions: divisions,
                                    keyOffset: event.state.keyOffset,
                                    emitRestNote: !hasNonChordInGroup
                                )
                            } else if !hasNonChordInGroup {
                                content += generateRestXML(duration: chunkDur, divisions: divisions)
                            }
                        case .rest:
                            content += generateRestXML(duration: chunkDur, divisions: divisions)
                        case .percussion(let pattern):
                            if isFirstChunk {
                                content += generatePercussionXML(
                                    pattern: pattern, duration: duration, divisions: divisions)
                            }
                        }
                    }
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

    private static func decomposeDivisions(_ totalDivisions: Int, divisions: Int) -> [Int] {
        let total = max(1, totalDivisions)
        if durationInfo(duration: total, divisions: divisions) != nil {
            return [total]
        }
        let d = divisions
        let standardAtoms: [Int] = [
            4 * d,
            3 * d,
            2 * d,
            d + d / 2,
            d,
            d / 2 + d / 4,
            d / 2,
            d / 4 + d / 8,
            d / 4,
            d / 8,
            d / 16,
        ].filter { $0 > 0 }

        var remaining = total
        var result: [Int] = []
        while remaining > 0 {
            if durationInfo(duration: remaining, divisions: divisions) != nil {
                result.append(remaining)
                break
            }
            if let match = standardAtoms.first(where: { $0 <= remaining }) {
                result.append(match)
                remaining -= match
            } else {
                result.append(remaining)
                break
            }
        }
        return result.isEmpty ? [total] : result
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

        let normalTypes: [(dur: Int, type: String)] = [
            (4 * d, "whole"),
            (2 * d, "half"),
            (d, "quarter"),
            (d / 2, "eighth"),
            (d / 4, "16th"),
            (d / 8, "32nd"),
        ]

        // Triplet (3:2) durations: duration = (normalDur * 2) / 3
        if d.isMultiple(of: 3) {
            for item in normalTypes where (item.dur * 2).isMultiple(of: 3) {
                if duration == (item.dur * 2) / 3 {
                    return NoteDurationInfo(type: item.type, dots: 0, timeModification: (3, 2))
                }
            }
        }

        // Quintuplet (5:4) durations: duration = (normalDur * 4) / 5
        if d.isMultiple(of: 5) {
            for item in normalTypes where (item.dur * 4).isMultiple(of: 5) {
                if duration == (item.dur * 4) / 5 {
                    return NoteDurationInfo(type: item.type, dots: 0, timeModification: (5, 4))
                }
            }
        }

        // Septuplet (7:4) durations: duration = (normalDur * 4) / 7
        if d.isMultiple(of: 7) {
            for item in normalTypes where (item.dur * 4).isMultiple(of: 7) {
                if duration == (item.dur * 4) / 7 {
                    return NoteDurationInfo(type: item.type, dots: 0, timeModification: (7, 4))
                }
            }
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
        let info =
            durationInfo(duration: duration, divisions: divisions)
            ?? NoteDurationInfo(type: "64th", dots: 0, timeModification: nil)
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

    private static func generateClefXML(instrument: String, sheet: Sheet) -> String {
        if sheet.isPercussionTrack(instrument: instrument) {
            return """
                        <clef>
                          <sign>percussion</sign>
                        </clef>
                """
        } else if Sheet.isBassClefInstrument(instrument) {
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
        let m = beat.metronomeTempo(forQuarterBPM: quarterBPM)
        return (m.beatUnit, m.isDotted, m.perMinute)
    }

    private static func generatePercussionXML(pattern: String, duration: Int, divisions: Int)
        -> String
    {
        let strokes = PercussionStroke.parse(pattern: pattern)
        if strokes.isEmpty {
            return decomposeDivisions(duration, divisions: divisions)
                .map { generateRestXML(duration: $0, divisions: divisions) }
                .joined()
        }
        let count = strokes.count
        let base = duration / count
        let remainder = duration % count
        var xml = ""
        for (i, stroke) in strokes.enumerated() {
            let pos = stroke.unpitchedDisplayPosition
            let noteDur = base + (i < remainder ? 1 : 0)
            for chunkDur in decomposeDivisions(noteDur, divisions: divisions) {
                xml += """
                            <note>
                              <unpitched>
                                <display-step>\(pos.step)</display-step>
                                <display-octave>\(pos.octave)</display-octave>
                              </unpitched>
                              <duration>\(chunkDur)</duration>

                    """
                xml += generateDurationElementsXML(duration: chunkDur, divisions: divisions)
                xml += "        </note>\n\n"
            }
        }
        return xml
    }

    private static func generateAttributesXML(
        sheet: Sheet,
        instrument: String,
        divisions: Int,
        initialBeat: Beat? = nil
    ) -> String {
        let effectiveBeat = initialBeat ?? sheet.beat
        let speed = sheet.speed > 0 ? sheet.speed : 120
        let initialMetronome = resolveMetronome(beat: effectiveBeat, quarterBPM: speed)
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
                      <beats>\(effectiveBeat.count)</beats>
                      <beat-type>\(effectiveBeat.noteValue)</beat-type>
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
        accidentalText: String? = nil,
        isChordContinuation: Bool = false
    ) -> String {
        let (step, alter, octave) = pitchToStepAlterOctave(note: note, keyOffset: keyOffset)
        var xml = "        <note>\n"
        if isChordContinuation {
            xml += "          <chord/>\n"
        }
        xml += """
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
        chord: ChordSymbol,
        duration: Int,
        divisions: Int,
        keyOffset: Int,
        emitRestNote: Bool = true
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

        xml += "      </harmony>\n"
        if emitRestNote {
            xml += """
                      <note>
                        <rest/>
                        <duration>\(duration)</duration>

                """
            xml += generateDurationElementsXML(duration: duration, divisions: divisions)
            xml += "      </note>\n\n"
        }
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

