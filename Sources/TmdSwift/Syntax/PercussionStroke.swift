import Foundation

/// Canonical percussion stroke represented by TMD's single-character drum pattern vocabulary.
///
/// Serves as the Single Source of Truth (SSOT) for percussion character resolution,
/// General MIDI Channel 10 pitches and velocities, unpitched staff display positions
/// (used by MusicXML and Music Braille), LilyPond `\drummode` tokens, and ABC percussion pitches.
public enum PercussionStroke: Equatable, Hashable, Sendable, CaseIterable {
    /// Bass Drum 1 / Kick (`D`, `d`, `B`, `b`).
    case kick
    /// Acoustic Snare (`S`, `s`).
    case snare
    /// Closed Hi-Hat (`X`, `x`).
    case closedHiHat
    /// Open Hi-Hat (`O`, `o`).
    case openHiHat
    /// Low-Mid Tom (`T`, `t`).
    case tom
    /// Crash Cymbal 1 (`C`, `c`).
    case crashCymbal

    /// Resolves a single TMD percussion pattern character into a typed `PercussionStroke`.
    public init?(character: Character) {
        switch character {
        case "D", "d", "B", "b": self = .kick
        case "S", "s": self = .snare
        case "X", "x": self = .closedHiHat
        case "O", "o": self = .openHiHat
        case "T", "t": self = .tom
        case "C", "c": self = .crashCymbal
        default: return nil
        }
    }

    /// Parses all valid percussion strokes from a TMD percussion pattern string.
    public static func parse(pattern: String) -> [PercussionStroke] {
        pattern.compactMap(PercussionStroke.init(character:))
    }

    /// General MIDI Channel 10 note number.
    public var midiPitch: Int {
        switch self {
        case .kick: 36
        case .snare: 38
        case .closedHiHat: 42
        case .openHiHat: 46
        case .tom: 45
        case .crashCymbal: 49
        }
    }

    /// Default MIDI velocity for this percussion stroke.
    public var defaultVelocity: UInt8 {
        switch self {
        case .kick: 118
        case .crashCymbal: 115
        case .snare: 105
        case .tom: 100
        case .openHiHat: 90
        case .closedHiHat: 78
        }
    }

    /// Unpitched staff display position (`stepIndex`: 0=C..6=B, `step`: `"C"`..`"B"`, `octave`: scientific octave)
    /// used by MusicXML `<unpitched>` and Music Braille unpitched percussion encoding.
    public var unpitchedDisplayPosition: (stepIndex: Int, step: String, octave: Int) {
        switch self {
        case .kick: (3, "F", 4)
        case .tom: (5, "A", 4)
        case .snare: (1, "D", 5)
        case .closedHiHat: (3, "F", 5)
        case .openHiHat: (4, "G", 5)
        case .crashCymbal: (5, "A", 5)
        }
    }

    /// LilyPond `\drummode` drum pitch token.
    public var lilyPondDrumName: String {
        switch self {
        case .closedHiHat: "hh"
        case .openHiHat: "hho"
        case .tom: "toml"
        case .snare: "sn"
        case .kick: "bd"
        case .crashCymbal: "cymc"
        }
    }

    /// ABC notation percussion pitch string (for hi-hat, tom, and snare).
    public var abcPitch: String? {
        switch self {
        case .closedHiHat: "^F"
        case .tom: "A"
        case .snare: "D"
        case .kick, .openHiHat, .crashCymbal: nil
        }
    }
}
