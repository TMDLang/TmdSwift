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
