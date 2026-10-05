import Foundation
import Testing
import TmdAudio
import TmdSkill
@testable import TmdSwift

@Test("TMD acronym public symbols use canonical capitalization")
func canonicalTMDPublicNamesExist() {
    let parser: TMDParser.Type = TMDParser.self
    let version: TMDVersion.Type = TMDVersion.self

    #expect(parser == TMDParser.self)
    #expect(version.current == "0.2.1")
}

@Test("TMD acronym public names are used by supporting modules")
func canonicalSupportingModuleNamesExist() {
    #expect(TMDSkill.skillName == "tmd")

    let audioError: TMDAudioError = .unsupportedPlatform
    #expect(audioError.errorDescription != nil)
}

@Test("Legacy Tmd acronym aliases have been removed after caller migration")
func legacyTMDAliasesHaveBeenRemoved() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceFiles = [
        "Sources/TmdSwift/Syntax/Parser.swift",
        "Sources/TmdSwift/Version.swift",
        "Sources/TmdSkill/TmdSkill.swift",
        "Sources/TmdAudio/TmdAudio.swift",
    ]

    for relativePath in sourceFiles {
        let source = try String(contentsOf: packageRoot.appendingPathComponent(relativePath))
        #expect(!source.contains("public typealias Tmd"))
    }
}
