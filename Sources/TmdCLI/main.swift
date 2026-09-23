import Foundation
import ArgumentParser
import TmdSwift
import TmdMIDI
import TmdMusicXML
import TmdLilyPond
import TmdAudio
import TmdABC
import TmdChordPro
import TmdReaper
import TmdSkill
import TmdVocaloid
import TmdUTAU
import TmdUtils

// MARK: - Format Subcommand

struct TmdCheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check measure consistency and report incorrect beat counts between bar lines '|'."
    )

    @Argument(help: "Path to the .tmd file to check.")
    var inputPath: String

    func run() throws {
        let content: String
        do {
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let issues = TMDMeasureChecker.check(source: content)
        if issues.isEmpty {
            print("✅ All measures in \(inputPath) conform to expected time signatures.")
        } else {
            print("❌ Found \(issues.count) measure discrepancy issue\(issues.count == 1 ? "" : "s") in \(inputPath):\n")
            for issue in issues {
                print(issue)
            }
            throw ExitCode.failure
        }
    }
}

struct TmdLSPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lsp",
        abstract: "Run the TMD Language Server Protocol (LSP) daemon communicating over standard I/O (JSON-RPC)."
    )

    func run() throws {
        let server = TMDLSPServer { responseString in
            if let data = responseString.data(using: .utf8) {
                FileHandle.standardOutput.write(data)
            }
        }

        var buffer = Data()
        let stdin = FileHandle.standardInput

        while server.isRunning {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                // EOF reached
                break
            }
            buffer.append(chunk)
            let frames = TMDJSONRPCCodec.decode(buffer: &buffer)
            for frame in frames {
                server.handle(message: frame)
            }
        }
    }
}

struct TmdOutlineCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "outline",
        abstract: "Generate a document symbol outline of a TMD score."
    )

    @Argument(help: "Path to the .tmd file to inspect.")
    var inputPath: String

    @Flag(name: [.customLong("json")], help: "Output outline as JSON.")
    var json: Bool = false

    func run() throws {
        let content: String
        do {
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let nodes = TMDOutlineGenerator.generate(source: content)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(nodes), let str = String(data: data, encoding: .utf8) {
                print(str)
            } else {
                print("[]")
            }
        } else {
            func printNode(_ node: TMDOutlineNode, indent: Int) {
                let pad = String(repeating: "  ", count: indent)
                var line = "\(pad)- [\(node.kind)] \(node.name)"
                if let detail = node.detail, !detail.isEmpty {
                    line += " (\(detail))"
                }
                line += " [L\(node.range.startLine):C\(node.range.startColumn) - L\(node.range.endLine):C\(node.range.endColumn)]"
                print(line)
                if let children = node.children {
                    for child in children {
                        printNode(child, indent: indent + 1)
                    }
                }
            }

            for node in nodes {
                printNode(node, indent: 0)
            }
        }
    }
}

struct TmdInspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect full song musical profile, vocal tessitura, key modulations, and arrangement density."
    )

    @Argument(help: "Path to the .tmd file to inspect.")
    var inputPath: String

    @Flag(name: [.customLong("json")], help: "Output song profile as JSON.")
    var json: Bool = false

    func run() throws {
        let sheet: Sheet
        do {
            sheet = try TmdParser.parseThrowing(filePathOrURL: inputPath)
        } catch let parseError as TMDParseError {
            print("Error: Syntax error in \(inputPath):")
            print(parseError.description)
            let codeFrame = parseError.formatCodeFrame()
            if !codeFrame.isEmpty {
                print("\n" + codeFrame)
            }
            throw ExitCode.failure
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let profile = TMDSongInspector.inspect(sheet: sheet)

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(profile), let str = String(data: data, encoding: .utf8) {
                print(str)
            } else {
                print("{}")
            }
        } else {
            print(TMDSongInspector.generateReport(profile))
        }
    }
}

