import Foundation

/// Errors that can occur during TMD refactoring operations.
public enum TMDRefactorError: Error, LocalizedError, Equatable {
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
public struct TMDRefactorTarget: Sendable {
    public var section: String?
    public var instrument: String?

    public init(section: String? = nil, instrument: String? = nil) {
        self.section = section
        self.instrument = instrument
    }
}

/// Provides source-preserving formatting and refactoring operations on TMD score documents.
public struct TMDRefactor {
    private static func reindentBlockComment(lines: [String], indentPrefix: String) -> [String] {
        if lines.count <= 1 {
            return lines.map { indentPrefix + $0.trimmingCharacters(in: .whitespaces) }
        }
        let firstLine = lines[0]
        let baseIndent = firstLine.prefix(while: { $0 == " " || $0 == "\t" }).count

        return lines.enumerated().map { idx, line in
            if idx == 0 {
                return indentPrefix + line.trimmingCharacters(in: .whitespaces)
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                return ""
            }
            let lineIndent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let relIndent = max(0, lineIndent - baseIndent)
            return indentPrefix + String(repeating: " ", count: relIndent) + line.trimmingCharacters(in: .whitespaces)
        }
    }

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
                resultLines.append(contentsOf: reindentBlockComment(lines: commentLines, indentPrefix: indent))
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
    public static func renameInstrument(in source: String, from oldInstrument: String, to newInstrument: String) throws -> String {
        // A paragraph header has the syntax: <name>:<instrument>@...
        // We match <name>:<oldInstrument>@ and replace with <name>:<newInstrument>@
        let pattern = "([A-Za-z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*" + NSRegularExpression.escapedPattern(for: oldInstrument) + "\\s*@"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return source
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, options: [], range: range)
        if matches.isEmpty {
            // Check if score even parses
            _ = try TmdParser.parseThrowing(string: source)
        }

        let replaced = regex.stringByReplacingMatches(in: source, options: [], range: range, withTemplate: "$1:\(newInstrument)@")
        // Verify valid TMD score after rename
        _ = try TmdParser.parseThrowing(string: replaced)
        return replaced
    }

