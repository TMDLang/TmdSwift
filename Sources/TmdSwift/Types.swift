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
              let tonic = ScaleDegree(letter: first) else {
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
        switch accidental {
        case .natural: tonic.letter
        case .sharp: "\(tonic.letter)'"
        case .flat: "\(tonic.letter),"
        }
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

    public init(degree: ScaleDegree, accidental: Accidental = .natural, octave: Int = 0, isScaleDegree: Bool = false) {
        self.degree = degree
        self.accidental = accidental
        self.octave = octave
        self.isScaleDegree = isScaleDegree
    }

    public var description: String {
        let value = isScaleDegree
            ? String(degree.rawValue)
            : degree.letter
        let acc = switch accidental {
        case .natural: value
        case .sharp: "\(value)'"
        case .flat: "\(value),"
        }
        let oct = if octave > 0 {
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
}

/// A typed chord symbol with a finite common-quality vocabulary and extensibility.
public struct ChordSymbol: Equatable, Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let root: ChordRoot
    public let quality: ChordQuality

    public init(root: ChordRoot, quality: ChordQuality = .major) {
        self.root = root
        self.quality = quality
    }

    public init(string: String) {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(value)
        guard let first = chars.first else {
            self.init(root: ChordRoot(degree: .c), quality: .custom(""))
            return
        }
        let isDegree = ("1"..."7").contains(String(first))
        let degree: ScaleDegree
        let rootEnd: Int
        if isDegree, let intVal = Int(String(first)), let parsed = ScaleDegree(rawValue: intVal) {
            degree = parsed
            rootEnd = 1
        } else {
            guard let parsed = ScaleDegree(letter: first) else {
                self.init(root: ChordRoot(degree: .c), quality: .custom(value))
                return
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
        while suffixStart < chars.count && (chars[suffixStart] == "_" || chars[suffixStart] == "^") {
            if chars[suffixStart] == "^" {
                octave += 1
            } else if chars[suffixStart] == "_" {
                octave -= 1
            }
            suffixStart += 1
        }
        let suffix = String(chars.dropFirst(suffixStart))
        self.init(root: ChordRoot(degree: degree, accidental: accidental, octave: octave, isScaleDegree: isDegree), quality: Self.quality(for: suffix))
    }

    public init(stringLiteral value: String) {
        self.init(string: value)
    }

    public var description: String {
        let rootText = root.description
        let suffix = switch quality {
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
        return rootText + suffix
    }

    private static func quality(for suffix: String) -> ChordQuality {
        switch suffix.lowercased() {
        case "": return .major
        case "m": return .minor
        case "7": return .dominant7
        case "maj7": return .major7
        case "m7": return .minor7
        case "dim": return .diminished
        case "m7-5", "ø": return .halfDiminished
        case "aug", "+": return .augmented
        case "sus", "sus4": return .suspended
        case "5": return .power
        default: return .custom(suffix)
        }
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

/// Shared pitch-name mappings used by the text and binary exporters.
public enum PitchMapping {
    public static let musicXMLSteps = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
    public static let musicXMLAlters = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
    public static let lilyPondNames = ["c", "cis", "d", "dis", "e", "f", "fis", "g", "gis", "a", "ais", "b"]
    public static let abcUpperNames = ["C", "^C", "D", "^D", "E", "F", "^F", "G", "^G", "A", "^A", "B"]
    public static let abcLowerNames = ["c", "^c", "d", "^d", "e", "f", "^f", "g", "^g", "a", "^a", "b"]
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

    public let directives: [SectionDirective]

    public init(noteLength: Int = 4, unitGroups: [UnitGroup] = [], directives: [SectionDirective] = []) {
        self.noteLength = noteLength
        self.unitGroups = unitGroups
        self.directives = directives
    }
}

/// A multi-track voice or instrument paragraph, formatted as
/// `name:instrument@|start|{ ... }`.
///
/// Represents an instrument track's musical score within a specific song
/// section and its entry measure offset.
///
/// > Note: Originally named `Paragraph` in Aguai's C++ code.
public struct Paragraph: Equatable {
    /// Paragraph/section name (e.g. `intro`, `A`, `bridge`).
    ///
    /// > Note: Originally named `name` in Aguai's C++ code.
    public let name: String

    /// Instrument or track name (e.g. `Guitar`, `CHORD`, `Piano`).
    ///
    /// > Note: Originally named `instrument` in Aguai's C++ code.
    public let instrument: String

    /// Measure start offset (e.g. `@|0|` starts at measure 0, `@|+4|` starts at
    /// measure 4).
    ///
    /// > Note: Originally named `start` in Aguai's C++ code.
    public let start: Int

    /// Section list contained within this paragraph.
    ///
    /// > Note: Originally named `sections` in Aguai's C++ code.
    public let sections: [Section]

    /// Optional show-program time marker used by executable/non-musical blocks.
    public let executionTime: String?

    /// Raw body of a show-program block enclosed by triple quotes.
    public let showProgram: String?

    public init(name: String = "", instrument: String = "", start: Int = 0, sections: [Section] = [], executionTime: String? = nil, showProgram: String? = nil) {
        self.name = name
        self.instrument = instrument
        self.start = start
        self.sections = sections
        self.executionTime = executionTime
        self.showProgram = showProgram
    }
}

/// Playback order and modulation instructions directing song flow.
///
/// Example syntax: `-> intro -> A -> {?-3} -> C ->#`.
///
/// > Note: Originally named `Order` and `OrderType` in Aguai's C++ code (where
/// > relative was typoed as `releative`).
public enum Order: Equatable {
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

    /// Initial key signature (syntax denoted by `?= A'`).
    ///
    /// > Note: Originally named `keySignature` in Aguai's C++ code.
    public let keySignature: KeySignature

    /// Time signature (syntax denoted by `<4/4>`).
    ///
    /// > Note: Originally named `beat` in Aguai's C++ code.
    public let beat: Beat

    /// All instrument paragraphs defined across the sheet.
    ///
    /// > Note: Originally named `paragraphs` in Aguai's C++ code.
    public let paragraphs: [Paragraph]

    /// Song structure playback order sequence.
    ///
    /// > Note: Originally named `orders` in Aguai's C++ code.
    public let orders: [Order]

    /// Song-level metadata such as lyrics, composer, and arranger credits.
    public let metadata: [String: String]

    public init(
        name: String = "",
        speed: Double = 0.0,
        keySignature: KeySignature = KeySignature(),
        beat: Beat = Beat(),
        paragraphs: [Paragraph] = [],
        orders: [Order] = [],
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.speed = speed
        self.keySignature = keySignature
        self.beat = beat
        self.paragraphs = paragraphs
        self.orders = orders
        self.metadata = metadata
    }

    /// Source-compatible initializer accepting the original string spelling.
    public init(
        name: String = "",
        speed: Double = 0.0,
        keySignature: String,
        beat: Beat = Beat(),
        paragraphs: [Paragraph] = [],
        orders: [Order] = [],
        metadata: [String: String] = [:]
    ) {
        self.init(name: name, speed: speed, keySignature: KeySignature(string: keySignature), beat: beat, paragraphs: paragraphs, orders: orders, metadata: metadata)
    }
}
