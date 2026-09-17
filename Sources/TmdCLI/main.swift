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

struct TmdRefactorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refactor",
        abstract: "Music score refactoring tools (rename instruments, rename sections, extract tracks).",
        subcommands: [
            TmdRefactorRenameInstrument.self,
            TmdRefactorRenameSection.self,
            TmdRefactorExtractInstrument.self
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
            TmdFormatCommand.self,
            TmdRefactorCommand.self
        ]
    )

    @Argument(help: "Path to the .tmd file to process.")
    var inputPath: String?

    @Flag(name: [.short, .long], help: "Only parse and display the score structure summary.")
    var parseOnly: Bool = false

    @Flag(name: [.long], help: "Play the score using the macOS default sound bank.")
    var play: Bool = false

    @Flag(name: [.long], help: "Install TMD skill definitions to local AI agent skill directories (Codex, Antigravity, Claude, etc.).")
    var installSkills: Bool = false

    @Option(name: [.short, .long], help: "Export to MIDI file at the specified path.")
    var midiOutput: String?

    @Option(name: [.customShort("r"), .long], help: "Export to REAPER project (.rpp) file at the specified path.")
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
        let sheet: Sheet
        do {
            sheet = try TmdParser.parseThrowing(filePathOrURL: inputPath)
        } catch {
            print("Error: Could not read or decode file at \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }

        print("Successfully parsed TMD file: \(inputPath)")
        print("----------------------------------------")
        print(sheet.summary())
        print("----------------------------------------")

        if parseOnly {
            return
        }

        if play {
            try play(sheet: sheet)
        }

        // Export to MIDI if requested
        if let outputPath = midiOutput {
            let midiData = TMDMIDIGenerator.generateMIDI(from: sheet)
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
            let soundBankURL = soundfont != nil ? URL(fileURLWithPath: soundfont!) : nil
            do {
                let wavData = try TMDWAVRenderer.renderWAV(from: sheet, soundBankURL: soundBankURL)
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

    private func play(sheet: Sheet) throws {
#if os(macOS)
        let soundBankURL = soundfont.map { URL(fileURLWithPath: $0) }
        let wavData: Data
        do {
            wavData = try TMDWAVRenderer.renderWAV(from: sheet, soundBankURL: soundBankURL)
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
if let first = rawArgs.first, ["check", "format", "refactor"].contains(first) {
    if first == "check" {
        TmdCheckCommand.main(Array(rawArgs.dropFirst()))
    } else if first == "format" {
        TmdFormatCommand.main(Array(rawArgs.dropFirst()))
    } else {
        TmdRefactorCommand.main(Array(rawArgs.dropFirst()))
    }
} else {
    TmdCLICommand.main()
}
