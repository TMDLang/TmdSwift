import Testing
import Foundation
@testable import TmdSwift
import TmdMIDI
import TmdMusicXML
import TmdLilyPond
import TmdUtils
import TmdAudio
import TmdABC
import TmdSkill

@Test func testParseTMDScore() throws {
    let tmd = """
    ::SCORE::
    /* Comment block */
    ** Test Song **
    != 120.0
    ?= C
    <4/4>

    intro:Piano@|0|{
        <4*>
        1 2 3 4
        (1' 2, 3^ 4_)%(--)
        [Cmaj7] -
    }

    -> intro -> {?relative_part} -> {?=absolute_part} ->#
    """

    let sheet = TmdParser.parse(string: tmd)
    #expect(sheet != nil)
    guard let sheet = sheet else { return }

    #expect(sheet.name == "Test Song")
    #expect(sheet.speed == 120.0)
    #expect(sheet.keySignature == KeySignature(tonic: .c))
    #expect(sheet.beat.count == 4)
    #expect(sheet.beat.noteValue == 4)

    #expect(sheet.paragraphs.count == 1)
    let paragraph = sheet.paragraphs[0]
    #expect(paragraph.name == "intro")
    #expect(paragraph.instrument == "Piano")
    #expect(paragraph.start == 0)
    #expect(paragraph.sections.count == 1)

    let section = paragraph.sections[0]
    #expect(section.noteLength == 4)
    #expect(section.unitGroups.count == 7)

    // 1 2 3 4
    #expect(section.unitGroups[0].units[0] == .note(Note(accidental: .natural, degree: 1, octave: 0)))
    #expect(section.unitGroups[1].units[0] == .note(Note(accidental: .natural, degree: 2, octave: 0)))
    #expect(section.unitGroups[2].units[0] == .note(Note(accidental: .natural, degree: 3, octave: 0)))
    #expect(section.unitGroups[3].units[0] == .note(Note(accidental: .natural, degree: 4, octave: 0)))

    // (1' 2, 3^ 4_)%(--)
    let group5 = section.unitGroups[4]
    #expect(group5.length == 2)
    #expect(group5.units.count == 4)
    #expect(group5.units[0] == .note(Note(accidental: .sharp, degree: 1, octave: 0)))
    #expect(group5.units[1] == .note(Note(accidental: .flat, degree: 2, octave: 0)))
    #expect(group5.units[2] == .note(Note(accidental: .natural, degree: 3, octave: 1)))
    #expect(group5.units[3] == .note(Note(accidental: .natural, degree: 4, octave: -1)))

    // [Cmaj7]
    let group6 = section.unitGroups[5]
    #expect(group6.units[0] == .chord("Cmaj7"))

    // -
    let group7 = section.unitGroups[6]
    #expect(group7.units[0] == .tie)

    // Orders
    #expect(sheet.orders.count == 3)
    #expect(sheet.orders[0] == .name("intro"))
    #expect(sheet.orders[1] == .relative("relative_part"))
    #expect(sheet.orders[2] == .absolute("absolute_part"))
}

@Test func testParseData() throws {
    let tmd = "::SCORE::\n** Song **\n!=90\n?=G\n<3/4>\n->#"
    let data = Data(tmd.utf8)
    let sheet = TmdParser.parse(data: data)
    #expect(sheet != nil)
    #expect(sheet?.name == "Song")
    #expect(sheet?.speed == 90.0)
    #expect(sheet?.keySignature == KeySignature(tonic: .g))
    #expect(sheet?.beat.count == 3)
    #expect(sheet?.beat.noteValue == 4)
}

@Test func testTokenize() throws {
    let text = "::SCORE:: ** Title ** != 120 ?= C <4/4> ->#"
    let tokens = Lexer(string: text).tokenize()
    #expect(tokens == [
        .scoreHeader,
        .doubleAsterisk,
        .identifier("Title"),
        .doubleAsterisk,
        .speedPrefix,
        .number(120),
        .keySignaturePrefix,
        .identifier("C"),
        .openAngle,
        .note(Note(accidental: .natural, degree: 4, octave: 0)),
        .slash,
        .note(Note(accidental: .natural, degree: 4, octave: 0)),
        .closeAngle,
        .arrowEnd,
        .eof
    ])
}

@Test func testTokenRanges() throws {
    let tokens = Lexer(string: "::SCORE::\n** Song **").tokenizeWithRanges()
    #expect(tokens[0].text == "::SCORE::")
    #expect(tokens[0].range.start.line == 1)
    #expect(tokens[0].range.start.column == 1)
    #expect(tokens[1].text == "**")
    #expect(tokens[1].range.start.line == 2)
    #expect(tokens[1].range.start.column == 1)
}

@Test func testThrowingParserReportsOffendingToken() throws {
    do {
        _ = try TmdParser.parseThrowing(string: "not-a-score")
        Issue.record("Expected a parse error")
    } catch let error as TMDParseError {
        #expect(error.text == "not-a-score")
        #expect(error.range.start.line == 1)
        #expect(error.range.start.column == 1)
        #expect(error.expectedTokens.contains("::SCORE::"))
        #expect(error.description.contains("not-a-score"))
        #expect(error.description.contains("expected ::SCORE::"))
    }
}

@Test func testThrowingParserRejectsMalformedParagraph() throws {
    do {
        _ = try TmdParser.parseThrowing(string: "::SCORE::\nintro")
        Issue.record("Expected a parse error")
    } catch let error as TMDParseError {
        #expect(error.text == "intro")
        #expect(error.range.start.line == 2)
        #expect(error.expectedTokens.contains(":"))
        #expect(error.description.contains("expected :"))
    }
}

@Test func testThrowingParserReportsExpectedTokensForPunctuation() throws {
    // Missing '@' in paragraph header
    do {
        _ = try TmdParser.parseThrowing(string: "::SCORE::\nintro:Piano|0|{\n<4*>\n1 2 3 4\n}")
        Issue.record("Expected a parse error for missing @")
    } catch let error as TMDParseError {
        #expect(error.expectedTokens.contains("@"))
        #expect(error.description.contains("expected @"))
    }

    // Missing '{' in paragraph header
    do {
        _ = try TmdParser.parseThrowing(string: "::SCORE::\nintro:Piano@|0|\n<4*>\n1 2 3 4\n}")
        Issue.record("Expected a parse error for missing {")
    } catch let error as TMDParseError {
        #expect(error.expectedTokens.contains("{"))
        #expect(error.description.contains("expected {"))
    }

    // Missing '<' inside paragraph section
    do {
        _ = try TmdParser.parseThrowing(string: "::SCORE::\nintro:Piano@|0|{\n4*>\n1 2 3 4\n}")
        Issue.record("Expected a parse error for missing <")
    } catch let error as TMDParseError {
        #expect(error.expectedTokens.contains("<"))
        #expect(error.description.contains("expected <"))
    }
}

@Test func testParserRejectsInvalidUnitTokenInParagraph() throws {
    let tmd = """
    ::SCORE::
    ** Invalid Token Test **
    != 120
    ?= C
    <4/4>

    intro:Drums@|0|{
        <8*>
        | A - - - A - - - |
    }
    -> intro ->#
    """
    #expect(throws: TMDParseError.self) {
        _ = try TmdParser.parseThrowing(string: tmd)
    }
}

@Test func testParseSampleFile() throws {
    let sampleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sample/basic/三天三夜.tmd")
    let data = try Data(contentsOf: sampleURL)
    let sheet = TmdParser.parse(data: data)
    #expect(sheet != nil)
    #expect(sheet?.name == "三天三夜")
    #expect(sheet?.speed == 133.0)
    #expect(sheet?.beat.count == 4)
    #expect(sheet?.beat.noteValue == 4)
    #expect(sheet?.paragraphs.count == 10)
    #expect(sheet?.orders.count == 13)

    // Verify summary()
    let summaryText = sheet?.summary() ?? ""
    #expect(summaryText.contains("三天三夜"))
    #expect(summaryText.contains("133.0 BPM"))

    // Verify format() roundtrip parsing
    let formattedTMD = sheet?.format() ?? ""
    let reparsed = TmdParser.parse(string: formattedTMD)
    #expect(reparsed != nil)
    #expect(reparsed?.name == sheet?.name)
    #expect(reparsed?.speed == sheet?.speed)
    #expect(reparsed?.paragraphs.count == sheet?.paragraphs.count)
    #expect(reparsed?.orders.count == sheet?.orders.count)

    // Verify MIDI generation
    if let validSheet = sheet {
        let midi = TMDMIDIGenerator.generateMIDI(from: validSheet)
        #expect(!midi.isEmpty)
        #expect(midi.starts(with: [0x4D, 0x54, 0x68, 0x64])) // "MThd"

        // Verify MusicXML generation
        let xml = TMDMusicXMLGenerator.generateMusicXML(from: validSheet)
        #expect(xml.contains("score-partwise"))
        #expect(xml.contains("三天三夜"))
        #expect(xml.contains("<part-list>"))
        #expect(xml.contains("</score-partwise>"))

        // Verify LilyPond generation
        let ly = TMDLilyPondGenerator.generateLilyPond(from: validSheet)
        #expect(ly.contains("\\version"))
        #expect(ly.contains("三天三夜"))
        #expect(ly.contains("\\score"))
        #expect(ly.contains("\\new Staff"))
    }
}

