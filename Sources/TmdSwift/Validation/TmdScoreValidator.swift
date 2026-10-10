import Foundation

/// Severity level of a TMD score diagnostic.
public enum TmdDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case error
    case warning
}

/// Canonical diagnostic rule codes per `TMD-Checker-and-Semantic-Linter-Specification.en.md`.
public enum TmdDiagnosticRule: String, Codable, Equatable, Sendable {
    case syntax = "E-SYNTAX"
    case measureBeat = "E-MEASURE-BEAT"
    case macroExpand = "E-MACRO-EXPAND"
    case timelineOverlap = "E-TIMELINE-OVERLAP"
    case tempoConflict = "E-TEMPO-CONFLICT"
    case chordMultiNote = "E-CHORD-MULTINOTE"
    case chordCustom = "W-CHORD-CUSTOM"
    case unusedEntry = "W-UNUSED-ENTRY"
    case unusedPrototype = "W-UNUSED-PROTOTYPE"
    case instrumentInconsistent = "W-INSTRUMENT-INCONSISTENT"
    case instrumentUnknown = "W-INSTRUMENT-UNKNOWN"
    case sectionLengthMismatch = "W-SECTION-LENGTH-MISMATCH"
}

/// A structured diagnostic produced by `TmdScoreValidator`.
public struct TmdScoreDiagnostic: Codable, Equatable, Sendable, CustomStringConvertible {
    public let file: String?
    public let line: Int
    public let column: Int
    public let endLine: Int
    public let endColumn: Int
    public let severity: TmdDiagnosticSeverity
    public let rule: TmdDiagnosticRule
    public let message: String
    public let suggestion: String?
    public let codeFrame: String?

    public init(
        file: String? = nil,
        line: Int = 1,
        column: Int = 1,
        endLine: Int? = nil,
        endColumn: Int? = nil,
        severity: TmdDiagnosticSeverity,
        rule: TmdDiagnosticRule,
        message: String,
        suggestion: String? = nil,
        codeFrame: String? = nil
    ) {
        self.file = file
        self.line = max(1, line)
        self.column = max(1, column)
        self.endLine = max(1, endLine ?? line)
        self.endColumn = max(1, endColumn ?? column)
        self.severity = severity
        self.rule = rule
        self.message = message
        self.suggestion = suggestion
        self.codeFrame = codeFrame
    }

    public var description: String {
        let prefix = severity == .error ? "❌ [\(rule.rawValue)]" : "⚠️ [\(rule.rawValue)]"
        let loc = file.map { "\($0):\(line):\(column)" } ?? "line \(line):\(column)"
        var out = "\(prefix) \(loc): \(message)"
        if let suggestion, !suggestion.isEmpty {
            out += "\n  💡 Suggestion: \(suggestion)"
        }
        if let codeFrame, !codeFrame.isEmpty {
            out += "\n\(codeFrame)"
        }
        return out
    }
}

/// Options controlling `TmdScoreValidator`.
public struct TmdValidationOptions: Equatable, Sendable {
    public var file: String?
    public var isSnippet: Bool
    public var lineOffset: Int

    public init(file: String? = nil, isSnippet: Bool = false, lineOffset: Int = 0) {
        self.file = file
        self.isSnippet = isSnippet
        self.lineOffset = lineOffset
    }
}

/// Unified 6-stage TMD Score Validator and Semantic Linter (`TmdScoreValidator`).
public enum TmdScoreValidator {

    /// Validates a TMD score string and returns all Error and Warning diagnostics.
    public static func validate(
        source: String,
        options: TmdValidationOptions = TmdValidationOptions()
    ) -> [TmdScoreDiagnostic] {
        var diagnostics: [TmdScoreDiagnostic] = []
        let lines = source.components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }

