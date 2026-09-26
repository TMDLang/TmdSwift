import Testing
@testable import TmdSwift

struct TonalityContractTests {
    private func inferentialScore(_ movableDoBase: String, playback: String = "") -> String {
        """
        ::SCORE::
        ** Inference Contract **
        != 120
        ?= \(movableDoBase)
        <4/4>

        verse:Vocal@|0|{
            <4*>
            6 1 3 6
            6 1 3 6
        }

        verse:CHORD@|0|{
            <4*>
            [Am] - [Dm] -
            [E] - [Am] -
        }

        \(playback) -> verse ->#
        """
    }

    @Test func keepsMovableDoContextSeparateAndInfersMinor() throws {
        let sheet = try #require(TmdParser.parse(string: inferentialScore("C")))
        let profile = TMDSongInspector.inspect(sheet: sheet)
        let tonality = try #require(profile.tonality)

        #expect(sheet.keySignature.description == "C")
        #expect(tonality.playbackContext.movableDoBase == "C")
        #expect(tonality.globalInference.tonic == "A")
        #expect(tonality.globalInference.mode == .minor)
        #expect(tonality.globalInference.confidence > 0)
    }

    @Test func keepsDeclaredKeySeparateFromMovableDoContext() throws {
        let tmd = """
        ::SCORE::
        ** Explicit Key Context **
        != 120
        ?= D
        key= Bm
        <4/4>

        verse:Vocal@|0|{
            <4*>
            6 1 3 6
        }

        -> verse ->#
        """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let tonality = try #require(TMDSongInspector.inspect(sheet: sheet).tonality)

        #expect(sheet.keySignature.description == "D")
        #expect(sheet.declaredKey == "Bm")
        #expect(tonality.playbackContext.movableDoBase == "D")
        #expect(tonality.declaredKey == "Bm")
    }

    @Test func reportsInsufficientEvidenceWithoutForcingMajor() throws {
        let tmd = """
        ::SCORE::
        ** Empty Tonality **
        != 120
        ?= C
        <4/4>

        verse:Piano@|0|{
            <4*>
            0 - - -
        }

        -> verse ->#
        """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let tonality = try #require(TMDSongInspector.inspect(sheet: sheet).tonality)

        #expect(tonality.globalInference.mode == .insufficient)
        #expect(tonality.globalInference.tonic == nil)
        #expect(tonality.globalInference.confidence == 0)
    }

    @Test func keepsPlaybackTranspositionSeparateFromInferredModulation() throws {
        let sheet = try #require(TmdParser.parse(string: inferentialScore("C", playback: "-> verse -> {?+2}")))
        let tonality = try #require(TMDSongInspector.inspect(sheet: sheet).tonality)

        #expect(tonality.playbackTranspositionPath == [0, 2])
        #expect(tonality.inferredModulationPath.isEmpty)
    }

    @Test func reportsModulationOnlyWhenSectionInferenceChanges() throws {
        let tmd = """
        ::SCORE::
        ** Inferred Section Change **
        != 120
        ?= C
        <4/4>

        major:Vocal@|0|{
            <4*>
            1 2 3 4
            5 6 7 1^
            1 2 3 4
            5 6 7 1^
        }

        major:CHORD@|0|{
            <4*>
            [C] - [F] -
            [G] - [C] -
            [C] - [F] -
            [G] - [C] -
        }

        minor:Vocal@|0|{
            <4*>
            6 7 1 2
            3 4 5 6
            6 7 1 2
            3 4 5 6
        }

        minor:CHORD@|0|{
            <4*>
            [Am] - [Dm] -
            [E] - [Am] -
            [Am] - [Dm] -
            [E] - [Am] -
        }

        -> major -> minor ->#
        """
        let sheet = try #require(TmdParser.parse(string: tmd))
        let tonality = try #require(TMDSongInspector.inspect(sheet: sheet).tonality)

        #expect(tonality.sections.map { $0.inferredTonality.mode } == [.major, .minor])
        #expect(tonality.inferredModulationPath.count == 1)
        #expect(tonality.inferredModulationPath[0].tonic == "A")
    }
}
