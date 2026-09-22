import Foundation
import TmdUtils

// MARK: - Token Definitions

public enum Token: Equatable, Sendable {
    case scoreHeader                 // ::SCORE::
    case doubleAsterisk              // **
    case speedPrefix                 // !=
    case relativeTempoPrefix         // !+
    case keySignaturePrefix          // ?=
    case openAngle                   // <
    case slash                       // /
    case asterisk                    // *
    case closeAngle                  // >
    case colon                       // :
    case at                          // @
    case pipe                        // |
    case openBrace                   // {
    case closeBrace                  // }
    case openParen                   // (
    case closeParen                  // )
    case percentOpenParen            // %(
    case arrow                       // ->
    case arrowEnd                    // ->#
    case relativeOrderPrefix         // {?
    case absoluteOrderPrefix         // {?=

    case number(Int)                 // e.g. 120, 4, 16
    case positiveNumber(Int)         // e.g. +4, +30
    case double(Double)              // e.g. 120.0
    case note(Note)                  // e.g. 1, 1', 1,, 1^, 1_
    case chord(String)               // e.g. [Cmaj7], [1], [6m]
    case percussion(String)           // e.g. XsTt
    case metadata(String, String)     // metadata key and value
    case programText(String)           // triple-quoted show-program body
    case tie                         // -
    case identifier(String)          // e.g. Piano, intro, C, A'
    case eof

    public var expectedDescription: String {
        switch self {
        case .scoreHeader: return "::SCORE::"
        case .doubleAsterisk: return "**"
        case .speedPrefix: return "!="
        case .relativeTempoPrefix: return "!+"
        case .keySignaturePrefix: return "?="
        case .openAngle: return "<"
        case .slash: return "/"
        case .asterisk: return "*"
        case .closeAngle: return ">"
        case .colon: return ":"
        case .at: return "@"
        case .pipe: return "|"
        case .openBrace: return "{"
        case .closeBrace: return "}"
        case .openParen: return "("
        case .closeParen: return ")"
        case .percentOpenParen: return "%("
        case .arrow: return "->"
        case .arrowEnd: return "->#"
        case .relativeOrderPrefix: return "{?"
        case .absoluteOrderPrefix: return "{?="
        case .number: return "number"
        case .positiveNumber: return "positive number"
        case .double: return "decimal number"
        case .note: return "note"
        case .chord: return "chord"
        case .percussion: return "percussion"
        case .metadata: return "metadata"
        case .programText: return "program block"
        case .tie: return "-"
        case .identifier: return "identifier"
        case .eof: return "end of input"
        }
    }
}

/// A source position measured in both scalar offset and human-readable line/column.
public struct SourcePosition: Equatable, Sendable {
    public let offset: Int
    public let line: Int
    public let column: Int
}

/// The source span occupied by a token.
public struct SourceRange: Equatable, Sendable {
    public let start: SourcePosition
    public let length: Int

    public var endOffset: Int { start.offset + length }
}

/// A token together with its source text and location.
public struct LexedToken: Equatable {
    public let token: Token
    public let text: String
    public let range: SourceRange
}

/// A syntax error reported by the throwing parser API.
public struct TMDParseError: Error, Equatable, CustomStringConvertible, LocalizedError {
    public let message: String
    public let token: Token
    public let text: String
    public let range: SourceRange
    public let expectedTokens: [String]

    public init(
        message: String,
        token: Token,
        text: String,
        range: SourceRange,
        expectedTokens: [String] = []
    ) {
        self.message = message
        self.token = token
        self.text = text
        self.range = range
        self.expectedTokens = expectedTokens
    }

    public var errorDescription: String? { description }

    public var description: String {
        var desc = "\(message) at \(range.start.line):\(range.start.column): `\(text)`"
        if !expectedTokens.isEmpty {
            desc += " (expected \(expectedTokens.joined(separator: ", ")))"
        }
        return desc
    }
}

// MARK: - Lexer

