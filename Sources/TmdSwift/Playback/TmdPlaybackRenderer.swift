import Foundation

/// A format-independent musical item produced from a TMD score.
public enum PlaybackContent: Equatable, Sendable {
    case note(Note)
    case chord(ChordSymbol)
    case rest
    case percussion(String)

    /// Whether this event produces audible sound (as opposed to `.rest`).
    public var isSounding: Bool {
        switch self {
        case .note, .chord, .percussion: true
        case .rest: false
        }
    }

    /// Whether this event is a single pitched `.note`.
    public var isNote: Bool {
        switch self {
        case .note: true
        default: false
        }
    }
}

/// The playback state effective at a point on the timeline.
public struct PlaybackState: Equatable, Sendable {
    public let tempo: Double
    public let keyOffset: Int
    public let timeSignature: Beat
    public let dynamicLevel: DynamicMark

    public init(tempo: Double, keyOffset: Int, timeSignature: Beat, dynamicLevel: DynamicMark = .mf)
    {
        self.tempo = tempo
        self.keyOffset = keyOffset
        self.timeSignature = timeSignature
        self.dynamicLevel = dynamicLevel
    }
}

/// A musical event expressed in quarter-note units.
public struct PlaybackEvent: Equatable, Sendable {
    public let position: Double
    public let duration: Double
    public let content: PlaybackContent
    public let state: PlaybackState
}

/// A directive applied at an absolute position on the playback timeline.
public struct PlaybackDirectiveEvent: Equatable, Sendable {
    public let position: Double
    public let kind: SectionDirectiveKind
    public let state: PlaybackState
}

/// One assignment's ordered playback material.
public struct PlaybackTrack: Equatable, Sendable {
    public let assignment: String
    public let events: [PlaybackEvent]
    public let directives: [PlaybackDirectiveEvent]
    public let duration: Double
}

/// The common timeline consumed by format-specific exporters.
public struct PlaybackTimeline: Equatable, Sendable {
    public let events: [PlaybackEvent]
    public let directives: [PlaybackDirectiveEvent]
    public let duration: Double
    public let assignment: String?

    public var track: PlaybackTrack? {
        guard let assignment else { return nil }
        return PlaybackTrack(
            assignment: assignment, events: events, directives: directives, duration: duration)
    }

    public init(
        events: [PlaybackEvent], directives: [PlaybackDirectiveEvent], duration: Double,
        assignment: String? = nil
    ) {
        self.events = events
        self.directives = directives
        self.duration = duration
        self.assignment = assignment
    }

    /// Returns timeline events with simultaneous `.note` events collapsed to the highest-pitched note,
    /// suitable for monophonic singing-synthesizer exporters (VSQ, VSQX, UST).
    public func monophonicEvents() -> [PlaybackEvent] {
        var result: [PlaybackEvent] = []
        var i = 0
        while i < events.count {
            let ev = events[i]
            if case .note(let note) = ev.content {
                var bestEvent = ev
                var bestPitch = note.midiPitch(keyOffset: ev.state.keyOffset)
                var j = i + 1
                while j < events.count && abs(events[j].position - ev.position) < 1e-4 {
                    let nextEv = events[j]
                    if case .note(let nextNote) = nextEv.content {
                        let p = nextNote.midiPitch(keyOffset: nextEv.state.keyOffset)
                        if p > bestPitch {
                            bestPitch = p
                            bestEvent = nextEv
                        }
                    }
                    j += 1
                }
                result.append(bestEvent)
                i = j
            } else {
                result.append(ev)
                i += 1
            }
        }
        return result
    }
}

/// A semantic playback issue found before target-specific rendering.
public struct PlaybackValidationIssue: Equatable, Sendable, CustomStringConvertible {
    public let sectionName: String
    public let assignment: String
    public let firstOffset: Int
    public let secondOffset: Int

    public var description: String {
        "Overlapping entries for assignment \(assignment) in section \(sectionName) at offsets \(firstOffset) and \(secondOffset)"
    }
}

