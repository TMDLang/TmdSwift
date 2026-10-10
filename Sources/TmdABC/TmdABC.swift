import Foundation
import TmdSwift

/// ABC Notation exporter for TMD Sheets.
///
/// Converts a Sheet into standard ABC Notation (v2.1+), widely supported by web players
/// (e.g. abcjs), Markdown previewers, and traditional tune archives.
public struct TmdABCGenerator {

    /// Generates ABC notation string from a Sheet.
    public static func generateABC(from inputSheet: Sheet) -> String {
        let (sheet, instruments) = inputSheet.preparedForExport()
        var abc = ""

        // Header fields
        abc += "X:1\n"
        abc += "T:\(sheet.name.isEmpty ? "Untitled" : sheet.name)\n"
        abc += "C:\(sheet.metadata["composer"] ?? "TMD (Chen, Chih-Han / aguai)")\n"
        abc += "M:\(sheet.beat.count)/\(sheet.beat.noteValue)\n"
        abc += "L:1/16\n"  // Base unit length = 16th note for high rhythm precision
        let speed = sheet.speed > 0 ? sheet.speed : 120
        let tempoField = resolveTempo(beat: sheet.beat, quarterBPM: speed)
        abc += "\(tempoField)\n"
        let effectiveKey = sheet.declaredKey ?? sheet.keySignature.description
        abc += "K:\(abcKey(effectiveKey))\n\n"

        // Output Voice headers
        for (idx, inst) in instruments.enumerated() {
            let vId = "V\(idx + 1)"
            abc += "V:\(vId) name=\"\(inst)\" snm=\"\(inst.prefix(3))\"\n"
        }
        abc += "\n"

        // Generate lines per instrument track
        for (idx, inst) in instruments.enumerated() {
            let vId = "V\(idx + 1)"
            abc += "[V:\(vId)]\n"
            if sheet.containsPercussionUnits(forInstrument: inst) {
                abc += "%%MIDI channel 10\n"
            }
            abc += generateTrackMusic(instrument: inst, sheet: sheet)
            abc += "\n\n"
        }

        return abc
    }

    private static func generateTrackMusic(
        instrument: String,
        sheet: Sheet
    ) -> String {
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        var result = ""
        let initialKey = sheet.declaredKey ?? sheet.keySignature.description
        var currentKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: initialKey)

