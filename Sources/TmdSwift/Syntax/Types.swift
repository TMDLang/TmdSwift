import Foundation

/// Time signature of the piece (e.g. `<4/4>` or `<3/4>`).
///
/// > Note: Originally named `Beat` in Aguai's C++ code, where the denominator
/// > was named `node`.
public struct Beat: Equatable, Sendable {
    /// Number of beats per measure (numerator), e.g. `4` in `4/4`.
    ///
    /// > Note: Originally named `count` in Aguai's C++ code.
    public let count: Int

    /// Unit note value representing one beat (denominator / beat unit), e.g.
    /// `4` for a quarter note.
    ///
    /// > Note: Originally named `node` in Aguai's C++ code (likely a typo for
    /// > `note`).
    public let noteValue: Int

    public init(count: Int = 4, noteValue: Int = 4) {
        self.count = count
        self.noteValue = noteValue
    }

    /// Resolves the canonical metronome beat unit and BPM for a quarter-note tempo (`quarterBPM`),
    /// including compound-meter dotted-quarter conversion (e.g. `6/8`, `9/8`, `12/8`).
    public func metronomeTempo(forQuarterBPM quarterBPM: Double) -> MetronomeTempo {
        if noteValue == 8 && count > 3 && count % 3 == 0 {
            let bpm = Int((quarterBPM / 1.5).rounded())
            return MetronomeTempo(
                beatUnit: "quarter",
                lilyPondUnit: "4.",
                abcUnit: "3/8",
                isDotted: true,
                perMinute: bpm
            )
        }
        switch noteValue {
        case 2:
            let bpm = Int((quarterBPM / 2.0).rounded())
            return MetronomeTempo(
                beatUnit: "half",
                lilyPondUnit: "2",
                abcUnit: "1/2",
                isDotted: false,
                perMinute: bpm
            )
        case 8:
            let bpm = Int((quarterBPM * 2.0).rounded())
            return MetronomeTempo(
                beatUnit: "eighth",
                lilyPondUnit: "8",
                abcUnit: "1/8",
                isDotted: false,
                perMinute: bpm
            )
        case 16:
            let bpm = Int((quarterBPM * 4.0).rounded())
            return MetronomeTempo(
                beatUnit: "16th",
                lilyPondUnit: "16",
                abcUnit: "1/16",
                isDotted: false,
                perMinute: bpm
            )
        default:
            let bpm = Int(quarterBPM.rounded())
            return MetronomeTempo(
                beatUnit: "quarter",
                lilyPondUnit: "4",
                abcUnit: "1/4",
                isDotted: false,
                perMinute: bpm
            )
        }
    }
}

/// Canonical metronome representation resolved from a `Beat` time signature and quarter-note BPM.
public struct MetronomeTempo: Equatable, Sendable {
    public let beatUnit: String
    public let lilyPondUnit: String
    public let abcUnit: String
    public let isDotted: Bool
    public let perMinute: Int

    public init(
        beatUnit: String,
        lilyPondUnit: String,
        abcUnit: String,
        isDotted: Bool,
        perMinute: Int
    ) {
        self.beatUnit = beatUnit
        self.lilyPondUnit = lilyPondUnit
        self.abcUnit = abcUnit
        self.isDotted = isDotted
        self.perMinute = perMinute
    }
}

/// Accidental symbol modifying the pitch (natural, sharp, or flat).
///
/// > Note: Originally named `SharpFalls` in Aguai's C++ code, where flat was
/// > named `Falls`.
public enum Accidental: Equatable, Hashable, Sendable {
    /// Natural pitch (unaltered).
    ///
    /// > Note: Originally named `SharpFalls::Normal` in Aguai's C++ code.
    case natural

    /// Sharp accidental (syntax denoted by `'`).
    ///
    /// > Note: Originally named `SharpFalls::Sharp` in Aguai's C++ code.
    case sharp

    /// Flat accidental (syntax denoted by `,`).
    ///
    /// > Note: Originally named `SharpFalls::Falls` in Aguai's C++ code.
    case flat

    /// Chromatic adjustment represented by this accidental.
    public var semitoneOffset: Int {
        switch self {
        case .natural: 0
        case .sharp: 1
        case .flat: -1
        }
    }

    /// The TMD syntax symbol (`""`, `"'"`, or `","`) for this accidental.
    public var tmdSymbol: String {
        switch self {
        case .natural: ""
        case .sharp: "'"
        case .flat: ","
        }
    }
}

/// A typed TMD key signature consisting of a tonic and an optional accidental.
public struct KeySignature: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The tonic letter of the key.
    public let tonic: ScaleDegree

    /// The accidental applied to the tonic.
    public let accidental: Accidental

    public init(tonic: ScaleDegree = .c, accidental: Accidental = .natural) {
        self.tonic = tonic
        self.accidental = accidental
    }

    /// Parses TMD spellings such as `C`, `A'`, and `E,`. Invalid spellings
    /// resolve to C so a non-optional Sheet property remains safe to use.
    public init(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
            let tonic = ScaleDegree(letter: first)
        else {
            self.init()
            return
        }
        let accidental: Accidental
        if trimmed.contains("'") || trimmed.contains("#") {
            accidental = .sharp
        } else if trimmed.contains(",") || trimmed.contains("b") {
            accidental = .flat
        } else {
            accidental = .natural
        }
        self.init(tonic: tonic, accidental: accidental)
    }

    public var description: String {
        "\(tonic.letter)\(accidental.tmdSymbol)"
    }

    /// Chromatic offset of this key's tonic from C.
    public var semitoneOffset: Int {
        tonic.semitoneOffset + accidental.semitoneOffset
    }
}

