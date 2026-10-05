import Foundation
import TmdUtils

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
            let index = diagnosticIndex(
                parser.failureIndex ?? parser.position, tokenCount: lexedTokens.count)
            let offending = lexedTokens[index]
            throw TmdParseError(
                message: "Unexpected token",
                token: offending.token,
                text: offending.text,
                range: offending.range,
                expectedTokens: parser.expectedTokens,
                source: string
            )
        }
        if let failureIndex = parser.failureIndex {
            let index = diagnosticIndex(failureIndex, tokenCount: lexedTokens.count)
            let offending = lexedTokens[index]
            throw TmdParseError(
                message: "Unexpected token",
                token: offending.token,
                text: offending.text,
                range: offending.range,
                expectedTokens: parser.expectedTokens,
                source: string
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
            throw TmdParseError(
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
        var declaredKey: String?
        var beat = Beat()
        var entries: [Entry] = []
        var playback: [Playback] = []
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

            case .explicitKeyPrefix:
                advance()
                var key = ""
                if case .identifier(let s) = current {
                    key = s
                    advance()
                } else if case .note(let note) = current {
                    key = String(note.degree.rawValue)
                    advance()
                }
                if !key.isEmpty {
                    declaredKey = key
                }

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
                    playback.append(.relative(name))
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
                    playback.append(.absolute(name))
                case .identifier(let s):
                    advance()
                    if s == "#" {
                        break
                    }
                    playback.append(.name(s))
                case .openParen:
                    if let expr = parseSExpr() {
                        playback.append(.macro(expr))
                    } else {
                        return nil
                    }
                default:
                    advance()
                }

            case .arrowEnd:
                advance()
                break

            default:
                // Paragraph: name:instrument@|start|{ ... } or abstract prototype: Theme { ... }
                if let entry = parseEntry() {
                    entries.append(entry)
                } else {
                    if failureIndex == nil {
                        recordFailure(
                            at: pos,
                            expected: [
                                Token.colon.expectedDescription,
                                Token.openBrace.expectedDescription,
                            ])
                    }
                    return nil
                }
            }
        }

        return Sheet(
            name: name, speed: speed, keySignature: keySignature, declaredKey: declaredKey,
            beat: beat, entries: entries, playback: playback, metadata: metadata)
    }

    private mutating func parseEntry() -> Entry? {
        var name = ""
        if case .identifier(let s) = current {
            name = s
            advance()
        }

        var instrument = ""
        var pitchMode: EntryPitchMode = .transposing
        var start = 0
        var executionTime: String?

        if current == .colon {
            advance()
            if case .identifier(let s) = current {
                instrument = s
                advance()
            }

            if case .chord(let attribute) = current {
                if attribute.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    == "pitchmode=fixed"
                {
                    pitchMode = .fixed
                    advance()
                } else {
                    recordFailure(at: pos, expected: ["pitchMode=fixed"])
                    return nil
                }
            }

            guard require(.at) else {
                return nil
            }

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
                        if n == 0 {
                            recordFailure(at: pos, expected: ["positive non-zero entry offset"])
                            return nil
                        }
                        start = n
                        advance()
                    }
                } else if case .number(let n) = current {
                    start = n
                    advance()
                } else if case .positiveNumber(let n) = current {
                    if n == 0 {
                        recordFailure(at: pos, expected: ["positive non-zero entry offset"])
                        return nil
                    }
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
        } else {
            // Abstract paragraph declaration without instrument binding: Theme { ... }
            if current != .openBrace {
                recordFailure(at: pos, expected: [Token.colon.expectedDescription])
                return nil
            }
            advance()
        }

        if case .programText(let body) = current {
            advance()
            match(.closeBrace)
            return Entry(
                name: name, assignment: instrument.isEmpty ? nil : instrument, pitchMode: pitchMode,
                start: start, sections: [], executionTime: executionTime, showProgram: body)
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
                var barlinePositions: [Int] = []
                while current != .openAngle && current != .closeBrace && current != .eof {
                    while current == .pipe {
                        barlinePositions.append(unitGroups.reduce(0) { $0 + $1.length })
                        advance()
                    }
                    if current == .openAngle || current == .closeBrace || current == .eof {
                        break
                    }

                    if current == .openBrace || current == .relativeOrderPrefix
                        || current == .absoluteOrderPrefix || current == .keySignaturePrefix
                        || current == .relativeTempoPrefix
                    {
                        if let directive = parseSectionDirective(
                            position: unitGroups.reduce(0) { $0 + $1.length })
                        {
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
                                recordFailure(
                                    at: pos,
                                    expected: ["note", "chord", "tie", "rest", "percussion", ")"])
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
                            recordFailure(
                                at: pos,
                                expected: [
                                    "note", "chord", "tie", "rest", "percussion", "tuplet",
                                    "directive", "}",
                                ])
                            return nil
                        }
                    }
                }
                sections.append(
                    Section(
                        noteLength: noteLength, unitGroups: unitGroups, directives: directives,
                        barlinePositions: barlinePositions))
            } else {
                recordFailure(at: pos, expected: .openAngle)
                return nil
            }
        }
        match(.closeBrace)

        if instrument.isEmpty && sections.contains(where: { !$0.directives.isEmpty }) {
            recordFailure(at: pos, expected: ["prototype without modifiers"])
            return nil
        }

        return Entry(
            name: name, assignment: instrument.isEmpty ? nil : instrument, pitchMode: pitchMode,
            start: start, sections: sections, executionTime: executionTime)
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
            value.allSatisfy({ "XxTtSsDdBbOoCc-".contains($0) })
        {
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
            let isNextPositiveNumber: Bool = {
                if case .positiveNumber = current { return true }
                return false
            }()
            if current == .plus || isNextPositiveNumber {
                var notes = [n]
                while true {
                    if match(.plus) {
                        if case .note(let nextNote) = current {
                            notes.append(nextNote)
                            advance()
                        } else if case .number(let num) = current,
                            let degree = ScaleDegree(rawValue: num)
                        {
                            notes.append(Note(accidental: .natural, degree: degree, octave: 0))
                            advance()
                        } else {
                            recordFailure(at: pos, expected: ["note"])
                            return nil
                        }
                    } else if case .positiveNumber(let num) = current {
                        if let degree = ScaleDegree(rawValue: num) {
                            notes.append(Note(accidental: .natural, degree: degree, octave: 0))
                            advance()
                        } else {
                            recordFailure(at: pos, expected: ["note"])
                            return nil
                        }
                    } else {
                        break
                    }
                }
                return notes.count > 1 ? .multiNote(notes) : .note(n)
            }
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
        case .identifier(let value)
        where !value.isEmpty && value.allSatisfy({ "XxTtSsDdBbOoCc".contains($0) }):
            advance()
            return .percussion(value)
        default:
            return nil

        }
    }

    private mutating func parseSectionDirective(position: Int) -> SectionDirective? {
        let startsWithBrace = match(.openBrace)
        guard
            startsWithBrace || current == .relativeOrderPrefix || current == .absoluteOrderPrefix
                || current == .keySignaturePrefix || current == .relativeTempoPrefix
        else { return nil }
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
            } else if value.lowercased() == "fixed" {
                recordFailure(at: position, expected: ["entry attribute [pitchMode=fixed]"])
                return nil
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
            if value.lowercased() == "fixed" {
                recordFailure(at: position, expected: ["entry attribute [pitchMode=fixed]"])
                return nil
            }
            return SectionDirective(position: position, kind: .absoluteKey(value))
        case .keySignaturePrefix:
            advance()
            var value = ""
            if case .identifier(let s) = current {
                value = s
                advance()
            } else if case .note(let n) = current {
                value = String(n.degree.rawValue)
                advance()
            }
            if value.lowercased() == "fixed" {
                recordFailure(at: position, expected: ["entry attribute [pitchMode=fixed]"])
                return nil
            }
            return SectionDirective(position: position, kind: .absoluteKey(value))
        case .explicitKeyPrefix:
            advance()
            var value = ""
            if case .identifier(let s) = current {
                value = s
                advance()
            } else if case .note(let n) = current {
                value = String(n.degree.rawValue)
                advance()
            }
            if !value.isEmpty {
                return SectionDirective(position: position, kind: .explicitKey(value))
            }
        case .identifier(let s):
            if let dyn = DynamicMark(rawValue: s.lowercased()) {
                advance()
                return SectionDirective(position: position, kind: .dynamics(dyn))
            }
        case .openAngle:
            advance()
            var count = 4
            var noteValue = 4
            if case .number(let n) = current {
                count = n
                advance()
            } else if case .note(let n) = current {
                count = n.degree.rawValue
                advance()
            }
            match(.slash)
            if case .number(let n) = current {
                noteValue = n
                advance()
            } else if case .note(let n) = current {
                noteValue = n.degree.rawValue
                advance()
            }
            match(.closeAngle)
            return SectionDirective(
                position: position, kind: .timeSignature(Beat(count: count, noteValue: noteValue)))
        default:
            break
        }
        return nil
    }

    private mutating func parseSExpr() -> SExpr? {
        guard require(.openParen) else { return nil }
        var items: [SExpr] = []
        while current != .closeParen && current != .eof {
            if current == .arrow || current == .arrowEnd {
                recordFailure(at: pos, expected: .closeParen)
                return nil
            }
            if current == .openParen {
                guard let sub = parseSExpr() else { return nil }
                items.append(sub)
            } else {
                switch current {
                case .number(let n):
                    advance()
                    items.append(.number(n))
                case .positiveNumber(let n):
                    advance()
                    items.append(.number(n))
                case .identifier(let s):
                    advance()
                    items.append(.symbol(s))
                case .note(let note):
                    advance()
                    if note.accidental == .natural && note.octave == 0 {
                        items.append(.number(note.degree.rawValue))
                    } else {
                        items.append(.symbol(note.format()))
                    }
                case .tie:
                    // Negative number like -12, or standalone symbol
                    advance()
                    if case .number(let n) = current {
                        advance()
                        items.append(.number(-n))
                    } else if case .note(let note) = current {
                        advance()
                        items.append(.number(-note.degree.rawValue))
                    } else {
                        items.append(.symbol("-"))
                    }
                case .chord(let chordStr):
                    advance()
                    items.append(.symbol(chordStr))
                case .percussion(let pat):
                    advance()
                    items.append(.symbol(pat))
                default:
                    let desc = current.expectedDescription
                    advance()
                    items.append(.symbol(desc))
                }
            }
        }
        guard require(.closeParen) else { return nil }
        return .list(items)
    }
}
