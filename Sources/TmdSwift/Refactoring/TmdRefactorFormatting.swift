import Foundation

extension TmdRefactor {
    static func reindentBlockComment(lines: [String], indentPrefix: String) -> [String] {
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
            return indentPrefix + String(repeating: " ", count: relIndent)
                + line.trimmingCharacters(in: .whitespaces)
        }
    }
    static func formatLine(_ line: String, indent: Int = 0) -> String {
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
            let value = trimmed.dropFirst(trimmed.hasPrefix("! =") ? 3 : 2).trimmingCharacters(
                in: .whitespaces)
            return "!= \(value)" + commentSuffix
        }
        if trimmed.hasPrefix("?=") || trimmed.hasPrefix("? =") {
            let value = trimmed.dropFirst(trimmed.hasPrefix("? =") ? 3 : 2).trimmingCharacters(
                in: .whitespaces)
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

        // Abstract prototype header line: e.g. Theme {
        if !trimmed.contains(":") && !trimmed.contains("@") && trimmed.hasSuffix("{")
            && !trimmed.hasPrefix("->")
        {
            let pName = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
            if !pName.isEmpty && !pName.contains(" ") && !pName.contains("\t") {
                return "\(pName) {" + commentSuffix
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

    static func formatMusicalUnits(_ text: String) -> String {
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