@Test func testAllSampleScoresParseSuccessfully() throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sampleURL = repoRoot.appendingPathComponent("sample")

    let enumerator = FileManager.default.enumerator(
        at: sampleURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    )

    var testedCount = 0
    while let fileURL = enumerator?.nextObject() as? URL {
        guard fileURL.pathExtension == "tmd" else { continue }
        let sheet = try TmdParser.parseThrowing(url: fileURL)
        #expect(!sheet.name.isEmpty, "Score in \(fileURL.lastPathComponent) should have a name")
        #expect(sheet.speed > 0, "Score in \(fileURL.lastPathComponent) should have positive BPM")
        #expect(!sheet.paragraphs.isEmpty, "Score in \(fileURL.lastPathComponent) should have paragraphs")
        testedCount += 1
    }

    #expect(testedCount >= 20, "Expected at least 20 sample TMD scores to be tested, found \(testedCount)")
}

@Test func testFileURLAndEncoding() throws {
    let sampleURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("sample/basic/三天三夜.tmd")

    // Test URL parsing
    let sheetFromURL = try TmdParser.parse(url: sampleURL)
    #expect(sheetFromURL != nil)
    #expect(sheetFromURL?.name == "三天三夜")

    // Test file:// string parsing with percent-encoding
    let fileURLString = sampleURL.absoluteString
    #expect(FilePathNormalizer.isFileURL(fileURLString))
    let sheetFromFileURL = try TmdParser.parse(filePathOrURL: fileURLString)
    #expect(sheetFromFileURL != nil)
    #expect(sheetFromFileURL?.name == "三天三夜")

    // Test Big5 encoded data detection
    let tmdBig5 = """
    ::SCORE::
    ** 測試Big5 **
    != 120
    ?= C
    <4/4>
    intro:鋼琴@|0|{
    <4*>
    1 2 3 4
    }
    -> intro ->#
    """
    if let big5Data = tmdBig5.data(using: .big5) {
        let sheetBig5 = TmdParser.parse(data: big5Data)
        #expect(sheetBig5 != nil)
        #expect(sheetBig5?.name == "測試Big5")
        #expect(sheetBig5?.paragraphs.first?.instrument == "鋼琴")
    }
}

#if os(macOS)
@Test func testAudioRenderingBasic() throws {
    let tmd = """
    ::SCORE::
    ** Audio Test **
    != 140
    ?= C
    <4/4>
    intro:Piano@|0|{
    <4*>
    1 2 3 4
    }
    -> intro ->#
    """
    guard let sheet = TmdParser.parse(string: tmd) else {
        Issue.record("Failed to parse audio test score")
        return
    }

    let sampleRate: Double = 44100.0
    let wavData = try TMDWAVRenderer.renderWAV(from: sheet, sampleRate: sampleRate)
    #expect(!wavData.isEmpty)
    #expect(wavData.starts(with: [0x52, 0x49, 0x46, 0x46])) // "RIFF"

    let pcmBytes = wavData.count - 44
    let durationSeconds = Double(pcmBytes) / (sampleRate * 4.0)
    // 4 beats at 140 BPM is ~1.71s + release tail (2.5s) >= 4.0s
    #expect(durationSeconds >= 4.0)
}

@Test func testAudioRenderingSlowTempoNotTruncated() throws {
    // 60 BPM with 4 quarter notes = exactly 4.0 seconds of music.
    // With release/reverb tail (at least 1.5s - 2.5s), duration MUST be >= 5.5s.
    // If tempo was hardcoded to 120 BPM, 4 beats would produce only 4 * 0.5 + 1.5 = 3.5s, truncating the song!
    let tmd = """
    ::SCORE::
    ** Slow 60 BPM Test **
    != 60
    ?= C
    <4/4>
    intro:Piano@|0|{
    <4*>
    1 2 3 4
    }
    -> intro ->#
    """
    guard let sheet = TmdParser.parse(string: tmd) else {
        Issue.record("Failed to parse 60 BPM score")
        return
    }

    let sampleRate: Double = 44100.0
    let wavData = try TMDWAVRenderer.renderWAV(from: sheet, sampleRate: sampleRate)
    #expect(wavData.count > 44)

    // Calculate actual audio duration from WAV PCM bytes (16-bit stereo = 4 bytes per frame)
    let pcmBytes = wavData.count - 44
    let durationSeconds = Double(pcmBytes) / (sampleRate * 4.0)

    // 4 beats at 60 BPM = 4.0s of score. It must NOT be truncated to 3.5s!
    #expect(durationSeconds >= 5.5, "Rendered duration (\(durationSeconds)s) was truncated below 5.5s!")
}

@Test func testAudioRenderingWithTempoChangeDirective() throws {
    // Starts at 120 BPM (2 beats = 1.0s), then drops to 60 BPM (2 beats = 2.0s). Total score duration = 3.0s.
    let tmd = """
    ::SCORE::
    ** Tempo Change Test **
    != 120
    ?= C
    <4/4>
    intro:Piano@|0|{
    <4*>
    1 2 {!=60} 3 4
    }
    -> intro ->#
    """
    guard let sheet = TmdParser.parse(string: tmd) else {
        Issue.record("Failed to parse tempo change score")
        return
    }

    let sampleRate: Double = 44100.0
    let wavData = try TMDWAVRenderer.renderWAV(from: sheet, sampleRate: sampleRate)
    let pcmBytes = wavData.count - 44
    let durationSeconds = Double(pcmBytes) / (sampleRate * 4.0)

    // Total score duration is 1.0s + 2.0s = 3.0s, plus release tail (>=2.0s) -> >= 4.5s.
    #expect(durationSeconds >= 4.5, "Rendered duration (\(durationSeconds)s) was truncated below 4.5s!")
}
#endif

@Test func testABCGeneration() throws {
    let tmd = """
    ::SCORE::
    ** ABC Test **
    != 120
    ?= C
    <4/4>
    intro:Piano@|0|{
    <4*>
    1 2 3 4
    }
    -> intro ->#
    """
    guard let sheet = TmdParser.parse(string: tmd) else {
        Issue.record("Failed to parse ABC test score")
        return
    }

    let abc = TMDABCGenerator.generateABC(from: sheet)
    #expect(abc.contains("X:1"))
    #expect(abc.contains("T:ABC Test"))
    #expect(abc.contains("M:4/4"))
    #expect(abc.contains("K:C"))
    #expect(abc.contains("V:V1 name=\"Piano\""))
}

@Test func testExtendedTMDSyntax() throws {
    let tmd = """
    ::SCORE::
    ** Extended **
    != 120
    ?= C
    <4/4>
    ~ "詞：阿怪"
    =~:__ARR__= "編曲者"

    A:Vocal@|-1|{
        <16*>
        0--- 1 2 3
        {!= 140}
        {!+10}
        {?+2}
        {?=fixed}
        {<3/4>}
    }
    A:Drums@|0|{
        <16*>
        XsTt x--
    }
    -> A ->#
    """

    let sheet = TmdParser.parse(string: tmd)
    #expect(sheet != nil)
    guard let sheet else { return }

    #expect(sheet.metadata["lyrics"] == "詞：阿怪")
    #expect(TmdParser.parse(string: "::SCORE::\n~ \"曲：作曲者\"\n->#")?.metadata["composer"] == "曲：作曲者")
    #expect(TmdParser.parse(string: "::SCORE::\n~ \"編：編曲者\"\n->#")?.metadata["arranger"] == "編：編曲者")
    #expect(sheet.metadata["ARR"] == "編曲者")
    #expect(sheet.paragraphs[0].start == -1)
    #expect(sheet.paragraphs[0].sections[0].unitGroups[0].units[0] == .rest)
    #expect(sheet.paragraphs[1].sections[0].unitGroups[0].units[0] == .percussion("XsTt"))
    #expect(sheet.paragraphs[0].sections[0].directives == [
        SectionDirective(position: 7, kind: .tempo(140)),
        SectionDirective(position: 7, kind: .relativeTempo(10)),
        SectionDirective(position: 7, kind: .relativeKey(2)),
        SectionDirective(position: 7, kind: .fixedPitch),
        SectionDirective(position: 7, kind: .timeSignature(Beat(count: 3, noteValue: 4)))
    ])

    let reparsed = TmdParser.parse(string: sheet.format())
    #expect(reparsed?.metadata == sheet.metadata)
    #expect(reparsed?.paragraphs[0].start == -1)
    #expect(reparsed?.paragraphs[0].sections[0].directives == sheet.paragraphs[0].sections[0].directives)

    let midi = TMDMIDIGenerator.generateMIDI(from: sheet)
    #expect(midi.contains(0x99))
    #expect(midi.contains(0x51)) // tempo meta event
    #expect(midi.contains(0x58)) // time-signature meta event
    #expect(midi.range(of: Data([0xFF, 0x51, 0x03, 0x06, 0x1A, 0x80])) != nil) // 150 BPM
    let musicXML = TMDMusicXMLGenerator.generateMusicXML(from: sheet)
    #expect(musicXML.contains("<per-minute>140</per-minute>"))
    #expect(musicXML.contains("<beats>3</beats>"))
    #expect(musicXML.contains("<unpitched>"))
    let lilyPond = TMDLilyPondGenerator.generateLilyPond(from: sheet)
    #expect(lilyPond.contains("\\tempo 4 = 140"))
    #expect(lilyPond.contains("\\tempo 4 = 150"))
    #expect(lilyPond.contains("\\time 3/4"))
    #expect(lilyPond.contains("\\new DrumStaff"))
    let abc = TMDABCGenerator.generateABC(from: sheet)
    #expect(abc.contains("Q:1/4=140"))
    #expect(abc.contains("Q:1/4=150"))
    #expect(abc.contains("M:3/4"))
    #expect(abc.contains("%%MIDI channel 10"))
}

