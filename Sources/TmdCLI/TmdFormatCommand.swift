import ArgumentParser
import TmdSwift

struct TmdFormatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Format a TMD file with standardized indentation, spacing, and comments preserved."
    )
    @OptionGroup var io: TmdRefactorIOOptions

    func run() throws {
        try io.execute(
            inPlaceMessage: { "Formatted \($0) in-place." },
            outputMessage: { "Formatted output written to \($0)." }
        ) { content in
            TmdRefactor.format(content)
        }
    }
}
