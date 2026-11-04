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
        if trimmed.lowercased().hasPrefix("key=") || trimmed.lowercased().hasPrefix("key =") {
            let eqIdx = trimmed.firstIndex(of: "=")!
            let value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
            return "key= \(value)" + commentSuffix
        }
        if trimmed.hasPrefix("<") && trimmed.hasSuffix(">") && trimmed.contains("/") {
            let compact = trimmed.filter { $0 != " " && $0 != "\t" }
            return compact + commentSuffix
        }

        // Metadata credit line: ~ "..."
        if trimmed.hasPrefix("~") {
            let value = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            return "~ \(value)" + commentSuffix
        }

        // Named metadata line: =~:__KEY__= "..."
        if trimmed.hasPrefix("=~") {
            if let quoteIdx = trimmed.firstIndex(of: "\"") {
                let prefixPart = trimmed[..<quoteIdx]
                let quotedPart = trimmed[quoteIdx...]
                let keyChars = prefixPart.dropFirst(2).filter {
                    $0 != ":" && $0 != "_" && $0 != "=" && $0 != " " && $0 != "\t"
                }
                if !keyChars.isEmpty {
                    return "=~:__\(keyChars)__= \(quotedPart)" + commentSuffix
                }
            }
            return trimmed + commentSuffix
        }

        // Paragraph header line: e.g. intro:Piano@|0|{ or intro:Piano [pitchMode=fixed] @|0|{
        if trimmed.contains(":") && trimmed.contains("@") && trimmed.hasSuffix("{") {
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let pName = parts[0].trimmingCharacters(in: .whitespaces)
                let rest = parts[1].trimmingCharacters(in: .whitespaces)
                let atParts = rest.split(separator: "@", maxSplits: 1)
                if atParts.count == 2 {
                    let instRaw = atParts[0].trimmingCharacters(in: .whitespaces)
                    let inst: String
                    if let bracketIdx = instRaw.firstIndex(of: "[") {
                        let baseInst = instRaw[..<bracketIdx].trimmingCharacters(in: .whitespaces)
                        let attr = instRaw[bracketIdx...].filter { $0 != " " && $0 != "\t" }
                        inst = "\(baseInst)\(attr)"
                    } else {
                        inst = instRaw
                    }
                    let timing = atParts[1].filter { $0 != " " && $0 != "\t" }
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

    static func formatMusicalUnits(_ text: String, addOuterBarlines: Bool = true) -> String {
        let chars = Array(text)
        var tokens: [String] = []
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

            if ch == "{" {
                if let closeIdx = chars[(i + 1)...].firstIndex(of: "}") {
                    let inner = String(chars[(i + 1)..<closeIdx]).trimmingCharacters(in: .whitespaces)
                    tokens.append(formatInlineDirective(inner))
                    i = closeIdx + 1
                } else {
                    let inner = String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces)
                    tokens.append("{" + inner)
                    i = chars.count
                }
                continue
            }

            if ch == "[" {
                if let closeIdx = chars[(i + 1)...].firstIndex(of: "]") {
                    let inner = String(chars[(i + 1)..<closeIdx]).filter { $0 != " " && $0 != "\t" }
                    tokens.append("[\(inner)]")
                    i = closeIdx + 1
                } else {
                    let inner = String(chars[(i + 1)...]).filter { $0 != " " && $0 != "\t" }
                    tokens.append("[\(inner)")
                    i = chars.count
                }
                continue
            }

            if ch == "(" {
                if let closeIdx = findMatchingParen(in: chars, from: i) {
                    let inner = String(chars[(i + 1)..<closeIdx])
                    let formattedInner = formatMusicalUnits(inner, addOuterBarlines: false)
                    var nextIdx = closeIdx + 1
                    while nextIdx < chars.count && (chars[nextIdx] == " " || chars[nextIdx] == "\t") {
                        nextIdx += 1
                    }
                    if nextIdx < chars.count && chars[nextIdx] == "%" {
                        var afterPct = nextIdx + 1
                        while afterPct < chars.count
                            && (chars[afterPct] == " " || chars[afterPct] == "\t")
                        {
                            afterPct += 1
                        }
                        if afterPct < chars.count && chars[afterPct] == "(",
                            let dashCloseIdx = findMatchingParen(in: chars, from: afterPct)
                        {
                            let dashInner = String(chars[(afterPct + 1)..<dashCloseIdx]).filter {
                                $0 != " " && $0 != "\t"
                            }
                            tokens.append("(\(formattedInner))%(\(dashInner))")
                            i = dashCloseIdx + 1
                            continue
                        }
                    }
                    tokens.append("(\(formattedInner))")
                    i = closeIdx + 1
                } else {
                    tokens.append("(")
                    i += 1
                }
                continue
            }

            if ("1"..."7").contains(ch) {
                var noteUnit = scanCanonicalNote(from: chars, at: &i)
                while true {
                    let savedIdx = i
                    while i < chars.count && (chars[i] == " " || chars[i] == "\t") {
                        i += 1
                    }
                    if i < chars.count && chars[i] == "+" {
                        i += 1
                        while i < chars.count && (chars[i] == " " || chars[i] == "\t") {
                            i += 1
                        }
                        if i < chars.count && ("1"..."7").contains(chars[i]) {
                            let nextNote = scanCanonicalNote(from: chars, at: &i)
                            noteUnit += "+\(nextNote)"
                            continue
                        }
                    }
                    i = savedIdx
                    break
                }
                tokens.append(noteUnit)
                continue
            }

            if ch == "0" {
                tokens.append("0")
                i += 1
                continue
            }

            if ch == "-" {
                tokens.append("-")
                i += 1
                continue
            }

            var word = ""
            while i < chars.count {
                let cur = chars[i]
                if cur == " " || cur == "\t" || "|{}()[]01234567-+".contains(cur) {
                    break
                }
                word.append(cur)
                i += 1
            }
            if !word.isEmpty {
                tokens.append(word)
            } else {
                tokens.append(String(ch))
                i += 1
            }
        }

        if addOuterBarlines && !tokens.isEmpty {
            if tokens.first != "|" {
                tokens.insert("|", at: 0)
            }
            if tokens.last != "|" {
                tokens.append("|")
            }
        }

        return tokens.joined(separator: " ")
    }

    private static func findMatchingParen(in chars: [Character], from openIdx: Int) -> Int? {
        var depth = 0
        for idx in openIdx..<chars.count {
            if chars[idx] == "(" {
                depth += 1
            } else if chars[idx] == ")" {
                depth -= 1
                if depth == 0 {
                    return idx
                }
            }
        }
        return nil
    }

    private static func scanCanonicalNote(from chars: [Character], at i: inout Int) -> String {
        let degree = chars[i]
        i += 1
        var accidental = ""
        var octave = 0
        while i < chars.count {
            let mod = chars[i]
            if mod == "'" || mod == "," {
                accidental = String(mod)
                i += 1
            } else if mod == "^" {
                octave += 1
                i += 1
            } else if mod == "_" {
                octave -= 1
                i += 1
            } else {
                break
            }
        }
        var result = String(degree) + accidental
        if octave > 0 {
            result += String(repeating: "^", count: octave)
        } else if octave < 0 {
            result += String(repeating: "_", count: -octave)
        }
        return result
    }

    private static func formatInlineDirective(_ inner: String) -> String {
        let lower = inner.lowercased()
        if lower.hasPrefix("key"),
            let eqIdx = inner.firstIndex(of: "="),
            inner[inner.index( inner.startIndex, offsetBy: 3)..<eqIdx].allSatisfy({
                $0 == " " || $0 == "\t"
            })
        {
            let val = inner[inner.index(after: eqIdx)...].filter { $0 != " " && $0 != "\t" }
            return "{key= \(val)}"
        }
        let compact = inner.filter { $0 != " " && $0 != "\t" }
        return "{\(compact)}"
    }
}