        for (mIdx, measure) in measures.enumerated() {
            var measureStepAlters: [Int: [Int]] = [:]
            for directive in measure.directives {
                switch directive.kind {
                case .absoluteKey(let key), .explicitKey(let key):
                    currentKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: key)
                    measureStepAlters.removeAll()
                case .relativeKey:
                    let key = PitchMapping.tonicScaleInfo(forKeyOffset: directive.state.keyOffset)
                        .name
                    currentKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: key)
                    measureStepAlters.removeAll()
                case .fixedPitch:
                    currentKeyStepAlters = [0, 0, 0, 0, 0, 0, 0]
                    measureStepAlters.removeAll()
                default:
                    break
                }
                result += formatDirective(directive)
            }
            for group in measure.simultaneousEventGroups {
                result += formatMeasureEventGroup(
                    group,
                    defaultKeyStepAlters: currentKeyStepAlters,
                    measureStepAlters: &measureStepAlters
                )
                result += " "
            }
            result += "|"
            if (mIdx + 1) % 4 == 0 && mIdx < measures.count - 1 {
                result += "\n"
            } else {
                result += " "
            }
        }
        return result.trimmingCharacters(in: .whitespaces) + "\n"
    }

    public static func resolveTempo(beat: Beat, quarterBPM: Double) -> String {
        // Compound meter: denominator is 8 and numerator is a multiple of 3 (> 3, e.g. 6/8, 9/8, 12/8)
        if beat.noteValue == 8 && beat.count > 3 && beat.count % 3 == 0 {
            // Beat unit is a dotted-quarter note (in ABC represented as 3/8)
            let bpm = Int((quarterBPM / 1.5).rounded())
            return "Q:3/8=\(bpm)"
        }
        switch beat.noteValue {
        case 2:
            let bpm = Int((quarterBPM / 2.0).rounded())
            return "Q:1/2=\(bpm)"
        case 8:
            let bpm = Int((quarterBPM * 2.0).rounded())
            return "Q:1/8=\(bpm)"
        case 16:
            let bpm = Int((quarterBPM * 4.0).rounded())
            return "Q:1/16=\(bpm)"
        default:
            let bpm = Int(quarterBPM.rounded())
            return "Q:1/4=\(bpm)"
        }
    }

    private static func formatDirective(_ directive: PlaybackDirectiveEvent) -> String {
        directive.abcString
    }

    private static func formatMeasureEventGroup(
        _ group: [MeasureEvent],
        defaultKeyStepAlters: [Int],
        measureStepAlters: inout [Int: [Int]]
    ) -> String {
        guard let first = group.first else { return "" }
        let noteEvents = group.compactMap { ev -> (Note, MeasureEvent)? in
            if case .note(let n) = ev.content { return (n, ev) }
            return nil
        }
        if noteEvents.count > 1 {
            let multiplier = max(1, Int((first.duration * 4).rounded()))
            let suffix = multiplier > 1 ? "\(multiplier)" : ""
            let tie = noteEvents.contains { $0.1.tieStart } ? "-" : ""
            let pitches = noteEvents.map { note, ev in
                noteToABCPitch(
                    note,
                    keyOffset: ev.state.keyOffset,
                    defaultKeyStepAlters: defaultKeyStepAlters,
                    measureStepAlters: &measureStepAlters
                )
            }
            return "[\(pitches.joined())]\(suffix)\(tie)"
        }
        return formatMeasureEvent(
            first,
            defaultKeyStepAlters: defaultKeyStepAlters,
            measureStepAlters: &measureStepAlters
        )
    }

    private static func formatMeasureEvent(
        _ event: MeasureEvent,
        defaultKeyStepAlters: [Int],
        measureStepAlters: inout [Int: [Int]]
    ) -> String {
        let multiplier = max(1, Int((event.duration * 4).rounded()))
        let suffix = multiplier > 1 ? "\(multiplier)" : ""
        switch event.content {
        case .note(let note):
            let tie = event.tieStart ? "-" : ""
            let pitch = noteToABCPitch(
                note,
                keyOffset: event.state.keyOffset,
                defaultKeyStepAlters: defaultKeyStepAlters,
                measureStepAlters: &measureStepAlters
            )
            return "\(pitch)\(suffix)\(tie)"
        case .chord(let chord):
            return "\"\(chord.description)\"z\(suffix)"
        case .rest:
            return "z\(suffix)"
        case .percussion(let pattern):
            let pitches = PercussionStroke.parse(pattern: pattern).compactMap(\.abcPitch)
            if pitches.isEmpty { return "z\(suffix)" }
            let count = pitches.count
            let base = multiplier / count
            let remainder = multiplier % count
            return pitches.enumerated().map { i, pitch in
                let dur = base + (i < remainder ? 1 : 0)
                let s = dur > 1 ? "\(dur)" : ""
                return "\(pitch)\(s)"
            }.joined(separator: " ")
        }
    }

    // MARK: - Pitch Helpers

    private static func noteToABCPitch(
        _ note: Note,
        keyOffset: Int,
        defaultKeyStepAlters: [Int],
        measureStepAlters: inout [Int: [Int]]
    ) -> String {
        let spelled = PitchMapping.spell(note: note, keyOffset: keyOffset)
        var octaveAlters = measureStepAlters[spelled.octave] ?? defaultKeyStepAlters
        let expectedAlter = octaveAlters[spelled.stepIndex]

        let prefix: String
        if spelled.alter == expectedAlter {
            prefix = ""
        } else {
            octaveAlters[spelled.stepIndex] = spelled.alter
            measureStepAlters[spelled.octave] = octaveAlters
            if spelled.alter == 0 {
                prefix = "="
            } else if spelled.alter == 1 {
                prefix = "^"
            } else if spelled.alter == -1 {
                prefix = "_"
            } else if spelled.alter >= 2 {
                prefix = "^^"
            } else if spelled.alter <= -2 {
                prefix = "__"
            } else {
                prefix = ""
            }
        }

        let stepUpper = PitchMapping.stepNames[spelled.stepIndex]
        let stepLower = PitchMapping.stepLowerNames[spelled.stepIndex]
        let octave = spelled.octave

        let letter: String
        if octave >= 5 {
            let apostrophes = String(repeating: "'", count: octave - 5)
            letter = "\(stepLower)\(apostrophes)"
        } else if octave == 4 {
            letter = stepLower
        } else if octave == 3 {
            letter = stepUpper
        } else {
            let commas = String(repeating: ",", count: 3 - octave)
            letter = "\(stepUpper)\(commas)"
        }

        return "\(prefix)\(letter)"
    }

    fileprivate static func abcKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "C" }
        var isMinor = false
        var root = trimmed
        if root.hasSuffix("m") && !root.hasSuffix("maj") {
            isMinor = true
            root.removeLast()
        } else if root.lowercased().hasSuffix("minor") {
            isMinor = true
            root = String(root.dropLast(5)).trimmingCharacters(in: .whitespaces)
        }
        let keySig = KeySignature(string: root)
        let normalized = ((keySig.semitoneOffset % 12) + 12) % 12
        var majorName = PitchMapping.tonicScaleInfo(forKeyOffset: normalized).name
        if root.contains("#") && majorName.contains("b") {
            let sharps = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            majorName = sharps[normalized]
        }
        return isMinor ? "\(majorName)m" : majorName
    }
}

private extension PlaybackDirectiveEvent {
    var abcString: String {
        switch kind {
        case .tempo, .relativeTempo:
            let cmd = TmdABCGenerator.resolveTempo(
                beat: state.timeSignature, quarterBPM: state.tempo)
            return "\(cmd) "
        case .timeSignature(let beat):
            return "M:\(beat.count)/\(beat.noteValue) "
        case .absoluteKey(let key), .explicitKey(let key):
            return "K:\(TmdABCGenerator.abcKey(key)) "
        case .dynamics(let mark):
            return "!\(mark.rawValue)! "
        case .relativeKey:
            let key = PitchMapping.tonicScaleInfo(forKeyOffset: state.keyOffset).name
            return "K:\(key) "
        case .fixedPitch:
            return "K:C "
        }
    }
}
