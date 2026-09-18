import Testing
import Foundation
@testable import TmdSwift

@Test func testTMDOutlineGeneration() throws {
    let source = """
    ::SCORE::
    ** My Song **
    != 128
    ?= G
    <4/4>

    intro:CHORD@|0|{
        <4*>
        [G] [D] [Em] [C] |
    }

    intro:Piano@|0|{
        <4*>
        1 2 3 4 |
    }

    verse:CHORD@|0|{
        <4*>
        [G] - [D] - |
    }

    -> intro -> verse ->#
    """

    let nodes = TMDOutlineGenerator.generate(source: source)

    // Verify top-level structure: Score node, Sections node, and Orders node
    #expect(nodes.count == 3)

    // 1. Score node
    let scoreNode = nodes[0]
    #expect(scoreNode.name == "Score: My Song")
    #expect(scoreNode.kind == "class")
    #expect(scoreNode.detail?.contains("!= 128") == true)
    #expect(scoreNode.detail?.contains("?= G") == true)
    #expect(scoreNode.detail?.contains("<4/4>") == true)

    // 2. Sections node
    let sectionsNode = nodes[1]
    #expect(sectionsNode.name == "Sections")
    #expect(sectionsNode.kind == "namespace")
    guard let sectionChildren = sectionsNode.children else {
        #expect(Bool(false), "Sections should have children")
        return
    }
    #expect(sectionChildren.count == 2) // "intro" and "verse"

    let introNode = sectionChildren[0]
    #expect(introNode.name == "intro")
    #expect(introNode.kind == "namespace")
    let introTracks = introNode.children ?? []
    #expect(introTracks.count == 2)
    #expect(introTracks[0].name == "CHORD")
    #expect(introTracks[0].kind == "field")
    #expect(introTracks[0].children == nil)

    #expect(introTracks[1].name == "Piano")
    #expect(introTracks[1].kind == "field")
    #expect(introTracks[1].children == nil)

    let verseNode = sectionChildren[1]
    #expect(verseNode.name == "verse")
    #expect(verseNode.kind == "namespace")
    let verseTracks = verseNode.children ?? []
    #expect(verseTracks.count == 1)
    #expect(verseTracks[0].name == "CHORD")
    #expect(verseTracks[0].kind == "field")
    #expect(verseTracks[0].children == nil)

    // 3. Orders node
    let ordersNode = nodes[2]
    #expect(ordersNode.name == "Orders")
    #expect(ordersNode.kind == "event")
    #expect(ordersNode.detail == "-> intro -> verse ->#")
    let orderChildren = ordersNode.children ?? []
    #expect(orderChildren.count == 2)
    #expect(orderChildren[0].name == "intro")
    #expect(orderChildren[0].kind == "method")
    #expect(orderChildren[1].name == "verse")
    #expect(orderChildren[1].kind == "method")

    // Verify JSON encoding can be decoded back cleanly
    let jsonData = try JSONEncoder().encode(nodes)
    let decodedNodes = try JSONDecoder().decode([TMDOutlineNode].self, from: jsonData)
    #expect(decodedNodes == nodes)
}

@Test func testCLIOutlineCommand() throws {
    let source = """
    ::SCORE::
    ** CLI Outline Test **
    != 100
    ?= C
    <4/4>

    intro:Piano@|0|{
        <4*>
        1 2 3 4 |
    }

    -> intro ->#
    """

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tmdPath = tempDir.appendingPathComponent("score.tmd").path
    try source.write(toFile: tmdPath, atomically: true, encoding: .utf8)

    var tmdURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).deletingLastPathComponent().appendingPathComponent("tmd")
    if !FileManager.default.isExecutableFile(atPath: tmdURL.path) {
        let fallbackURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/out/Products/Debug/tmd")
        if FileManager.default.isExecutableFile(atPath: fallbackURL.path) {
            tmdURL = fallbackURL
        }
    }
    #expect(FileManager.default.isExecutableFile(atPath: tmdURL.path), "tmd binary must be built and available")
    guard FileManager.default.isExecutableFile(atPath: tmdURL.path) else { return }

    let outlinePipe = Pipe()
    let process = Process()
    process.executableURL = tmdURL
    process.arguments = ["outline", "--json", tmdPath]

    process.standardOutput = outlinePipe
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    let data = outlinePipe.fileHandleForReading.readDataToEndOfFile()
    let parsedNodes = try JSONDecoder().decode([TMDOutlineNode].self, from: data)
    #expect(parsedNodes.count == 3)
    #expect(parsedNodes[0].name == "Score: CLI Outline Test")
}

