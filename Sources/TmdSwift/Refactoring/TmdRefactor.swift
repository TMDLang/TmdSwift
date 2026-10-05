import Foundation

/// Errors that can occur during TMD refactoring operations.
public enum TmdRefactorError: Error, LocalizedError, Equatable {
    case invalidScore(String)
    case instrumentNotFound(String)
    case sectionNotFound(String)
    case trackNotFound(String)
    case invalidOperation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidScore(let reason):
            return "Invalid score: \(reason)"
        case .instrumentNotFound(let inst):
            return "Instrument '\(inst)' not found in score"
        case .sectionNotFound(let sec):
            return "Section '\(sec)' not found in score"
        case .trackNotFound(let track):
            return "Track '\(track)' not found in score"
        case .invalidOperation(let op):
            return op
        }
    }
}

/// Target selector for scoped refactoring operations.
public struct TmdRefactorTarget: Sendable {
    public var section: String?
    public var instrument: String?

    public init(section: String? = nil, instrument: String? = nil) {
        self.section = section
        self.instrument = instrument
    }
}

/// Provides source-preserving formatting and refactoring operations on TMD score documents.
public struct TmdRefactor {

    /// Formats a TMD source string preserving comments and line layout while normalizing whitespace and bar tokens.
    public static func format(_ source: String) -> String {
        var resultLines: [String] = []
        let rawLines = source.components(separatedBy: .newlines)
        var inProgramBlock = false
        var indentLevel = 0
        var i = 0

        while i < rawLines.count {
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("\"\"\"") {
                let occurrences = trimmed.components(separatedBy: "\"\"\"").count - 1
                if occurrences % 2 != 0 {
                    inProgramBlock.toggle()
                }
                resultLines.append(line)
                i += 1
                continue
            }

            if inProgramBlock {
                resultLines.append(line)
                i += 1
                continue
            }

            if trimmed.isEmpty {
                resultLines.append("")
                i += 1
                continue
            }

            if trimmed == "}" {
                indentLevel = max(0, indentLevel - 1)
                resultLines.append(formatLine(line, indent: 0))
                i += 1
                continue
            }

            // If line starts a block comment
            if trimmed.hasPrefix("/*") {
                var commentLines = [line]
                if !trimmed.contains("*/") || trimmed == "/*" {
                    var j = i + 1
                    while j < rawLines.count {
                        commentLines.append(rawLines[j])
                        if rawLines[j].contains("*/") {
                            break
                        }
                        j += 1
                    }
                    i = j + 1
                } else {
                    i += 1
                }
                let indent = String(repeating: "    ", count: indentLevel)
                resultLines.append(
                    contentsOf: reindentBlockComment(lines: commentLines, indentPrefix: indent))
                continue
            }

            let formattedLine = formatLine(line, indent: indentLevel)
            resultLines.append(formattedLine)

            if trimmed.hasSuffix("{") {
                indentLevel += 1
            }
            i += 1
        }

        // Clean up excessive empty lines (> 2 consecutive empty lines to 1)
        var finalLines: [String] = []
        var emptyCount = 0
        for l in resultLines {
            if l.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyCount += 1
                if emptyCount <= 1 {
                    finalLines.append("")
                }
            } else {
                emptyCount = 0
                finalLines.append(l)
            }
        }

