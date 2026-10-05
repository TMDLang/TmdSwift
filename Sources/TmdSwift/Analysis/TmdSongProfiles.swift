import Foundation

public struct TmdNotePitchInfo: Equatable, Sendable, Codable {
    public let midiPitch: Int
    public let noteName: String
    public let sectionName: String
    public let timelinePosition: Double
    public let sectionOccurrence: Int
    public let measure: Int
    public let timeSeconds: Double

    public init(
        midiPitch: Int,
        noteName: String,
        sectionName: String,
        timelinePosition: Double,
        sectionOccurrence: Int = 1,
        measure: Int = 1,
        timeSeconds: Double = 0.0
    ) {
        self.midiPitch = midiPitch
        self.noteName = noteName
        self.sectionName = sectionName
        self.timelinePosition = timelinePosition
        self.sectionOccurrence = sectionOccurrence
        self.measure = measure
        self.timeSeconds = timeSeconds
    }

    /// Converts MIDI note number (0~127) to standard note name string (e.g. 60 -> "C4", 69 -> "A4").
    public static func name(for midiPitch: Int) -> String {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = (midiPitch / 12) - 1
        let noteIndex = (midiPitch % 12 + 12) % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
}

/// Qualitative rating of a vocal/instrument pitch span difficulty.
public enum TmdPitchRangeDifficulty: String, Equatable, Sendable, Codable {
    case easy
    case moderate
    case challenging
    case difficult
}

/// Standard classical/pop vocal voice classifications.
public enum TmdVocalClassification: String, Equatable, Sendable, Codable, CaseIterable {
    case soprano
    case mezzoSoprano = "mezzo-soprano"
    case contralto
    case tenor
    case baritone
    case bass
}

/// Vocal or instrument pitch range and tessitura summary.
public struct TmdPitchRangeProfile: Equatable, Sendable, Codable {
    public let instrument: String
    /// Canonical assignment represented by this pitch profile.
    public var assignment: String { instrument }
    public let lowestNote: TmdNotePitchInfo
    public let highestNote: TmdNotePitchInfo
    public let spanSemitones: Int
    public var spanOctaves: Double {
        Double(spanSemitones) / 12.0
    }
    public let totalNotes: Int
    public let averageMidiPitch: Double
    public let difficulty: TmdPitchRangeDifficulty
    public let suitableVoiceTypes: [TmdVocalClassification]

    public init(
        instrument: String,
        lowestNote: TmdNotePitchInfo,
        highestNote: TmdNotePitchInfo,
        spanSemitones: Int,
        totalNotes: Int,
        averageMidiPitch: Double,
        difficulty: TmdPitchRangeDifficulty = .easy,
        suitableVoiceTypes: [TmdVocalClassification] = []
    ) {
        self.instrument = instrument
        self.lowestNote = lowestNote
        self.highestNote = highestNote
        self.spanSemitones = spanSemitones
        self.totalNotes = totalNotes
        self.averageMidiPitch = averageMidiPitch
        self.difficulty = difficulty
        self.suitableVoiceTypes = suitableVoiceTypes
    }
}

/// Timing span descriptor for a section in the song's playback timeline.
public struct TmdSectionTimingProfile: Equatable, Sendable, Codable {
    public let name: String
    public let orderIndex: Int
    public let occurrenceIndex: Int
    public let startMeasure: Int
    public let startPositionQuarterNotes: Double
    public let durationQuarterNotes: Double
    public let startSeconds: Double
    public let durationSeconds: Double
    public let measures: Int
    public let keyOffset: Int
    public let tempo: Double

    public init(
        name: String,
        orderIndex: Int,
        occurrenceIndex: Int = 1,
        startMeasure: Int = 1,
        startPositionQuarterNotes: Double,
        durationQuarterNotes: Double,
        startSeconds: Double,
        durationSeconds: Double,
        measures: Int,
        keyOffset: Int,
        tempo: Double
    ) {
        self.name = name
        self.orderIndex = orderIndex
        self.occurrenceIndex = occurrenceIndex
        self.startMeasure = startMeasure
        self.startPositionQuarterNotes = startPositionQuarterNotes
        self.durationQuarterNotes = durationQuarterNotes
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.measures = measures
        self.keyOffset = keyOffset
        self.tempo = tempo
    }
}

/// Song playback timeline timing and duration breakdown.
public struct TmdTimingProfile: Equatable, Sendable, Codable {
    public let totalDurationSeconds: Double
    public let totalMeasures: Int
    public let sections: [TmdSectionTimingProfile]