public struct PlaybackTempoConflict: Equatable, Sendable {
    public let position: Double
    public let tempos: [Double]
}

/// A contiguous segment of uniform tempo and time signature on the playback timeline.
public struct TempoSegment: Equatable, Sendable {
    public var quarterStart: Double
    public var secondStart: Double
    public var bpm: Double
    public var timeSignature: Beat

    public init(quarterStart: Double, secondStart: Double, bpm: Double, timeSignature: Beat) {
        self.quarterStart = quarterStart
        self.secondStart = secondStart
        self.bpm = bpm
        self.timeSignature = timeSignature
    }
}

/// Expands immutable TMD AST data into a shared playback timeline.
public enum TmdPlaybackRenderer {
    private struct PlaybackOrderCursor {
        var state: PlaybackState
        var timelinePosition = 0.0

        init(sheet: Sheet) {
            state = initialState(for: sheet)
        }

        mutating func visit(_ order: Playback) -> String? {
            switch order {
            case .relative(let value):
                if let delta = Int(value.replacingOccurrences(of: "+", with: "")) {
                    state = PlaybackState(
                        tempo: state.tempo, keyOffset: state.keyOffset + delta,
                        timeSignature: state.timeSignature, dynamicLevel: state.dynamicLevel)
                }
                return nil
            case .absolute(let value):
                state = PlaybackState(
                    tempo: state.tempo, keyOffset: KeySignature(string: value).semitoneOffset,
                    timeSignature: state.timeSignature, dynamicLevel: state.dynamicLevel)
                return nil
            case .name(let name):
                return name
            case .macro:
                return nil
            }
        }

        mutating func advance(by duration: Double) {
            timelinePosition += duration
        }
    }

    private static func orders(for sheet: Sheet) -> [Playback] {
        sheet.effectivePlaybackOrders
    }

    /// Builds piece-wise linear tempo segments from conductor directives.
    public static func buildTempoSegments(
        initialTempo: Double,
        initialBeat: Beat = Beat(),
        directives: [PlaybackDirectiveEvent]
    ) -> [TempoSegment] {
        let startBpm = initialTempo > 0 ? initialTempo : 120.0
        var segments: [TempoSegment] = [
            TempoSegment(
                quarterStart: 0,
                secondStart: 0,
                bpm: startBpm,
                timeSignature: initialBeat
            )
        ]
        let sortedDirectives = directives.sorted { $0.position < $1.position }
        for directive in sortedDirectives {
            let affectsTempoOrMeter: Bool = switch directive.kind {
            case .tempo, .relativeTempo, .timeSignature: true
            case .dynamics, .absoluteKey, .explicitKey, .relativeKey, .fixedPitch: false
            }
            guard affectsTempoOrMeter else { continue }
            let last = segments[segments.count - 1]
            if directive.position > last.quarterStart {
                let deltaQuarters = directive.position - last.quarterStart
                let deltaSeconds = deltaQuarters * (60.0 / last.bpm)
                let secondStart = last.secondStart + deltaSeconds
                segments.append(
                    TempoSegment(
                        quarterStart: directive.position,
                        secondStart: secondStart,
                        bpm: directive.state.tempo,
                        timeSignature: directive.state.timeSignature
                    )
                )
            } else if directive.position == last.quarterStart {
                segments[segments.count - 1].bpm = directive.state.tempo
                segments[segments.count - 1].timeSignature = directive.state.timeSignature
            }
        }
        return segments
    }

    /// Converts a quarter-note position into elapsed seconds using piece-wise tempo segments.
    public static func quarterToSeconds(_ quarter: Double, segments: [TempoSegment]) -> Double {
        if quarter <= 0 || segments.isEmpty { return 0 }
        var seg = segments[0]
        for s in segments.reversed() where quarter >= s.quarterStart {
            seg = s
            break
        }
        let deltaQuarters = quarter - seg.quarterStart
        return seg.secondStart + deltaQuarters * (60.0 / seg.bpm)
    }

