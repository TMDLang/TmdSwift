import Testing
import TmdABC
import TmdLilyPond
import TmdMusicXML

@testable import TmdSwift

@Suite("Engraving repeat export tests")
struct EngravingRepeatTests {
    private let source = """
        ::SCORE::
        ** Engraving Repeat **
        != 120
        ?= C
        <4/4>

        verse:Vocal@|0|{
            <4*>
            | 1 2 3 4 |
            L1| la li lu le |
            L2| sa si su se |
        }

        -> verse[L1] -> verse[L2] ->#
        """

    @Test("folds consecutive stanza-selected playback into notation repeats")
    func foldsConsecutiveStanzaPlayback() throws {
        let sheet = try #require(TmdParser.parse(string: source))
        let abc = TmdABCGenerator.generateABC(from: sheet)
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        #expect(abc.contains("|:") && abc.contains(":|"))
        #expect(abc.contains("w: 1.") && abc.contains("w: 2."))
        #expect(xml.contains("<repeat direction=\"backward\""))
        #expect(xml.contains("<ending number=\"1\""))
        #expect(lily.contains("\\repeat volta 2"))
        #expect(lily.contains("\\set stanza = \"1.\""))
        #expect(lily.contains("\\set stanza = \"2.\""))
    }

    @Test("marks section transitions and score endings")
    func marksSectionTransitionsAndEndings() throws {
        let sheet = try #require(TmdParser.parse(string: source.replacingOccurrences(of: "-> verse[L1] -> verse[L2] ->#", with: "-> verse[L1] ->#")))
        let abc = TmdABCGenerator.generateABC(from: sheet)
        let xml = TmdMusicXMLGenerator.generateMusicXML(from: sheet)
        let lily = TmdLilyPondGenerator.generateLilyPond(from: sheet)

        #expect(abc.contains("|]"))
        #expect(xml.contains("<bar-style>light-heavy</bar-style>"))
        #expect(lily.contains("\\bar \"|.\""))
    }
}
