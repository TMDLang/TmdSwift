import Foundation

/// Computes the score timing profile independently from the Inspector facade.
public enum TmdSongTimingAnalyzer {
    public static func analyze(
        sheet: Sheet, timelineDirectives: [PlaybackDirectiveEvent]
    ) -> TmdTimingProfile {
        let orders = sheet.playback.isEmpty
            ? sheet.entries.map(\.name).reduce(into: [String]()) {
                if !$0.contains($1) { $0.append($1) }
            }.map(Playback.name)
            : sheet.playback

        var state = PlaybackState(
            tempo: sheet.speed > 0 ? sheet.speed : 120.0,
            keyOffset: sheet.keySignature.semitoneOffset,
            timeSignature: sheet.beat
        )
        var sections: [TmdSectionTimingProfile] = []
        var currentQuarterPosition = 0.0
        var currentSeconds = 0.0
        var currentMeasure = 1
        var totalMeasures = 0
        var sectionOccurrences: [String: Int] = [:]

        for (idx, order) in orders.enumerated() {
            switch order {
            case .relative(let val):
                if let delta = Int(val.replacingOccurrences(of: "+", with: "")) {
                    state = PlaybackState(
                        tempo: state.tempo, keyOffset: state.keyOffset + delta,
                        timeSignature: state.timeSignature)
                }
            case .absolute(let val):
                state = PlaybackState(
                    tempo: state.tempo,
                    keyOffset: KeySignature(string: val).semitoneOffset,
                    timeSignature: state.timeSignature)
            case .name(let secName):
                let duration = TmdPlaybackRenderer.duration(of: secName, in: sheet)
                let startPosition = currentQuarterPosition
                let endPosition = startPosition + duration
                var cursor = startPosition
                var tempo = state.tempo
                var meter = state.timeSignature
                var durationSeconds = 0.0
                var measureCount = 0.0

                for directive in timelineDirectives {
                    guard directive.position >= startPosition,
                          directive.position < endPosition else { continue }
                    if directive.position > cursor {
                        let segment = directive.position - cursor
                        durationSeconds += segment * 60.0 / tempo
                        measureCount += segment / measureDuration(for: meter)
                        cursor = directive.position
                    }
                    tempo = directive.state.tempo
                    meter = directive.state.timeSignature
                }
                if endPosition > cursor {
                    let segment = endPosition - cursor
                    durationSeconds += segment * 60.0 / tempo
                    measureCount += segment / measureDuration(for: meter)
                }

                let occurrence = sectionOccurrences[secName, default: 0] + 1
                sectionOccurrences[secName] = occurrence
                let sectionMeasures = max(1, Int(round(measureCount)))
                sections.append(TmdSectionTimingProfile(
                    name: secName,
                    orderIndex: idx,
                    occurrenceIndex: occurrence,
                    startMeasure: currentMeasure,
                    startPositionQuarterNotes: currentQuarterPosition,
                    durationQuarterNotes: duration,
                    startSeconds: currentSeconds,
                    durationSeconds: durationSeconds,
                    measures: sectionMeasures,
                    keyOffset: state.keyOffset,
                    tempo: state.tempo
                ))

                currentQuarterPosition += duration
                currentSeconds += durationSeconds
                currentMeasure += sectionMeasures
                totalMeasures += sectionMeasures
                state = PlaybackState(
                    tempo: tempo, keyOffset: state.keyOffset, timeSignature: meter)
            case .macro:
                break
            }
        }

        return TmdTimingProfile(
            totalDurationSeconds: currentSeconds,
            totalMeasures: totalMeasures,
            sections: sections)
    }

    private static func measureDuration(for beat: Beat) -> Double {
        Double(max(1, beat.count)) * 4.0 / Double(max(1, beat.noteValue))
    }
}
