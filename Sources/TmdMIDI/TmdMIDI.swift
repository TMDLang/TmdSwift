import Foundation
import TmdSwift

/// Standard MIDI file generator for TMD Sheets.
public struct TMDMIDIGenerator {
    public static let defaultTicksPerQuarterNote: UInt16 = 480

    /// Converts a Sheet into Standard MIDI File (SMF Type 1) binary data.
    public static func generateMIDI(
        from inputSheet: Sheet,
        ticksPerQuarter: UInt16 = defaultTicksPerQuarterNote,
        targetParagraph: String? = nil,
        targetInstrument: String? = nil
    ) -> Data {
        let sheet = TMDMacroEvaluator.expand(inputSheet)
        var effectiveSheet = sheet
        if let targetParagraph {
            let filteredParagraphs = sheet.paragraphs.filter { $0.name == targetParagraph }
            effectiveSheet = Sheet(
                name: sheet.name,
                speed: sheet.speed,
                keySignature: sheet.keySignature,
                beat: sheet.beat,
                paragraphs: filteredParagraphs,
                orders: [.name(targetParagraph)],
                metadata: sheet.metadata
            )
        }

        var distinctInstruments = effectiveSheet.distinctInstruments(fallbackToDefault: false)
        if let targetInstrument {
            distinctInstruments = distinctInstruments.filter { $0 == targetInstrument }
        }

        let timelineInstrument = effectiveSheet.paragraphs.first {
            $0.sections.contains { !$0.directives.isEmpty }
        }?.instrument ?? distinctInstruments.first ?? "Piano"
        let timeline = TMDPlaybackRenderer.render(sheet: effectiveSheet, instrument: timelineInstrument)
        var trackData = [TMDMIDIEncoder.encodeTrack(events: conductorEvents(
            sheet: effectiveSheet, timeline: timeline, ticksPerQuarter: ticksPerQuarter
        ))]
        var melodyChannel = 0
        for (_, instrument) in distinctInstruments.enumerated() {
            let midiInstrument = MIDIInstrument.resolve(instrument)
            let channel: UInt8
            if midiInstrument.isPercussion {
                channel = 9
            } else {
                if melodyChannel == 9 { melodyChannel += 1 } // Skip percussion channel 10 (index 9)
                channel = UInt8(melodyChannel % 16)
                melodyChannel += 1
            }
            let timeline = TMDPlaybackRenderer.render(sheet: effectiveSheet, instrument: instrument)
            trackData.append(TMDMIDIEncoder.encodeTrack(events: instrumentEvents(
                timeline: timeline, instrument: instrument, midiInstrument: midiInstrument,
                channel: channel, ticksPerQuarter: ticksPerQuarter
            )))
        }
        return TMDMIDIEncoder.encodeFile(tracks: trackData, ticksPerQuarter: ticksPerQuarter)
    }

    private static func conductorEvents(sheet: Sheet, timeline: PlaybackTimeline, ticksPerQuarter: UInt16) -> [MIDIEvent] {
        let initial = [
            MIDIEvent(tick: 0, message: .trackName(sheet.name.isEmpty ? "TMD Score" : sheet.name)),
            MIDIEvent(tick: 0, message: .tempo(sheet.speed > 0 ? sheet.speed : 120)),
            MIDIEvent(tick: 0, message: .timeSignature(sheet.beat))
        ]
        let directives = timeline.directives.compactMap { directive -> MIDIEvent? in
            let tick = midiTick(directive.position, ticksPerQuarter: ticksPerQuarter)
            switch directive.kind {
            case .tempo, .relativeTempo: return MIDIEvent(tick: tick, message: .tempo(directive.state.tempo))
            case .timeSignature: return MIDIEvent(tick: tick, message: .timeSignature(directive.state.timeSignature))
            case .absoluteKey, .relativeKey: return nil
            }
        }
        return initial + directives
    }