    private static func initialState(for sheet: Sheet) -> PlaybackState {
        PlaybackState(
            tempo: sheet.speed > 0 ? sheet.speed : 120,
            keyOffset: sheet.keySignature.semitoneOffset,
            timeSignature: sheet.beat
        )
    }

    /// Finds different absolute tempo values declared at the same playback position.
    public static func validateTempoConflicts(sheet: Sheet) -> [PlaybackTempoConflict] {
        var directives: [PlaybackDirectiveEvent] = []
        for assignment in sheet.distinctAssignments() {
            directives.append(contentsOf: render(sheet: sheet, instrument: assignment).directives)
        }
        let grouped = Dictionary(grouping: directives) { $0.position }
        return grouped.compactMap { position, values in
            let tempos = Array(
                Set(
                    values.compactMap { directive -> Double? in
                        if case .tempo(let value) = directive.kind { return value }
                        return nil
                    })
            ).sorted()
            guard tempos.count > 1 else { return nil }
            return PlaybackTempoConflict(position: position, tempos: tempos)
        }.sorted { $0.position < $1.position }
    }

    /// Validates source entries that will be assembled into the same assignment track.
    /// Entries may be adjacent; only their occupied measure ranges may not overlap.
    public static func validate(sheet: Sheet) -> [PlaybackValidationIssue] {
        let grouped = Dictionary(grouping: sheet.entries.filter { !$0.isPrototype }) {
            "\($0.name.lowercased())\u{0}\($0.assignment!.lowercased())"
        }
        var issues: [PlaybackValidationIssue] = []
        for entries in grouped.values {
            for index in entries.indices {
                for otherIndex in entries.index(after: index)..<entries.endIndex {
                    let first = entries[index]
                    let second = entries[otherIndex]
                    let firstRange = range(of: first, beat: sheet.beat)
                    let secondRange = range(of: second, beat: sheet.beat)
                    if max(firstRange.lowerBound, secondRange.lowerBound)
                        < min(firstRange.upperBound, secondRange.upperBound)
                    {
                        issues.append(
                            PlaybackValidationIssue(
                                sectionName: first.name,
                                assignment: first.assignment ?? "",
                                firstOffset: first.start,
                                secondOffset: second.start
                            ))
                    }
                }
            }
        }
        return issues
    }

    private static func range(of entry: Entry, beat: Beat) -> Range<Double> {
        let duration = entry.sections.reduce(0.0) { total, section in
            let unitDuration = 4.0 / Double(max(1, section.noteLength))
            return total
                + section.unitGroups.reduce(0.0) { $0 + Double(max(0, $1.length)) * unitDuration }
        }
        let start = Double(entry.start) * measureDuration(for: beat)
        return start..<start + duration
    }