    public init(
        totalDurationSeconds: Double, totalMeasures: Int, sections: [TmdSectionTimingProfile]
    ) {
        self.totalDurationSeconds = totalDurationSeconds
        self.totalMeasures = totalMeasures
        self.sections = sections
    }
}

/// Harmonic content and progression analysis.
public struct TmdHarmonyProfile: Equatable, Sendable, Codable {
    public let distinctChords: [String]
    public let chordCount: Int
    public let modulations: [String]

    public init(distinctChords: [String], chordCount: Int, modulations: [String]) {
        self.distinctChords = distinctChords
        self.chordCount = chordCount
        self.modulations = modulations
    }
}

/// Arrangement orchestration and concurrent track layering density.
public struct TmdArrangementDensityProfile: Equatable, Sendable, Codable {
    public struct SectionDensity: Equatable, Sendable, Codable {
        public let sectionName: String
        public let trackCount: Int
        public let instruments: [String]

        public init(sectionName: String, trackCount: Int, instruments: [String]) {
            self.sectionName = sectionName
            self.trackCount = trackCount
            self.instruments = instruments
        }
    }

    public let maxConcurrentTracks: Int
    public let sectionDensities: [SectionDensity]

    public init(maxConcurrentTracks: Int, sectionDensities: [SectionDensity]) {
        self.maxConcurrentTracks = maxConcurrentTracks
        self.sectionDensities = sectionDensities
    }
}

/// Distribution of the 12 chromatic pitch classes across a section or entire score.
public struct TmdPitchClassDistribution: Equatable, Sendable, Codable {
    /// Accumulated quarter-note duration weights for each pitch class (0: C, 1: C#, ..., 11: B).
    public let weights: [Double]
    /// Ratio of diatonic notes to total pitch weight (0.0 ~ 1.0).
    public let diatonicRatio: Double
    /// Ratio of non-diatonic (chromatic) notes to total pitch weight (0.0 ~ 1.0).
    public let chromaticRatio: Double
    /// Prominent pitch classes ordered by descending weight (e.g. ["C", "G", "E"]).
    public let topPitchClasses: [String]

    public init(
        weights: [Double], diatonicRatio: Double, chromaticRatio: Double, topPitchClasses: [String]
    ) {
        self.weights = weights
        self.diatonicRatio = diatonicRatio
        self.chromaticRatio = chromaticRatio
        self.topPitchClasses = topPitchClasses
    }
}

public enum TmdTonalityMode: String, Equatable, Sendable, Codable {
    case major, minor, modal, ambiguous, insufficient
}

public enum TmdScaleFamily: String, Equatable, Sendable, Codable {
    case major, naturalMinor, harmonicMinor, melodicMinor, modal, chromatic, unknown
}

public enum TmdKeyStability: String, Equatable, Sendable, Codable {
    case high
    case moderate
    case ambiguous
    case insufficient
}

public struct TmdTonalityCandidate: Equatable, Sendable, Codable {
    public let tonic: String
    public let mode: TmdTonalityMode
    public let scaleFamily: TmdScaleFamily
    public let correlation: Double

    public init(
        tonic: String, mode: TmdTonalityMode, scaleFamily: TmdScaleFamily, correlation: Double
    ) {
        self.tonic = tonic
        self.mode = mode
        self.scaleFamily = scaleFamily
        self.correlation = correlation
    }
}

public struct TmdTonalityEvidence: Equatable, Sendable, Codable {
    public let noteWeight: Double
    public let chordWeight: Double
}

public struct TmdTonalityInference: Equatable, Sendable, Codable {
    public let tonic: String?
    public let mode: TmdTonalityMode
    public let scaleFamily: TmdScaleFamily
    public let confidence: Double
    public let margin: Double
    public let stability: TmdKeyStability
    public let bestCorrelation: Double
    public let topCandidates: [TmdTonalityCandidate]
    public let evidence: TmdTonalityEvidence

