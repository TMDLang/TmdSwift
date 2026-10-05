import Foundation
import Testing

@Test("Core responsibilities have explicit source boundaries")
func coreResponsibilitiesHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    let canonicalFiles = [
        ("Syntax", "TmdParser.swift"),
        ("Validation", "TmdMeasureChecker.swift"),
        ("Analysis", "TmdSongInspector.swift"),
        ("Playback", "TmdPlaybackRenderer.swift"),
    ]

    for (boundary, file) in canonicalFiles {
        let path = sourceRoot.appendingPathComponent(boundary).appendingPathComponent(file).path
        #expect(FileManager.default.fileExists(atPath: path))
    }
}

@Test("Syntax lexer, parser, and diagnostics have separate source boundaries")
func syntaxResponsibilitiesHaveExplicitSourceBoundaries() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let syntaxRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Syntax")
    for file in ["Lexer.swift", "TmdParser.swift", "TmdParseDiagnostics.swift"] {
        #expect(FileManager.default.fileExists(atPath: syntaxRoot.appendingPathComponent(file).path))
    }
    let parser = try String(contentsOf: syntaxRoot.appendingPathComponent("TmdParser.swift"))
    #expect(!parser.contains("public final class Lexer"))
    #expect(!parser.contains("public struct TmdParseError"))
}

@Test("Inspector analyzers stay inside the analysis boundary")
func inspectorAnalyzersHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let analysisRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Analysis")
    let files = [
        "TmdSongHarmonyAnalyzer.swift",
        "TmdSongPitchRangeAnalyzer.swift",
        "TmdSongTimingAnalyzer.swift",
        "TmdSongTonalityAnalyzer.swift",
    ]

    for file in files {
        #expect(FileManager.default.fileExists(atPath: analysisRoot.appendingPathComponent(file).path))
    }
}

@Test("Inspector profiles have an explicit source boundary")
func inspectorProfilesHaveExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let analysisRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Analysis")
    #expect(FileManager.default.fileExists(atPath: analysisRoot.appendingPathComponent("TmdSongProfiles.swift").path))
    let inspector = try String(contentsOf: analysisRoot.appendingPathComponent("TmdSongInspector.swift"))
    #expect(!inspector.contains("public struct TmdSongProfile"))
}

@Test("Text I/O and source refactoring stay outside the syntax core")
func toolResponsibilitiesHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    let files = [
        "IO/TmdTextIO.swift",
        "Refactoring/TmdRefactor.swift",
    ]

    for file in files {
        #expect(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(file).path))
    }
}

@Test("Refactoring formatting helpers have an explicit responsibility boundary")
func refactoringFormattingHasExplicitBoundary() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let path = packageRoot.appendingPathComponent("Sources/TmdSwift/Refactoring/TmdRefactorFormatting.swift").path
    #expect(FileManager.default.fileExists(atPath: path))
}

@Test("Refactoring transposition has an explicit responsibility boundary")
func refactoringTransposeHasExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let refactoringRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Refactoring")
    #expect(FileManager.default.fileExists(atPath: refactoringRoot.appendingPathComponent("TmdRefactorTranspose.swift").path))
    let facade = try String(contentsOf: refactoringRoot.appendingPathComponent("TmdRefactor.swift"))
    #expect(!facade.contains("public static func transpose("))
}

@Test("Refactoring grid operations have an explicit responsibility boundary")
func refactoringGridHasExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let refactoringRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Refactoring")
    #expect(FileManager.default.fileExists(atPath: refactoringRoot.appendingPathComponent("TmdRefactorGrid.swift").path))
    let facade = try String(contentsOf: refactoringRoot.appendingPathComponent("TmdRefactor.swift"))
    #expect(!facade.contains("public static func doubleGrid("))
}

@Test("Refactoring track operations have an explicit responsibility boundary")
func refactoringTracksHaveExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let refactoringRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Refactoring")
    #expect(FileManager.default.fileExists(atPath: refactoringRoot.appendingPathComponent("TmdRefactorTracks.swift").path))
    let facade = try String(contentsOf: refactoringRoot.appendingPathComponent("TmdRefactor.swift"))
    #expect(!facade.contains("public static func duplicateTrack("))
}

@Test("Macro transformations have an explicit playback boundary")
func macroTransformationsHaveExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let playbackRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Playback")
    #expect(FileManager.default.fileExists(atPath: playbackRoot.appendingPathComponent("TmdMacroTransformations.swift").path))
    let evaluator = try String(contentsOf: playbackRoot.appendingPathComponent("TmdMacroEvaluator.swift"))
    #expect(!evaluator.contains("public static func transposeSections"))
}

