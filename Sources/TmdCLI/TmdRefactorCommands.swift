import ArgumentParser
import Foundation
import TmdSwift

struct TmdRefactorRenameInstrument: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename-instrument",
        abstract: "Rename all occurrences of an instrument in a TMD score."
    )

    @Argument(help: "Path to the .tmd file to refactor.")
    var inputPath: String

    @Option(name: .long, help: "Existing instrument name to rename from.")
    var from: String

    @Option(name: .long, help: "New instrument name to rename to.")
    var to: String

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output refactored score to the specified path.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let refactored: String
        do {
            refactored = try TMDRefactor.renameInstrument(in: content, from: from, to: to)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(refactored, to: inputPath)
                print("Renamed instrument in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(refactored, to: outPath)
                print("Refactored score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(refactored, terminator: "")
        }
    }
}

struct TmdRefactorRenameSection: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename-section",
        abstract: "Rename all occurrences of a section across paragraphs and orders in a TMD score."
    )

    @Argument(help: "Path to the .tmd file to refactor.")
    var inputPath: String

    @Option(name: .long, help: "Existing section name to rename from.")
    var from: String

    @Option(name: .long, help: "New section name to rename to.")
    var to: String

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output refactored score to the specified path.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let refactored: String
        do {
            refactored = try TMDRefactor.renameSection(in: content, from: from, to: to)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(refactored, to: inputPath)
                print("Renamed section in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(refactored, to: outPath)
                print("Refactored score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(refactored, terminator: "")
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
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let extracted: String
        do {
            extracted = try TMDRefactor.extractInstrument(from: content, instrument: instrument)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(extracted, to: outPath)
                print("Extracted instrument '\(instrument)' to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(extracted, terminator: "")
        }
    }
}

struct TmdRefactorDoubleGrid: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "double-grid",
        abstract: "Double grid resolution (<4*> -> <8*>) padding units with ties."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Optional instrument filter.")
    var instrument: String?

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the refactored TMD document.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target =
            (section != nil || instrument != nil)
            ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result: String
        do {
            result = try TMDRefactor.doubleGrid(source: content, target: target)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(result, to: inputPath)
                print("Transformed grid (double-grid) in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(result, to: outPath)
                print("Transformed score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
        }
    }
}

struct TmdRefactorHalveGrid: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "halve-grid",
        abstract: "Halve grid resolution (<8*> -> <4*>) collapsing ties."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Optional instrument filter.")
    var instrument: String?

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the refactored TMD document.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target =
            (section != nil || instrument != nil)
            ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result: String
        do {
            result = try TMDRefactor.halveGrid(source: content, target: target)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(result, to: inputPath)
                print("Transformed grid (halve-grid) in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(result, to: outPath)
                print("Transformed score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
        }
    }
}

struct TmdRefactorDuplicateTrack: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "duplicate-track",
        abstract: "Duplicate a track with a new instrument name and optional octave shift."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Option(name: .long, help: "Source instrument name to duplicate.")
    var source: String

    @Option(name: .long, help: "Target new instrument name.")
    var target: String

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Octave shift (e.g. +1, -1).")
    var octave: Int = 0

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the refactored TMD document.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let result: String
        do {
            result = try TMDRefactor.duplicateTrack(
                source: content,
                sourceInstrument: source,
                targetInstrument: target,
                section: section,
                octaveShift: octave
            )
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(result, to: inputPath)
                print("Duplicated track in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(result, to: outPath)
                print("Refactored score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
        }
    }
}

struct TmdRefactorGenerateHarmony: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-harmony",
        abstract: "Generate parallel diatonic harmony for an instrument."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Option(name: .long, help: "Source melody instrument name.")
    var source: String

    @Option(name: .long, help: "Target harmony instrument name.")
    var target: String

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Interval steps (e.g. +2 for 3rd up, -2 for 3rd down).")
    var interval: Int = 2

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the refactored TMD document.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let result: String
        do {
            result = try TMDRefactor.generateHarmony(
                source: content,
                sourceInstrument: source,
                harmonyInstrument: target,
                section: section,
                intervalSteps: interval
            )
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(result, to: inputPath)
                print("Generated harmony in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(result, to: outPath)
                print("Refactored score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
        }
    }
}

struct TmdRefactorInlineOrders: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inline-orders",
        abstract: "Unroll / inline score playback orders into a linear score."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the inlined TMD document.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let result: String
        do {
            result = try TMDRefactor.inlineOrders(source: content)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(result, to: inputPath)
                print("Inlined orders in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(result, to: outPath)
                print("Inlined score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
        }
    }
}

struct TmdRefactorOptimizeGrid: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "optimize-grid",
        abstract:
            "Automatically simplify grid resolution to the minimal divisible scale without altering rhythm."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Optional instrument filter.")
    var instrument: String?

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the refactored TMD document.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target =
            (section != nil || instrument != nil)
            ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result = TMDRefactor.optimizeGrid(source: content, target: target)

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(result, to: inputPath)
                print("Optimized grid in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(result, to: outPath)
                print("Refactored score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
        }
    }
}

struct TmdRefactorTranspose: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transpose",
        abstract:
            "Transpose notes, chords, and key signatures by semitones or diatonic scale steps."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

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

    @Option(name: .long, help: "Optional section filter.")
    var section: String?

    @Option(name: .long, help: "Optional instrument filter.")
    var instrument: String?

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output path for the refactored TMD document.")
    var output: String?

    func run() throws {
        guard semitones != nil || diatonic != nil else {
            print("Error: Either --semitones (-s) or --diatonic (-d) must be specified.")
            throw ExitCode.failure
        }

        let content: String
        do {
            content = try TMDTextIO.readUTF8(from: inputPath)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target =
            (section != nil || instrument != nil)
            ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result = TMDRefactor.transpose(
            source: content,
            semitones: semitones ?? 0,
            diatonicSteps: diatonic ?? 0,
            updateKeySignature: updateKey,
            target: target
        )

        if inPlace {
            do {
                try TMDTextIO.writeUTF8(result, to: inputPath)
                print("Transposed score in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try TMDTextIO.writeUTF8(result, to: outPath)
                print("Refactored score written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(result, terminator: "")
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
