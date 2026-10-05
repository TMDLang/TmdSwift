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
        ("Syntax", "Parser.swift"),
        ("Validation", "MeasureCheck.swift"),
        ("Analysis", "SongInspector.swift"),
        ("Playback", "Playback.swift"),
    ]

    for (boundary, file) in canonicalFiles {
        let path = sourceRoot.appendingPathComponent(boundary).appendingPathComponent(file).path
        #expect(FileManager.default.fileExists(atPath: path))
    }
}

@Test("Inspector analyzers stay inside the analysis boundary")
func inspectorAnalyzersHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let analysisRoot = packageRoot.appendingPathComponent("Sources/TmdSwift/Analysis")
    let files = [
        "SongHarmonyAnalyzer.swift",
        "SongPitchRangeAnalyzer.swift",
        "SongTimingAnalyzer.swift",
        "SongTonalityAnalyzer.swift",
    ]

    for file in files {
        #expect(FileManager.default.fileExists(atPath: analysisRoot.appendingPathComponent(file).path))
    }
}

@Test("Text I/O and source refactoring stay outside the syntax core")
func toolResponsibilitiesHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    let files = [
        "IO/TMDTextIO.swift",
        "Refactoring/Refactor.swift",
    ]

    for file in files {
        #expect(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(file).path))
    }
}

@Test("Presentation consumers stay outside the syntax core")
func presentationResponsibilitiesHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = packageRoot.appendingPathComponent("Sources/TmdSwift")
    let files = [
        "Formatting/Format.swift",
        "Presentation/Outline.swift",
        "Presentation/TonalityVisualizer.swift",
    ]

    for file in files {
        #expect(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent(file).path))
    }
}

@Test("Macro expansion stays inside the playback boundary")
func macroResponsibilitiesHaveExplicitSourceBoundaries() {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let path = packageRoot.appendingPathComponent("Sources/TmdSwift/Playback/MacroEvaluator.swift").path
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
            atPath: sourceRoot.appendingPathComponent("Playback/Measure.swift").path))
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
    for file in ["Localization.swift", "LocalizationCatalog.swift"] {
        #expect(
            FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent("Analysis").appendingPathComponent(file).path))
        #expect(
            !FileManager.default.fileExists(
                atPath: sourceRoot.appendingPathComponent(file).path))
    }
}
