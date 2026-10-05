import Foundation

/// Shared UTF-8 text input/output used by command-line subcommands.
public enum TmdTextIO {
    public static func readUTF8(from path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    public static func writeUTF8(_ content: String, to path: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
