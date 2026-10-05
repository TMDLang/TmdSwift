import ArgumentParser
import Foundation
import TmdSwift

struct TmdOutlineCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "outline",
        abstract: "Generate a document symbol outline of a TMD score."
    )

    @Argument(help: "Path to the .tmd file to inspect.")
    var inputPath: String

    @Flag(name: [.customLong("json")], help: "Output outline as JSON.")
    var json: Bool = false

    func run() throws {
        let content: String
        do {
            content = try TmdTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let nodes = TmdOutlineGenerator.generate(source: content)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(nodes), let str = String(data: data, encoding: .utf8) {
                print(str)
            } else {
                print("[]")
            }
        } else {
            func printNode(_ node: TmdOutlineNode, indent: Int) {
                let pad = String(repeating: "  ", count: indent)
                var line = "\(pad)- [\(node.kind)] \(node.name)"
                if let detail = node.detail, !detail.isEmpty { line += " (\(detail))" }
                line += " [L\(node.range.startLine):C\(node.range.startColumn) - L\(node.range.endLine):C\(node.range.endColumn)]"
                print(line)
                node.children?.forEach { printNode($0, indent: indent + 1) }
            }
            nodes.forEach { printNode($0, indent: 0) }
        }
    }
}