    /// Renders one instrument's playback sequence in quarter-note units.
    public static func render(sheet inputSheet: Sheet, instrument: String) -> PlaybackTimeline {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let paragraphs = sheet.entries.filter {
            $0.assignment?.caseInsensitiveCompare(instrument) == .orderedSame
        }
        let orders = orders(for: sheet)
        var cursor = PlaybackOrderCursor(sheet: sheet)
        var events: [PlaybackEvent] = []
        var directives: [PlaybackDirectiveEvent] = []

        for order in orders {
            guard let name = cursor.visit(order) else { continue }
                let matchingParagraphs = paragraphs.filter { $0.name == name }
                let paragraphDuration = duration(of: name, in: sheet, beat: cursor.state.timeSignature)
                guard !matchingParagraphs.isEmpty else {
                    cursor.advance(by: paragraphDuration)
                    continue
                }

                for paragraph in matchingParagraphs {
                    let start =
                        cursor.timelinePosition + Double(paragraph.start)
                        * measureDuration(for: cursor.state.timeSignature)
                    let paragraphState =
                        paragraph.pitchMode == .fixed
                        ? PlaybackState(
                            tempo: cursor.state.tempo, keyOffset: 0, timeSignature: cursor.state.timeSignature,
                            dynamicLevel: cursor.state.dynamicLevel)
                        : cursor.state
                    let rendered = render(
                        paragraph: paragraph,
                        start: start,
                        state: paragraphState,
                        fixedPitch: paragraph.pitchMode == .fixed
                    )
                    events.append(contentsOf: rendered.events)
                    directives.append(contentsOf: rendered.directives)
                    cursor.state = PlaybackState(
                        tempo: rendered.state.tempo,
                        keyOffset: paragraph.pitchMode == .fixed
                            ? cursor.state.keyOffset : rendered.state.keyOffset,
                        timeSignature: cursor.state.timeSignature,
                        dynamicLevel: rendered.state.dynamicLevel
                    )
                }
                cursor.advance(by: paragraphDuration)
        }

        // Shift the entire timeline forward so that the earliest event across all instruments in the score
        // starts at exactly position 0.0, preserving inter-instrument entrance relationships.
        let globalMin = globalEarliestPosition(in: sheet)
        let minEventPosition = events.map(\.position).min() ?? 0.0
        let minDirectivePosition = directives.map(\.position).min() ?? 0.0
        let localMin = min(minEventPosition, minDirectivePosition)
        let earliestPosition = min(globalMin, localMin)
        let offset = earliestPosition < 0.0 ? -earliestPosition : 0.0

        let adjustedEvents = events.map { event in
            PlaybackEvent(
                position: event.position + offset,
                duration: event.duration,
                content: event.content,
                state: event.state
            )
        }
        let adjustedDirectives = directives.map { directive in
            PlaybackDirectiveEvent(
                position: directive.position + offset,
                kind: directive.kind,
                state: directive.state
            )
        }

        return PlaybackTimeline(
            events: adjustedEvents.sorted { $0.position < $1.position },
            directives: adjustedDirectives.sorted { $0.position < $1.position },
            duration: cursor.timelinePosition + offset,
            assignment: paragraphs.first?.assignment ?? instrument
        )
    }

    /// Renders the score-level conductor timeline by merging directives from every concrete instrument.
    public static func renderConductor(sheet inputSheet: Sheet) -> PlaybackTimeline {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let instruments = sheet.distinctInstruments(fallbackToDefault: false)
        let sourceTimelines = instruments.map { render(sheet: sheet, instrument: $0) }
        var merged: [PlaybackDirectiveEvent] = []

        for timeline in sourceTimelines {
            for directive in timeline.directives.sorted(by: { $0.position < $1.position }) {
                if merged.contains(where: {
                    $0.position == directive.position && $0.kind == directive.kind
                }) {
                    continue
                }
                merged.append(directive)
            }
        }

        var state = initialState(for: sheet)
        let directives = merged.enumerated()
            .sorted {
                $0.element.position == $1.element.position
                    ? $0.offset < $1.offset
                    : $0.element.position < $1.element.position
            }
            .map(\.element)
            .map { directive in
                state = directive.kind.applied(to: state)
                return PlaybackDirectiveEvent(
                    position: directive.position, kind: directive.kind, state: state)
            }

        return PlaybackTimeline(
            events: [],
            directives: directives,
            duration: sourceTimelines.map(\.duration).max() ?? 0
        )
    }