        // Stage 1a: Measure consistency check (E-MEASURE-BEAT)
        let measureIssues = TmdMeasureChecker.check(source: source)
        for issue in measureIssues {
            let line = max(1, issue.lineNumber) + options.lineOffset
            let lineLen =
                (issue.lineNumber >= 1 && issue.lineNumber <= lines.count)
                ? max(1, lines[issue.lineNumber - 1].utf16.count) : 80
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: line,
                    column: 1,
                    endLine: line,
                    endColumn: lineLen + 1,
                    severity: .error,
                    rule: .measureBeat,
                    message: issue.description
                ))
        }

        // Stage 1b: Strict Syntax / Throwing Parser check (E-SYNTAX)
        let sheet: Sheet
        do {
            sheet = try TmdParser.parseThrowing(string: source)
        } catch let err as TmdParseError {
            let line = max(1, err.range.start.line) + options.lineOffset
            let col = max(1, err.range.start.column)
            let len = max(1, err.range.length)
            let suggestion = err.hints.isEmpty ? nil : err.hints.joined(separator: " ")
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: line,
                    column: col,
                    endLine: line,
                    endColumn: col + len,
                    severity: .error,
                    rule: .syntax,
                    message: err.description,
                    suggestion: suggestion,
                    codeFrame: err.formatCodeFrame(sourceCode: source)
                ))
            return diagnostics
        } catch {
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: 1 + options.lineOffset,
                    column: 1,
                    severity: .error,
                    rule: .syntax,
                    message: error.localizedDescription
                ))
            return diagnostics
        }

        // Validate movable-do header ?= is not a minor key like ?= Am
        for (idx, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if let range = trimmed.range(of: #"^\?=\s*([A-Ga-g][',#b]?m\b|\S+)"#, options: .regularExpression) {
                let token = String(trimmed[range])
                    .replacingOccurrences(of: #"^\?=\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !isValidMovableDoKeyToken(token) {
                    let lineNum = idx + 1 + options.lineOffset
                    let baseLetter = String(token.prefix(while: { $0 != "m" && $0 != "M" }))
                    diagnostics.append(
                        TmdScoreDiagnostic(
                            file: options.file,
                            line: lineNum,
                            column: 1,
                            endLine: lineNum,
                            endColumn: max(1, rawLine.count),
                            severity: .error,
                            rule: .syntax,
                            message: "Invalid movable-do key signature '?= \(token)'. '?=' only defines where '1' (do) is in semitones.",
                            suggestion: token.lowercased().hasSuffix("m")
                                ? "Use '?= \(baseLetter.isEmpty ? "A" : baseLetter)' for the movable-do base and 'key= \(token)' for the written minor key signature."
                                : "Use a pitch class such as C, D, E, F, G, A, B with optional ' or , (e.g. '?= C', '?= F', '?= B,')."
                        ))
                }
            }
        }

        // Stage 2: Macro Expansion & Timeline Validation
        let expandedSheet: Sheet
        do {
            expandedSheet = try TmdMacroEvaluator.expandThrowing(sheet)
        } catch let macroErr as TmdMacroError {
            let line = (macroErr.line ?? 1) + options.lineOffset
            let col = macroErr.column ?? 1
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: line,
                    column: col,
                    severity: .error,
                    rule: .macroExpand,
                    message: macroErr.errorDescription ?? macroErr.message
                ))
            expandedSheet = sheet
        } catch {
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: 1 + options.lineOffset,
                    column: 1,
                    severity: .error,
                    rule: .macroExpand,
                    message: error.localizedDescription
                ))
            expandedSheet = sheet
        }

        // 2b. Timeline overlap (E-TIMELINE-OVERLAP)
        for overlap in TmdPlaybackRenderer.validate(sheet: expandedSheet) {
            let line = findEntryLine(
                name: overlap.sectionName, assignment: overlap.assignment, in: lines)
                + options.lineOffset
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: line,
                    column: 1,
                    severity: .error,
                    rule: .timelineOverlap,
                    message: overlap.description
                ))
        }

        // 2c. Simultaneous tempo conflicts (E-TEMPO-CONFLICT)
        for conflict in TmdPlaybackRenderer.validateTempoConflicts(sheet: expandedSheet) {
            let temposStr = conflict.tempos.map { String(Int($0.rounded())) }.joined(
                separator: ", ")
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: 1 + options.lineOffset,
                    column: 1,
                    severity: .error,
                    rule: .tempoConflict,
                    message:
                        "Conflicting simultaneous tempo directives (\(temposStr) BPM) at beat position \(conflict.position)."
                ))
        }

        // Stage 3: Chord Symbol Linter (E-CHORD-MULTINOTE, W-CHORD-CUSTOM)
        for entry in sheet.entries {
            for section in entry.sections {
                for group in section.unitGroups {
                    for unit in group.units {
                        if case .chord(let chord) = unit, case .custom(let rawSuffix) = chord.quality
                        {
                            let fullBracket = "[\(chord.description)]"
                            let loc = findTokenLocation(
                                token: fullBracket, entryName: entry.name,
                                assignment: entry.assignment, in: lines)
                            let line = loc.line + options.lineOffset
                            let col = loc.column

                            if isMultiNoteMisuse(chord: chord, rawSuffix: rawSuffix) {
                                let suggested = suggestMultiNoteFix(from: chord.description)
                                diagnostics.append(
                                    TmdScoreDiagnostic(
                                        file: options.file,
                                        line: line,
                                        column: col,
                                        endLine: line,
                                        endColumn: col + fullBracket.count,
                                        severity: .error,
                                        rule: .chordMultiNote,
                                        message:
                                            "Invalid chord symbol '\(fullBracket)': chord brackets cannot contain space-separated notes or trailing whitespace.",
                                        suggestion:
                                            "Use '+' for simultaneous multi-note dyads/chords without brackets: '\(suggested)'."
                                    ))
                            } else if !isRecognizedExtendedChordSuffix(rawSuffix) {
                                diagnostics.append(
                                    TmdScoreDiagnostic(
                                        file: options.file,
                                        line: line,
                                        column: col,
                                        endLine: line,
                                        endColumn: col + fullBracket.count,
                                        severity: .warning,
                                        rule: .chordCustom,
                                        message:
                                            "Unrecognized chord quality suffix '\(rawSuffix)' in '\(fullBracket)'."
                                    ))
                            }
                        }
                    }
                }
            }
        }

        // Stage 4: Unused Entries & Prototypes (W-UNUSED-ENTRY, W-UNUSED-PROTOTYPE)
        if !options.isSnippet && !sheet.playback.isEmpty {
            let referencedInExpanded = Set(
                expandedSheet.playback.compactMap { order -> String? in
                    if case .name(let n) = order { return n }
                    return nil
                })
            var macroSymbols = Set<String>()
            for order in sheet.playback {
                if case .macro(let sexpr) = order {
                    sexpr.collectSymbols(into: &macroSymbols)
                }
            }

            var reportedUnusedEntries = Set<String>()
            for entry in sheet.entries {
                if entry.isPrototype {
                    if !macroSymbols.contains(entry.name)
                        && !referencedInExpanded.contains(entry.name)
                    {
                        let key = "proto:\(entry.name)"
                        if reportedUnusedEntries.insert(key).inserted {
                            let line =
                                findEntryLine(name: entry.name, assignment: nil, in: lines)
                                + options.lineOffset
                            diagnostics.append(
                                TmdScoreDiagnostic(
                                    file: options.file,
                                    line: line,
                                    column: 1,
                                    severity: .warning,
                                    rule: .unusedPrototype,
                                    message:
                                        "Prototype '\(entry.name)' is defined but never referenced by any macro in '-> ... ->#'."
                                ))
                        }
                    }
                } else {
                    if !referencedInExpanded.contains(entry.name)
                        && !macroSymbols.contains(entry.name)
                    {
                        let inst = entry.assignment ?? ""
                        let key = "entry:\(entry.name):\(inst)"
                        if reportedUnusedEntries.insert(key).inserted {
                            let line =
                                findEntryLine(
                                    name: entry.name, assignment: entry.assignment, in: lines)
                                + options.lineOffset
                            diagnostics.append(
                                TmdScoreDiagnostic(
                                    file: options.file,
                                    line: line,
                                    column: 1,
                                    severity: .warning,
                                    rule: .unusedEntry,
                                    message:
                                        "Entry '\(entry.name):\(inst)' is defined but never referenced in the playback order '-> ... ->#'."
                                ))
                        }
                    }
                }
            }
        }

        // Stage 5: Instrument Name Consistency & Recognition (W-INSTRUMENT-INCONSISTENT, W-INSTRUMENT-UNKNOWN)
        var normalizedInstrumentMap: [String: [String]] = [:]
        var seenDistinctAssignments = Set<String>()
        for entry in sheet.entries {
            guard let assignment = entry.assignment, !assignment.isEmpty else { continue }
            if seenDistinctAssignments.insert(assignment).inserted {
                let norm = normalizeInstrumentKey(assignment)
                if !norm.isEmpty {
                    normalizedInstrumentMap[norm, default: []].append(assignment)
                }
                if !isRecognizedInstrument(assignment) {
                    let line =
                        findEntryLine(name: entry.name, assignment: assignment, in: lines)
                        + options.lineOffset
                    diagnostics.append(
                        TmdScoreDiagnostic(
                            file: options.file,
                            line: line,
                            column: 1,
                            severity: .warning,
                            rule: .instrumentUnknown,
                            message:
                                "Unrecognized instrument assignment '\(assignment)' (will fall back to default Acoustic Grand Piano)."
                        ))
                }
            }
        }
        for (_, variants) in normalizedInstrumentMap where variants.count > 1 {
            let sortedVariants = variants.sorted()
            let line =
                findEntryLine(name: nil, assignment: sortedVariants.last, in: lines)
                + options.lineOffset
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: line,
                    column: 1,
                    severity: .warning,
                    rule: .instrumentInconsistent,
                    message:
                        "Inconsistent instrument assignment spellings: \(sortedVariants.map { "'\($0)'" }.joined(separator: " vs. ")).",
                    suggestion:
                        "Use a single canonical instrument name across all sections so tracks are not split."
                ))
        }

        // Stage 6: Cross-Instrument Section Length Discrepancy (W-SECTION-LENGTH-MISMATCH)
        let measureDur = TmdPlaybackRenderer.measureDuration(for: sheet.beat)
        if measureDur > 0 {
            var sectionNames: [String] = []
            var seenSec = Set<String>()
            for entry in sheet.entries where !entry.isPrototype && entry.showProgram == nil {
                if seenSec.insert(entry.name).inserted {
                    sectionNames.append(entry.name)
                }
            }

            for secName in sectionNames {
                let secEntries = sheet.entries.filter {
                    $0.name == secName && !$0.isPrototype && $0.showProgram == nil
                }
                // Group by canonical instrument assignment and compute max measure span (start + durationInMeasures)
                var spanByInstrument: [(instrument: String, span: Int, entry: Entry)] = []
                var groupedInst: [String: [Entry]] = [:]
                var instOrder: [String] = []
                for e in secEntries {
                    let inst = e.assignment ?? ""
                    if groupedInst[inst] == nil {
                        instOrder.append(inst)
                    }
                    groupedInst[inst, default: []].append(e)
                }
                guard instOrder.count >= 2 else { continue }

                for inst in instOrder {
                    guard let entriesForInst = groupedInst[inst] else { continue }
                    var maxEndMeasure = 0
                    for e in entriesForInst {
                        let beatDur = e.sections.reduce(0.0) { total, section in
                            let unitDur = 4.0 / Double(max(1, section.noteLength))
                            return total
                                + section.unitGroups.reduce(0.0) {
                                    $0 + Double(max(0, $1.length)) * unitDur
                                }
                        }
                        let measuresCount = Int((beatDur / measureDur).rounded())
                        let endMeasure = e.start + measuresCount
                        if endMeasure > maxEndMeasure {
                            maxEndMeasure = endMeasure
                        }
                    }
                    if maxEndMeasure > 0, let firstEntry = entriesForInst.first {
                        spanByInstrument.append((inst, maxEndMeasure, firstEntry))
                    }
                }

                let distinctSpans = Set(spanByInstrument.map(\.span))
                if spanByInstrument.count >= 2 && distinctSpans.count > 1 {
                    // Find modal (most common) span, breaking ties by maximum span
                    var freq: [Int: Int] = [:]
                    for item in spanByInstrument {
                        freq[item.span, default: 0] += 1
                    }
                    let referenceSpan =
                        freq.max { a, b in
                            if a.value != b.value { return a.value < b.value }
                            return a.key < b.key
                        }?.key ?? (distinctSpans.max() ?? 0)

                    for item in spanByInstrument where item.span != referenceSpan {
                        let line =
                            findEntryLine(
                                name: secName, assignment: item.instrument, in: lines)
                            + options.lineOffset
                        diagnostics.append(
                            TmdScoreDiagnostic(
                                file: options.file,
                                line: line,
                                column: 1,
                                severity: .warning,
                                rule: .sectionLengthMismatch,
                                message:
                                    "Section '\(secName)' instrument '\(item.instrument)' spans \(item.span) measure(s), whereas other instruments in '\(secName)' span \(referenceSpan) measure(s). Check if '<n*>' note-length subdivision or rest padding was intended."
                            ))
                    }
                }
            }
        }

        return diagnostics
    }

    /// Extracts and validates all ```tmd ... ``` fenced code blocks inside a Markdown document.
    public static func validateMarkdown(
        source: String,
        file: String? = nil
    ) -> [TmdScoreDiagnostic] {
        var diagnostics: [TmdScoreDiagnostic] = []
        let lines = source.components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }

        var inTmdBlock = false
        var fenceStartLine = 0
        var blockLines: [String] = []

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !inTmdBlock {
                if trimmed.lowercased().hasPrefix("```tmd") {
                    inTmdBlock = true
                    fenceStartLine = idx + 1  // 1-indexed line of ```tmd
                    blockLines = []
                }
            } else {
                if trimmed.hasPrefix("```") {
                    inTmdBlock = false
                    let blockContent = blockLines.joined(separator: "\n")
                    diagnostics.append(
                        contentsOf: validateMarkdownBlock(
                            blockContent: blockContent,
                            fenceStartLine: fenceStartLine,
                            file: file
                        ))
                } else {
                    blockLines.append(line)
                }
            }
        }

        return diagnostics
    }

    private static func validateMarkdownBlock(
        blockContent: String,
        fenceStartLine: Int,
        file: String?
    ) -> [TmdScoreDiagnostic] {
        let trimmed = blockContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.contains("::SCORE::") {
            return validate(
                source: blockContent,
                options: TmdValidationOptions(
                    file: file,
                    isSnippet: false,
                    lineOffset: fenceStartLine
                ))
        } else {
            // Partial snippet without ::SCORE::
            let hasEntryBrace = blockContent.contains("{") && blockContent.contains("}")
            let trailingOrder = blockContent.contains("->") ? "" : "\n->#"
            let syntheticSource: String
            let syntheticHeaderLines: Int
            if hasEntryBrace {
                syntheticSource = "::SCORE::\n!= 120\n?= C\n<4/4>\n" + blockContent + trailingOrder
                syntheticHeaderLines = 4
            } else if trimmed.hasPrefix("<") {
                syntheticSource =
                    "::SCORE::\n!= 120\n?= C\n<4/4>\nSnippet:Piano@|0|{\n" + blockContent + "\n}\n-> Snippet ->#"
                syntheticHeaderLines = 5
            } else {
                // Single-line or bare expression snippet (e.g. just playback arrows or comments)
                return []
            }

            let rawDiags = validate(
                source: syntheticSource,
                options: TmdValidationOptions(
                    file: file,
                    isSnippet: true,
                    lineOffset: fenceStartLine - syntheticHeaderLines
                ))
            return rawDiags
        }
    }

    // MARK: - Helpers

    private static func isValidMovableDoKeyToken(_ token: String) -> Bool {
        if let num = Int(token), (1...7).contains(num) {
            return true
        }
        return token.range(
            of: #"^[A-Ga-g][',#b]?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isMultiNoteMisuse(chord: ChordSymbol, rawSuffix: String) -> Bool {
        if rawSuffix.contains(" ") || rawSuffix.contains("\t") || rawSuffix.contains(",") {
            return true
        }
        // e.g. [1 3 5] or [3, ]
        if chord.root.isScaleDegree
            && rawSuffix.range(of: #"^[',_^\s0-7b#]+$"#, options: .regularExpression) != nil
            && !["5", "6", "7", "9", "11", "13"].contains(rawSuffix)
        {
            return true
        }
        return false
    }

    private static func suggestMultiNoteFix(from rawDescription: String) -> String {
        let tokens =
            rawDescription
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        if tokens.count >= 2 {
            return tokens.joined(separator: "+")
        }
        return rawDescription.trimmingCharacters(in: .whitespaces)
    }

    private static func isRecognizedExtendedChordSuffix(_ suffix: String) -> Bool {
        ChordSymbol.isRecognizedExtendedQuality(suffix)
    }

    private static func normalizeInstrumentKey(_ name: String) -> String {
        return
            name
            .lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func isRecognizedInstrument(_ name: String) -> Bool {
        MIDIInstrument.isRecognized(name)
    }

    private static func findEntryLine(
        name: String?,
        assignment: String?,
        in lines: [String]
    ) -> Int {
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if let name, let assignment {
                if trimmed.hasPrefix("\(name):\(assignment)") {
                    return idx + 1
                }
            } else if let name {
                if trimmed.hasPrefix("\(name)")
                    && (trimmed.contains("{") || trimmed.contains(":"))
                {
                    return idx + 1
                }
            } else if let assignment {
                if trimmed.contains(":\(assignment)@") || trimmed.contains(":\(assignment){") {
                    return idx + 1
                }
            }
        }
        return 1
    }

    private static func findTokenLocation(
        token: String,
        entryName: String,
        assignment: String?,
        in lines: [String]
    ) -> (line: Int, column: Int) {
        let startLineIdx = max(0, findEntryLine(name: entryName, assignment: assignment, in: lines) - 1)
        for idx in startLineIdx..<lines.count {
            if let range = lines[idx].range(of: token) {
                let col = lines[idx].distance(from: lines[idx].startIndex, to: range.lowerBound) + 1
                return (idx + 1, col)
            }
        }
        for (idx, line) in lines.enumerated() {
            if let range = line.range(of: token) {
                let col = line.distance(from: line.startIndex, to: range.lowerBound) + 1
                return (idx + 1, col)
            }
        }
        return (startLineIdx + 1, 1)
    }
}
