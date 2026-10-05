import Foundation

/// Represents a detected measure duration issue within a TMD score.
public struct TmdMeasureIssue: Equatable, CustomStringConvertible, Sendable {
    public let paragraphName: String
    public let instrument: String
    public let lineNumber: Int
    public let measureIndex: Int
    public let expectedUnits: Int
    public let actualUnits: Int
    public let noteLength: Int
    public let beat: Beat
    public let snippet: String

    public var deltaUnits: Int { actualUnits - expectedUnits }

    public var description: String {
        if instrument == "Order" {
            if !paragraphName.isEmpty {
                return
                    "Playback (line \(lineNumber)): Undefined section '\(paragraphName)' in playback (\(snippet))"
            } else {
                return "Playback (line \(lineNumber)): \(snippet)"
            }
        }
        if snippet.hasPrefix("Unclosed entry") {
            return "\(paragraphName):\(instrument) (line \(lineNumber)): \(snippet)"
        }
        if snippet.contains("explicit barlines") {
            return "\(paragraphName):\(instrument) (line \(lineNumber)): \(snippet)"
        }
        let diffStr = deltaUnits > 0 ? "+\(deltaUnits)" : "\(deltaUnits)"
        if measureIndex == 0 {
            var desc = "\(paragraphName):\(instrument) (line \(lineNumber)): "
            desc +=
                "Expected \(expectedUnits) measures (\(snippet)), found \(actualUnits) measures (\(diffStr) measures)"
            return desc
        } else {
            var desc =
                "\(paragraphName):\(instrument) (line \(lineNumber), measure \(measureIndex)): "
            desc +=
                "Expected \(expectedUnits) units (\(beat.count)/\(beat.noteValue) at <\(noteLength)*>), found \(actualUnits) units (\(diffStr) units)"
            if !snippet.isEmpty {
                desc += "\n  --> | \(snippet) |"
            }
            return desc
        }
    }
}

/// Verifies parser-valid measure invariants and combines them with the
/// malformed-source lexer fallback without owning that fallback implementation.
public struct TmdMeasureChecker {
    /// Checks parser-valid structural invariants directly from the canonical AST.
    public static func check(sheet: Sheet) -> [TmdMeasureIssue] {
        let measureDuration =
            Double(max(1, sheet.beat.count) * 4) / Double(max(1, sheet.beat.noteValue))
        var issues: [TmdMeasureIssue] = []

        for entry in sheet.entries where !entry.sections.isEmpty {
            for section in entry.sections {
                let duration = section.unitGroups.reduce(0.0) { total, group in
                    total + Double(max(0, group.length)) * 4.0
                        / Double(max(1, section.noteLength))
                }
                if duration > measureDuration + 1e-9 && section.barlinePositions.isEmpty {
                    let measureCount = Int((duration / measureDuration).rounded())
                    issues.append(
                        TmdMeasureIssue(
                            paragraphName: entry.name,
                            instrument: entry.assignment ?? "",
                            lineNumber: 0,
                            measureIndex: 0,
                            expectedUnits: measureCount,
                            actualUnits: measureCount,
                            noteLength: section.noteLength,
                            beat: sheet.beat,
                            snippet: "Multi-measure section requires explicit barlines"
                        ))
                }
            }
        }
        return issues
    }

    /// Checks source text using AST validation first, then the malformed-source fallback.
    public static func check(source: String) -> [TmdMeasureIssue] {
        let astIssues: [TmdMeasureIssue]
        if let sheet = TmdParser.parse(string: source) {
            astIssues = check(sheet: sheet)
        } else {
            astIssues = []
        }
        return astIssues + TmdMeasureLexerFallback.check(source: source)
    }
}
