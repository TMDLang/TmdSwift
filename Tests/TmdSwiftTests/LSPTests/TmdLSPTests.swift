import Foundation
import Testing

@testable import TmdLSP
@testable import TmdSwift

@Suite("TMD LSP Protocol & Completion Tests")
struct TmdLSPTests {

    @Test("Parses JSON-RPC messages with Content-Length header")
    func testJSONRPCMessageParsing() throws {
        let raw =
            "Content-Length: 46\r\n\r\n{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}"
        // Test helper will decode JSON-RPC frame
        let frames = TmdJSONRPCCodec.decode(raw)
        #expect(frames.count == 1)
        #expect(frames[0].id == 1)
        #expect(frames[0].method == "initialize")
    }

    @Test("Encodes JSON-RPC response with Content-Length header")
    func testJSONRPCMessageEncoding() throws {
        let response = TmdJSONRPCResponse(id: 1, result: ["capabilities": [:]])
        let encoded = TmdJSONRPCCodec.encode(response)
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
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 21, character: 3)
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
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 11, character: 4)
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
        let itemsWithAutoClose = TmdLSPCompletionEngine.complete(
            source: sourceWithAutoClose,
            position: TmdLSPPosition(line: 11, character: 4)  // cursor between ( and )
        )
        let canonAutoClose = itemsWithAutoClose.first(where: { $0.label == "canon" })
        #expect(canonAutoClose?.insertText?.hasSuffix(")") == false)
    }

    @Test("Provides all section directives and filters typed directive prefixes")
    func testCompletionSectionDirectives() throws {
        let source = """
            A:Piano@|0|{
                <4*>
                {
            """
        let all = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 2, character: 5)
        )
        let labels = all.map(\.label)
        #expect(labels.contains("!= 120"))
        #expect(labels.contains("!+ 10"))
        #expect(labels.contains("?= C"))
        #expect(labels.contains("?+ 2"))
        #expect(labels.contains("?- 2"))
        #expect(!labels.contains("?= fixed"))
        #expect(labels.contains("key= Bm"))
        #expect(labels.contains("ppp"))
        #expect(labels.contains("p"))
        #expect(labels.contains("fff"))
        #expect(labels.contains("<4/4>"))

        let partial = """
            A:Piano@|0|{
                <4*>
                {key
            """
        let keyItems = TmdLSPCompletionEngine.complete(
            source: partial,
            position: TmdLSPPosition(line: 2, character: 8)
        )
        #expect(keyItems.map(\.label) == ["key= Bm"])

        let sourceWithAutoClose = """
            A:Piano@|0|{
                <4*>
                {}
            """
        let autoCloseItems = TmdLSPCompletionEngine.complete(
            source: sourceWithAutoClose,
            position: TmdLSPPosition(line: 2, character: 5)
        )
        let meterItem = autoCloseItems.first(where: { $0.label == "<4/4>" })
        #expect(meterItem?.insertText?.hasSuffix("}") == false)
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
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 6, character: 6)
        )
        let labels = items.map(\.label)
        #expect(labels.contains("Piano") || labels.contains("AcousticGrandPiano"))
        #expect(labels.contains("Violin"))
        #expect(labels.contains("Cello"))
        #expect(labels.contains("Bass") || labels.contains("ElectricBassFinger"))
        #expect(labels.contains("Drums"))
        #expect(
            items.first(where: { $0.label == "Piano" })?.detail == "General MIDI Assignment: Piano")
    }

    @Test("Provides canonical fixed-pitch entry attributes")
    func testCompletionFixedPitchEntryAttribute() throws {
        let source = "A:Timpani["
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 0, character: source.count)
        )
        #expect(items.map(\.label).contains("pitchMode=fixed"))
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
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 8, character: 5)
        )
        let labels = items.map(\.label)
        // Scale degree chords (triads, secondary dominants, modal mixture, sevenths, extended, slash)
        #expect(labels.contains("1"))
        #expect(labels.contains("2m"))
        #expect(labels.contains("3m"))
        #expect(labels.contains("4"))
        #expect(labels.contains("5"))
        #expect(labels.contains("6m"))
        #expect(labels.contains("7dim"))
        #expect(labels.contains("2"))
        #expect(labels.contains("3"))
        #expect(labels.contains("6"))
        #expect(labels.contains("4m"))
        #expect(labels.contains("1maj7"))
        #expect(labels.contains("2m7"))
        #expect(labels.contains("3m7"))
        #expect(labels.contains("4maj7"))
        #expect(labels.contains("57"))
        #expect(labels.contains("6m7"))
        #expect(labels.contains("2m7-5"))
        #expect(labels.contains("1sus4"))
        #expect(labels.contains("5sus4"))
        #expect(labels.contains("1add9"))
        #expect(labels.contains("5/4"))
        #expect(labels.contains("4/5"))
        #expect(labels.contains("1/3"))
        #expect(labels.contains("6m/5"))

        // Absolute letter diatonic chords in C
        #expect(labels.contains("C"))
        #expect(labels.contains("Dm"))
        #expect(labels.contains("Em"))
        #expect(labels.contains("F"))
        #expect(labels.contains("G"))
        #expect(labels.contains("Am"))
        #expect(labels.contains("Bdim"))
        #expect(labels.contains("Cmaj7"))
        #expect(labels.contains("G7"))
        #expect(labels.contains("C/E"))
    }

    @Test("Filters chords when typing prefix inside bracket '[6' or '[F'")
    func testChordCompletionPrefixFiltering() throws {
        let source = """
            ::SCORE::
            ** Prefix Score **
            ?= C
            <4/4>

            verse:Piano@|0|{
                <4*>
                [6
            }
            """
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 7, character: 6)
        )
        let labels = items.map(\.label)
        #expect(labels.contains("6m"))
        #expect(labels.contains("6m7"))
        #expect(labels.contains("6"))
        #expect(labels.contains("6m/5"))
        #expect(!labels.contains("1"))
        #expect(!labels.contains("4maj7"))
    }

    @Test("Provides correct diatonic chords for other major and minor keys (e.g. E major, Eb major, Am)")
    func testChordCompletionAcrossVariousKeys() throws {
        // E Major
        let sourceE = """
            ::SCORE::
            ** E Major **
            ?= E
            <4/4>

            verse:Piano@|0|{
                <4*>
                [
            }
            """
        let itemsE = TmdLSPCompletionEngine.complete(
            source: sourceE,
            position: TmdLSPPosition(line: 7, character: 5)
        )
        let labelsE = itemsE.map(\.label)
        #expect(labelsE.contains("E"))
        #expect(labelsE.contains("F#m"))
        #expect(labelsE.contains("G#m"))
        #expect(labelsE.contains("A"))
        #expect(labelsE.contains("B"))
        #expect(labelsE.contains("C#m"))
        #expect(labelsE.contains("D#dim"))
        #expect(labelsE.contains("B7"))

        // Eb Major
        let sourceEb = """
            ::SCORE::
            ** Eb Major **
            ?= Eb
            <4/4>

            verse:Piano@|0|{
                <4*>
                [
            }
            """
        let itemsEb = TmdLSPCompletionEngine.complete(
            source: sourceEb,
            position: TmdLSPPosition(line: 7, character: 5)
        )
        let labelsEb = itemsEb.map(\.label)
        #expect(labelsEb.contains("Eb"))
        #expect(labelsEb.contains("Fm"))
        #expect(labelsEb.contains("Gm"))
        #expect(labelsEb.contains("Ab"))
        #expect(labelsEb.contains("Bb"))
        #expect(labelsEb.contains("Cm"))
        #expect(labelsEb.contains("Ddim"))
    }

    @Test("Does not append closing ']' if next character is already ']'")
    func testChordCompletionAvoidsDuplicateClosingBracket() throws {
        let source = """
            verse:Piano@|0|{
                <4*>
                []
            }
            """
        let items = TmdLSPCompletionEngine.complete(
            source: source,
            position: TmdLSPPosition(line: 2, character: 5)
        )
        let chordItem = items.first(where: { $0.label == "1" })
        #expect(chordItem?.insertText == "1")
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
        let diagnostics = TmdLSPDiagnosticEngine.diagnose(source: source)
        #expect(!diagnostics.isEmpty)
        let msg = diagnostics[0].message
        #expect(msg.contains("Expected") || msg.contains("units") || msg.contains("measure"))
    }

    @Test("Server handles initialize and completion workflow")
    func testServerLifecycleAndCompletion() throws {
        var sentMessages: [String] = []
        let server = TmdLSPServer { msg in
            sentMessages.append(msg)
        }

        // 1. Initialize
        let initFrame = TmdJSONRPCFrame(id: 1, method: "initialize", params: [:])
        server.handle(message: initFrame)
        #expect(sentMessages.count == 1)
        #expect(sentMessages[0].contains("\"capabilities\""))
        #expect(sentMessages[0].contains("\"triggerCharacters\":[\">\",\"(\",\":\",\"[\",\"{\"]"))

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
                "text": source,
            ]
        ]
        server.handle(
            message: TmdJSONRPCFrame(id: nil, method: "textDocument/didOpen", params: openParams))
        // Expect diagnostics notification sent
        #expect(sentMessages.count >= 2)
        #expect(sentMessages.last?.contains("textDocument/publishDiagnostics") == true)

        // 3. Completion request
        let compParams: [String: Any] = [
            "textDocument": ["uri": "file:///test.tmd"],
            "position": ["line": 10, "character": 3],
        ]
        server.handle(
            message: TmdJSONRPCFrame(id: 2, method: "textDocument/completion", params: compParams))
        let compResponse = sentMessages.last ?? ""
        #expect(compResponse.contains("verse"))
    }

    @Test("Server handles document formatting and outline symbols")
    func testServerFormattingAndSymbols() throws {
        var sentMessages: [String] = []
        let server = TmdLSPServer { msg in
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
                "text": source,
            ]
        ]
        server.handle(
            message: TmdJSONRPCFrame(id: nil, method: "textDocument/didOpen", params: openParams))

        // 1. Formatting
        let formatParams: [String: Any] = [
            "textDocument": ["uri": "file:///test.tmd"]
        ]
        server.handle(
            message: TmdJSONRPCFrame(
                id: 10, method: "textDocument/formatting", params: formatParams))
        let formatResp = sentMessages.last ?? ""
        #expect(formatResp.contains("newText"))

        // 2. Document Symbol
        let symbolParams: [String: Any] = [
            "textDocument": ["uri": "file:///test.tmd"]
        ]
        server.handle(
            message: TmdJSONRPCFrame(
                id: 11, method: "textDocument/documentSymbol", params: symbolParams))
        let symbolResp = sentMessages.last ?? ""
        #expect(symbolResp.contains("Test Score") || symbolResp.contains("verse"))
    }
}
