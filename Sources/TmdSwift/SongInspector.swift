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

    public init(
        instrument: String,
        lowestNote: TMDNotePitchInfo,
        highestNote: TMDNotePitchInfo,
        spanSemitones: Int,
        totalNotes: Int,
        averageMidiPitch: Double
    ) {
        self.instrument = instrument
        self.lowestNote = lowestNote
        self.highestNote = highestNote
        self.spanSemitones = spanSemitones
        self.totalNotes = totalNotes
        self.averageMidiPitch = averageMidiPitch
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

    public init(
        title: String,
        initialTempo: Double,
        initialKey: String,
        initialTimeSignature: String,
        timing: TMDTimingProfile,
        vocalRange: TMDPitchRangeProfile?,
        instrumentRanges: [TMDPitchRangeProfile],
        harmony: TMDHarmonyProfile,
        density: TMDArrangementDensityProfile
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
    }
}

/// Inspector engine extracting holistic musical metrics, vocal tessitura, and arrangement profiles from a TMD Sheet.
public enum TMDSongInspector {

    /// Inspects a parsed TMD `Sheet` and produces an in-depth `TMDSongProfile`.
    public static func inspect(sheet: Sheet) -> TMDSongProfile {
        let title = sheet.name.isEmpty ? "Untitled" : sheet.name
        let initialTempo = sheet.speed > 0 ? sheet.speed : 120.0
        let initialKey = sheet.keySignature.description
        let initialMeter = "\(sheet.beat.count)/\(sheet.beat.noteValue)"

        // 1. Timing & Structure Profile
        let timingProfile = buildTimingProfile(sheet: sheet)

        // 2. Instrument & Pitch Ranges
        let instruments = sheet.distinctInstruments(fallbackToDefault: false)
        var instrumentRanges: [TMDPitchRangeProfile] = []

        for inst in instruments {
            if let profile = buildPitchProfile(for: inst, sheet: sheet, timingProfile: timingProfile) {
                instrumentRanges.append(profile)
            }
        }

        // 3. Vocal Range (picks target vocal instrument)
        let targetVocalInst = sheet.resolveVocalInstrument()
        let vocalRange = instrumentRanges.first { $0.instrument == targetVocalInst }

        // 4. Harmony & Chord Profile
        let harmonyProfile = buildHarmonyProfile(sheet: sheet)

        // 5. Arrangement & Density Profile
        let densityProfile = buildDensityProfile(sheet: sheet)

        return TMDSongProfile(
            title: title,
            initialTempo: initialTempo,
            initialKey: initialKey,
            initialTimeSignature: initialMeter,
            timing: timingProfile,
            vocalRange: vocalRange,
            instrumentRanges: instrumentRanges,
            harmony: harmonyProfile,
            density: densityProfile
        )
    }

    private static func buildTimingProfile(sheet: Sheet) -> TMDTimingProfile {
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
                let nominalMeasureDur = Double(max(1, state.timeSignature.count)) * 4.0 / Double(max(1, state.timeSignature.noteValue))
                let secMeasures = max(1, Int(round(durQuarterNotes / nominalMeasureDur)))
                let secDurationSeconds = (durQuarterNotes / (state.tempo / 60.0))

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
            }
        }

        return TMDTimingProfile(
            totalDurationSeconds: currentSeconds,
            totalMeasures: totalMeasures,
            sections: sections
        )
    }

    private static func buildPitchProfile(for instrument: String, sheet: Sheet, timingProfile: TMDTimingProfile) -> TMDPitchRangeProfile? {
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
            let nominalMeasureDur = Double(max(1, event.state.timeSignature.count)) * 4.0 / Double(max(1, event.state.timeSignature.noteValue))
            let measure: Int
            let timeSeconds: Double
            if let sec = matchedSection {
                let offsetInSec = max(0.0, event.position - sec.startPositionQuarterNotes)
                let measureOffset = Int(floor(offsetInSec / nominalMeasureDur))
                measure = sec.startMeasure + measureOffset
                let secTimeOffset = offsetInSec / (sec.tempo / 60.0)
                timeSeconds = sec.startSeconds + secTimeOffset
            } else {
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
            spanSemitones: highest.midi - lowest.midi,
            totalNotes: hits.count,
            averageMidiPitch: avgPitch
        )
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
            lines.append("🎤 Vocal Range:    \(vocal.lowestNote.noteName) (MIDI \(vocal.lowestNote.midiPitch)) – \(vocal.highestNote.noteName) (MIDI \(vocal.highestNote.midiPitch)) [Span: \(vocal.spanSemitones) semitones / \(octaves) octaves]")
            lines.append("   - Lowest Note:  \(vocal.lowestNote.noteName) in \(formatNoteLocation(vocal.lowestNote))")
            lines.append("   - Highest Note: \(vocal.highestNote.noteName) in \(formatNoteLocation(vocal.highestNote))")
        }

        lines.append("🏛  Structure:      " + profile.timing.sections.map { "\($0.name) (\(String(format: "%0.1fs", $0.durationSeconds)))" }.joined(separator: " -> "))
        lines.append("⚡ Density:        Peak \(profile.density.maxConcurrentTracks) tracks concurrently")

        if !profile.harmony.distinctChords.isEmpty {
            lines.append("🎹 Harmony:        " + profile.harmony.distinctChords.joined(separator: " "))
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
}
