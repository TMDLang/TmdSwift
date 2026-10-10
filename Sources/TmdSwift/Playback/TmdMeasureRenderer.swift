import Foundation

/// Standard musical notation duration representations.
public struct NotationDuration: Equatable, Sendable {
    public let baseDenominator: Int  // 1, 2, 4, 8, 16, 32, 64
    public let isDotted: Bool
    public let quarterValue: Double

    public init(baseDenominator: Int, isDotted: Bool, quarterValue: Double) {
        self.baseDenominator = baseDenominator
        self.isDotted = isDotted
        self.quarterValue = quarterValue
    }

    /// Predefined standard notation duration atoms (powers-of-2 and single-dotted values).
    public static let standardValues: [NotationDuration] = [
        NotationDuration(baseDenominator: 1, isDotted: false, quarterValue: 4.0),
        NotationDuration(baseDenominator: 2, isDotted: true, quarterValue: 3.0),
        NotationDuration(baseDenominator: 2, isDotted: false, quarterValue: 2.0),
        NotationDuration(baseDenominator: 4, isDotted: true, quarterValue: 1.5),
        NotationDuration(baseDenominator: 4, isDotted: false, quarterValue: 1.0),
        NotationDuration(baseDenominator: 8, isDotted: true, quarterValue: 0.75),
        NotationDuration(baseDenominator: 8, isDotted: false, quarterValue: 0.5),
        NotationDuration(baseDenominator: 16, isDotted: true, quarterValue: 0.375),
        NotationDuration(baseDenominator: 16, isDotted: false, quarterValue: 0.25),
        NotationDuration(baseDenominator: 32, isDotted: true, quarterValue: 0.1875),
        NotationDuration(baseDenominator: 32, isDotted: false, quarterValue: 0.125),
        NotationDuration(baseDenominator: 64, isDotted: false, quarterValue: 0.0625),
    ]

    /// Decomposes any duration (in quarter-note units) into standard notation values.
    public static func decompose(quarterNotes: Double) -> [NotationDuration] {
        var remaining = quarterNotes
        var result: [NotationDuration] = []
        let epsilon = 1e-4

        while remaining > epsilon {
            var matched = false
            for standard in standardValues {
                if remaining >= standard.quarterValue - epsilon {
                    result.append(standard)
                    remaining -= standard.quarterValue
                    matched = true
                    break
                }
            }
            if !matched {
                // If smaller than 64th note, append a 64th note and finish
                if remaining > 0 {
                    result.append(
                        NotationDuration(baseDenominator: 64, isDotted: false, quarterValue: 0.0625)
                    )
                }
                break
            }
        }
        return result.isEmpty
            ? [NotationDuration(baseDenominator: 4, isDotted: false, quarterValue: 1.0)] : result
    }
}

/// Represents an atomic or split musical event positioned within a measure.
public struct MeasureEvent: Equatable, Sendable {
    public let startOffset: Double
    public let duration: Double
    public let content: PlaybackContent
    public let tieStart: Bool
    public let tieStop: Bool
    public let state: PlaybackState

    public init(
        startOffset: Double,
        duration: Double,
        content: PlaybackContent,
        tieStart: Bool = false,
        tieStop: Bool = false,
        state: PlaybackState
    ) {
        self.startOffset = startOffset
        self.duration = duration
        self.content = content
        self.tieStart = tieStart
        self.tieStop = tieStop
        self.state = state
    }
}

/// Represents a discrete measure in a score for engraving and notation.
public struct Measure: Equatable, Sendable {
    public let index: Int
    public let startTime: Double
    public let nominalDuration: Double
    public let timeSignature: Beat
    public let tempo: Double
    public let keyOffset: Int
    public let events: [MeasureEvent]
    public let directives: [PlaybackDirectiveEvent]

    public init(
        index: Int,
        startTime: Double,
        nominalDuration: Double,
        timeSignature: Beat,
        tempo: Double,
        keyOffset: Int,
        events: [MeasureEvent],
        directives: [PlaybackDirectiveEvent] = []
    ) {
        self.index = index
        self.startTime = startTime
        self.nominalDuration = nominalDuration
        self.timeSignature = timeSignature
        self.tempo = tempo
        self.keyOffset = keyOffset
        self.events = events
        self.directives = directives
    }

    /// Groups events in the measure that start at the same offset (within `1e-4` quarter notes)
    /// into simultaneous event groups (such as `.multiNote` dyads/chords).
    public var simultaneousEventGroups: [[MeasureEvent]] {
        var groups: [[MeasureEvent]] = []
        for ev in events {
            if let lastGroup = groups.last,
                let firstInLast = lastGroup.first,
                abs(ev.startOffset - firstInLast.startOffset) < 1e-4
            {
                groups[groups.count - 1].append(ev)
            } else {
                groups.append([ev])
            }
        }
        return groups
    }
}