@Test("Presentation consumers stay outside the syntax core")
func presentationResponsibilitiesHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    let files = [
        "Presentation/TmdOutline.swift",
        "Presentation/TmdTonalityVisualizer.swift",
    ]

    for file in files {
        #expect(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(file).path))
    }
}

@Test("LSP data models have an explicit source boundary")
func lspDataModelsHaveExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let lspRoot = packageRoot.appendingPathComponent("Sources/TmdLSP")
    #expect(FileManager.default.fileExists(atPath: lspRoot.appendingPathComponent("TmdLSPTypes.swift").path))
    let implementation = try String(contentsOf: lspRoot.appendingPathComponent("TmdLSP.swift"))
    #expect(!implementation.contains("public struct TmdLSPPosition"))
}

@Test("LSP JSON-RPC codec has an explicit source boundary")
func lspCodecHasExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let lspRoot = packageRoot.appendingPathComponent("Sources/TmdLSP")
    #expect(FileManager.default.fileExists(atPath: lspRoot.appendingPathComponent("TmdLSPCodec.swift").path))
    let implementation = try String(contentsOf: lspRoot.appendingPathComponent("TmdLSP.swift"))
    #expect(!implementation.contains("public struct TmdJSONRPCCodec"))
}

@Test("LSP completion engine has an explicit source boundary")
func lspCompletionHasExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let lspRoot = packageRoot.appendingPathComponent("Sources/TmdLSP")
    #expect(FileManager.default.fileExists(atPath: lspRoot.appendingPathComponent("TmdLSPCompletion.swift").path))
    let implementation = try String(contentsOf: lspRoot.appendingPathComponent("TmdLSP.swift"))
    #expect(!implementation.contains("public struct TmdLSPCompletionEngine"))
}

@Test("LSP diagnostic engine has an explicit source boundary")
func lspDiagnosticHasExplicitBoundary() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let lspRoot = packageRoot.appendingPathComponent("Sources/TmdLSP")
    #expect(FileManager.default.fileExists(atPath: lspRoot.appendingPathComponent("TmdLSPDiagnostics.swift").path))
    let implementation = try String(contentsOf: lspRoot.appendingPathComponent("TmdLSP.swift"))
    #expect(!implementation.contains("public struct TmdLSPDiagnosticEngine"))
}

@Test("Source formatting stays inside the syntax boundary")
func sourceFormattingHasExplicitSyntaxBoundary() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    #expect(
        FileManager.default.fileExists(
            atPath: sourceRoot.appendingPathComponent("Syntax/Format.swift").path))
    #expect(
        !FileManager.default.fileExists(
            atPath: sourceRoot.appendingPathComponent("Formatting/Format.swift").path))
}

@Test("Macro expansion stays inside the playback boundary")
func macroResponsibilitiesHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let path = packageRoot.appendingPathComponent("Sources/TmdSwift/Playback/TmdMacroEvaluator.swift").path
    #expect(FileManager.default.fileExists(atPath: path))
}

@Test("Measure rendering stays inside the playback boundary")
func measureRenderingHasExplicitPlaybackBoundary() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    #expect(
        FileManager.default.fileExists(
            atPath: sourceRoot.appendingPathComponent("Playback/TmdMeasureRenderer.swift").path))
    #expect(
        !FileManager.default.fileExists(
            atPath: sourceRoot.appendingPathComponent("Measure.swift").path))
}

@Test("The canonical source model stays inside the syntax boundary")
func sourceModelHasExplicitSyntaxBoundary() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let path = packageRoot.appendingPathComponent("Sources/TmdSwift/Syntax/Types.swift").path
    #expect(FileManager.default.fileExists(atPath: path))
}

@Test("Inspector localization stays inside the analysis boundary")
func inspectorLocalizationHasExplicitAnalysisBoundary() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    for file in ["TmdLocalization.swift", "TmdLocalizationCatalog.swift"] {
        #expect(
            FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent("Analysis").appendingPathComponent(file).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent(file).path))
    }
}

@Test("AST measure checking and lexer fallback have separate implementations")
func measureCheckerSeparatesASTAndLexerFallback() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let validationRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Validation")
    #expect(
        FileManager.default.fileExists(
            atPath: validationRoot.appendingPathComponent("TmdMeasureLexerFallback.swift").path))
    let checker = try String(
        contentsOf: validationRoot.appendingPathComponent("TmdMeasureChecker.swift"))
    #expect(!checker.contains("private static func checkWithLexer"))
}
