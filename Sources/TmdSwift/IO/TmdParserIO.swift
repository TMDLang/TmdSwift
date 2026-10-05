import Foundation
import TmdUtils

/// Loads encoded TMD sources before handing pure text to `TmdParser`.
public enum TmdParserIO {
    public static func parseThrowing(data: Data) throws -> Sheet {
        guard let result = TextEncodingDetector.detectAndDecode(data) else {
            throw TmdParseError(
                message: "Unable to decode source",
                token: .eof,
                text: "",
                range: SourceRange(
                    start: SourcePosition(offset: 0, line: 1, column: 1), length: 0))
        }
        return try TmdParser.parseThrowing(string: result.content)
    }

    public static func parseThrowing(url: URL) throws -> Sheet {
        try parseThrowing(data: Data(contentsOf: url))
    }

    public static func parseThrowing(filePathOrURL: String) throws -> Sheet {
        let cleanPath = FilePathNormalizer.fileURLToPath(filePathOrURL)
        return try parseThrowing(url: URL(fileURLWithPath: cleanPath))
    }

    public static func parse(data: Data) -> Sheet? {
        guard let result = TextEncodingDetector.detectAndDecode(data) else { return nil }
        return TmdParser.parse(string: result.content)
    }

    public static func parse(url: URL) throws -> Sheet? {
        return parse(data: try Data(contentsOf: url))
    }

    public static func parse(filePathOrURL: String) throws -> Sheet? {
        let cleanPath = FilePathNormalizer.fileURLToPath(filePathOrURL)
        return try parse(url: URL(fileURLWithPath: cleanPath))
    }
}
