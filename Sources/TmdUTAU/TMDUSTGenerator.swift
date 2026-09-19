import Foundation
import TmdSwift
import TmdMIDI

/// Options for configuring UTAU `.ust` exports.
public struct USTExportOptions: Sendable, Equatable {
    /// Title of the project. If empty, falls back to the sheet's name.
    public var projectName: String
    /// Voice directory path to embed in UST settings.
    public var voiceDir: String
    /// Default lyric to use if none is provided for a note.
    public var defaultLyric: String
    /// Optional sequence of lyrics to apply to consecutive notes.
    public var lyrics: [String]
    /// Ticks per quarter note (standard UTAU PPQ is 480).
    public var ticksPerQuarter: UInt16

    public init(
        projectName: String = "",
        voiceDir: String = "",
        defaultLyric: String = "a",
        lyrics: [String] = [],
        ticksPerQuarter: UInt16 = 480
    ) {
        self.projectName = projectName
        self.voiceDir = voiceDir
        self.defaultLyric = defaultLyric
        self.lyrics = lyrics
        self.ticksPerQuarter = ticksPerQuarter
    }
}

/// Exporter for UTAU sequence text (`.ust`) format, fully compatible with
/// original UTAU and modern cross-platform OpenUtau.
public struct TMDUSTGenerator: Sendable {
    /// Generates a `.ust` formatted string from a parsed TMD `Sheet`.
    ///
    /// - Parameters:
    ///   - sheet: The parsed TMD score sheet.
    ///   - targetInstrument: Specific instrument track to export. If nil, auto-selects vocal tracks.
    ///   - options: Configuration options including project name and lyrics.
    /// - Returns: A complete UTAU Sequence Text (`.ust`) string.
    public static func generateUST(
        from sheet: Sheet,
        targetInstrument: String? = nil,
        options: USTExportOptions = USTExportOptions()
    ) -> String {
        let selectedInstrument = resolveTargetInstrument(sheet: sheet, requested: targetInstrument)
        let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: selectedInstrument)

        let initialTempo = sheet.speed > 0 ? sheet.speed : 120.0
        let title = options.projectName.isEmpty ? (sheet.name.isEmpty ? "TMD UTAU Score" : sheet.name) : options.projectName

        var lines: [String] = [
            "[#SETTING]",
            String(format: "Tempo=%.2f", initialTempo),
            "Tracks=1",
            "ProjectName=\(title)",
            "VoiceDir=\(options.voiceDir)",
            "OutFile=",
            "CacheDir=",
            "Tool1=",
            "Tool2=",
            "Mode2=True",
            "Charset=UTF-8",
            ""
        ]

        var currentPosition = 0.0
        var currentTempo = initialTempo
        var noteIndex = 0
        var lyricIndex = 0

        for event in timeline.events {
            // Fill any timeline gap prior to this event with a Rest (Lyric=R)
            if event.position > currentPosition {
                let gapDuration = event.position - currentPosition
                let gapTicks = Int((gapDuration * Double(options.ticksPerQuarter)).rounded())
                if gapTicks > 0 {
                    lines.append(contentsOf: formatRestNote(index: noteIndex, ticks: gapTicks))
                    noteIndex += 1
                }
                currentPosition = event.position
            }

            switch event.content {
            case .note(let note):
                let ticks = max(1, Int((event.duration * Double(options.ticksPerQuarter)).rounded()))
                let pitch = TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: event.state.keyOffset)
                let lyric: String
                if lyricIndex < options.lyrics.count {
                    lyric = options.lyrics[lyricIndex]
                    lyricIndex += 1
                } else {
                    lyric = options.defaultLyric
                }

                var noteLines: [String] = [
                    String(format: "[#%04d]", noteIndex),
                    "Length=\(ticks)",
                    "Lyric=\(lyric)",
                    "NoteNum=\(pitch)",
                    "PreUtterance=",
                    "Intensity=100",
                    "Modulation=0"
                ]

                if abs(event.state.tempo - currentTempo) > 0.001 {
                    noteLines.append(String(format: "Tempo=%.2f", event.state.tempo))
                    currentTempo = event.state.tempo
                }

                noteLines.append("")
                lines.append(contentsOf: noteLines)
                noteIndex += 1
                currentPosition = event.position + event.duration

            case .rest:
                let ticks = max(1, Int((event.duration * Double(options.ticksPerQuarter)).rounded()))
                lines.append(contentsOf: formatRestNote(index: noteIndex, ticks: ticks))
                noteIndex += 1
                currentPosition = event.position + event.duration

            case .chord, .percussion:
                break
            }
        }

        lines.append("[#TRACKEND]")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private static func formatRestNote(index: Int, ticks: Int) -> [String] {
        [
            String(format: "[#%04d]", index),
            "Length=\(ticks)",
            "Lyric=R",
            "NoteNum=60",
            "PreUtterance=",
            ""
        ]
    }

    public static func resolveTargetInstrument(sheet: Sheet, requested: String?) -> String {
        sheet.resolveVocalInstrument(requested: requested)
    }
}
