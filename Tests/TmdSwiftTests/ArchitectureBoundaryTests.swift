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
