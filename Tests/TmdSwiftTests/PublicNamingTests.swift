import Foundation
import Testing
import TmdAudio
import TmdSkill
@testable import TmdSwift

@Test("Tmd prefix public symbols use canonical capitalization")
func canonicalTmdPublicNamesExist() {
    let parser: TmdParser.Type = TmdParser.self
    let version: TmdVersion.Type = TmdVersion.self
    let checker: TmdMeasureChecker.Type = TmdMeasureChecker.self
    let inspector: TmdSongInspector.Type = TmdSongInspector.self
    let renderer: TmdPlaybackRenderer.Type = TmdPlaybackRenderer.self
    let textIO: TmdTextIO.Type = TmdTextIO.self

    #expect(parser == TmdParser.self)
    #expect(version.current == "0.2.3")
    #expect(checker == TmdMeasureChecker.self)
    #expect(inspector == TmdSongInspector.self)
    #expect(renderer == TmdPlaybackRenderer.self)
    #expect(textIO == TmdTextIO.self)
}

@Test("Release version stays aligned across the extension manifest and install instructions")
func releaseVersionIsConsistentAcrossPublishedMetadata() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let version = TmdVersion.current
    let extensionManifest = try Data(contentsOf: packageRoot.appendingPathComponent("editor/vscode/package.json"))
    let manifest = try #require(JSONSerialization.jsonObject(with: extensionManifest) as? [String: Any])
    let extensionVersion = try #require(manifest["version"] as? String)
    let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"))

    #expect(version == "0.2.3")
    #expect(extensionVersion == version)
    #expect(readme.contains("zonble.tmd-vscode-\(version)"))
}

@Test("Tmd prefix public names are used by supporting modules")
func canonicalSupportingModuleNamesExist() {
    #expect(TmdSkill.skillName == "tmd")

    let audioError: TmdAudioError = .unsupportedPlatform
    #expect(audioError.errorDescription != nil)
}

@Test("Canonical Tmd source filenames match the public symbols")
func canonicalTmdSourceFilenamesMatchSymbols() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceFiles = [
        "Sources/TmdSwift/Syntax/TmdParser.swift",
        "Sources/TmdSwift/TmdVersion.swift",
        "Sources/TmdSkill/TmdSkill.swift",
        "Sources/TmdAudio/TmdAudio.swift",
        "Sources/TmdSwift/Validation/TmdMeasureChecker.swift",
        "Sources/TmdSwift/Analysis/TmdSongInspector.swift",
        "Sources/TmdSwift/Playback/TmdPlaybackRenderer.swift",
        "Sources/TmdSwift/IO/TmdTextIO.swift",
    ]

    for relativePath in sourceFiles {
        #expect(FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(relativePath).path))
    }
}

@Test("README uses canonical Tmd* symbols, TmdParserIO, and refactor --from/--to flags")
func readmeUsesCanonicalTmdSymbolsAndRefactorFlags() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let readme = try String(contentsOf: packageRoot.appendingPathComponent("README.md"), encoding: .utf8)

    for staleSymbol in [
        "TMDSongInspector",
        "TMDTonalityVisualizer",
        "TMDLocale",
        "TMDMIDIGenerator",
        "TMDMusicXMLGenerator",
        "TMDLilyPondGenerator",
        "TMDABCGenerator",
        "TmdParser.parse(filePathOrURL:",
        "rename-instrument sample/basic/三天三夜.tmd --source",
        "rename-section sample/basic/三天三夜.tmd --source",
    ] {
        #expect(!readme.contains(staleSymbol), "README.md should not contain stale reference: \(staleSymbol)")
    }

    for canonicalReference in [
        "TmdSongInspector.inspect(sheet: sheet, locale: .en)",
        "TmdSongInspector.generateReport(profile)",
        "TmdTonalityVisualizer.generateHTML(profile, locale: .en)",
        "TmdLocale",
        "TmdParserIO.parse(filePathOrURL:",
        "TmdMIDIGenerator.generateMIDI(from: sheet)",
        "TmdMusicXMLGenerator.generateMusicXML(from: sheet)",
        "TmdLilyPondGenerator.generateLilyPond(from: sheet)",
        "TmdABCGenerator.generateABC(from: sheet)",
        #"rename-instrument sample/basic/三天三夜.tmd --from "Piano" --to "Keys""#,
        #"rename-section sample/basic/三天三夜.tmd --from "verse" --to "A""#,
    ] {
        #expect(readme.contains(canonicalReference), "README.md should contain canonical reference: \(canonicalReference)")
    }
}

@Test("ARCHITECTURE_PARITY.md lists existing canonical Swift paths including TmdParserIO and TmdParseDiagnostics")
func architectureParityMatrixReferencesExistingCanonicalSwiftPaths() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let parityDoc = try String(
        contentsOf: packageRoot.appendingPathComponent("ARCHITECTURE_PARITY.md"),
        encoding: .utf8
    )

    #expect(parityDoc.contains("Sources/TmdSwift/IO/TmdParserIO.swift"))
    #expect(parityDoc.contains("Sources/TmdSwift/Syntax/TmdParseDiagnostics.swift"))

    let regex = try NSRegularExpression(pattern: #"Sources/TmdSwift/[A-Za-z0-9_./]+"#)
    let nsRange = NSRange(parityDoc.startIndex..<parityDoc.endIndex, in: parityDoc)
    let matches = regex.matches(in: parityDoc, range: nsRange)
    #expect(!matches.isEmpty)

    for match in matches {
        guard let range = Range(match.range, in: parityDoc) else { continue }
        let relPath = String(parityDoc[range])
        #expect(
            FileManager.default.fileExists(atPath: packageRoot.appendingPathComponent(relPath).path),
            "Path in ARCHITECTURE_PARITY.md must exist: \(relPath)"
        )
    }
}

@Test("Bundled editor/vscode/skill.md stays synchronized with TmdSkill.skillMarkdown SSOT")
func vscodeBundledSkillMarkdownMatchesTmdSkillSSOT() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let vscodeSkill = try String(
        contentsOf: packageRoot.appendingPathComponent("editor/vscode/skill.md"),
        encoding: .utf8
    )

    #expect(TmdSkill.skillMarkdown.contains("[pitchMode=fixed]"))
    #expect(vscodeSkill == TmdSkill.skillMarkdown)
}
