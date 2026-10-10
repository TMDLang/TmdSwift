import Foundation

public struct TmdParseError: Error, Equatable, CustomStringConvertible, LocalizedError {
    public let message: String
    public let token: Token
    public let text: String
    public let range: SourceRange
    public let expectedTokens: [String]
    public let source: String?

    public init(
        message: String,
        token: Token,
        text: String,
        range: SourceRange,
        expectedTokens: [String] = [],
        source: String? = nil
    ) {
        self.message = message
        self.token = token
        self.text = text
        self.range = range
        self.expectedTokens = expectedTokens
        self.source = source
    }

    public var hints: [String] {
        var result: [String] = []

        // Diagnostic Hint 1: Fullwidth punctuation typo
        if let fullwidthMatch = fullwidthPunctuationOrder.first(where: { text.contains($0) }),
            let half = fullwidthPunctuationMap[fullwidthMatch]
        {
            result.append(
                "Hint: Fullwidth punctuation detected: `\(fullwidthMatch)` -> replace with halfwidth `\(half)`"
            )
        }

        // Diagnostic Hint 2: Accidental typo like 1#, 7b, #, b
        if expectedTokens.contains("note") || expectedTokens.contains("chord")
            || expectedTokens.contains("percussion")
        {
            let isSharpOrFlatTypo =
                text == "#" || text == "b"
                || text.range(of: "^[1-7]#$", options: .regularExpression) != nil
                || text.range(of: "^[1-7][bB]$", options: .regularExpression) != nil
            if isSharpOrFlatTypo {
                result.append(
                    "Hint: For sharp/flat accidentals in TMD, use `'` for sharp (e.g. `1'`) and `,` for flat (e.g. `7,`)"
                )
            }
        }

        // Diagnostic Hint 3: Missing time grid directive like <4*>
        if expectedTokens.count == 1 && expectedTokens[0] == "<" {
            if token.isGridCandidate(text: text) {
                result.append(
                    "Hint: Each section inside `{ ... }` must start with a time grid directive like `<4*>` or `<8*>` before note events"
                )
            }
        }

        // Diagnostic Hint 4: Percussion / drum valid symbols
        if expectedTokens.contains("percussion")
            && text.range(of: "[A-Za-z]", options: .regularExpression) != nil
        {
            result.append(
                "Hint: If writing percussion/drums, valid symbols are: X/x (Hi-Hat), S/s (Snare), B/b/D/d (Bass Drum), T/t (Tom), C/c (Crash), O/o (Open Hi-Hat)"
            )
        }

        return result
    }

    public var errorDescription: String? { description }

    public var description: String {
        var desc = "\(message) at \(range.start.line):\(range.start.column): `\(text)`"
        if !expectedTokens.isEmpty {
            desc += " (expected \(expectedTokens.joined(separator: ", ")))"
        }
        for hint in hints {
            desc += "\n\(hint)"
        }
        return desc
    }

    public func formatCodeFrame(sourceCode: String? = nil) -> String {
        let src = sourceCode ?? self.source ?? ""
        if src.isEmpty { return "" }
        let lines = src.components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }
        let errLine = range.start.line
        let errCol = range.start.column
        let tokenLen = max(1, range.length > 0 ? range.length : (text.isEmpty ? 1 : text.count))

        let startLine = max(1, errLine - 1)
        let endLine = min(lines.count, errLine + 1)

        let maxLineNumWidth = String(endLine).count
        let pad = { (n: Int) -> String in
            let s = String(n)
            return String(repeating: " ", count: max(0, maxLineNumWidth - s.count)) + s
        }

        var out: [String] = []

        for l in startLine...endLine {
            let lineIdx = l - 1
            let lineStr = lineIdx < lines.count ? lines[lineIdx] : ""
            if l == errLine {
                out.append("\(pad(l)) | \(lineStr)")
                let caretIndent = String(repeating: " ", count: max(0, errCol - 1))
                let carets = String(repeating: "^", count: tokenLen)
                let leftPad = String(repeating: " ", count: maxLineNumWidth)
                out.append("\(leftPad) | \(caretIndent)\(carets)")
            } else {
                out.append("\(pad(l)) | \(lineStr)")
            }
        }

        return out.joined(separator: "\n")
    }
}