    /// Renames all occurrences of a section across paragraphs and orders in a TMD source string.
    public static func renameSection(in source: String, from oldSection: String, to newSection: String) throws -> String {
        // 1. Rename in paragraph declarations: <oldSection>:<instrument>@... -> <newSection>:<instrument>@...
        let paraPattern = "(^|\\n)\\s*" + NSRegularExpression.escapedPattern(for: oldSection) + "\\s*:"
        let paraRegex = try NSRegularExpression(pattern: paraPattern, options: [])

        var result = paraRegex.stringByReplacingMatches(
            in: source,
            options: [],
            range: NSRange(source.startIndex..<source.endIndex, in: source),
            withTemplate: "$1\(newSection):"
        )

        // 2. Rename in orders: `-> <oldSection> ` or `-> <oldSection>\n` or `-> <oldSection>->`
        let orderPattern = "(->\\s*)" + NSRegularExpression.escapedPattern(for: oldSection) + "(?=\\s*(->|->#|\\n|$))"
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
        let matchingParagraphs = sheet.paragraphs.filter { $0.instrument == instrument }
        guard !matchingParagraphs.isEmpty else {
            throw TMDRefactorError.instrumentNotFound(instrument)
        }

        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []
        var insideParagraph = false
        var keepParagraph = false

        let headerPattern = "^([a-zA-Z0-9_\\u4e00-\\u9fa5-]+)\\s*:\\s*([a-zA-Z0-9_\\u4e00-\\u9fa5-]+)(@[^{]*)?\\s*\\{"
        let headerRegex = try? NSRegularExpression(pattern: headerPattern, options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            var isHeader = false
            var pInst = ""
            if let regex = headerRegex {
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                   let instRange = Range(match.range(at: 2), in: trimmed) {
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
        var matching = sheet.paragraphs.filter { $0.instrument == sourceInstrument }
        if let sec = section {
            matching = matching.filter { $0.name == sec }
        }
        if matching.isEmpty {
            if let sec = section {
                throw TMDRefactorError.trackNotFound("\(sec):\(sourceInstrument)")
            }
            throw TMDRefactorError.instrumentNotFound(sourceInstrument)
        }

        let duplicatedParagraphs: [Paragraph] = matching.map { orig in
            let clonedSections = orig.sections.map { sec in
                let clonedGroups = sec.unitGroups.map { g in
                    let clonedUnits = g.units.map { u -> Unit in
                        if case .note(let note) = u {
                            return .note(Note(
                                accidental: note.accidental,
                                degree: note.degree,
                                octave: note.octave + octaveShift
                            ))
                        }
                        return u
                    }
                    return UnitGroup(units: clonedUnits, length: g.length)
                }
                return Section(noteLength: sec.noteLength, unitGroups: clonedGroups, directives: sec.directives)
            }
            return Paragraph(
                name: orig.name,
                instrument: targetInstrument,
                start: orig.start,
                sections: clonedSections,
                executionTime: orig.executionTime,
                showProgram: orig.showProgram
            )
        }

        let newParagraphsText = duplicatedParagraphs
            .map { $0.format() }
            .joined(separator: "\n")

        var combined: String
        let orderPattern = "(^|\\n)\\s*->"
        if let regex = try? NSRegularExpression(pattern: orderPattern, options: []),
           let match = regex.firstMatch(in: source, options: [], range: NSRange(source.startIndex..<source.endIndex, in: source)) {
            let matchedRange = Range(match.range, in: source)!
            let insertPos = source.index(matchedRange.lowerBound, offsetBy: source[matchedRange.lowerBound] == "\n" ? 1 : 0)
            combined = String(source[..<insertPos]) + "\n" + newParagraphsText + "\n" + String(source[insertPos...])
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
        var matching = sheet.paragraphs.filter { $0.instrument == sourceInstrument }
        if let sec = section {
            matching = matching.filter { $0.name == sec }
        }
        if matching.isEmpty {
            if let sec = section {
                throw TMDRefactorError.trackNotFound("\(sec):\(sourceInstrument)")
            }
            throw TMDRefactorError.instrumentNotFound(sourceInstrument)
        }

        let steps = intervalSteps
        let harmonizedParagraphs: [Paragraph] = matching.map { orig in
            let clonedSections = orig.sections.map { sec in
                let clonedGroups = sec.unitGroups.map { g in
                    let clonedUnits = g.units.map { u -> Unit in
                        if case .note(let note) = u {
                            let currentDeg = note.degree.rawValue // 1..7
                            let zeroIndexed = currentDeg - 1 // 0..6
                            let newZero = zeroIndexed + steps
                            let newDegVal = (((newZero % 7) + 7) % 7) + 1
                            let octaveDelta = Int(floor(Double(newZero) / 7.0))
                            let newDegree = ScaleDegree(rawValue: newDegVal) ?? note.degree
                            return .note(Note(
                                accidental: note.accidental,
                                degree: newDegree,
                                octave: note.octave + octaveDelta
                            ))
                        }
                        return u
                    }
                    return UnitGroup(units: clonedUnits, length: g.length)
                }
                return Section(noteLength: sec.noteLength, unitGroups: clonedGroups, directives: sec.directives)
            }
            return Paragraph(
                name: orig.name,
                instrument: harmonyInstrument,
                start: orig.start,
                sections: clonedSections,
                executionTime: orig.executionTime,
                showProgram: orig.showProgram
            )
        }

        let newParagraphsText = harmonizedParagraphs
            .map { $0.format() }
            .joined(separator: "\n")

        var combined: String
        let orderPattern = "(^|\\n)\\s*->"
        if let regex = try? NSRegularExpression(pattern: orderPattern, options: []),
           let match = regex.firstMatch(in: source, options: [], range: NSRange(source.startIndex..<source.endIndex, in: source)) {
            let matchedRange = Range(match.range, in: source)!
            let insertPos = source.index(matchedRange.lowerBound, offsetBy: source[matchedRange.lowerBound] == "\n" ? 1 : 0)
            combined = String(source[..<insertPos]) + "\n" + newParagraphsText + "\n" + String(source[insertPos...])
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
        guard !sheet.orders.isEmpty else { return source }

        var seenInstruments: [String] = []
        for p in sheet.paragraphs {
            if !seenInstruments.contains(p.instrument) {
                seenInstruments.append(p.instrument)
            }
        }

        var linearParagraphs: [Paragraph] = []
        for inst in seenInstruments {
            var combinedUnitGroups: [UnitGroup] = []
            var baseNoteLength = 4

            for ord in sheet.orders {
                guard case .name(let sName) = ord else { continue }
                guard let para = sheet.paragraphs.first(where: { $0.name == sName && $0.instrument == inst }) else {
                    continue
                }
                for sec in para.sections {
                    baseNoteLength = sec.noteLength
                    combinedUnitGroups.append(contentsOf: sec.unitGroups)
                }
            }

            linearParagraphs.append(Paragraph(
                name: "linear",
                instrument: inst,
                start: 0,
                sections: [
                    Section(noteLength: baseNoteLength, unitGroups: combinedUnitGroups, directives: [])
                ]
            ))
        }

        let newSheet = Sheet(
            name: sheet.name,
            speed: sheet.speed,
            keySignature: sheet.keySignature,
            beat: sheet.beat,
            paragraphs: linearParagraphs,
            orders: [.name("linear")],
            metadata: sheet.metadata
        )
        return format(newSheet.format())
    }

    /// Doubles grid resolution (<4*> -> <8*>) padding units with ties, doubling tuplet dash lengths.
    public static func doubleGrid(source: String, target: TMDRefactorTarget? = nil) throws -> String {
        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []

        var inMatchingPara = false
        var insideParagraph = false

        let headerRegex = try NSRegularExpression(
            pattern: "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
            options: []
        )
        let gridRegex = try NSRegularExpression(pattern: "^<(\\d+)\\*>", options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            let nsTrimmed = trimmed as NSString
            let match = headerRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let m = match {
                insideParagraph = true
                let pSec = nsTrimmed.substring(with: m.range(at: 1))
                let pInst = nsTrimmed.substring(with: m.range(at: 2))
                inMatchingPara = (target?.section == nil || target?.section == pSec) &&
                                 (target?.instrument == nil || target?.instrument == pInst)
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

            let gMatch = gridRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let gm = gMatch {
                let lenStr = nsTrimmed.substring(with: gm.range(at: 1))
                let curLen = Int(lenStr) ?? 4
                let newLen = curLen * 2
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                resultLines.append("\(indent)<\(newLen)*>")
                continue
            }

            if trimmed.contains("|") || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "01234567[]-")) != nil {
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
    public static func halveGrid(source: String, target: TMDRefactorTarget? = nil) throws -> String {
        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []

        var inMatchingPara = false
        var insideParagraph = false

        let headerRegex = try NSRegularExpression(
            pattern: "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
            options: []
        )
        let gridRegex = try NSRegularExpression(pattern: "^<(\\d+)\\*>", options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let nsTrimmed = trimmed as NSString

            let match = headerRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let m = match {
                insideParagraph = true
                let pSec = nsTrimmed.substring(with: m.range(at: 1))
                let pInst = nsTrimmed.substring(with: m.range(at: 2))
                inMatchingPara = (target?.section == nil || target?.section == pSec) &&
                                 (target?.instrument == nil || target?.instrument == pInst)
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

            let gMatch = gridRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let gm = gMatch {
                let lenStr = nsTrimmed.substring(with: gm.range(at: 1))
                let curLen = Int(lenStr) ?? 4
                if curLen % 2 != 0 {
                    throw TMDRefactorError.invalidOperation("Cannot halve odd grid <\(curLen)*>")
                }
                let newLen = curLen / 2
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                resultLines.append("\(indent)<\(newLen)*>")
                continue
            }

            if trimmed.contains("|") || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "01234567[]-")) != nil {
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                let transformed = try halveGridInLine(trimmed)
                resultLines.append(indent + transformed)
            } else {
                resultLines.append(rawLine)
            }
        }

        return format(resultLines.joined(separator: "\n"))
    }

    private static func parseTupletToken(_ tok: String) -> (inner: String, dashes: String)? {
        guard tok.hasPrefix("(") && tok.contains(")") else { return nil }

        // Match `(inner) % (dashes)` or `(inner)%(dashes)`
        let patternWithLen = "^\\(([^)]+)\\)\\s*%\\s*\\(([-]+)\\)$"
        if let regex = try? NSRegularExpression(pattern: patternWithLen, options: []) {
            let nsTok = tok as NSString
            if let m = regex.firstMatch(in: tok, options: [], range: NSRange(location: 0, length: nsTok.length)) {
                let inner = nsTok.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
                let dashes = nsTok.substring(with: m.range(at: 2))
                return (inner: inner, dashes: dashes)
            }
        }

        // Match standalone `(inner)` without `%`
        let patternWithoutLen = "^\\(([^)]+)\\)$"
        if let regex = try? NSRegularExpression(pattern: patternWithoutLen, options: []) {
            let nsTok = tok as NSString
            if let m = regex.firstMatch(in: tok, options: [], range: NSRange(location: 0, length: nsTok.length)) {
                let inner = nsTok.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
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
            working = String(working[..<commentStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        let tokens = tokenizeMeasureLine(working)
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
            working = String(working[..<commentStart.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        let tokens = tokenizeMeasureLine(working)
        var outTokens: [String] = []
        var currentMeasure: [String] = []

        func processMeasure(_ measureTokens: [String]) throws {
            var i = 0
            while i < measureTokens.count {
                let u1 = measureTokens[i]
                if let tuplet = parseTupletToken(u1) {
                    if tuplet.dashes.count % 2 != 0 {
                        throw TMDRefactorError.invalidOperation(
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
                    throw TMDRefactorError.invalidOperation(
                        "Cannot halve measure with odd number of units: | \(measureTokens.joined(separator: " ")) |"
                    )
                }
                let u2 = measureTokens[i + 1]
                if u2 != "-" {
                    throw TMDRefactorError.invalidOperation(
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

    private static func tokenizeMeasureLine(_ line: String) -> [String] {
        var tokens: [String] = []
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let ch = chars[i]
            if ch == " " || ch == "\t" {
                i += 1
                continue
            }
            if ch == "|" {
                tokens.append("|")
                i += 1
                continue
            }
            if ch == "[" {
                if let end = chars[i...].firstIndex(of: "]") {
                    tokens.append(String(chars[i...end]))
                    i = end + 1
                    continue
                }
            }
            if ch == "(" {
                if let endParen = chars[i...].firstIndex(of: ")") {
                    var afterParen = endParen + 1
                    while afterParen < chars.count && (chars[afterParen] == " " || chars[afterParen] == "\t") {
                        afterParen += 1
                    }
                    if afterParen < chars.count && chars[afterParen] == "%" {
                        var afterPercent = afterParen + 1
                        while afterPercent < chars.count && (chars[afterPercent] == " " || chars[afterPercent] == "\t") {
                            afterPercent += 1
                        }
                        if afterPercent < chars.count && chars[afterPercent] == "(" {
                            if let endDashes = chars[afterPercent...].firstIndex(of: ")") {
                                tokens.append(String(chars[i...endDashes]))
                                i = endDashes + 1
                                continue
                            }
                        }
                    }
                    tokens.append(String(chars[i...endParen]))
                    i = endParen + 1
                    continue
                }
            }
            if ch == "{" {
                if let end = chars[i...].firstIndex(of: "}") {
                    tokens.append(String(chars[i...end]))
                    i = end + 1
                    continue
                }
            }

            var word = ""
            while i < chars.count && !chars[i].isWhitespace && !"|[](){}".contains(chars[i]) {
                word.append(chars[i])
                i += 1
            }
            if !word.isEmpty {
                tokens.append(word)
            }
        }
        return tokens
    }

    // MARK: - Private Formatting Helpers

    private static func formatLine(_ line: String, indent: Int = 0) -> String {
        let indentPrefix = String(repeating: "    ", count: indent)
        var working = line
        var commentSuffix = ""

        // Extract inline block comment if present at end of line
        if let commentStart = working.range(of: "/*") {
            let commentText = String(working[commentStart.lowerBound...])
            working = String(working[..<commentStart.lowerBound])
            commentSuffix = "  " + commentText.trimmingCharacters(in: .whitespaces)
        }

        let trimmed = working.trimmingCharacters(in: .whitespaces)

        // Check if header line
        if trimmed.hasPrefix("::SCORE::") {
            return "::SCORE::" + commentSuffix
        }
        if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
            let title = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)
            return "** \(title) **" + commentSuffix
        }
        if trimmed.hasPrefix("!=") || trimmed.hasPrefix("! =") {
            let value = trimmed.dropFirst(trimmed.hasPrefix("! =") ? 3 : 2).trimmingCharacters(in: .whitespaces)
            return "!= \(value)" + commentSuffix
        }
        if trimmed.hasPrefix("?=") || trimmed.hasPrefix("? =") {
            let value = trimmed.dropFirst(trimmed.hasPrefix("? =") ? 3 : 2).trimmingCharacters(in: .whitespaces)
            return "?= \(value)" + commentSuffix
        }
        if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && trimmed.contains("/") {
            return trimmed + commentSuffix
        }

        // Paragraph header line: e.g. intro:Piano@|0|{
        if trimmed.contains(":") && trimmed.contains("@") && trimmed.hasSuffix("{") {
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let pName = parts[0].trimmingCharacters(in: .whitespaces)
                let rest = parts[1].trimmingCharacters(in: .whitespaces)
                let atParts = rest.split(separator: "@", maxSplits: 1)
                if atParts.count == 2 {
                    let inst = atParts[0].trimmingCharacters(in: .whitespaces)
                    let timing = atParts[1].trimmingCharacters(in: .whitespaces)
                    return "\(pName):\(inst)@\(timing)" + commentSuffix
                }
            }
        }

        // Section header line: <4*> or <16*>
        if trimmed.hasPrefix("<") && trimmed.hasSuffix("*>") {
            return indentPrefix + trimmed + commentSuffix
        }

        // Closing brace
        if trimmed == "}" {
            return "}" + commentSuffix
        }

        // Orders line: -> ...
        if trimmed.hasPrefix("->") {
            let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var orderTokens: [String] = []
            var i = 0
            while i < tokens.count {
                let t = tokens[i]
                if t == "->" || t == "->#" {
                    orderTokens.append(t)
                } else if t.hasPrefix("->") {
                    orderTokens.append("->")
                    let sub = String(t.dropFirst(2))
                    if !sub.isEmpty {
                        orderTokens.append(sub)
                    }
                } else {
                    orderTokens.append(t)
                }
                i += 1
            }
            return orderTokens.joined(separator: " ") + commentSuffix
        }

        // Content / measure line
        let formattedContent = formatMusicalUnits(trimmed)
        return indentPrefix + formattedContent + commentSuffix
    }

    private static func formatMusicalUnits(_ text: String) -> String {
        var output = ""
        let chars = Array(text)
        var i = 0
        var lastWasSpace = false

        while i < chars.count {
            let ch = chars[i]
            if ch == "|" {
                if !output.isEmpty && !output.hasSuffix(" ") {
                    output.append(" ")
                }
                output.append("|")
                // Always ensure space after '|'
                output.append(" ")
                lastWasSpace = true
                // Skip following whitespace in source
                while i + 1 < chars.count && (chars[i + 1] == " " || chars[i + 1] == "\t") {
                    i += 1
                }
            } else if ch == " " || ch == "\t" {
                if !lastWasSpace && !output.isEmpty {
                    output.append(" ")
                    lastWasSpace = true
                }
            } else {
                output.append(ch)
                lastWasSpace = false
            }
            i += 1
        }

        return output.trimmingCharacters(in: .whitespaces)
    }
}
