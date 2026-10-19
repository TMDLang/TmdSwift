import Foundation
import Testing

@testable import TmdSwift

private let zeldaSample = """
::SCORE::
** Zelda's Lullaby **
!= 100
?= C
<4/4>

lullaby:ocarina@|0|{
    <4*>
    7_ - 2 6_ - (5_6_)%(-) 7_ - 2 6_ - 0
    2^ - (1^ 7 1^ 7)%(--) 5 -
}

-> lullaby -> lullaby ->#

"""

@Test("Share hash round-trips scores including CJK text through a URL-safe hash")
func shareHashRoundTripsScores() throws {
    for text in [zeldaSample, "::SCORE::\n** 三天三夜 **\n", ""] {
        let hash = try TmdStudioShare.encodeShareHash(text)
        #expect(hash.hasPrefix("#tmd="))
        let payload = String(hash.dropFirst("#tmd=".count))
        #expect(
            payload.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
            }
        )
        let decoded = try TmdStudioShare.decodeShareHash(hash)
        #expect(decoded == text)
    }
}

@Test("Decodes reference deflate-raw share hashes produced by Tmd-TS Web Studio")
func decodesReferenceTmdTSShareHashes() throws {
    let emptyDecoded = try TmdStudioShare.decodeShareHash("#tmd=AwA")
    #expect(emptyDecoded == "")

    let cjkDecoded = try TmdStudioShare.decodeShareHash(
        "#tmd=s7IKdvYPcrWy4tLSUniyo_PpkpVgco6ClhYXAA"
    )
    #expect(cjkDecoded == "::SCORE::\n** 三天三夜 **\n")

    let zeldaDecoded = try TmdStudioShare.decodeShareHash(
        "#tmd=s7IKdvYPcrWy4tLSUohKzUlJVC9W8CnNyUlMqlTQ0uJStFUwNDDgsrdVcOayMdE3sePiyoHIWuUnJxZl5iU61BjUVHMpAIGNiZYdmGEer6CrYKRgBqI0TOPN4jVVNXQ1UYQNwAqN4kAqDOMUzBVABEgZUJ2pgi5XLReXrp0C1CoFFKYyFwA"
    )
    #expect(zeldaDecoded == zeldaSample)
}

@Test("Returns nil when the hash is not a TMD share link")
func returnsNilWhenHashIsNotAShareLink() throws {
    #expect(try TmdStudioShare.decodeShareHash("") == nil)
    #expect(try TmdStudioShare.decodeShareHash("#") == nil)
    #expect(try TmdStudioShare.decodeShareHash("#section-2") == nil)
}

@Test("Rejects damaged deflate-raw or base64url payloads")
func rejectsDamagedPayloads() {
    #expect(throws: TmdStudioShareError.self) {
        _ = try TmdStudioShare.decodeShareHash("#tmd=bm90LWRlZmxhdGU")
    }
    #expect(throws: TmdStudioShareError.self) {
        _ = try TmdStudioShare.decodeShareHash("#tmd=***")
    }
}

@Test("Rejects a payload that is not valid UTF-8")
func rejectsInvalidUTF8Payload() throws {
    let invalidUTF8A = try TmdStudioShare.compressRawDeflate(Data([0x61, 0xff, 0x62]))
    let hashA = "#tmd=" + TmdStudioShare.base64URLEncode(invalidUTF8A)
    #expect(throws: TmdStudioShareError.invalidUTF8Payload) {
        _ = try TmdStudioShare.decodeShareHash(hashA)
    }

    let truncatedUTF8 = try TmdStudioShare.compressRawDeflate(Data([0x61, 0xe3, 0x81]))
    let hashB = "#tmd=" + TmdStudioShare.base64URLEncode(truncatedUTF8)
    #expect(throws: TmdStudioShareError.invalidUTF8Payload) {
        _ = try TmdStudioShare.decodeShareHash(hashB)
    }
}

