import Testing
import Foundation
@testable import TmdSwift
@testable import TmdLSP

@Suite("TMD LSP Protocol & Completion Tests")
struct TMDLSPTests {

    @Test("Parses JSON-RPC messages with Content-Length header")
    func testJSONRPCMessageParsing() throws {
        let raw = "Content-Length: 46\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"
        // Test helper will decode JSON-RPC frame
        let frames = TMDJSONRPCCodec.decode(raw)
        #expect(frames.count == 1)
        #expect(frames[0].id == 1)
        #expect(frames[0].method == "initialize")
    }

    @Test("Encodes JSON-RPC response with Content-Length header")
    func testJSONRPCMessageEncoding() throws {
        let response = TMDJSONRPCResponse(id: 1, result: ["capabilities": [:]])
        let encoded = TMDJSONRPCCodec.encode(response)
        #expect(encoded.starts(with: "Content-Length: "))
        #expect(encoded.contains("\r\n\r\n"))
        #expect(encoded.contains("\"jsonrpc\":\"2.0\""))
    }

    @Test("Provides section name completions after '-> ' in playback orders")
    func testCompletionSectionNames() throws {
        let source = """
        ::SCORE::
        ** Test Score **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
            <4*>
            1 2 3 4
        }

        verse:Piano@|0|{
            <4*>
            1 2 3 4
        }

        Theme {
            <4*>
            1 2 3 4
        }

        -> 
        """
        // Position at line 21 (0-based index: 21), column 3
        let items = TMDLSPCompletionEngine.complete(
            source: source,
            position: TMDLSPPosition(line: 21, character: 3)
        )
        let labels = items.map(\.label)
        #expect(labels.contains("intro"))
        #expect(labels.contains("verse"))
        #expect(labels.contains("Theme"))
    }

    @Test("Provides S-expression macro snippets after '-> (' in playback orders")
    func testCompletionSExprMacros() throws {
        let source = """
        ::SCORE::
        ** Test Score **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }

        -> (
        """
        let items = TMDLSPCompletionEngine.complete(
            source: source,
            position: TMDLSPPosition(line: 11, character: 4)
        )
        let labels = items.map(\.label)
        #expect(labels.contains("canon"))
        #expect(labels.contains("loop"))
        #expect(labels.contains("layer"))
        #expect(labels.contains("seq"))
        #expect(labels.contains("reverse"))
        #expect(labels.contains("flip"))
        #expect(labels.contains("transpose"))
        #expect(labels.contains("vary"))

        // Assert that the snippet does not contain leading '(' when triggered after '('
        let canonItem = items.first(where: { $0.label == "canon" })
        #expect(canonItem?.insertText?.hasPrefix("(") == false)
        #expect(canonItem?.insertText?.hasPrefix("canon") == true)

        // Also test when editor auto-closed ')' so line is "-> (|)"
        let sourceWithAutoClose = """
        ::SCORE::
        ** Test Score **
        != 120
        ?= C
        <4/4>

        Theme {
            <4*>
            1 2 3 4
        }

        -> ()
        """
        let itemsWithAutoClose = TMDLSPCompletionEngine.complete(
            source: sourceWithAutoClose,
            position: TMDLSPPosition(line: 11, character: 4) // cursor between ( and )
        )
        let canonAutoClose = itemsWithAutoClose.first(where: { $0.label == "canon" })
        #expect(canonAutoClose?.insertText?.hasSuffix(")") == false)
    }

    @Test("Provides General MIDI 128 instrument names after colon in paragraph header")
    func testCompletionGeneralMIDIInstruments() throws {
        let source = """
        ::SCORE::
        ** Test Score **
        != 120
        ?= C
        <4/4>

        verse:
        """
        let items = TMDLSPCompletionEngine.complete(
            source: source,
            position: TMDLSPPosition(line: 6, character: 6)
        )
        let labels = items.map(\.label)
        #expect(labels.contains("Piano") || labels.contains("AcousticGrandPiano"))
        #expect(labels.contains("Violin"))
        #expect(labels.contains("Cello"))
        #expect(labels.contains("Bass") || labels.contains("ElectricBassFinger"))
        #expect(labels.contains("Drums"))
    }

