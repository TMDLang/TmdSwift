import Foundation

/// Errors that can occur during TMD refactoring operations.
public enum TMDRefactorError: Error, LocalizedError, Equatable {
    case invalidScore(String)
    case instrumentNotFound(String)
    case sectionNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidScore(let reason):
            return "Invalid score: \(reason)"
        case .instrumentNotFound(let inst):
            return "Instrument '\(inst)' not found in score"
        case .sectionNotFound(let sec):
            return "Section '\(sec)' not found in score"
        }
    }
}

/// Provides source-preserving formatting and refactoring operations on TMD score documents.
public struct TMDRefactor {
    /// Formats a TMD source string preserving comments and line layout while normalizing whitespace and bar tokens.
    public static func format(_ source: String) -> String {
        var resultLines: [String] = []
        let rawLines = source.components(separatedBy: .newlines)
        var inProgramBlock = false
        var indentLevel = 0
        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("\"\"\"") {
                let occurrences = trimmed.components(separatedBy: "\"\"\"").count - 1
                if occurrences % 2 != 0 {
                    inProgramBlock.toggle()
                }
                resultLines.append(line)
                continue
            }

            if inProgramBlock {
                resultLines.append(line)
                continue
            }

            if trimmed.isEmpty {
                resultLines.append("")
                continue
            }

            if trimmed == "}" {
                indentLevel = max(0, indentLevel - 1)
                resultLines.append(formatLine(line, indent: 0))
                continue
            }

            // If line is pure block comment
            if trimmed.hasPrefix("/*") && trimmed.hasSuffix("*/") {
                let indent = String(repeating: "    ", count: indentLevel)
                resultLines.append(indent + trimmed)
                continue
            }

            let formattedLine = formatLine(line, indent: indentLevel)
            resultLines.append(formattedLine)

            if trimmed.hasSuffix("{") {
                indentLevel += 1
            }
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
    /// Preserves score metadata, headers, tempo, key, beat, and orders.
    public static func extractInstrument(from source: String, instrument: String) throws -> String {
        let sheet = try TmdParser.parseThrowing(string: source)
        let matchingParagraphs = sheet.paragraphs.filter { $0.instrument == instrument }
        guard !matchingParagraphs.isEmpty else {
            throw TMDRefactorError.instrumentNotFound(instrument)
        }

        let extractedSheet = Sheet(
            name: sheet.name,
            speed: sheet.speed,
            keySignature: sheet.keySignature,
            beat: sheet.beat,
            paragraphs: matchingParagraphs,
            orders: sheet.orders,
            metadata: sheet.metadata
        )

        return format(extractedSheet.format())
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