/// A chord root in TMD notation, either a movable-do degree or a letter root.
public struct ChordRoot: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let degree: ScaleDegree
    public let accidental: Accidental
    public let octave: Int
    public let isScaleDegree: Bool

    public init(
        degree: ScaleDegree, accidental: Accidental = .natural, octave: Int = 0,
        isScaleDegree: Bool = false
    ) {
        self.degree = degree
        self.accidental = accidental
        self.octave = octave
        self.isScaleDegree = isScaleDegree
    }

    public var description: String {
        let value =
            isScaleDegree
            ? String(degree.rawValue)
            : degree.letter
        let acc = "\(value)\(accidental.tmdSymbol)"
        let oct =
            if octave > 0 {
                String(repeating: "^", count: octave)
            } else if octave < 0 {
                String(repeating: "_", count: -octave)
            } else {
                ""
            }
        return "\(acc)\(oct)"
    }

    /// Chromatic offset of this root within the octave for pitch exporters.
    public var semitoneOffset: Int {
        degree.semitoneOffset + accidental.semitoneOffset + (octave * 12)
    }
}

/// Common chord qualities. Unrecognized suffixes are retained as `.custom`.
public enum ChordQuality: Equatable, Hashable, Sendable {
    case major
    case minor
    case dominant7
    case major7
    case minor7
    case diminished
    case halfDiminished
    case augmented
    case suspended
    case power
    case custom(String)

    /// Semitone intervals used by pitch-based exporters.
    public var semitoneIntervals: [Int] {
        switch self {
        case .major: [0, 4, 7]
        case .minor: [0, 3, 7]
        case .dominant7: [0, 4, 7, 10]
        case .major7: [0, 4, 7, 11]
        case .minor7: [0, 3, 7, 10]
        case .diminished: [0, 3, 6]
        case .halfDiminished: [0, 3, 6, 10]
        case .augmented: [0, 4, 8]
        case .suspended: [0, 5, 7]
        case .power: [0, 7]
        case .custom: [0, 4, 7]
        }
    }

    /// Diatonic step and semitone intervals above the chord root used for diatonic chord spelling.
    public var diatonicVoicingIntervals: [(diatonicSteps: Int, semitones: Int)] {
        switch self {
        case .major, .custom: [(0, 0), (2, 4), (4, 7)]
        case .minor: [(0, 0), (2, 3), (4, 7)]
        case .dominant7: [(0, 0), (2, 4), (4, 7), (6, 10)]
        case .major7: [(0, 0), (2, 4), (4, 7), (6, 11)]
        case .minor7: [(0, 0), (2, 3), (4, 7), (6, 10)]
        case .diminished: [(0, 0), (2, 3), (4, 6)]
        case .halfDiminished: [(0, 0), (2, 3), (4, 6), (6, 10)]
        case .augmented: [(0, 0), (2, 4), (4, 8)]
        case .suspended: [(0, 0), (3, 5), (4, 7)]
        case .power: [(0, 0), (4, 7)]
        }
    }

    /// Canonical TMD chord quality suffix.
    public var tmdSuffix: String {
        switch self {
        case .major: ""
        case .minor: "m"
        case .dominant7: "7"
        case .major7: "maj7"
        case .minor7: "m7"
        case .diminished: "dim"
        case .halfDiminished: "m7-5"
        case .augmented: "aug"
        case .suspended: "sus"
        case .power: "5"
        case .custom(let value): value
        }
    }

    /// Creates a `ChordQuality` from a TMD chord quality suffix string.
    public init(suffix: String) {
        switch suffix.lowercased() {
        case "": self = .major
        case "m": self = .minor
        case "7": self = .dominant7
        case "maj7": self = .major7
        case "m7": self = .minor7
        case "dim": self = .diminished
        case "m7-5", "ø": self = .halfDiminished
        case "aug", "+": self = .augmented
        case "sus", "sus4": self = .suspended
        case "5": self = .power
        default: self = .custom(suffix)
        }
    }
}