public final class Lexer {
    private static let metadataKeyByPrefix = [
        "詞：": "lyrics",
        "曲：": "composer",
        "編：": "arranger"
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
                advance() // /
                advance() // *
                while !isAtEnd {
                    if peek() == "*" && peek(offset: 1) == "/" {
                        advance() // *
                        advance() // /
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
            tokens.append(LexedToken(token: token, text: text, range: SourceRange(start: position, length: index - start)))
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
            advance(); advance(); advance()
            var body = ""
            while !isAtEnd && !(peek() == "\"" && peek(offset: 1) == "\"" && peek(offset: 2) == "\"") {
                body.append(Character(advance()!))
            }
            if !isAtEnd { advance(); advance(); advance() }
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
            if named { advance(); advance() } else { advance() }
            while peek() == " " || peek() == "\t" { advance() }
            var key = "credit"
            if named {
                if peek() == ":" { advance() }
                while peek() == " " || peek() == "\t" { advance() }
                if peek() == "_" {
                    while peek() == "_" { advance() }
                    key = ""
                    while let ch = peek(), ch != "_" && ch != "=" && ch != " " && ch != "\t" && ch != "\"" {
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
                advance(); advance(); advance()
                return .arrowEnd
            } else {
                advance(); advance()
                return .arrow
            }
        }

        // {?= or {?
        if c == "{" && peek(offset: 1) == "?" {
            if peek(offset: 2) == "=" {
                advance(); advance(); advance()
                return .absoluteOrderPrefix
            } else {
                advance(); advance()
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

        // **
        if c == "*" && peek(offset: 1) == "*" {
            advance(); advance()
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
        case "[":
            // Chord: [Cmaj7]
            advance() // [
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
                guard let degree = ScaleDegree(rawValue: Int(c.value - UnicodeScalar("0").value)) else {
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
        if (c >= "0" && c <= "9") || (c == "+" && (peek(offset: 1).map { $0 >= "0" && $0 <= "9" } ?? false)) {
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

        // Identifier or text token (allows hyphens internal to names like Chorus-1)
        var idStr = ""
        let stops = Set(" \t\r\n:!=?*<>/|{}()[]@#,".unicodeScalars)
        while !isAtEnd {
            guard let cur = peek() else { break }
            if stops.contains(cur) {
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

// MARK: - Parser

public struct TmdParser {
    /// Parses a TMD score from a text string.
    public static func parse(string: String) -> Sheet? {
        let lexer = Lexer(string: string)
        let tokens = lexer.tokenize()
        var parser = TokenParser(tokens: tokens)
        return parser.parseSheet()
    }

    /// Parses a TMD score and reports the offending token when syntax is invalid.
    public static func parseThrowing(string: String) throws -> Sheet {
        let lexedTokens = Lexer(string: string).tokenizeWithRanges()
        var parser = TokenParser(tokens: lexedTokens.map(\.token))
        guard let sheet = parser.parseSheet() else {
            let index = diagnosticIndex(parser.failureIndex ?? parser.position, tokenCount: lexedTokens.count)
            let offending = lexedTokens[index]
            throw TMDParseError(
                message: "Unexpected token",
                token: offending.token,
                text: offending.text,
                range: offending.range,
                expectedTokens: parser.expectedTokens
            )
        }
        if let failureIndex = parser.failureIndex {
            let index = diagnosticIndex(failureIndex, tokenCount: lexedTokens.count)
            let offending = lexedTokens[index]
            throw TMDParseError(
                message: "Unexpected token",
                token: offending.token,
                text: offending.text,
                range: offending.range,
                expectedTokens: parser.expectedTokens
            )
        }
        return sheet
    }

    private static func diagnosticIndex(_ index: Int, tokenCount: Int) -> Int {
        guard tokenCount > 1 else { return 0 }
        return min(index == tokenCount - 1 ? index - 1 : index, tokenCount - 1)
    }

    /// Parses encoded data and reports decoding or syntax failures.
    public static func parseThrowing(data: Data) throws -> Sheet {
        guard let result = TextEncodingDetector.detectAndDecode(data) else {
            throw TMDParseError(
                message: "Unable to decode source",
                token: .eof,
                text: "",
                range: SourceRange(start: SourcePosition(offset: 0, line: 1, column: 1), length: 0)
            )
        }
        return try parseThrowing(string: result.content)
    }

    /// Parses a file URL and reports syntax failures with source locations.
    public static func parseThrowing(url: URL) throws -> Sheet {
        try parseThrowing(data: Data(contentsOf: url))
    }

    /// Parses a path or `file://` URL and reports syntax failures with source locations.
    public static func parseThrowing(filePathOrURL: String) throws -> Sheet {
        let cleanPath = FilePathNormalizer.fileURLToPath(filePathOrURL)
        return try parseThrowing(url: URL(fileURLWithPath: cleanPath))
    }

    /// Parses a TMD score from raw byte data, automatically detecting character encoding (UTF-8, Big5, GB18030, etc.).
    public static func parse(data: Data) -> Sheet? {
        guard let result = TextEncodingDetector.detectAndDecode(data) else {
            return nil
        }
        return parse(string: result.content)
    }

    /// Parses a TMD score from a file URL or remote URL.
    public static func parse(url: URL) throws -> Sheet? {
        let data = try Data(contentsOf: url)
        return parse(data: data)
    }

    /// Parses a TMD score from a path string or `file://` URL string, normalizing path and decoding encoding.
    public static func parse(filePathOrURL: String) throws -> Sheet? {
        let cleanPath = FilePathNormalizer.fileURLToPath(filePathOrURL)
        let url = URL(fileURLWithPath: cleanPath)
        return try parse(url: url)
    }
}

private struct TokenParser {
    private let tokens: [Token]
    private var pos: Int = 0
    private(set) var failureIndex: Int?
    private(set) var expectedTokens: [String] = []

    var position: Int { pos }

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    private var current: Token {
        if pos < tokens.count {
            return tokens[pos]
        }
        return .eof
    }

    @discardableResult
    private mutating func advance() -> Token {
        let tok = current
        if pos < tokens.count {
            pos += 1
        }
        return tok
    }

    private mutating func recordFailure(at index: Int, expected: [String]) {
        if failureIndex == nil || index >= (failureIndex ?? 0) {
            failureIndex = index
            expectedTokens = expected
        }
    }

    private mutating func recordFailure(at index: Int, expected: Token) {
        recordFailure(at: index, expected: [expected.expectedDescription])
    }

    @discardableResult
    private mutating func match(_ expected: Token) -> Bool {
        if current == expected {
            pos += 1
            return true
        }
        return false
    }

    @discardableResult
    private mutating func require(_ expected: Token) -> Bool {
        if match(expected) {
            return true
        }
        recordFailure(at: pos, expected: expected)
        return false
    }

    private mutating func skipPipes() {
        while current == .pipe {
            pos += 1
        }
    }

    mutating func parseSheet() -> Sheet? {
        guard require(.scoreHeader) else {
            return nil
        }

        var name = ""
        var speed = 0.0
        var keySignature = KeySignature()
        var beat = Beat()
        var paragraphs: [Paragraph] = []
        var orders: [Order] = []
        var metadata: [String: String] = [:]

        while current != .eof {
            switch current {
            case .doubleAsterisk:
                advance()
                // Name may consist of multiple tokens until next doubleAsterisk
                var nameParts: [String] = []
                while current != .doubleAsterisk && current != .eof {
                    switch advance() {
                    case .identifier(let s): nameParts.append(s)
                    case .number(let n): nameParts.append(String(n))
                    case .positiveNumber(let n): nameParts.append(String(n))
                    case .note(let note): nameParts.append(String(note.degree.rawValue))
                    default: break
                    }
                }
                match(.doubleAsterisk)
                name = nameParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)

            case .metadata(let key, let value):
                advance()
                metadata[key] = value

            case .speedPrefix:
                advance()
                if case .double(let d) = current {
                    speed = d
                    advance()
                } else if case .number(let n) = current {
                    speed = Double(n)
                    advance()
                } else if case .positiveNumber(let n) = current {
                    speed = Double(n)
                    advance()
                }

            case .keySignaturePrefix:
                advance()
                var key = ""
                if case .identifier(let s) = current {
                    key = s
                    advance()
                } else if case .note(let note) = current {
                    key = String(note.degree.rawValue)
                    advance()
                }
                keySignature = KeySignature(string: key)

            case .openAngle:
                advance()
                if case .number(let c) = current {
                    beat = Beat(count: c, noteValue: beat.noteValue)
                    advance()
                } else if case .note(let note) = current {
                    beat = Beat(count: note.degree.rawValue, noteValue: beat.noteValue)
                    advance()
                }
                match(.slash)
                if case .number(let n) = current {
                    beat = Beat(count: beat.count, noteValue: n)
                    advance()
                } else if case .note(let note) = current {
                    beat = Beat(count: beat.count, noteValue: note.degree.rawValue)
                    advance()
                }
                match(.closeAngle)

            case .arrow:
                advance()
                switch current {
                case .arrowEnd:
                    advance()
                    break
                case .relativeOrderPrefix:
                    advance()
                    var name = ""
                    while current != .closeBrace && current != .eof {
                        switch advance() {
                        case .identifier(let s): name += s
                        case .number(let n): name += String(n)
                        case .positiveNumber(let n): name += "+\(n)"
                        case .note(let note): name += String(note.degree.rawValue)
                        case .tie: name += "-"
                        default: break
                        }
                    }
                    match(.closeBrace)
                    orders.append(.relative(name))
                case .absoluteOrderPrefix:
                    advance()
                    var name = ""
                    while current != .closeBrace && current != .eof {
                        switch advance() {
                        case .identifier(let s): name += s
                        case .number(let n): name += String(n)
                        case .positiveNumber(let n): name += "+\(n)"
                        case .note(let note): name += String(note.degree.rawValue)
                        case .tie: name += "-"
                        default: break
                        }
                    }
                    match(.closeBrace)
                    orders.append(.absolute(name))
                case .identifier(let s):
                    advance()
                    if s == "#" {
                        break
                    }
                    orders.append(.name(s))
                default:
                    advance()
                }

            case .arrowEnd:
                advance()
                break

            default:
                // Paragraph: name:instrument@|start|{ ... }
                if let paragraph = parseParagraph() {
                    paragraphs.append(paragraph)
                } else {
                    if failureIndex == nil {
                        recordFailure(at: pos, expected: [Token.colon.expectedDescription])
                    }
                    return nil
                }
            }
        }

        return Sheet(name: name, speed: speed, keySignature: keySignature, beat: beat, paragraphs: paragraphs, orders: orders, metadata: metadata)
    }

    private mutating func parseParagraph() -> Paragraph? {
        var name = ""
        if case .identifier(let s) = current {
            name = s
            advance()
        }

        guard require(.colon) else {
            return nil
        }

        var instrument = ""
        if case .identifier(let s) = current {
            instrument = s
            advance()
        }

        guard require(.at) else {
            return nil
        }

        var start = 0
        var executionTime: String?
        if match(.pipe) {
            if current == .tie {
                advance()
                if case .number(let n) = current {
                    start = -n
                    advance()
                } else if case .note(let note) = current {
                    start = -note.degree.rawValue
                    advance()
                } else if case .positiveNumber(let n) = current {
                    start = n
                    advance()
                }
            } else if case .number(let n) = current {
                start = n
                advance()
            } else if case .positiveNumber(let n) = current {
                start = n
                advance()
            } else if case .note(let note) = current {
                start = note.degree.rawValue
                advance()
            }
            match(.pipe)
        } else if case .identifier(let time) = current {
            executionTime = time
            advance()
        }

        guard require(.openBrace) else {
            return nil
        }

        if case .programText(let body) = current {
            advance()
            match(.closeBrace)
            return Paragraph(name: name, instrument: instrument, start: start, sections: [], executionTime: executionTime, showProgram: body)
        }

        var sections: [Section] = []
        while current != .closeBrace && current != .eof {
            skipPipes()
            if current == .openAngle {
                advance()
                var noteLength = 4
                if case .number(let n) = current {
                    noteLength = n
                    advance()
                } else if case .note(let note) = current {
                    noteLength = note.degree.rawValue
                    advance()
                } else if current == .asterisk {
                    // Legacy spelling: <*1>
                    advance()
                    if case .number(let n) = current {
                        noteLength = n
                        advance()
                    } else if case .note(let note) = current {
                        noteLength = note.degree.rawValue
                        advance()
                    }
                }
                match(.asterisk)
                match(.closeAngle)

                var unitGroups: [UnitGroup] = []
                var directives: [SectionDirective] = []
                while current != .openAngle && current != .closeBrace && current != .eof {
                    skipPipes()
                    if current == .openAngle || current == .closeBrace || current == .eof {
                        break
                    }

                    if current == .openBrace || current == .relativeOrderPrefix || current == .absoluteOrderPrefix || current == .keySignaturePrefix || current == .relativeTempoPrefix {
                        if let directive = parseSectionDirective(position: unitGroups.reduce(0) { $0 + $1.length }) {
                            directives.append(directive)
                        } else {
                            advance()
                        }
                        continue
                    }

                    if match(.openParen) {
                        skipPipes()
                        var groupUnits: [Unit] = []
                        while current != .closeParen && current != .eof {
                            skipPipes()
                            if current == .closeParen { break }
                            let units = parseUnits()
                            if !units.isEmpty {
                                groupUnits.append(contentsOf: units)
                            } else {
                                recordFailure(at: pos, expected: ["note", "chord", "tie", "rest", "percussion", ")"])
                                return nil
                            }
                        }
                        match(.closeParen)

                        var length = 1
                        if match(.percentOpenParen) {
                            length = 0
                            while current == .tie {
                                length += 1
                                advance()
                            }
                            match(.closeParen)
                        }
                        unitGroups.append(UnitGroup(units: groupUnits, length: length))
                    } else {
                        let units = parseUnits()
                        if !units.isEmpty {
                            for unit in units {
                                unitGroups.append(UnitGroup(units: [unit], length: 1))
                            }
                        } else {
                            recordFailure(at: pos, expected: ["note", "chord", "tie", "rest", "percussion", "tuplet", "directive", "}"])
                            return nil
                        }
                    }
                }
                sections.append(Section(noteLength: noteLength, unitGroups: unitGroups, directives: directives))
            } else {
                recordFailure(at: pos, expected: .openAngle)
                return nil
            }
        }
        match(.closeBrace)

        return Paragraph(name: name, instrument: instrument, start: start, sections: sections, executionTime: executionTime)
    }

    private mutating func parseUnits() -> [Unit] {
        skipPipes()
        if case .number(let n) = current {
            let text = String(n)
            var units: [Unit] = []
            var allValid = true
            for ch in text {
                if let d = Int(String(ch)), let degree = ScaleDegree(rawValue: d) {
                    units.append(.note(Note(accidental: .natural, degree: degree, octave: 0)))
                } else if ch == "0" {
                    units.append(.rest)
                } else {
                    allValid = false
                    break
                }
            }
            if allValid && !units.isEmpty {
                advance()
                return units
            }
        }
        if case .identifier(let value) = current, !value.isEmpty,
           let firstNonPerc = value.first(where: { !"XxTtSsDdBbOoCc".contains($0) }),
           firstNonPerc == "-",
           value.allSatisfy({ "XxTtSsDdBbOoCc-".contains($0) }) {
            // Identifier like 'x--' or 'X-x-' in percussion: split into percussion and ties
            advance()
            var units: [Unit] = []
            var percBuf = ""
            for ch in value {
                if ch == "-" {
                    if !percBuf.isEmpty {
                        units.append(.percussion(percBuf))
                        percBuf = ""
                    }
                    units.append(.tie)
                } else {
                    percBuf.append(ch)
                }
            }
            if !percBuf.isEmpty {
                units.append(.percussion(percBuf))
            }
            return units
        }
        if case .identifier(let value) = current, !value.isEmpty, value.allSatisfy({ $0 == "." }) {
            advance()
            return Array(repeating: Unit.tie, count: value.count)
        }
        if let unit = parseUnit() {
            return [unit]
        }
        return []
    }

    private mutating func parseUnit() -> Unit? {
        skipPipes()
        switch current {
        case .note(let n):
            advance()
            return .note(n)
        case .chord(let ch):
            advance()
            return .chord(ChordSymbol(string: ch))
        case .tie:
            advance()
            return .tie
        case .identifier(let value) where !value.isEmpty && value.allSatisfy({ $0 == "." }):
            advance()
            return .tie
        case .number(0):
            advance()
            return .rest
        case .percussion(let pattern):
            advance()
            return .percussion(pattern)
        case .identifier(let value) where !value.isEmpty && value.allSatisfy({ "XxTtSsDdBbOoCc".contains($0) }):
            advance()
            return .percussion(value)
        default:
            return nil

        }
    }

    private mutating func parseSectionDirective(position: Int) -> SectionDirective? {
        let startsWithBrace = match(.openBrace)
        guard startsWithBrace || current == .relativeOrderPrefix || current == .absoluteOrderPrefix || current == .keySignaturePrefix || current == .relativeTempoPrefix else { return nil }
        // `{?` and `{?=` are emitted as single lexer tokens which already
        // consume the opening brace; all directive forms still end in `}`.
        defer { match(.closeBrace) }

        switch current {
        case .relativeTempoPrefix:
            advance()
            if case .number(let value) = current {
                advance()
                return SectionDirective(position: position, kind: .relativeTempo(Double(value)))
            }
            if case .double(let value) = current {
                advance()
                return SectionDirective(position: position, kind: .relativeTempo(value))
            }
        case .speedPrefix:
            advance()
            if case .double(let value) = current {
                advance()
                return SectionDirective(position: position, kind: .tempo(value))
            }
            if case .positiveNumber(let value) = current {
                advance()
                return SectionDirective(position: position, kind: .relativeTempo(Double(value)))
            }
            if case .number(let value) = current {
                advance()
                return SectionDirective(position: position, kind: .tempo(Double(value)))
            }
        case .relativeOrderPrefix:
            advance()
            var value = ""
            while current != .closeBrace && current != .eof {
                switch advance() {
                case .number(let n): value += String(n)
                case .positiveNumber(let n): value += "+\(n)"
                case .note(let n): value += String(n.degree.rawValue)
                case .identifier(let s): value += s
                case .tie: value += "-"
                default: break
                }
            }
            if let delta = Int(value) {
                return SectionDirective(position: position, kind: .relativeKey(delta))
            }
        case .absoluteOrderPrefix:
            advance()
            var value = ""
            while current != .closeBrace && current != .eof {
                switch advance() {
                case .identifier(let s): value += s
                case .number(let n): value += String(n)
                case .positiveNumber(let n): value += "+\(n)"
                case .note(let n): value += String(n.degree.rawValue)
                default: break
                }
            }
            return SectionDirective(position: position, kind: .absoluteKey(value))
        case .keySignaturePrefix:
            advance()
            var value = ""
            if case .identifier(let s) = current { value = s; advance() }
            else if case .note(let n) = current { value = String(n.degree.rawValue); advance() }
            return SectionDirective(position: position, kind: .absoluteKey(value))
        case .openAngle:
            advance()
            var count = 4
            var noteValue = 4
            if case .number(let n) = current { count = n; advance() }
            else if case .note(let n) = current { count = n.degree.rawValue; advance() }
            match(.slash)
            if case .number(let n) = current { noteValue = n; advance() }
            else if case .note(let n) = current { noteValue = n.degree.rawValue; advance() }
            match(.closeAngle)
            return SectionDirective(position: position, kind: .timeSignature(Beat(count: count, noteValue: noteValue)))
        default:
            break
        }
        return nil
    }
}