    @Test("Provides diatonic and scale-degree chords when opening bracket '[' inside paragraph")
    func testCompletionDiatonicChords() throws {
        let source = """
        ::SCORE::
        ** Test Score **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            [
        }
        """
        let items = TMDLSPCompletionEngine.complete(
            source: source,
            position: TMDLSPPosition(line: 8, character: 5)
        )
        let labels = items.map(\.label)
        // Scale degree chords (1, 4, 5, 3m, 6m, 4maj7, 5/4, etc.)
        #expect(labels.contains("1"))
        #expect(labels.contains("2m"))
        #expect(labels.contains("3m"))
        #expect(labels.contains("4"))
        #expect(labels.contains("5"))
        #expect(labels.contains("6m"))
        #expect(labels.contains("4maj7"))
        #expect(labels.contains("57"))
        #expect(labels.contains("3m7"))
        #expect(labels.contains("6m7"))
        #expect(labels.contains("5/4"))
        #expect(labels.contains("4/5"))

        // Absolute letter diatonic chords
        #expect(labels.contains("C"))
        #expect(labels.contains("Dm"))
        #expect(labels.contains("Em"))
        #expect(labels.contains("F"))
        #expect(labels.contains("G"))
        #expect(labels.contains("Am"))
    }

    @Test("Publishes diagnostics on beat discrepancies in measures")
    func testPublishDiagnostics() throws {
        let source = """
        ::SCORE::
        ** Measure Error Score **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
            <4*>
            | 1 2 3 4 5 |
        }
        -> intro ->#
        """
        let diagnostics = TMDLSPDiagnosticEngine.diagnose(source: source)
        #expect(!diagnostics.isEmpty)
        let msg = diagnostics[0].message
        #expect(msg.contains("Expected") || msg.contains("units") || msg.contains("measure"))
    }

    @Test("Server handles initialize and completion workflow")
    func testServerLifecycleAndCompletion() throws {
        var sentMessages: [String] = []
        let server = TMDLSPServer { msg in
            sentMessages.append(msg)
        }

        // 1. Initialize
        let initFrame = TMDJSONRPCFrame(id: 1, method: "initialize", params: [:])
        server.handle(message: initFrame)
        #expect(sentMessages.count == 1)
        #expect(sentMessages[0].contains("\"capabilities\""))

        // 2. Open document
        let source = """
        ::SCORE::
        ** Test **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            1 2 3 4
        }
        -> 
        """
        let openParams: [String: Any] = [
            "textDocument": [
                "uri": "file:///test.tmd",
                "text": source
            ]
        ]
        server.handle(message: TMDJSONRPCFrame(id: nil, method: "textDocument/didOpen", params: openParams))
        // Expect diagnostics notification sent
        #expect(sentMessages.count >= 2)
        #expect(sentMessages.last?.contains("textDocument/publishDiagnostics") == true)

        // 3. Completion request
        let compParams: [String: Any] = [
            "textDocument": ["uri": "file:///test.tmd"],
            "position": ["line": 10, "character": 3]
        ]
        server.handle(message: TMDJSONRPCFrame(id: 2, method: "textDocument/completion", params: compParams))
        let compResponse = sentMessages.last ?? ""
        #expect(compResponse.contains("verse"))
    }

    @Test("Server handles document formatting and outline symbols")
    func testServerFormattingAndSymbols() throws {
        var sentMessages: [String] = []
        let server = TMDLSPServer { msg in
            sentMessages.append(msg)
        }

        let source = """
        ::SCORE::
        ** Test Score **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            1 2 3 4
        }
        -> verse ->#
        """
        let openParams: [String: Any] = [
            "textDocument": [
                "uri": "file:///test.tmd",
                "text": source
            ]
        ]
        server.handle(message: TMDJSONRPCFrame(id: nil, method: "textDocument/didOpen", params: openParams))

        // 1. Formatting
        let formatParams: [String: Any] = [
            "textDocument": ["uri": "file:///test.tmd"]
        ]
        server.handle(message: TMDJSONRPCFrame(id: 10, method: "textDocument/formatting", params: formatParams))
        let formatResp = sentMessages.last ?? ""
        #expect(formatResp.contains("newText"))

        // 2. Document Symbol
        let symbolParams: [String: Any] = [
            "textDocument": ["uri": "file:///test.tmd"]
        ]
        server.handle(message: TMDJSONRPCFrame(id: 11, method: "textDocument/documentSymbol", params: symbolParams))
        let symbolResp = sentMessages.last ?? ""
        #expect(symbolResp.contains("Test Score") || symbolResp.contains("verse"))
    }
}