@Test func testFixedPitchSectionDirective() throws {
    let tmd = """
    ::SCORE::
    ** Fixed Pitch Test **
    != 120
    ?= G
    <4/4>

    verse:Timpani@|0|{
        <4*>
        {?=fixed}
        1 2 3 4
    }

    verse:Piano@|0|{
        <4*>
        1 2 3 4
    }

    -> {?+3} -> verse ->#
    """

    let sheet = try #require(TmdParser.parse(string: tmd))
    
    // In Timpani track, {?=fixed} forces keyOffset = 0 regardless of initial key G or global transposition {?+3}
    let timpaniTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Timpani")
    #expect(!timpaniTimeline.events.isEmpty)
    for event in timpaniTimeline.events {
        #expect(event.state.keyOffset == 0)
    }

    // In Piano track, without {?=fixed}, key G (offset 7) + transposition {?+3} results in keyOffset = 10
    let pianoTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    #expect(!pianoTimeline.events.isEmpty)
    for event in pianoTimeline.events {
        #expect(event.state.keyOffset == 10)
    }
}

@Test func testMIDIGenerationWithTargetSectionAndInstrument() throws {
    let tmd = """
    ::SCORE::
    ** Multi Section Song **
    != 120
    ?= C
    <4/4>

    intro:Piano@|0|{
        <4*>
        1 2 3 4
    }

    intro:Bass@|0|{
        <4*>
        1_ - - -
    }

    verse:Piano@|0|{
        <4*>
        5 6 7 1^
    }

    -> intro -> verse ->#
    """

    let sheet = try #require(TmdParser.parse(string: tmd))

    // 1. Generate full MIDI: should contain both Piano and Bass tracks
    let fullMidi = TMDMIDIGenerator.generateMIDI(from: sheet)
    #expect(!fullMidi.isEmpty)

    // 2. Generate section-only MIDI: intro
    let introMidi = TMDMIDIGenerator.generateMIDI(from: sheet, targetParagraph: "intro")
    #expect(!introMidi.isEmpty)

    // 3. Generate solo track MIDI: intro (Piano only)
    let pianoIntroMidi = TMDMIDIGenerator.generateMIDI(from: sheet, targetParagraph: "intro", targetInstrument: "Piano")
    #expect(!pianoIntroMidi.isEmpty)
    // Should be smaller than introMidi because Bass track is excluded
    #expect(pianoIntroMidi.count < introMidi.count)

    // 4. Test CLI export with --section and --instrument flags
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let tmdPath = tempDir.appendingPathComponent("score.tmd").path
    try tmd.write(toFile: tmdPath, atomically: true, encoding: .utf8)
    let midiOutPath = tempDir.appendingPathComponent("intro_piano.mid").path

    if let tmdURL = TmdTestHelper.findTmdExecutable() {
        let process = Process()
        process.executableURL = tmdURL
        process.arguments = [tmdPath, "-m", midiOutPath, "--section", "intro", "--instrument", "Piano"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: midiOutPath))
        let cliData = try Data(contentsOf: URL(fileURLWithPath: midiOutPath))
        #expect(!cliData.isEmpty)

#if os(macOS)
        let wavOutPath = tempDir.appendingPathComponent("intro_piano.wav").path
        let wavProcess = Process()
        wavProcess.executableURL = tmdURL
        wavProcess.arguments = [tmdPath, "-w", wavOutPath, "--section", "intro", "--instrument", "Piano"]
        try wavProcess.run()
        wavProcess.waitUntilExit()
        #expect(wavProcess.terminationStatus == 0)
        #expect(FileManager.default.fileExists(atPath: wavOutPath))
        let cliWavData = try Data(contentsOf: URL(fileURLWithPath: wavOutPath))
        #expect(!cliWavData.isEmpty)
#endif
    } else {
        Issue.record("tmd binary must be built and available")
    }
}

@Test func testStaggeredEntranceWithLeadInPickup() throws {
    let tmd = """
    ::SCORE::
    ** Staggered LeadIn **
    != 120
    ?= C
    <4/4>

    A:Vocal@|-1|{
        <4*>
        | 0 0 3 1 |
        | 5 6 5 4 |
    }

    A:Piano@|-1|{
        <4*>
        | 0 0 0 0 |
        | 1 2 3 4 |
    }

    A:Violin@|0|{
        <4*>
        | 0 0 0 0 |
        | 5 6 7 1 |
    }

    -> A ->#
    """
    let sheet = try #require(TmdParser.parse(string: tmd))

    // 1. Test section-filtered playback (as used in VS Code Play Section / Preview)
    let sectionFiltered = Sheet(
        name: sheet.name,
        speed: sheet.speed,
        keySignature: sheet.keySignature,
        beat: sheet.beat,
        paragraphs: sheet.paragraphs.filter { $0.name == "A" },
        orders: [.name("A")],
        metadata: sheet.metadata
    )

    let vocalTimeline = TMDPlaybackRenderer.render(sheet: sectionFiltered, instrument: "Vocal")
    let pianoTimeline = TMDPlaybackRenderer.render(sheet: sectionFiltered, instrument: "Piano")
    let violinTimeline = TMDPlaybackRenderer.render(sheet: sectionFiltered, instrument: "Violin")

    let vocalNotes = vocalTimeline.events.filter { if case .note = $0.content { return true } else { return false } }
    let pianoNotes = pianoTimeline.events.filter { if case .note = $0.content { return true } else { return false } }
    let violinNotes = violinTimeline.events.filter { if case .note = $0.content { return true } else { return false } }

    // Vocal starts pickup at beat 2.0 (Bar -1, beat 3)
    #expect(vocalNotes.first?.position == 2.0)
    // Vocal bar 0 note '5' starts at beat 4.0
    #expect(vocalNotes[2].position == 4.0)

    // Piano starts at beat 4.0 (Bar 0, exactly aligned with Vocal bar 0)
    #expect(pianoNotes.first?.position == 4.0)

    // Violin was declared at @|0| with 1 bar of rest: its first note must be at beat 8.0 (Bar 1),
    // NOT at beat 4.0!
    #expect(violinNotes.first?.position == 8.0, "Violin at @|0| with 1 bar rest must enter at beat 8.0, not be desynced to beat 4.0")
}

@Test func testMultiSectionWithLeadInPickupOverlap() throws {
    let tmd = """
    ::SCORE::
    ** Overlapping Sections **
    != 120
    ?= C
    <4/4>

    A:Piano@|0|{
        <4*>
        | 1 2 3 4 |
        | 5 6 7 1 |
    }

    B:Vocal@|-1|{
        <4*>
        | 0 0 3 4 |
        | 5 6 7 1 |
    }

    B:Piano@|0|{
        <4*>
        | 1 2 3 4 |
    }

    -> A -> B ->#
    """
    let sheet = try #require(TmdParser.parse(string: tmd))

    let pianoTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    let vocalTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Vocal")

    let pianoNotes = pianoTimeline.events.filter { if case .note = $0.content { return true } else { return false } }
    let vocalNotes = vocalTimeline.events.filter { if case .note = $0.content { return true } else { return false } }

    // Section A Piano: 8 notes across beats 0.0..<8.0
    #expect(pianoNotes[0].position == 0.0)
    #expect(pianoNotes[7].position == 7.0)

    // Section B Piano starts at beat 8.0
    #expect(pianoNotes[8].position == 8.0)

    // Section B Vocal has pickup at @|-1|: measure starts at beat 4.0, rests at beats 4.0 & 5.0,
    // so first note '3' starts at beat 6.0 (overlapping Section A's second measure!)
    #expect(vocalNotes[0].position == 6.0)
    #expect(vocalNotes[1].position == 7.0)
    // Section B Vocal measure 0 starts at beat 8.0
    #expect(vocalNotes[2].position == 8.0)
}

@Test func testScoreStartingWithNegativePickupShiftedToZero() throws {
    let tmd = """
    ::SCORE::
    ** Score With Initial Pickup **
    != 120
    ?= C
    <4/4>

    Intro:Vocal@|-1|{
        <4*>
        | 0 0 3 4 |
        | 5 6 7 1 |
    }

    Intro:Piano@|0|{
        <4*>
        | 1 2 3 4 |
    }

    Verse:Piano@|0|{
        <4*>
        | 5 6 7 1 |
    }

    -> Intro -> Verse ->#
    """
    let sheet = try #require(TmdParser.parse(string: tmd))

    let vocalTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Vocal")
    let pianoTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")

    let vocalNotes = vocalTimeline.events.filter { if case .note = $0.content { return true } else { return false } }
    let pianoNotes = pianoTimeline.events.filter { if case .note = $0.content { return true } else { return false } }

    // Global earliest note was at beat -2.0 (Bar -1, beat 2). Entire score is shifted by +4.0 (1 measure):
    // Bar -1 starts at 0.0, so pickup note '3' starts at beat 2.0.
    #expect(vocalNotes[0].position == 2.0)
    #expect(vocalNotes[1].position == 3.0)
    // Bar 0 starts at beat 4.0
    #expect(vocalNotes[2].position == 4.0)

    // Intro Piano@|0| starts at beat 4.0
    #expect(pianoNotes[0].position == 4.0)

    // Intro has 2 measures total from -1 to 1 (Intro ends at bar 1, which is beat 8.0 from pickup, or 4.0 after bar 0).
    // Verse Piano@|0| starts at beat 8.0
    #expect(pianoNotes[4].position == 8.0)
}