/// Renders format-independent timeline events into discrete, duration-conserved measures.
public enum TmdMeasureRenderer {

    /// Renders an instrument track into an array of strictly bounded measures.
    public static func renderMeasures(sheet: Sheet, instrument: String) -> [Measure] {
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: instrument)
        let defaultBeat =
            sheet.beat.count > 0 && sheet.beat.noteValue > 0
            ? sheet.beat : Beat(count: 4, noteValue: 4)
        let initialMeasureDuration = Double(defaultBeat.count) * 4.0 / Double(defaultBeat.noteValue)

        let totalDuration = max(timeline.duration, initialMeasureDuration)
        let measureCount = max(1, Int(ceil(totalDuration / initialMeasureDuration)))

        // Pre-build measure intervals
        struct Interval {
            let start: Double
            let end: Double
            let duration: Double
            let beat: Beat
        }

        var intervals: [Interval] = []
        var curStart = 0.0
        var curBeat = defaultBeat

        // Keep track of time signature changes in directives
        let timeSigDirectives = timeline.directives.filter {
            if case .timeSignature = $0.kind { return true }
            return false
        }.sorted { $0.position < $1.position }

        var nextDirectiveIndex = 0

        while curStart < totalDuration || intervals.count < measureCount {
            while nextDirectiveIndex < timeSigDirectives.count,
                timeSigDirectives[nextDirectiveIndex].position <= curStart
            {
                if case .timeSignature(let b) = timeSigDirectives[nextDirectiveIndex].kind {
                    curBeat = b
                }
                nextDirectiveIndex += 1
            }
            let dur = Double(max(1, curBeat.count)) * 4.0 / Double(max(1, curBeat.noteValue))
            let curEnd = curStart + dur
            intervals.append(Interval(start: curStart, end: curEnd, duration: dur, beat: curBeat))
            curStart = curEnd
        }

        var measures: [Measure] = []

        for (mIdx, interval) in intervals.enumerated() {
            let mStart = interval.start
            let mEnd = interval.end
            let mDuration = interval.duration
            let mBeat = interval.beat

            let directivesInMeasure = timeline.directives.filter {
                $0.position >= mStart && $0.position < mEnd
            }

            // Find overlapping playback events
            var rawMeasureEvents: [MeasureEvent] = []
            for event in timeline.events {
                let evStart = event.position
                let evEnd = event.position + event.duration
                if evEnd <= mStart || evStart >= mEnd {
                    continue
                }

                let clStart = max(mStart, evStart)
                let clEnd = min(mEnd, evEnd)
                let clDur = clEnd - clStart
                if clDur <= 0 { continue }

                let isNote = event.content.isNote
                let tieStop = isNote && (evStart < mStart)
                let tieStart = isNote && (evEnd > mEnd)

                rawMeasureEvents.append(
                    MeasureEvent(
                        startOffset: clStart - mStart,
                        duration: clDur,
                        content: event.content,
                        tieStart: tieStart,
                        tieStop: tieStop,
                        state: event.state
                    ))
            }

            rawMeasureEvents.sort { $0.startOffset < $1.startOffset }

            // Fill gaps with rests to guarantee conservation of measure duration
            var paddedEvents: [MeasureEvent] = []
            var cursor = 0.0
            let state =
                rawMeasureEvents.first?.state
                ?? PlaybackState(
                    tempo: sheet.speed > 0 ? sheet.speed : 120,
                    keyOffset: sheet.keySignature.semitoneOffset,
                    timeSignature: mBeat
                )

            let epsilon = 1e-4
            for ev in rawMeasureEvents {
                let gap = ev.startOffset - cursor
                if gap > epsilon {
                    paddedEvents.append(
                        MeasureEvent(
                            startOffset: cursor,
                            duration: gap,
                            content: .rest,
                            state: state
                        ))
                }
                paddedEvents.append(ev)
                cursor = max(cursor, ev.startOffset + ev.duration)
            }

            let trailingGap = mDuration - cursor
            if trailingGap > epsilon {
                paddedEvents.append(
                    MeasureEvent(
                        startOffset: cursor,
                        duration: trailingGap,
                        content: .rest,
                        state: state
                    ))
            }

            measures.append(
                Measure(
                    index: mIdx,
                    startTime: mStart,
                    nominalDuration: mDuration,
                    timeSignature: mBeat,
                    tempo: state.tempo,
                    keyOffset: state.keyOffset,
                    events: paddedEvents,
                    directives: directivesInMeasure
                ))
        }

        return measures
    }
}
