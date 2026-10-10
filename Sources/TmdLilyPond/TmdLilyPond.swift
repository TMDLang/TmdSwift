import Foundation
import TmdSwift

/// LilyPond score generator for TMD Sheets.
///
/// Exports the Sheet AST into LilyPond (`.ly`) source files, which can be compiled by the
/// `lilypond` tool into publication-quality engraving PDFs, SVGs, or PNGs.
public struct TmdLilyPondGenerator {

    /// Generates LilyPond `.ly` file content from a Sheet.
    public static func generateLilyPond(from inputSheet: Sheet) -> String {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let composer = sheet.metadata["composer"] ?? "TMD"
        let initialTempoCommand = resolveTempo(
            beat: sheet.beat, quarterBPM: sheet.speed > 0 ? sheet.speed : 120)
        let effectiveKey = sheet.declaredKey ?? sheet.keySignature.description
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
              \(initialTempoCommand)
              \\key \(lilyPondKey(effectiveKey))
            }

            """

        let instruments = sheet.distinctInstruments(fallbackToDefault: false)

        var identifierMap: [String: String] = [:]
        var usedNames: Set<String> = []
        for (idx, inst) in instruments.enumerated() {
            var name = sanitizeIdentifier(inst, index: idx)
            if usedNames.contains(name) {
                let numberWords = [
                    "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
                ]
                let suffix = idx < 10 ? numberWords[idx] : "N\(idx)"
                name += suffix
            }
            usedNames.insert(name)
            identifierMap[inst] = name
        }

        // Generate track music definitions for each instrument
        for inst in instruments {
            let varName = identifierMap[inst] ?? "Track"
            let isDrum = paragraphsContainPercussion(sheet.entries, instrument: inst)
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
            let isDrum = paragraphsContainPercussion(sheet.entries, instrument: inst)
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
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        var result = "  "

        for measure in measures {
            for directive in measure.directives {
                result += formatDirective(directive)
            }
            for group in measure.simultaneousEventGroups {
                result += formatMeasureEventGroup(group, percussion: percussion)
                result += " "
            }
            result += "|\n  "
        }
        return result.trimmingCharacters(in: .whitespaces) + "\n"
    }

    public static func resolveTempo(beat: Beat, quarterBPM: Double) -> String {
        // Compound meter: denominator is 8 and numerator is a multiple of 3 (> 3, e.g. 6/8, 9/8, 12/8)
        if beat.noteValue == 8 && beat.count > 3 && beat.count % 3 == 0 {
            // Beat unit is a dotted-quarter note (4.)
            let bpm = Int((quarterBPM / 1.5).rounded())
            return "\\tempo 4. = \(bpm)"
        }
        switch beat.noteValue {
        case 2:
            let bpm = Int((quarterBPM / 2.0).rounded())
            return "\\tempo 2 = \(bpm)"
        case 8:
            let bpm = Int((quarterBPM * 2.0).rounded())
            return "\\tempo 8 = \(bpm)"
        case 16:
            let bpm = Int((quarterBPM * 4.0).rounded())
            return "\\tempo 16 = \(bpm)"
        default:
            let bpm = Int(quarterBPM.rounded())
            return "\\tempo 4 = \(bpm)"
        }
    }

    private static func formatDirective(_ directive: PlaybackDirectiveEvent) -> String {
        directive.lilyPondString
    }

    private static func formatMeasureEventGroup(_ group: [MeasureEvent], percussion: Bool) -> String
    {
        guard let first = group.first else { return "" }
        let noteEvents = group.compactMap { ev -> (Note, MeasureEvent)? in
            if case .note(let n) = ev.content { return (n, ev) }
            return nil
        }
        if noteEvents.count > 1 {
            let decomposed = NotationDuration.decompose(quarterNotes: first.duration)
            let pitches = noteEvents.map { note, ev in
                noteToLilyPondPitch(note, keyOffset: ev.state.keyOffset)
            }
            let chordBody = "<\(pitches.joined(separator: " "))>"
            let hasTieStart = noteEvents.contains { $0.1.tieStart }
            var parts: [String] = []
            for (idx, d) in decomposed.enumerated() {
                let durStr = "\(d.baseDenominator)\(d.isDotted ? "." : "")"
                let isLast = (idx == decomposed.count - 1)
                let tie = (isLast ? (hasTieStart ? "~" : "") : "~")
                parts.append("\(chordBody)\(durStr)\(tie)")
            }
            return parts.joined(separator: " ")
        }
        return formatMeasureEvent(first, percussion: percussion)
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
            let percMap = [
                "X": "hh", "x": "hh",
                "O": "hho", "o": "hho",
                "T": "toml", "t": "toml",
                "S": "sn", "s": "sn",
                "D": "bd", "d": "bd",
                "B": "bd", "b": "bd",
                "C": "cymc", "c": "cymc",
            ]
            let names = pattern.compactMap { percMap[String($0)] }
            if names.isEmpty {
                return decomposed.map { d in "r\(d.baseDenominator)\(d.isDotted ? "." : "")" }
                    .joined(separator: " ")
            }
            return decomposed.map { d in
                let durStr = "\(d.baseDenominator)\(d.isDotted ? "." : "")"
                return names.map { "\($0)\(durStr)" }.joined(separator: " ")
            }.joined(separator: " ")
        }
    }

    private static func paragraphsContainPercussion(_ entries: [Entry], instrument: String) -> Bool
    {
        entries.filter { ($0.assignment ?? "").caseInsensitiveCompare(instrument) == .orderedSame }
            .contains { paragraph in
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
        let spelled = PitchMapping.spell(note: note, keyOffset: keyOffset)
        return PitchMapping.lilyPondPitch(spelled)
    }

    private static func chordToLilyPondPitches(_ chord: ChordSymbol, keyOffset: Int) -> [String] {
        return PitchMapping.spellChordVoicing(chord, keyOffset: keyOffset).map {
            PitchMapping.lilyPondPitch($0)
        }
    }

    fileprivate static func lilyPondKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return "c \\major" }
        var isMinor = false
        var rest = String(trimmed.dropFirst())
        if rest.hasSuffix("m") && !rest.hasSuffix("maj") {
            isMinor = true
            rest.removeLast()
        } else if rest.lowercased().hasSuffix("minor") {
            isMinor = true
            rest = String(rest.dropLast(5)).trimmingCharacters(in: .whitespaces)
        }
        var pitch = String(first).lowercased()
        if rest.contains("'") || rest.contains("#") {
            pitch += "is"
        } else if rest.contains(",") || rest.contains("b") {
            pitch += "es"
        }
        return "\(pitch) \\\(isMinor ? "minor" : "major")"
    }

    private static func sanitizeIdentifier(_ string: String, index: Int) -> String {
        let numberWords = [
            "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
        ]
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

private extension PlaybackDirectiveEvent {
    var lilyPondString: String {
        switch kind {
        case .tempo, .relativeTempo:
            let cmd = TmdLilyPondGenerator.resolveTempo(
                beat: state.timeSignature, quarterBPM: state.tempo)
            return "\(cmd) "
        case .timeSignature(let beat):
            return "\\time \(beat.count)/\(beat.noteValue) "
        case .absoluteKey(let key), .explicitKey(let key):
            return "\\key \(TmdLilyPondGenerator.lilyPondKey(key)) "
        case .dynamics(let mark):
            return "\\\(mark.rawValue) "
        case .relativeKey:
            let semitone = ((state.keyOffset % 12) + 12) % 12
            let keyTonic = PitchMapping.lilyPondNames[semitone]
            return "\\key \(keyTonic) \\major "
        case .fixedPitch:
            return "\\key c \\major "
        }
    }
}
