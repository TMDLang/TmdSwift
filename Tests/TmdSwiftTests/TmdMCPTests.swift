import Testing
@testable import TmdMCP

@Suite("TMD MCP server")
struct TmdMCPTests {
    @Test("exposes the shared TMD MCP tool contract")
    func exposesToolContract() {
        #expect(TmdMCPServer.toolNames == [
            "get_tmd_skill", "parse_tmd", "check_tmd", "convert_tmd", "tmd_export_braille",
        ])
    }
}
