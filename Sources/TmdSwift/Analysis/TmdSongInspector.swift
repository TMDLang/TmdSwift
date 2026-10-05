import Foundation

/// Pitch descriptor with MIDI note number, canonical note name (e.g. "C4", "A5"), and source section context.
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
public enum TmdSongInspector {

    /// Inspects a parsed TMD `Sheet` and produces an in-depth `TmdSongProfile`.
    public static func inspect(
        sheet inputSheet: Sheet,
        targetInstrument: String? = nil,
        locale: TmdLocale = .zhHant
    ) -> TmdSongProfile {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let title = sheet.name.isEmpty ? "Untitled" : sheet.name
        let initialTempo = sheet.speed > 0 ? sheet.speed : 120.0
        let initialKey = sheet.keySignature.description
        let initialMeter = "\(sheet.beat.count)/\(sheet.beat.noteValue)"

        // 1. Timing & Structure Profile
        let timelineDirectives = collectTimelineDirectives(sheet: sheet)
        let timingProfile = buildTimingProfile(sheet: sheet, timelineDirectives: timelineDirectives)

        // 2. Instrument & Pitch Ranges
        let instruments = sheet.distinctInstruments(fallbackToDefault: false)
        var instrumentRanges: [TmdPitchRangeProfile] = []

        for inst in instruments {
            if let profile = buildPitchProfile(
                for: inst, sheet: sheet, timingProfile: timingProfile,
                timelineDirectives: timelineDirectives)
            {
                instrumentRanges.append(profile)
            }
        }

        // 3. Vocal Range (picks target vocal instrument or specified target)
        let targetVocalInst: String
        if let targetInstrument, instruments.contains(targetInstrument) {
            targetVocalInst = targetInstrument
        } else {
            targetVocalInst = sheet.resolveVocalInstrument()
        }
        let vocalRange = instrumentRanges.first { $0.assignment == targetVocalInst }

        // 4. Harmony & Chord Profile
        let harmonyProfile = buildHarmonyProfile(sheet: sheet)

        // 5. Arrangement & Density Profile
        let densityProfile = buildDensityProfile(sheet: sheet)

        // 6. Tonality & Pitch-Class Profile
        let tonalityProfile = buildTonalityProfile(
            sheet: sheet, timingProfile: timingProfile, locale: locale)

        return TmdSongProfile(
            title: title,
            initialTempo: initialTempo,
            initialKey: initialKey,
            initialTimeSignature: initialMeter,
            timing: timingProfile,
            vocalRange: vocalRange,
            instrumentRanges: instrumentRanges,
            harmony: harmonyProfile,
            density: densityProfile,
            tonality: tonalityProfile,
            locale: locale
        )
    }

    private static func buildTimingProfile(
        sheet: Sheet, timelineDirectives: [PlaybackDirectiveEvent]
    ) -> TmdTimingProfile {
        TmdSongTimingAnalyzer.analyze(
            sheet: sheet, timelineDirectives: timelineDirectives)
    }

    private static func buildPitchProfile(
        for instrument: String,
        sheet: Sheet,
        timingProfile: TmdTimingProfile,
        timelineDirectives: [PlaybackDirectiveEvent]
    ) -> TmdPitchRangeProfile? {
        return TmdSongPitchRangeAnalyzer.analyze(
            instrument: instrument, sheet: sheet, timingProfile: timingProfile,
            timelineDirectives: timelineDirectives)
    }

    /// Evaluates pitch span difficulty based on semitones range.
    public static func evaluateDifficulty(spanSemitones: Int) -> TmdPitchRangeDifficulty {
        TmdSongPitchRangeAnalyzer.evaluateDifficulty(spanSemitones: spanSemitones)
    }

    /// Classical standard vocal ranges with amateur/pop margin and male octave displacement.
    public static func evaluateSuitableVoiceTypes(lowestMidi: Int, highestMidi: Int)
        -> [TmdVocalClassification]
    {
        TmdSongPitchRangeAnalyzer.evaluateSuitableVoiceTypes(
            lowestMidi: lowestMidi, highestMidi: highestMidi)
    }

    private static func buildHarmonyProfile(sheet: Sheet) -> TmdHarmonyProfile {
        TmdSongHarmonyAnalyzer.analyze(sheet: sheet)
    }

