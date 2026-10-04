import ArgumentParser
import Foundation
import TmdLSP

struct TmdLSPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lsp",
        abstract: "Run the TMD Language Server Protocol (LSP) daemon communicating over standard I/O (JSON-RPC)."
    )

    func run() throws {
        let server = TMDLSPServer { responseString in
            if let data = responseString.data(using: .utf8) {
                FileHandle.standardOutput.write(data)
            }
        }
        var buffer = Data()
        let stdin = FileHandle.standardInput
        while server.isRunning {
            let chunk = stdin.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            for frame in TMDJSONRPCCodec.decode(buffer: &buffer) {
                server.handle(message: frame)
            }
        }
    }
}
