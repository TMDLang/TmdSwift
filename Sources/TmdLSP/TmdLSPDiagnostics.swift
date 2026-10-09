import Foundation
import TmdSwift

public struct TmdLSPDiagnosticEngine {
    public static func diagnose(source: String) -> [TmdLSPDiagnostic] {
        var diagnostics: [TmdLSPDiagnostic] = []
        let lines = source.components(separatedBy: "\n")

        // 1. Measure consistency check
        let issues = TmdMeasureChecker.check(source: source)
        for issue in issues {
            let line = max(0, issue.lineNumber - 1)
            let col = 0
            let endCharacter = line < lines.count ? lines[line].utf16.count : 80
            let range = TmdLSPRange(
                start: TmdLSPPosition(line: line, character: col),
                end: TmdLSPPosition(line: line, character: endCharacter)
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

