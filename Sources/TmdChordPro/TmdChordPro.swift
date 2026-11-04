import Foundation
import TmdSwift

/// Options configuring the ChordPro exporter.
public struct ChordProOptions: Sendable, Equatable {
    /// Number of measures formatted per line (defaults to 4).
    public var measuresPerLine: Int

    public init(measuresPerLine: Int = 4) {
        self.measuresPerLine = measuresPerLine
    }
}

/// ChordPro exporter for TMD scores.
///
/// Converts a `Sheet` into standard ChordPro lead sheet format, with section comments
/// and measure barlines (`| [C] | [F] |`).
public struct TmdChordProGenerator: Sendable {

    /// Generates a ChordPro string from a parsed TMD `Sheet`.
    public static func generateChordPro(
        from inputSheet: Sheet,
        options: ChordProOptions = ChordProOptions()
    ) -> String {
        let (sheet, distinctInstruments) = inputSheet.preparedForExport()
        var lines: [String] = []

        // Title and Metadata directives
        if !sheet.name.isEmpty {
            lines.append("{title: \(sheet.name)}")
        }

        if let subtitle = sheet.metadata["subtitle"] {
            lines.append("{subtitle: \(subtitle)}")
        }
        if let artist = sheet.metadata["artist"] {
            lines.append("{artist: \(artist)}")
        }
        if let composer = sheet.metadata["composer"] {
            let comp = composer.replacingOccurrences(
                of: #"^曲[：:]\s*"#, with: "", options: .regularExpression)
            lines.append("{composer: \(comp)}")
        }
        if let lyricist = sheet.metadata["lyricist"] ?? sheet.metadata["lyrics"] {
            let lyr = lyricist.replacingOccurrences(
                of: #"^詞[：:]\s*"#, with: "", options: .regularExpression)
            lines.append("{lyricist: \(lyr)}")
        }
        if let arranger = sheet.metadata["arranger"] {
            let arr = arranger.replacingOccurrences(
                of: #"^編[：:]\s*"#, with: "", options: .regularExpression)
            lines.append("{arranger: \(arr)}")
        }

        let initialKeyName =
            sheet.declaredKey
            ?? PitchMapping.tonicScaleInfo(forKeyOffset: sheet.keySignature.semitoneOffset).name
        lines.append("{key: \(initialKeyName)}")

        if sheet.beat.count > 0 && sheet.beat.noteValue > 0 {
            lines.append("{time: \(sheet.beat.count)/\(sheet.beat.noteValue)}")
        }

        if sheet.speed > 0 {
            lines.append("{tempo: \(Int(round(sheet.speed)))}")
        }

        // Determine target track: pick guitar/chords instrument or first instrument
        let regex = try? NSRegularExpression(
            pattern: "guitar|chord|lead|piano", options: .caseInsensitive)
        let targetInstrument =
            distinctInstruments.first { inst in
                regex?.firstMatch(in: inst, range: NSRange(inst.startIndex..., in: inst)) != nil
            } ?? distinctInstruments.first ?? "Piano"

        // Group sections by order
        let orders = sheet.effectivePlaybackOrders

        let measuresPerLine = max(1, options.measuresPerLine)
        var currentKeyOffset = sheet.keySignature.semitoneOffset
        var emittedKeyOffset = currentKeyOffset

        for order in orders {
            switch order {
            case .relative(let value):
                if let delta = Int(value.replacingOccurrences(of: "+", with: "")) {
                    currentKeyOffset += delta
                }
                continue
            case .absolute(let value):
                currentKeyOffset = KeySignature(string: value).semitoneOffset
                continue
            case .macro:
                continue
            case .name(let pName):
                guard !pName.isEmpty else { continue }
            }
            guard case .name(let pName) = order else { continue }
            let baseSectionName = Playback.parseSectionSelector(pName).name
            let sectionParagraphs = sheet.entries.filter { $0.name == baseSectionName }
            let sectionKey = keySignature(for: currentKeyOffset)
            let sectionSheet = Sheet(
                name: sheet.name,
                speed: sheet.speed,
                keySignature: sectionKey,
                beat: sheet.beat,
                entries: sectionParagraphs,
                playback: [.name(pName)],
                metadata: sheet.metadata
            )

            let sectionInstruments = Array(Set(sectionParagraphs.compactMap { $0.assignment }))
                .sorted()
            let instToRender =
                sectionInstruments.contains(targetInstrument)
                ? targetInstrument
                : (sectionInstruments.first { inst in
                    regex?.firstMatch(in: inst, range: NSRange(inst.startIndex..., in: inst)) != nil
                } ?? sectionInstruments.first ?? targetInstrument)

            let sectionMeasures = TmdMeasureRenderer.renderMeasures(
                sheet: sectionSheet,
                instrument: instToRender
            )

            let vocalInstrument = sectionParagraphs.first {
                $0.sections.contains { !$0.lyrics.isEmpty }
            }?.assignment
            let vocalMeasures: [Measure] =
                if let vocalInstrument, vocalInstrument != instToRender {
                    TmdMeasureRenderer.renderMeasures(
                        sheet: sectionSheet,
                        instrument: vocalInstrument
                    )
                } else {
                    sectionMeasures
                }

            let measureCount = max(sectionMeasures.count, vocalMeasures.count)
            if measureCount == 0 { continue }

            lines.append("")
            if currentKeyOffset != emittedKeyOffset {
                let modulatedKeyName = PitchMapping.tonicScaleInfo(forKeyOffset: currentKeyOffset)
                    .name
                lines.append("{key: \(modulatedKeyName)}")
                emittedKeyOffset = currentKeyOffset
            }
            lines.append("{comment: \(pName)}")

            var measureStrings: [String] = []

            for mIdx in 0..<measureCount {
                let chordEvents: [(offset: Double, text: String)] =
                    (mIdx < sectionMeasures.count ? sectionMeasures[mIdx].events : []).compactMap {
                        ev in
                        if case .chord(let chord) = ev.content {
                            return (
                                ev.startOffset,
                                "[\(chordText(chord, keyOffset: ev.state.keyOffset))]"
                            )
                        }
                        return nil
                    }
                let lyricEvents: [(offset: Double, text: String)] =
                    (mIdx < vocalMeasures.count
                        ? vocalMeasures[mIdx].simultaneousEventGroups : []).compactMap { group in
                        guard let noteEv = group.first(where: { $0.content.isNote }),
                            let syl = noteEv.lyric
                        else { return nil }
                        return (noteEv.startOffset, syl.rawText)
                    }

                if !lyricEvents.isEmpty {
                    var chordCursor = 0
                    var tokens: [String] = []
                    for lyr in lyricEvents {
                        var prefixChords = ""
                        while chordCursor < chordEvents.count
                            && chordEvents[chordCursor].offset <= lyr.offset + 1e-4
                        {
                            prefixChords += chordEvents[chordCursor].text
                            chordCursor += 1
                        }
                        tokens.append(prefixChords + lyr.text)
                    }
                    while chordCursor < chordEvents.count {
                        tokens.append(chordEvents[chordCursor].text)
                        chordCursor += 1
                    }
                    measureStrings.append(tokens.joined(separator: " "))
                } else if !chordEvents.isEmpty {
                    measureStrings.append(chordEvents.map(\.text).joined(separator: " "))
                } else {
                    measureStrings.append("")
                }
            }

            // Format into lines of measuresPerLine: | [C] | [F] |
            var i = 0
            while i < measureStrings.count {
                let end = min(i + measuresPerLine, measureStrings.count)
                let chunk = measureStrings[i..<end]
                let body = chunk.map { c in
                    c.isEmpty ? " " : " \(c) "
                }.joined(separator: "|")
                lines.append("|\(body)|")
                i += measuresPerLine
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func keySignature(for offset: Int) -> KeySignature {
        let keyName = PitchMapping.tonicScaleInfo(forKeyOffset: offset).name
        return KeySignature(string: keyName)
    }

    private static func formatSpelledRoot(_ spelled: SpelledPitch) -> String {
        let acc: String
        switch spelled.alter {
        case 1: acc = "#"
        case -1: acc = "b"
        case 2: acc = "##"
        case -2: acc = "bb"
        default: acc = ""
        }
        return "\(spelled.step)\(acc)"
    }

    private static func chordText(_ chord: ChordSymbol, keyOffset: Int) -> String {
        let root = formatSpelledRoot(
            PitchMapping.spell(chordRoot: chord.root, keyOffset: keyOffset))
        let suffix = String(chord.description.dropFirst(chord.root.description.count))
        guard let bass = chord.bass else { return root + suffix }
        let qualitySuffix =
            suffix.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first.map(
                String.init) ?? ""
        let bassText = formatSpelledRoot(
            PitchMapping.spell(chordRoot: bass, keyOffset: keyOffset))
        return root + qualitySuffix + "/" + bassText
    }
}
