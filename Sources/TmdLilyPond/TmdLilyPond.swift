import Foundation
import TmdSwift

/// LilyPond score generator for TMD Sheets.
///
/// Exports the Sheet AST into LilyPond (`.ly`) source files, which can be compiled by the
/// `lilypond` tool into publication-quality engraving PDFs, SVGs, or PNGs.
public struct TMDLilyPondGenerator {

    /// Generates LilyPond `.ly` file content from a Sheet.
    public static func generateLilyPond(from sheet: Sheet) -> String {
        let composer = sheet.metadata["composer"] ?? "TMD"
        var ly = """
        \\version "2.24.0"

        \\header {
          title = "\(escapeLilyPond(sheet.name.isEmpty ? "Untitled" : sheet.name))"
          composer = "\(escapeLilyPond(composer))"
          tagline = "Engraved by TmdSwift LilyPond Exporter"
        }

        \\paper {
          indent = 1.5\\cm
          short-indent = 0.5\\cm
        }

        global = {
          \\time \(sheet.beat.count)/\(sheet.beat.noteValue)
          \\tempo 4 = \(Int(sheet.speed > 0 ? sheet.speed : 120))
          \\key \(lilyPondKey(sheet.keySignature.description))
        }

        """

        let instruments = sheet.distinctInstruments()

        var identifierMap: [String: String] = [:]
        var usedNames: Set<String> = []
        for (idx, inst) in instruments.enumerated() {
            var name = sanitizeIdentifier(inst, index: idx)
            if usedNames.contains(name) {
                let numberWords = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
                let suffix = idx < 10 ? numberWords[idx] : "N\(idx)"
                name += suffix
            }
            usedNames.insert(name)
            identifierMap[inst] = name
        }

        // Generate track music definitions for each instrument
        for inst in instruments {
            let varName = identifierMap[inst] ?? "Track"
            let isDrum = paragraphsContainPercussion(sheet.paragraphs, instrument: inst)
            ly += "\(varName) = \(isDrum ? "\\drummode " : ""){\n"
            ly += "  \\global\n"
            ly += generateTrackMusic(instrument: inst, sheet: sheet, percussion: isDrum)
            ly += "}\n\n"
        }

        // Score layout block
        ly += "\\score {\n"
        ly += "  <<\n"
        for inst in instruments {
            let varName = identifierMap[inst] ?? "Track"
            let isDrum = paragraphsContainPercussion(sheet.paragraphs, instrument: inst)
            let staffType = isDrum ? "DrumStaff" : "Staff"
            ly += """
                \\new \(staffType) = "\(escapeLilyPond(inst))" \\with {
                  instrumentName = "\(escapeLilyPond(inst))"
                  shortInstrumentName = "\(escapeLilyPond(inst.prefix(3).description))"
                } {
                  \\\(varName)
                }

            """
        }
        ly += "  >>\n"
        ly += "  \\layout { }\n"
        ly += "  \\midi { }\n"
        ly += "}\n"

        return ly
    }

    private static func generateTrackMusic(
        instrument: String,
        sheet: Sheet,
        percussion: Bool
    ) -> String {
        let measures = TMDMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        var result = "  "

        for measure in measures {
            for directive in measure.directives {
                result += formatDirective(directive)
            }
            for event in measure.events {
                result += formatMeasureEvent(event, percussion: percussion)
                result += " "
            }
            result += "|\n  "
        }
        return result.trimmingCharacters(in: .whitespaces) + "\n"
    }

    private static func formatDirective(_ directive: PlaybackDirectiveEvent) -> String {
        switch directive.kind {
        case .tempo, .relativeTempo: "\\tempo 4 = \(Int(directive.state.tempo.rounded())) "
        case .timeSignature(let beat): "\\time \(beat.count)/\(beat.noteValue) "
        case .absoluteKey(let key): "\\key \(lilyPondKey(key)) "
        case .relativeKey: "% TMD relative key modulation "
        }
    }

