import Foundation
import MCP
import TmdABC
import TmdAudio
import TmdBraille
import TmdChordPro
import TmdLilyPond
import TmdMIDI
import TmdMusicXML
import TmdReaper
import TmdSkill
import TmdSwift
import TmdUTAU
import TmdVocaloid

/// Model Context Protocol integration for the TMD compiler.
public enum TmdMCPServer {
    public static let serverName = "tmd-mcp-server"
    public static let toolNames = [
        "get_tmd_skill", "parse_tmd", "check_tmd", "convert_tmd", "tmd_export_braille",
    ]

    public static func runBlocking() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            defer { semaphore.signal() }
            do {
                try await start()
            } catch {
                fputs("TMD MCP server error: \(error.localizedDescription)\n", stderr)
            }
        }
        semaphore.wait()
    }

    @discardableResult
    public static func installConfiguration() -> [(path: String, installed: Bool, error: String?)] {
        let home = NSHomeDirectory()
        let paths = [
            "\(home)/Library/Application Support/Claude/claude_desktop_config.json",
            "\(home)/.cursor/mcp.json",
            "\(home)/.gemini/config/mcp_config.json",
            "\(home)/.gemini/antigravity-cli/mcp_config.json",
            "\(home)/.codeium/windsurf/mcp_config.json",
        ]
        return paths.map { installConfiguration(at: $0) }
    }

    private static func installConfiguration(at path: String) -> (path: String, installed: Bool, error: String?) {
        do {
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var root: [String: Any] = [:]
            if let data = try? Data(contentsOf: url),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = object
            }
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            servers["tmd"] = ["command": "tmd", "args": ["--mcp"]]
            root["mcpServers"] = servers
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try (data + Data([0x0A])).write(to: url, options: .atomic)
            return (path, true, nil)
        } catch {
            return (path, false, error.localizedDescription)
        }
    }

    public static func start() async throws {
        let server = Server(
            name: serverName,
            version: "0.1.0",
            title: "TMD (Timebase Mark Down) Music Compiler",
            instructions: "Use check_tmd before exporting or modifying a TMD score.",
            capabilities: .init(tools: .init())
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: toolDefinitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            try await callTool(params)
        }
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    private static let textOrFileProperties: Value = .object([
        "type": .string("object"),
        "properties": .object([
            "text": .object(["type": .string("string")]),
            "filePath": .object(["type": .string("string")]),
        ]),
    ])

    private static let toolDefinitions: [Tool] = [
        Tool(
            name: "get_tmd_skill",
            description: "Return the complete TMD language and AI authoring skill.",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])]),
            annotations: .init(readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "parse_tmd",
            description: "Parse TMD source text or a local TMD file and return score metadata.",
            inputSchema: textOrFileProperties,
            annotations: .init(readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "check_tmd",
            description: "Validate TMD syntax, measure beats, lyrics, macros, and playback semantics.",
            inputSchema: textOrFileProperties,
            annotations: .init(readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "convert_tmd",
            description: "Convert TMD source to a supported export format.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                    "filePath": .object(["type": .string("string")]),
                    "format": .object([
                        "type": .string("string"),
                        "enum": .array(["midi", "wav", "musicxml", "lilypond", "abc", "reaper", "rpp", "chordpro", "cho", "vsq", "vsqx", "ust", "braille", "brl", "brf"].map(Value.string)),
                    ]),
                    "outputPath": .object(["type": .string("string")]),
                    "section": .object(["type": .string("string")]),
                    "instrument": .object(["type": .string("string")]),
                    "flattenRepeats": .object(["type": .string("boolean")]),
                ]),
                "required": .array([.string("format")]),
            ]),
            annotations: .init(readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "tmd_export_braille",
            description: "Export TMD as Unicode or ASCII Music Braille.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "text": .object(["type": .string("string")]),
                    "filePath": .object(["type": .string("string")]),
                    "encoding": .object(["type": .string("string"), "enum": .array([.string("unicode"), .string("ascii")])]),
                    "layout": .object(["type": .string("string"), "enum": .array([.string("part-by-part"), .string("bar-over-bar")])]),
                    "outputPath": .object(["type": .string("string")]),
                    "section": .object(["type": .string("string")]),
                    "instrument": .object(["type": .string("string")]),
                ]),
            ]),
            annotations: .init(readOnlyHint: false, idempotentHint: true)
        ),
    ]

    private static func callTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let result: String
            switch params.name {
            case "get_tmd_skill":
                result = TmdSkill.skillMarkdown
            case "parse_tmd":
                result = try parse(arguments: params.arguments)
            case "check_tmd":
                result = try check(arguments: params.arguments)
            case "convert_tmd":
                result = try convert(arguments: params.arguments)
            case "tmd_export_braille":
                result = try exportBraille(arguments: params.arguments)
            default:
                throw MCPError.invalidParams("Unknown TMD tool: \(params.name)")
            }
            return .init(content: [.text(text: result, annotations: nil, _meta: nil)], isError: false)
        } catch let error as MCPError {
            throw error
        } catch {
            return .init(
                content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                isError: true)
        }
    }

    private static func source(arguments: [String: Value]?) throws -> (String, String?) {
        if let text = arguments?["text"]?.stringValue { return (text, nil) }
        if let path = arguments?["filePath"]?.stringValue {
            do { return (try String(contentsOfFile: path, encoding: .utf8), path) }
            catch { throw MCPError.invalidParams("Unable to read TMD file: \(error.localizedDescription)") }
        }
        throw MCPError.invalidParams("Provide either text or filePath")
    }

    private static func parse(arguments: [String: Value]?) throws -> String {
        let (text, path) = try source(arguments: arguments)
        do {
            let sheet = try TmdParser.parseThrowing(string: text)
            let result: [String: Any] = [
                "name": sheet.name,
                "speed": sheet.speed,
                "keySignature": sheet.keySignature.description,
                "declaredKey": sheet.declaredKey as Any,
                "beat": "\(sheet.beat.count)/\(sheet.beat.noteValue)",
                "entries": sheet.entries.count,
                "playbackOrders": sheet.playback.count,
                "filePath": path as Any,
            ]
            return try json(result)
        } catch { throw MCPError.invalidParams("Unable to parse TMD: \(error.localizedDescription)") }
    }

    private static func check(arguments: [String: Value]?) throws -> String {
        let (text, path) = try source(arguments: arguments)
        let diagnostics = TmdScoreValidator.validate(source: text, options: .init(file: path))
        return try json(diagnostics.map { diagnostic in
            [
                "severity": diagnostic.severity.rawValue,
                "rule": diagnostic.rule.rawValue,
                "message": diagnostic.message,
                "line": diagnostic.line,
                "column": diagnostic.column,
                "suggestion": diagnostic.suggestion as Any,
            ] as [String: Any]
        })
    }

    private static func convert(arguments: [String: Value]?) throws -> String {
        let (text, _) = try source(arguments: arguments)
        guard let format = arguments?["format"]?.stringValue else {
            throw MCPError.invalidParams("convert_tmd requires format")
        }
        let sheet = try TmdParser.parseThrowing(string: text)
        let section = arguments?["section"]?.stringValue
        let instrument = arguments?["instrument"]?.stringValue
        let flatten = arguments?["flattenRepeats"]?.boolValue ?? false
        let output: ExportedArtifact
        switch format {
        case "musicxml": output = .text(TmdMusicXMLGenerator.generateMusicXML(from: sheet, options: .init(flattenRepeats: flatten)))
        case "lilypond": output = .text(TmdLilyPondGenerator.generateLilyPond(from: sheet, options: .init(flattenRepeats: flatten)))
        case "abc": output = .text(TmdABCGenerator.generateABC(from: sheet, options: .init(flattenRepeats: flatten)))
        case "chordpro", "cho": output = .text(TmdChordProGenerator.generateChordPro(from: sheet))
        case "reaper", "rpp": output = .text(try TmdReaperGenerator.generateRPP(from: sheet))
        case "braille", "brl", "brf": output = .text(TmdBrailleGenerator.generateBraille(from: sheet, options: .init(targetSection: section, targetInstrument: instrument)))
        case "ust": output = .text(TmdUSTGenerator.generateUST(from: sheet, targetInstrument: instrument))
        case "vsqx": output = .text(TmdVSQXGenerator.generateVSQX(from: sheet, targetInstrument: instrument))
        case "vsq": output = .data(TmdVSQGenerator.generateVSQ(from: sheet, targetInstrument: instrument))
        case "midi": output = .data(try TmdMIDIGenerator.generateMIDI(from: sheet, targetParagraph: section, targetInstrument: instrument))
        case "wav": output = .data(try TmdWAVRenderer.renderWAV(from: sheet, targetParagraph: section, targetInstrument: instrument))
        default: throw MCPError.invalidParams("Unsupported TMD format: \(format)")
        }
        if let path = arguments?["outputPath"]?.stringValue {
            switch output {
            case .text(let value): try value.write(toFile: path, atomically: true, encoding: .utf8)
            case .data(let value): try value.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            return "Wrote \(format) output to \(path)"
        }
        switch output {
        case .text(let value): return value
        case .data(let value): return value.base64EncodedString()
        }
    }

    private static func exportBraille(arguments: [String: Value]?) throws -> String {
        let (text, _) = try source(arguments: arguments)
        let sheet = try TmdParser.parseThrowing(string: text)
        let encoding = TmdBrailleEncoding(rawValue: arguments?["encoding"]?.stringValue ?? "unicode") ?? .unicode
        let layout = TmdBrailleLayout(rawValue: arguments?["layout"]?.stringValue ?? "part-by-part") ?? .partByPart
        let output = TmdBrailleGenerator.generateBraille(from: sheet, options: .init(encoding: encoding, layout: layout, targetSection: arguments?["section"]?.stringValue, targetInstrument: arguments?["instrument"]?.stringValue))
        if let path = arguments?["outputPath"]?.stringValue {
            try output.write(toFile: path, atomically: true, encoding: .utf8)
            return "Wrote braille output to \(path)"
        }
        return output
    }

    private static func json(_ value: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(value) else { throw MCPError.internalError("Could not encode JSON result") }
        return String(data: try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) ?? "{}"
    }

    private enum ExportedArtifact {
        case text(String)
        case data(Data)
    }
}
