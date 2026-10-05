import Foundation

// MARK: - LSP Data Structures

public struct TmdLSPPosition: Codable, Equatable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct TmdLSPRange: Codable, Equatable, Sendable {
    public let start: TmdLSPPosition
    public let end: TmdLSPPosition

    public init(start: TmdLSPPosition, end: TmdLSPPosition) {
        self.start = start
        self.end = end
    }
}

public enum TmdLSPCompletionItemKind: Int, Codable, Sendable {
    case text = 1
    case method = 2
    case function = 3
    case constructor = 4
    case field = 5
    case variable = 6
    case `class` = 7
    case interface = 8
    case module = 9
    case property = 10
    case unit = 11
    case value = 12
    case `enum` = 13
    case keyword = 14
    case snippet = 15
    case color = 16
    case file = 17
    case reference = 18
}

public enum TmdLSPSymbolKind: Int, Codable, Sendable {
    case file = 1
    case module = 2
    case namespace = 3
    case package = 4
    case `class` = 5
    case method = 6
    case property = 7
    case field = 8
    case constructor = 9
    case `enum` = 10
    case interface = 11
    case function = 12
    case variable = 13
    case constant = 14
    case string = 15
    case number = 16
    case boolean = 17
    case array = 18
    case object = 19
    case key = 20
    case null = 21
    case enumMember = 22
    case structKind = 23
    case event = 24
    case `operator` = 25
    case typeParameter = 26

    public static func from(outlineKind: String) -> TmdLSPSymbolKind {
        switch outlineKind.lowercased() {
        case "file": return .file
        case "namespace": return .namespace
        case "class": return .class
        case "method": return .method
        case "property": return .property
        case "field": return .field
        case "event": return .event
        case "operator": return .operator
        case "string": return .string
        case "number": return .number
        default: return .variable
        }
    }
}

public struct TmdLSPCompletionItem: Codable, Equatable, Sendable {
    public let label: String
    public let kind: TmdLSPCompletionItemKind
    public let detail: String?
    public let documentation: String?
    public let insertText: String?
    public let insertTextFormat: Int?  // 1: PlainText, 2: Snippet

    public init(
        label: String,
        kind: TmdLSPCompletionItemKind,
        detail: String? = nil,
        documentation: String? = nil,
        insertText: String? = nil,
        insertTextFormat: Int? = nil
    ) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.documentation = documentation
        self.insertText = insertText
        self.insertTextFormat = insertTextFormat
    }
}

public struct TmdLSPDiagnostic: Codable, Equatable, Sendable {
    public let range: TmdLSPRange
    public let severity: Int  // 1: Error, 2: Warning, 3: Information, 4: Hint
    public let source: String?
    public let message: String

    public init(range: TmdLSPRange, severity: Int = 1, source: String? = "tmd", message: String) {
        self.range = range
        self.severity = severity
        self.source = source
        self.message = message
    }
}

