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
        let title = sheet.name
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        abc += "T:\(title.isEmpty ? "Untitled" : title)\n"
        if let rawComposer = sheet.metadata["composer"] {
            let composerLines = rawComposer
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for line in composerLines {
                abc += "C:\(line)\n"
            }
        }
        abc += "M:\(sheet.beat.count)/\(sheet.beat.noteValue)\n"
        abc += "L:1/16\n"  // Base unit length = 16th note for high rhythm precision
        let speed = sheet.speed > 0 ? sheet.speed : 120
        let tempoField = resolveTempo(beat: sheet.beat, quarterBPM: speed)
        abc += "\(tempoField)\n"
        let effectiveKey = sheet.declaredKey ?? sheet.keySignature.description
        abc += "K:\(abcKey(effectiveKey))\n"

        // Output Voice headers
        for (idx, inst) in instruments.enumerated() {
            let vId = "V\(idx + 1)"
            abc += "V:\(vId) name=\"\(inst)\" snm=\"\(inst.prefix(3))\"\n"
        }

        // Generate lines per instrument track
        for (idx, inst) in instruments.enumerated() {
            let vId = "V\(idx + 1)"
            abc += "[V:\(vId)]\n"
            if sheet.containsPercussionUnits(forInstrument: inst) {
                abc += "%%MIDI channel 10\n"
            }
            abc += generateTrackMusic(instrument: inst, sheet: sheet)
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

        var lineMeasures: [Measure] = []
        for (mIdx, measure) in measures.enumerated() {
            lineMeasures.append(measure)
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
            let isEndOfLine = ((mIdx + 1) % 4 == 0) || (mIdx == measures.count - 1)
            if isEndOfLine {
                result += "\n"
                let lyricLines = formatABCLyricLines(for: lineMeasures)
                if !lyricLines.isEmpty {
                    result += lyricLines + "\n"
                }
                lineMeasures.removeAll()
            } else {
                result += " "
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed + "\n"
    }

    private static func formatABCLyricLines(for measures: [Measure]) -> String {
        var stanzaSet: Set<Int> = []
        var hasActiveLyrics = false
        for measure in measures {
            for group in measure.simultaneousEventGroups {
                guard let noteEv = group.first(where: { $0.content.isNote }) else { continue }
                if noteEv.lyric != nil || noteEv.isLyricMelisma {
                    hasActiveLyrics = true
                }
                for k in noteEv.stanzaLyrics.keys {
                    stanzaSet.insert(k)
                }
            }
        }
        guard hasActiveLyrics || !stanzaSet.isEmpty else { return "" }

        let sortedStanzas = stanzaSet.sorted()
        if sortedStanzas.count > 1 {
            var lines: [String] = []
            for stanza in sortedStanzas {
                var measureStrings: [String] = []
                for measure in measures {
                    var tokens: [String] = []
                    for group in measure.simultaneousEventGroups {
                        guard let noteEv = group.first(where: { $0.content.isNote }) else {
                            continue
                        }
                        if let unit = noteEv.stanzaLyrics[stanza] {
                            switch unit {
                            case .syllable(let syl):
                                tokens.append(syl.rawText)
                            case .tie:
                                tokens.append("_")
                            case .rest:
                                tokens.append("*")
                            }
                        } else {
                            tokens.append("*")
                        }
                    }
                    if !tokens.isEmpty {
                        measureStrings.append(tokens.joined(separator: " "))
                    }
                }
                if !measureStrings.isEmpty {
                    lines.append("w: \(stanza). \(measureStrings.joined(separator: " | "))")
                }
            }
            return lines.joined(separator: "\n")
        } else {
            var measureStrings: [String] = []
            for measure in measures {
                var tokens: [String] = []
                for group in measure.simultaneousEventGroups {
                    guard let noteEv = group.first(where: { $0.content.isNote }) else { continue }
                    if let syl = noteEv.lyric {
                        tokens.append(syl.rawText)
                    } else if noteEv.isLyricMelisma {
                        tokens.append("_")
                    } else {
                        tokens.append("*")
                    }
                }
                if !tokens.isEmpty {
                    measureStrings.append(tokens.joined(separator: " "))
                }
            }
            guard !measureStrings.isEmpty else { return "" }
            return "w: \(measureStrings.joined(separator: " | "))"
        }
    }

    public static func resolveTempo(beat: Beat, quarterBPM: Double) -> String {
        let m = beat.metronomeTempo(forQuarterBPM: quarterBPM)
        return "Q:\(m.abcUnit)=\(m.perMinute)"
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
        if noteEvents.count == group.count && noteEvents.count > 1 {
            let suffix = formatDurationSuffix(quarterNotes: first.duration)
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
        if group.count > 1 {
            return group.map {
                formatMeasureEvent(
                    $0,
                    defaultKeyStepAlters: defaultKeyStepAlters,
                    measureStepAlters: &measureStepAlters
                )
            }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
        let suffix = formatDurationSuffix(quarterNotes: event.duration)
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
            let strokeDuration = event.duration / Double(count)
            let strokeSuffix = formatDurationSuffix(quarterNotes: strokeDuration)
            return pitches.map { pitch in
                "\(pitch)\(strokeSuffix)"
            }.joined(separator: " ")
        }
    }

    // MARK: - Duration & Pitch Helpers

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let t = x % y
            x = y
            y = t
        }
        return max(1, x)
    }

    /// Formats a duration in quarter-note beats as an ABC length suffix relative to `L:1/16`.
    private static func formatDurationSuffix(quarterNotes: Double) -> String {
        let units = max(0.0, quarterNotes * 4.0)
        var bestNum = max(1, Int(units.rounded()))
        var bestDen = 1
        var bestErr = abs(units - Double(bestNum))

        if bestErr > 1e-4 {
            for den in 2...64 {
                let num = Int((units * Double(den)).rounded())
                guard num >= 1 else { continue }
                let err = abs(units - Double(num) / Double(den))
                if err + 1e-7 < bestErr {
                    bestNum = num
                    bestDen = den
                    bestErr = err
                    if err < 1e-5 { break }
                }
            }
        }

        let divisor = gcd(bestNum, bestDen)
        let num = bestNum / divisor
        let den = bestDen / divisor

        if den == 1 {
            return num == 1 ? "" : "\(num)"
        } else if num == 1 {
            return "/\(den)"
        } else {
            return "\(num)/\(den)"
        }
    }

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
        } else {
            let commas = String(repeating: ",", count: max(0, 4 - octave))
            letter = "\(stepUpper)\(commas)"
        }

        return "\(prefix)\(letter)"
    }

    fileprivate static func abcKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "C" }
        var isMinor = false
        var root = trimmed
        let lowerRoot = root.lowercased()
        if lowerRoot.hasSuffix("minor") {
            isMinor = true
            root = String(root.dropLast(5)).trimmingCharacters(in: .whitespaces)
        } else if lowerRoot.hasSuffix("min") {
            isMinor = true
            root = String(root.dropLast(3)).trimmingCharacters(in: .whitespaces)
        } else if lowerRoot.hasSuffix("major") {
            root = String(root.dropLast(5)).trimmingCharacters(in: .whitespaces)
        } else if lowerRoot.hasSuffix("maj") {
            root = String(root.dropLast(3)).trimmingCharacters(in: .whitespaces)
        } else if root.hasSuffix("m") {
            isMinor = true
            root.removeLast()
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

extension PlaybackDirectiveEvent {
    fileprivate var abcString: String {
        switch kind {
        case .tempo, .relativeTempo:
            let cmd = TmdABCGenerator.resolveTempo(
                beat: state.timeSignature, quarterBPM: state.tempo)
            return "[\(cmd)] "
        case .timeSignature(let beat):
            return "[M:\(beat.count)/\(beat.noteValue)] "
        case .absoluteKey(let key), .explicitKey(let key):
            return "[K:\(TmdABCGenerator.abcKey(key))] "
        case .dynamics(let mark):
            return "!\(mark.rawValue)! "
        case .relativeKey:
            let key = PitchMapping.tonicScaleInfo(forKeyOffset: state.keyOffset).name
            return "[K:\(key)] "
        case .fixedPitch:
            return "[K:C] "
        }
    }
}
