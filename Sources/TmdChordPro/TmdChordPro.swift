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
public struct TMDChordProGenerator: Sendable {

    /// Generates a ChordPro string from a parsed TMD `Sheet`.
    public static func generateChordPro(
        from inputSheet: Sheet,
        options: ChordProOptions = ChordProOptions()
    ) -> String {
        let sheet = TMDMacroEvaluator.expand(inputSheet)
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
            let comp = composer.replacingOccurrences(of: #"^曲[：:]\s*"#, with: "", options: .regularExpression)
            lines.append("{composer: \(comp)}")
        }
        if let lyricist = sheet.metadata["lyricist"] ?? sheet.metadata["lyrics"] {
            let lyr = lyricist.replacingOccurrences(of: #"^詞[：:]\s*"#, with: "", options: .regularExpression)
            lines.append("{lyricist: \(lyr)}")
        }
        if let arranger = sheet.metadata["arranger"] {
            let arr = arranger.replacingOccurrences(of: #"^編[：:]\s*"#, with: "", options: .regularExpression)
            lines.append("{arranger: \(arr)}")
        }

        lines.append("{key: \(sheet.keySignature.description)}")

        if sheet.beat.count > 0 && sheet.beat.noteValue > 0 {
            lines.append("{time: \(sheet.beat.count)/\(sheet.beat.noteValue)}")
        }

        if sheet.speed > 0 {
            lines.append("{tempo: \(Int(round(sheet.speed)))}")
        }

        // Determine target track: pick guitar/chords instrument or first instrument
        let distinctInstruments = sheet.distinctInstruments(fallbackToDefault: false)
        let regex = try? NSRegularExpression(pattern: "guitar|chord|lead|piano", options: .caseInsensitive)
        let targetInstrument = distinctInstruments.first { inst in
            regex?.firstMatch(in: inst, range: NSRange(inst.startIndex..., in: inst)) != nil
        } ?? distinctInstruments.first ?? "Piano"

        // Group sections by order
        var seenNames = Set<String>()
        var uniqueParagraphNames: [String] = []
        for paragraph in sheet.paragraphs {
            if seenNames.insert(paragraph.name).inserted {
                uniqueParagraphNames.append(paragraph.name)
            }
        }

        let orders: [Order] = !sheet.orders.isEmpty
            ? sheet.orders
            : uniqueParagraphNames.map { .name($0) }

        let measuresPerLine = max(1, options.measuresPerLine)

        for order in orders {
            guard case .name(let pName) = order else { continue }
            let sectionParagraphs = sheet.paragraphs.filter { $0.name == pName }
            // Create a sub-sheet with just this section to isolate its measures
            let sectionSheet = Sheet(
                name: sheet.name,
                speed: sheet.speed,
                keySignature: sheet.keySignature,
                beat: sheet.beat,
                paragraphs: sectionParagraphs,
                orders: [.name(pName)],
                metadata: sheet.metadata
            )

            let sectionInstruments = Array(Set(sectionParagraphs.map { $0.instrument })).sorted()
            let instToRender = sectionInstruments.contains(targetInstrument)
                ? targetInstrument
                : (sectionInstruments.first { inst in
                    regex?.firstMatch(in: inst, range: NSRange(inst.startIndex..., in: inst)) != nil
                } ?? sectionInstruments.first ?? targetInstrument)

            let sectionMeasures = TMDMeasureRenderer.renderMeasures(
                sheet: sectionSheet,
                instrument: instToRender
            )

            if sectionMeasures.isEmpty { continue }

            lines.append("")
            lines.append("{comment: \(pName)}")

            var measureStrings: [String] = []

            for m in sectionMeasures {
                var chordsInMeasure: [String] = []
                for ev in m.events {
                    if case .chord(let chord) = ev.content {
                        chordsInMeasure.append("[\(chord.description)]")
                    }
                }

                if !chordsInMeasure.isEmpty {
                    measureStrings.append(chordsInMeasure.joined(separator: " "))
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
}
