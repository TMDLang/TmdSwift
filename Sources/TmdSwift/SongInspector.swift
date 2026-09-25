import Foundation

/// Pitch descriptor with MIDI note number, canonical note name (e.g. "C4", "A5"), and source section context.
public struct TMDNotePitchInfo: Equatable, Sendable, Codable {
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
public enum TMDPitchRangeDifficulty: String, Equatable, Sendable, Codable {
    case easy
    case moderate
    case challenging
    case difficult
}

/// Standard classical/pop vocal voice classifications.
public enum TMDVocalClassification: String, Equatable, Sendable, Codable, CaseIterable {
    case soprano
    case mezzoSoprano = "mezzo-soprano"
    case contralto
    case tenor
    case baritone
    case bass
}

/// Vocal or instrument pitch range and tessitura summary.
public struct TMDPitchRangeProfile: Equatable, Sendable, Codable {
    public let instrument: String
    public let lowestNote: TMDNotePitchInfo
    public let highestNote: TMDNotePitchInfo
    public let spanSemitones: Int
    public var spanOctaves: Double {
        Double(spanSemitones) / 12.0
    }
    public let totalNotes: Int
    public let averageMidiPitch: Double
    public let difficulty: TMDPitchRangeDifficulty
    public let suitableVoiceTypes: [TMDVocalClassification]

