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