@Test("Enforces MAX_SHARED_CHARS limit on encode and decode")
func enforcesSizeLimitOnEncodeAndDecode() throws {
    let overLimit = String(repeating: "a", count: TmdStudioShare.maxSharedChars + 1)
    #expect(throws: TmdStudioShareError.scoreTooLarge) {
        _ = try TmdStudioShare.encodeShareHash(overLimit)
    }

    let atLimit = String(repeating: "a", count: TmdStudioShare.maxSharedChars)
    let encodedAtLimit = try TmdStudioShare.encodeShareHash(atLimit)
    #expect(try TmdStudioShare.decodeShareHash(encodedAtLimit) == atLimit)

    let compressedOverLimit = try TmdStudioShare.compressRawDeflate(Data(overLimit.utf8))
    let overLimitHash = "#tmd=" + TmdStudioShare.base64URLEncode(compressedOverLimit)
    #expect(throws: TmdStudioShareError.scoreTooLarge) {
        _ = try TmdStudioShare.decodeShareHash(overLimitHash)
    }
}

@Test("Generates full TMD Studio URL with default and custom base URLs")
func generatesFullStudioURL() throws {
    let text = "::SCORE::\n** 三天三夜 **\n"
    let defaultURL = try TmdStudioShare.generateStudioURL(for: text)
    #expect(defaultURL.hasPrefix("https://tmdlang.github.io/Tmd-TS/#tmd="))
    let hashPart = String(
        defaultURL.dropFirst("https://tmdlang.github.io/Tmd-TS/".count)
    )
    #expect(try TmdStudioShare.decodeShareHash(hashPart) == text)

    let customURL = try TmdStudioShare.generateStudioURL(
        for: text,
        baseURL: "https://example.com/studio"
    )
    #expect(customURL.hasPrefix("https://example.com/studio/#tmd="))
}

@Test("CLI studio-url subcommand outputs valid TMD Studio share URL")
func cliStudioURLCommandOutputsValidShareLink() throws {
    let source = """
        ::SCORE::
        ** CLI Studio URL Test **
        != 120
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

    guard let tmdURL = TmdTestHelper.findTmdExecutable() else {
        Issue.record("tmd binary must be built and available")
        return
    }

    let outPipe = Pipe()
    let process = Process()
    process.executableURL = tmdURL
    process.arguments = ["studio-url", tmdPath]
    process.standardOutput = outPipe
    try process.run()
    process.waitUntilExit()

    #expect(process.terminationStatus == 0)
    let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    #expect(output.hasPrefix("https://tmdlang.github.io/Tmd-TS/#tmd="))
    let hashPart = String(output.dropFirst("https://tmdlang.github.io/Tmd-TS/".count))
    let decoded = try TmdStudioShare.decodeShareHash(hashPart)
    #expect(decoded == source)

    // Custom --base-url
    let customPipe = Pipe()
    let customProcess = Process()
    customProcess.executableURL = tmdURL
    customProcess.arguments = [
        "studio-url", "--base-url", "https://studio.example.org/app", tmdPath,
    ]
    customProcess.standardOutput = customPipe
    try customProcess.run()
    customProcess.waitUntilExit()

    #expect(customProcess.terminationStatus == 0)
    let customOutput = String(
        data: customPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    #expect(customOutput.hasPrefix("https://studio.example.org/app/#tmd="))

    // Non-existent file exits with non-zero status
    let missingProcess = Process()
    missingProcess.executableURL = tmdURL
    missingProcess.arguments = ["studio-url", tempDir.appendingPathComponent("missing.tmd").path]
    missingProcess.standardError = Pipe()
    try missingProcess.run()
    missingProcess.waitUntilExit()
    #expect(missingProcess.terminationStatus != 0)
}

@Test("TmdStudioURLCommand avoids macOS 10.15-gated FileHandle.close() for default deployment target compatibility")
func studioURLCommandAvoidsAvailabilityGatedFileHandleClose() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let commandPath = packageRoot.appendingPathComponent("Sources/TmdCLI/TmdStudioURLCommand.swift")
    let source = try String(contentsOf: commandPath, encoding: .utf8)
    #expect(!source.contains("fileHandleForWriting.close()"))
    #expect(source.contains("fileHandleForWriting.closeFile()"))
}
