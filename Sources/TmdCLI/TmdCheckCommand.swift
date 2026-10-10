import ArgumentParser
import Foundation
import TmdSwift

struct TmdCheckJSONReport: Codable {
    let filesChecked: Int
    let errorCount: Int
    let warningCount: Int
    let diagnostics: [TmdScoreDiagnostic]
}

struct TmdCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract:
            "Validate TMD scores (syntax, measure beat counts, macros, timeline, and semantic lint rules)."
    )

    @Argument(help: "One or more .tmd/.md file paths or directory paths to check.")
    var inputPaths: [String]

    @Flag(name: .long, help: "Treat warnings as errors (exit with code 1 if any warnings occur).")
    var strict: Bool = false

    @Flag(
        name: [.long, .customLong("md")],
        help: "Also scan .md files for ```tmd fenced code blocks when scanning directories.")
    var markdown: Bool = false

    @Flag(name: .long, help: "Output structured diagnostics as JSON.")
    var json: Bool = false

    func run() throws {
        var targets: [(path: String, isMarkdown: Bool)] = []
        let fm = FileManager.default

        for rawPath in inputPaths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: rawPath, isDirectory: &isDir) else {
                if !json {
                    print("Error reading \(rawPath): No such file or directory")
                }
                throw ExitCode.failure
            }

            if isDir.boolValue {
                let dirURL = URL(fileURLWithPath: rawPath)
                let enumerator = fm.enumerator(
                    at: dirURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
                var discovered: [(path: String, isMarkdown: Bool)] = []
                while let fileURL = enumerator?.nextObject() as? URL {
                    let ext = fileURL.pathExtension.lowercased()
                    if ext == "tmd" {
                        discovered.append((fileURL.path, false))
                    } else if markdown && ext == "md" {
                        discovered.append((fileURL.path, true))
                    }
                }
                discovered.sort { $0.path < $1.path }
                targets.append(contentsOf: discovered)
            } else {
                let ext = URL(fileURLWithPath: rawPath).pathExtension.lowercased()
                targets.append((rawPath, ext == "md" || markdown))
            }
        }

        var allDiagnostics: [TmdScoreDiagnostic] = []
        var hadReadError = false

        for target in targets {
            let content: String
            do {
                content = try TmdTextIO.readUTF8(from: target.path)
            } catch {
                if !json {
                    print("Error reading \(target.path): \(error.localizedDescription)")
                }
                hadReadError = true
                continue
            }

            let diags: [TmdScoreDiagnostic]
            if target.isMarkdown {
                diags = TmdScoreValidator.validateMarkdown(source: content, file: target.path)
            } else {
                diags = TmdScoreValidator.validate(
                    source: content,
                    options: TmdValidationOptions(file: target.path)
                )
            }
            allDiagnostics.append(contentsOf: diags)

            if !json {
                let errors = diags.filter { $0.severity == .error }
                let warnings = diags.filter { $0.severity == .warning }
                if errors.isEmpty && warnings.isEmpty {
                    print("✅ All checks and measures in \(target.path) conform to expected rules and time signatures.")
                } else {
                    if !errors.isEmpty {
                        print(
                            "❌ Found \(errors.count) error\(errors.count == 1 ? "" : "s")\(warnings.isEmpty ? "" : " and \(warnings.count) warning\(warnings.count == 1 ? "" : "s")") in \(target.path):\n"
                        )
                    } else {
                        print(
                            "⚠️ Found \(warnings.count) warning\(warnings.count == 1 ? "" : "s") in \(target.path):\n"
                        )
                    }
                    for d in diags {
                        print(d.description)
                    }
                }
            }
        }

        let errorCount = allDiagnostics.filter { $0.severity == .error }.count
        let warningCount = allDiagnostics.filter { $0.severity == .warning }.count

        if json {
            let report = TmdCheckJSONReport(
                filesChecked: targets.count,
                errorCount: errorCount,
                warningCount: warningCount,
                diagnostics: allDiagnostics
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report),
                let jsonStr = String(data: data, encoding: .utf8)
            {
                print(jsonStr)
            }
        } else if targets.count > 1 {
            print(
                "\nChecked \(targets.count) file(s): \(errorCount) error(s), \(warningCount) warning(s)."
            )
        }

        if hadReadError || errorCount > 0 || (strict && warningCount > 0) {
            throw ExitCode.failure
        }
    }
}