    public init(
        instrument: String,
        lowestNote: TMDNotePitchInfo,
        highestNote: TMDNotePitchInfo,
        spanSemitones: Int,
        totalNotes: Int,
        averageMidiPitch: Double,
        difficulty: TMDPitchRangeDifficulty = .easy,
        suitableVoiceTypes: [TMDVocalClassification] = []
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
public struct TMDSectionTimingProfile: Equatable, Sendable, Codable {
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
public struct TMDTimingProfile: Equatable, Sendable, Codable {
    public let totalDurationSeconds: Double
    public let totalMeasures: Int
    public let sections: [TMDSectionTimingProfile]

    public init(totalDurationSeconds: Double, totalMeasures: Int, sections: [TMDSectionTimingProfile]) {
        self.totalDurationSeconds = totalDurationSeconds
        self.totalMeasures = totalMeasures
        self.sections = sections
    }
}

/// Harmonic content and progression analysis.
public struct TMDHarmonyProfile: Equatable, Sendable, Codable {
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
public struct TMDArrangementDensityProfile: Equatable, Sendable, Codable {
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
public struct TMDPitchClassDistribution: Equatable, Sendable, Codable {
    /// Accumulated quarter-note duration weights for each pitch class (0: C, 1: C#, ..., 11: B).
    public let weights: [Double]
    /// Ratio of diatonic notes to total pitch weight (0.0 ~ 1.0).
    public let diatonicRatio: Double
    /// Ratio of non-diatonic (chromatic) notes to total pitch weight (0.0 ~ 1.0).
    public let chromaticRatio: Double
    /// Prominent pitch classes ordered by descending weight (e.g. ["C", "G", "E"]).
    public let topPitchClasses: [String]

    public init(weights: [Double], diatonicRatio: Double, chromaticRatio: Double, topPitchClasses: [String]) {
        self.weights = weights
        self.diatonicRatio = diatonicRatio
        self.chromaticRatio = chromaticRatio
        self.topPitchClasses = topPitchClasses
    }
}

/// A candidate key match and its Pearson correlation score from K-S analysis.
public struct TMDKeyFitCandidate: Equatable, Sendable, Codable {
    public let keyName: String
    public let correlation: Double

    public init(keyName: String, correlation: Double) {
        self.keyName = keyName
        self.correlation = correlation
    }
}

/// Qualitative stability assessment of tonality.
public enum TMDKeyStability: String, Equatable, Sendable, Codable {
    case high
    case moderate
    case ambiguous
}

/// Key correlation and best-fit prediction results from Krumhansl-Schmuckler analysis.
public struct TMDKeyCorrelation: Equatable, Sendable, Codable {
    public let declaredKey: String
    public let declaredKeyCorrelation: Double
    public let topCandidateKeys: [TMDKeyFitCandidate]
    public let stability: TMDKeyStability

    public init(
        declaredKey: String,
        declaredKeyCorrelation: Double,
        topCandidateKeys: [TMDKeyFitCandidate],
        stability: TMDKeyStability
    ) {
        self.declaredKey = declaredKey
        self.declaredKeyCorrelation = declaredKeyCorrelation
        self.topCandidateKeys = topCandidateKeys
        self.stability = stability
    }
}

/// Tonality and pitch-class distribution metrics for an individual section.
public struct TMDSectionTonalityProfile: Equatable, Sendable, Codable {
    public let sectionName: String
    public let occurrenceIndex: Int
    public let declaredKey: String
    public let keyOffset: Int
    public let fifthsPosition: Int
    public let pitchClasses: TMDPitchClassDistribution
    public let correlation: TMDKeyCorrelation
    public let nonDiatonicNotes: [String]

    public init(
        sectionName: String,
        occurrenceIndex: Int,
        declaredKey: String,
        keyOffset: Int,
        fifthsPosition: Int,
        pitchClasses: TMDPitchClassDistribution,
        correlation: TMDKeyCorrelation,
        nonDiatonicNotes: [String]
    ) {
        self.sectionName = sectionName
        self.occurrenceIndex = occurrenceIndex
        self.declaredKey = declaredKey
        self.keyOffset = keyOffset
        self.fifthsPosition = fifthsPosition
        self.pitchClasses = pitchClasses
        self.correlation = correlation
        self.nonDiatonicNotes = nonDiatonicNotes
    }
}

/// Holistic tonality profile across sections and the full song.
public struct TMDTonalityProfile: Equatable, Sendable, Codable {
    public let globalPitchClasses: TMDPitchClassDistribution
    public let globalCorrelation: TMDKeyCorrelation
    public let circleOfFifthsPath: [Int]
    public let sections: [TMDSectionTonalityProfile]
    /// Human-friendly one-line producer diagnosis (e.g. "純淨自然大調，未轉調")
    public let summaryText: String
    /// Qualitative character/mood description (e.g. "陽光明朗，100% 自然音無調外音")
    public let moodDescription: String
    /// Story of key movements (e.g. "全曲維持單一調性" or "主歌 C 大調 ➔ 副歌升 2 半音至 D 大調")
    public let modulationStory: String

    public init(
        globalPitchClasses: TMDPitchClassDistribution,
        globalCorrelation: TMDKeyCorrelation,
        circleOfFifthsPath: [Int],
        sections: [TMDSectionTonalityProfile],
        summaryText: String = "",
        moodDescription: String = "",
        modulationStory: String = ""
    ) {
        self.globalPitchClasses = globalPitchClasses
        self.globalCorrelation = globalCorrelation
        self.circleOfFifthsPath = circleOfFifthsPath
        self.sections = sections
        self.summaryText = summaryText
        self.moodDescription = moodDescription
        self.modulationStory = modulationStory
    }
}

/// Complete structural, vocal range, harmonic, and temporal profile of a TMD score.
public struct TMDSongProfile: Equatable, Sendable, Codable {
    public let title: String
    public let initialTempo: Double
    public let initialKey: String
    public let initialTimeSignature: String
    public let timing: TMDTimingProfile
    public let vocalRange: TMDPitchRangeProfile?
    public let instrumentRanges: [TMDPitchRangeProfile]
    public let harmony: TMDHarmonyProfile
    public let density: TMDArrangementDensityProfile
    public let tonality: TMDTonalityProfile?

    public init(
        title: String,
        initialTempo: Double,
        initialKey: String,
        initialTimeSignature: String,
        timing: TMDTimingProfile,
        vocalRange: TMDPitchRangeProfile?,
        instrumentRanges: [TMDPitchRangeProfile],
        harmony: TMDHarmonyProfile,
        density: TMDArrangementDensityProfile,
        tonality: TMDTonalityProfile? = nil
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
    }
}

/// Inspector engine extracting holistic musical metrics, vocal tessitura, and arrangement profiles from a TMD Sheet.
public enum TMDSongInspector {

    /// Inspects a parsed TMD `Sheet` and produces an in-depth `TMDSongProfile`.
    public static func inspect(sheet inputSheet: Sheet, targetInstrument: String? = nil) -> TMDSongProfile {
        let sheet = TMDMacroEvaluator.expand(inputSheet)
        let title = sheet.name.isEmpty ? "Untitled" : sheet.name
        let initialTempo = sheet.speed > 0 ? sheet.speed : 120.0
        let initialKey = sheet.keySignature.description
        let initialMeter = "\(sheet.beat.count)/\(sheet.beat.noteValue)"

        // 1. Timing & Structure Profile
        let timelineDirectives = collectTimelineDirectives(sheet: sheet)
        let timingProfile = buildTimingProfile(sheet: sheet, timelineDirectives: timelineDirectives)

        // 2. Instrument & Pitch Ranges
        let instruments = sheet.distinctInstruments(fallbackToDefault: false)
        var instrumentRanges: [TMDPitchRangeProfile] = []

        for inst in instruments {
            if let profile = buildPitchProfile(for: inst, sheet: sheet, timingProfile: timingProfile, timelineDirectives: timelineDirectives) {
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
        let vocalRange = instrumentRanges.first { $0.instrument == targetVocalInst }

        // 4. Harmony & Chord Profile
        let harmonyProfile = buildHarmonyProfile(sheet: sheet)

        // 5. Arrangement & Density Profile
        let densityProfile = buildDensityProfile(sheet: sheet)

        // 6. Tonality & Pitch-Class Profile
        let tonalityProfile = buildTonalityProfile(sheet: sheet, timingProfile: timingProfile)

        return TMDSongProfile(
            title: title,
            initialTempo: initialTempo,
            initialKey: initialKey,
            initialTimeSignature: initialMeter,
            timing: timingProfile,
            vocalRange: vocalRange,
            instrumentRanges: instrumentRanges,
            harmony: harmonyProfile,
            density: densityProfile,
            tonality: tonalityProfile
        )
    }

    private static func buildTimingProfile(sheet: Sheet, timelineDirectives: [PlaybackDirectiveEvent]) -> TMDTimingProfile {
        let orders = sheet.orders.isEmpty
            ? sheet.paragraphs.map(\.name).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.map(Order.name)
            : sheet.orders

        var state = PlaybackState(
            tempo: sheet.speed > 0 ? sheet.speed : 120.0,
            keyOffset: sheet.keySignature.semitoneOffset,
            timeSignature: sheet.beat
        )

        var sections: [TMDSectionTimingProfile] = []
        var currentQuarterPosition = 0.0
        var currentSeconds = 0.0
        var currentMeasure = 1
        var totalMeasures = 0
        var sectionOccurrences: [String: Int] = [:]

        for (idx, order) in orders.enumerated() {
            switch order {
            case .relative(let val):
                if let delta = Int(val.replacingOccurrences(of: "+", with: "")) {
                    state = PlaybackState(tempo: state.tempo, keyOffset: state.keyOffset + delta, timeSignature: state.timeSignature)
                }
            case .absolute(let val):
                let offset = KeySignature(string: val).semitoneOffset
                state = PlaybackState(tempo: state.tempo, keyOffset: offset, timeSignature: state.timeSignature)
            case .name(let secName):
                let durQuarterNotes = TMDPlaybackRenderer.duration(of: secName, in: sheet)
                let startPosition = currentQuarterPosition
                let endPosition = startPosition + durQuarterNotes
                var cursor = startPosition
                var tempo = state.tempo
                var meter = state.timeSignature
                var secDurationSeconds = 0.0
                var measureCount = 0.0

                for directive in timelineDirectives {
                    if directive.position < startPosition || directive.position >= endPosition { continue }
                    if directive.position > cursor {
                        let segment = directive.position - cursor
                        secDurationSeconds += segment * 60.0 / tempo
                        measureCount += segment / measureDuration(for: meter)
                        cursor = directive.position
                    }
                    tempo = directive.state.tempo
                    meter = directive.state.timeSignature
                }

                if endPosition > cursor {
                    let segment = endPosition - cursor
                    secDurationSeconds += segment * 60.0 / tempo
                    measureCount += segment / measureDuration(for: meter)
                }

                let secMeasures = max(1, Int(round(measureCount)))

                let occurrence = sectionOccurrences[secName, default: 0] + 1
                sectionOccurrences[secName] = occurrence

                let secProfile = TMDSectionTimingProfile(
                    name: secName,
                    orderIndex: idx,
                    occurrenceIndex: occurrence,
                    startMeasure: currentMeasure,
                    startPositionQuarterNotes: currentQuarterPosition,
                    durationQuarterNotes: durQuarterNotes,
                    startSeconds: currentSeconds,
                    durationSeconds: secDurationSeconds,
                    measures: secMeasures,
                    keyOffset: state.keyOffset,
                    tempo: state.tempo
                )
                sections.append(secProfile)

                currentQuarterPosition += durQuarterNotes
                currentSeconds += secDurationSeconds
                currentMeasure += secMeasures
                totalMeasures += secMeasures
                state = PlaybackState(tempo: tempo, keyOffset: state.keyOffset, timeSignature: meter)
            case .macro:
                // S-expression macros are desugared by TMDMacroEvaluator before inspection
                break
            }
        }

        return TMDTimingProfile(
            totalDurationSeconds: currentSeconds,
            totalMeasures: totalMeasures,
            sections: sections
        )
    }

    private static func buildPitchProfile(
        for instrument: String,
        sheet: Sheet,
        timingProfile: TMDTimingProfile,
        timelineDirectives: [PlaybackDirectiveEvent]
    ) -> TMDPitchRangeProfile? {
        let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: instrument)

        struct NoteHit {
            let midi: Int
            let name: String
            let pos: Double
            let sectionName: String
            let sectionOccurrence: Int
            let measure: Int
            let timeSeconds: Double
        }

        var hits: [NoteHit] = []

        for event in timeline.events {
            guard case .note(let note) = event.content else { continue }
            // Note MIDI pitch calculation:
            // 60 (Middle C) + keyOffset + degreeOffset + accidental + octave
            var pitch = 60 + event.state.keyOffset + note.degree.semitoneOffset
            switch note.accidental {
            case .sharp: pitch += 1
            case .flat: pitch -= 1
            case .natural: break
            }
            pitch += note.octave * 12

            let noteName = TMDNotePitchInfo.name(for: pitch)
            let matchedSection = timingProfile.sections.first {
                event.position >= $0.startPositionQuarterNotes && event.position < ($0.startPositionQuarterNotes + $0.durationQuarterNotes + 0.001)
            }

            let sectionName = matchedSection?.name ?? ""
            let sectionOccurrence = matchedSection?.occurrenceIndex ?? 1
            let measure: Int
            let timeSeconds: Double
            if let sec = matchedSection {
                let position = max(sec.startPositionQuarterNotes, event.position)
                var cursor = sec.startPositionQuarterNotes
                var tempo = sec.tempo
                var meter = event.state.timeSignature
                var elapsedSeconds = 0.0
                var elapsedMeasures = 0.0

                for directive in timelineDirectives {
                    if directive.position <= cursor || directive.position >= position { continue }
                    let segment = directive.position - cursor
                    elapsedSeconds += segment * 60.0 / tempo
                    elapsedMeasures += segment / measureDuration(for: meter)
                    cursor = directive.position
                    tempo = directive.state.tempo
                    meter = directive.state.timeSignature
                }

                if position > cursor {
                    let segment = position - cursor
                    elapsedSeconds += segment * 60.0 / tempo
                    elapsedMeasures += segment / measureDuration(for: meter)
                }

                measure = sec.startMeasure + Int(floor(elapsedMeasures + 1e-9))
                timeSeconds = sec.startSeconds + elapsedSeconds
            } else {
                let nominalMeasureDur = measureDuration(for: event.state.timeSignature)
                measure = 1 + Int(floor(event.position / nominalMeasureDur))
                timeSeconds = event.position / (event.state.tempo / 60.0)
            }

            hits.append(NoteHit(
                midi: pitch,
                name: noteName,
                pos: event.position,
                sectionName: sectionName,
                sectionOccurrence: sectionOccurrence,
                measure: measure,
                timeSeconds: timeSeconds
            ))
        }

        guard !hits.isEmpty else { return nil }

        let lowest = hits.min(by: { $0.midi < $1.midi })!
        let highest = hits.max(by: { $0.midi < $1.midi })!
        let sumPitch = hits.reduce(0) { $0 + $1.midi }
        let avgPitch = Double(sumPitch) / Double(hits.count)

        let spanSemitones = highest.midi - lowest.midi
        let difficulty = evaluateDifficulty(spanSemitones: spanSemitones)
        let suitable = evaluateSuitableVoiceTypes(lowestMidi: lowest.midi, highestMidi: highest.midi)

        return TMDPitchRangeProfile(
            instrument: instrument,
            lowestNote: TMDNotePitchInfo(
                midiPitch: lowest.midi,
                noteName: lowest.name,
                sectionName: lowest.sectionName,
                timelinePosition: lowest.pos,
                sectionOccurrence: lowest.sectionOccurrence,
                measure: lowest.measure,
                timeSeconds: lowest.timeSeconds
            ),
            highestNote: TMDNotePitchInfo(
                midiPitch: highest.midi,
                noteName: highest.name,
                sectionName: highest.sectionName,
                timelinePosition: highest.pos,
                sectionOccurrence: highest.sectionOccurrence,
                measure: highest.measure,
                timeSeconds: highest.timeSeconds
            ),
            spanSemitones: spanSemitones,
            totalNotes: hits.count,
            averageMidiPitch: avgPitch,
            difficulty: difficulty,
            suitableVoiceTypes: suitable
        )
    }

    /// Evaluates pitch span difficulty based on semitones range.
    public static func evaluateDifficulty(spanSemitones: Int) -> TMDPitchRangeDifficulty {
        if spanSemitones <= 12 { return .easy }
        if spanSemitones <= 16 { return .moderate }
        if spanSemitones <= 20 { return .challenging }
        return .difficult
    }

    /// Classical standard vocal ranges with amateur/pop margin and male octave displacement.
    public static func evaluateSuitableVoiceTypes(lowestMidi: Int, highestMidi: Int) -> [TMDVocalClassification] {
        let voiceRanges: [(type: TMDVocalClassification, min: Int, max: Int)] = [
            (.soprano, 57, 86),       // A3 - D6
            (.mezzoSoprano, 53, 81),  // F3 - A5
            (.contralto, 50, 77),     // D3 - F5
            (.tenor, 45, 74),         // A2 - D5
            (.baritone, 41, 69),      // F2 - A4
            (.bass, 38, 65)           // D2 - F4
        ]

        var suitable: [TMDVocalClassification] = []

        // Direct range check
        for vr in voiceRanges {
            if lowestMidi >= vr.min && highestMidi <= vr.max {
                suitable.append(vr.type)
            }
        }

        // Check standard male octave transpose (melodies written in treble clef C4-C5 sung C3-C4 by males)
        let transposedLow = lowestMidi - 12
        let transposedHigh = highestMidi - 12
        let maleVoiceTypes: Set<TMDVocalClassification> = [.tenor, .baritone, .bass]
        for vr in voiceRanges {
            if maleVoiceTypes.contains(vr.type) && !suitable.contains(vr.type) {
                if transposedLow >= vr.min && transposedHigh <= vr.max {
                    suitable.append(vr.type)
                }
            }
        }

        return suitable
    }

    private static func buildHarmonyProfile(sheet: Sheet) -> TMDHarmonyProfile {
        var chords: [String] = []
        for p in sheet.paragraphs {
            for sec in p.sections {
                for group in sec.unitGroups {
                    for unit in group.units {
                        if case .chord(let ch) = unit {
                            let raw = "[\(ch.description)]"
                            if !chords.contains(raw) {
                                chords.append(raw)
                            }
                        }
                    }
                }
            }
        }

        var modulations: [String] = []
        for order in sheet.orders {
            if case .relative(let val) = order {
                modulations.append("Relative: \(val) semitones")
            } else if case .absolute(let val) = order {
                modulations.append("Key: \(val)")
            }
        }

        return TMDHarmonyProfile(
            distinctChords: chords,
            chordCount: chords.count,
            modulations: modulations
        )
    }

    private static func buildDensityProfile(sheet: Sheet) -> TMDArrangementDensityProfile {
        var sectionDict: [String: [String]] = [:]
        for p in sheet.paragraphs {
            sectionDict[p.name, default: []].append(p.instrument)
        }

        var sectionDensities: [TMDArrangementDensityProfile.SectionDensity] = []
        var maxTracks = 0

        for (secName, instList) in sectionDict {
            let uniqueInst = Array(Set(instList)).sorted()
            if uniqueInst.count > maxTracks {
                maxTracks = uniqueInst.count
            }
            sectionDensities.append(TMDArrangementDensityProfile.SectionDensity(
                sectionName: secName,
                trackCount: uniqueInst.count,
                instruments: uniqueInst
            ))
        }

        return TMDArrangementDensityProfile(
            maxConcurrentTracks: maxTracks,
            sectionDensities: sectionDensities.sorted(by: { $0.sectionName < $1.sectionName })
        )
    }

    private static func formatNoteLocation(_ note: TMDNotePitchInfo) -> String {
        let mins = Int(note.timeSeconds) / 60
        let secs = Int(note.timeSeconds) % 60
        let timeStr = String(format: "%d:%02d", mins, secs)
        if !note.sectionName.isEmpty {
            return "[\(note.sectionName) #\(note.sectionOccurrence) @ m.\(note.measure), \(timeStr)]"
        } else {
            return "[@ m.\(note.measure), \(timeStr)]"
        }
    }

    /// Generates human-readable plain text / ASCII inspection report.
    public static func generateReport(_ profile: TMDSongProfile) -> String {
        let mins = Int(profile.timing.totalDurationSeconds) / 60
        let secs = Int(profile.timing.totalDurationSeconds) % 60
        let timeFormatted = String(format: "%d:%02d (%0.1fs)", mins, secs, profile.timing.totalDurationSeconds)

        var lines: [String] = []
        lines.append("================================================================================")
        lines.append("📊 TMD Song Profile: [ \(profile.title) ]")
        lines.append("================================================================================")
        lines.append("⏱  Duration:       \(timeFormatted), \(profile.timing.totalMeasures) measures total")
        lines.append("🎼 Key & Tempo:    \(profile.initialKey) Major, != \(profile.initialTempo) BPM, <\(profile.initialTimeSignature)>")

        if let vocal = profile.vocalRange {
            let octaves = String(format: "%0.1f", vocal.spanOctaves)
            lines.append("🎤 Vocal Range:    \(vocal.lowestNote.noteName) (MIDI \(vocal.lowestNote.midiPitch)) – \(vocal.highestNote.noteName) (MIDI \(vocal.highestNote.midiPitch)) [Span: \(vocal.spanSemitones) semitones / \(octaves) octaves, Difficulty: \(vocal.difficulty.rawValue)]")
            lines.append("   - Lowest Note:  \(vocal.lowestNote.noteName) in \(formatNoteLocation(vocal.lowestNote))")
            lines.append("   - Highest Note: \(vocal.highestNote.noteName) in \(formatNoteLocation(vocal.highestNote))")
            if !vocal.suitableVoiceTypes.isEmpty {
                let voiceNames = vocal.suitableVoiceTypes.map(\.rawValue).joined(separator: ", ")
                lines.append("   - Suitable For: \(voiceNames)")
            }
        }

        lines.append("🏛  Structure:      " + profile.timing.sections.map { "\($0.name) (\(String(format: "%0.1fs", $0.durationSeconds)))" }.joined(separator: " -> "))
        lines.append("⚡ Density:        Peak \(profile.density.maxConcurrentTracks) tracks concurrently")

        if !profile.harmony.distinctChords.isEmpty {
            lines.append("🎹 Harmony:        " + profile.harmony.distinctChords.joined(separator: " "))
        }

        if let tonality = profile.tonality {
            let stabStr = tonality.globalCorrelation.stability.rawValue.capitalized
            let corrStr = String(format: "%0.2f", tonality.globalCorrelation.declaredKeyCorrelation)
            let diatonicPct = String(format: "%0.1f%%", tonality.globalPitchClasses.diatonicRatio * 100.0)
            let topPitches = tonality.globalPitchClasses.topPitchClasses.prefix(5).joined(separator: ", ")

            lines.append("🗝  調性診斷：       \(tonality.summaryText)")
            lines.append("   - 風格氣質：    \(tonality.moodDescription)")
            lines.append("   - 轉調歷程：    \(tonality.modulationStory)")
            lines.append("   - 核心骨幹音：  \(topPitches)")
            lines.append("   - 調性數值：    \(tonality.globalCorrelation.declaredKey) [相關度: \(corrStr), 穩定度: \(stabStr), 自然音純度: \(diatonicPct)]")

            let candidateStr = tonality.globalCorrelation.topCandidateKeys.prefix(3).map {
                "\($0.keyName) (\(String(format: "%0.2f", $0.correlation)))"
            }.joined(separator: ", ")
            if !candidateStr.isEmpty {
                lines.append("   - 候選調性 (K-S): \(candidateStr)")
            }

            let pathStr = tonality.circleOfFifthsPath.map { "\($0 >= 0 ? "+" : "")\($0)" }.joined(separator: " -> ")
            if !pathStr.isEmpty {
                lines.append("   - 五度圈歷程:   \(pathStr)")
            }

            if !tonality.sections.isEmpty {
                lines.append("   - 各段落調性細節:")
                for sec in tonality.sections {
                    let secCorr = String(format: "%0.2f", sec.correlation.declaredKeyCorrelation)
                    let secDiatonic = String(format: "%0.1f%%", sec.pitchClasses.diatonicRatio * 100.0)
                    var secLine = "     • [\(sec.sectionName) #\(sec.occurrenceIndex)]: \(sec.declaredKey) (r: \(secCorr), 自然音: \(secDiatonic)"
                    if !sec.nonDiatonicNotes.isEmpty {
                        secLine += ", 調外音: \(sec.nonDiatonicNotes.joined(separator: ", "))"
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

        lines.append("--------------------------------------------------------------------------------")
        lines.append("Instrument Track Ranges:")
        for inst in profile.instrumentRanges {
            let octaves = String(format: "%0.1f", inst.spanOctaves)
            lines.append("  - \(inst.instrument.padding(toLength: 14, withPad: " ", startingAt: 0)): \(inst.lowestNote.noteName) – \(inst.highestNote.noteName) (\(inst.spanSemitones) semitones / \(octaves) octaves, \(inst.totalNotes) notes)")
        }
        lines.append("================================================================================")

        return lines.joined(separator: "\n")
    }

    // MARK: - Tonality & Key Profile Analysis Engine

    private static func buildTonalityProfile(sheet: Sheet, timingProfile: TMDTimingProfile) -> TMDTonalityProfile {
        let distinctInsts = sheet.distinctInstruments(fallbackToDefault: true)
        var allEvents: [PlaybackEvent] = []
        for inst in distinctInsts {
            let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: inst)
            allEvents.append(contentsOf: timeline.events)
        }

        var globalWeights = [Double](repeating: 0.0, count: 12)
        var sectionWeights: [Int: [Double]] = [:] // Section index in timingProfile -> 12 weights
        for idx in 0..<timingProfile.sections.count {
            sectionWeights[idx] = [Double](repeating: 0.0, count: 12)
        }

        // 1. Accumulate melody notes
        for event in allEvents {
            guard case .note(let note) = event.content else { continue }
            var pitch = 60 + event.state.keyOffset + note.degree.semitoneOffset
            switch note.accidental {
            case .sharp: pitch += 1
            case .flat: pitch -= 1
            case .natural: break
            }
            pitch += note.octave * 12
            let pc = (pitch % 12 + 12) % 12
            let dur = event.duration

            globalWeights[pc] += dur

            for (secIdx, sec) in timingProfile.sections.enumerated() {
                if event.position >= sec.startPositionQuarterNotes &&
                   event.position < (sec.startPositionQuarterNotes + sec.durationQuarterNotes + 0.001) {
                    sectionWeights[secIdx]![pc] += dur
                }
            }
        }

        // 2. Accumulate chord symbol constituents
        for event in allEvents {
            guard case .chord(let chord) = event.content else { continue }
            let dur = event.duration
            let chordPCs = chordPitchClasses(chord, keyOffset: event.state.keyOffset)
            for (pc, weightFactor) in chordPCs {
                let w = dur * weightFactor
                globalWeights[pc] += w
                for (secIdx, sec) in timingProfile.sections.enumerated() {
                    if event.position >= sec.startPositionQuarterNotes &&
                       event.position < (sec.startPositionQuarterNotes + sec.durationQuarterNotes + 0.001) {
                        sectionWeights[secIdx]![pc] += w
                    }
                }
            }
        }

        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let baseKey = sheet.keySignature.description

        // Global distribution & K-S correlation
        let globalDist = makePitchClassDistribution(weights: globalWeights, tonicOffset: sheet.keySignature.semitoneOffset)
        let globalCorr = evaluateKeyCorrelation(weights: globalWeights, declaredKeyName: baseKey, declaredTonicOffset: sheet.keySignature.semitoneOffset)

        // Sections
        var sectionProfiles: [TMDSectionTonalityProfile] = []
        var circleOfFifthsPath: [Int] = []

        for (secIdx, sec) in timingProfile.sections.enumerated() {
            let weights = sectionWeights[secIdx] ?? [Double](repeating: 0.0, count: 12)
            let secTonicOffset = (sheet.keySignature.semitoneOffset + sec.keyOffset % 12 + 12) % 12
            let secKeyName = keyName(forTonicOffset: secTonicOffset)
            let secDist = makePitchClassDistribution(weights: weights, tonicOffset: secTonicOffset)
            let secCorr = evaluateKeyCorrelation(weights: weights, declaredKeyName: secKeyName, declaredTonicOffset: secTonicOffset)

            let diatonicMask = diatonicPitchClassMask(tonicOffset: secTonicOffset)
            var nonDiatonic: [String] = []
            for pc in 0..<12 {
                if !diatonicMask.contains(pc) && weights[pc] > 0.001 {
                    nonDiatonic.append(pitchClassNames[pc])
                }
            }

            let fifthsStep = circleOfFifthsStep(tonicOffset: secTonicOffset)
            circleOfFifthsPath.append(fifthsStep)

            sectionProfiles.append(TMDSectionTonalityProfile(
                sectionName: sec.name,
                occurrenceIndex: sec.occurrenceIndex,
                declaredKey: secKeyName,
                keyOffset: sec.keyOffset,
                fifthsPosition: fifthsStep,
                pitchClasses: secDist,
                correlation: secCorr,
                nonDiatonicNotes: nonDiatonic
            ))
        }

        // Human-friendly producer narrative synthesis
        let diatonicRatio = globalDist.diatonicRatio
        let moodDescription: String
        if diatonicRatio >= 0.95 {
            moodDescription = "純淨自然大調（陽光明朗、易唱易記，無明顯調外色彩）"
        } else if diatonicRatio >= 0.80 {
            moodDescription = "流行大調（略帶和弦色彩音與裝飾副屬和弦）"
        } else {
            moodDescription = "調式色彩／藍調前衛（調外音豐富，張力強烈）"
        }

        // Modulation story
        var modTransitions: [String] = []
        var prevKey = baseKey
        var prevOffset = 0
        for sec in sectionProfiles {
            if sec.keyOffset != prevOffset || sec.declaredKey != prevKey {
                let diff = sec.keyOffset - prevOffset
                let semitoneDiff = diff >= 0 ? "+\(diff)" : "\(diff)"
                let stepDiff = sec.fifthsPosition
                let stepStr = stepDiff >= 0 ? "+\(stepDiff)" : "\(stepDiff)"
                modTransitions.append("[\(sec.sectionName)] 轉至 \(sec.declaredKey) 大調 (\(semitoneDiff) 半音 / 五度圈 \(stepStr) 步)")
                prevKey = sec.declaredKey
                prevOffset = sec.keyOffset
            }
        }

        let modulationStory: String
        if modTransitions.isEmpty {
            modulationStory = "全曲維持單一調性（未轉調）"
        } else {
            modulationStory = "\(baseKey) 大調起奏 ➔ " + modTransitions.joined(separator: " ➔ ")
        }

        let summaryText: String
        if modTransitions.isEmpty {
            summaryText = "\(baseKey) 大調（\(diatonicRatio >= 0.95 ? "純淨自然大調" : "流行色彩大調")，全曲無轉調）"
        } else {
            summaryText = "\(baseKey) 大調（轉調推進情緒，經歷 \(modTransitions.count) 次轉調）"
        }

        return TMDTonalityProfile(
            globalPitchClasses: globalDist,
            globalCorrelation: globalCorr,
            circleOfFifthsPath: circleOfFifthsPath,
            sections: sectionProfiles,
            summaryText: summaryText,
            moodDescription: moodDescription,
            modulationStory: modulationStory
        )
    }

    private static func chordPitchClasses(_ chord: ChordSymbol, keyOffset: Int) -> [(pc: Int, weight: Double)] {
        let rootOffset: Int
        if chord.root.isScaleDegree {
            rootOffset = (keyOffset + chord.root.semitoneOffset) % 12
        } else {
            rootOffset = chord.root.semitoneOffset % 12
        }
        let tonic = (rootOffset + 12) % 12
        var result: [(Int, Double)] = []

        let intervals = chord.quality.semitoneIntervals
        for (i, interval) in intervals.enumerated() {
            let pc = (tonic + interval) % 12
            let w: Double
            switch i {
            case 0: w = 1.0     // Root
            case 1: w = 0.8     // Third
            case 2: w = 0.8     // Fifth
            default: w = 0.6    // 7th / Extension
            }
            result.append((pc, w))
        }

        if let bass = chord.bass {
            let bassOffset: Int
            if bass.isScaleDegree {
                bassOffset = (keyOffset + bass.semitoneOffset) % 12
            } else {
                bassOffset = bass.semitoneOffset % 12
            }
            let bassPC = (bassOffset + 12) % 12
            result.append((bassPC, 0.8))
        }

        return result
    }

    private static func diatonicPitchClassMask(tonicOffset: Int) -> Set<Int> {
        // Major scale diatonic intervals: [0, 2, 4, 5, 7, 9, 11]
        let majorSteps = [0, 2, 4, 5, 7, 9, 11]
        var mask = Set<Int>()
        for step in majorSteps {
            mask.insert((tonicOffset + step) % 12)
        }
        return mask
    }

    private static func makePitchClassDistribution(weights: [Double], tonicOffset: Int) -> TMDPitchClassDistribution {
        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let total = weights.reduce(0.0, +)
        guard total > 0.0001 else {
            return TMDPitchClassDistribution(
                weights: weights,
                diatonicRatio: 1.0,
                chromaticRatio: 0.0,
                topPitchClasses: []
            )
        }

        let diatonicMask = diatonicPitchClassMask(tonicOffset: tonicOffset)
        var diatonicSum = 0.0
        for pc in 0..<12 {
            if diatonicMask.contains(pc) {
                diatonicSum += weights[pc]
            }
        }

        let diatonicRatio = diatonicSum / total
        let chromaticRatio = max(0.0, 1.0 - diatonicRatio)

        var indexed: [(name: String, weight: Double)] = []
        for i in 0..<12 {
            if weights[i] > 0.0001 {
                indexed.append((pitchClassNames[i], weights[i]))
            }
        }
        indexed.sort(by: { $0.weight > $1.weight })
        let topNames = indexed.map(\.name)

        return TMDPitchClassDistribution(
            weights: weights,
            diatonicRatio: diatonicRatio,
            chromaticRatio: chromaticRatio,
            topPitchClasses: topNames
        )
    }

    // Krumhansl-Schmuckler 12-pitch-class profiles for Major and Minor
    private static let ksMajorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let ksMinorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    private static func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count, !x.isEmpty else { return 0.0 }
        let n = Double(x.count)
        let meanX = x.reduce(0.0, +) / n
        let meanY = y.reduce(0.0, +) / n

        var num = 0.0
        var denomX = 0.0
        var denomY = 0.0

        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            num += dx * dy
            denomX += dx * dx
            denomY += dy * dy
        }

        let denom = sqrt(denomX * denomY)
        if denom < 1e-9 { return 0.0 }
        return num / denom
    }

    private static func evaluateKeyCorrelation(weights: [Double], declaredKeyName: String, declaredTonicOffset: Int) -> TMDKeyCorrelation {
        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        var candidates: [TMDKeyFitCandidate] = []

        // Evaluate all 12 Major and 12 Minor keys
        for tonic in 0..<12 {
            var rotWeights = [Double](repeating: 0.0, count: 12)
            for i in 0..<12 {
                rotWeights[i] = weights[(tonic + i) % 12]
            }

            let rMajor = pearsonCorrelation(rotWeights, ksMajorProfile)
            candidates.append(TMDKeyFitCandidate(keyName: "\(pitchClassNames[tonic]) Major", correlation: rMajor))

            let rMinor = pearsonCorrelation(rotWeights, ksMinorProfile)
            candidates.append(TMDKeyFitCandidate(keyName: "\(pitchClassNames[tonic]) Minor", correlation: rMinor))
        }

        candidates.sort(by: { $0.correlation > $1.correlation })

        // Find correlation of declared key (Major profile)
        var declaredRot = [Double](repeating: 0.0, count: 12)
        for i in 0..<12 {
            declaredRot[i] = weights[(declaredTonicOffset + i) % 12]
        }
        let declaredR = pearsonCorrelation(declaredRot, ksMajorProfile)

        let diatonicMask = diatonicPitchClassMask(tonicOffset: declaredTonicOffset)
        let total = weights.reduce(0.0, +)
        let diatonicSum = (0..<12).filter { diatonicMask.contains($0) }.map { weights[$0] }.reduce(0.0, +)
        let diatonicRatio = total > 0 ? (diatonicSum / total) : 1.0

        let stability: TMDKeyStability
        if declaredR >= 0.70 && diatonicRatio >= 0.85 {
            stability = .high
        } else if declaredR >= 0.40 && diatonicRatio >= 0.65 {
            stability = .moderate
        } else {
            stability = .ambiguous
        }

        return TMDKeyCorrelation(
            declaredKey: declaredKeyName,
            declaredKeyCorrelation: declaredR,
            topCandidateKeys: Array(candidates.prefix(3)),
            stability: stability
        )
    }

    private static func keyName(forTonicOffset tonic: Int) -> String {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        return names[(tonic % 12 + 12) % 12]
    }

    private static func circleOfFifthsStep(tonicOffset: Int) -> Int {
        // C=0, G=+1, D=+2, A=+3, E=+4, B=+5, F#=+6, F=-1, Bb=-2, Eb=-3, Ab=-4, Db=-5
        switch (tonicOffset % 12 + 12) % 12 {
        case 0: return 0    // C
        case 7: return 1    // G
        case 2: return 2    // D
        case 9: return 3    // A
        case 4: return 4    // E
        case 11: return 5   // B
        case 6: return 6    // F# / Gb
        case 1: return -5   // Db / C#
        case 8: return -4   // Ab / G#
        case 3: return -3   // Eb
        case 10: return -2  // Bb
        case 5: return -1   // F
        default: return 0
        }
    }

    private static func collectTimelineDirectives(sheet: Sheet) -> [PlaybackDirectiveEvent] {
        let paragraphs = sheet.paragraphs
        let instruments = Set(paragraphs.map { $0.instrument.isEmpty ? "Piano" : $0.instrument })
        var directives: [PlaybackDirectiveEvent] = []
        for instrument in instruments {
            directives.append(contentsOf: TMDPlaybackRenderer.render(sheet: sheet, instrument: instrument).directives)
        }
        directives.sort(by: { $0.position < $1.position })

        var filtered: [PlaybackDirectiveEvent] = []
        for directive in directives {
            if let last = filtered.last {
                if last.position == directive.position
                    && last.state.tempo == directive.state.tempo
                    && last.state.timeSignature.count == directive.state.timeSignature.count
                    && last.state.timeSignature.noteValue == directive.state.timeSignature.noteValue {
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

    private static func renderAsciiCircleOfFifths(tonality: TMDTonalityProfile) -> String {
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
        let c   = node("C", 0)
        let g   = node("G", 1)
        let d   = node("D", 2)
        let a   = node("A", 3)
        let e   = node("E", 4)
        let b   = node("B", 5)
        let fs  = node("F#", 6)
        let db  = node("Db", -5)
        let ab  = node("Ab", -4)
        let eb  = node("Eb", -3)
        let bb  = node("Bb", -2)
        let f   = node("F", -1)

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

    private static func renderPitchClassHistogram(tonality: TMDTonalityProfile) -> String {
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
            lines.append("     \(name): \(bar.padding(toLength: barMaxWidth, withPad: " ", startingAt: 0)) \(pct)")
        }
        return lines.joined(separator: "\n")
    }
}
