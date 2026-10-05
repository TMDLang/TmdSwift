import Foundation
import TmdSwift


public struct TmdLSPDiagnosticEngine {
    public static func diagnose(source: String) -> [TmdLSPDiagnostic] {
        var diagnostics: [TmdLSPDiagnostic] = []

        // 1. Measure consistency check
        let issues = TmdMeasureChecker.check(source: source)
        for issue in issues {
            let line = max(0, issue.lineNumber - 1)
            let col = 0
            let range = TmdLSPRange(
                start: TmdLSPPosition(line: line, character: col),
                end: TmdLSPPosition(line: line, character: 80)
            )
            diagnostics.append(
                TmdLSPDiagnostic(
                    range: range,
                    severity: 1,  // Error
                    source: "tmd-measure-checker",
                    message: issue.description
                ))
        }

        // 2. Syntax / Throwing parser check
        do {
            _ = try TmdParser.parseThrowing(string: source)
        } catch let err as TmdParseError {
            let line = max(0, err.range.start.line - 1)
            let col = max(0, err.range.start.column - 1)
            let length = max(1, err.range.length)
            let range = TmdLSPRange(
                start: TmdLSPPosition(line: line, character: col),
                end: TmdLSPPosition(line: line, character: col + length)
            )
            diagnostics.append(
                TmdLSPDiagnostic(
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

public final class TmdLSPServer: @unchecked Sendable {
    public private(set) var documents: [String: String] = [:]
    public var sendOutput: ((String) -> Void)?
    public private(set) var isRunning: Bool = true

    public init(sendOutput: ((String) -> Void)? = nil) {
        self.sendOutput = sendOutput
    }

    public func handle(message: TmdJSONRPCFrame) {
        guard let method = message.method else { return }

        switch method {
        case "initialize":
            let capabilities: [String: Any] = [
                "capabilities": [
                    "textDocumentSync": 1,  // Full document sync
                    "completionProvider": [
                        "resolveProvider": false,
                        "triggerCharacters": [">", "(", ":", "[", "{"],
                    ],
                    "documentFormattingProvider": true,
                    "documentSymbolProvider": true,
                ],
                "serverInfo": [
                    "name": "tmd-lsp",
                    "version": "1.0.0",
                ],
            ]
            let resp = TmdJSONRPCResponse(id: message.id, result: capabilities)
            send(TmdJSONRPCCodec.encode(resp))

        case "initialized":
            // Notification from client after initialize
            break

        case "shutdown":
            let resp = TmdJSONRPCResponse(id: message.id, result: NSNull())
            send(TmdJSONRPCCodec.encode(resp))

        case "exit":
            isRunning = false

        case "textDocument/didOpen":
            if let params = message.params as? [String: Any],
                let textDocument = params["textDocument"] as? [String: Any],
                let uri = textDocument["uri"] as? String,
                let text = textDocument["text"] as? String
            {
                documents[uri] = text
                publishDiagnostics(uri: uri, source: text)
            }

        case "textDocument/didChange":
            if let params = message.params as? [String: Any],
                let textDocument = params["textDocument"] as? [String: Any],
                let uri = textDocument["uri"] as? String,
                let contentChanges = params["contentChanges"] as? [[String: Any]],
                let lastChange = contentChanges.last,
                let text = lastChange["text"] as? String
            {
                documents[uri] = text
                publishDiagnostics(uri: uri, source: text)
            }

        case "textDocument/didClose":
            if let params = message.params as? [String: Any],
                let textDocument = params["textDocument"] as? [String: Any],
                let uri = textDocument["uri"] as? String
            {
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
                let source = documents[uri]
            {
                let position = TmdLSPPosition(line: line, character: character)
                let items = TmdLSPCompletionEngine.complete(source: source, position: position)
                completionItems = items.map { item in
                    var dict: [String: Any] = [
                        "label": item.label,
                        "kind": item.kind.rawValue,
                    ]
                    if let detail = item.detail { dict["detail"] = detail }
                    if let doc = item.documentation { dict["documentation"] = doc }
                    if let insert = item.insertText { dict["insertText"] = insert }
                    if let format = item.insertTextFormat { dict["insertTextFormat"] = format }
                    return dict
                }
            }

            let resp = TmdJSONRPCResponse(id: id, result: completionItems)
            send(TmdJSONRPCCodec.encode(resp))

        case "textDocument/formatting":
            guard let id = message.id else { return }
            var edits: [[String: Any]] = []

            if let params = message.params as? [String: Any],
                let textDocument = params["textDocument"] as? [String: Any],
                let uri = textDocument["uri"] as? String,
                let source = documents[uri]
            {
                let formatted = TmdRefactor.format(source)
                let lines = source.components(separatedBy: "\n")
                let lastLineIndex = max(0, lines.count - 1)
                let lastLineChar = lines[lastLineIndex].utf16.count

                let range: [String: Any] = [
                    "start": ["line": 0, "character": 0],
                    "end": ["line": lastLineIndex, "character": lastLineChar],
                ]
                edits.append([
                    "range": range,
                    "newText": formatted,
                ])
            }

            let resp = TmdJSONRPCResponse(id: id, result: edits)
            send(TmdJSONRPCCodec.encode(resp))

        case "textDocument/documentSymbol":
            guard let id = message.id else { return }
            var symbols: [[String: Any]] = []

            if let params = message.params as? [String: Any],
                let textDocument = params["textDocument"] as? [String: Any],
                let uri = textDocument["uri"] as? String,
                let source = documents[uri]
            {
                let nodes = TmdOutlineGenerator.generate(source: source)
                symbols = nodes.map { nodeToLSPDocumentSymbol($0) }
            }

            let resp = TmdJSONRPCResponse(id: id, result: symbols)
            send(TmdJSONRPCCodec.encode(resp))

        default:
            if let id = message.id {
                let resp = TmdJSONRPCResponse(id: id, result: NSNull())
                send(TmdJSONRPCCodec.encode(resp))
            }
        }
    }

    private func send(_ encoded: String) {
        sendOutput?(encoded)
    }

    private func publishDiagnostics(uri: String, source: String) {
        let diags = TmdLSPDiagnosticEngine.diagnose(source: source)
        let diagDicts: [[String: Any]] = diags.map { d in
            var dict: [String: Any] = [
                "range": [
                    "start": ["line": d.range.start.line, "character": d.range.start.character],
                    "end": ["line": d.range.end.line, "character": d.range.end.character],
                ],
                "severity": d.severity,
                "message": d.message,
            ]
            if let src = d.source { dict["source"] = src }
            return dict
        }
        sendDiagnosticsNotification(uri: uri, diagnostics: diagDicts)
    }

    private func sendDiagnosticsNotification(uri: String, diagnostics: [[String: Any]]) {
        let params: [String: Any] = [
            "uri": uri,
            "diagnostics": diagnostics,
        ]
        let encoded = TmdJSONRPCCodec.encode(
            method: "textDocument/publishDiagnostics", params: params)
        send(encoded)
    }

    private func nodeToLSPDocumentSymbol(_ node: TmdOutlineNode) -> [String: Any] {
        let symbolKind = TmdLSPSymbolKind.from(outlineKind: node.kind).rawValue
        var dict: [String: Any] = [
            "name": node.name,
            "kind": symbolKind,
            "range": [
                "start": [
                    "line": max(0, node.range.startLine - 1),
                    "character": max(0, node.range.startColumn - 1),
                ],
                "end": [
                    "line": max(0, node.range.endLine - 1),
                    "character": max(0, node.range.endColumn - 1),
                ],
            ],
            "selectionRange": [
                "start": [
                    "line": max(0, node.selectionRange.startLine - 1),
                    "character": max(0, node.selectionRange.startColumn - 1),
                ],
                "end": [
                    "line": max(0, node.selectionRange.endLine - 1),
                    "character": max(0, node.selectionRange.endColumn - 1),
                ],
            ],
        ]
        if let detail = node.detail { dict["detail"] = detail }
        if let children = node.children, !children.isEmpty {
            dict["children"] = children.map { nodeToLSPDocumentSymbol($0) }
        }
        return dict
    }
}
