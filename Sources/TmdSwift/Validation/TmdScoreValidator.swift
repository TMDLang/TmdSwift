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
    case tempoOutOfRange = "W-TEMPO-OUT-OF-RANGE"
    case lyricCount = "E-LYRIC-COUNT"
    case lyricDirective = "E-LYRIC-DIRECTIVE"
    case lyricGroup = "E-LYRIC-GROUP"
    case lyricTokenUnseparated = "E-LYRIC-TOKEN-UNSEPARATED"
    case stanzaZero = "E-STANZA-ZERO"
    case stanzaRange = "E-STANZA-RANGE"
    case stanzaDuplicate = "E-STANZA-DUPLICATE"
    case stanzaInconsistent = "E-STANZA-INCONSISTENT"
    case stanzaGap = "W-STANZA-GAP"
    case stanzaFallback = "W-STANZA-FALLBACK"

    public static let lyricSlotMismatch: TmdDiagnosticRule = .lyricCount
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
            if let range = trimmed.range(
                of: #"^\?=\s*([A-Ga-g][',#b]?m\b|\S+)"#, options: .regularExpression)
            {
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
                            message:
                                "Invalid movable-do key signature '?= \(token)'. '?=' only defines where '1' (do) is in semitones.",
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
            expandedSheet = TmdMacroEvaluator.expandOrTrap(sheet)
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
            expandedSheet = TmdMacroEvaluator.expandOrTrap(sheet)
        }

        // 2b. Timeline overlap (E-TIMELINE-OVERLAP)
        for overlap in TmdPlaybackRenderer.validate(sheet: expandedSheet) {
            let line =
                findEntryLine(
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

        // 2d. Tempo bounds check (W-TEMPO-OUT-OF-RANGE: [10, 1000] BPM)
        if sheet.speed > 0
            && (sheet.speed < TmdPlaybackRenderer.minTempoBPM
                || sheet.speed > TmdPlaybackRenderer.maxTempoBPM)
        {
            let speedLine =
                (lines.firstIndex {
                    let t = $0.trimmingCharacters(in: .whitespaces)
                    return !t.hasPrefix("//") && t.hasPrefix("!=")
                }.map { $0 + 1 } ?? 1) + options.lineOffset
            let clamped = TmdPlaybackRenderer.clampTempo(sheet.speed)
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: speedLine,
                    column: 1,
                    severity: .warning,
                    rule: .tempoOutOfRange,
                    message:
                        "Tempo '!= \(sheet.speed)' is outside the supported range [10, 1000] BPM (will be clamped to \(clamped) BPM).",
                    suggestion: "Specify a tempo between 10 and 1000 BPM."
                ))
        }

        for entry in sheet.entries {
            var currentTempo =
                sheet.speed > 0
                ? TmdPlaybackRenderer.clampTempo(sheet.speed)
                : TmdPlaybackRenderer.defaultTempoBPM
            let entryLine =
                findEntryLine(name: entry.name, assignment: entry.assignment, in: lines)
                + options.lineOffset
            for section in entry.sections {
                for directive in section.directives.sorted(by: { $0.position < $1.position }) {
                    switch directive.kind {
                    case .tempo(let bpm):
                        if bpm < TmdPlaybackRenderer.minTempoBPM
                            || bpm > TmdPlaybackRenderer.maxTempoBPM
                        {
                            let clamped = TmdPlaybackRenderer.clampTempo(bpm)
                            diagnostics.append(
                                TmdScoreDiagnostic(
                                    file: options.file,
                                    line: entryLine,
                                    column: 1,
                                    severity: .warning,
                                    rule: .tempoOutOfRange,
                                    message:
                                        "Tempo directive '{!= \(bpm)}' in '\(entry.name)' is outside the supported range [10, 1000] BPM (will be clamped to \(clamped) BPM).",
                                    suggestion: "Specify a tempo between 10 and 1000 BPM."
                                ))
                        }
                        currentTempo = TmdPlaybackRenderer.clampTempo(bpm)
                    case .relativeTempo(let delta):
                        let targetTempo = currentTempo + delta
                        if targetTempo < TmdPlaybackRenderer.minTempoBPM
                            || targetTempo > TmdPlaybackRenderer.maxTempoBPM
                        {
                            let clamped = TmdPlaybackRenderer.clampTempo(targetTempo)
                            let op = delta >= 0 ? "!+" : "!-"
                            diagnostics.append(
                                TmdScoreDiagnostic(
                                    file: options.file,
                                    line: entryLine,
                                    column: 1,
                                    severity: .warning,
                                    rule: .tempoOutOfRange,
                                    message:
                                        "Relative tempo directive '{\(op) \(abs(delta))}' in '\(entry.name)' results in \(targetTempo) BPM, outside [10, 1000] BPM (will be clamped to \(clamped) BPM).",
                                    suggestion: "Keep effective tempo within 10 to 1000 BPM."
                                ))
                        }
                        currentTempo = TmdPlaybackRenderer.clampTempo(targetTempo)
                    default:
                        break
                    }
                }
            }
        }

        // Stage 3: Chord Symbol Linter (E-CHORD-MULTINOTE, W-CHORD-CUSTOM)
        for entry in sheet.entries {
            for section in entry.sections {
                for group in section.unitGroups {
                    for unit in group.units {
                        if case .chord(let chord) = unit,
                            case .custom(let rawSuffix) = chord.quality
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
                    if case .name(let n) = order { return Playback.parseSectionSelector(n).name }
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
                var spanByInstrument:
                    [(instrument: String, span: Int, endBeats: Double, entry: Entry)] = []
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
                    var maxEndBeats = 0.0
                    for e in entriesForInst {
                        let beatDur = e.sections.reduce(0.0) { total, section in
                            let unitDur = 4.0 / Double(max(1, section.noteLength))
                            return total
                                + section.unitGroups.reduce(0.0) {
                                    $0 + Double(max(0, $1.length)) * unitDur
                                }
                        }
                        let entryBeat = TmdPlaybackRenderer.entryInitialBeat(
                            for: e, in: sheet, fallback: sheet.beat)
                        let entryMeasureDur = TmdPlaybackRenderer.measureDuration(for: entryBeat)
                        let measuresCount = Int((beatDur / entryMeasureDur).rounded())
                        let endMeasure = e.start + measuresCount
                        let endBeats = Double(e.start) * entryMeasureDur + beatDur
                        if endMeasure > maxEndMeasure {
                            maxEndMeasure = endMeasure
                        }
                        if endBeats > maxEndBeats {
                            maxEndBeats = endBeats
                        }
                    }
                    if maxEndMeasure > 0, let firstEntry = entriesForInst.first {
                        spanByInstrument.append((inst, maxEndMeasure, maxEndBeats, firstEntry))
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
                    let referenceEndBeats =
                        spanByInstrument.first { $0.span == referenceSpan }?.endBeats ?? 0.0

                    for item in spanByInstrument
                    where item.span != referenceSpan
                        && abs(item.endBeats - referenceEndBeats) > 1e-4
                    {
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

        // Stage 7: Vocal Lyrics & Stanza Validation (E-LYRIC-*, E-STANZA-*, W-STANZA-*)
        validateLyricsAndStanzas(
            sheet: sheet,
            lines: lines,
            options: options,
            diagnostics: &diagnostics
        )

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
                    "::SCORE::\n!= 120\n?= C\n<4/4>\nSnippet:Piano@|0|{\n" + blockContent
                    + "\n}\n-> Snippet ->#"
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
        let startLineIdx = max(
            0, findEntryLine(name: entryName, assignment: assignment, in: lines) - 1)
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

    // MARK: - Stage 7: Vocal Lyrics & Stanza Validation

    private static func validateLyricsAndStanzas(
        sheet: Sheet,
        lines: [String],
        options: TmdValidationOptions,
        diagnostics: inout [TmdScoreDiagnostic]
    ) {
        for entry in sheet.entries {
            for section in entry.sections where !section.lyrics.isEmpty {
                var stanzasByPhrase: [Range<Int>: [LyricLine]] = [:]
                var phraseOrder: [Range<Int>] = []
                for lyricLine in section.lyrics {
                    if stanzasByPhrase[lyricLine.unitGroupRange] == nil {
                        phraseOrder.append(lyricLine.unitGroupRange)
                    }
                    stanzasByPhrase[lyricLine.unitGroupRange, default: []].append(lyricLine)
                }

                var sectionValidStanzas = Set<Int>()
                var validStanzasByPhrase: [Range<Int>: Set<Int>] = [:]

                for phraseRange in phraseOrder {
                    guard let phraseLyrics = stanzasByPhrase[phraseRange] else { continue }
                    var seenStanzas = Set<Int>()
                    var validInPhrase = Set<Int>()

                    for lyricLine in phraseLyrics {
                        let lineNum = max(1, lyricLine.sourceLine) + options.lineOffset
                        let rawStanza = lyricLine.stanza
                        if rawStanza == 0 {
                            diagnostics.append(
                                TmdScoreDiagnostic(
                                    file: options.file,
                                    line: lineNum,
                                    column: 1,
                                    severity: .error,
                                    rule: .stanzaZero,
                                    message:
                                        "Invalid stanza index 'L0|' in '\(entry.name)': stanza numbering is 1-based (L1..L64)."
                                ))
                        } else if let s = rawStanza, (s < 0 || s > 64) {
                            diagnostics.append(
                                TmdScoreDiagnostic(
                                    file: options.file,
                                    line: lineNum,
                                    column: 1,
                                    severity: .error,
                                    rule: .stanzaRange,
                                    message:
                                        "Stanza index 'L\(s)|' in '\(entry.name)' exceeds the maximum limit of 64 (L1..L64)."
                                ))
                        } else {
                            let effectiveStanza = rawStanza ?? 1
                            if !seenStanzas.insert(effectiveStanza).inserted {
                                diagnostics.append(
                                    TmdScoreDiagnostic(
                                        file: options.file,
                                        line: lineNum,
                                        column: 1,
                                        severity: .error,
                                        rule: .stanzaDuplicate,
                                        message:
                                            "Duplicate stanza 'L\(effectiveStanza)|' under the same melodic phrase in '\(entry.name)'."
                                    ))
                            }
                            validInPhrase.insert(effectiveStanza)
                            sectionValidStanzas.insert(effectiveStanza)
                        }

                        // Check directives, groups, unseparated tokens, and 1:1 slot count per measure
                        validateLyricLineMeasures(
                            lyricLine: lyricLine,
                            section: section,
                            entry: entry,
                            lineNum: lineNum,
                            options: options,
                            diagnostics: &diagnostics
                        )
                    }
                    validStanzasByPhrase[phraseRange] = validInPhrase
                }

                // Check W-STANZA-GAP
                if let maxStanza = sectionValidStanzas.max(), maxStanza > 1 {
                    let missing = (1...maxStanza).filter { !sectionValidStanzas.contains($0) }
                    if !missing.isEmpty {
                        let firstLine =
                            max(1, section.lyrics.first?.sourceLine ?? 1) + options.lineOffset
                        let missingStr = missing.map { "L\($0)" }.joined(separator: ", ")
                        diagnostics.append(
                            TmdScoreDiagnostic(
                                file: options.file,
                                line: firstLine,
                                column: 1,
                                severity: .warning,
                                rule: .stanzaGap,
                                message:
                                    "Discontinuous stanza numbering in '\(entry.name)': missing \(missingStr)."
                            ))
                    }
                }

                // Check E-STANZA-INCONSISTENT across phrases in the same section
                if phraseOrder.count >= 2 && !sectionValidStanzas.isEmpty {
                    for phraseRange in phraseOrder {
                        let phraseSet = validStanzasByPhrase[phraseRange] ?? []
                        if !phraseSet.isEmpty && phraseSet != sectionValidStanzas {
                            let missing =
                                sectionValidStanzas.subtracting(phraseSet).sorted()
                                .map { "L\($0)" }.joined(separator: ", ")
                            let lineNum =
                                max(1, stanzasByPhrase[phraseRange]?.first?.sourceLine ?? 1)
                                + options.lineOffset
                            diagnostics.append(
                                TmdScoreDiagnostic(
                                    file: options.file,
                                    line: lineNum,
                                    column: 1,
                                    severity: .error,
                                    rule: .stanzaInconsistent,
                                    message:
                                        "Inconsistent stanza declarations in '\(entry.name)': melodic phrase is missing \(missing)."
                                ))
                        }
                    }
                }
            }
        }

        // Check W-STANZA-FALLBACK in playback flow
        for order in sheet.playback {
            guard case .name(let raw) = order else { continue }
            let parsed = Playback.parseSectionSelector(raw)
            guard parsed.stanza == nil else { continue }
            let matchingEntries = sheet.entries.filter { $0.name == parsed.name }
            let isMultiStanza = matchingEntries.contains { entry in
                entry.sections.contains { $0.activeStanzaBitmask.nonzeroBitCount > 1 }
            }
            if isMultiStanza {
                let orderLine =
                    (lines.firstIndex {
                        let t = $0.trimmingCharacters(in: .whitespaces)
                        return !t.hasPrefix("//") && t.contains("->") && t.contains(parsed.name)
                    }.map { $0 + 1 } ?? 1) + options.lineOffset
                diagnostics.append(
                    TmdScoreDiagnostic(
                        file: options.file,
                        line: orderLine,
                        column: 1,
                        severity: .warning,
                        rule: .stanzaFallback,
                        message:
                            "Playback order '-> \(parsed.name)' references multi-stanza section '\(parsed.name)' without an explicit stanza selector (falling back to '[L1]').",
                        suggestion:
                            "Specify an explicit stanza selector such as '-> \(parsed.name)[L1]'."
                    ))
            }
        }
    }

    private static func validateLyricLineMeasures(
        lyricLine: LyricLine,
        section: Section,
        entry: Entry,
        lineNum: Int,
        options: TmdValidationOptions,
        diagnostics: inout [TmdScoreDiagnostic]
    ) {
        let measureRanges = lyricLine.measureUnitGroupRanges
        if lyricLine.measures.count != measureRanges.count {
            diagnostics.append(
                TmdScoreDiagnostic(
                    file: options.file,
                    line: lineNum,
                    column: 1,
                    severity: .error,
                    rule: .lyricCount,
                    message:
                        "Lyric line in '\(entry.name)' has \(lyricLine.measures.count) measure(s), but the corresponding melodic line has \(measureRanges.count) measure(s)."
                ))
        }

        let pairCount = min(lyricLine.measures.count, measureRanges.count)
        for mIdx in 0..<pairCount {
            let lyricMeasure = lyricLine.measures[mIdx]
            let groupRange = measureRanges[mIdx]
            let clampedLower = max(0, min(section.unitGroups.count, groupRange.lowerBound))
            let clampedUpper = max(
                clampedLower, min(section.unitGroups.count, groupRange.upperBound))
            let melodicGroups = Array(section.unitGroups[clampedLower..<clampedUpper])

            // 1. Check E-LYRIC-DIRECTIVE
            if containsDirective(in: lyricMeasure.elements) {
                diagnostics.append(
                    TmdScoreDiagnostic(
                        file: options.file,
                        line: lineNum,
                        column: 1,
                        severity: .error,
                        rule: .lyricDirective,
                        message:
                            "Musical directive inside lyric measure \(mIdx + 1) in '\(entry.name)' is forbidden."
                    ))
            }

            // 2. Check E-LYRIC-TOKEN-UNSEPARATED (multiple CJK ideographs in a single syllable token)
            for unit in lyricMeasure.flatSoundingUnits {
                if case .syllable(let syl) = unit, countCJKIdeographs(in: syl.cleanWord) >= 2 {
                    diagnostics.append(
                        TmdScoreDiagnostic(
                            file: options.file,
                            line: lineNum,
                            column: 1,
                            severity: .error,
                            rule: .lyricTokenUnseparated,
                            message:
                                "Unseparated multi-character lyric token '\(syl.rawText)' in '\(entry.name)': separate each syllable with spaces."
                        ))
                }
            }

            // 3. Check E-LYRIC-GROUP and E-LYRIC-COUNT
            let totalMelodicUnits = melodicGroups.reduce(0) { $0 + $1.units.count }
            let totalLyricUnits = lyricMeasure.flatSoundingUnits.count

            let hasMelodicSubdivision = melodicGroups.contains { $0.units.count > 1 }
            let hasLyricGroup = lyricMeasure.slots.contains {
                if case .group = $0 { return true }
                return false
            }

            if lyricMeasure.slots.count == melodicGroups.count {
                var groupMismatch = false
                for (gIdx, mGroup) in melodicGroups.enumerated() {
                    let lSlot = lyricMeasure.slots[gIdx]
                    if mGroup.units.count > 1 {
                        if case .group(let lUnits) = lSlot {
                            if lUnits.count != mGroup.units.count {
                                groupMismatch = true
                            }
                        } else {
                            groupMismatch = true
                        }
                    } else if case .group(let lUnits) = lSlot {
                        if lUnits.count != mGroup.units.count {
                            groupMismatch = true
                        }
                    }
                }
                if groupMismatch {
                    diagnostics.append(
                        TmdScoreDiagnostic(
                            file: options.file,
                            line: lineNum,
                            column: 1,
                            severity: .error,
                            rule: .lyricGroup,
                            message:
                                "Parenthesized lyric group in measure \(mIdx + 1) of '\(entry.name)' does not match melodic unit group subdivision."
                        ))
                } else if totalLyricUnits != totalMelodicUnits {
                    diagnostics.append(
                        TmdScoreDiagnostic(
                            file: options.file,
                            line: lineNum,
                            column: 1,
                            severity: .error,
                            rule: .lyricCount,
                            message:
                                "Lyric measure \(mIdx + 1) in '\(entry.name)' has \(totalLyricUnits) sounding token(s), expected \(totalMelodicUnits) to match melodic slots."
                        ))
                }
            } else {
                if hasMelodicSubdivision || hasLyricGroup {
                    diagnostics.append(
                        TmdScoreDiagnostic(
                            file: options.file,
                            line: lineNum,
                            column: 1,
                            severity: .error,
                            rule: .lyricGroup,
                            message:
                                "Hierarchical grouping mismatch in measure \(mIdx + 1) of '\(entry.name)': melodic measure has \(melodicGroups.count) top-level slot(s) while lyric measure has \(lyricMeasure.slots.count)."
                        ))
                }
                if totalLyricUnits != totalMelodicUnits {
                    diagnostics.append(
                        TmdScoreDiagnostic(
                            file: options.file,
                            line: lineNum,
                            column: 1,
                            severity: .error,
                            rule: .lyricCount,
                            message:
                                "Lyric measure \(mIdx + 1) in '\(entry.name)' has \(totalLyricUnits) sounding token(s), expected \(totalMelodicUnits) to match melodic slots."
                        ))
                }
            }
        }
    }

    private static func containsDirective(in elements: [LyricElement]) -> Bool {
        for element in elements {
            switch element {
            case .directive:
                return true
            case .group(let children):
                if containsDirective(in: children) {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private static func countCJKIdeographs(in text: String) -> Int {
        text.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
        }.count
    }
}
