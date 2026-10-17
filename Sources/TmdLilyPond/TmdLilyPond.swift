import Foundation
import TmdSwift

/// LilyPond score generator for TMD Sheets.
///
/// Exports the Sheet AST into LilyPond (`.ly`) source files, which can be compiled by the
/// `lilypond` tool into publication-quality engraving PDFs, SVGs, or PNGs.
public struct TmdLilyPondGenerator {

    /// Generates LilyPond `.ly` file content from a Sheet.
    public static func generateLilyPond(from inputSheet: Sheet) -> String {
        let (sheet, instruments) = inputSheet.preparedForExport()
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
            let isDrum = sheet.containsPercussionUnits(forInstrument: inst)
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
            let isDrum = sheet.containsPercussionUnits(forInstrument: inst)
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
            var pendingDirectives: [(offset: Double, directive: PlaybackDirectiveEvent)] = []
            for directive in measure.directives {
                if case .timeSignature = directive.kind {
                    result += formatDirective(directive)
                } else {
                    let relOffset = max(0.0, directive.position - measure.startTime)
                    pendingDirectives.append((relOffset, directive))
                }
            }
            let groups = measure.simultaneousEventGroups
            var dirIdx = 0
            for (gIdx, group) in groups.enumerated() {
                let nextGroupStart =
                    (gIdx + 1 < groups.count)
                    ? (groups[gIdx + 1].first?.startOffset ?? Double.infinity)
                    : Double.infinity
                var activeDynamic: String? = nil
                while dirIdx < pendingDirectives.count
                    && pendingDirectives[dirIdx].offset < nextGroupStart - 1e-4
                {
                    let d = pendingDirectives[dirIdx].directive
                    if case .dynamics(let mark) = d.kind {
                        activeDynamic = mark.rawValue
                    } else {
                        result += formatDirective(d)
                    }
                    dirIdx += 1
                }
                result += formatMeasureEventGroup(
                    group, percussion: percussion, dynamic: activeDynamic)
                result += " "
            }
            while dirIdx < pendingDirectives.count {
                let d = pendingDirectives[dirIdx].directive
                if case .dynamics = d.kind {
                } else {
                    result += formatDirective(d)
                }
                dirIdx += 1
            }
            result += "|\n  "
        }
        return result.trimmingCharacters(in: .whitespaces) + "\n"
    }

    public static func resolveTempo(beat: Beat, quarterBPM: Double) -> String {
        let m = beat.metronomeTempo(forQuarterBPM: quarterBPM)
        return "\\tempo \(m.lilyPondUnit) = \(m.perMinute)"
    }

    private static func formatDirective(_ directive: PlaybackDirectiveEvent) -> String {
        directive.lilyPondString
    }

    private static func formatMeasureEventGroup(
        _ group: [MeasureEvent],
        percussion: Bool,
        dynamic: String? = nil
    ) -> String {
        guard let first = group.first else { return "" }
        let noteEvents = group.compactMap { ev -> (Note, MeasureEvent)? in
            if case .note(let n) = ev.content { return (n, ev) }
            return nil
        }
        if noteEvents.count == group.count && noteEvents.count > 1 {
            let pitches = noteEvents.map { note, ev in
                noteToLilyPondPitch(note, keyOffset: ev.state.keyOffset)
            }
            let chordBody = "<\(pitches.joined(separator: " "))>"
            let hasTieStart = noteEvents.contains { $0.1.tieStart }
            return formatLilyPondTokens(
                quarterNotes: first.duration,
                body: chordBody,
                tieStart: hasTieStart,
                dynamic: dynamic
            )
        }
        if group.count > 1 {
            return group.enumerated().map { idx, ev in
                formatMeasureEvent(ev, percussion: percussion, dynamic: idx == 0 ? dynamic : nil)
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        }
        return formatMeasureEvent(first, percussion: percussion, dynamic: dynamic)
    }

    private static func formatMeasureEvent(
        _ event: MeasureEvent,
        percussion: Bool,
        dynamic: String? = nil
    ) -> String {
        switch event.content {
        case .note(let note):
            let pitch = noteToLilyPondPitch(note, keyOffset: event.state.keyOffset)
            return formatLilyPondTokens(
                quarterNotes: event.duration,
                body: pitch,
                tieStart: event.tieStart,
                dynamic: dynamic
            )
        case .chord(let chord):
            let pitches = chordToLilyPondPitches(chord, keyOffset: event.state.keyOffset)
            let chordBody = "<\(pitches.joined(separator: " "))>"
            return formatLilyPondTokens(
                quarterNotes: event.duration,
                body: chordBody,
                tieStart: event.tieStart,
                dynamic: dynamic
            )
        case .rest:
            return formatLilyPondTokens(
                quarterNotes: event.duration,
                body: "r",
                tieStart: false,
                dynamic: dynamic,
                tieInternal: false
            )
        case .percussion(let pattern):
            let names = PercussionStroke.parse(pattern: pattern).map(\.lilyPondDrumName)
            if names.isEmpty {
                return formatLilyPondTokens(
                    quarterNotes: event.duration,
                    body: "r",
                    tieStart: false,
                    dynamic: dynamic,
                    tieInternal: false
                )
            }
            let strokeDuration = event.duration / Double(names.count)
            return names.enumerated().map { idx, name in
                formatLilyPondTokens(
                    quarterNotes: strokeDuration,
                    body: name,
                    tieStart: false,
                    dynamic: idx == 0 ? dynamic : nil,
                    tieInternal: false
                )
            }.joined(separator: " ")
        }
    }

    // MARK: - Pitch & Duration Helpers

    private static func formatLilyPondTokens(
        quarterNotes: Double,
        body: String,
        tieStart: Bool,
        dynamic: String?,
        tieInternal: Bool = true
    ) -> String {
        let durations = decomposeLilyPondDurations(quarterNotes: quarterNotes)
        let dynSuffix = dynamic.map { "\\\($0)" } ?? ""
        var parts: [String] = []
        for (idx, durStr) in durations.enumerated() {
            let isFirst = (idx == 0)
            let isLast = (idx == durations.count - 1)
            let tie = isLast ? (tieStart ? "~" : "") : (tieInternal ? "~" : "")
            parts.append("\(body)\(durStr)\(isFirst ? dynSuffix : "")\(tie)")
        }
        return parts.joined(separator: " ")
    }

    private static func decomposeLilyPondDurations(quarterNotes: Double) -> [String] {
        guard quarterNotes > 0 else { return ["64"] }
        let candidates: [(den: Int, dotted: Bool, q: Double)] = [
            (1, false, 4.0),
            (2, true, 3.0),
            (2, false, 2.0),
            (4, true, 1.5),
            (4, false, 1.0),
            (8, true, 0.75),
            (8, false, 0.5),
            (16, true, 0.375),
            (16, false, 0.25),
            (32, true, 0.1875),
            (32, false, 0.125),
            (64, false, 0.0625),
            (128, false, 0.03125),
            (256, false, 0.015625),
            (512, false, 0.0078125),
            (1024, false, 0.00390625),
        ]
        var atoms: [String] = []
        var remaining = quarterNotes
        let epsilon = 1e-6
        while remaining >= 0.00390625 - epsilon {
            var matched = false
            for c in candidates {
                if remaining >= c.q - epsilon {
                    atoms.append("\(c.den)\(c.dotted ? "." : "")")
                    remaining -= c.q
                    matched = true
                    break
                }
            }
            if !matched { break }
        }
        if !atoms.isEmpty && abs(remaining) <= 1e-5 {
            return atoms
        }

        // Non-dyadic rational duration (e.g. tuplets 3:2, 5:3, 7:5, 11:7 or n-stroke percussion)
        var qNum = 1
        var qDen = 1
        var foundRational = false
        for den in 1...2048 {
            let approxNum = Int((quarterNotes * Double(den)).rounded())
            if approxNum > 0 && abs(quarterNotes - Double(approxNum) / Double(den)) <= 1e-5 {
                let g = gcd(approxNum, den)
                qNum = approxNum / g
                qDen = den / g
                foundRational = true
                break
            }
        }
        if !foundRational {
            let scaled = max(1, Int((quarterNotes * 1920.0).rounded()))
            let g = gcd(scaled, 1920)
            qNum = scaled / g
            qDen = 1920 / g
        }

        let powerDenominators = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
        var baseDen = 4
        for d in powerDenominators {
            if 4.0 / Double(d) >= quarterNotes - 1e-6 {
                baseDen = d
            } else {
                break
            }
        }
        let rawNum = qNum * baseDen
        let rawDen = qDen * 4
        let g = gcd(rawNum, rawDen)
        let mNum = rawNum / g
        let mDen = rawDen / g
        if mNum == mDen {
            return ["\(baseDen)"]
        } else if mDen == 1 {
            return ["\(baseDen)*\(mNum)"]
        } else {
            return ["\(baseDen)*\(mNum)/\(mDen)"]
        }
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let t = y
            y = x % y
            x = t
        }
        return max(1, x)
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
        let lowerRest = rest.lowercased()
        if lowerRest.hasSuffix("minor") {
            isMinor = true
            rest = String(rest.dropLast(5)).trimmingCharacters(in: .whitespaces)
        } else if lowerRest.hasSuffix("min") {
            isMinor = true
            rest = String(rest.dropLast(3)).trimmingCharacters(in: .whitespaces)
        } else if lowerRest.hasSuffix("major") {
            rest = String(rest.dropLast(5)).trimmingCharacters(in: .whitespaces)
        } else if lowerRest.hasSuffix("maj") {
            rest = String(rest.dropLast(3)).trimmingCharacters(in: .whitespaces)
        } else if rest.hasSuffix("m") {
            isMinor = true
            rest.removeLast()
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

extension PlaybackDirectiveEvent {
    fileprivate var lilyPondString: String {
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