/// A typed chord symbol with a finite common-quality vocabulary and extensibility.
public struct ChordSymbol: Equatable, Hashable, Sendable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public static let extendedChordQualities: Set<String> = [
        "6", "m6", "min6", "6/9", "69", "m6/9",
        "9", "maj9", "m9", "min9",
        "add9", "add2", "add4", "add11",
        "11", "m11", "min11", "maj11",
        "13", "maj13", "m13", "min13",
        "sus2", "sus4", "7sus4", "7sus2", "9sus4",
        "dim7", "aug7", "m7b5",
        "7b5", "7#5", "7b9", "7#9", "7#11", "7b13",
        "m(maj7)", "mmaj7", "maj7#11", "maj7#5",
    ]

    public static func isRecognizedExtendedQuality(_ suffix: String) -> Bool {
        extendedChordQualities.contains(
            suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    public let root: ChordRoot
    public let quality: ChordQuality
    public let bass: ChordRoot?

    public init(root: ChordRoot, quality: ChordQuality = .major, bass: ChordRoot? = nil) {
        self.root = root
        self.quality = quality
        self.bass = bass
    }

    public static func parseRoot(from chars: [Character]) -> (root: ChordRoot, remaining: String)? {
        guard let first = chars.first else { return nil }
        let isDegree = ("1"..."7").contains(String(first))
        let degree: ScaleDegree
        let rootEnd: Int
        if isDegree, let intVal = Int(String(first)), let parsed = ScaleDegree(rawValue: intVal) {
            degree = parsed
            rootEnd = 1
        } else {
            guard let parsed = ScaleDegree(letter: first) else {
                return nil
            }
            degree = parsed
            rootEnd = 1
        }
        var accidental: Accidental = .natural
        var suffixStart = rootEnd
        if suffixStart < chars.count && ["'", "#", ",", "b"].contains(chars[suffixStart]) {
            accidental = (chars[suffixStart] == "'" || chars[suffixStart] == "#") ? .sharp : .flat
            suffixStart += 1
        }
        var octave = 0
        while suffixStart < chars.count && (chars[suffixStart] == "_" || chars[suffixStart] == "^")
        {
            if chars[suffixStart] == "^" {
                octave += 1
            } else if chars[suffixStart] == "_" {
                octave -= 1
            }
            suffixStart += 1
        }
        let remaining = String(chars.dropFirst(suffixStart))
        return (
            ChordRoot(
                degree: degree, accidental: accidental, octave: octave, isScaleDegree: isDegree),
            remaining
        )
    }

    public init(string: String) {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("/") {
            let parts = value.components(separatedBy: "/")
            let mainPart = parts[0]
            let bassPart = parts.dropFirst().joined(separator: "/")

            if let parsedMain = Self.parseRoot(from: Array(mainPart)) {
                let bassRoot = Self.parseRoot(from: Array(bassPart))?.root
                self.init(
                    root: parsedMain.root,
                    quality: ChordQuality(suffix: parsedMain.remaining),
                    bass: bassRoot
                )
                return
            }
        }

        if let parsed = Self.parseRoot(from: Array(value)) {
            self.init(root: parsed.root, quality: ChordQuality(suffix: parsed.remaining))
            return
        }

        self.init(root: ChordRoot(degree: .c), quality: .custom(value))
    }

    public init(stringLiteral value: String) {
        self.init(string: value)
    }

    public var description: String {
        let bassText = bass.map { "/\($0.description)" } ?? ""
        return root.description + quality.tmdSuffix + bassText
    }
}

/// The seven scale degrees used by TMD numbered notation.
public enum ScaleDegree: Int, CaseIterable, Equatable, Sendable {
    case c = 1
    case d = 2
    case e = 3
    case f = 4
    case g = 5
    case a = 6
    case b = 7

    /// The canonical letter name shared by keys and chord roots.
    public var letter: String {
        switch self {
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .a: return "A"
        case .b: return "B"
        }
    }

    /// Natural chromatic offset of this degree within a major scale.
    public var semitoneOffset: Int {
        [0, 2, 4, 5, 7, 9, 11][rawValue - 1]
    }

    /// Creates a scale degree from a case-insensitive letter name.
    public init?(letter: Character) {
        switch letter.uppercased() {
        case "C": self = .c
        case "D": self = .d
        case "E": self = .e
        case "F": self = .f
        case "G": self = .g
        case "A": self = .a
        case "B": self = .b
        default: return nil
        }
    }
}

/// A diatonically spelled pitch with step, alteration, scientific octave, and MIDI pitch.
public struct SpelledPitch: Equatable, Sendable {
    public let stepIndex: Int
    public let step: String
    public let alter: Int
    public let octave: Int
    public let midiPitch: Int

    public init(stepIndex: Int, step: String, alter: Int, octave: Int, midiPitch: Int) {
        self.stepIndex = stepIndex
        self.step = step
        self.alter = alter
        self.octave = octave
        self.midiPitch = midiPitch
    }
}

/// Diatonic scale degree and accidental profile for a tonic key offset.
public struct TonicScaleInfo: Equatable, Sendable {
    public let name: String
    /// Accidental offset (-1, 0, 1) for steps C=0, D=1, E=2, F=3, G=4, A=5, B=6.
    public let stepAccidentals: [Int]
    /// Diatonic step (0..6) for scale degrees 1..7 (index 0..6).
    public let degreeSteps: [Int]

    public init(name: String, stepAccidentals: [Int], degreeSteps: [Int]) {
        self.name = name
        self.stepAccidentals = stepAccidentals
        self.degreeSteps = degreeSteps
    }
}

/// Shared pitch-name mappings used by the text and binary exporters.
public enum PitchMapping {
    public static let tmdKeyNames = [
        "C", "C'", "D", "E,", "E", "F", "F'", "G", "A,", "A", "B,", "B",
    ]

    public static let stepNames = ["C", "D", "E", "F", "G", "A", "B"]
    public static let stepLowerNames = ["c", "d", "e", "f", "g", "a", "b"]
    public static let naturalStepSemitones = [0, 2, 4, 5, 7, 9, 11]

    public static let musicXMLSteps = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
    public static let musicXMLAlters = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
    public static let lilyPondNames = [
        "c", "cis", "d", "dis", "e", "f", "fis", "g", "gis", "a", "ais", "b",
    ]
    public static let abcUpperNames = [
        "C", "^C", "D", "^D", "E", "F", "^F", "G", "^G", "A", "^A", "B",
    ]
    public static let abcLowerNames = [
        "c", "^c", "d", "^d", "e", "f", "^f", "g", "^g", "a", "^a", "b",
    ]

    public static func normalizedSemitone(_ semitone: Int) -> Int {
        (semitone % 12 + 12) % 12
    }

    public static func keyName(forSemitone semitone: Int) -> String {
        tmdKeyNames[normalizedSemitone(semitone)]
    }

    public static func tonicScaleInfo(forKeyOffset keyOffset: Int) -> TonicScaleInfo {
        switch normalizedSemitone(keyOffset) {
        case 0:
            return TonicScaleInfo(
                name: "C", stepAccidentals: [0, 0, 0, 0, 0, 0, 0],
                degreeSteps: [0, 1, 2, 3, 4, 5, 6])
        case 1:
            return TonicScaleInfo(
                name: "Db", stepAccidentals: [0, -1, -1, 0, -1, -1, -1],
                degreeSteps: [1, 2, 3, 4, 5, 6, 0])
        case 2:
            return TonicScaleInfo(
                name: "D", stepAccidentals: [1, 0, 0, 1, 0, 0, 0],
                degreeSteps: [1, 2, 3, 4, 5, 6, 0])
        case 3:
            return TonicScaleInfo(
                name: "Eb", stepAccidentals: [0, 0, -1, 0, 0, -1, -1],
                degreeSteps: [2, 3, 4, 5, 6, 0, 1])
        case 4:
            return TonicScaleInfo(
                name: "E", stepAccidentals: [1, 1, 0, 1, 1, 0, 0],
                degreeSteps: [2, 3, 4, 5, 6, 0, 1])
        case 5:
            return TonicScaleInfo(
                name: "F", stepAccidentals: [0, 0, 0, 0, 0, 0, -1],
                degreeSteps: [3, 4, 5, 6, 0, 1, 2])
        case 6:
            return TonicScaleInfo(
                name: "F#", stepAccidentals: [1, 1, 1, 1, 1, 1, 0],
                degreeSteps: [3, 4, 5, 6, 0, 1, 2])
        case 7:
            return TonicScaleInfo(
                name: "G", stepAccidentals: [0, 0, 0, 1, 0, 0, 0],
                degreeSteps: [4, 5, 6, 0, 1, 2, 3])
        case 8:
            return TonicScaleInfo(
                name: "Ab", stepAccidentals: [0, -1, -1, 0, 0, -1, -1],
                degreeSteps: [5, 6, 0, 1, 2, 3, 4])
        case 9:
            return TonicScaleInfo(
                name: "A", stepAccidentals: [1, 0, 0, 1, 1, 0, 0],
                degreeSteps: [5, 6, 0, 1, 2, 3, 4])
        case 10:
            return TonicScaleInfo(
                name: "Bb", stepAccidentals: [0, 0, -1, 0, 0, 0, -1],
                degreeSteps: [6, 0, 1, 2, 3, 4, 5])
        case 11:
            return TonicScaleInfo(
                name: "B", stepAccidentals: [1, 1, 0, 1, 1, 1, 0],
                degreeSteps: [6, 0, 1, 2, 3, 4, 5])
        default:
            return TonicScaleInfo(
                name: "C", stepAccidentals: [0, 0, 0, 0, 0, 0, 0],
                degreeSteps: [0, 1, 2, 3, 4, 5, 6])
        }
    }

    /// Spells a numbered-notation `Note` into its canonical diatonic step, alteration, and scientific octave.
    public static func spell(note: Note, keyOffset: Int) -> SpelledPitch {
        let info = tonicScaleInfo(forKeyOffset: keyOffset)
        let degIdx = max(0, min(6, note.degree.rawValue - 1))
        let stepIndex = info.degreeSteps[degIdx]
        let alter = info.stepAccidentals[stepIndex] + note.accidental.semitoneOffset
        let midiPitch = note.midiPitch(keyOffset: keyOffset)
        let naturalSemitone = naturalStepSemitones[stepIndex]
        let octave = (midiPitch - naturalSemitone - alter) / 12 - 1
        return SpelledPitch(
            stepIndex: stepIndex,
            step: stepNames[stepIndex],
            alter: alter,
            octave: octave,
            midiPitch: midiPitch
        )
    }

    /// Spells a `ChordRoot` (either movable-do degree or explicit letter root) into a `SpelledPitch`.
    public static func spell(
        chordRoot: ChordRoot,
        keyOffset: Int,
        defaultLetterOctave: Int = 3,
        defaultDegreeOctave: Int = 4
    ) -> SpelledPitch {
        if chordRoot.isScaleDegree {
            let note = Note(
                accidental: chordRoot.accidental,
                degree: chordRoot.degree,
                octave: chordRoot.octave + (defaultDegreeOctave - 4)
            )
            return spell(note: note, keyOffset: keyOffset)
        } else {
            let stepIndex = max(0, min(6, chordRoot.degree.rawValue - 1))
            let alter = chordRoot.accidental.semitoneOffset
            let octave = defaultLetterOctave + chordRoot.octave
            let naturalSemitone = naturalStepSemitones[stepIndex]
            let midiPitch = (octave + 1) * 12 + naturalSemitone + alter
            return SpelledPitch(
                stepIndex: stepIndex,
                step: stepNames[stepIndex],
                alter: alter,
                octave: octave,
                midiPitch: midiPitch
            )
        }
    }

    /// Spells all chord members (including optional slash bass) diatonically relative to the spelled chord root.
    public static func spellChordVoicing(_ chord: ChordSymbol, keyOffset: Int) -> [SpelledPitch] {
        let rootPitch = spell(
            chordRoot: chord.root,
            keyOffset: keyOffset,
            defaultLetterOctave: 3,
            defaultDegreeOctave: 4
        )
        let intervals = chord.quality.diatonicVoicingIntervals

        var pitches: [SpelledPitch] = intervals.map { interval in
            let totalSteps = rootPitch.stepIndex + interval.diatonicSteps
            let memberStepIndex = totalSteps % 7
            let memberOctave = rootPitch.octave + (totalSteps / 7)
            let memberMidi = rootPitch.midiPitch + interval.semitones
            let naturalMidi = (memberOctave + 1) * 12 + naturalStepSemitones[memberStepIndex]
            let memberAlter = memberMidi - naturalMidi
            return SpelledPitch(
                stepIndex: memberStepIndex,
                step: stepNames[memberStepIndex],
                alter: memberAlter,
                octave: memberOctave,
                midiPitch: memberMidi
            )
        }

        if let bass = chord.bass {
            let bassPitch = spell(
                chordRoot: bass,
                keyOffset: keyOffset,
                defaultLetterOctave: 2,
                defaultDegreeOctave: 2
            )
            if !pitches.contains(where: { $0.midiPitch == bassPitch.midiPitch }) {
                pitches.insert(bassPitch, at: 0)
            }
        }
        return pitches
    }

    /// Formats a `SpelledPitch` as a standard Dutch LilyPond pitch token (with Middle C = `c'`).
    public static func lilyPondPitch(_ spelled: SpelledPitch) -> String {
        let base = stepLowerNames[max(0, min(6, spelled.stepIndex))]
        let acc: String
        if spelled.alter == 1 {
            acc = "is"
        } else if spelled.alter >= 2 {
            acc = "isis"
        } else if spelled.alter == -1 {
            acc = "es"
        } else if spelled.alter <= -2 {
            acc = "eses"
        } else {
            acc = ""
        }
        let oct: String
        if spelled.octave > 3 {
            oct = String(repeating: "'", count: spelled.octave - 3)
        } else if spelled.octave < 3 {
            oct = String(repeating: ",", count: 3 - spelled.octave)
        } else {
            oct = ""
        }
        return "\(base)\(acc)\(oct)"
    }

    public static func keySignatureToFifths(_ key: String) -> Int {
        let trimmed = key.trimmingCharacters(in: .whitespaces).uppercased()
        switch trimmed {
        case "C": return 0
        case "G": return 1
        case "D": return 2
        case "A": return 3
        case "E": return 4
        case "B": return 5
        case "F#", "F'": return 6
        case "C#", "C'": return 7
        case "F": return -1
        case "BB", "B,": return -2
        case "EB", "E,": return -3
        case "AB", "A,": return -4
        case "A#", "A'": return -2
        case "DB", "D,": return -5
        case "GB", "G,": return -6
        case "CB", "C,": return -7
        default: return 0
        }
    }

    public static func parseKeyModeAndFifths(_ key: String) -> (fifths: Int, mode: String?) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        var root = trimmed
        var isMinor = false
        if root.hasSuffix("m") && !root.hasSuffix("maj") {
            isMinor = true
            root.removeLast()
        } else if root.lowercased().hasSuffix("minor") {
            isMinor = true
            root = String(root.dropLast(5)).trimmingCharacters(in: .whitespaces)
        } else if root.lowercased().hasSuffix("major") {
            root = String(root.dropLast(5)).trimmingCharacters(in: .whitespaces)
        }

        if isMinor {
            let normalizedRoot = root.uppercased()
            let minorFifths: Int =
                switch normalizedRoot {
                case "A": 0
                case "E": 1
                case "B": 2
                case "F#", "F'": 3
                case "C#", "C'": 4
                case "G#", "G'": 5
                case "D#", "D'": 6
                case "A#", "A'": 7
                case "D": -1
                case "G": -2
                case "C": -3
                case "F": -4
                case "BB", "B,": -5
                case "EB", "E,": -6
                case "AB", "A,": -7
                default:
                    if normalizedRoot == "BB" || normalizedRoot == "B,"
                        || normalizedRoot.hasPrefix("B")
                            && (normalizedRoot.hasSuffix("B") || normalizedRoot.hasSuffix(","))
                    {
                        -5
                    } else {
                        keySignatureToFifths(root) - 3
                    }
                }
            return (minorFifths, "minor")
        } else {
            return (keySignatureToFifths(root), "major")
        }
    }

    /// Returns the 7 default step alterations (C=0 .. B=6) implied by a written key signature string.
    public static func keySignatureStepAlters(forKey key: String) -> [Int] {
        let fifths = parseKeyModeAndFifths(key).fifths
        var alters = [0, 0, 0, 0, 0, 0, 0]
        if fifths > 0 {
            let sharpOrder = [3, 0, 4, 1, 5, 2, 6]  // F, C, G, D, A, E, B
            for i in 0..<min(7, fifths) {
                alters[sharpOrder[i]] = 1
            }
        } else if fifths < 0 {
            let flatOrder = [6, 2, 5, 1, 4, 0, 3]  // B, E, A, D, G, C, F
            for i in 0..<min(7, -fifths) {
                alters[flatOrder[i]] = -1
            }
        }
        return alters
    }

    public static func semitoneToDegreeAccidental(_ semitone: Int) -> (
        degree: ScaleDegree, accidental: Accidental
    ) {
        switch normalizedSemitone(semitone) {
        case 0: return (.c, .natural)
        case 1: return (.c, .sharp)
        case 2: return (.d, .natural)
        case 3: return (.d, .sharp)
        case 4: return (.e, .natural)
        case 5: return (.f, .natural)
        case 6: return (.f, .sharp)
        case 7: return (.g, .natural)
        case 8: return (.g, .sharp)
        case 9: return (.a, .natural)
        case 10: return (.b, .flat)
        case 11: return (.b, .natural)
        default: fatalError("Normalized semitone must be between 0 and 11")
        }
    }

    public static func accidentalSymbol(_ accidental: Accidental) -> String {
        accidental.tmdSymbol
    }
}

