import ArgumentParser
import TmdSwift

struct TmdCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract:
            "Check measure consistency and report incorrect beat counts between bar lines '|'."
    )

    @Argument(help: "Path to the .tmd file to check.")
    var inputPath: String

    func run() throws {
        let content: String
        do {
            content = try TmdTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let issues = TmdMeasureChecker.check(source: content)
        if issues.isEmpty {
            print("✅ All measures in \(inputPath) conform to expected time signatures.")
        } else {
            print(
                "❌ Found \(issues.count) measure discrepancy issue\(issues.count == 1 ? "" : "s") in \(inputPath):\n"
            )
            for issue in issues {
                print(issue)
            }
            throw ExitCode.failure
        }
    }
}