        return finalLines.joined(separator: "\n") + "\n"
    }

    /// Renames all occurrences of an instrument across paragraphs in a TMD source string.
    public static func renameInstrument(
        in source: String, from oldInstrument: String, to newInstrument: String
    ) throws -> String {
        // A paragraph header has the syntax: <name>:<instrument>@...
        // We match <name>:<oldInstrument>@ and replace with <name>:<newInstrument>@
        let pattern =
            "([A-Za-z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*"
            + NSRegularExpression.escapedPattern(for: oldInstrument) + "\\s*@"
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
            in: source, options: [], range: range, withTemplate: "$1:\(newInstrument)@")
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

        let headerPattern =
            "^([a-zA-Z0-9_\\u4e00-\\u9fa5-]+)\\s*:\\s*([a-zA-Z0-9_\\u4e00-\\u9fa5-]+)(@[^{]*)?\\s*\\{"
        let headerRegex = try? NSRegularExpression(pattern: headerPattern, options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            var isHeader = false
            var pInst = ""
            if let regex = headerRegex {
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                    let instRange = Range(match.range(at: 2), in: trimmed)
                {
                    isHeader = true
                    pInst = String(trimmed[instRange])
                }
            }

            if isHeader {
                insideParagraph = true
                keepParagraph = (pInst == instrument)
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

        let duplicatedParagraphs: [Entry] = matching.map { orig in
            let clonedSections = orig.sections.map { sec in
                let clonedGroups = sec.unitGroups.map { g in
                    let clonedUnits = g.units.map { u -> Unit in
                        switch u {
                        case .note(let note):
                            return .note(
                                Note(
                                    accidental: note.accidental,
                                    degree: note.degree,
                                    octave: note.octave + octaveShift
                                ))
                        case .multiNote(let notes):
                            let newNotes = notes.map { note in
                                Note(
                                    accidental: note.accidental,
                                    degree: note.degree,
                                    octave: note.octave + octaveShift
                                )
                            }
                            return .multiNote(newNotes)
                        default:
                            return u
                        }
                    }
                    return UnitGroup(units: clonedUnits, length: g.length)
                }
                return Section(
                    noteLength: sec.noteLength, unitGroups: clonedGroups,
                    directives: sec.directives, barlinePositions: sec.barlinePositions)
            }
            return Entry(
                name: orig.name,
                assignment: targetInstrument,
                start: orig.start,
                sections: clonedSections,
                executionTime: orig.executionTime,
                showProgram: orig.showProgram
            )
        }

        let newParagraphsText =
            duplicatedParagraphs
            .map { $0.format() }
            .joined(separator: "\n")

        var combined: String
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

    /// Generates diatonic harmony (e.g. parallel 3rd up: intervalSteps = 2, 3rd down: intervalSteps = -2).
    public static func generateHarmony(
        source: String,
        sourceInstrument: String,
        harmonyInstrument: String,
        section: String? = nil,
        intervalSteps: Int
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

        let steps = intervalSteps
        let harmonizedParagraphs: [Entry] = matching.map { orig in
            let clonedSections = orig.sections.map { sec in
                let clonedGroups = sec.unitGroups.map { g in
                    let clonedUnits = g.units.map { u -> Unit in
                        switch u {
                        case .note(let note):
                            let currentDeg = note.degree.rawValue  // 1..7
                            let zeroIndexed = currentDeg - 1  // 0..6
                            let newZero = zeroIndexed + steps
                            let newDegVal = (((newZero % 7) + 7) % 7) + 1
                            let octaveDelta = Int(floor(Double(newZero) / 7.0))
                            let newDegree = ScaleDegree(rawValue: newDegVal) ?? note.degree
                            return .note(
                                Note(
                                    accidental: note.accidental,
                                    degree: newDegree,
                                    octave: note.octave + octaveDelta
                                ))
                        case .multiNote(let notes):
                            let newNotes = notes.map { note in
                                let currentDeg = note.degree.rawValue
                                let zeroIndexed = currentDeg - 1
                                let newZero = zeroIndexed + steps
                                let newDegVal = (((newZero % 7) + 7) % 7) + 1
                                let octaveDelta = Int(floor(Double(newZero) / 7.0))
                                let newDegree = ScaleDegree(rawValue: newDegVal) ?? note.degree
                                return Note(
                                    accidental: note.accidental,
                                    degree: newDegree,
                                    octave: note.octave + octaveDelta
                                )
                            }
                            return .multiNote(newNotes)
                        default:
                            return u
                        }
                    }
                    return UnitGroup(units: clonedUnits, length: g.length)
                }
                return Section(
                    noteLength: sec.noteLength, unitGroups: clonedGroups,
                    directives: sec.directives, barlinePositions: sec.barlinePositions)
            }
            return Entry(
                name: orig.name,
                assignment: harmonyInstrument,
                start: orig.start,
                sections: clonedSections,
                executionTime: orig.executionTime,
                showProgram: orig.showProgram
            )
        }

        let newParagraphsText =
            harmonizedParagraphs
            .map { $0.format() }
            .joined(separator: "\n")

        var combined: String
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
            let assignment = p.assignment ?? ""
            if !seenInstruments.contains(assignment) {
                seenInstruments.append(assignment)
            }
        }

        var linearParagraphs: [Entry] = []
        for inst in seenInstruments {
            var combinedUnitGroups: [UnitGroup] = []
            var baseNoteLength = 4

            for ord in sheet.playback {
                guard case .name(let sName) = ord else { continue }
                guard
                    let para = sheet.entries.first(where: {
                        $0.name == sName && $0.assignment == inst
                    })
                else {
                    continue
                }
                for sec in para.sections {
                    baseNoteLength = sec.noteLength
                    combinedUnitGroups.append(contentsOf: sec.unitGroups)
                }
            }

            linearParagraphs.append(
                Entry(
                    name: "linear",
                    assignment: inst,
                    start: 0,
                    sections: [
                        Section(
                            noteLength: baseNoteLength, unitGroups: combinedUnitGroups,
                            directives: [])
                    ]
                ))
        }

        let newSheet = Sheet(
            name: sheet.name,
            speed: sheet.speed,
            keySignature: sheet.keySignature,
            beat: sheet.beat,
            entries: linearParagraphs,
            playback: [.name("linear")],
            metadata: sheet.metadata
        )
        return format(newSheet.format())
    }

    /// Doubles grid resolution (<4*> -> <8*>) padding units with ties, doubling tuplet dash lengths.
    public static func doubleGrid(source: String, target: TmdRefactorTarget? = nil) throws -> String
    {
        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []

        var inMatchingPara = false
        var insideParagraph = false

        let headerRegex = try NSRegularExpression(
            pattern:
                "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
            options: []
        )
        let gridRegex = try NSRegularExpression(pattern: "^<(\\d+)\\*>", options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            let nsTrimmed = trimmed as NSString
            let match = headerRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let m = match {
                insideParagraph = true
                let pSec = nsTrimmed.substring(with: m.range(at: 1))
                let pInst = nsTrimmed.substring(with: m.range(at: 2))
                inMatchingPara =
                    (target?.section == nil || target?.section == pSec)
                    && (target?.instrument == nil || target?.instrument == pInst)
                resultLines.append(rawLine)
                continue
            }

            if trimmed == "}" {
                insideParagraph = false
                inMatchingPara = false
                resultLines.append(rawLine)
                continue
            }

            if !insideParagraph || !inMatchingPara {
                resultLines.append(rawLine)
                continue
            }

            let gMatch = gridRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let gm = gMatch {
                let lenStr = nsTrimmed.substring(with: gm.range(at: 1))
                let curLen = Int(lenStr) ?? 4
                let newLen = curLen * 2
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                resultLines.append("\(indent)<\(newLen)*>")
                continue
            }

            if trimmed.contains("|")
                || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "01234567[]-")) != nil
            {
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                let transformed = doubleGridInLine(trimmed)
                resultLines.append(indent + transformed)
            } else {
                resultLines.append(rawLine)
            }
        }

        return format(resultLines.joined(separator: "\n"))
    }

    /// Halves grid resolution (<8*> -> <4*>) collapsing ties and halving tuplet lengths.
    public static func halveGrid(source: String, target: TmdRefactorTarget? = nil) throws -> String
    {
        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []

        var inMatchingPara = false
        var insideParagraph = false

        let headerRegex = try NSRegularExpression(
            pattern:
                "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
            options: []
        )
        let gridRegex = try NSRegularExpression(pattern: "^<(\\d+)\\*>", options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let nsTrimmed = trimmed as NSString

            let match = headerRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let m = match {
                insideParagraph = true
                let pSec = nsTrimmed.substring(with: m.range(at: 1))
                let pInst = nsTrimmed.substring(with: m.range(at: 2))
                inMatchingPara =
                    (target?.section == nil || target?.section == pSec)
                    && (target?.instrument == nil || target?.instrument == pInst)
                resultLines.append(rawLine)
                continue
            }

            if trimmed == "}" {
                insideParagraph = false
                inMatchingPara = false
                resultLines.append(rawLine)
                continue
            }

            if !insideParagraph || !inMatchingPara {
                resultLines.append(rawLine)
                continue
            }

            let gMatch = gridRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let gm = gMatch {
                let lenStr = nsTrimmed.substring(with: gm.range(at: 1))
                let curLen = Int(lenStr) ?? 4
                if curLen % 2 != 0 {
                    throw TmdRefactorError.invalidOperation("Cannot halve odd grid <\(curLen)*>")
                }
                let newLen = curLen / 2
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                resultLines.append("\(indent)<\(newLen)*>")
                continue
            }

            if trimmed.contains("|")
                || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "01234567[]-")) != nil
            {
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                let transformed = try halveGridInLine(trimmed)
                resultLines.append(indent + transformed)
            } else {
                resultLines.append(rawLine)
            }
        }

        return format(resultLines.joined(separator: "\n"))
    }

    static func parseTupletToken(_ tok: String) -> (inner: String, dashes: String)? {
        guard tok.hasPrefix("(") && tok.contains(")") else { return nil }

        // Match `(inner) % (dashes)` or `(inner)%(dashes)`
        let patternWithLen = "^\\(([^)]+)\\)\\s*%\\s*\\(([-]+)\\)$"
        if let regex = try? NSRegularExpression(pattern: patternWithLen, options: []) {
            let nsTok = tok as NSString
            if let m = regex.firstMatch(
                in: tok, options: [], range: NSRange(location: 0, length: nsTok.length))
            {
                let inner = nsTok.substring(with: m.range(at: 1)).trimmingCharacters(
                    in: .whitespaces)
                let dashes = nsTok.substring(with: m.range(at: 2))
                return (inner: inner, dashes: dashes)
            }
        }

        // Match standalone `(inner)` without `%`
        let patternWithoutLen = "^\\(([^)]+)\\)$"
        if let regex = try? NSRegularExpression(pattern: patternWithoutLen, options: []) {
            let nsTok = tok as NSString
            if let m = regex.firstMatch(
                in: tok, options: [], range: NSRange(location: 0, length: nsTok.length))
            {
                let inner = nsTok.substring(with: m.range(at: 1)).trimmingCharacters(
                    in: .whitespaces)
                return (inner: inner, dashes: "-")
            }
        }

        return nil
    }

    private static func doubleGridInLine(_ line: String) -> String {
        var working = line
        var commentSuffix = ""
        if let commentStart = working.range(of: "/*") {
            commentSuffix = " " + String(working[commentStart.lowerBound...])
            working = String(working[..<commentStart.lowerBound]).trimmingCharacters(
                in: .whitespaces)
        }

        let tokens = measureUnits(in: working)
        var outTokens: [String] = []

        for tok in tokens {
            if tok == "|" {
                outTokens.append("|")
                continue
            }

            if let tuplet = parseTupletToken(tok) {
                let doubledDashes = tuplet.dashes + tuplet.dashes
                outTokens.append("(\(tuplet.inner))%(\(doubledDashes))")
                continue
            }

            // Regular unit: append a tie '-'
            outTokens.append(tok)
            outTokens.append("-")
        }

        return outTokens.joined(separator: " ") + commentSuffix
    }

    private static func halveGridInLine(_ line: String) throws -> String {
        var working = line
        var commentSuffix = ""
        if let commentStart = working.range(of: "/*") {
            commentSuffix = " " + String(working[commentStart.lowerBound...])
            working = String(working[..<commentStart.lowerBound]).trimmingCharacters(
                in: .whitespaces)
        }

        let tokens = measureUnits(in: working)
        var outTokens: [String] = []
        var currentMeasure: [String] = []

        func processMeasure(_ measureTokens: [String]) throws {
            var i = 0
            while i < measureTokens.count {
                let u1 = measureTokens[i]
                if let tuplet = parseTupletToken(u1) {
                    if tuplet.dashes.count % 2 != 0 {
                        throw TmdRefactorError.invalidOperation(
                            "Cannot halve tuplet with odd length: '\(u1)' in | \(measureTokens.joined(separator: " ")) |"
                        )
                    }
                    let halfLen = tuplet.dashes.count / 2
                    let halvedDashes = String(repeating: "-", count: halfLen)
                    outTokens.append("(\(tuplet.inner))%(\(halvedDashes))")
                    i += 1
                    continue
                }

                if i + 1 >= measureTokens.count {
                    throw TmdRefactorError.invalidOperation(
                        "Cannot halve measure with odd number of units: | \(measureTokens.joined(separator: " ")) |"
                    )
                }
                let u2 = measureTokens[i + 1]
                if u2 != "-" {
                    throw TmdRefactorError.invalidOperation(
                        "Cannot halve grid: unit '\(u1) \(u2)' does not sustain with a tie '-'"
                    )
                }
                outTokens.append(u1)
                i += 2
            }
        }

        for tok in tokens {
            if tok == "|" {
                if !currentMeasure.isEmpty {
                    try processMeasure(currentMeasure)
                    currentMeasure = []
                }
                outTokens.append("|")
            } else {
                currentMeasure.append(tok)
            }
        }

        if !currentMeasure.isEmpty {
            try processMeasure(currentMeasure)
        }

        return outTokens.joined(separator: " ") + commentSuffix
    }

    /// Groups the canonical Lexer tokens into the measure units consumed by refactors.
    ///
    /// The Lexer remains the only source of token boundaries. This layer only combines
    /// adjacent syntax that is one refactor unit, such as a note followed immediately by
    /// ties or a complete tuplet expression.
    static func measureUnits(in line: String) -> [String] {
        let lexed = Lexer(string: line).tokenizeWithRanges()
            .filter { $0.token != .eof }
        var units: [String] = []
        var index = 0

        while index < lexed.count {
            let current = lexed[index]

            if current.token == .pipe {
                units.append(current.text)
                index += 1
                continue
            }

            if current.token == .openParen,
                let innerEnd = lexed[index...].firstIndex(where: { $0.token == .closeParen })
            {
                let inner = lexed[(index + 1)..<innerEnd].map(\.text).joined(separator: " ")
                var end = innerEnd + 1
                var dashes = ""

                if end < lexed.count, lexed[end].token == .percentOpenParen,
                    let dashEnd = lexed[(end + 1)...].firstIndex(where: { $0.token == .closeParen })
                {
                    dashes = lexed[(end + 1)..<dashEnd]
                        .filter { $0.token == .tie }
                        .map { _ in "-" }
                        .joined()
                    end = dashEnd + 1
                }

                if !dashes.isEmpty {
                    units.append("(\(inner))%(\(dashes))")
                } else {
                    units.append("(\(inner))")
                }
                index = end
                continue
            }

            var unit = current.text
            var end = index + 1
            while end < lexed.count,
                lexed[end].token == .tie,
                lexed[end - 1].range.endOffset == lexed[end].range.start.offset
            {
                unit += lexed[end].text
                end += 1
            }
            units.append(unit)
            index = end
        }

        return units
    }

    static func containsTransposableUnit(in line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("<") else {
            return false
        }
        return Lexer(string: line).tokenize().contains { token in
            switch token {
            case .note, .chord:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Private Formatting Helpers


    /// Optimizes and compresses grid resolution repeatedly until minimal noteLength is reached.
    public static func optimizeGrid(source: String, target: TmdRefactorTarget? = nil) -> String {
        if target?.section != nil || target?.instrument != nil {
            var current = source
            while true {
                do {
                    let next = try halveGrid(source: current, target: target)
                    if next == current { break }
                    current = next
                } catch {
                    break
                }
            }
            return current
        }

        // Optimize each paragraph independently so one indivisible track does not block other tracks
        var current = source
        if let sheet = try? TmdParser.parseThrowing(string: current) {
            for p in sheet.entries {
                var paraCurrent = current
                let pTarget = TmdRefactorTarget(section: p.name, instrument: p.assignment)
                while true {
                    do {
                        let next = try halveGrid(source: paraCurrent, target: pTarget)
                        if next == paraCurrent { break }
                        paraCurrent = next
                    } catch {
                        break
                    }
                }
                current = paraCurrent
            }
        }
        return current
    }

}
