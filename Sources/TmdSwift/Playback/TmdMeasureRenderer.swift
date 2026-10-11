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
    public static func renderMeasures(sheet inputSheet: Sheet, instrument: String) -> [Measure] {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let timeline = TmdPlaybackRenderer.render(sheet: sheet, instrument: instrument)
        let defaultBeat =
            sheet.beat.count > 0 && sheet.beat.noteValue > 0
            ? sheet.beat : Beat(count: 4, noteValue: 4)
        let totalDuration = timeline.duration

        // Pre-build unified score-level measure intervals
        struct Interval {
            let start: Double
            let end: Double
            let duration: Double
            let beat: Beat
        }

        var intervals: [Interval] = []
        var curStart = 0.0
        var curBeat = defaultBeat

        let timeSigDirectives = buildScoreTimeSignatures(sheet: sheet, defaultBeat: defaultBeat)
        var nextDirectiveIndex = 0

        while curStart < totalDuration - 1e-6 || intervals.isEmpty {
            while nextDirectiveIndex < timeSigDirectives.count,
                timeSigDirectives[nextDirectiveIndex].position <= curStart + 1e-6
            {
                curBeat = timeSigDirectives[nextDirectiveIndex].beat
                nextDirectiveIndex += 1
            }
            var dur = Double(max(1, curBeat.count)) * 4.0 / Double(max(1, curBeat.noteValue))
            var curEnd = curStart + dur
            if nextDirectiveIndex < timeSigDirectives.count {
                let nextPos = timeSigDirectives[nextDirectiveIndex].position
                if nextPos > curStart + 1e-6 && nextPos < curEnd - 1e-6 {
                    curEnd = nextPos
                    dur = curEnd - curStart
                }
            }
            intervals.append(Interval(start: curStart, end: curEnd, duration: dur, beat: curBeat))
            curStart = curEnd
        }

        var measures: [Measure] = []
        var activeState = PlaybackState(
            tempo: sheet.speed > 0 ? sheet.speed : 120,
            keyOffset: sheet.keySignature.semitoneOffset,
            timeSignature: defaultBeat
        )
        var prevMeasureBeat = defaultBeat

        for (mIdx, interval) in intervals.enumerated() {
            let mStart = interval.start
            let mEnd = interval.end
            let mDuration = interval.duration
            let mBeat = interval.beat

            let rawDirectivesInMeasure = timeline.directives.filter {
                $0.position >= mStart && $0.position < mEnd
            }

            let epsilon = 1e-4
            activeState = PlaybackState(
                tempo: activeState.tempo,
                keyOffset: activeState.keyOffset,
                timeSignature: mBeat,
                dynamicLevel: activeState.dynamicLevel
            )
            for dir in rawDirectivesInMeasure where dir.position <= mStart + epsilon {
                activeState = PlaybackState(
                    tempo: dir.state.tempo,
                    keyOffset: dir.state.keyOffset,
                    timeSignature: mBeat,
                    dynamicLevel: dir.state.dynamicLevel
                )
            }

            var directivesInMeasure = rawDirectivesInMeasure.filter {
                if case .timeSignature = $0.kind { return false }
                return true
            }
            if (mIdx == 0 && mBeat != defaultBeat) || (mIdx > 0 && mBeat != prevMeasureBeat) {
                directivesInMeasure.insert(
                    PlaybackDirectiveEvent(
                        position: mStart,
                        kind: .timeSignature(mBeat),
                        state: activeState
                    ),
                    at: 0
                )
            }
            prevMeasureBeat = mBeat

            // Find overlapping playback events (sounding events first, then non-overlapping rests)
            var rawMeasureEvents: [MeasureEvent] = []
            for event in timeline.events where event.content.isSounding {
                let evStart = event.position
                let evEnd = event.position + event.duration
                if evEnd <= mStart + 1e-6 || evStart >= mEnd - 1e-6 {
                    continue
                }

                let clStart = max(mStart, evStart)
                let clEnd = min(mEnd, evEnd)
                let clDur = clEnd - clStart
                if clDur <= 1e-6 { continue }

                let isNote = event.content.isNote
                let tieStop = isNote && (evStart < mStart - 1e-6)
                let tieStart = isNote && (evEnd > mEnd + 1e-6)

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

            for event in timeline.events where !event.content.isSounding {
                let evStart = event.position
                let evEnd = event.position + event.duration
                if evEnd <= mStart + 1e-6 || evStart >= mEnd - 1e-6 {
                    continue
                }

                let clStart = max(mStart, evStart)
                let clEnd = min(mEnd, evEnd)
                let clDur = clEnd - clStart
                if clDur <= 1e-6 { continue }

                let relStart = clStart - mStart
                let relEnd = relStart + clDur
                let overlapsExisting = rawMeasureEvents.contains { existing in
                    let exStart = existing.startOffset
                    let exEnd = exStart + existing.duration
                    return relStart < exEnd - epsilon && relEnd > exStart + epsilon
                }
                if !overlapsExisting {
                    rawMeasureEvents.append(
                        MeasureEvent(
                            startOffset: relStart,
                            duration: clDur,
                            content: event.content,
                            tieStart: false,
                            tieStop: false,
                            state: event.state
                        ))
                }
            }

            rawMeasureEvents.sort { $0.startOffset < $1.startOffset }
            let hasChordEvent = rawMeasureEvents.contains {
                if case .chord = $0.content { return true }
                return false
            }
            if !hasChordEvent {
                for i in rawMeasureEvents.indices {
                    let ev = rawMeasureEvents[i]
                    if let nextEv = rawMeasureEvents[(i + 1)...].first(where: {
                        $0.startOffset > ev.startOffset + epsilon
                    }) {
                        let maxDur = nextEv.startOffset - ev.startOffset
                        if ev.duration > maxDur + epsilon {
                            rawMeasureEvents[i] = MeasureEvent(
                                startOffset: ev.startOffset,
                                duration: maxDur,
                                content: ev.content,
                                tieStart: false,
                                tieStop: ev.tieStop,
                                state: ev.state
                            )
                        }
                    }
                }
            }

            // Fill gaps with rests to guarantee conservation of measure duration
            var paddedEvents: [MeasureEvent] = []
            var cursor = 0.0
            let state =
                (rawMeasureEvents.first.map { $0.startOffset <= epsilon } ?? false)
                ? rawMeasureEvents.first!.state : activeState

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

            if let lastEvent = rawMeasureEvents.last {
                activeState = lastEvent.state
            }
            if let lastDirective = rawDirectivesInMeasure.last {
                let lastEventPos = rawMeasureEvents.last.map { mStart + $0.startOffset } ?? -1.0
                if lastDirective.position >= lastEventPos - epsilon {
                    activeState = lastDirective.state
                }
            }
            activeState = PlaybackState(
                tempo: activeState.tempo,
                keyOffset: activeState.keyOffset,
                timeSignature: mBeat,
                dynamicLevel: activeState.dynamicLevel
            )
        }

        return measures
    }

    /// Builds a unified score-level time signature schedule across all playback sections.
    private static func buildScoreTimeSignatures(
        sheet: Sheet,
        defaultBeat: Beat
    ) -> [(position: Double, beat: Beat)] {
        let orders = sheet.effectivePlaybackOrders
        let globalMin = TmdPlaybackRenderer.globalEarliestPosition(in: sheet)
        let offset = globalMin < 0.0 ? -globalMin : 0.0
        var schedule: [(position: Double, beat: Beat)] = []

        func upsertTimeSignature(at position: Double, beat: Beat) {
            if let idx = schedule.firstIndex(where: { abs($0.position - position) < 1e-4 }) {
                schedule[idx] = (position: position, beat: beat)
            } else {
                schedule.append((position: position, beat: beat))
                schedule.sort { $0.position < $1.position }
            }
        }

        var sectionStart = 0.0
        var currentBeat = defaultBeat

        // If the first section has a negative-start pickup before timelinePosition 0, adopt its initial beat at 0.0
        if offset > 0 {
            for order in orders {
                if case .name(let firstSecName) = order {
                    let matching = sheet.entries.filter {
                        $0.name == firstSecName && !$0.isPrototype && $0.start < 0
                    }
                    if let firstPickup = matching.first {
                        let b = TmdPlaybackRenderer.entryInitialBeat(
                            for: firstPickup, in: sheet, fallback: defaultBeat)
                        upsertTimeSignature(at: 0.0, beat: b)
                        currentBeat = b
                    }
                    break
                }
            }
        }

        for order in orders {
            guard case .name(let secName) = order else { continue }
            let secDur = TmdPlaybackRenderer.duration(of: secName, in: sheet, beat: currentBeat)
            let sectionEnd = sectionStart + secDur
            let matching = sheet.entries.filter { $0.name == secName && !$0.isPrototype }
            guard !matching.isEmpty else {
                sectionStart = sectionEnd
                continue
            }

            var interiorByPos: [(position: Double, beats: [Beat])] = []
            var trailingBeats: [Beat] = []

            for paragraph in matching {
                let entryBeat = TmdPlaybackRenderer.entryInitialBeat(
                    for: paragraph, in: sheet, fallback: currentBeat)
                let pStart =
                    sectionStart + Double(paragraph.start)
                    * TmdPlaybackRenderer.measureDuration(for: entryBeat)
                let minPos = (paragraph.start < 0 && sectionStart > 0) ? sectionStart : pStart
                var pos = pStart

                for section in paragraph.sections {
                    let unitDur = 4.0 / Double(max(1, section.noteLength))
                    let totalUnits = section.unitGroups.reduce(0) { $0 + max(0, $1.length) }
                    for dir in section.directives {
                        if case .timeSignature(let b) = dir.kind {
                            let rawPos = pos + Double(max(0, dir.position)) * unitDur
                            let effectivePos = max(rawPos, minPos)
                            let shiftedPos = effectivePos + offset
                            let isTrailing =
                                dir.position >= totalUnits && effectivePos >= sectionEnd - 1e-6
                            if isTrailing {
                                if !trailingBeats.contains(b) {
                                    trailingBeats.append(b)
                                }
                            } else {
                                if let idx = interiorByPos.firstIndex(where: {
                                    abs($0.position - shiftedPos) < 1e-4
                                }) {
                                    if !interiorByPos[idx].beats.contains(b) {
                                        interiorByPos[idx].beats.append(b)
                                    }
                                } else {
                                    interiorByPos.append((position: shiftedPos, beats: [b]))
                                }
                            }
                        }
                    }
                    pos += Double(totalUnits) * unitDur
                }
            }

            interiorByPos.sort { $0.position < $1.position }
            for group in interiorByPos {
                let remDur = max(0.0, (sectionEnd + offset) - group.position)
                let chosen = selectConductorBeat(from: group.beats, sectionDuration: remDur)
                upsertTimeSignature(at: group.position, beat: chosen)
                currentBeat = chosen
            }

            if !trailingBeats.isEmpty {
                let chosenTrailing = trailingBeats[0]
                upsertTimeSignature(at: sectionEnd + offset, beat: chosenTrailing)
                currentBeat = chosenTrailing
            }

            sectionStart = sectionEnd
        }

        return schedule
    }

    /// Selects the common conductor time signature when multiple distinct meters occur simultaneously.
    private static func selectConductorBeat(
        from candidates: [Beat],
        sectionDuration: Double
    ) -> Beat {
        guard let first = candidates.first else {
            return Beat(count: 4, noteValue: 4)
        }
        guard candidates.count > 1 else {
            return first
        }
        let divisible = candidates.filter { b in
            let dur = TmdPlaybackRenderer.measureDuration(for: b)
            guard dur > 1e-6 && sectionDuration > 1e-4 else { return false }
            let bars = sectionDuration / dur
            return abs(bars.rounded() - bars) < 1e-3 && bars.rounded() >= 1.0
        }
        let pool = divisible.isEmpty ? candidates : divisible

        func rank(_ b: Beat) -> (Int, Double, Double) {
            let tier: Int
            if b.noteValue == 4 && (2...6).contains(b.count) {
                tier = 0
            } else if b.noteValue == 8 && (3...12).contains(b.count) {
                tier = 1
            } else if b.noteValue == 2 && (2...4).contains(b.count) {
                tier = 2
            } else {
                tier = 3
            }
            let dur = TmdPlaybackRenderer.measureDuration(for: b)
            return (tier, abs(dur - 4.0), -dur)
        }

        return pool.min { rank($0) < rank($1) } ?? first
    }
}