    private static func formatMeasureEvent(_ event: MeasureEvent, percussion: Bool) -> String {
        let decomposed = NotationDuration.decompose(quarterNotes: event.duration)
        switch event.content {
        case .note(let note):
            let pitch = noteToLilyPondPitch(note, keyOffset: event.state.keyOffset)
            var parts: [String] = []
            for (idx, d) in decomposed.enumerated() {
                let durStr = "\(d.baseDenominator)\(d.isDotted ? "." : "")"
                let isLast = (idx == decomposed.count - 1)
                let tie = (isLast ? (event.tieStart ? "~" : "") : "~")
                parts.append("\(pitch)\(durStr)\(tie)")
            }
            return parts.joined(separator: " ")
        case .chord(let chord):
            let pitches = chordToLilyPondPitches(chord, keyOffset: event.state.keyOffset)
            let chordBody = "<\(pitches.joined(separator: " "))>"
            var parts: [String] = []
            for (idx, d) in decomposed.enumerated() {
                let durStr = "\(d.baseDenominator)\(d.isDotted ? "." : "")"
                let isLast = (idx == decomposed.count - 1)
                let tie = (isLast ? (event.tieStart ? "~" : "") : "~")
                parts.append("\(chordBody)\(durStr)\(tie)")
            }
            return parts.joined(separator: " ")
        case .rest:
            return decomposed.map { d in
                "r\(d.baseDenominator)\(d.isDotted ? "." : "")"
            }.joined(separator: " ")
        case .percussion(let pattern):
            let names = pattern.compactMap { ["X": "hh", "x": "hh", "T": "toml", "t": "toml", "S": "sn", "s": "sn"][$0] }
            if names.isEmpty {
                return decomposed.map { d in "r\(d.baseDenominator)\(d.isDotted ? "." : "")" }.joined(separator: " ")
            }
            return decomposed.map { d in
                let durStr = "\(d.baseDenominator)\(d.isDotted ? "." : "")"
                return names.map { "\($0)\(durStr)" }.joined(separator: " ")
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

    // MARK: - Pitch & Duration Helpers

    private static func formatDuration(noteLength: Int, spanCount: Int) -> String {
        guard spanCount > 0, noteLength > 0, noteLength.isMultiple(of: spanCount) else {
            return "\(noteLength)"
        }
        return "\(noteLength / spanCount)"
    }

    private static func noteToLilyPondPitch(_ note: Note, keyOffset: Int) -> String {
        let degree = note.degree.rawValue
        guard (1...7).contains(degree) else { return "c'" }
        var midiPitch = 60 + keyOffset + note.degree.semitoneOffset

        switch note.accidental {
        case .sharp: midiPitch += 1
        case .flat: midiPitch -= 1
        case .natural: break
        }
        midiPitch += note.octave * 12

        return midiPitchToLilyPond(midiPitch)
    }

    private static func chordToLilyPondPitches(_ chord: ChordSymbol, keyOffset: Int) -> [String] {
        let root: Int
        if chord.root.isScaleDegree {
            root = 60 + keyOffset + chord.root.degree.semitoneOffset
                + chord.root.accidental.semitoneOffset
        } else {
            root = 48 + chord.root.semitoneOffset
        }
        return chord.quality.semitoneIntervals.map { midiPitchToLilyPond(root + $0) }
    }

    private static func midiPitchToLilyPond(_ pitch: Int) -> String {
        // LilyPond base: c' is Middle C (MIDI 60)
        let semitone = ((pitch % 12) + 12) % 12
        let octave = (pitch / 12) - 1 // Middle C is octave 4 in standard convention, octave 3 in LilyPond reference

        var name = PitchMapping.lilyPondNames[semitone]
        if octave > 3 {
            name += String(repeating: "'", count: octave - 3)
        } else if octave < 3 {
            name += String(repeating: ",", count: 3 - octave)
        }
        return name
    }

    private static func lilyPondKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "c \\major" }
        var pitch = String(first).lowercased()
        if trimmed.contains("'") || trimmed.contains("#") {
            pitch += "is"
        } else if trimmed.contains(",") || trimmed.contains("b") {
            pitch += "es"
        }
        return "\(pitch) \\major"
    }

    private static func sanitizeIdentifier(_ string: String, index: Int) -> String {
        let numberWords = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        var converted = ""
        for ch in string {
            if ch.isLetter {
                converted.append(ch)
            } else if let digit = ch.wholeNumberValue, (0...9).contains(digit) {
                converted.append(numberWords[digit])
            }
        }
        return converted.isEmpty ? "Track\(index + 1)" : converted
    }

    private static func escapeLilyPond(_ string: String) -> String {
        return string.replacingOccurrences(of: "\"", with: "\\\"")
    }
}