/// A musical note containing scale degree, accidental, and octave displacement.
///
/// > Note: Originally named `Node` in Aguai's C++ code (likely a typo for `Note`).
public struct Note: Equatable, Sendable {
    /// Accidental of the note.
    ///
    /// > Note: Originally named `sharpFalls` in Aguai's C++ code.
    public let accidental: Accidental

    /// Numbered musical notation scale degree (`1` to `7` representing Do
    /// through Ti). Invalid values cannot be represented in the AST.
    ///
    /// > Note: Originally named `name` (as `int`) in Aguai's C++ code.
    public let degree: ScaleDegree

    /// Octave displacement. Positive numbers shift octaves higher (syntax `^`),
    /// negative lower (syntax `_`).
    ///
    /// > Note: Originally named `octave` in Aguai's C++ code.
    public let octave: Int

    public init(accidental: Accidental = .natural, degree: ScaleDegree = .c, octave: Int = 0) {
        self.accidental = accidental
        self.degree = degree
        self.octave = octave
    }

    /// Source-compatible initializer for callers that use the TMD numeric form.
    /// Invalid degrees fail immediately instead of creating an invalid Note.
    public init(accidental: Accidental = .natural, degree: Int, octave: Int = 0) {
        precondition((1...7).contains(degree), "Scale degree must be between 1 and 7")
        self.init(accidental: accidental, degree: ScaleDegree(rawValue: degree)!, octave: octave)
    }

