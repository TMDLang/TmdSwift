import Foundation

extension TmdRefactor {
    public static func renameInstrument(
        in source: String, from oldInstrument: String, to newInstrument: String
    ) throws -> String {
        // A paragraph header has the syntax: <name>:<instrument>[optional attr]@...
        let pattern =
            "([A-Za-z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*"
            + NSRegularExpression.escapedPattern(for: oldInstrument)
            + "\\s*(\\[[^\\]]*\\])?\\s*@"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return source
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, options: [], range: range)
        if matches.isEmpty {
            // Check if score even parses
            _ = try TmdParser.parseThrowing(string: source)
        }

        let replaced = regex.stringByReplacingMatches(
            in: source, options: [], range: range, withTemplate: "$1:\(newInstrument)$2@")
        // Verify valid TMD score after rename
        _ = try TmdParser.parseThrowing(string: replaced)
        return replaced
    }

    /// Renames all occurrences of a section across paragraphs and orders in a TMD source string.
    public static func renameSection(
        in source: String, from oldSection: String, to newSection: String
    ) throws -> String {
        // 1. Rename in paragraph declarations: <oldSection>:<instrument>@... -> <newSection>:<instrument>@...
        let paraPattern =
            "(^|\\n)\\s*" + NSRegularExpression.escapedPattern(for: oldSection) + "\\s*:"
        let paraRegex = try NSRegularExpression(pattern: paraPattern, options: [])

        var result = paraRegex.stringByReplacingMatches(
            in: source,
            options: [],
            range: NSRange(source.startIndex..<source.endIndex, in: source),
            withTemplate: "$1\(newSection):"
        )

        // 2. Rename in orders: `-> <oldSection> ` or `-> <oldSection>\n` or `-> <oldSection>->`
        let orderPattern =
            "(->\\s*)" + NSRegularExpression.escapedPattern(for: oldSection)
            + "(?=\\s*(->|->#|\\n|$))"
        let orderRegex = try NSRegularExpression(pattern: orderPattern, options: [])
        result = orderRegex.stringByReplacingMatches(
            in: result,
            options: [],
            range: NSRange(result.startIndex..<result.endIndex, in: result),
            withTemplate: "$1\(newSection)"
        )

        // Verify valid TMD score after rename
        _ = try TmdParser.parseThrowing(string: result)
        return result
    }

    /// Extracts all tracks matching the given instrument from the score into a new TMD document.
    /// Preserves score metadata, headers, tempo, key, beat, comments, and orders.
    public static func extractInstrument(from source: String, instrument: String) throws -> String {
        let sheet = try TmdParser.parseThrowing(string: source)
        let matchingParagraphs = sheet.entries.filter { $0.assignment == instrument }
        guard !matchingParagraphs.isEmpty else {
            throw TmdRefactorError.instrumentNotFound(instrument)
        }

        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []
        var insideParagraph = false
        var keepParagraph = false

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if let header = parseParagraphHeaderLine(trimmed) {
                insideParagraph = true
                keepParagraph = (header.instrument == instrument)
                if keepParagraph {
                    resultLines.append(rawLine)
                }
                continue
            }

            if trimmed == "}" {
                if insideParagraph && keepParagraph {
                    resultLines.append(rawLine)
                }
                insideParagraph = false
                keepParagraph = false
                continue
            }

            if insideParagraph {
                if keepParagraph {
                    resultLines.append(rawLine)
                }
                continue
            }

            resultLines.append(rawLine)
        }

        let formatted = format(resultLines.joined(separator: "\n"))
        _ = try TmdParser.parseThrowing(string: formatted)
        return formatted
    }

    /// Duplicates a track with an optional target section and octave shift.
    public static func duplicateTrack(
        source: String,
        sourceInstrument: String,
        targetInstrument: String,
        section: String? = nil,
        octaveShift: Int = 0
    ) throws -> String {
        try cloneAndInsertTrack(
            source: source,
            sourceInstrument: sourceInstrument,
            targetInstrument: targetInstrument,
            section: section
        ) { note in
            Note(
                accidental: note.accidental,
                degree: note.degree,
                octave: note.octave + octaveShift
            )
        }
    }

    /// Generates diatonic harmony (e.g. parallel 3rd up: intervalSteps = 2, 3rd down: intervalSteps = -2).
    public static func generateHarmony(
        source: String,
        sourceInstrument: String,
        harmonyInstrument: String,
        section: String? = nil,
        intervalSteps: Int
    ) throws -> String {
        try cloneAndInsertTrack(
            source: source,
            sourceInstrument: sourceInstrument,
            targetInstrument: harmonyInstrument,
            section: section
        ) { note in
            transposeNoteDiatonicSteps(note, steps: intervalSteps)
        }
    }

    private static func cloneAndInsertTrack(
        source: String,
        sourceInstrument: String,
        targetInstrument: String,
        section: String?,
        transformNote: (Note) -> Note
    ) throws -> String {
        let sheet = try TmdParser.parseThrowing(string: source)
        var matching = sheet.entries.filter { $0.assignment == sourceInstrument }
        if let sec = section {
            matching = matching.filter { $0.name == sec }
        }
        if matching.isEmpty {
            if let sec = section {
                throw TmdRefactorError.trackNotFound("\(sec):\(sourceInstrument)")
            }
            throw TmdRefactorError.instrumentNotFound(sourceInstrument)
        }

        let clonedParagraphs: [Entry] = matching.map { orig in
            Entry(
                name: orig.name,
                assignment: targetInstrument,
                pitchMode: orig.pitchMode,
                start: orig.start,
                sections: orig.sections.mapNotes(transformNote),
                executionTime: orig.executionTime,
                showProgram: orig.showProgram
            )
        }

        let newParagraphsText =
            clonedParagraphs
            .map { $0.format() }
            .joined(separator: "\n")

        let combined: String
        let orderPattern = "(^|\\n)\\s*->"
        if let regex = try? NSRegularExpression(pattern: orderPattern, options: []),
            let match = regex.firstMatch(
                in: source, options: [],
                range: NSRange(source.startIndex..<source.endIndex, in: source))
        {
            let matchedRange = Range(match.range, in: source)!
            let insertPos = source.index(
                matchedRange.lowerBound, offsetBy: source[matchedRange.lowerBound] == "\n" ? 1 : 0)
            combined =
                String(source[..<insertPos]) + "\n" + newParagraphsText + "\n"
                + String(source[insertPos...])
        } else {
            combined = source + "\n\n" + newParagraphsText
        }

        let formatted = format(combined)
        _ = try TmdParser.parseThrowing(string: formatted)
        return formatted
    }

    /// Unrolls / inlines score playback orders into a linear score sequence.
    public static func inlineOrders(source: String) throws -> String {
        let sheet = try TmdParser.parseThrowing(string: source)
        guard !sheet.playback.isEmpty else { return source }

        var seenInstruments: [String] = []
        for p in sheet.entries {
            guard let assignment = p.assignment, !assignment.isEmpty else { continue }
            if !seenInstruments.contains(assignment) {
                seenInstruments.append(assignment)
            }
        }

        var linearParagraphs: [Entry] = []
        for inst in seenInstruments {
            var combinedSections: [Section] = []
            var sourceEntries: [Entry] = []

            for ord in sheet.playback {
                guard case .name(let sName) = ord else { continue }
                guard
                    let para = sheet.entries.first(where: {
                        $0.name == sName && $0.assignment == inst
                    })
                else {
                    continue
                }
                sourceEntries.append(para)
                for sec in para.sections {
                    if let prev = combinedSections.last, prev.noteLength == sec.noteLength {
                        combinedSections.removeLast()
                        let offset = prev.unitGroups.reduce(0) { $0 + $1.length }
                        let shiftedDirectives = sec.directives.map {
                            SectionDirective(position: $0.position + offset, kind: $0.kind)
                        }
                        let shiftedBarlines = sec.barlinePositions.map { $0 + offset }
                        let mergedBarlines = Array(Set(prev.barlinePositions + shiftedBarlines))
                            .sorted()
                        combinedSections.append(
                            Section(
                                noteLength: prev.noteLength,
                                unitGroups: prev.unitGroups + sec.unitGroups,
                                directives: prev.directives + shiftedDirectives,
                                barlinePositions: mergedBarlines
                            ))
                    } else {
                        combinedSections.append(sec)
                    }
                }
            }

            let pitchModes = Set(sourceEntries.map(\.pitchMode))
            let executionTimes = Set(sourceEntries.compactMap(\.executionTime))
            let showPrograms = Set(sourceEntries.compactMap(\.showProgram))

            linearParagraphs.append(
                Entry(
                    name: "linear",
                    assignment: inst,
                    pitchMode: pitchModes.count == 1 ? pitchModes.first! : .transposing,
                    start: 0,
                    sections: combinedSections,
                    executionTime: executionTimes.count == 1 ? executionTimes.first : nil,
                    showProgram: showPrograms.count == 1 ? showPrograms.first : nil
                ))
        }

        let newSheet = Sheet(
            name: sheet.name,
            speed: sheet.speed,
            keySignature: sheet.keySignature,
            declaredKey: sheet.declaredKey,
            beat: sheet.beat,
            entries: linearParagraphs,
            playback: [.name("linear")],
            metadata: sheet.metadata
        )
        return format(newSheet.format())
    }

}
