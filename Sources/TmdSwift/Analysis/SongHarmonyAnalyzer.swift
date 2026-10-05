import Foundation

/// Extracts harmonic content and playback key changes from a parsed score.
public enum TMDSongHarmonyAnalyzer {
    public static func analyze(sheet: Sheet) -> TMDHarmonyProfile {
        var chords: [String] = []
        for paragraph in sheet.entries {
            for section in paragraph.sections {
                for group in section.unitGroups {
                    for unit in group.units {
                        if case .chord(let chord) = unit {
                            let raw = "[\(chord.description)]"
                            if !chords.contains(raw) {
                                chords.append(raw)
                            }
                        }
                    }
                }
            }
        }

        var modulations: [String] = []
        for order in sheet.playback {
            if case .relative(let value) = order {
                modulations.append("Relative: \(value) semitones")
            } else if case .absolute(let value) = order {
                modulations.append("Key: \(value)")
            }
        }

        return TMDHarmonyProfile(
            distinctChords: chords,
            chordCount: chords.count,
            modulations: modulations
        )
    }
}