struct TmdFormatCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Format a TMD file with standardized indentation, spacing, and comments preserved."
    )

    @Argument(help: "Path to the .tmd file to format.")
    var inputPath: String

    @Flag(name: [.short, .long], help: "Modify the file in-place.")
    var inPlace: Bool = false

    @Option(name: [.short, .long], help: "Output formatted score to the specified path.")
    var output: String?

    func run() throws {
        let content: String
        do {
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let formatted = TMDRefactor.format(content)

        if inPlace {
            do {
                try formatted.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Formatted \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try formatted.write(toFile: outPath, atomically: true, encoding: .utf8)
                print("Formatted output written to \(outPath).")
            } catch {
                print("Error writing \(outPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else {
            print(formatted, terminator: "")
        }
    }
}

// MARK: - Refactor Subcommands

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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
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
                try refactored.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Renamed instrument in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try refactored.write(toFile: outPath, atomically: true, encoding: .utf8)
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
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
                try refactored.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Renamed section in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try refactored.write(toFile: outPath, atomically: true, encoding: .utf8)
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
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
                try extracted.write(toFile: outPath, atomically: true, encoding: .utf8)
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target = (section != nil || instrument != nil) ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result: String
        do {
            result = try TMDRefactor.doubleGrid(source: content, target: target)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try result.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Transformed grid (double-grid) in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try result.write(toFile: outPath, atomically: true, encoding: .utf8)
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target = (section != nil || instrument != nil) ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result: String
        do {
            result = try TMDRefactor.halveGrid(source: content, target: target)
        } catch {
            print("Refactor error: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        if inPlace {
            do {
                try result.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Transformed grid (halve-grid) in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try result.write(toFile: outPath, atomically: true, encoding: .utf8)
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
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
                try result.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Duplicated track in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try result.write(toFile: outPath, atomically: true, encoding: .utf8)
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
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
                try result.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Generated harmony in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try result.write(toFile: outPath, atomically: true, encoding: .utf8)
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
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
                try result.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Inlined orders in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try result.write(toFile: outPath, atomically: true, encoding: .utf8)
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
        abstract: "Automatically simplify grid resolution to the minimal divisible scale without altering rhythm."
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target = (section != nil || instrument != nil) ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result = TMDRefactor.optimizeGrid(source: content, target: target)

        if inPlace {
            do {
                try result.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Optimized grid in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try result.write(toFile: outPath, atomically: true, encoding: .utf8)
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
        abstract: "Transpose notes, chords, and key signatures by semitones or diatonic scale steps."
    )

    @Argument(help: "Path to the .tmd file.")
    var inputPath: String

    @Option(name: [.short, .customLong("semitones")], help: "Pitch shift in semitones (e.g. +2, -3).")
    var semitones: Int?

    @Option(name: [.short, .customLong("diatonic")], help: "Diatonic scale step shift (e.g. +2, -1).")
    var diatonic: Int?

    @Flag(name: [.customShort("k"), .customLong("update-key")], help: "Also update score {!K:...} key signatures when transposing semitones.")
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
            content = try String(contentsOfFile: inputPath, encoding: .utf8)
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let target = (section != nil || instrument != nil) ? TMDRefactorTarget(section: section, instrument: instrument) : nil
        let result = TMDRefactor.transpose(
            source: content,
            semitones: semitones ?? 0,
            diatonicSteps: diatonic ?? 0,
            updateKeySignature: updateKey,
            target: target
        )

        if inPlace {
            do {
                try result.write(toFile: inputPath, atomically: true, encoding: .utf8)
                print("Transposed score in \(inputPath) in-place.")
            } catch {
                print("Error writing \(inputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        } else if let outPath = output {
            do {
                try result.write(toFile: outPath, atomically: true, encoding: .utf8)
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
        abstract: "Music score refactoring tools (rename, extract, grid scale, harmony, unroll orders).",
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
            TmdRefactorInlineOrders.self
        ]
    )
}

// MARK: - Main TMD Command

struct TmdCLICommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tmd",
        abstract: "A compiler and toolkit for the TMD (Timebase Mark Down) music markup language.",
        discussion: "In memory of Chen, Chih-Han / aguai (阿怪, 1974–2019).\nOriginal project: https://github.com/aguai/TMDLang",
        version: TmdVersion.current,
        subcommands: [
            TmdCheckCommand.self,
            TmdInspectCommand.self,
            TmdFormatCommand.self,
            TmdOutlineCommand.self,
            TmdRefactorCommand.self
        ]
    )

    @Argument(help: "Path to the .tmd file to process.")
    var inputPath: String?

    @Flag(name: [.short, .long], help: "Only parse and display the score structure summary.")
    var parseOnly: Bool = false

    @Flag(name: [.customLong("inspect")], help: "Inspect full song musical profile, vocal range, and orchestration density.")
    var inspectSong: Bool = false

    @Flag(name: [.long], help: "Play the score using the macOS default sound bank.")
    var play: Bool = false

    @Flag(name: [.long], help: "Install TMD skill definitions to local AI agent skill directories (Codex, Antigravity, Claude, etc.).")
    var installSkills: Bool = false

    @Option(name: [.short, .long], help: "Export to MIDI file at the specified path.")
    var midiOutput: String?

    @Option(name: [.customShort("r"), .long, .customLong("rpp-output")], help: "Export to REAPER project (.rpp) file at the specified path.")
    var reaperOutput: String?

    @Option(name: [.customShort("x"), .long], help: "Export to MusicXML file at the specified path.")
    var musicxmlOutput: String?

    @Option(name: [.customShort("l"), .long], help: "Export to LilyPond (.ly) file at the specified path.")
    var lilypondOutput: String?

    @Option(name: [.customShort("a"), .long], help: "Export to ABC notation (.abc) file at the specified path.")
    var abcOutput: String?

    @Option(name: [.customShort("c"), .customLong("chordpro-output"), .customLong("cho-output")], help: "Export to ChordPro (.cho) file at the specified path.")
    var chordproOutput: String?

    @Option(name: [.long], help: "Render PDF score using lilypond compiler.")
    var pdfOutput: String?

    @Option(name: [.customShort("w"), .long], help: "Render to WAV audio file at the specified path.")
    var wavOutput: String?

    @Option(name: [.customLong("vsq-output")], help: "Export vocal track to VOCALOID2 (.vsq) file at the specified path.")
    var vsqOutput: String?

    @Option(name: [.customLong("vsqx-output")], help: "Export vocal track to VOCALOID3/4 (.vsqx) XML file at the specified path.")
    var vsqxOutput: String?

    @Option(name: [.customShort("u"), .customLong("ust-output")], help: "Export vocal track to UTAU / OpenUtau (.ust) file at the specified path.")
    var ustOutput: String?

    @Option(name: [.long], help: "Vocaloid singer name (defaults to Miku).")
    var singer: String = "Miku"

    @Option(name: [.long], help: "Optional SoundFont (.sf2) or DLS soundbank path for audio rendering.")
    var soundfont: String?

    @Option(name: .long, help: "Optional section filter for MIDI export or playback.")
    var section: String?

    @Option(name: .long, help: "Optional instrument filter for MIDI export or playback.")
    var instrument: String?

    @Flag(name: [.short, .long], help: "Force export even if measure discrepancies are detected.")
    var force: Bool = false

    func run() throws {
        if installSkills {
            print("Installing TMD skill for AI agents...")
            let results = TmdSkill.installSkills()
            if results.isEmpty {
                print("No AI agent directories found to install into.")
            } else {
                for res in results {
                    print(res.message)
                }
            }
            if inputPath == nil {
                return
            }
        }

        guard let inputPath = inputPath else {
            print("Error: Missing expected argument '<input-path>'")
            print("Use --help for usage information, or --install-skills to install AI agent skills.")
            throw ExitCode.failure
        }

        print("TmdSwift v\(TmdVersion.current) - In memory of Chen, Chih-Han / aguai (阿怪, 1974–2019).")

        let fileContent: String
        do {
            fileContent = try String(contentsOfFile: FilePathNormalizer.fileURLToPath(inputPath), encoding: .utf8)
        } catch {
            print("Error: Could not read file at \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let sheet: Sheet
        do {
            sheet = try TmdParser.parseThrowing(string: fileContent)
        } catch let parseError as TMDParseError {
            print("Error: Syntax error in \(inputPath):")
            print(parseError.description)
            let codeFrame = parseError.formatCodeFrame()
            if !codeFrame.isEmpty {
                print("\n" + codeFrame)
            }
            throw ExitCode.failure
        } catch {
            print("Error: Syntax error in \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let isExporting = (midiOutput != nil || reaperOutput != nil || musicxmlOutput != nil ||
                           lilypondOutput != nil || abcOutput != nil || chordproOutput != nil ||
                           pdfOutput != nil || wavOutput != nil || vsqOutput != nil ||
                           vsqxOutput != nil || ustOutput != nil)

        if isExporting && !force {
            let issues = TMDMeasureChecker.check(source: fileContent)
            if !issues.isEmpty {
                print("❌ Export aborted: Found \(issues.count) measure discrepancy issue\(issues.count == 1 ? "" : "s") in \(inputPath):")
                for issue in issues.prefix(10) {
                    print("  - \(issue)")
                }
                if issues.count > 10 {
                    print("  ... and \(issues.count - 10) more issues. Run `tmd check \(inputPath)` to see all.")
                }
                print("\nUse --force (-f) to ignore measure errors and force export.")
                throw ExitCode.failure
            }
        }

        print("Successfully parsed TMD file: \(inputPath)")
        print("----------------------------------------")
        print(sheet.summary())
        print("----------------------------------------")

        if inspectSong {
            let profile = TMDSongInspector.inspect(sheet: sheet)
            print(TMDSongInspector.generateReport(profile))
            return
        }

        if parseOnly {
            return
        }

        if play {
            try play(sheet: sheet, targetParagraph: section, targetInstrument: instrument)
        }

        // Export to MIDI if requested
        if let outputPath = midiOutput {
            let midiData = TMDMIDIGenerator.generateMIDI(
                from: sheet,
                targetParagraph: section,
                targetInstrument: instrument
            )
            let outURL = URL(fileURLWithPath: outputPath)
            do {
                try midiData.write(to: outURL)
                print("MIDI exported successfully to \(outputPath) (\(midiData.count) bytes)")
            } catch {
                print("Error saving MIDI to \(outputPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Export to REAPER project (.rpp) if requested
        if let rppPath = reaperOutput {
            let rppString = TMDReaperGenerator.generateRPP(from: sheet)
            let outURL = URL(fileURLWithPath: rppPath)
            do {
                try rppString.write(to: outURL, atomically: true, encoding: .utf8)
                print("REAPER project exported successfully to \(rppPath) (\(rppString.utf8.count) bytes)")
            } catch {
                print("Error saving REAPER project to \(rppPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Export to MusicXML if requested
        if let xmlPath = musicxmlOutput {
            let xmlString = TMDMusicXMLGenerator.generateMusicXML(from: sheet)
            let outURL = URL(fileURLWithPath: xmlPath)
            do {
                try xmlString.write(to: outURL, atomically: true, encoding: .utf8)
                print("MusicXML exported successfully to \(xmlPath) (\(xmlString.utf8.count) bytes)")
            } catch {
                print("Error saving MusicXML to \(xmlPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Export to LilyPond if requested
        if let lyPath = lilypondOutput {
            let lyString = TMDLilyPondGenerator.generateLilyPond(from: sheet)
            let outURL = URL(fileURLWithPath: lyPath)
            do {
                try lyString.write(to: outURL, atomically: true, encoding: .utf8)
                print("LilyPond exported successfully to \(lyPath) (\(lyString.utf8.count) bytes)")
            } catch {
                print("Error saving LilyPond file to \(lyPath): \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Render to PDF using lilypond command line if requested
        if let pdfPath = pdfOutput {
            let tempLyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".ly")
            let lyString = TMDLilyPondGenerator.generateLilyPond(from: sheet)
            try? lyString.write(to: tempLyURL, atomically: true, encoding: .utf8)

            let pdfBase = pdfPath.hasSuffix(".pdf") ? String(pdfPath.dropLast(4)) : pdfPath
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["lilypond", "--pdf", "-o", pdfBase, tempLyURL.path]

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    print("PDF rendered successfully via LilyPond to \(pdfPath)")
                } else {
                    print("Warning: lilypond exited with status \(process.terminationStatus). Make sure lilypond is installed (e.g. `brew install lilypond`).")
                }
            } catch {
                print("Could not invoke lilypond: \(error.localizedDescription). You can export the .ly file directly using `-l`.")
            }
            try? FileManager.default.removeItem(at: tempLyURL)
        }

        // Export to ABC notation if requested
        if let abcPath = abcOutput {
            let abcString = TMDABCGenerator.generateABC(from: sheet)
            let outURL = URL(fileURLWithPath: abcPath)
            do {
                try abcString.write(to: outURL, atomically: true, encoding: .utf8)
                print("ABC notation exported successfully to \(abcPath) (\(abcString.utf8.count) bytes)")
            } catch {
                print("Error saving ABC notation: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Export to ChordPro if requested
        if let choPath = chordproOutput {
            let choString = TMDChordProGenerator.generateChordPro(from: sheet)
            let outURL = URL(fileURLWithPath: choPath)
            do {
                try choString.write(to: outURL, atomically: true, encoding: .utf8)
                print("ChordPro exported successfully to \(choPath) (\(choString.utf8.count) bytes)")
            } catch {
                print("Error saving ChordPro file: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Render to WAV audio if requested
        if let wavPath = wavOutput {
            let soundBankURL = soundfont.map { URL(fileURLWithPath: $0) }
            do {
                let wavData = try TMDWAVRenderer.renderWAV(
                    from: sheet,
                    soundBankURL: soundBankURL,
                    targetParagraph: section,
                    targetInstrument: instrument
                )
                let outURL = URL(fileURLWithPath: wavPath)
                try wavData.write(to: outURL)
                print("WAV rendered successfully to \(wavPath) (\(wavData.count) bytes)")
            } catch {
                print("Error rendering WAV audio: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Export to VOCALOID2 (.vsq) if requested
        if let vsqPath = vsqOutput {
            let options = VocaloidExportOptions(singerName: singer)
            let vsqData = TMDVSQGenerator.generateVSQ(from: sheet, options: options)
            let outURL = URL(fileURLWithPath: vsqPath)
            do {
                try vsqData.write(to: outURL)
                print("VOCALOID2 (.vsq) exported successfully to \(vsqPath) (\(vsqData.count) bytes)")
            } catch {
                print("Error saving VSQ file: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Export to VOCALOID3/4 (.vsqx) if requested
        if let vsqxPath = vsqxOutput {
            let options = VocaloidExportOptions(singerName: singer)
            let vsqxString = TMDVSQXGenerator.generateVSQX(from: sheet, options: options)
            let outURL = URL(fileURLWithPath: vsqxPath)
            do {
                try vsqxString.write(to: outURL, atomically: true, encoding: .utf8)
                print("VOCALOID3/4 (.vsqx) exported successfully to \(vsqxPath) (\(vsqxString.utf8.count) bytes)")
            } catch {
                print("Error saving VSQX file: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }

        // Export to UTAU / OpenUtau (.ust) if requested
        if let ustPath = ustOutput {
            let options = USTExportOptions(projectName: sheet.name)
            let ustString = TMDUSTGenerator.generateUST(from: sheet, options: options)
            let outURL = URL(fileURLWithPath: ustPath)
            do {
                try ustString.write(to: outURL, atomically: true, encoding: .utf8)
                print("UTAU (.ust) exported successfully to \(ustPath) (\(ustString.utf8.count) bytes)")
            } catch {
                print("Error saving UST file: \(error.localizedDescription)")
                throw ExitCode.failure
            }
        }
    }

    private func play(sheet: Sheet, targetParagraph: String? = nil, targetInstrument: String? = nil) throws {
#if os(macOS)
        let soundBankURL = soundfont.map { URL(fileURLWithPath: $0) }
        let wavData: Data
        do {
            wavData = try TMDWAVRenderer.renderWAV(
                from: sheet,
                soundBankURL: soundBankURL,
                targetParagraph: targetParagraph,
                targetInstrument: targetInstrument
            )
        } catch {
            print("Error rendering audio for playback: \(error.localizedDescription)")
            throw ExitCode.failure
        }

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tmd-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            try wavData.write(to: tempURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            process.arguments = [tempURL.path]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                print("Error: afplay exited with status \(process.terminationStatus).")
                throw ExitCode.failure
            }
        } catch let error as ExitCode {
            throw error
        } catch {
            print("Error playing audio: \(error.localizedDescription)")
            throw ExitCode.failure
        }
#else
        print("Error: --play is currently supported only on macOS.")
        throw ExitCode.failure
#endif
    }
}

// Route subcommand dispatch manually if first argument matches a subcommand
let rawArgs = Array(CommandLine.arguments.dropFirst())
if let first = rawArgs.first, ["lsp", "check", "inspect", "outline", "format", "refactor"].contains(first) {
    if first == "lsp" {
        TmdLSPCommand.main(Array(rawArgs.dropFirst()))
    } else if first == "check" {
        TmdCheckCommand.main(Array(rawArgs.dropFirst()))
    } else if first == "inspect" {
        TmdInspectCommand.main(Array(rawArgs.dropFirst()))
    } else if first == "outline" {
        TmdOutlineCommand.main(Array(rawArgs.dropFirst()))
    } else if first == "format" {
        TmdFormatCommand.main(Array(rawArgs.dropFirst()))
    } else {
        TmdRefactorCommand.main(Array(rawArgs.dropFirst()))
    }
} else {
    TmdCLICommand.main()
}