    public init(
        tonic: String?, mode: TmdTonalityMode, scaleFamily: TmdScaleFamily,
        confidence: Double, margin: Double, stability: TmdKeyStability,
        bestCorrelation: Double, topCandidates: [TmdTonalityCandidate],
        evidence: TmdTonalityEvidence
    ) {
        self.tonic = tonic
        self.mode = mode
        self.scaleFamily = scaleFamily
        self.confidence = confidence
        self.margin = margin
        self.stability = stability
        self.bestCorrelation = bestCorrelation
        self.topCandidates = topCandidates
        self.evidence = evidence
    }
}

public struct TmdPlaybackContext: Equatable, Sendable, Codable {
    public let movableDoBase: String
    public let transpositionOffset: Int
    public let fixedPitch: Bool
}

public struct TmdTonalityTransition: Equatable, Sendable, Codable {
    public let sectionName: String
    public let tonic: String
    public let mode: TmdTonalityMode
    public let semitoneDiff: Int
    public let fifthsStepDiff: Int
}

/// Tonality and pitch-class distribution metrics for an individual section.
public struct TmdSectionTonalityProfile: Equatable, Sendable, Codable {
    public let sectionName: String
    public let occurrenceIndex: Int
    public let playbackContext: TmdPlaybackContext
    public let fifthsPosition: Int
    public let pitchClasses: TmdPitchClassDistribution
    public let inferredTonality: TmdTonalityInference
    public let nonDiatonicNotes: [String]

    public init(
        sectionName: String,
        occurrenceIndex: Int,
        playbackContext: TmdPlaybackContext,
        fifthsPosition: Int,
        pitchClasses: TmdPitchClassDistribution,
        inferredTonality: TmdTonalityInference,
        nonDiatonicNotes: [String]
    ) {
        self.sectionName = sectionName
        self.occurrenceIndex = occurrenceIndex
        self.playbackContext = playbackContext
        self.fifthsPosition = fifthsPosition
        self.pitchClasses = pitchClasses
        self.inferredTonality = inferredTonality
        self.nonDiatonicNotes = nonDiatonicNotes
    }
}

/// Holistic tonality profile across sections and the full song.
public struct TmdTonalityProfile: Equatable, Sendable, Codable {
    public let globalPitchClasses: TmdPitchClassDistribution
    public let globalInference: TmdTonalityInference
    public let playbackContext: TmdPlaybackContext
    public let playbackTranspositionPath: [Int]
    public let inferredModulationPath: [TmdTonalityTransition]
    public let circleOfFifthsPath: [Int]
    public let sections: [TmdSectionTonalityProfile]
    /// Human-friendly one-line producer diagnosis (e.g. "純淨自然大調，未轉調")
    public let summaryText: String
    /// Qualitative character/mood description (e.g. "陽光明朗，100% 自然音無調外音")
    public let moodDescription: String
    /// Story of key movements (e.g. "全曲維持單一調性" or "主歌 C 大調 ➔ 副歌升 2 半音至 D 大調")
    public let modulationStory: String
    /// Locale used when generating the human-readable narrative fields.
    public let locale: TmdLocale
    /// Explicit musical tonality declared with `key=`, separate from movable-do `?=`.
    public let declaredKey: String?

    public init(
        globalPitchClasses: TmdPitchClassDistribution,
        globalInference: TmdTonalityInference,
        playbackContext: TmdPlaybackContext,
        playbackTranspositionPath: [Int],
        inferredModulationPath: [TmdTonalityTransition],
        circleOfFifthsPath: [Int],
        sections: [TmdSectionTonalityProfile],
        summaryText: String = "",
        moodDescription: String = "",
        modulationStory: String = "",
        locale: TmdLocale = .zhHant,
        declaredKey: String? = nil
    ) {
        self.globalPitchClasses = globalPitchClasses
        self.globalInference = globalInference
        self.playbackContext = playbackContext
        self.playbackTranspositionPath = playbackTranspositionPath
        self.inferredModulationPath = inferredModulationPath
        self.circleOfFifthsPath = circleOfFifthsPath
        self.sections = sections
        self.summaryText = summaryText
        self.moodDescription = moodDescription
        self.modulationStory = modulationStory
        self.locale = locale
        self.declaredKey = declaredKey
    }

