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
