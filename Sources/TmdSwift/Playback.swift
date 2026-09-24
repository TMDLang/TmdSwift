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
                let paragraph = paragraphs.first { $0.name == name }
                let paragraphDuration = duration(of: name, in: sheet)
                guard let paragraph else {
                    timelinePosition += paragraphDuration
                    continue
                }

                let start = timelinePosition + Double(paragraph.start) * measureDuration(for: state.timeSignature)
                let rendered = render(
                    paragraph: paragraph,
                    start: start,
                    state: state
                )
                events.append(contentsOf: rendered.events)
                directives.append(contentsOf: rendered.directives)
                state = rendered.state
                timelinePosition += max(paragraphDuration, rendered.duration)
            case .macro:
                // S-expression macros are desugared by TMDMacroEvaluator before rendering
                break
            }
        }

        // If any event starts at a negative position (e.g. lead-in measure @|-1| on the first paragraph),
        // shift the entire timeline forward so that the earliest event starts at exactly position 0.0.
        let minEventPosition = events.map(\.position).min() ?? 0.0
        let minDirectivePosition = directives.map(\.position).min() ?? 0.0
        let earliestPosition = min(minEventPosition, minDirectivePosition)
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
                        // Extend the duration of the most recent note or chord
                        let last = events.removeLast()
                        events.append(PlaybackEvent(
                            position: last.position,
                            duration: last.duration + groupDuration,
                            content: last.content,
                            state: last.state
                        ))
                    } else {
                        // Leading tie with no preceding note acts as rest
                        events.append(PlaybackEvent(position: position, duration: groupDuration, content: .rest, state: state))
                    }
                } else {
                    let baseSlotDuration = groupDuration / Double(max(1, group.units.count))
                    var currentEventIndex = -1

                    for (idx, unit) in group.units.enumerated() {
                        if unit == .tie {
                            if currentEventIndex >= 0 {
                                let ev = events[currentEventIndex]
                                events[currentEventIndex] = PlaybackEvent(
                                    position: ev.position,
                                    duration: ev.duration + baseSlotDuration,
                                    content: ev.content,
                                    state: ev.state
                                )
                            } else if !events.isEmpty {
                                let last = events.removeLast()
                                events.append(PlaybackEvent(
                                    position: last.position,
                                    duration: last.duration + baseSlotDuration,
                                    content: last.content,
                                    state: last.state
                                ))
                                currentEventIndex = events.count - 1
                            } else {
                                events.append(PlaybackEvent(
                                    position: position + Double(idx) * baseSlotDuration,
                                    duration: baseSlotDuration,
                                    content: .rest,
                                    state: state
                                ))
                                currentEventIndex = events.count - 1
                            }
                        } else {
                            if let content = content(of: unit) {
                                events.append(PlaybackEvent(
                                    position: position + Double(idx) * baseSlotDuration,
                                    duration: baseSlotDuration,
                                    content: content,
                                    state: state
                                ))
                                currentEventIndex = events.count - 1
                            }
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

    /// Calculates total quarter-note duration of a section/paragraph name in a sheet.
    public static func duration(of name: String, in sheet: Sheet) -> Double {
        sheet.paragraphs
            .filter { $0.name == name }
            .map { paragraph in
                Double(max(0, paragraph.start)) * measureDuration(for: sheet.beat)
                    + paragraph.sections.reduce(0) { total, section in
                        let unitDuration = 4.0 / Double(max(1, section.noteLength))
                        return total + section.unitGroups.reduce(0) { $0 + Double(max(0, $1.length)) * unitDuration }
                    }
            }
            .max() ?? 0
    }

    /// Calculates measure duration in quarter notes for a given beat signature.
    public static func measureDuration(for beat: Beat) -> Double {
        Double(max(1, beat.count)) * 4.0 / Double(max(1, beat.noteValue))
    }
}
