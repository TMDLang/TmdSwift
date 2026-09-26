import Foundation

/// A format-independent musical item produced from a TMD score.
public enum PlaybackContent: Equatable, Sendable {
    case note(Note)
    case chord(ChordSymbol)
    case rest
    case percussion(String)
}

/// The playback state effective at a point on the timeline.
public struct PlaybackState: Equatable, Sendable {
    public let tempo: Double
    public let keyOffset: Int
    public let timeSignature: Beat
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

/// The common timeline consumed by format-specific exporters.
public struct PlaybackTimeline: Equatable, Sendable {
    public let events: [PlaybackEvent]
    public let directives: [PlaybackDirectiveEvent]
    public let duration: Double
}

/// Expands immutable TMD AST data into a shared playback timeline.
public enum TMDPlaybackRenderer {
    /// Renders one instrument's playback sequence in quarter-note units.
    public static func render(sheet inputSheet: Sheet, instrument: String) -> PlaybackTimeline {
        let sheet = TMDMacroEvaluator.expand(inputSheet)
        let paragraphs = sheet.paragraphs.filter { $0.instrument == instrument }
        let orders = sheet.orders.isEmpty
            ? sheet.paragraphs.map(\.name).reduce(into: [String]()) { names, name in
                if !names.contains(name) { names.append(name) }
            }.map(Order.name)
            : sheet.orders
        var state = PlaybackState(
            tempo: sheet.speed > 0 ? sheet.speed : 120,
            keyOffset: sheet.keySignature.semitoneOffset,
            timeSignature: sheet.beat
        )
        var events: [PlaybackEvent] = []
        var directives: [PlaybackDirectiveEvent] = []
        var timelinePosition = 0.0

        for order in orders {
            switch order {
            case .relative(let value):
                if let delta = Int(value.replacingOccurrences(of: "+", with: "")) {
                    state = PlaybackState(tempo: state.tempo, keyOffset: state.keyOffset + delta, timeSignature: state.timeSignature)
                }
            case .absolute(let value):
                let keyOffset = KeySignature(string: value).semitoneOffset
                state = PlaybackState(tempo: state.tempo, keyOffset: keyOffset, timeSignature: state.timeSignature)
            case .name(let name):
                let matchingParagraphs = paragraphs.filter { $0.name == name }
                let paragraphDuration = duration(of: name, in: sheet, beat: state.timeSignature)
                guard !matchingParagraphs.isEmpty else {
                    timelinePosition += paragraphDuration
                    continue
                }

                for paragraph in matchingParagraphs {
                    let start = timelinePosition + Double(paragraph.start) * measureDuration(for: state.timeSignature)
                    let rendered = render(
                        paragraph: paragraph,
                        start: start,
                        state: state
                    )
                    events.append(contentsOf: rendered.events)
                    directives.append(contentsOf: rendered.directives)
                    state = rendered.state
                }
                timelinePosition += paragraphDuration
            case .macro:
                // S-expression macros are desugared by TMDMacroEvaluator before rendering
                break
            }
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
            duration: timelinePosition + offset
        )
    }

    /// Renders the score-level conductor timeline by merging directives from every concrete instrument.
    public static func renderConductor(sheet inputSheet: Sheet) -> PlaybackTimeline {
        let sheet = TMDMacroEvaluator.expand(inputSheet)
        let instruments = sheet.distinctInstruments(fallbackToDefault: false)
        let sourceTimelines = instruments.map { render(sheet: sheet, instrument: $0) }
        var merged: [PlaybackDirectiveEvent] = []

        for timeline in sourceTimelines {
            for directive in timeline.directives.sorted(by: { $0.position < $1.position }) {
                if merged.contains(where: { $0.position == directive.position && $0.kind == directive.kind }) {
                    continue
                }
                merged.append(directive)
            }
        }

        let initialState = PlaybackState(
            tempo: sheet.speed > 0 ? sheet.speed : 120,
            keyOffset: sheet.keySignature.semitoneOffset,
            timeSignature: sheet.beat
        )
        var state = initialState
        let directives = merged.enumerated()
            .sorted {
                $0.element.position == $1.element.position
                    ? $0.offset < $1.offset
                    : $0.element.position < $1.element.position
            }
            .map(\.element)
            .map { directive in
                state = apply(directive.kind, to: state)
                return PlaybackDirectiveEvent(position: directive.position, kind: directive.kind, state: state)
            }

        return PlaybackTimeline(
            events: [],
            directives: directives,
            duration: sourceTimelines.map(\.duration).max() ?? 0
        )
    }