    /// Converts this numbered-notation note to MIDI pitch using Middle C = 60.
    public func midiPitch(keyOffset: Int) -> Int {
        60 + keyOffset + totalSemitones
    }

    /// Chromatic offset from C in the numbered-notation pitch space.
    public var totalSemitones: Int {
        degree.semitoneOffset + accidental.semitoneOffset + octave * 12
    }
}

/// The atomic musical unit, which can be a single note, a chord, or a tie/dash.
///
/// > Note: Originally implemented as `Unit` struct with `UnitType` enum in
/// > Aguai's C++ code.
public enum Unit: Equatable {
    /// A single note.
    ///
    /// > Note: Originally represented as `UnitType::Node` in Aguai's C++ code.
    case note(Note)

    /// A chord symbol enclosed in square brackets (e.g. `[Cmaj7]`, `[1]`,
    /// `[6m]`).
    ///
    /// > Note: Originally represented as `UnitType::Chord` in Aguai's C++ code.
    case chord(ChordSymbol)

    /// A tie or duration extension dash (syntax `-`).
    ///
    /// > Note: Originally represented as `UnitType::Copy` in Aguai's C++ code.
    case tie

    /// A rest. The source syntax is `0`; repeated dashes may extend it.
    case rest

    /// A percussion pattern using the original TMD character vocabulary.
    case percussion(String)

