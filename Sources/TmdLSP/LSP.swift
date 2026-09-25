import Foundation
import TmdSwift

// MARK: - LSP Data Structures

public struct TMDLSPPosition: Codable, Equatable, Sendable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

public struct TMDLSPRange: Codable, Equatable, Sendable {
    public let start: TMDLSPPosition
    public let end: TMDLSPPosition

    public init(start: TMDLSPPosition, end: TMDLSPPosition) {
        self.start = start
        self.end = end
    }
}

public enum TMDLSPCompletionItemKind: Int, Codable, Sendable {
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

public enum TMDLSPSymbolKind: Int, Codable, Sendable {
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

    public static func from(outlineKind: String) -> TMDLSPSymbolKind {
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

public struct TMDLSPCompletionItem: Codable, Equatable, Sendable {
    public let label: String
    public let kind: TMDLSPCompletionItemKind
    public let detail: String?
    public let documentation: String?
    public let insertText: String?
    public let insertTextFormat: Int? // 1: PlainText, 2: Snippet

    public init(
        label: String,
        kind: TMDLSPCompletionItemKind,
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

public struct TMDLSPDiagnostic: Codable, Equatable, Sendable {
    public let range: TMDLSPRange
    public let severity: Int // 1: Error, 2: Warning, 3: Information, 4: Hint
    public let source: String?
    public let message: String

    public init(range: TMDLSPRange, severity: Int = 1, source: String? = "tmd", message: String) {
        self.range = range
        self.severity = severity
        self.source = source
        self.message = message
    }
}

// MARK: - JSON-RPC Frame & Codec

public struct TMDJSONRPCFrame: @unchecked Sendable {
    public let id: Int?
    public let method: String?
    public let params: Any?

    public init(id: Int?, method: String?, params: Any? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct TMDJSONRPCResponse: @unchecked Sendable {
    public let id: Int?
    public let result: Any?
    public let error: Any?

    public init(id: Int?, result: Any? = nil, error: Any? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct TMDJSONRPCCodec {
    public static func decode(_ input: String) -> [TMDJSONRPCFrame] {
        var buffer = Data(input.utf8)
        return decode(buffer: &buffer)
    }

    public static func decode(buffer: inout Data) -> [TMDJSONRPCFrame] {
        var frames: [TMDJSONRPCFrame] = []
        let separator = Data("\r\n\r\n".utf8)

        while let range = buffer.range(of: separator) {
            let headerData = buffer.subdata(in: 0..<range.lowerBound)
            let headerStr = String(data: headerData, encoding: .utf8) ?? ""

            var contentLength: Int? = nil
            for line in headerStr.components(separatedBy: "\r\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 && parts[0].lowercased() == "content-length" {
                    contentLength = Int(parts[1])
                }
            }

            guard let length = contentLength else {
                break
            }

            let bodyStart = range.upperBound
            let bodyEnd = bodyStart + length
            guard buffer.count >= bodyEnd else {
                break
            }

            let bodyData = buffer.subdata(in: bodyStart..<bodyEnd)
            buffer = buffer.subdata(in: bodyEnd..<buffer.count)

            if let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                let id = obj["id"] as? Int
                let method = obj["method"] as? String
                let params = obj["params"]
                frames.append(TMDJSONRPCFrame(id: id, method: method, params: params))
            }
        }
        return frames
    }

    public static func encode(_ response: TMDJSONRPCResponse) -> String {
        var dict: [String: Any] = [
            "jsonrpc": "2.0"
        ]
        if let id = response.id {
            dict["id"] = id
        } else {
            dict["id"] = NSNull()
        }
        if let result = response.result {
            dict["result"] = result
        }
        if let error = response.error {
            dict["error"] = error
        }
        return encodePayload(dict)
    }

    public static func encode(method: String, params: Any) -> String {
        let dict: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        return encodePayload(dict)
    }

    private static func encodePayload(_ dict: [String: Any]) -> String {
        var options: JSONSerialization.WritingOptions = []
        if #available(macOS 10.15, *) {
            options.insert(.withoutEscapingSlashes)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: options),
              let jsonStr = String(data: data, encoding: .utf8) else {
            return ""
        }
        let length = jsonStr.utf8.count
        return "Content-Length: \(length)\r\n\r\n\(jsonStr)"
    }
}

// MARK: - Completion Engine

public struct TMDLSPCompletionEngine {
    public static let standardInstruments: [String] = [
        // Keyboard & Piano
        "Piano", "AcousticGrandPiano", "BrightAcousticPiano", "ElectricGrandPiano", "HonkyTonkPiano", "ElectricPiano", "Harpsichord", "Clavinet",
        // Strings
        "Violin", "Viola", "Cello", "Contrabass", "Strings", "StringEnsemble", "PizzicatoStrings", "OrchestralHarp",
        // Guitars & Bass
        "AcousticGuitar", "NylonGuitar", "SteelGuitar", "CleanGuitar", "OverdrivenGuitar", "DistortionGuitar",
        "Bass", "AcousticBass", "ElectricBass", "ElectricBassFinger", "ElectricBassPick", "SlapBass", "SynthBass",
        // Brass & Woodwinds
        "Trumpet", "Trombone", "Tuba", "MutedTrumpet", "FrenchHorn", "BrassSection",
        "SopranoSax", "AltoSax", "TenorSax", "BaritoneSax", "Oboe", "EnglishHorn", "Bassoon", "Clarinet", "Piccolo", "Flute", "PanFlute",
        // Voices
        "Vocal", "Choir", "VoiceOohs", "SynthVoice",
        // Percussion
        "Drums", "Percussion", "Timpani", "SteelDrums", "TaikoDrum", "MelodicTom"
    ]

    public static let macroSnippets: [(label: String, insertText: String, detail: String)] = [
        ("canon", "(canon ${1:Theme} (${2:Violin1 Violin2}) ${3:2})", "Polyphonic Canon: (canon <theme> (<instruments...>) <offset_bars>)"),
        ("loop", "(loop ${1:Theme} ${2:Cello} ${3:4})", "Sequential Loop: (loop <theme> <instrument> <times>) or (loop <section> <times>)"),
        ("layer", "(layer\n\t${1:expr1}\n\t${2:expr2})", "Parallel Concurrency: (layer <expr1> <expr2> ...)"),
        ("seq", "(seq\n\t${1:expr1}\n\t${2:expr2})", "Sequential Chain: (seq <expr1> <expr2> ...)"),
        ("reverse", "(reverse ${1:Theme})", "Retrograde Inversion: (reverse <theme|expr>)"),
        ("flip", "(flip ${1:Theme})", "Melodic Inversion: (flip <theme|expr> [axis])"),
        ("transpose", "(transpose ${1:Theme} ${2:7})", "Semitone Transposition: (transpose <theme|expr> <semitones>)"),
        ("vary", "(vary ${1:Theme} ${2:reverse} ${3:12})", "Chained Transformations: (vary <theme> <trans1> ...)"),
        ("minor", "(minor ${1:Theme})", "Parallel Minor Modal Transform: (minor <theme>)"),
        ("major", "(major ${1:Theme})", "Parallel Major Modal Transform: (major <theme>)"),
        ("play", "(play ${1:Theme} ${2:Violin})", "Track Binding: (play <theme> <instrument>)")
    ]

    public static func complete(source: String, position: TMDLSPPosition) -> [TMDLSPCompletionItem] {
        let lines = source.components(separatedBy: "\n")
        guard position.line < lines.count else { return [] }
        let currentLine = lines[position.line]
        let prefix = String(currentLine.prefix(position.character))

        // 1. Check for S-Expression macro completion: inside "-> (" or "(" or "(<word>"
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        let isInsideMacro: Bool = {
            if trimmedPrefix.hasSuffix("-> (") || trimmedPrefix.hasSuffix("(") {
                return true
            }
            if let lastParenIndex = prefix.lastIndex(of: "(") {
                let afterParen = prefix[prefix.index(after: lastParenIndex)...]
                // If there is no closing parenthesis after the opening paren, and only letters/digits typed so far
                if !afterParen.contains(")") && !afterParen.contains(" ") && !afterParen.isEmpty {
                    return true
                }
            }
            return false
        }()

        let remainder = String(currentLine.dropFirst(position.character))
        let nextChar = remainder.first

        if isInsideMacro {
            return macroSnippets.map {
                let rawInsert = $0.insertText
                var cleanInsert = rawInsert.hasPrefix("(") ? String(rawInsert.dropFirst()) : rawInsert
                if nextChar == ")" && cleanInsert.hasSuffix(")") {
                    cleanInsert.removeLast()
                }
                return TMDLSPCompletionItem(
                    label: $0.label,
                    kind: .snippet,
                    detail: $0.detail,
                    documentation: $0.detail,
                    insertText: cleanInsert,
                    insertTextFormat: 2 // Snippet
                )
            }
        }

        // 2. Check for Playback Order section completion: after "-> "
        if prefix.trimmingCharacters(in: .whitespaces).hasSuffix("->") || prefix.trimmingCharacters(in: .whitespaces).contains("->") {
            let sectionNames = TMDOutlineGenerator.extractSectionNames(source: source)
            return sectionNames.map {
                TMDLSPCompletionItem(
                    label: $0,
                    kind: .field,
                    detail: "TMD Section: \($0)",
                    documentation: "Playback section or abstract theme"
                )
            }
        }

        // 3. Check for Instrument completion: after ":"
        if prefix.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
            return standardInstruments.map {
                TMDLSPCompletionItem(
                    label: $0,
                    kind: .keyword,
                    detail: "General MIDI Instrument: \($0)",
                    documentation: "Standard instrument sound assignment"
                )
            }
        }

        // 4. Check for Chord completion: after "["
        if prefix.trimmingCharacters(in: .whitespaces).hasSuffix("[") {
            let appendClosingBracket = nextChar != "]"
            var items: [TMDLSPCompletionItem] = []

            // A. Scale Degree Chords (Key-agnostic, pop progression friendly: 1, 4, 5, 3m, 6m, etc.)
            for chord in scaleDegreeChords {
                items.append(TMDLSPCompletionItem(
                    label: chord,
                    kind: .value,
                    detail: "Scale Degree Chord: [\(chord)]",
                    documentation: "Key-independent scale degree notation for pop progression and transposition.",
                    insertText: appendClosingBracket ? "\(chord)]" : chord
                ))
            }

            // B. Diatonic Letter Chords for current key
            let sheet = TmdParser.parse(string: source)
            let keyStr = sheet?.keySignature.description ?? "C"
            let diatonicChords = getDiatonicChords(for: keyStr)
            for chord in diatonicChords {
                items.append(TMDLSPCompletionItem(
                    label: chord,
                    kind: .value,
                    detail: "Diatonic Chord in \(keyStr)",
                    documentation: "Absolute diatonic chord in key of \(keyStr).",
                    insertText: appendClosingBracket ? "\(chord)]" : chord
                ))
            }

            return items
        }

        return []
    }

    private static let scaleDegreeChords: [String] = [
        // Basic triads
        "1", "2m", "3m", "4", "5", "6m", "7dim",
        // Seventh & extended chords (4-5-3-6 & pop essentials)
        "1maj7", "2m7", "3m7", "4maj7", "57", "6m7", "5sus4",
        // Common slash & inversion chords
        "5/4", "4/5", "1/3", "5/7", "1/5"
    ]

    private static func getDiatonicChords(for keyStr: String) -> [String] {
        if keyStr.contains("m") {
            return ["Am", "Bdim", "C", "Dm", "Em", "F", "G", "Am7", "Dm7", "E7", "Cmaj7", "Fmaj7"]
        }
        switch keyStr {
        case "G": return ["G", "Am", "Bm", "C", "D", "Em", "F#dim", "Gmaj7", "Am7", "Bm7", "Cmaj7", "D7", "Em7", "Dsus4", "G/B", "D/F#", "C/D"]
        case "D": return ["D", "Em", "F#m", "G", "A", "Bm", "C#dim", "Dmaj7", "Em7", "F#m7", "Gmaj7", "A7", "Bm7", "Asus4"]
        case "A": return ["A", "Bm", "C#m", "D", "E", "F#m", "G#dim", "Amaj7", "Bm7", "C#m7", "Dmaj7", "E7", "F#m7", "Esus4"]
        case "F": return ["F", "Gm", "Am", "Bb", "C", "Dm", "Edim", "Fmaj7", "Gm7", "Am7", "Bbmaj7", "C7", "Dm7", "Csus4", "F/A", "C/E", "Bb/C"]
        case "Bb": return ["Bb", "Cm", "Dm", "Eb", "F", "Gm", "Adim", "Bbmaj7", "Cm7", "Dm7", "Ebmaj7", "F7", "Gm7", "Fsus4"]
        default: return ["C", "Dm", "Em", "F", "G", "Am", "Bdim", "Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Gsus4", "C/E", "G/B", "F/G"]
        }
    }
}

// MARK: - Diagnostic Engine

public struct TMDLSPDiagnosticEngine {
    public static func diagnose(source: String) -> [TMDLSPDiagnostic] {
        var diagnostics: [TMDLSPDiagnostic] = []

        // 1. Measure consistency check
        let issues = TMDMeasureChecker.check(source: source)
        for issue in issues {
            let line = max(0, issue.lineNumber - 1)
            let col = 0
            let range = TMDLSPRange(
                start: TMDLSPPosition(line: line, character: col),
                end: TMDLSPPosition(line: line, character: 80)
            )
            diagnostics.append(TMDLSPDiagnostic(
                range: range,
                severity: 1, // Error
                source: "tmd-measure-checker",
                message: issue.description
            ))
        }

        // 2. Syntax / Throwing parser check
        do {
            _ = try TmdParser.parseThrowing(string: source)
        } catch let err as TMDParseError {
            let line = max(0, err.range.start.line - 1)
            let col = max(0, err.range.start.column - 1)
            let length = max(1, err.range.length)
            let range = TMDLSPRange(
                start: TMDLSPPosition(line: line, character: col),
                end: TMDLSPPosition(line: line, character: col + length)
            )
            diagnostics.append(TMDLSPDiagnostic(
                range: range,
                severity: 1,
                source: "tmd-parser",
                message: err.description
            ))
        } catch {
            // Other errors
        }

        return diagnostics
    }
}

// MARK: - LSP Server Handler & Event Loop

public final class TMDLSPServer: @unchecked Sendable {
    public private(set) var documents: [String: String] = [:]
    public var sendOutput: ((String) -> Void)?
    public private(set) var isRunning: Bool = true

    public init(sendOutput: ((String) -> Void)? = nil) {
        self.sendOutput = sendOutput
    }

    public func handle(message: TMDJSONRPCFrame) {
        guard let method = message.method else { return }

        switch method {
        case "initialize":
            let capabilities: [String: Any] = [
                "capabilities": [
                    "textDocumentSync": 1, // Full document sync
                    "completionProvider": [
                        "resolveProvider": false,
                        "triggerCharacters": [">", "(", ":", "["]
                    ],
                    "documentFormattingProvider": true,
                    "documentSymbolProvider": true
                ],
                "serverInfo": [
                    "name": "tmd-lsp",
                    "version": "1.0.0"
                ]
            ]
            let resp = TMDJSONRPCResponse(id: message.id, result: capabilities)
            send(TMDJSONRPCCodec.encode(resp))

        case "initialized":
            // Notification from client after initialize
            break

        case "shutdown":
            let resp = TMDJSONRPCResponse(id: message.id, result: NSNull())
            send(TMDJSONRPCCodec.encode(resp))

        case "exit":
            isRunning = false

        case "textDocument/didOpen":
            if let params = message.params as? [String: Any],
               let textDocument = params["textDocument"] as? [String: Any],
               let uri = textDocument["uri"] as? String,
               let text = textDocument["text"] as? String {
                documents[uri] = text
                publishDiagnostics(uri: uri, source: text)
            }

        case "textDocument/didChange":
            if let params = message.params as? [String: Any],
               let textDocument = params["textDocument"] as? [String: Any],
               let uri = textDocument["uri"] as? String,
               let contentChanges = params["contentChanges"] as? [[String: Any]],
               let lastChange = contentChanges.last,
               let text = lastChange["text"] as? String {
                documents[uri] = text
                publishDiagnostics(uri: uri, source: text)
            }

        case "textDocument/didClose":
            if let params = message.params as? [String: Any],
               let textDocument = params["textDocument"] as? [String: Any],
               let uri = textDocument["uri"] as? String {
                documents.removeValue(forKey: uri)
                // Clear diagnostics
                sendDiagnosticsNotification(uri: uri, diagnostics: [])
            }

        case "textDocument/completion":
            guard let id = message.id else { return }
            var completionItems: [[String: Any]] = []

            if let params = message.params as? [String: Any],
               let textDocument = params["textDocument"] as? [String: Any],
               let uri = textDocument["uri"] as? String,
               let posDict = params["position"] as? [String: Any],
               let line = posDict["line"] as? Int,
               let character = posDict["character"] as? Int,
               let source = documents[uri] {
                let position = TMDLSPPosition(line: line, character: character)
                let items = TMDLSPCompletionEngine.complete(source: source, position: position)
                completionItems = items.map { item in
                    var dict: [String: Any] = [
                        "label": item.label,
                        "kind": item.kind.rawValue
                    ]
                    if let detail = item.detail { dict["detail"] = detail }
                    if let doc = item.documentation { dict["documentation"] = doc }
                    if let insert = item.insertText { dict["insertText"] = insert }
                    if let format = item.insertTextFormat { dict["insertTextFormat"] = format }
                    return dict
                }
            }

            let resp = TMDJSONRPCResponse(id: id, result: completionItems)
            send(TMDJSONRPCCodec.encode(resp))

        case "textDocument/formatting":
            guard let id = message.id else { return }
            var edits: [[String: Any]] = []

            if let params = message.params as? [String: Any],
               let textDocument = params["textDocument"] as? [String: Any],
               let uri = textDocument["uri"] as? String,
               let source = documents[uri] {
                let formatted = TMDRefactor.format(source)
                let lines = source.components(separatedBy: "\n")
                let lastLineIndex = max(0, lines.count - 1)
                let lastLineChar = lines[lastLineIndex].utf16.count

                let range: [String: Any] = [
                    "start": ["line": 0, "character": 0],
                    "end": ["line": lastLineIndex, "character": lastLineChar]
                ]
                edits.append([
                    "range": range,
                    "newText": formatted
                ])
            }

            let resp = TMDJSONRPCResponse(id: id, result: edits)
            send(TMDJSONRPCCodec.encode(resp))

        case "textDocument/documentSymbol":
            guard let id = message.id else { return }
            var symbols: [[String: Any]] = []

            if let params = message.params as? [String: Any],
               let textDocument = params["textDocument"] as? [String: Any],
               let uri = textDocument["uri"] as? String,
               let source = documents[uri] {
                let nodes = TMDOutlineGenerator.generate(source: source)
                symbols = nodes.map { nodeToLSPDocumentSymbol($0) }
            }

            let resp = TMDJSONRPCResponse(id: id, result: symbols)
            send(TMDJSONRPCCodec.encode(resp))

        default:
            if let id = message.id {
                let resp = TMDJSONRPCResponse(id: id, result: NSNull())
                send(TMDJSONRPCCodec.encode(resp))
            }
        }
    }

    private func send(_ encoded: String) {
        sendOutput?(encoded)
    }

    private func publishDiagnostics(uri: String, source: String) {
        let diags = TMDLSPDiagnosticEngine.diagnose(source: source)
        let diagDicts: [[String: Any]] = diags.map { d in
            var dict: [String: Any] = [
                "range": [
                    "start": ["line": d.range.start.line, "character": d.range.start.character],
                    "end": ["line": d.range.end.line, "character": d.range.end.character]
                ],
                "severity": d.severity,
                "message": d.message
            ]
            if let src = d.source { dict["source"] = src }
            return dict
        }
        sendDiagnosticsNotification(uri: uri, diagnostics: diagDicts)
    }

    private func sendDiagnosticsNotification(uri: String, diagnostics: [[String: Any]]) {
        let params: [String: Any] = [
            "uri": uri,
            "diagnostics": diagnostics
        ]
        let encoded = TMDJSONRPCCodec.encode(method: "textDocument/publishDiagnostics", params: params)
        send(encoded)
    }

    private func nodeToLSPDocumentSymbol(_ node: TMDOutlineNode) -> [String: Any] {
        let symbolKind = TMDLSPSymbolKind.from(outlineKind: node.kind).rawValue
        var dict: [String: Any] = [
            "name": node.name,
            "kind": symbolKind,
            "range": [
                "start": ["line": max(0, node.range.startLine - 1), "character": max(0, node.range.startColumn - 1)],
                "end": ["line": max(0, node.range.endLine - 1), "character": max(0, node.range.endColumn - 1)]
            ],
            "selectionRange": [
                "start": ["line": max(0, node.selectionRange.startLine - 1), "character": max(0, node.selectionRange.startColumn - 1)],
                "end": ["line": max(0, node.selectionRange.endLine - 1), "character": max(0, node.selectionRange.endColumn - 1)]
            ]
        ]
        if let detail = node.detail { dict["detail"] = detail }
        if let children = node.children, !children.isEmpty {
            dict["children"] = children.map { nodeToLSPDocumentSymbol($0) }
        }
        return dict
    }
}