    private static func render(
        paragraph: Entry,
        start: Double,
        state initialState: PlaybackState,
        fixedPitch: Bool
    ) -> (
        events: [PlaybackEvent], directives: [PlaybackDirectiveEvent], state: PlaybackState,
        duration: Double
    ) {
        var state = initialState
        var events: [PlaybackEvent] = []
        var directives: [PlaybackDirectiveEvent] = []
        var position = start

        for section in paragraph.sections {
            let unitDuration = 4.0 / Double(max(1, section.noteLength))
            let sortedDirectives = section.directives.sorted { $0.position < $1.position }
            var directiveIndex = 0
            var sectionPosition = 0

            for group in section.unitGroups {
                while directiveIndex < sortedDirectives.count,
                    sortedDirectives[directiveIndex].position <= sectionPosition
                {
                    let directive = sortedDirectives[directiveIndex]
                    state = directive.kind.applied(to: state, fixedPitch: fixedPitch)
                    directives.append(
                        PlaybackDirectiveEvent(
                            position: position,
                            kind: directive.kind,
                            state: state
                        ))
                    directiveIndex += 1
                }

                let groupDuration = Double(max(0, group.length)) * unitDuration
                let activeUnits = group.units.filter { $0 != .tie }

                if activeUnits.isEmpty {
                    // All units in group are ties
                    if !events.isEmpty {
                        // Extend the duration of the most recent note(s) or chord
                        // If multiple events occurred at the same position, extend all of them (e.g. multiNote)
                        let lastPos = events.last!.position
                        var i = events.count - 1
                        while i >= 0 && abs(events[i].position - lastPos) < 1e-6 {
                            let ev = events[i]
                            events[i] = PlaybackEvent(
                                position: ev.position,
                                duration: ev.duration + groupDuration,
                                content: ev.content,
                                state: ev.state
                            )
                            i -= 1
                        }
                    } else {
                        // Leading tie with no preceding note acts as rest
                        events.append(
                            PlaybackEvent(
                                position: position, duration: groupDuration, content: .rest,
                                state: state))
                    }
                } else {
                    let baseSlotDuration = groupDuration / Double(max(1, group.units.count))
                    var currentEventIndices: [Int] = []

                    for (idx, unit) in group.units.enumerated() {
                        if unit == .tie {
                            if !currentEventIndices.isEmpty {
                                for evIdx in currentEventIndices {
                                    let ev = events[evIdx]
                                    events[evIdx] = PlaybackEvent(
                                        position: ev.position,
                                        duration: ev.duration + baseSlotDuration,
                                        content: ev.content,
                                        state: ev.state
                                    )
                                }
                            } else if !events.isEmpty {
                                let lastPos = events.last!.position
                                var extendedIndices: [Int] = []
                                var i = events.count - 1
                                while i >= 0 && abs(events[i].position - lastPos) < 1e-6 {
                                    let ev = events[i]
                                    events[i] = PlaybackEvent(
                                        position: ev.position,
                                        duration: ev.duration + baseSlotDuration,
                                        content: ev.content,
                                        state: ev.state
                                    )
                                    extendedIndices.append(i)
                                    i -= 1
                                }
                                currentEventIndices = extendedIndices
                            } else {
                                events.append(
                                    PlaybackEvent(
                                        position: position + Double(idx) * baseSlotDuration,
                                        duration: baseSlotDuration,
                                        content: .rest,
                                        state: state
                                    ))
                                currentEventIndices = [events.count - 1]
                            }
                        } else {
                            let slotPosition = position + Double(idx) * baseSlotDuration
                            var newIndices: [Int] = []
                            switch unit {
                            case .multiNote(let notes):
                                for note in notes {
                                    events.append(
                                        PlaybackEvent(
                                            position: slotPosition,
                                            duration: baseSlotDuration,
                                            content: .note(note),
                                            state: state
                                        ))
                                    newIndices.append(events.count - 1)
                                }
                            default:
                                if let content = unit.playbackContent {
                                    events.append(
                                        PlaybackEvent(
                                            position: slotPosition,
                                            duration: baseSlotDuration,
                                            content: content,
                                            state: state
                                        ))
                                    newIndices.append(events.count - 1)
                                }
                            }
                            currentEventIndices = newIndices
                        }
                    }
                }
                position += groupDuration
                sectionPosition += group.length
            }

            while directiveIndex < sortedDirectives.count {
                let directive = sortedDirectives[directiveIndex]
                state = directive.kind.applied(to: state)
                directives.append(
                    PlaybackDirectiveEvent(position: position, kind: directive.kind, state: state))
                directiveIndex += 1
            }
        }

        return (events, directives, state, position - start)
    }