    /// A multi-note group (dyad, polyphonic cluster, or non-chord simultaneous notes) connected by `+` (e.g. `1+3`).
    case multiNote([Note])

    /// Transforms any pitched `Note` or `[Note]` inside this `Unit`, leaving chords, rests, ties, and percussion unchanged.
    public func mapNotes(_ transform: (Note) -> Note) -> Unit {
        switch self {
        case .note(let note):
            return .note(transform(note))
        case .multiNote(let notes):
            return .multiNote(notes.map(transform))
        default:
            return self
        }
    }
}

/// A rhythmic unit group or tuplet grouping.
///
/// Represents either a standalone unit or multiple units compressed into a
/// defined beat duration (e.g. `(7, 1)%(--)`).
///
/// > Note: Originally named `UnitGroup` in Aguai's C++ code.
public struct UnitGroup: Equatable {
    /// List of musical units (notes, chords, ties) in this group.
    ///
    /// > Note: Originally named `units` in Aguai's C++ code.
    public let units: [Unit]

    /// Duration in section base beats that this group spans (e.g. `%(--)` spans
    /// 2 base beats).
    ///
    /// > Note: Originally named `length` in Aguai's C++ code.
    public let length: Int

    public init(units: [Unit] = [], length: Int = 1) {
        self.units = units
        self.length = length
    }
}

/// The kind of local musical change occurring inside a section.
///
/// Standard Italian musical dynamic markings for volume and performance intensity.
public enum DynamicMark: String, Equatable, Hashable, Sendable, CaseIterable {
    case ppp
    case pp
    case p
    case mp
    case mf
    case f
    case ff
    case fff

    /// Default MIDI velocity corresponding to this dynamic level.
    public var defaultVelocity: UInt8 {
        switch self {
        case .ppp: return 20
        case .pp: return 35
        case .p: return 50
        case .mp: return 65
        case .mf: return 80
        case .f: return 95
        case .ff: return 110
        case .fff: return 125
        }
    }
}

/// A directive is stored together with its position in ``Section.directives``.
/// Its position is measured in the section's base units, so exporters can apply
/// the change at the correct point in the rendered timeline.
public enum SectionDirectiveKind: Equatable, Sendable {
    /// Sets the tempo to an absolute BPM value.
    case tempo(Double)

    /// Adds the given BPM delta to the current tempo.
    case relativeTempo(Double)

    /// Changes to an absolute key signature, such as `C` or `A'`.
    case absoluteKey(String)

    /// Transposes the current key by the given number of semitones.
    case relativeKey(Int)

    /// Explicitly declares an inline musical key/mode change (e.g. `Bm`, `F#m`, `C`).
    case explicitKey(String)

    /// Sets the playback dynamic level and engraved dynamic mark (e.g. `{p}`, `{f}`).
    case dynamics(DynamicMark)

    /// Forces fixed pitch (keyOffset = 0, immune to song-level order transpositions).
    case fixedPitch

    /// Changes the time signature, for example from 4/4 to 3/4.
    case timeSignature(Beat)
}

/// A positioned local change in a TMD section.
public struct SectionDirective: Equatable, Sendable {
    /// Position measured in section base units, before the directive.
    public let position: Int

    /// The tempo, key, or time-signature change to apply.
    public let kind: SectionDirectiveKind

    public init(position: Int, kind: SectionDirectiveKind) {
        self.position = position
        self.kind = kind
    }
}

/// A section or measure segment defining base note subdivision (e.g. `<16*>`)
/// and unit groups.
///
/// > Note: Originally named `Section` in Aguai's C++ code.
public struct Section: Equatable {
    /// Base subdivision note length (e.g. `4` for quarter-note grid, `16` for
    /// sixteenth-note grid `<16*>`).
    ///
    /// > Note: Originally named `nodeLength` in Aguai's C++ code (likely a typo
    /// > for `noteLength`).
    public let noteLength: Int

    /// Unit groups contained in this section.
    ///
    /// > Note: Originally named `unitGroups` in Aguai's C++ code.
    public let unitGroups: [UnitGroup]

