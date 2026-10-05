import Foundation

// MARK: - Lexer

public final class Lexer {
    private static let metadataKeyByPrefix = [
        "詞：": "lyrics",
        "曲：": "composer",
        "編：": "arranger",
    ]

    private let scalars: [UnicodeScalar]
    private var index: Int = 0

    public init(string: String) {
        self.scalars = Array(string.unicodeScalars)
    }

    private var isAtEnd: Bool {
        index >= scalars.count
    }

    private func peek(offset: Int = 0) -> UnicodeScalar? {
        let target = index + offset
        guard target >= 0 && target < scalars.count else { return nil }
        return scalars[target]
    }

    @discardableResult
    private func advance() -> UnicodeScalar? {
        guard !isAtEnd else { return nil }
        let c = scalars[index]
        index += 1
        return c
    }

    private func skipWhitespace() {
        while !isAtEnd {
            guard let c = peek() else { break }
            if c == " " || c == "\t" || c == "\r" || c == "\n" {
                advance()
            } else if c == "/" && peek(offset: 1) == "*" {
                // Skip block comment /* ... */
                advance()  // /
                advance()  // *
                while !isAtEnd {
                    if peek() == "*" && peek(offset: 1) == "/" {
                        advance()  // *
                        advance()  // /
                        break
                    }
                    advance()
                }
            } else {
                break
            }
        }
    }

    public func tokenize() -> [Token] {
        var tokens: [Token] = []
        while true {
            let token = nextToken()
            tokens.append(token)
            if token == .eof {
                break
            }
        }
        return tokens
    }

    /// Tokenizes the source while retaining each token's source range.
    public func tokenizeWithRanges() -> [LexedToken] {
        var tokens: [LexedToken] = []
        while true {
            skipWhitespace()
            let start = index
            let token = nextToken()
            let position = SourcePosition(
                offset: start,
                line: scalars[..<start].reduce(into: 1) { line, scalar in
                    if scalar == "\n" { line += 1 }
                },
                column: scalars[..<start].reversed().prefix { $0 != "\n" }.count + 1
            )
            let text = String(scalars[start..<index].map { Character(String($0)) })
            tokens.append(
                LexedToken(
                    token: token, text: text,
                    range: SourceRange(start: position, length: index - start)))
            if token == .eof { break }
        }
        return tokens
    }

