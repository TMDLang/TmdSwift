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
public struct TmdRefactorTarget: Sendable, Equatable {
    public var section: String?
    public var instrument: String?

    public init(section: String? = nil, instrument: String? = nil) {
        self.section = section
        self.instrument = instrument
    }

    /// Resolves an optional target selector when at least one of `section` or `instrument` is non-nil.
    public static func resolve(section: String?, instrument: String?) -> TmdRefactorTarget? {
        guard section != nil || instrument != nil else { return nil }
        return TmdRefactorTarget(section: section, instrument: instrument)
    }

    /// Returns whether the given section and instrument match this target selector.
    public func matches(section: String, instrument: String) -> Bool {
        (self.section == nil || self.section == section)
            && (self.instrument == nil || self.instrument == instrument)
    }
}

/// Provides source-preserving formatting and refactoring operations on TMD score documents.
public struct TmdRefactor {

    private static let paragraphHeaderRegex = try! NSRegularExpression(
        pattern:
            "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
        options: []
    )

    private static let gridSubdivisionRegex = try! NSRegularExpression(
        pattern: "^<(\\d+)\\*>",
        options: []
    )

    /// Parses a paragraph header line (`<section>:<instrument>@... {`) and returns `(section, instrument)` if matched.
    static func parseParagraphHeaderLine(_ trimmedLine: String) -> (section: String, instrument: String)? {
        let nsTrimmed = trimmedLine as NSString
        let range = NSRange(location: 0, length: nsTrimmed.length)
        guard let match = paragraphHeaderRegex.firstMatch(in: trimmedLine, options: [], range: range) else {
            return nil
        }
        return (
            section: nsTrimmed.substring(with: match.range(at: 1)),
            instrument: nsTrimmed.substring(with: match.range(at: 2))
        )
    }

    /// Parses a grid subdivision marker line (`<N*>`) and returns `N` if matched.
    static func parseGridSubdivisionLine(_ trimmedLine: String) -> Int? {
        let nsTrimmed = trimmedLine as NSString
        let range = NSRange(location: 0, length: nsTrimmed.length)
        guard let match = gridSubdivisionRegex.firstMatch(in: trimmedLine, options: [], range: range) else {
            return nil
        }
        return Int(nsTrimmed.substring(with: match.range(at: 1))) ?? 4
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
}
