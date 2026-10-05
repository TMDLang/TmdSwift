import ArgumentParser
import TmdSwift

struct TmdFormatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Format a TMD file with standardized indentation, spacing, and comments preserved."
    )
    @Argument(help: "Path to the .tmd file to format.") var inputPath: String
    @Flag(name: [.short, .long], help: "Modify the file in-place.") var inPlace = false
    @Option(name: [.short, .long], help: "Output formatted score to the specified path.") var output: String?

    func run() throws {
        let content: String
        do { content = try TmdTextIO.readUTF8(from: inputPath) }
        catch { print("Error reading \(inputPath): \(error.localizedDescription)"); throw ExitCode.failure }
        let formatted = TmdRefactor.format(content)
        if inPlace {
            do { try TmdTextIO.writeUTF8(formatted, to: inputPath); print("Formatted \(inputPath) in-place.") }
            catch { print("Error writing \(inputPath): \(error.localizedDescription)"); throw ExitCode.failure }
        } else if let output {
            do { try TmdTextIO.writeUTF8(formatted, to: output); print("Formatted output written to \(output).") }
            catch { print("Error writing \(output): \(error.localizedDescription)"); throw ExitCode.failure }
        } else { print(formatted, terminator: "") }
    }
}