    private func nextToken() -> Token {
        skipWhitespace()
        guard let c = peek() else {
            return .eof
        }

        if c == "\"" && peek(offset: 1) == "\"" && peek(offset: 2) == "\"" {
            advance()
            advance()
            advance()
            var body = ""
            while !isAtEnd
                && !(peek() == "\"" && peek(offset: 1) == "\"" && peek(offset: 2) == "\"")
            {
                body.append(Character(advance()!))
            }
            if !isAtEnd {
                advance()
                advance()
                advance()
            }
            return .programText(body)
        }

        // ::SCORE::
        if c == ":" && peek(offset: 1) == ":" {
            var prefix = ""
            for i in 0..<9 {
                if let ch = peek(offset: i) {
                    prefix.append(Character(ch))
                }
            }
            if prefix == "::SCORE::" {
                for _ in 0..<9 { advance() }
                return .scoreHeader
            }
        }

        // Song metadata. Credit shorthand uses `~ "..."`; named metadata uses
        // `=~:__KEY__= "..."`.
        if c == "~" || (c == "=" && peek(offset: 1) == "~") {
            let named = c == "="
            if named {
                advance()
                advance()
            } else {
                advance()
            }
            while peek() == " " || peek() == "\t" { advance() }
            var key = "credit"
            if named {
                if peek() == ":" { advance() }
                while peek() == " " || peek() == "\t" { advance() }
                if peek() == "_" {
                    while peek() == "_" { advance() }
                    key = ""
                    while let ch = peek(),
                        ch != "_" && ch != "=" && ch != " " && ch != "\t" && ch != "\""
                    {
                        key.append(Character(advance()!))
                    }
                    while peek() == "_" { advance() }
                    if peek() == "=" { advance() }
                }
            }
            while peek() == " " || peek() == "\t" { advance() }
            if peek() == "\"" {
                advance()
                var value = ""
                while let ch = peek(), ch != "\"" {
                    value.append(Character(advance()!))
                }
                if peek() == "\"" { advance() }
                if key == "credit" {
                    key = Self.metadataKeyByPrefix.first { value.hasPrefix($0.key) }?.value ?? key
                }
                return .metadata(key, value)
            }
        }

        // -># or ->
        if c == "-" && peek(offset: 1) == ">" {
            if peek(offset: 2) == "#" {
                advance()
                advance()
                advance()
                return .arrowEnd
            } else {
                advance()
                advance()
                return .arrow
            }
        }

        // {?= or {?
        if c == "{" && peek(offset: 1) == "?" {
            if peek(offset: 2) == "=" {
                advance()
                advance()
                advance()
                return .absoluteOrderPrefix
            } else {
                advance()
                advance()
                return .relativeOrderPrefix
            }
        }

        // %( (optional whitespace handled by lexer)
        if c == "%" {
            var offset = 1
            while let sc = peek(offset: offset), sc == " " || sc == "\t" {
                offset += 1
            }
            if peek(offset: offset) == "(" {
                for _ in 0...offset { advance() }
                return .percentOpenParen
            }
        }

        // != (optional whitespace handled by lexer)
        if c == "!" {
            var offset = 1
            while let sc = peek(offset: offset), sc == " " || sc == "\t" {
                offset += 1
            }
            if peek(offset: offset) == "=" {
                for _ in 0...offset { advance() }
                return .speedPrefix
            }
            if peek(offset: offset) == "+" {
                for _ in 0...offset { advance() }
                return .relativeTempoPrefix
            }
        }

        // ?= (optional whitespace handled by lexer)
        if c == "?" {
            var offset = 1
            while let sc = peek(offset: offset), sc == " " || sc == "\t" {
                offset += 1
            }
            if peek(offset: offset) == "=" {
                for _ in 0...offset { advance() }
                return .keySignaturePrefix
            }
        }

        // key= or Key= (optional whitespace handled by lexer)
        if (c == "k" || c == "K") && (peek(offset: 1) == "e" || peek(offset: 1) == "E")
            && (peek(offset: 2) == "y" || peek(offset: 2) == "Y")
        {
            var offset = 3
            while let sc = peek(offset: offset), sc == " " || sc == "\t" {
                offset += 1
            }
            if peek(offset: offset) == "=" {
                for _ in 0...offset { advance() }
                return .explicitKeyPrefix
            }
        }

        // **
        if c == "*" && peek(offset: 1) == "*" {
            advance()
            advance()
            return .doubleAsterisk
        }

        // Single character punctuation
        switch c {
        case ":":
            advance()
            return .colon
        case "@":
            advance()
            return .at
        case "|":
            advance()
            return .pipe
        case "{":
            advance()
            return .openBrace
        case "}":
            advance()
            return .closeBrace
        case "(":
            advance()
            return .openParen
        case ")":
            advance()
            return .closeParen
        case "<":
            advance()
            return .openAngle
        case ">":
            advance()
            return .closeAngle
        case "/":
            advance()
            return .slash
        case "*":
            advance()
            return .asterisk
        case "-":
            advance()
            return .tie
        case "+" where !(peek(offset: 1).map { $0 >= "0" && $0 <= "9" } ?? false):
            advance()
            return .plus
        case "[":
            // Chord: [Cmaj7]
            advance()  // [
            var chordContent = ""
            while !isAtEnd && peek() != "]" {
                if let ch = advance() {
                    chordContent.append(Character(ch))
                }
            }
            if peek() == "]" {
                advance()
            }
            return .chord(chordContent.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            break
        }

        // Note (1~7 followed by optional ', ,, ^, _)
        if c >= "1" && c <= "7" {
            // Check if it is followed immediately by note modifiers (', ,, ^, _)
            // Or if it's a stand-alone digit not followed by more digits
            let next = peek(offset: 1)
            let isModifier = next == "'" || next == "," || next == "^" || next == "_"
            let isDigit = next.map { $0 >= "0" && $0 <= "9" } ?? false

            if isModifier || !isDigit {
                advance()
                guard let degree = ScaleDegree(rawValue: Int(c.value - UnicodeScalar("0").value))
                else {
                    return .identifier(String(Character(c)))
                }
                var accidental: Accidental = .natural
                var octave = 0
                while !isAtEnd {
                    guard let mod = peek() else { break }
                    if mod == "'" {
                        accidental = .sharp
                        advance()
                    } else if mod == "," {
                        accidental = .flat
                        advance()
                    } else if mod == "^" {
                        octave += 1
                        advance()
                    } else if mod == "_" {
                        octave -= 1
                        advance()
                    } else {
                        break
                    }
                }
                return .note(Note(accidental: accidental, degree: degree, octave: octave))
            }
        }

        // Number (integer or double) or identifier
        if (c >= "0" && c <= "9")
            || (c == "+" && (peek(offset: 1).map { $0 >= "0" && $0 <= "9" } ?? false))
        {
            var numStr = ""
            if c == "+" {
                numStr.append(Character(advance()!))
            }
            var hasDot = false
            while !isAtEnd {
                guard let cur = peek() else { break }
                if cur >= "0" && cur <= "9" {
                    numStr.append(Character(advance()!))
                } else if cur == "." && !hasDot {
                    if let afterDot = peek(offset: 1), afterDot >= "0" && afterDot <= "9" {
                        hasDot = true
                        numStr.append(Character(advance()!))
                    } else {
                        break
                    }
                } else {
                    break
                }
            }

            if hasDot, let d = Double(numStr) {
                return .double(d)
            } else if let i = Int(numStr) {
                return c == "+" ? .positiveNumber(i) : .number(i)
            }
        }

        // Identifier or text token (allows hyphens internal to names like Chorus-1 and sharps like F#m)
        var idStr = ""
        let stops = Set(" \t\r\n:!=?*<>/|{}()[]@,+".unicodeScalars)
        while !isAtEnd {
            guard let cur = peek() else { break }
            if stops.contains(cur) {
                break
            }
            if cur == "#" && idStr.isEmpty {
                // If # stands alone or starts token, check if it's -># (which is handled earlier) or single #
                break
            }
            if cur == "-" && (peek(offset: 1) == ">" || peek(offset: 1) == " ") {
                break
            }
            idStr.append(Character(advance()!))
        }

        if !idStr.isEmpty {
            return .identifier(idStr)
        }

        // Fallback: single character identifier
        advance()
        return .identifier(String(Character(c)))
    }
}
