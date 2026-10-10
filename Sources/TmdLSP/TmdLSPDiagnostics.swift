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
            let severity = diag.severity.lspSeverityCode
            var msg = diag.message
            if let suggestion = diag.suggestion, !suggestion.isEmpty, !msg.contains(suggestion) {
                msg += " (\(suggestion))"
            }
            return TmdLSPDiagnostic(
                range: range,
                severity: severity,
                source: diag.rule.lspSourceName,
                message: msg
            )
        }
    }
}

private extension TmdDiagnosticSeverity {
    var lspSeverityCode: Int {
        switch self {
        case .error: 1
        case .warning: 2
        }
    }
}

private extension TmdDiagnosticRule {
    var lspSourceName: String {
        switch self {
        case .measureBeat:
            "tmd-measure-checker"
        case .syntax:
            "tmd-parser"
        default:
            "tmd-validator"
        }
    }
}

