import Foundation

/// Computes instrument pitch ranges independently from the Inspector facade.
public enum TmdSongPitchRangeAnalyzer {
    public static func analyze(
        instrument: String,
        sheet: Sheet,
        timingProfile: TmdTimingProfile,
        timelineDirectives: [PlaybackDirectiveEvent]
    ) -> TmdPitchRangeProfile? {
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: instrument)
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
            let pitch = note.midiPitch(keyOffset: event.state.keyOffset)
            let matchedSection = timingProfile.sections.first {
                event.position >= $0.startPositionQuarterNotes
                    && event.position < $0.startPositionQuarterNotes + $0.durationQuarterNotes + 0.001
            }
            let sectionName = matchedSection?.name ?? ""
            let occurrence = matchedSection?.occurrenceIndex ?? 1
            let measure: Int
            let timeSeconds: Double
            if let section = matchedSection {
                let position = max(section.startPositionQuarterNotes, event.position)
                var cursor = section.startPositionQuarterNotes
                var tempo = section.tempo
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
                measure = section.startMeasure + Int(floor(elapsedMeasures + 1e-9))
                timeSeconds = section.startSeconds + elapsedSeconds
            } else {
                let nominalMeasureDuration = measureDuration(for: event.state.timeSignature)
                measure = 1 + Int(floor(event.position / nominalMeasureDuration))
                timeSeconds = event.position / (event.state.tempo / 60.0)
            }
            hits.append(NoteHit(
                midi: pitch, name: TmdNotePitchInfo.name(for: pitch), pos: event.position,
                sectionName: sectionName, sectionOccurrence: occurrence,
                measure: measure, timeSeconds: timeSeconds))
        }

        guard !hits.isEmpty else { return nil }
        let lowest = hits.min { $0.midi < $1.midi }!
        let highest = hits.max { $0.midi < $1.midi }!
        let span = highest.midi - lowest.midi
        return TmdPitchRangeProfile(
            instrument: instrument,
            lowestNote: TmdNotePitchInfo(
                midiPitch: lowest.midi, noteName: lowest.name, sectionName: lowest.sectionName,
                timelinePosition: lowest.pos, sectionOccurrence: lowest.sectionOccurrence,
                measure: lowest.measure, timeSeconds: lowest.timeSeconds),
            highestNote: TmdNotePitchInfo(
                midiPitch: highest.midi, noteName: highest.name, sectionName: highest.sectionName,
                timelinePosition: highest.pos, sectionOccurrence: highest.sectionOccurrence,
                measure: highest.measure, timeSeconds: highest.timeSeconds),
            spanSemitones: span,
            totalNotes: hits.count,
            averageMidiPitch: Double(hits.reduce(0) { $0 + $1.midi }) / Double(hits.count),
            difficulty: evaluateDifficulty(spanSemitones: span),
            suitableVoiceTypes: evaluateSuitableVoiceTypes(
                lowestMidi: lowest.midi, highestMidi: highest.midi))
    }

    public static func evaluateDifficulty(spanSemitones: Int) -> TmdPitchRangeDifficulty {
        if spanSemitones <= 12 { return .easy }
        if spanSemitones <= 16 { return .moderate }
        if spanSemitones <= 20 { return .challenging }
        return .difficult
    }

    public static func evaluateSuitableVoiceTypes(
        lowestMidi: Int, highestMidi: Int
    ) -> [TmdVocalClassification] {
        let ranges: [(TmdVocalClassification, Int, Int)] = [
            (.soprano, 57, 86), (.mezzoSoprano, 53, 81), (.contralto, 50, 77),
            (.tenor, 45, 74), (.baritone, 41, 69), (.bass, 38, 65)
        ]
        var suitable: [TmdVocalClassification] = []
        for (type, min, max) in ranges where lowestMidi >= min && highestMidi <= max {
            suitable.append(type)
        }
        let maleTypes: Set<TmdVocalClassification> = [.tenor, .baritone, .bass]
        for (type, min, max) in ranges where maleTypes.contains(type) && !suitable.contains(type) {
            if lowestMidi - 12 >= min && highestMidi - 12 <= max { suitable.append(type) }
        }
        return suitable
    }

    private static func measureDuration(for beat: Beat) -> Double {
        Double(max(1, beat.count)) * 4.0 / Double(max(1, beat.noteValue))
    }
}