    private static func buildDensityProfile(sheet: Sheet) -> TmdArrangementDensityProfile {
        var sectionDict: [String: [String]] = [:]
        for p in sheet.entries {
            guard let assignment = p.assignment else { continue }
            sectionDict[p.name, default: []].append(assignment)
        }

        var sectionDensities: [TmdArrangementDensityProfile.SectionDensity] = []
        var maxTracks = 0

        for (secName, instList) in sectionDict {
            let uniqueInst = Array(Set(instList)).sorted()
            if uniqueInst.count > maxTracks {
                maxTracks = uniqueInst.count
            }
            sectionDensities.append(
                TmdArrangementDensityProfile.SectionDensity(
                    sectionName: secName,
                    trackCount: uniqueInst.count,
                    instruments: uniqueInst
                ))
        }

        return TmdArrangementDensityProfile(
            maxConcurrentTracks: maxTracks,
            sectionDensities: sectionDensities.sorted(by: { $0.sectionName < $1.sectionName })
        )
    }

    private static func formatNoteLocation(_ note: TmdNotePitchInfo) -> String {
        let mins = Int(note.timeSeconds) / 60
        let secs = Int(note.timeSeconds) % 60
        let timeStr = String(format: "%d:%02d", mins, secs)
        if !note.sectionName.isEmpty {
            return
                "[\(note.sectionName) #\(note.sectionOccurrence) @ m.\(note.measure), \(timeStr)]"
        } else {
            return "[@ m.\(note.measure), \(timeStr)]"
        }
    }

