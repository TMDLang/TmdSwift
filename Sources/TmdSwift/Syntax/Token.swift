import Foundation

// MARK: - Token Definitions

public enum Token: Equatable, Sendable {
    case scoreHeader  // ::SCORE::
    case doubleAsterisk  // **
    case speedPrefix  // !=
    case relativeTempoPrefix  // !+
    case keySignaturePrefix  // ?=
    case explicitKeyPrefix  // key= or Key=
    case openAngle  // <
    case slash  // /
    case asterisk  // *
    case closeAngle  // >
    case colon  // :
    case at  // @
    case pipe  // |
    case openBrace  // {
    case closeBrace  // }
    case openParen  // (
    case closeParen  // )
    case percentOpenParen  // %(
    case arrow  // ->
    case arrowEnd  // ->#
    case relativeOrderPrefix  // {?
    case absoluteOrderPrefix  // {?=

    case number(Int)  // e.g. 120, 4, 16
    case positiveNumber(Int)  // e.g. +4, +30
    case double(Double)  // e.g. 120.0
    case note(Note)  // e.g. 1, 1', 1,, 1^, 1_
    case chord(String)  // e.g. [Cmaj7], [1], [6m]
    case percussion(String)  // e.g. XsTt
    case metadata(String, String)  // metadata key and value
    case programText(String)  // triple-quoted show-program body
    case tie  // -
    case plus  // +
    case identifier(String)  // e.g. Piano, intro, C, A'
    case eof

    public var expectedDescription: String {
        switch self {
        case .scoreHeader: return "::SCORE::"
        case .doubleAsterisk: return "**"
        case .speedPrefix: return "!="
        case .relativeTempoPrefix: return "!+"
        case .keySignaturePrefix: return "?="
        case .explicitKeyPrefix: return "key="
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
        case .plus: return "+"
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

public let fullwidthPunctuationMap: [String: String] = [
    "（": "(",
    "）": ")",
    "｛": "{",
    "｝": "}",
    "【": "[",
    "】": "]",
    "：": ":",
    "｜": "|",
    "－": "-",
    "，": ",",
    "、": ",",
    "？": "?",
    "！": "!",
    "＊": "*",
    "／": "/",
    "＜": "<",
    "＞": ">",
]

public let fullwidthPunctuationOrder: [String] = [
    "（", "）", "｛", "｝", "【", "】", "：", "｜", "－", "，", "、", "？", "！", "＊", "／", "＜", "＞",
]