    /// Absolute unit positions at which the source contained an explicit barline.
    public let barlinePositions: [Int]

    public let directives: [SectionDirective]

    public init(
        noteLength: Int = 4, unitGroups: [UnitGroup] = [], directives: [SectionDirective] = [],
        barlinePositions: [Int] = []
    ) {
        self.noteLength = noteLength
        self.unitGroups = unitGroups
        self.directives = directives
        self.barlinePositions = barlinePositions
    }

    /// Returns a copy of this section with all pitched `Note` / `[Note]` units transformed by `transform`.
    public func mapNotes(_ transform: (Note) -> Note) -> Section {
        let newGroups = unitGroups.map { group in
            UnitGroup(
                units: group.units.map { $0.mapNotes(transform) },
                length: group.length
            )
        }
        return Section(
            noteLength: noteLength,
            unitGroups: newGroups,
            directives: directives,
            barlinePositions: barlinePositions
        )
    }
}

extension Array where Element == Section {
    /// Returns a copy of all sections with every pitched `Note` / `[Note]` unit transformed by `transform`.
    public func mapNotes(_ transform: (Note) -> Note) -> [Section] {
        map { $0.mapNotes(transform) }
    }
}

/// Pitch interpretation for an entire assigned entry.
public enum EntryPitchMode: Equatable, Sendable {
    case transposing
    case fixed
}

/// A source entry, formatted as
/// `name:instrument@|start|{ ... }`.
///
/// An entry contains one section's musical material and its measure offset.
public struct Entry: Equatable {
    /// Entry section name (e.g. `intro`, `A`, `bridge`).
    ///
    /// > Note: Originally named `name` in Aguai's C++ code.
    public let name: String

    /// Assignment name (e.g. `Guitar`, `CHORD`, `Piano`). `nil` identifies a prototype.
    public let assignment: String?

    /// Canonical entry-wide pitch interpretation.
    public let pitchMode: EntryPitchMode

    /// Measure start offset (e.g. `@|0|` starts at measure 0, `@|+4|` starts at
    /// measure 4).
    ///
    /// > Note: Originally named `start` in Aguai's C++ code.
    public let start: Int

    /// Section list contained within this entry.
    ///
    /// > Note: Originally named `sections` in Aguai's C++ code.
    public let sections: [Section]

    /// Optional show-program time marker used by executable/non-musical blocks.
    public let executionTime: String?

    /// Raw body of a show-program block enclosed by triple quotes.
    public let showProgram: String?

    public init(
        name: String = "", assignment: String? = nil, pitchMode: EntryPitchMode = .transposing,
        start: Int = 0, sections: [Section] = [], executionTime: String? = nil,
        showProgram: String? = nil
    ) {
        self.name = name
        self.assignment = assignment
        self.pitchMode = pitchMode
        self.start = start
        self.sections = sections
        self.executionTime = executionTime
        self.showProgram = showProgram
    }
}

extension Entry {
    public var isPrototype: Bool { assignment == nil }
}

/// An S-Expression node representing symbols, numbers, and nested lists for macro composition.
public enum SExpr: Equatable, Hashable, Sendable, CustomStringConvertible {
    case symbol(String)
    case number(Int)
    case list([SExpr])

    public var description: String {
        switch self {
        case .symbol(let s):
            return s
        case .number(let n):
            return String(n)
        case .list(let items):
            return "(" + items.map(\.description).joined(separator: " ") + ")"
        }
    }

    /// Atomic identifier string when used as a prototype/theme argument (`symbol` or `number`), or `""` for lists.
    public var themeIdentifier: String {
        switch self {
        case .symbol(let s): return s
        case .number(let n): return String(n)
        case .list: return ""
        }
    }

    /// Recursively collects all `.symbol` strings inside this S-Expression into `set`.
    public func collectSymbols(into set: inout Set<String>) {
        switch self {
        case .symbol(let s):
            set.insert(s)
        case .number:
            break
        case .list(let items):
            for item in items {
                item.collectSymbols(into: &set)
            }
        }
    }
}

/// Playback order and modulation instructions directing song flow.
///
/// Example syntax: `-> intro -> A -> {?-3} -> C ->#`.
///
/// > Note: Originally named `OrderType` in Aguai's C++ code (where
/// > relative was typoed as `releative`).
public enum Playback: Equatable {
    /// Plays the paragraph matching the given name (e.g. `-> intro`, `-> A`).
    ///
    /// > Note: Originally named `OrderType::Name` in Aguai's C++ code.
    case name(String)

    /// Relative key modulation (e.g. `{?+3}` modulates up 3 semitones, `{?-3}`
    /// modulates down 3 semitones).
    ///
    /// > Note: Originally named `OrderType::Relative` in Aguai's C++ code
    /// > (previously typoed as `releative`).
    case relative(String)

    /// Absolute key modulation (e.g. `{?=C}`).
    ///
    /// > Note: Originally named `OrderType::Absolute` in Aguai's C++ code.
    case absolute(String)

    /// An S-Expression macro evaluation directive (e.g. `(canon Theme (V1 V2) 2)`).
    case macro(SExpr)
}

/// The complete TMD score sheet.
///
/// Contains song title, tempo, key signature, time signature, instrument
/// paragraphs, and arrangement playback orders.
///
/// > Note: Originally named `Sheet` in Aguai's C++ code.
public struct Sheet: Equatable {
    /// Song title (syntax enclosed in `** Title **`).
    ///
    /// > Note: Originally named `name` in Aguai's C++ code.
    public let name: String

    /// Playback tempo in BPM (syntax denoted by `!= 133`).
    ///
    /// > Note: Originally named `speed` in Aguai's C++ code.
    public let speed: Double

