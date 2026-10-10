import ArgumentParser
import Foundation
import TmdSwift

/// Shared file input/output options and execution runner for CLI score refactoring commands.
struct TmdRefactorIOOptions: ParsableArguments {
    @Argument(help: "Path to the .tmd file to refactor.")
    var inputPath: String

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the refactored TMD document.")
    var output: String?

    func execute(
        inPlaceMessage: (String) -> String,
        outputMessage: (String) -> String = { "Refactored score written to \($0)." },
        transform: (String) throws -> String
    ) throws {
        try Self.run(
            inputPath: inputPath,
            inPlace: inPlace,
            output: output,
            inPlaceMessage: inPlaceMessage,
            outputMessage: outputMessage,
            transform: transform
        )
    }

    static func run(
        inputPath: String,
        inPlace: Bool,
        output: String?,
        inPlaceMessage: (String) -> String,
        outputMessage: (String) -> String = { "Refactored score written to \($0)." },
        transform: (String) throws -> String
    ) throws {
        let content: String
        do {
            content = try TmdTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let result: String
        do {
            result = try transform(content)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TmdTextIO.writeUTF8(result, to: inputPath)
                print(inPlaceMessage(inputPath))
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TmdTextIO.writeUTF8(result, to: outPath)
                print(outputMessage(outPath))
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
        }
    }
}

/// Shared optional section and instrument target filter options for CLI score refactoring commands.
struct TmdRefactorFilterOptions: ParsableArguments {
    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Optional instrument filter.")
    var instrument: String?

    var target: TmdRefactorTarget? {
        TmdRefactorTarget.resolve(section: section, instrument: instrument)
    }
}

struct TmdRefactorRenameInstrument: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename-instrument",
        abstract: "Rename all occurrences of an instrument in a TMD score."
    )

    @OptionGroup var io: TmdRefactorIOOptions

    @Option(name: .long, help: "Existing instrument name to rename from.")
    var from: String

    @Option(name: .long, help: "New instrument name to rename to.")
    var to: String

    func run() throws {
        try io.execute(inPlaceMessage: { "Renamed instrument in \($0) in-place." }) { content in
            try TmdRefactor.renameInstrument(in: content, from: from, to: to)
        }
    }
}

struct TmdRefactorRenameSection: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename-section",
        abstract: "Rename all occurrences of a section across paragraphs and orders in a TMD score."
    )

    @OptionGroup var io: TmdRefactorIOOptions

    @Option(name: .long, help: "Existing section name to rename from.")
    var from: String

    @Option(name: .long, help: "New section name to rename to.")
    var to: String

    func run() throws {
        try io.execute(inPlaceMessage: { "Renamed section in \($0) in-place." }) { content in
            try TmdRefactor.renameSection(in: content, from: from, to: to)
        }
    }
}

struct TmdRefactorExtractInstrument: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "extract-instrument",
        abstract: "Extract all tracks belonging to an instrument into a separate TMD document."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Option(name: .long, help: "Instrument name to extract.")
    var instrument: String

    @Option(name: [.short, .long], help: "Output path for the extracted TMD document.")
    var output: String?

    func run() throws {
        try TmdRefactorIOOptions.run(
            inputPath: inputPath,
            inPlace: false,
            output: output,
            inPlaceMessage: { _ in "" },
            outputMessage: { "Extracted instrument '\(instrument)' to \($0)." }
        ) { content in
            try TmdRefactor.extractInstrument(from: content, instrument: instrument)
        }
    }
}

struct TmdRefactorDoubleGrid: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "double-grid",
        abstract: "Double grid resolution (<4*> -> <8*>) padding units with ties."
    )

    @OptionGroup var io: TmdRefactorIOOptions
    @OptionGroup var filter: TmdRefactorFilterOptions

    func run() throws {
        try io.execute(
            inPlaceMessage: { "Transformed grid (double-grid) in \($0) in-place." },
            outputMessage: { "Transformed score written to \($0)." }
        ) { content in
            try TmdRefactor.doubleGrid(source: content, target: filter.target)
        }
    }
}

struct TmdRefactorHalveGrid: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "halve-grid",
        abstract: "Halve grid resolution (<8*> -> <4*>) collapsing ties."
    )

    @OptionGroup var io: TmdRefactorIOOptions
    @OptionGroup var filter: TmdRefactorFilterOptions

    func run() throws {
        try io.execute(
            inPlaceMessage: { "Transformed grid (halve-grid) in \($0) in-place." },
            outputMessage: { "Transformed score written to \($0)." }
        ) { content in
            try TmdRefactor.halveGrid(source: content, target: filter.target)
        }
    }
}