    private static func render(
        paragraph: Paragraph,
        start: Double,
        state initialState: PlaybackState
    ) -> (events: [PlaybackEvent], directives: [PlaybackDirectiveEvent], state: PlaybackState, duration: Double) {
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
                      sortedDirectives[directiveIndex].position <= sectionPosition {
                    let directive = sortedDirectives[directiveIndex]
                    state = apply(directive.kind, to: state)
                    directives.append(PlaybackDirectiveEvent(
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
                        events.append(PlaybackEvent(position: position, duration: groupDuration, content: .rest, state: state))
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
                                events.append(PlaybackEvent(
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
                                    events.append(PlaybackEvent(
                                        position: slotPosition,
                                        duration: baseSlotDuration,
                                        content: .note(note),
                                        state: state
                                    ))
                                    newIndices.append(events.count - 1)
                                }
                            default:
                                if let content = content(of: unit) {
                                    events.append(PlaybackEvent(
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
                state = apply(directive.kind, to: state)
                directives.append(PlaybackDirectiveEvent(position: position, kind: directive.kind, state: state))
                directiveIndex += 1
            }
        }

        return (events, directives, state, position - start)
    }

    private static func content(of unit: Unit) -> PlaybackContent? {
        switch unit {
        case .note(let note): .note(note)
        case .chord(let chord): .chord(chord)
        case .rest: .rest
        case .percussion(let pattern): .percussion(pattern)
        case .multiNote: nil
        case .tie: nil
        }
    }

    private static func apply(_ kind: SectionDirectiveKind, to state: PlaybackState) -> PlaybackState {
        switch kind {
        case .tempo(let value):
            PlaybackState(tempo: max(1, value), keyOffset: state.keyOffset, timeSignature: state.timeSignature)
        case .relativeTempo(let value):
            PlaybackState(tempo: max(1, state.tempo + value), keyOffset: state.keyOffset, timeSignature: state.timeSignature)
        case .absoluteKey(let value):
            PlaybackState(tempo: state.tempo, keyOffset: KeySignature(string: value).semitoneOffset, timeSignature: state.timeSignature)
        case .relativeKey(let value):
            PlaybackState(tempo: state.tempo, keyOffset: state.keyOffset + value, timeSignature: state.timeSignature)
        case .fixedPitch:
            PlaybackState(tempo: state.tempo, keyOffset: 0, timeSignature: state.timeSignature)
        case .timeSignature(let beat):
            PlaybackState(tempo: state.tempo, keyOffset: state.keyOffset, timeSignature: beat)
        }
    }

    /// Calculates total quarter-note duration of a section/paragraph name in a sheet,
    /// measured from the section's downbeat anchor (measure 0) to the latest ending note.
    public static func duration(of name: String, in sheet: Sheet, beat: Beat? = nil) -> Double {
        let effectiveBeat = beat ?? sheet.beat
        let matching = sheet.paragraphs.filter { $0.name == name }
        guard !matching.isEmpty else { return 0.0 }

        let ends = matching.map { paragraph in
            let startBeats = Double(paragraph.start) * measureDuration(for: effectiveBeat)
            let noteDuration = paragraph.sections.reduce(0.0) { total, section in
                let unitDuration = 4.0 / Double(max(1, section.noteLength))
                return total + section.unitGroups.reduce(0.0) { $0 + Double(max(0, $1.length)) * unitDuration }
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
    public static func globalEarliestPosition(in sheet: Sheet) -> Double {
        let orders = sheet.orders.isEmpty
            ? sheet.paragraphs.map(\.name).reduce(into: [String]()) { names, name in
                if !names.contains(name) { names.append(name) }
            }.map(Order.name)
            : sheet.orders
        var state = PlaybackState(
            tempo: sheet.speed > 0 ? sheet.speed : 120,
            keyOffset: sheet.keySignature.semitoneOffset,
            timeSignature: sheet.beat
        )
        var timelinePosition = 0.0
        var minPosition = 0.0

        for order in orders {
            switch order {
            case .relative(let value):
                if let delta = Int(value.replacingOccurrences(of: "+", with: "")) {
                    state = PlaybackState(tempo: state.tempo, keyOffset: state.keyOffset + delta, timeSignature: state.timeSignature)
                }
            case .absolute(let value):
                let keyOffset = KeySignature(string: value).semitoneOffset
                state = PlaybackState(tempo: state.tempo, keyOffset: keyOffset, timeSignature: state.timeSignature)
            case .name(let name):
                let matchingParagraphs = sheet.paragraphs.filter { $0.name == name }
                let paragraphDuration = duration(of: name, in: sheet, beat: state.timeSignature)
                for paragraph in matchingParagraphs {
                    let start = timelinePosition + Double(paragraph.start) * measureDuration(for: state.timeSignature)
                    if start < minPosition {
                        minPosition = start
                    }
                }
                timelinePosition += paragraphDuration
            case .macro:
                break
            }
        }
        return minPosition
    }
}