    /// Generates human-readable plain text / ASCII inspection report.
    public static func generateReport(_ profile: TmdSongProfile, locale: TmdLocale? = nil) -> String
    {
        let strings = TmdReportStrings(localizer: TmdLocalizer(locale: locale ?? profile.locale))
        let mins = Int(profile.timing.totalDurationSeconds) / 60
        let secs = Int(profile.timing.totalDurationSeconds) % 60
        let timeFormatted = String(
            format: "%d:%02d (%0.1fs)", mins, secs, profile.timing.totalDurationSeconds)

        var lines: [String] = []
        lines.append(
            "================================================================================")
        lines.append("📊 \(strings.songProfile): [ \(profile.title) ]")
        lines.append(
            "================================================================================")
        lines.append(
            "⏱  \(strings.duration):       \(timeFormatted), \(profile.timing.totalMeasures) \(strings.measuresTotal)"
        )
        lines.append(
            "🎼 \(strings.keyAndTempo):    \(strings.localizer.text(.playbackBase)) \(profile.initialKey), != \(profile.initialTempo) BPM, <\(profile.initialTimeSignature)>"
        )
        lines.append("   - \(strings.analysisScope)")

        if let vocal = profile.vocalRange {
            let octaves = String(format: "%0.1f", vocal.spanOctaves)
            lines.append(
                "🎤 Vocal Range:    \(vocal.lowestNote.noteName) (MIDI \(vocal.lowestNote.midiPitch)) – \(vocal.highestNote.noteName) (MIDI \(vocal.highestNote.midiPitch)) [Span: \(vocal.spanSemitones) semitones / \(octaves) octaves, Difficulty: \(vocal.difficulty.rawValue)]"
            )
            lines.append(
                "   - Lowest Note:  \(vocal.lowestNote.noteName) in \(formatNoteLocation(vocal.lowestNote))"
            )
            lines.append(
                "   - Highest Note: \(vocal.highestNote.noteName) in \(formatNoteLocation(vocal.highestNote))"
            )
            if !vocal.suitableVoiceTypes.isEmpty {
                let voiceNames = vocal.suitableVoiceTypes.map(\.rawValue).joined(separator: ", ")
                lines.append("   - Suitable For: \(voiceNames)")
            }
        }

        lines.append(
            "🏛  \(strings.structure):      "
                + profile.timing.sections.map {
                    "\($0.name) (\(String(format: "%0.1fs", $0.durationSeconds)))"
                }.joined(separator: " -> "))
        lines.append(
            "⚡ \(strings.density):        Peak \(profile.density.maxConcurrentTracks) \(strings.tracksConcurrently)"
        )

        if !profile.harmony.distinctChords.isEmpty {
            lines.append(
                "🎹 \(strings.harmony):        "
                    + profile.harmony.distinctChords.joined(separator: " "))
        }

        if let tonality = profile.tonality {
            let stabStr = tonality.globalInference.stability.rawValue.capitalized
            let corrStr = String(format: "%0.2f", tonality.globalInference.bestCorrelation)
            let diatonicPct = String(
                format: "%0.1f%%", tonality.globalPitchClasses.diatonicRatio * 100.0)
            let topPitches = tonality.globalPitchClasses.topPitchClasses.prefix(5).joined(
                separator: ", ")

            lines.append("🗝  \(strings.tonalityDiagnosis)       \(tonality.summaryText)")
            lines.append("   - \(strings.mood):    \(tonality.moodDescription)")
            lines.append("   - \(strings.modulationJourney):    \(tonality.modulationStory)")
            lines.append("   - \(strings.tonalCore):  \(topPitches)")
            let inferredLabel =
                "\(tonality.globalInference.tonic ?? "?") \(modeLabel(tonality.globalInference.mode, localizer: strings.localizer))"
            lines.append(
                "   - \(strings.tonalMetrics):    \(inferredLabel) [\(strings.correlation): \(corrStr), \(strings.stability): \(stabStr), \(strings.diatonicPurity): \(diatonicPct)]"
            )

            let candidateStr = tonality.globalInference.topCandidates.prefix(3).map {
                "\($0.tonic) \(modeLabel($0.mode, localizer: strings.localizer)) (\(String(format: "%0.2f", $0.correlation)))"
            }.joined(separator: ", ")
            if !candidateStr.isEmpty {
                lines.append("   - \(strings.candidateKeys): \(candidateStr)")
            }

            let pathStr = tonality.circleOfFifthsPath.map { "\($0 >= 0 ? "+" : "")\($0)" }.joined(
                separator: " -> ")
            if !pathStr.isEmpty {
                lines.append("   - \(strings.circleOfFifths):   \(pathStr)")
            }

            if !tonality.sections.isEmpty {
                lines.append("   - \(strings.sectionDetails):")
                for sec in tonality.sections {
                    let secCorr = String(format: "%0.2f", sec.inferredTonality.bestCorrelation)
                    let secDiatonic = String(
                        format: "%0.1f%%", sec.pitchClasses.diatonicRatio * 100.0)
                    let sectionLabel =
                        "\(sec.inferredTonality.tonic ?? "?") \(modeLabel(sec.inferredTonality.mode, localizer: strings.localizer))"
                    var secLine =
                        "     • [\(sec.sectionName) #\(sec.occurrenceIndex)]: \(sectionLabel) (r: \(secCorr), \(strings.diatonicPurity): \(secDiatonic)"
                    if !sec.nonDiatonicNotes.isEmpty {
                        secLine +=
                            ", \(strings.nonDiatonic): \(sec.nonDiatonicNotes.joined(separator: ", "))"
                    }
                    secLine += ")"
                    lines.append(secLine)
                }
            }

            // ASCII Visualizations
            lines.append("")
            lines.append("  [ Circle of Fifths Trajectory ]")
            lines.append(renderAsciiCircleOfFifths(tonality: tonality))
            lines.append("")
            lines.append("  [ Pitch Class Weight Distribution ]")
            lines.append(renderPitchClassHistogram(tonality: tonality))
        }

        lines.append(
            "--------------------------------------------------------------------------------")
        lines.append(strings.instrumentRanges)
        for inst in profile.instrumentRanges {
            let octaves = String(format: "%0.1f", inst.spanOctaves)
            lines.append(
                "  - \(inst.assignment.padding(toLength: 14, withPad: " ", startingAt: 0)): \(inst.lowestNote.noteName) – \(inst.highestNote.noteName) (\(inst.spanSemitones) semitones / \(octaves) octaves, \(inst.totalNotes) notes)"
            )
        }
        lines.append(
            "================================================================================")

        return lines.joined(separator: "\n")
    }

    // MARK: - Tonality & Key Profile Analysis Engine