struct TmdRefactorDuplicateTrack: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicate-track",
        abstract: "Duplicate a track with a new instrument name and optional octave shift."
    )

    @OptionGroup var io: TmdRefactorIOOptions

    @Option(name: .long, help: "Source instrument name to duplicate.")
    var source: String

    @Option(name: .long, help: "Target new instrument name.")
    var target: String

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Octave shift (e.g. +1, -1).")
    var octave: Int = 0

    func run() throws {
        try io.execute(inPlaceMessage: { "Duplicated track in \($0) in-place." }) { content in
            try TmdRefactor.duplicateTrack(
                source: content,
                sourceInstrument: source,
                targetInstrument: target,
                section: section,
                octaveShift: octave
            )
        }
    }
}

struct TmdRefactorGenerateHarmony: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-harmony",
        abstract: "Generate parallel diatonic harmony for an instrument."
    )

    @OptionGroup var io: TmdRefactorIOOptions

    @Option(name: .long, help: "Source melody instrument name.")
    var source: String

    @Option(name: .long, help: "Target harmony instrument name.")
    var target: String

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Interval steps (e.g. +2 for 3rd up, -2 for 3rd down).")
    var interval: Int = 2

    func run() throws {
        try io.execute(inPlaceMessage: { "Generated harmony in \($0) in-place." }) { content in
            try TmdRefactor.generateHarmony(
                source: content,
                sourceInstrument: source,
                harmonyInstrument: target,
                section: section,
                intervalSteps: interval
            )
        }
    }
}

struct TmdRefactorInlineOrders: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inline-orders",
        abstract: "Unroll / inline score playback orders into a linear score."
    )

    @OptionGroup var io: TmdRefactorIOOptions

    func run() throws {
        try io.execute(
            inPlaceMessage: { "Inlined orders in \($0) in-place." },
            outputMessage: { "Inlined score written to \($0)." }
        ) { content in
            try TmdRefactor.inlineOrders(source: content)
        }
    }
}

struct TmdRefactorOptimizeGrid: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "optimize-grid",
        abstract:
            "Automatically simplify grid resolution to the minimal divisible scale without altering rhythm."
    )

    @OptionGroup var io: TmdRefactorIOOptions
    @OptionGroup var filter: TmdRefactorFilterOptions

    func run() throws {
        try io.execute(inPlaceMessage: { "Optimized grid in \($0) in-place." }) { content in
            TmdRefactor.optimizeGrid(source: content, target: filter.target)
        }
    }
}

struct TmdRefactorTranspose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transpose",
        abstract:
            "Transpose notes, chords, and key signatures by semitones or diatonic scale steps."
    )

    @OptionGroup var io: TmdRefactorIOOptions

    @Option(
        name: [.short, .customLong("semitones")], help: "Pitch shift in semitones (e.g. +2, -3).")
    var semitones: Int?

    @Option(
        name: [.short, .customLong("diatonic")], help: "Diatonic scale step shift (e.g. +2, -1).")
    var diatonic: Int?

    @Flag(
        name: [.customShort("k"), .customLong("update-key")],
        help: "Also update score {!K:...} key signatures when transposing semitones.")
    var updateKey: Bool = false

    @OptionGroup var filter: TmdRefactorFilterOptions

    func run() throws {
        guard semitones != nil || diatonic != nil else {
            print("Error: Either --semitones (-s) or --diatonic (-d) must be specified.")
            throw ExitCode.failure
        }

        try io.execute(inPlaceMessage: { "Transposed score in \($0) in-place." }) { content in
            TmdRefactor.transpose(
                source: content,
                semitones: semitones ?? 0,
                diatonicSteps: diatonic ?? 0,
                updateKeySignature: updateKey,
                target: filter.target
            )
        }
    }
}

struct TmdRefactorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refactor",
        abstract:
            "Music score refactoring tools (rename, extract, grid scale, harmony, unroll orders).",
        subcommands: [
            TmdRefactorRenameInstrument.self,
            TmdRefactorRenameSection.self,
            TmdRefactorExtractInstrument.self,
            TmdRefactorDoubleGrid.self,
            TmdRefactorHalveGrid.self,
            TmdRefactorOptimizeGrid.self,
            TmdRefactorTranspose.self,
            TmdRefactorDuplicateTrack.self,
            TmdRefactorGenerateHarmony.self,
            TmdRefactorInlineOrders.self,
        ]
    )
}