    /// Initial movable-do key signature base (syntax denoted by `?= A'`).
    ///
    /// > Note: Originally named `keySignature` in Aguai's C++ code.
    public let keySignature: KeySignature

    /// Optional explicit musical key/mode declaration (syntax denoted by `key= Bm` or `Key= Bm`).
    public let declaredKey: String?

    /// Time signature (syntax denoted by `<4/4>`).
    ///
    /// > Note: Originally named `beat` in Aguai's C++ code.
    public let beat: Beat

    /// Canonical source entries defined across the sheet.
    public let entries: [Entry]

    /// Canonical playback expressions sequencing the song.
    public let playback: [Playback]

    /// Song-level metadata such as lyrics, composer, and arranger credits.
    public let metadata: [String: String]

    public init(
        name: String = "",
        speed: Double = 0.0,
        keySignature: KeySignature = KeySignature(),
        declaredKey: String? = nil,
        beat: Beat = Beat(),
        entries: [Entry] = [],
        playback: [Playback] = [],
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.speed = speed
        self.keySignature = keySignature
        self.declaredKey = declaredKey
        self.beat = beat
        self.entries = entries
        self.playback = playback
        self.metadata = metadata
    }

    /// Source-compatible initializer accepting the original string spelling.
    public init(
        name: String = "",
        speed: Double = 0.0,
        keySignature: String,
        declaredKey: String? = nil,
        beat: Beat = Beat(),
        entries: [Entry] = [],
        playback: [Playback] = [],
        metadata: [String: String] = [:]
    ) {
        self.init(
            name: name, speed: speed, keySignature: KeySignature(string: keySignature),
            declaredKey: declaredKey, beat: beat, entries: entries, playback: playback,
            metadata: metadata)
    }

    /// Returns a sorted list of unique instrument names present across all paragraphs in the sheet.
    /// - Parameter fallbackToDefault: If true and no instruments exist, returns `["Piano"]`.
    public func distinctInstruments(fallbackToDefault: Bool = true) -> [String] {
        let distinct = Array(Set(entries.compactMap(\.assignment).filter { !$0.isEmpty })).sorted()
        if distinct.isEmpty && fallbackToDefault {
            return ["Piano"]
        }
        return distinct
    }

    public func distinctAssignments() -> [String] {
        var canonical: [String: String] = [:]
        for assignment in entries.compactMap(\.assignment) {
            canonical[assignment.lowercased(), default: assignment] = assignment
        }
        return canonical.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Resolves the target vocal instrument for singing-synthesis exporters (VSQ, VSQX, UST).
    /// Checks the requested instrument first, then matches common vocal keywords, falling back to the first instrument or `"Vocal"`.
    public func resolveVocalInstrument(requested: String? = nil) -> String {
        let distinct = distinctInstruments(fallbackToDefault: false)
        if let requested = requested, distinct.contains(requested) {
            return requested
        }

        let regex = try? NSRegularExpression(
            pattern: "vocal|voice|miku|utau|teto|sing|lead|melody", options: .caseInsensitive)
        if let matched = distinct.first(where: { inst in
            regex?.firstMatch(in: inst, range: NSRange(inst.startIndex..., in: inst)) != nil
        }) {
            return matched
        }

        return distinct.first ?? "Vocal"
    }

    /// Returns `true` if any entry assigned to `instrument` (case-insensitively) contains a `.percussion` unit.
    public func containsPercussionUnits(forInstrument instrument: String) -> Bool {
        entries
            .filter { ($0.assignment ?? "").caseInsensitiveCompare(instrument) == .orderedSame }
            .contains { entry in
                entry.sections.contains { section in
                    section.unitGroups.contains { group in
                        group.units.contains {
                            if case .percussion = $0 { return true }
                            return false
                        }
                    }
                }
            }
    }

    /// Returns `true` if `instrument` is a percussion track by name keyword or by containing `.percussion` units.
    public func isPercussionTrack(instrument: String) -> Bool {
        let lower = instrument.lowercased()
        let aliases = [
            "drum", "drums", "groove", "percussion", "perc", "beat", "drumkit", "kit",
            "cajon", "snare", "kick", "hihat",
        ]
        if aliases.contains(where: { lower.contains($0) }) {
            return true
        }
        return containsPercussionUnits(forInstrument: instrument)
    }

    /// Returns `true` if `instrument` conventionally uses bass clef (`F` clef on line 4).
    public static func isBassClefInstrument(_ instrument: String) -> Bool {
        let lower = instrument.lowercased()
        let bassKeywords = [
            "bass", "cello", "tuba", "contrabass", "bassoon", "trombone", "baritone", "timpani",
        ]
        return bassKeywords.contains { lower.contains($0) }
    }

    /// Returns `true` if `instrument` is a dedicated chord-symbol assignment (`CHORD` or `CHORDS`).
    public static func isChordSymbolTrack(_ instrument: String) -> Bool {
        let lower = instrument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "chord" || lower == "chords"
    }

    /// Expands all S-Expression macros on this sheet and returns the expanded sheet along with its ordered distinct instruments.
    public func preparedForExport(fallbackToDefault: Bool = false) -> (
        sheet: Sheet, instruments: [String]
    ) {
        let expanded = TmdMacroEvaluator.expandOrTrap(self)
        return (expanded, expanded.distinctInstruments(fallbackToDefault: fallbackToDefault))
    }

    /// Returns `playback` when explicitly specified, or falls back to playing each distinct entry section name in appearance order.
    public var effectivePlaybackOrders: [Playback] {
        guard playback.isEmpty else { return playback }
        var seen = Set<String>()
        var names: [String] = []
        for entry in entries where seen.insert(entry.name).inserted {
            names.append(entry.name)
        }
        return names.map(Playback.name)
    }
}