@Test func testHuoxiangjiStaggeredEntranceAndSectionPreview() throws {
    let tmd = """
    ::SCORE::
    ** 藿香薊 **
    != 120
    ?= E
    <4/4>

    /* Intro */

    Intro:Violin@|-1| {
        <4 *>
        | 0 0 0 5 |
        | 1^ 5 6 6 | (6 7)%(-) 1^ 7 6 | 5 6 5 (5 5)%(-) | 5 (5 6)%(-) 5 5 |
        | 1^ 5 6 6 | (6 7)%(-) 1^ 7 6 | 7 1^ 1^ - | - - - - |
    }

    Intro:Piano@|7| {
        <4*>
        | 0 0 1 1 |
        | (1 2)%(-) 3 3 2 | (2 3)%(-) 2 1 1 | (1 2)%(-) 3 3 2 | (2 7_)%(-) 5_ 1 - |
        | - - - - |
    }

    /* A */

    A1:Vocal@|-1| {
        <4*>
        | 0 0 3 1 |
        | 5 6 5 4 | 3 - - - | - - - - | 0 0 1 3 |
        | 2 (3 2)%(-) 1 2 | 3 - - - | - - - - | 0 0 3 1 |
        | 5 6 5 4 | 3 - - - | - - - - | 0 0 1 3 |
        | 3 2 2 1 | 1 - - - | - - - - | 0 5 1^ 5 |
    }

    A1:Piano@|-1| {
        <4*>
        | 0 0 0 0 |
        | 0 0 0 0 | 0 (3 3 )%(-) 3 (3 3 )%(-) | 3 (3 3 )%(-) 3 2 | 1 - - - |
        | 0 0 0 0 | 0 (3 3 )%(-) 3 (3 3 )%(-) | 3 (3 3 )%(-) 3 2 | 1 - - - |
        | 0 0 0 0 | 0 (3 3 )%(-) 3 (3 3 )%(-) | 3 (3 3 )%(-) 3 2 | 1 - - - |
        | 0 0 0 0 | 0 (3 3 )%(-) 3 (3 3 )%(-) | 3 (3 3 )%(-) 3 2 | 1 - - - |
    }

    A1:Violin@|0| {
        <4 *>
        | 0 0 0 0 |
    }

    -> Intro -> A1 ->#
    """
    let sheet = try #require(TmdParser.parse(string: tmd))

    // 1. Previewing Section A1 (like clicking Play Section on A1 in VS Code)
    let a1FilteredSheet = Sheet(
        name: sheet.name,
        speed: sheet.speed,
        keySignature: sheet.keySignature,
        beat: sheet.beat,
        paragraphs: sheet.paragraphs.filter { $0.name == "A1" },
        orders: [.name("A1")],
        metadata: sheet.metadata
    )

    let a1VocalTimeline = TMDPlaybackRenderer.render(sheet: a1FilteredSheet, instrument: "Vocal")
    let a1PianoTimeline = TMDPlaybackRenderer.render(sheet: a1FilteredSheet, instrument: "Piano")
    let a1ViolinTimeline = TMDPlaybackRenderer.render(sheet: a1FilteredSheet, instrument: "Violin")

    let a1VocalNotes = a1VocalTimeline.events.filter { if case .note = $0.content { return true } else { return false } }
    let a1PianoNotes = a1PianoTimeline.events.filter { if case .note = $0.content { return true } else { return false } }

    // Vocal starts pickup at beat 2.0 (Bar -1, beat 2)
    #expect(a1VocalNotes.first?.position == 2.0)
    // Vocal bar 0 note '5' starts at beat 4.0
    #expect(a1VocalNotes[2].position == 4.0)

    // Piano has rest in bar -1 and bar 0, its first note starts at bar 1 (beat 9.0)
    #expect(a1PianoNotes.first?.position == 9.0)

    // Violin at @|0| with 1 bar rest: its event rests during beats 4.0..<8.0.
    // Ensure violin timeline starts at beat 4.0 (measure 0), not beat 0.0!
    #expect(a1ViolinTimeline.events.first?.position == 4.0)

    // 2. Full Song: Intro ends at measure 13 (beat 56.0 with the 1-measure pickup shift).
    // Section A1 starts at measure 13 (beat 56.0).
    // A1:Vocal@|-1| starts at measure 12 (beat 52.0), overlapping Intro Piano!
    let fullVocalTimeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Vocal")
    let fullVocalNotes = fullVocalTimeline.events.filter { if case .note = $0.content { return true } else { return false } }
    // Full song shifted by +4.0 (Intro Violin@|-1|).
    // Intro ends at bar 13 -> beat 4.0 + 13 * 4.0 = 56.0.
    // A1:Vocal@|-1| starts at 56.0 - 4.0 = 52.0. Pickup notes '3' and '1' are at beat 54.0 and 55.0.
    #expect(fullVocalNotes.first?.position == 54.0)
}



@Test func testLegacySectionMarkerSyntax() throws {
    let tmd = """
    ::SCORE:: ** Legacy ** != 120 ?= C <4/4>
    A:Piano@{ <*1> 1 2 3 4 }
    -> A ->#
    """

    let sheet = TmdParser.parse(string: tmd)
    #expect(sheet != nil)
    #expect(sheet?.paragraphs.first?.sections.first?.noteLength == 1)
}