    /// Calculates total quarter-note duration of a section/paragraph name in a sheet,
    /// measured from the section's downbeat anchor (measure 0) to the latest ending note.
    public static func duration(of name: String, in sheet: Sheet, beat: Beat? = nil) -> Double {
        let effectiveBeat = beat ?? sheet.beat
        let matching = sheet.entries.filter { $0.name == name }
        guard !matching.isEmpty else { return 0.0 }

        let ends = matching.map { paragraph in
            let startBeats = Double(paragraph.start) * measureDuration(for: effectiveBeat)
            let noteDuration = paragraph.sections.reduce(0.0) { total, section in
                let unitDuration = 4.0 / Double(max(1, section.noteLength))
                return total
                    + section.unitGroups.reduce(0.0) {
                        $0 + Double(max(0, $1.length)) * unitDuration
                    }
            }
            return startBeats + noteDuration
        }
        return max(0.0, ends.max() ?? 0.0)
    }

    /// Calculates measure duration in quarter notes for a given beat signature.
    public static func measureDuration(for beat: Beat) -> Double {
        Double(max(1, beat.count)) * 4.0 / Double(max(1, beat.noteValue))
    }

    /// Calculates the global negative offset across all instruments in the score orders,
    /// ensuring all tracks share the exact same temporal alignment.
    public static func globalEarliestPosition(in inputSheet: Sheet) -> Double {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let orders = orders(for: sheet)
        var cursor = PlaybackOrderCursor(sheet: sheet)
        var minPosition = 0.0

        for order in orders {
            guard let name = cursor.visit(order) else { continue }
                let matchingParagraphs = sheet.entries.filter { $0.name == name }
                let paragraphDuration = duration(of: name, in: sheet, beat: cursor.state.timeSignature)
                for paragraph in matchingParagraphs {
                    let start =
                        cursor.timelinePosition + Double(paragraph.start)
                        * measureDuration(for: cursor.state.timeSignature)
                    if start < minPosition {
                        minPosition = start
                    }
                }
                cursor.advance(by: paragraphDuration)
        }
        return minPosition
    }
}

private extension Unit {
    var playbackContent: PlaybackContent? {
        switch self {
        case .note(let note): .note(note)
        case .chord(let chord): .chord(chord)
        case .rest: .rest
        case .percussion(let pattern): .percussion(pattern)
        case .multiNote, .tie: nil
        }
    }
}

private extension SectionDirectiveKind {
    func applied(to state: PlaybackState, fixedPitch: Bool = false) -> PlaybackState {
        if fixedPitch {
            switch self {
            case .absoluteKey, .relativeKey, .fixedPitch:
                return state
            default:
                break
            }
        }
        return switch self {
        case .tempo(let value):
            PlaybackState(
                tempo: max(1, value), keyOffset: state.keyOffset,
                timeSignature: state.timeSignature, dynamicLevel: state.dynamicLevel)
        case .relativeTempo(let value):
            PlaybackState(
                tempo: max(1, state.tempo + value), keyOffset: state.keyOffset,
                timeSignature: state.timeSignature, dynamicLevel: state.dynamicLevel)
        case .absoluteKey(let value):
            PlaybackState(
                tempo: state.tempo, keyOffset: KeySignature(string: value).semitoneOffset,
                timeSignature: state.timeSignature, dynamicLevel: state.dynamicLevel)
        case .relativeKey(let value):
            PlaybackState(
                tempo: state.tempo, keyOffset: state.keyOffset + value,
                timeSignature: state.timeSignature, dynamicLevel: state.dynamicLevel)
        case .explicitKey:
            // `key=` is notation metadata only. Unlike `?=` and relative
            // movable-do directives, it must not alter the sounding pitch
            // context.
            state
        case .dynamics(let mark):
            PlaybackState(
                tempo: state.tempo, keyOffset: state.keyOffset, timeSignature: state.timeSignature,
                dynamicLevel: mark)
        case .fixedPitch:
            PlaybackState(
                tempo: state.tempo, keyOffset: 0, timeSignature: state.timeSignature,
                dynamicLevel: state.dynamicLevel)
        case .timeSignature(let beat):
            PlaybackState(
                tempo: state.tempo, keyOffset: state.keyOffset, timeSignature: beat,
                dynamicLevel: state.dynamicLevel)
        }
    }
}
