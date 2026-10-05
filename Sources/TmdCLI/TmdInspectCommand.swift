import ArgumentParser
import Foundation
import TmdSwift

struct TmdInspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect full song musical profile, vocal tessitura, key modulations, and arrangement density."
    )

    @Argument(help: "Path to the .tmd file to inspect.") var inputPath: String
    @Flag(name: [.customLong("json")], help: "Output song profile as JSON.") var json = false
    @Flag(name: [.customLong("svg")], help: "Output tonality visualizer dashboard as SVG.") var svg = false
    @Flag(name: [.customLong("html")], help: "Output tonality report and dashboard as HTML.") var html = false
    @Option(name: [.customLong("locale")], help: "Localization to use for generated profile text (en or zh-Hant).") var locale: String?

    func run() throws {
        let sheet: Sheet
        do { sheet = try TmdParser.parseThrowing(filePathOrURL: inputPath) }
        catch let parseError as TmdParseError {
            print("Error: Syntax error in \(inputPath):")
            print(parseError.description)
            let codeFrame = parseError.formatCodeFrame()
            if !codeFrame.isEmpty { print("\n" + codeFrame) }
            throw ExitCode.failure
        } catch {
            print("Error reading \(inputPath): \(error.localizedDescription)")
            throw ExitCode.failure
        }
        let profile = TmdSongInspector.inspect(sheet: sheet, locale: inspectionLocale)
        if json {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted]
            if let data = try? encoder.encode(profile), let str = String(data: data, encoding: .utf8) { print(str) }
            else { print("{}") }
        } else if svg { print(TmdTonalityVisualizer.generateSVG(profile)) }
        else if html { print(TmdTonalityVisualizer.generateHTML(profile)) }
        else { print(TmdSongInspector.generateReport(profile)) }
    }

    private var inspectionLocale: TmdLocale {
        guard let locale else { return .en }
        return locale.lowercased().hasPrefix("zh") ? .zhHant : .en
    }
}
