import ArgumentParser
import Foundation
import TmdSwift
import TmdUtils

struct TmdStudioURLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "studio-url",
        abstract: "Generate a shareable TMD Studio URL (#tmd=...) for a TMD score."
    )

    @Argument(help: "Path to the .tmd file to encode into a TMD Studio URL.")
    var inputPath: String

    @Option(
        name: [.customLong("base-url")],
        help: "Base URL of TMD Studio (defaults to \(TmdStudioShare.defaultBaseURL))."
    )
    var baseURL: String = TmdStudioShare.defaultBaseURL

    @Flag(
        name: [.customLong("open")],
        help: "Open the generated TMD Studio URL in the default web browser."
    )
    var openInBrowser: Bool = false

    @Flag(
        name: [.customLong("copy")],
        help: "Copy the generated TMD Studio URL to the system clipboard."
    )
    var copyToClipboard: Bool = false

    func run() throws {
        let content: String
        do {
            content = try TmdTextIO.readUTF8(
                from: FilePathNormalizer.fileURLToPath(inputPath)
            )
        } catch {
            FileHandle.standardError.write(
                Data("Error reading \(inputPath): \(error.localizedDescription)\n".utf8)
            )
            throw ExitCode.failure
        }

        let studioURL: String
        do {
            studioURL = try TmdStudioShare.generateStudioURL(
                for: content,
                baseURL: baseURL
            )
        } catch {
            FileHandle.standardError.write(
                Data("Error generating TMD Studio URL: \(error.localizedDescription)\n".utf8)
            )
            throw ExitCode.failure
        }

        print(studioURL)

        if copyToClipboard {
            try Self.copyURLToClipboard(studioURL)
        }

        if openInBrowser {
            try Self.openURLInDefaultBrowser(studioURL)
        }
    }

    private static func copyURLToClipboard(_ url: String) throws {
        #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
            let pipe = Pipe()
            process.standardInput = pipe
            do {
                try process.run()
                pipe.fileHandleForWriting.write(Data(url.utf8))
                try pipe.fileHandleForWriting.close()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    FileHandle.standardError.write(
                        Data("Error: pbcopy exited with status \(process.terminationStatus).\n".utf8)
                    )
                    throw ExitCode.failure
                }
            } catch let error as ExitCode {
                throw error
            } catch {
                FileHandle.standardError.write(
                    Data("Error copying URL to clipboard: \(error.localizedDescription)\n".utf8)
                )
                throw ExitCode.failure
            }
        #else
            FileHandle.standardError.write(
                Data("Error: --copy is currently supported only on macOS.\n".utf8)
            )
            throw ExitCode.failure
        #endif
    }

    private static func openURLInDefaultBrowser(_ url: String) throws {
        #if os(macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [url]
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    FileHandle.standardError.write(
                        Data("Error: open exited with status \(process.terminationStatus).\n".utf8)
                    )
                    throw ExitCode.failure
                }
            } catch let error as ExitCode {
                throw error
            } catch {
                FileHandle.standardError.write(
                    Data("Error opening URL in browser: \(error.localizedDescription)\n".utf8)
                )
                throw ExitCode.failure
            }
        #elseif os(Linux)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["xdg-open", url]
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    FileHandle.standardError.write(
                        Data("Error: xdg-open exited with status \(process.terminationStatus).\n".utf8)
                    )
                    throw ExitCode.failure
                }
            } catch let error as ExitCode {
                throw error
            } catch {
                FileHandle.standardError.write(
                    Data("Error opening URL in browser: \(error.localizedDescription)\n".utf8)
                )
                throw ExitCode.failure
            }
        #else
            FileHandle.standardError.write(
                Data("Error: --open is not supported on this platform.\n".utf8)
            )
            throw ExitCode.failure
        #endif
    }
}
