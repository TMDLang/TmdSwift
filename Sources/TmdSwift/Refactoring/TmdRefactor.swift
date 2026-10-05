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
}