    private enum CodingKeys: String, CodingKey {
        case globalPitchClasses, globalInference, playbackContext, playbackTranspositionPath,
            inferredModulationPath, circleOfFifthsPath, sections
        case summaryText, moodDescription, modulationStory, locale, declaredKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            globalPitchClasses: try container.decode(
                TmdPitchClassDistribution.self, forKey: .globalPitchClasses),
            globalInference: try container.decode(
                TmdTonalityInference.self, forKey: .globalInference),
            playbackContext: try container.decode(
                TmdPlaybackContext.self, forKey: .playbackContext),
            playbackTranspositionPath: try container.decode(
                [Int].self, forKey: .playbackTranspositionPath),
            inferredModulationPath: try container.decode(
                [TmdTonalityTransition].self, forKey: .inferredModulationPath),
            circleOfFifthsPath: try container.decode([Int].self, forKey: .circleOfFifthsPath),
            sections: try container.decode([TmdSectionTonalityProfile].self, forKey: .sections),
            summaryText: try container.decode(String.self, forKey: .summaryText),
            moodDescription: try container.decode(String.self, forKey: .moodDescription),
            modulationStory: try container.decode(String.self, forKey: .modulationStory),
            locale: try container.decodeIfPresent(TmdLocale.self, forKey: .locale) ?? .zhHant,
            declaredKey: try container.decodeIfPresent(String.self, forKey: .declaredKey)
        )
    }
}

/// Complete structural, vocal range, harmonic, and temporal profile of a TMD score.
public struct TmdSongProfile: Equatable, Sendable, Codable {
    public let title: String
    public let initialTempo: Double
    public let initialKey: String
    public let initialTimeSignature: String
    public let timing: TmdTimingProfile
    public let vocalRange: TmdPitchRangeProfile?
    public let instrumentRanges: [TmdPitchRangeProfile]
    public let harmony: TmdHarmonyProfile
    public let density: TmdArrangementDensityProfile
    public let tonality: TmdTonalityProfile?
    /// Locale used for localized narrative fields in this profile.
    public let locale: TmdLocale

    public init(
        title: String,
        initialTempo: Double,
        initialKey: String,
        initialTimeSignature: String,
        timing: TmdTimingProfile,
        vocalRange: TmdPitchRangeProfile?,
        instrumentRanges: [TmdPitchRangeProfile],
        harmony: TmdHarmonyProfile,
        density: TmdArrangementDensityProfile,
        tonality: TmdTonalityProfile? = nil,
        locale: TmdLocale = .zhHant
    ) {
        self.title = title
        self.initialTempo = initialTempo
        self.initialKey = initialKey
        self.initialTimeSignature = initialTimeSignature
        self.timing = timing
        self.vocalRange = vocalRange
        self.instrumentRanges = instrumentRanges
        self.harmony = harmony
        self.density = density
        self.tonality = tonality
        self.locale = locale
    }

    private enum CodingKeys: String, CodingKey {
        case title, initialTempo, initialKey, initialTimeSignature, timing
        case vocalRange, instrumentRanges, harmony, density, tonality, locale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try container.decode(String.self, forKey: .title),
            initialTempo: try container.decode(Double.self, forKey: .initialTempo),
            initialKey: try container.decode(String.self, forKey: .initialKey),
            initialTimeSignature: try container.decode(String.self, forKey: .initialTimeSignature),
            timing: try container.decode(TmdTimingProfile.self, forKey: .timing),
            vocalRange: try container.decodeIfPresent(
                TmdPitchRangeProfile.self, forKey: .vocalRange),
            instrumentRanges: try container.decode(
                [TmdPitchRangeProfile].self, forKey: .instrumentRanges),
            harmony: try container.decode(TmdHarmonyProfile.self, forKey: .harmony),
            density: try container.decode(TmdArrangementDensityProfile.self, forKey: .density),
            tonality: try container.decodeIfPresent(TmdTonalityProfile.self, forKey: .tonality),
            locale: try container.decodeIfPresent(TmdLocale.self, forKey: .locale) ?? .zhHant
        )
    }
}

/// Inspector engine extracting holistic musical metrics, vocal tessitura, and arrangement profiles from a TMD Sheet.