    public static func instrumentEvents(
        timeline: PlaybackTimeline,
        instrument: String,
        midiInstrument: MIDIInstrument,
        channel: UInt8,
        ticksPerQuarter: UInt16
    ) -> [MIDIEvent] {
        var events = [MIDIEvent(tick: 0, message: .trackName(instrument))]
        if !midiInstrument.isPercussion {
            events.append(MIDIEvent(tick: 0, message: .programChange(channel: channel, program: midiInstrument.program)))
        }
        let lower = instrument.lowercased()
        if lower.contains("left") || lower.contains("-l") {
            events.append(MIDIEvent(tick: 0, message: .controlChange(channel: channel, controller: 10, value: 20)))
        } else if lower.contains("right") || lower.contains("-r") {
            events.append(MIDIEvent(tick: 0, message: .controlChange(channel: channel, controller: 10, value: 108)))
        }
        for event in timeline.events {
            let start = midiTick(event.position, ticksPerQuarter: ticksPerQuarter)
            let duration = max(1, midiTick(event.duration, ticksPerQuarter: ticksPerQuarter))
            switch event.content {
            case .note(let note):
                appendNote(&events, start: start, duration: duration, channel: channel, pitch: noteToMIDIPitch(note, keyOffset: event.state.keyOffset), velocity: 96)
            case .chord(let chord):
                chordToMIDIPitches(chord, keyOffset: event.state.keyOffset).forEach {
                    appendNote(&events, start: start, duration: duration, channel: channel, pitch: $0, velocity: 88)
                }
            case .percussion(let pattern):
                let step = max(1, duration / UInt32(clamping: max(1, pattern.count)))
                for (index, character) in pattern.enumerated() {
                    if let pitch = percussionMIDIPitch(for: character) {
                        let velocity: UInt8 = switch character {
                        case "D", "d", "B", "b": 118 // Strong Kick
                        case "C", "c": 115           // Exploding Crash Cymbal
                        case "S", "s": 105           // Crisp Snare
                        case "T", "t": 100           // Tom-toms
                        case "O", "o": 90            // Open Hi-Hat
                        default: 78                  // Background Closed Hi-Hat
                        }
                        let offset = UInt32(clamping: index).multipliedReportingOverflow(by: step)
                        let noteStart = start.addingReportingOverflow(offset.partialValue)
                        appendNote(
                            &events,
                            start: noteStart.overflow ? UInt32.max : noteStart.partialValue,
                            duration: step,
                            channel: 9,
                            pitch: pitch,
                            velocity: velocity
                        )
                    }
                }
            case .rest:
                break
            }
        }
        return events
    }

    private static func appendNote(_ events: inout [MIDIEvent], start: UInt32, duration: UInt32, channel: UInt8, pitch: Int, velocity: UInt8) {
        guard (0...127).contains(pitch) else { return }
        events.append(MIDIEvent(tick: start, message: .noteOn(channel: channel, note: UInt8(pitch), velocity: velocity)))
        let noteOffOffset = duration > 2 ? duration - 2 : 1
        let noteOffTick = start.addingReportingOverflow(noteOffOffset)
        events.append(MIDIEvent(
            tick: noteOffTick.overflow ? UInt32.max : noteOffTick.partialValue,
            message: .noteOff(channel: channel, note: UInt8(pitch))
        ))
    }

    private static func midiTick(_ quarterNotes: Double, ticksPerQuarter: UInt16) -> UInt32 {
        let ticks = (quarterNotes * Double(ticksPerQuarter)).rounded()
        guard ticks.isFinite else { return 0 }
        return clampedUInt32(ticks)
    }

    private static func clampedUInt32(_ value: Double) -> UInt32 {
        guard value.isFinite else { return value.sign == .minus ? 0 : UInt32.max }
        return UInt32(min(max(0, value), Double(UInt32.max)))
    }

    // MARK: - Musical Helpers

    /// Converts scale degree (1~7) + accidental + octave into MIDI pitch (Middle C = 60).
    public static func noteToMIDIPitch(_ note: Note, keyOffset: Int) -> Int {
        var pitch = 60 + keyOffset + note.degree.semitoneOffset

        switch note.accidental {
        case .sharp: pitch += 1
        case .flat: pitch -= 1
        case .natural: break
        }

        pitch += note.octave * 12
        return pitch
    }

    private static func percussionMIDIPitch(for character: Character) -> Int? {
        [
            "D": 36, "d": 36, "B": 36, "b": 36,  // Bass Drum 1 (Kick)
            "S": 38, "s": 38,                     // Acoustic Snare
            "X": 42, "x": 42,                     // Closed Hi-Hat
            "O": 46, "o": 46,                     // Open Hi-Hat
            "T": 45, "t": 45,                     // Low-Mid Tom
            "C": 49, "c": 49                      // Crash Cymbal 1
        ][character]
    }

    /// Resolves chord names (degree numbers like `1`, `6m`, `4`, `5`, or chord names like `Cmaj7`).
    public static func chordToMIDIPitches(_ chord: String, keyOffset: Int) -> [Int] {
        chordToMIDIPitches(ChordSymbol(string: chord), keyOffset: keyOffset)
    }

    /// Resolves a typed chord symbol into MIDI pitches.
    public static func chordToMIDIPitches(_ chord: ChordSymbol, keyOffset: Int) -> [Int] {
        let rootPitch: Int
        if chord.root.isScaleDegree {
            let note = Note(accidental: chord.root.accidental, degree: chord.root.degree, octave: chord.root.octave)
            rootPitch = noteToMIDIPitch(note, keyOffset: keyOffset) - 12
        } else {
            rootPitch = 48 + chord.root.semitoneOffset
        }
        return chord.quality.semitoneIntervals.map { rootPitch + $0 }
    }

    public static func generalMidiProgram(for instrument: String) -> UInt8 {
        MIDIInstrument.resolve(instrument).program
    }

}