    private static func buildTonalityProfile(
        sheet: Sheet,
        timingProfile: TmdTimingProfile,
        locale: TmdLocale
    ) -> TmdTonalityProfile {
        TmdSongTonalityAnalyzer.analyze(
            sheet: sheet, timingProfile: timingProfile, locale: locale)
    }

    private static func modeLabel(_ mode: TmdTonalityMode, localizer: TmdLocalizer) -> String {
        TmdSongTonalityAnalyzer.modeLabel(mode, localizer: localizer)
    }

    private static func collectTimelineDirectives(sheet: Sheet) -> [PlaybackDirectiveEvent] {
        let paragraphs = sheet.entries
        let instruments = Set(paragraphs.compactMap(\.assignment).filter { !$0.isEmpty })
        var directives: [PlaybackDirectiveEvent] = []
        for instrument in instruments {
            directives.append(
                contentsOf: TmdPlaybackRenderer.render(sheet: sheet, instrument: instrument)
                    .directives)
        }
        directives.sort(by: { $0.position < $1.position })

        var filtered: [PlaybackDirectiveEvent] = []
        for directive in directives {
            if let last = filtered.last {
                if last.position == directive.position
                    && last.state.tempo == directive.state.tempo
                    && last.state.timeSignature.count == directive.state.timeSignature.count
                    && last.state.timeSignature.noteValue == directive.state.timeSignature.noteValue
                {
                    continue
                }
            }
            filtered.append(directive)
        }
        return filtered
    }

    private static func measureDuration(for beat: Beat) -> Double {
        Double(max(1, beat.count)) * 4.0 / Double(max(1, beat.noteValue))
    }

    // MARK: - ASCII / Unicode Tonality Visualizers

    private static func renderAsciiCircleOfFifths(tonality: TmdTonalityProfile) -> String {
        // Collect active fifths steps from sections
        var activeSteps = Set<Int>()
        for sec in tonality.sections {
            activeSteps.insert(sec.fifthsPosition)
        }

        func node(_ name: String, _ step: Int) -> String {
            if activeSteps.contains(step) {
                return "[\(name.padding(toLength: 2, withPad: " ", startingAt: 0))]*"
            } else {
                return " \(name.padding(toLength: 2, withPad: " ", startingAt: 0)) "
            }
        }

        // 12-clock positions:
        //        0: C
        //  -1: F       +1: G
        // -2: Bb        +2: D
        // -3: Eb        +3: A
        //  -4: Ab      +4: E
        //   -5: Db    +5: B
        //       +6: F#
        let c = node("C", 0)
        let g = node("G", 1)
        let d = node("D", 2)
        let a = node("A", 3)
        let e = node("E", 4)
        let b = node("B", 5)
        let fs = node("F#", 6)
        let db = node("Db", -5)
        let ab = node("Ab", -4)
        let eb = node("Eb", -3)
        let bb = node("Bb", -2)
        let f = node("F", -1)

        var lines: [String] = []
        lines.append("              \(c)")
        lines.append("        \(f)         \(g)")
        lines.append("     \(bb)             \(d)")
        lines.append("     \(eb)             \(a)")
        lines.append("        \(ab)         \(e)")
        lines.append("           \(db)     \(b)")
        lines.append("              \(fs)")
        lines.append("     (* = active key center)")
        return lines.joined(separator: "\n")
    }

    private static func renderPitchClassHistogram(tonality: TmdTonalityProfile) -> String {
        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let weights = tonality.globalPitchClasses.weights
        let maxWeight = weights.max() ?? 1.0
        guard maxWeight > 0.0001 else { return "     (no pitch data)" }

        let barMaxWidth = 24
        var lines: [String] = []
        for pc in 0..<12 {
            let w = weights[pc]
            let ratio = w / maxWeight
            let barLen = Int(round(ratio * Double(barMaxWidth)))
            let bar = String(repeating: "█", count: barLen)
            let name = pitchClassNames[pc].padding(toLength: 3, withPad: " ", startingAt: 0)
            let pct = String(format: "%5.1f%%", (w / (weights.reduce(0.0, +) + 1e-9)) * 100.0)
            lines.append(
                "     \(name): \(bar.padding(toLength: barMaxWidth, withPad: " ", startingAt: 0)) \(pct)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