@Test func testShowProgramBlock() throws {
    let tmd = #"""
    ::SCORE::
    ** Show **
    show:Lighting@intro{
    """
    cue black
    wait 4
    """
    }
    -> show ->#
    """#

    let sheet = TmdParser.parse(string: tmd)
    #expect(sheet?.paragraphs.first?.executionTime == "intro")
    #expect(sheet?.paragraphs.first?.instrument == "Lighting")
    #expect(sheet?.paragraphs.first?.showProgram?.contains("cue black") == true)
    #expect(sheet?.format().contains("\"\"\"") == true)
    #expect(sheet?.format().contains("cue black") == true)
}

@Test func testScaleDegreeEnum() throws {
    #expect(ScaleDegree.c.rawValue == 1)
    #expect(ScaleDegree.d.rawValue == 2)
    #expect(ScaleDegree.e.rawValue == 3)
    #expect(ScaleDegree.f.rawValue == 4)
    #expect(ScaleDegree.g.rawValue == 5)
    #expect(ScaleDegree.a.rawValue == 6)
    #expect(ScaleDegree.b.rawValue == 7)
    #expect(ScaleDegree(rawValue: 0) == nil)
    #expect(ScaleDegree(rawValue: 8) == nil)
    #expect(Note().degree == .c)
    #expect(Note(degree: 5).degree == .g)
    #expect(Note(degree: .a).format() == "6")

    let sharp = KeySignature(string: "A'")
    #expect(sharp.tonic == .a)
    #expect(sharp.accidental == .sharp)
    #expect(sharp.description == "A'")
    let flat = KeySignature(string: "E,")
    #expect(flat.tonic == .e)
    #expect(flat.accidental == .flat)
    #expect(flat.description == "E,")
    #expect(KeySignature(string: "not-a-key") == KeySignature(tonic: .c))
}

@Test func testTypedChordSymbol() throws {
    let majorSeventh: ChordSymbol = "Cmaj7"
    #expect(majorSeventh.root == ChordRoot(degree: .c))
    #expect(majorSeventh.quality == .major7)
    #expect(majorSeventh.description == "Cmaj7")

    let movableMinor: ChordSymbol = "6m"
    #expect(movableMinor.root == ChordRoot(degree: .a, isScaleDegree: true))
    #expect(movableMinor.quality == .minor)
    #expect(movableMinor.description == "6m")

    let extended = ChordSymbol(string: "C7#9")
    #expect(extended.quality == .custom("7#9"))
    #expect(extended.description == "C7#9")

    let slashLetter: ChordSymbol = "C/E"
    #expect(slashLetter.root == ChordRoot(degree: .c))
    #expect(slashLetter.quality == .major)
    #expect(slashLetter.bass == ChordRoot(degree: .e))
    #expect(slashLetter.description == "C/E")

    let slashDegree: ChordSymbol = "1/3"
    #expect(slashDegree.root == ChordRoot(degree: .c, isScaleDegree: true))
    #expect(slashDegree.quality == .major)
    #expect(slashDegree.bass == ChordRoot(degree: .e, isScaleDegree: true))
    #expect(slashDegree.description == "1/3")

    let slashMinorSeventh: ChordSymbol = "Am7/G"
    #expect(slashMinorSeventh.root == ChordRoot(degree: .a))
    #expect(slashMinorSeventh.quality == .minor7)
    #expect(slashMinorSeventh.bass == ChordRoot(degree: .g))
    #expect(slashMinorSeventh.description == "Am7/G")
}


@Test func testSharedPitchMappings() throws {
    #expect(ScaleDegree.c.semitoneOffset == 0)
    #expect(ScaleDegree.f.semitoneOffset == 5)
    #expect(PitchMapping.musicXMLSteps[10] == "A")
    #expect(PitchMapping.musicXMLAlters[10] == 1)
    #expect(PitchMapping.lilyPondNames[11] == "b")
    #expect(PitchMapping.abcLowerNames[1] == "^c")
}

@Test func testPlaybackTimeline() throws {
    let section = Section(
        noteLength: 4,
        unitGroups: [
            UnitGroup(units: [.note(Note(degree: .c))], length: 1),
            UnitGroup(units: [.rest], length: 2)
        ],
        directives: [
            SectionDirective(position: 1, kind: .relativeTempo(10)),
            SectionDirective(position: 1, kind: .relativeKey(2))
        ]
    )
    let sheet = Sheet(
        speed: 100,
        paragraphs: [Paragraph(name: "intro", instrument: "Piano", start: 1, sections: [section])],
        orders: [.name("intro")]
    )

    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    #expect(timeline.events.count == 2)
    #expect(timeline.events[0].position == 4)
    #expect(timeline.events[1].position == 5)
    #expect(timeline.events[1].duration == 2)
    #expect(timeline.events[1].state == PlaybackState(tempo: 110, keyOffset: 2, timeSignature: Beat()))
    #expect(timeline.directives.map(\.position) == [5, 5])
}

@Test func testFilePathNormalizerVariants() throws {
    #expect(FilePathNormalizer.isFileURL(" file:///tmp/a%20b "))
    #expect(FilePathNormalizer.isFileURL("<file://localhost/tmp/a>"))
    #expect(!FilePathNormalizer.isFileURL("/tmp/a"))
    #expect(FilePathNormalizer.fileURLToPath("file:///tmp/a%20b") == "/tmp/a b")
    #expect(FilePathNormalizer.fileURLToPath("file://localhost/tmp/a") == "/tmp/a")
    #expect(FilePathNormalizer.fileURLToPath("file:C:/Users/test") == "C:/Users/test")
    #expect(FilePathNormalizer.fileURLToPath("/tmp/plain") == "/tmp/plain")

    let anchor = FilePathNormalizer.parseLocation(from: "score.tmd#L42C10")
    #expect(anchor.filePath == "score.tmd")
    #expect(anchor.line == 42)
    #expect(anchor.column == 10)

    let colonAnchor = FilePathNormalizer.parseLocation(from: "score.tmd:42:10")
    #expect(colonAnchor.filePath == "score.tmd")
    #expect(colonAnchor.line == 42)
    #expect(colonAnchor.column == 10)

    let urlAnchor = FilePathNormalizer.parseLocation(from: "file:///tmp/score.tmd#L7")
    #expect(urlAnchor.filePath == "/tmp/score.tmd")
    #expect(urlAnchor.line == 7)
    #expect(urlAnchor.column == nil)

    let windows = FilePathNormalizer.parseLocation(from: "C:/score.tmd:12:4")
    #expect(windows.filePath == "C:/score.tmd")
    #expect(windows.line == 12)
    #expect(windows.column == 4)

    let empty = FilePathNormalizer.parseLocation(from: "   ")
    #expect(empty.filePath.isEmpty)
    #expect(empty.line == nil)
}

@Test func testTextEncodingDetectorVariants() throws {
    let empty = TextEncodingDetector.detectAndDecode(Data())
    #expect(empty?.content == "")
    #expect(TextEncodingDetector.displayName(for: .utf8) == "UTF-8")
    #expect(TextEncodingDetector.displayName(for: .big5) == "Big5")
    #expect(TextEncodingDetector.displayName(for: .gb18030) == "GB18030")
    #expect(TextEncodingDetector.displayName(for: .shiftJISCustom) == "Shift-JIS")
    #expect(TextEncodingDetector.displayName(for: .eucJPCustom) == "EUC-JP")

    let utf8BOM = Data([0xEF, 0xBB, 0xBF]) + Data("測試".utf8)
    #expect(TextEncodingDetector.detectAndDecode(utf8BOM)?.content == "測試")

    let utf16LE = Data([0xFF, 0xFE]) + ("測試".data(using: .utf16LittleEndian) ?? Data())
    #expect(TextEncodingDetector.detectAndDecode(utf16LE)?.content == "測試")
    let utf16BE = Data([0xFE, 0xFF]) + ("測試".data(using: .utf16BigEndian) ?? Data())
    #expect(TextEncodingDetector.detectAndDecode(utf16BE)?.content == "測試")

    let utf32LE = Data([0xFF, 0xFE, 0x00, 0x00]) + ("TMD".data(using: .utf32LittleEndian) ?? Data())
    #expect(TextEncodingDetector.detectAndDecode(utf32LE)?.content == "TMD")
}

@Test func testExporterFallbackBranches() throws {
    let sheet = Sheet(
        name: "Fallback",
        speed: 0,
        keySignature: "?",
        beat: Beat(count: 0, noteValue: 0),
        paragraphs: [Paragraph(name: "A", instrument: "Unknown", sections: [
            Section(noteLength: 8, unitGroups: [
                UnitGroup(units: [.note(Note(degree: .c)), .chord("???")], length: 2),
                UnitGroup(units: [], length: 1)
            ])
        ])],
        orders: [.name("A"), .name("Missing")]
    )

    #expect(!TMDMIDIGenerator.generateMIDI(from: sheet).isEmpty)
    #expect(TMDMIDIGenerator.noteToMIDIPitch(Note(degree: .c), keyOffset: 0) == 60)
    #expect(!TMDMIDIGenerator.chordToMIDIPitches("???", keyOffset: 0).isEmpty)
    #expect(TMDMIDIGenerator.generalMidiProgram(for: "Unknown") == 0)
    #expect(MIDIInstrument.resolve("Unknown") == .unknown)
    #expect(MIDIInstrument.resolve("Unknown").program == 0)
    #expect(MIDIInstrument.resolve("Chorus-1") == .choir)
    #expect(MIDIInstrument.resolve("Viola").program == 41)
    #expect(MIDIInstrument.resolve("Oboe").program == 68)
    #expect(MIDIInstrument.resolve("Clarinet").program == 71)
    #expect(MIDIInstrument.resolve("Harpsichord").program == 6)
    #expect(MIDIInstrument.resolve("Timpani").program == 47)
    #expect(MIDIInstrument.resolve("Marimba").program == 12)
    #expect(MIDIInstrument.resolve("Harmonica").program == 22)
    #expect(MIDIInstrument.resolve("Harp").program == 46)
    #expect(MIDIInstrument.resolve("FrenchHorn").program == 60)
    #expect(MIDIInstrument.resolve("Bassoon").program == 70)
    #expect(MIDIInstrument.resolve("Piccolo").program == 72)
    #expect(MIDIInstrument.resolve("Sitar").program == 104)
    #expect(MIDIInstrument.resolve("Taiko").program == 116)
    #expect(MIDIInstrument.resolve("Gunshot").program == 127)
    #expect(MIDIInstrument.resolve("Prog:40").program == 40)
    #expect(MIDIInstrument.resolve("73").program == 73)
    #expect(MIDIInstrument.resolve("Groove").isPercussion)
    #expect(MIDIInstrument.resolve("Drums").isPercussion)
    #expect(TMDMusicXMLGenerator.generateMusicXML(from: sheet).contains("score-partwise"))
    #expect(TMDLilyPondGenerator.generateLilyPond(from: sheet).contains("\\score"))
    #expect(TMDABCGenerator.generateABC(from: sheet).contains("T:Fallback"))
}

@Test func testCompleteGeneralMIDI128InstrumentsCoverage() {
    for prog in 0...127 {
        let instFromNumber = MIDIInstrument.resolve("\(prog)")
        #expect(instFromNumber.program == UInt8(prog))
        let instFromProg = MIDIInstrument.resolve("program:\(prog)")
        #expect(instFromProg.program == UInt8(prog))
    }
}

@Test func testNegativeParagraphStartOffset() throws {
    let tmd = """
    ::SCORE::
    ** Negative Offset Test **
    != 120
    ?= C
    <4/4>

    intro:Piano@|0|{
        <4*>
        1 2 3 4
    }

    v1:Piano@|-1|{
        <4*>
        5 6 7 1^
    }

    -> intro -> v1 ->#
    """

    let sheet = try TmdParser.parseThrowing(string: tmd)
    #expect(sheet.paragraphs.count == 2)
    #expect(sheet.paragraphs[0].start == 0)
    #expect(sheet.paragraphs[1].start == -1)

    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    #expect(!timeline.events.isEmpty)

    // intro starts at measure 0 (4 quarter notes: 0.0, 1.0, 2.0, 3.0).
    // v1 is ordered after intro, but with start = -1 (one measure = 4 beats earlier),
    // so v1 starts at 4.0 - 4.0 = 0.0 (overlapping with intro!).
    let v1Notes = timeline.events.filter { event in
        if case .note(let n) = event.content { return n.degree == .g }
        return false
    }
    #expect(!v1Notes.isEmpty)
    #expect(v1Notes[0].position == 0.0)

    // Also verify MIDI generator doesn't crash or overflow
    let midi = TMDMIDIGenerator.generateMIDI(from: sheet)
    #expect(!midi.isEmpty)
}

@Test func testTieExtendsNoteDuration() throws {
    let tmd = """
    ::SCORE::
    ** Tie Half Note Test **
    != 120
    ?= C
    <4/4>

    intro:Piano@|0|{
        <4*>
        3 - 1 - - -
    }

    -> intro ->#
    """

    let sheet = try TmdParser.parseThrowing(string: tmd)
    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")

    // In <4*>, 3 - should be a half note (duration = 2.0 quarter notes).
    // 1 - - - should be a whole note (duration = 4.0 quarter notes).
    let noteEvents = timeline.events.filter {
        if case .note = $0.content { return true }
        return false
    }
    #expect(noteEvents.count == 2)
    #expect(noteEvents[0].duration == 2.0)
    #expect(noteEvents[1].duration == 4.0)
}

@Test func testTupletTieExtension() throws {
    let tmd = """
    ::SCORE::
    ** Tuplet Tie Test **
    != 120
    ?= C
    <4/4>

    intro:Piano@|0|{
        <4*>
        (1 2 3 -)%(--) -
    }

    -> intro ->#
    """

    let sheet = try TmdParser.parseThrowing(string: tmd)
    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    let noteEvents = timeline.events.filter {
        if case .note = $0.content { return true }
        return false
    }
    #expect(noteEvents.count == 3)
    // In <4*>, 2 beats total for the paragraph:
    // (1 2 3 -)%(--) is length 2, so groupDuration = 2.0.
    // Each of the 4 slots has baseSlotDuration = 2.0 / 4 = 0.5.
    // Slot 0: note 1 (dur 0.5)
    // Slot 1: note 2 (dur 0.5)
    // Slot 2: note 3 (dur 0.5 + 0.5 from internal tie = 1.0)
    // Following tie "-" is length 1 (duration 1.0), which extends note 3 to 1.0 + 1.0 = 2.0.
    #expect(noteEvents[0].duration == 0.5)
    #expect(noteEvents[1].duration == 0.5)
    #expect(noteEvents[2].duration == 2.0)
}

@Test func testNegativeTransposition() throws {
    let tmd = """
    ::SCORE::
    ** Negative Transposition Test **
    != 120
    ?= C
    <4/4>

    sec:Piano@|0|{
        <4*>
        1 2 3 4
    }

    -> sec -> {?-1} -> sec ->#
    """

    let sheet = try TmdParser.parseThrowing(string: tmd)
    #expect(sheet.orders.count == 3)
    #expect(sheet.orders[1] == .relative("-1"))

    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    let noteEvents = timeline.events.filter {
        if case .note = $0.content { return true }
        return false
    }
    #expect(noteEvents.count == 8)
    #expect(noteEvents[0].state.keyOffset == 0)
    #expect(noteEvents[4].state.keyOffset == -1)
}

@Test func testChordOctaveShift() throws {
    let chordNormal = ChordSymbol(string: "6m")
    #expect(chordNormal.root.octave == 0)
    #expect(chordNormal.quality == .minor)

    let chordDown = ChordSymbol(string: "6_m")
    #expect(chordDown.root.octave == -1)
    #expect(chordDown.quality == .minor)

    let chordUp = ChordSymbol(string: "1^")
    #expect(chordUp.root.octave == 1)
    #expect(chordUp.quality == .major)

    let normalPitches = TMDMIDIGenerator.chordToMIDIPitches(chordNormal, keyOffset: 0)
    let downPitches = TMDMIDIGenerator.chordToMIDIPitches(chordDown, keyOffset: 0)
    #expect(downPitches.count == normalPitches.count)
    // Each pitch in 6_m must be exactly 12 semitones lower than 6m
    for (down, normal) in zip(downPitches, normalPitches) {
        #expect(down == normal - 12)
    }
}

@Test func testTmdSkillDefinitionAndInstallation() throws {
    #expect(TmdSkill.skillName == "tmd")
    #expect(TmdSkill.skillMarkdown.contains("name: tmd"))
    #expect(TmdSkill.skillMarkdown.contains("::SCORE::"))
    #expect(TmdSkill.skillMarkdown.contains("--install-skills"))
    #expect(TmdSkill.skillMarkdown.contains("Modular Section-Based Chunking"))
    #expect(TmdSkill.skillMarkdown.contains("Human Composition Principles"))
    #expect(TmdSkill.skillMarkdown.contains("AI Co-Composing Patterns"))
    #expect(TmdSkill.skillMarkdown.contains("Contrapuntal Techniques: Canon and Fugue"))
    #expect(TmdSkill.skillMarkdown.contains("Strict Canon with Measure Offsets"))
    #expect(TmdSkill.skillMarkdown.contains("Fugue Architecture"))

    let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tmd-skill-test-\(UUID().uuidString)")
    let targetSkillDir = tempDir.appendingPathComponent("skills/tmd")

    let results = TmdSkill.installSkills(to: [targetSkillDir])
    #expect(results.count == 1)
    #expect(results[0].success)

    let installedFile = targetSkillDir.appendingPathComponent("SKILL.md")
    #expect(FileManager.default.fileExists(atPath: installedFile.path))

    let content = try String(contentsOf: installedFile, encoding: .utf8)
    #expect(content == TmdSkill.skillMarkdown)

    try? FileManager.default.removeItem(at: tempDir)
}

@Test func testTupletWhitespaceAndUnspacedDigits() throws {
    func makeScore(_ body: String) -> String {
        """
        ::SCORE::
        ** Repro **
        != 100
        <4/4>

        m:piano@|0|{
            <4*>
            \(body)
        }

        -> m ->#
        """
    }

    // 1. Tuplet with whitespace between % and (: (1 2 5 1 2 5) % (--) 4 3
    let sheet1 = TmdParser.parse(string: makeScore("(1 2 5 1 2 5) % (--) 4 3"))
    #expect(sheet1 != nil)
    guard let s1 = sheet1 else { return }
    let groups1 = s1.paragraphs[0].sections[0].unitGroups
    let beats1 = groups1.reduce(0) { $0 + $1.length }
    #expect(beats1 == 4)
    #expect(groups1.count == 3)
    #expect(groups1[0].units.count == 6)
    #expect(groups1[0].length == 2)
    #expect(groups1[1].length == 1)
    #expect(groups1[2].length == 1)

    // 2. Unspaced digits inside and outside tuplets: (125125)%(--) 43
    let sheet2 = TmdParser.parse(string: makeScore("(125125)%(--) 43"))
    #expect(sheet2 != nil)
    guard let s2 = sheet2 else { return }
    let groups2 = s2.paragraphs[0].sections[0].unitGroups
    let beats2 = groups2.reduce(0) { $0 + $1.length }
    #expect(beats2 == 4)
    #expect(groups2.count == 3)
    #expect(groups2[0].units.count == 6)
    #expect(groups2[0].length == 2)
    #expect(groups2[1].units[0] == .note(Note(accidental: .natural, degree: 4, octave: 0)))
    #expect(groups2[2].units[0] == .note(Note(accidental: .natural, degree: 3, octave: 0)))

    // 3. Unspaced digits with spaces in tuplet: (125125) % (--) 43
    let sheet3 = TmdParser.parse(string: makeScore("(125125) % (--) 43"))
    #expect(sheet3 != nil)
    guard let s3 = sheet3 else { return }
    let groups3 = s3.paragraphs[0].sections[0].unitGroups
    let beats3 = groups3.reduce(0) { $0 + $1.length }
    #expect(beats3 == 4)
    #expect(groups3.count == 3)
    #expect(groups3[0].units.count == 6)
    #expect(groups3[0].length == 2)

    // 4. Consecutive unspaced ties following notes and rests: 1--- 0--- 5-- 1-
    let sheet4 = TmdParser.parse(string: makeScore("1--- 0--- 5-- 1-"))
    #expect(sheet4 != nil)
    guard let s4 = sheet4 else { return }
    let groups4 = s4.paragraphs[0].sections[0].unitGroups
    let beats4 = groups4.reduce(0) { $0 + $1.length }
    #expect(beats4 == 13)
    #expect(groups4.count == 13)
    #expect(groups4[0].units[0] == .note(Note(accidental: .natural, degree: 1, octave: 0)))
    #expect(groups4[1].units[0] == .tie)
    #expect(groups4[2].units[0] == .tie)
    #expect(groups4[3].units[0] == .tie)
    #expect(groups4[4].units[0] == .rest)
    #expect(groups4[5].units[0] == .tie)
    #expect(groups4[6].units[0] == .tie)
    #expect(groups4[7].units[0] == .tie)

    // 5. Tuplets with various dash lengths: (1 2 3)% (---) (123)%(----)
    let sheet5 = TmdParser.parse(string: makeScore("(1 2 3)% (---) (123)%(----)"))
    #expect(sheet5 != nil)
    guard let s5 = sheet5 else { return }
    let groups5 = s5.paragraphs[0].sections[0].unitGroups
    #expect(groups5.count == 2)
    #expect(groups5[0].units.count == 3)
    #expect(groups5[0].length == 3)
    #expect(groups5[1].units.count == 3)
    #expect(groups5[1].length == 4)

    // 6. Unspaced notes with octave and accidental modifiers mixed with consecutive ties: 1'^2,_3^-- 43-
    let sheet6 = TmdParser.parse(string: makeScore("1'^2,_3^-- 43-"))
    #expect(sheet6 != nil)
    guard let s6 = sheet6 else { return }
    let groups6 = s6.paragraphs[0].sections[0].unitGroups
    let beats6 = groups6.reduce(0) { $0 + $1.length }
    #expect(beats6 == 8)
    #expect(groups6.count == 8)
    #expect(groups6[0].units[0] == .note(Note(accidental: .sharp, degree: 1, octave: 1)))
    #expect(groups6[1].units[0] == .note(Note(accidental: .flat, degree: 2, octave: -1)))
    #expect(groups6[2].units[0] == .note(Note(accidental: .natural, degree: 3, octave: 1)))
    #expect(groups6[3].units[0] == .tie)
    #expect(groups6[4].units[0] == .tie)
    #expect(groups6[5].units[0] == .note(Note(accidental: .natural, degree: 4, octave: 0)))
    #expect(groups6[6].units[0] == .note(Note(accidental: .natural, degree: 3, octave: 0)))
    #expect(groups6[7].units[0] == .tie)
}

@Test func testSheetInstrumentHelper() throws {
    let sheetWithInstruments = Sheet(
        paragraphs: [
            Paragraph(name: "intro", instrument: "Guitar"),
            Paragraph(name: "verse", instrument: "Bass"),
            Paragraph(name: "chorus", instrument: "Vocal"),
            Paragraph(name: "intro", instrument: "Piano")
        ]
    )

    #expect(sheetWithInstruments.distinctInstruments() == ["Bass", "Guitar", "Piano", "Vocal"])
    #expect(sheetWithInstruments.distinctInstruments(fallbackToDefault: false) == ["Bass", "Guitar", "Piano", "Vocal"])

    let emptySheet = Sheet(paragraphs: [])
    #expect(emptySheet.distinctInstruments(fallbackToDefault: true) == ["Piano"])
    #expect(emptySheet.distinctInstruments(fallbackToDefault: false) == [])

    // Vocal track resolution
    #expect(sheetWithInstruments.resolveVocalInstrument() == "Vocal")
    #expect(sheetWithInstruments.resolveVocalInstrument(requested: "Guitar") == "Guitar")
    #expect(sheetWithInstruments.resolveVocalInstrument(requested: "Unknown") == "Vocal")

    let sheetWithMiku = Sheet(paragraphs: [Paragraph(name: "verse", instrument: "Hatsune_Miku")])
    #expect(sheetWithMiku.resolveVocalInstrument() == "Hatsune_Miku")

    let sheetOnlyBass = Sheet(paragraphs: [Paragraph(name: "verse", instrument: "Bass")])
    #expect(sheetOnlyBass.resolveVocalInstrument() == "Bass")

    #expect(emptySheet.resolveVocalInstrument() == "Vocal")
}

@Test func testTMDParseErrorDiagnosticHintsAndCodeFrame() throws {
    // 1. Fullwidth punctuation typo hint
    let fullwidthCode = "::SCORE::\n** Song **\nintro:Piano@|0|｛\n<4*>\n1 2 3 4\n}\n-> intro ->#"
    do {
        _ = try TmdParser.parseThrowing(string: fullwidthCode)
        Issue.record("Expected parse error for fullwidth brace")
    } catch let error as TMDParseError {
        #expect(error.description.contains("Fullwidth punctuation detected: `｛` -> replace with halfwidth `{`"))
        let frame = error.formatCodeFrame()
        #expect(frame.contains("3 | intro:Piano@|0|｛"))
        #expect(frame.contains("^"))
    }

    // 2. Accidental typo hint: 1#
    let accidentalCode = "::SCORE::\n** Song **\nintro:Piano@|0|{\n<4*>\n1# 2 3 4\n}\n-> intro ->#"
    do {
        _ = try TmdParser.parseThrowing(string: accidentalCode)
        Issue.record("Expected parse error for 1#")
    } catch let error as TMDParseError {
        #expect(error.description.contains("For sharp/flat accidentals in TMD, use `'` for sharp"))
    }

    // 3. Missing time grid directive <4*>
    let missingGridCode = "::SCORE::\n** Song **\nintro:Piano@|0|{\n1 2 3 4\n}\n-> intro ->#"
    do {
        _ = try TmdParser.parseThrowing(string: missingGridCode)
        Issue.record("Expected parse error for missing time grid")
    } catch let error as TMDParseError {
        #expect(error.description.contains("Each section inside `{ ... }` must start with a time grid directive like `<4*>` or `<8*>`"))
    }

    // 4. Code frame formatting explicitly
    let frameErr = TMDParseError(
        message: "Unexpected token",
        token: .identifier("bad"),
        text: "bad",
        range: SourceRange(start: SourcePosition(offset: 15, line: 2, column: 5), length: 3),
        expectedTokens: ["note"],
        source: "line 1\n1 2 bad 4\nline 3"
    )
    let frame = frameErr.formatCodeFrame()
    #expect(frame.contains("1 | line 1"))
    #expect(frame.contains("2 | 1 2 bad 4"))
    #expect(frame.contains("  |     ^^^"))
    #expect(frame.contains("3 | line 3"))
}

@Test func testVSCodeScoreTemplatesAreValid() throws {
    let templates: [(name: String, content: String)] = [
        ("Starter", """
        ::SCORE::
        ** 小星星 (Twinkle Twinkle) **
        != 100
        ?= C
        <4/4>

        A:Lead@|0|{
            <4*>
            | 1 1 5 5 | 6 6 5 - |
            | 4 4 3 3 | 2 2 1 - |
        }

        A:Piano@|0|{
            <2*>
            | [1] [1] | [4] [1] |
            | [4] [1] | [5] [1] |
        }

        A:Bass@|0|{
            <4*>
            | 1_ - 1_ - | 4__ - 1_ - |
            | 4__ - 1_ - | 5__ - 1_ - |
        }

        B:Lead@|0|{
            <4*>
            | 5 5 4 4 | 3 3 2 - |
            | 5 5 4 4 | 3 3 2 - |
        }

        B:Piano@|0|{
            <2*>
            | [1] [4] | [1] [5] |
            | [1] [4] | [1] [5] |
        }

        B:Bass@|0|{
            <4*>
            | 1_ - 4__ - | 1_ - 5__ - |
            | 1_ - 4__ - | 1_ - 5__ - |
        }

        -> A -> B -> A ->#
        """),
        ("Blank", """
        ::SCORE::
        ** Untitled Song **
        != 120
        ?= C
        <4/4>

        intro:Piano@|0|{
            <4*>
            | 1 2 3 4 |
        }

        -> intro ->#
        """),
        ("LeadSheet", """
        ::SCORE::
        ** Pop Lead Sheet **
        != 128
        ?= C
        <4/4>

        intro:Chord@|0|{
            <2*>
            | [1] [5] | [6m] [4] |
            | [1] [5] | [4]  [1] |
        }

        intro:Lead@|0|{
            <4*>
            | . . . . | . . . . |
            | 1 2 3 5 | 6 5 3 1 |
        }

        verse:Chord@|0|{
            <2*>
            | [1] [5] | [6m] [4] |
            | [1] [5] | [4]  [1] |
        }

        verse:Lead@|0|{
            <4*>
            | 1 2 3 1 | 5 5 3 - |
            | 6 6 5 3 | 2 - - - |
            | 1 2 3 1 | 5 5 3 - |
            | 4 3 2 5 | 1 - - - |
        }

        chorus:Chord@|0|{
            <2*>
            | [4] [5] | [3m] [6m] |
            | [2m] [5] | [1]  [1]  |
        }

        chorus:Lead@|0|{
            <4*>
            | 6 6 7 1^ | 7 5 3 - |
            | 4 4 3 2  | 5 - - - |
            | 6 6 7 1^ | 7 5 3 - |
            | 4 3 2 5  | 1 - - - |
        }

        -> intro -> verse -> chorus ->#
        """),
        ("Band", """
        ::SCORE::
        ** Band Arrangement **
        != 120
        ?= C
        <4/4>

        verse:Vocal@|0|{
            <4*>
            | 1 2 3 5 | 6 5 3 - |
            | 4 4 3 3 | 2 - - - |
            | 1 2 3 5 | 6 5 3 - |
            | 4 3 2 5 | 1 - - - |
        }

        verse:Keyboard@|0|{
            <2*>
            | [C] [G] | [Am] [F] |
            | [C] [G] | [F]  [C] |
            | [C] [G] | [Am] [F] |
            | [F] [G] | [C]  [C] |
        }

        verse:Guitar@|0|{
            <4*>
            | [C] - [C] - | [G] - [G] - |
            | [Am] - [Am] - | [F] - [F] - |
            | [C] - [C] - | [G] - [G] - |
            | [F] - [G] - | [C] - - - |
        }

        verse:Bass@|0|{
            <4*>
            | 1_ - 1_ - | 5__ - 5__ - |
            | 6__ - 6__ - | 4__ - 4__ - |
            | 1_ - 1_ - | 5__ - 5__ - |
            | 4__ - 5__ - | 1_ - - - |
        }

        verse:Drums@|0|{
            <8*>
            | X-X-X-X- | X-X-X-X- |
            | X-X-X-X- | X-X-X-X- |
            | X-X-X-X- | X-X-X-X- |
            | X-X-X-X- | S-S-C--- |
        }

        -> verse ->#
        """),
        ("Canon", """
        ::SCORE::
        ** Canon in C **
        != 108
        ?= C
        <4/4>

        theme:Voice1@|0|{
            <4*>
            | 1 2 3 1 | 1 2 3 1 |
            | 3 4 5 - | 3 4 5 - |
        }

        theme:Voice2@|+2|{
            <4*>
            | 1 2 3 1 | 1 2 3 1 |
            | 3 4 5 - | 3 4 5 - |
        }

        theme:Cello@|0|{
            <2*>
            | [1] [5] | [6m] [3m] |
            | [4] [1] | [4]  [5]  |
            | [1] [5] | [6m] [3m] |
        }

        -> theme ->#
        """),
        ("Drums", """
        ::SCORE::
        ** Drum Grooves **
        != 120
        ?= C
        <4/4>

        beat:Drums@|0|{
            <8*>
            | X-X-X-X- |
            | B-S-B-S- |
            | B--BS-B- |
            | SSSSC--- |
        }

        beat:Percussion@|0|{
            <8*>
            | X-X-X-X- |
            | X-X-X-X- |
            | X-X-X-X- |
            | X-X-X--- |
        }

        -> beat ->#
        """),
        ("ProgramLyrics", """
        ::SCORE::
        ** 月光小夜曲 **
        != 96
        ?= G
        <4/4>
        ~ "詞：阿怪"
        ~ "曲：阿怪"
        ~ "編：TMD"

        /*
        [Program / Stage Direction]
        Scene: A quiet night under the pale moonlight.
        */

        verse:Vocal@|0|{
            <4*>
            | 5_ 1 2 3 | 2 1 2 - |
            | 3 5 6 5 | 3 - - - |
            | 6 1^ 6 5 | 3 2 1 - |
            | 2 3 2 1_ | 1 - - - |
        }

        verse:Guitar@|0|{
            <2*>
            | [1] [5] | [6m] [3m] |
            | [4] [1] | [2m] [5]  |
            | [4] [5] | [3m] [6m] |
            | [2m] [5] | [1]  [1]  |
        }

        verse:Bass@|0|{
            <4*>
            | 1_ - 5__ - | 6__ - 3__ - |
            | 4__ - 1_ - | 2__ - 5__ - |
            | 4__ - 5__ - | 3__ - 6__ - |
            | 2__ - 5__ - | 1_ - - - |
        }

        -> verse ->#
        """)
    ]

    for template in templates {
        let sheet = try TmdParser.parseThrowing(string: template.content)
        #expect(!sheet.paragraphs.isEmpty, "Template \(template.name) should have paragraphs")
        #expect(!sheet.orders.isEmpty, "Template \(template.name) should have orders")
        let issues = TMDMeasureChecker.check(source: template.content)
        #expect(issues.isEmpty, "Template \(template.name) should not have measure discrepancy issues, found: \(issues)")
    }
}

@Test("Test multi-note dyad syntax 1+3 2+4 parsing and formatting")
func testMultiNoteParsingAndFormatting() throws {
    let source = """
    ::SCORE::
    ** MultiNote **
    != 120
    ?= C
    <4/4>

    main:Piano@|0|{
        <4*>
        | 1+3 2+4 3+5 1^+3 |
    }

    -> main ->#
    """
    let sheet = try TmdParser.parseThrowing(string: source)
    #expect(sheet.paragraphs.count == 1)
    let section = sheet.paragraphs[0].sections[0]
    #expect(section.unitGroups.count == 4)

    // Verify first unit group has multiNote with [1, 3]
    guard case .multiNote(let notes1) = section.unitGroups[0].units[0] else {
        Issue.record("Expected .multiNote, got \(section.unitGroups[0].units[0])")
        return
    }
    #expect(notes1.count == 2)
    #expect(notes1[0].degree == .c)
    #expect(notes1[1].degree == .e)

    // Verify formatting preserves 1+3
    let formatted = section.unitGroups[0].format()
    #expect(formatted == "1+3")

    // Check MeasureChecker treats each multi-note as 1 unit in <4*>
    let issues = TMDMeasureChecker.check(source: source)
    #expect(issues.isEmpty, "MeasureChecker should treat 1+3 as 1 unit, found issues: \(issues)")

    // Check PlaybackTimeline emits both notes at the same position and duration
    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    let noteEvents = timeline.events.filter { if case .note = $0.content { return true } else { return false } }
    #expect(noteEvents.count == 8) // 4 beats * 2 notes each = 8 note events
    #expect(noteEvents[0].position == 0.0)
    #expect(noteEvents[1].position == 0.0)
    #expect(noteEvents[0].duration == 1.0)
    #expect(noteEvents[1].duration == 1.0)
}

@Test("Test multi-note with tie extension")
func testMultiNoteTieExtension() throws {
    let source = """
    ::SCORE::
    ** MultiNote Tie **
    != 120
    ?= C
    <4/4>

    main:Piano@|0|{
        <4*>
        | 1+5 - - - |
    }

    -> main ->#
    """
    let sheet = try TmdParser.parseThrowing(string: source)
    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    let noteEvents = timeline.events.filter { if case .note = $0.content { return true } else { return false } }
    #expect(noteEvents.count == 2)
    #expect(noteEvents[0].position == 0.0)
    #expect(noteEvents[0].duration == 4.0) // 1 sustained for 4 beats
    #expect(noteEvents[1].position == 0.0)
    #expect(noteEvents[1].duration == 4.0) // 5 sustained for 4 beats
}

@Test("Test multi-note inside tuplet")
func testMultiNoteInsideTuplet() throws {
    let source = """
    ::SCORE::
    ** MultiNote Tuplet **
    != 120
    ?= C
    <4/4>

    main:Piano@|0|{
        <4*>
        | (1+3 2+4)%(--) 5 - |
    }

    -> main ->#
    """
    let sheet = try TmdParser.parseThrowing(string: source)
    let section = sheet.paragraphs[0].sections[0]
    #expect(section.unitGroups.count == 3)
    let tuplet = section.unitGroups[0]
    #expect(tuplet.length == 2)
    #expect(tuplet.units.count == 2)
    if case .multiNote(let notes) = tuplet.units[0] {
        #expect(notes.count == 2)
    } else {
        Issue.record("Expected multiNote in tuplet")
    }

    let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: "Piano")
    let noteEvents = timeline.events.filter { if case .note = $0.content { return true } else { return false } }
    // (1+3 2+4)%(--) => 2 notes at 0.0 (dur 1.0), 2 notes at 1.0 (dur 1.0); then 5 - => 1 note at 2.0 (dur 2.0)
    #expect(noteEvents.count == 5)
    #expect(noteEvents[0].position == 0.0 && noteEvents[0].duration == 1.0)
    #expect(noteEvents[1].position == 0.0 && noteEvents[1].duration == 1.0)
    #expect(noteEvents[2].position == 1.0 && noteEvents[2].duration == 1.0)
    #expect(noteEvents[3].position == 1.0 && noteEvents[3].duration == 1.0)
    #expect(noteEvents[4].position == 2.0 && noteEvents[4].duration == 2.0)
}

@Test("Test invalid multi-note syntax rejects or reports errors")
func testInvalidMultiNoteSyntax() {
    let invalidScores: [(name: String, score: String)] = [
        ("TrailingPlusAtBarEnd", """
        ::SCORE::
        ** TrailingPlusAtBarEnd **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | 1 2 3 4+ |
        }

        -> main ->#
        """),
        ("ConsecutivePlus", """
        ::SCORE::
        ** ConsecutivePlus **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | 1++3 2 3 4 |
        }

        -> main ->#
        """),
        ("InvalidChordRHS", """
        ::SCORE::
        ** InvalidChordRHS **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | 1+[C] 2 3 4 |
        }

        -> main ->#
        """),
        ("InvalidTieRHS", """
        ::SCORE::
        ** InvalidTieRHS **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | 1+- 2 3 4 |
        }

        -> main ->#
        """),
        ("StandalonePlus", """
        ::SCORE::
        ** StandalonePlus **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | + 1 2 3 |
        }

        -> main ->#
        """),
        ("InvalidScaleDegreeRHS", """
        ::SCORE::
        ** InvalidScaleDegreeRHS **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | 1+8 2 3 4 |
        }

        -> main ->#
        """),
        ("TrailingPlusBeforeNextMeasure", """
        ::SCORE::
        ** TrailingPlusBeforeNextMeasure **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | 1 2 3 4+ |
            | 1 2 3 4 |
        }

        -> main ->#
        """),
        ("TrailingPlusBeforeClosingBrace", """
        ::SCORE::
        ** TrailingPlusBeforeClosingBrace **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            1 2 3 4+
        }

        -> main ->#
        """),
        ("TrailingPlusSingleNoteBar", """
        ::SCORE::
        ** TrailingPlusSingleNoteBar **
        != 120
        ?= C
        <4/4>

        main:Piano@|0|{
            <4*>
            | 1+ |
        }

        -> main ->#
        """)
    ]

    for (name, score) in invalidScores {
        #expect(throws: Error.self, "Score '\(name)' with invalid '+' syntax must fail parsing") {
            try TmdParser.parseThrowing(string: score)
        }
    }
}
