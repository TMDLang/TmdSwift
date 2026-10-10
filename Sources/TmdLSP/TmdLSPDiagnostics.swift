import Foundation
import TmdSwift

public struct TmdLSPDiagnosticEngine {
    public static func diagnose(source: String) -> [TmdLSPDiagnostic] {
        let scoreDiagnostics = TmdScoreValidator.validate(source: source)
        let lines = source.components(separatedBy: "\n")

        return scoreDiagnostics.map { diag in
            let startLine = max(0, diag.line - 1)
            let startCol = max(0, diag.column - 1)
            let endLine = max(startLine, diag.endLine - 1)
            let defaultEndCol = startLine < lines.count ? lines[startLine].utf16.count : 80
            let endCol =
                diag.endColumn > diag.column
                ? max(startCol + 1, diag.endColumn - 1)
                : max(startCol + 1, defaultEndCol)

            let range = TmdLSPRange(
                start: TmdLSPPosition(line: startLine, character: startCol),
                end: TmdLSPPosition(line: endLine, character: endCol)
            )
            let severity = diag.severity == .error ? 1 : 2
            var msg = diag.message
            if let suggestion = diag.suggestion, !suggestion.isEmpty, !msg.contains(suggestion) {
                msg += " (\(suggestion))"
            }
            let sourceName: String
            switch diag.rule {
            case .measureBeat:
                sourceName = "tmd-measure-checker"
            case .syntax:
                sourceName = "tmd-parser"
            default:
                sourceName = "tmd-validator"
            }
            return TmdLSPDiagnostic(
                range: range,
                severity: severity,
                source: sourceName,
                message: msg
            )
        }
    }
}

// MARK: - LSP Server Handler & Event Loop

