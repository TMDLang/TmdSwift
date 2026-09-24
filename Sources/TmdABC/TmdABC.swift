import Foundation
import TmdSwift

/// ABC Notation exporter for TMD Sheets.
///
/// Converts a Sheet into standard ABC Notation (v2.1+), widely supported by web players
/// (e.g. abcjs), Markdown previewers, and traditional tune archives.
public struct TMDABCGenerator {

    /// Generates ABC notation string from a Sheet.
    public static func generateABC(from inputSheet: Sheet) -> String {
        let sheet = TMDMacroEvaluator.expand(inputSheet)
        var abc = ""

        // Header fields
        abc += "X:1\n"
        abc += "T:\(sheet.name.isEmpty ? "Untitled" : sheet.name)\n"
        abc += "C:\(sheet.metadata["composer"] ?? "TMD (Chen, Chih-Han / aguai)")\n"
        abc += "M:\(sheet.beat.count)/\(sheet.beat.noteValue)\n"
        abc += "L:1/16\n" // Base unit length = 16th note for high rhythm precision
        abc += "Q:1/4=\(Int(sheet.speed > 0 ? sheet.speed : 120))\n"
        abc += "K:\(abcKey(sheet.keySignature.description))\n\n"

        let instruments = sheet.distinctInstruments()

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
            if paragraphsContainPercussion(sheet.paragraphs, instrument: inst) {
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
        let measures = TMDMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        var result = ""
        for (mIdx, measure) in measures.enumerated() {
            for directive in measure.directives {
                result += formatDirective(directive)
            }
            for event in measure.events {
                result += formatMeasureEvent(event)
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

    private static func formatDirective(_ directive: PlaybackDirectiveEvent) -> String {
        switch directive.kind {
        case .tempo, .relativeTempo:
            return "Q:1/4=\(Int(directive.state.tempo.rounded())) "
        case .timeSignature(let beat):
            return "M:\(beat.count)/\(beat.noteValue) "
        case .absoluteKey(let key):
            return "K:\(abcKey(key)) "
        case .relativeKey:
            let key = keyInfo(for: directive.state.keyOffset).name
            return "K:\(key) "
        case .fixedPitch:
            return "K:C "
        }
    }

    private static func formatMeasureEvent(_ event: MeasureEvent) -> String {
        let multiplier = max(1, Int((event.duration * 4).rounded()))
        let suffix = multiplier > 1 ? "\(multiplier)" : ""
        switch event.content {
        case .note(let note):
            let tie = event.tieStart ? "-" : ""
            return "\(noteToABCPitch(note, keyOffset: event.state.keyOffset))\(suffix)\(tie)"
        case .chord(let chord):
            return "\"\(chord.description)\"z\(suffix)"
        case .rest:
            return "z\(suffix)"
        case .percussion(let pattern):
            let pitches = pattern.compactMap { ["X": "^F", "x": "^F", "T": "A", "t": "A", "S": "D", "s": "D"][$0] }
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

    private static func paragraphsContainPercussion(_ paragraphs: [Paragraph], instrument: String) -> Bool {
        paragraphs.filter { $0.instrument == instrument }.contains { paragraph in
            paragraph.sections.contains { section in
                section.unitGroups.contains { group in
                    group.units.contains { if case .percussion = $0 { return true }; return false }
                }
            }
        }
    }

    // MARK: - Pitch Helpers

    private struct ABCKeyInfo {
        let name: String
        // Accidental offset (-1, 0, 1) for steps C=0, D=1, E=2, F=3, G=4, A=5, B=6
        let stepAccidentals: [Int]
        // Diatonic step (0..6) for scale degrees 1..7 (index 0..6)
        let degreeSteps: [Int]
    }

    private static func keyInfo(for keyOffset: Int) -> ABCKeyInfo {
        let normalized = ((keyOffset % 12) + 12) % 12
        switch normalized {
        case 0: // C
            return ABCKeyInfo(name: "C", stepAccidentals: [0, 0, 0, 0, 0, 0, 0], degreeSteps: [0, 1, 2, 3, 4, 5, 6])
        case 1: // Db
            return ABCKeyInfo(name: "Db", stepAccidentals: [0, -1, -1, 0, -1, -1, -1], degreeSteps: [1, 2, 3, 4, 5, 6, 0])
        case 2: // D
            return ABCKeyInfo(name: "D", stepAccidentals: [1, 0, 0, 1, 0, 0, 0], degreeSteps: [1, 2, 3, 4, 5, 6, 0])
        case 3: // Eb
            return ABCKeyInfo(name: "Eb", stepAccidentals: [0, 0, -1, 0, 0, -1, -1], degreeSteps: [2, 3, 4, 5, 6, 0, 1])
        case 4: // E
            return ABCKeyInfo(name: "E", stepAccidentals: [1, 1, 0, 1, 1, 0, 0], degreeSteps: [2, 3, 4, 5, 6, 0, 1])
        case 5: // F
            return ABCKeyInfo(name: "F", stepAccidentals: [0, 0, 0, 0, 0, 0, -1], degreeSteps: [3, 4, 5, 6, 0, 1, 2])
        case 6: // F#
            return ABCKeyInfo(name: "F#", stepAccidentals: [1, 1, 1, 1, 1, 1, 0], degreeSteps: [3, 4, 5, 6, 0, 1, 2])
        case 7: // G
            return ABCKeyInfo(name: "G", stepAccidentals: [0, 0, 0, 1, 0, 0, 0], degreeSteps: [4, 5, 6, 0, 1, 2, 3])
        case 8: // Ab
            return ABCKeyInfo(name: "Ab", stepAccidentals: [0, -1, -1, 0, 0, -1, -1], degreeSteps: [5, 6, 0, 1, 2, 3, 4])
        case 9: // A
            return ABCKeyInfo(name: "A", stepAccidentals: [1, 0, 0, 1, 1, 0, 0], degreeSteps: [5, 6, 0, 1, 2, 3, 4])
        case 10: // Bb
            return ABCKeyInfo(name: "Bb", stepAccidentals: [0, 0, -1, 0, 0, 0, -1], degreeSteps: [6, 0, 1, 2, 3, 4, 5])
        case 11: // B
            return ABCKeyInfo(name: "B", stepAccidentals: [1, 1, 0, 1, 1, 1, 0], degreeSteps: [6, 0, 1, 2, 3, 4, 5])
        default:
            return ABCKeyInfo(name: "C", stepAccidentals: [0, 0, 0, 0, 0, 0, 0], degreeSteps: [0, 1, 2, 3, 4, 5, 6])
        }
    }

    private static func noteToABCPitch(_ note: Note, keyOffset: Int) -> String {
        let info = keyInfo(for: keyOffset)
        let degIdx = max(0, min(6, note.degree.rawValue - 1))
        let stepIdx = info.degreeSteps[degIdx]
        let keyAcc = info.stepAccidentals[stepIdx]

        let delta: Int
        switch note.accidental {
        case .sharp: delta = 1
        case .flat: delta = -1
        case .natural: delta = 0
        }

        let noteAlter = keyAcc + delta
        let prefix: String
        if noteAlter == keyAcc {
            prefix = ""
        } else if noteAlter == 0 && keyAcc != 0 {
            prefix = "="
        } else if noteAlter == 1 && keyAcc != 1 {
            prefix = "^"
        } else if noteAlter == -1 && keyAcc != -1 {
            prefix = "_"
        } else if noteAlter >= 2 {
            prefix = "^^"
        } else if noteAlter <= -2 {
            prefix = "__"
        } else {
            prefix = ""
        }

        let stepUpper = ["C", "D", "E", "F", "G", "A", "B"][stepIdx]
        let stepLower = ["c", "d", "e", "f", "g", "a", "b"][stepIdx]

        let midiPitch = 60 + keyOffset + note.degree.semitoneOffset + delta + note.octave * 12
        let octave = (midiPitch / 12) - 1

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

    private static func abcKey(_ key: String) -> String {
        let keySig = KeySignature(string: key)
        return keyInfo(for: keySig.semitoneOffset).name
    }

}
