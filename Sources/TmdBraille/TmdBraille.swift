import Foundation
import TmdSwift

/// Encoding format for Music Braille output.
public enum TmdBrailleEncoding: String, Sendable, CaseIterable {
    /// 6-dot Unicode Braille Patterns (`U+2800`–`U+28FF`, `.brl`).
    case unicode
    /// North American Braille ASCII (`0x20`–`0x5F`, `.brf`).
    case ascii
}

/// Score layout mode for multi-track Music Braille output.
public enum TmdBrailleLayout: String, Sendable, CaseIterable {
    /// Sequential part-by-part output (each instrument rendered continuously from origin to `->#`).
    /// Recommended by BANA / MBC for reading on single-line refreshable Braille displays.
    case partByPart = "part-by-part"
    /// Parallel section/measure-aligned bar-over-bar score layout (Chapter XX, Par. 20-1 to 20-11).
    case barOverBar = "bar-over-bar"
}

/// Configuration options for Music Braille export.
public struct TmdBrailleOptions: Sendable {
    public var encoding: TmdBrailleEncoding
    public var layout: TmdBrailleLayout
    public var targetSection: String?
    public var targetInstrument: String?

    public init(
        encoding: TmdBrailleEncoding = .unicode,
        layout: TmdBrailleLayout = .partByPart,
        targetSection: String? = nil,
        targetInstrument: String? = nil
    ) {
        self.encoding = encoding
        self.layout = layout
        self.targetSection = targetSection
        self.targetInstrument = targetInstrument
    }
}

/// International Music Braille Code (1996 New International Manual / BANA 2015) exporter for TMD Sheets.
public struct TmdBrailleGenerator {

    /// Generates a Music Braille string from a `Sheet`.
    public static func generateBraille(
        from inputSheet: Sheet,
        options: TmdBrailleOptions = TmdBrailleOptions()
    ) -> String {
        var workingSheet = TmdMacroEvaluator.expandOrTrap(inputSheet)

        if let targetSection = options.targetSection, !targetSection.isEmpty {
            let filteredEntries = workingSheet.entries.filter {
                $0.name.caseInsensitiveCompare(targetSection) == .orderedSame
            }
            workingSheet = Sheet(
                name: workingSheet.name,
                speed: workingSheet.speed,
                keySignature: workingSheet.keySignature,
                declaredKey: workingSheet.declaredKey,
                beat: workingSheet.beat,
                entries: filteredEntries,
                playback: [.name(targetSection)],
                metadata: workingSheet.metadata
            )
        }

        var instruments = distinctMusicalInstruments(in: workingSheet)
        if let targetInstrument = options.targetInstrument, !targetInstrument.isEmpty {
            instruments = instruments.filter {
                $0.caseInsensitiveCompare(targetInstrument) == .orderedSame
            }
        }

        var asciiLines: [String] = []

        // 1. Score Title Header (Grade 1 Uncontracted Literary Braille)
        let title = workingSheet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            asciiLines.append(title.brailleLiteraryString)
        }

        // 2. Metronome + Initial Key Signature + Initial Time Signature (Par. 14-18)
        let bpm = Int((workingSheet.speed > 0 ? workingSheet.speed : 120).rounded())
        let metronomeAscii = "?7#\(encodeUpperDigits(bpm))"
        let initialKey =
            workingSheet.declaredKey
            ?? PitchMapping.tonicScaleInfo(
                forKeyOffset: workingSheet.keySignature.semitoneOffset
            ).name
        let keySigAscii = encodeKeySignature(forKey: initialKey)
        let timeSigAscii = workingSheet.beat.brailleTimeSignature
        asciiLines.append("\(metronomeAscii) \(keySigAscii)\(timeSigAscii)")

        if instruments.isEmpty {
            let rawAscii = asciiLines.joined(separator: "\n") + "\n"
            return options.encoding == .unicode ? asciiToUnicodeBraille(rawAscii) : rawAscii
        }

        // Render per-instrument measure streams
        let renderedTracks = instruments.map { inst in
            renderTrackMeasures(instrument: inst, sheet: workingSheet)
        }

        switch options.layout {
        case .partByPart:
            for track in renderedTracks {
                let prefix = track.instrument.braillePartPrefixAscii
                let body = joinTrackMeasuresAscii(track.measures)
                asciiLines.append("\(prefix) \(body)<K")
            }

        case .barOverBar:
            // Instrument list & upward interval direction indicator (Par. 20-1, 20-6)
            for track in renderedTracks {
                let heading = track.instrument.brailleLiteraryString
                let prefix = track.instrument.braillePartPrefixAscii
                asciiLines.append("\(heading) \(prefix)")
            }
            let maxMeasures = renderedTracks.map { $0.measures.count }.max() ?? 0
            for mIdx in 0..<maxMeasures {
                asciiLines.append("#\(encodeUpperDigits(mIdx + 1))")
                let isLastMeasure = (mIdx == maxMeasures - 1)
                for track in renderedTracks {
                    let prefix = track.instrument.braillePartPrefixAscii
                    let mAscii =
                        mIdx < track.measures.count ? track.measures[mIdx].ascii : "M"
                    let suffix = isLastMeasure ? "<K" : ""
                    asciiLines.append("  \(prefix) \(mAscii)\(suffix)")
                }
            }
        }

        let rawAscii = asciiLines.joined(separator: "\n") + "\n"
        return options.encoding == .unicode ? asciiToUnicodeBraille(rawAscii) : rawAscii
    }

    private static func distinctMusicalInstruments(in sheet: Sheet) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []

        func appendIfMusical(_ entry: Entry) {
            guard entry.showProgram == nil, entry.executionTime == nil else { return }
            guard let assignment = entry.assignment?.trimmingCharacters(in: .whitespacesAndNewlines),
                !assignment.isEmpty
            else { return }
            let key = assignment.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(assignment)
            }
        }

        if !sheet.playback.isEmpty {
            for item in sheet.playback {
                if case .name(let secName) = item {
                    for entry in sheet.entries where entry.name == secName {
                        appendIfMusical(entry)
                    }
                }
            }
        } else {
            for entry in sheet.entries {
                appendIfMusical(entry)
            }
        }

        return result
    }

    // MARK: - Track Measure Rendering

    private struct RenderedBrailleMeasure {
        let index: Int
        let isFullMeasureRest: Bool
        let hasLeadingKeyOrMeterChange: Bool
        let preMeasureDirectivesAscii: String
        let ascii: String
        let endsWithCrossBarTie: Bool
        let startsWithCrossBarTie: Bool
    }

    private struct RenderedBrailleTrack {
        let instrument: String
        let measures: [RenderedBrailleMeasure]
    }

    private static func renderTrackMeasures(
        instrument: String,
        sheet: Sheet
    ) -> RenderedBrailleTrack {
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        let isFixedPitchTrack = sheet.entries.contains {
            $0.assignment?.caseInsensitiveCompare(instrument) == .orderedSame
                && $0.pitchMode == .fixed
        }
        let isChordTrack = isChordSymbolAssignment(instrument)
        let isPercussion = isPercussionAssignment(instrument, entries: sheet.entries)

        var activeWrittenKey =
            isFixedPitchTrack
            ? "C"
            : (sheet.declaredKey
                ?? PitchMapping.tonicScaleInfo(forKeyOffset: sheet.keySignature.semitoneOffset)
                .name)
        var activeKeyOffset = isFixedPitchTrack ? 0 : sheet.keySignature.semitoneOffset
        var defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: activeWrittenKey)
        var activeBeat = sheet.beat

        var lastPitch: (octave: Int, stepIndex: Int)? = nil
        var forceOctave = true

        var outMeasures: [RenderedBrailleMeasure] = []

        for measure in measures {
            var measureStepAlters: [Int: [Int]] = [:]
            var preDirectives: [String] = []
            var inlineDirectivesByOffset: [(offset: Double, ascii: String)] = []

            // Check measure-level directives
            for directive in measure.directives {
                switch directive.kind {
                case .explicitKey(let key), .absoluteKey(let key):
                    if !isFixedPitchTrack && key != activeWrittenKey {
                        activeWrittenKey = key
                        defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: key)
                        measureStepAlters.removeAll()
                        let ks = encodeKeySignature(forKey: key)
                        if !ks.isEmpty {
                            preDirectives.append(ks)
                        }
                        forceOctave = true
                    }
                case .relativeKey:
                    if !isFixedPitchTrack && sheet.declaredKey == nil {
                        let newKey = PitchMapping.tonicScaleInfo(
                            forKeyOffset: directive.state.keyOffset
                        ).name
                        if newKey != activeWrittenKey {
                            activeWrittenKey = newKey
                            activeKeyOffset = directive.state.keyOffset
                            defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(
                                forKey: newKey)
                            measureStepAlters.removeAll()
                            let ks = encodeKeySignature(forKey: newKey)
                            if !ks.isEmpty {
                                preDirectives.append(ks)
                            }
                            forceOctave = true
                        }
                    }
                case .fixedPitch:
                    activeWrittenKey = "C"
                    defaultKeyStepAlters = [0, 0, 0, 0, 0, 0, 0]
                    measureStepAlters.removeAll()
                case .timeSignature(let beat):
                    if beat != activeBeat {
                        activeBeat = beat
                        preDirectives.append(beat.brailleTimeSignature)
                        forceOctave = true
                    }
                case .tempo, .relativeTempo:
                    let bpm = Int(directive.state.tempo.rounded())
                    preDirectives.append("?7#\(encodeUpperDigits(bpm))")
                    forceOctave = true
                case .dynamics(let mark):
                    let relOffset = max(0.0, directive.position - measure.startTime)
                    inlineDirectivesByOffset.append((relOffset, ">\(mark.rawValue.uppercased())"))
                }
            }

            // Also detect playback-level keyOffset changes (e.g. `-> {?+2}`) on non-rest pitched events
            let nonRestEvents = measure.events.filter {
                if case .rest = $0.content { return false }
                return true
            }
            if !isFixedPitchTrack,
                !isChordTrack,
                !isPercussion,
                sheet.declaredKey == nil,
                let firstActive = nonRestEvents.first,
                firstActive.state.keyOffset != activeKeyOffset
            {
                activeKeyOffset = firstActive.state.keyOffset
                let newKey = PitchMapping.tonicScaleInfo(forKeyOffset: activeKeyOffset).name
                if newKey != activeWrittenKey {
                    activeWrittenKey = newKey
                    defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: newKey)
                    measureStepAlters.removeAll()
                    let ks = encodeKeySignature(forKey: newKey)
                    if !ks.isEmpty {
                        preDirectives.append(ks)
                    }
                    forceOctave = true
                }
            }

            // Check if entire measure is rest
            if nonRestEvents.isEmpty && inlineDirectivesByOffset.isEmpty {
                outMeasures.append(
                    RenderedBrailleMeasure(
                        index: measure.index,
                        isFullMeasureRest: true,
                        hasLeadingKeyOrMeterChange: !preDirectives.isEmpty,
                        preMeasureDirectivesAscii: preDirectives.joined(separator: " "),
                        ascii: "M",
                        endsWithCrossBarTie: false,
                        startsWithCrossBarTie: false
                    ))
                continue
            }

            // Group simultaneous events in the measure by startOffset
            var groups: [[MeasureEvent]] = []
            for ev in measure.events {
                if let lastGroup = groups.last,
                    let firstInLast = lastGroup.first,
                    abs(ev.startOffset - firstInLast.startOffset) < 1e-4
                {
                    groups[groups.count - 1].append(ev)
                } else {
                    groups.append([ev])
                }
            }

            var measureCells = ""
            var consumedDirectiveIndices: Set<Int> = []
            let startsWithTie = groups.first?.contains(where: { $0.tieStop }) ?? false
            let endsWithTie = groups.last?.contains(where: { $0.tieStart }) ?? false

            for group in groups {
                guard let primary = group.first else { continue }

                // Emit any inline dynamics at or before primary.startOffset
                var pendingDynamicAscii = ""
                for (dIdx, item) in inlineDirectivesByOffset.enumerated()
                where !consumedDirectiveIndices.contains(dIdx)
                    && item.offset <= primary.startOffset + 1e-4
                {
                    consumedDirectiveIndices.insert(dIdx)
                    pendingDynamicAscii += item.ascii
                    forceOctave = true
                }

                let groupAscii = renderEventGroup(
                    group: group,
                    isChordTrack: isChordTrack,
                    isPercussion: isPercussion,
                    defaultKeyStepAlters: defaultKeyStepAlters,
                    measureStepAlters: &measureStepAlters,
                    lastPitch: &lastPitch,
                    forceOctave: &forceOctave
                )

                if !pendingDynamicAscii.isEmpty {
                    // Par. 10-4: If the first character of groupAscii uses dots 1, 2, or 3, insert Dot 3 `'`
                    if let firstChar = groupAscii.first, cellUsesDots123(firstChar) {
                        measureCells += "\(pendingDynamicAscii)'\(groupAscii)"
                    } else {
                        measureCells += "\(pendingDynamicAscii)\(groupAscii)"
                    }
                } else {
                    measureCells += groupAscii
                }
            }

            outMeasures.append(
                RenderedBrailleMeasure(
                    index: measure.index,
                    isFullMeasureRest: false,
                    hasLeadingKeyOrMeterChange: !preDirectives.isEmpty,
                    preMeasureDirectivesAscii: preDirectives.joined(separator: " "),
                    ascii: measureCells,
                    endsWithCrossBarTie: endsWithTie,
                    startsWithCrossBarTie: startsWithTie
                ))
        }

        return RenderedBrailleTrack(instrument: instrument, measures: outMeasures)
    }

    private static func joinTrackMeasuresAscii(_ measures: [RenderedBrailleMeasure]) -> String {
        var tokens: [String] = []
        var i = 0
        while i < measures.count {
            let m = measures[i]
            if !m.preMeasureDirectivesAscii.isEmpty {
                tokens.append(m.preMeasureDirectivesAscii)
            }
            if m.isFullMeasureRest {
                var restCount = 1
                var j = i + 1
                while j < measures.count && measures[j].isFullMeasureRest
                    && measures[j].preMeasureDirectivesAscii.isEmpty
                {
                    restCount += 1
                    j += 1
                }
                tokens.append(encodeFullMeasureRests(count: restCount))
                i = j
            } else {
                var combined = m.ascii
                var cur = m
                var j = i + 1
                while j < measures.count && cur.endsWithCrossBarTie
                    && measures[j].startsWithCrossBarTie
                    && measures[j].preMeasureDirectivesAscii.isEmpty
                {
                    combined += measures[j].ascii
                    cur = measures[j]
                    j += 1
                }
                tokens.append(combined)
                i = j
            }
        }
        return tokens.joined(separator: " ")
    }

    // MARK: - Event Group Encoding

    private static func renderEventGroup(
        group: [MeasureEvent],
        isChordTrack: Bool,
        isPercussion: Bool,
        defaultKeyStepAlters: [Int],
        measureStepAlters: inout [Int: [Int]],
        lastPitch: inout (octave: Int, stepIndex: Int)?,
        forceOctave: inout Bool
    ) -> String {
        guard let first = group.first else { return "" }
        let atoms = NotationDuration.decompose(quarterNotes: first.duration)

        // 1. Check if group contains simultaneous pitched notes
        var notes: [(note: Note, event: MeasureEvent, spelled: SpelledPitch)] = []
        for ev in group {
            if case .note(let n) = ev.content {
                let spelled = PitchMapping.spell(note: n, keyOffset: ev.state.keyOffset)
                notes.append((n, ev, spelled))
            }
        }

        if !notes.isEmpty {
            // Sort bottom-up by diatonic pitch (octave * 7 + stepIndex, then midiPitch)
            notes.sort {
                let d0 = $0.spelled.octave * 7 + $0.spelled.stepIndex
                let d1 = $1.spelled.octave * 7 + $1.spelled.stepIndex
                if d0 != d1 { return d0 < d1 }
                return $0.spelled.midiPitch < $1.spelled.midiPitch
            }

            var out = ""
            for (atomIdx, atom) in atoms.enumerated() {
                let base = notes[0]
                let isContinuationAtom = atomIdx > 0 || base.event.tieStop
                let needsInternalTie = (atomIdx < atoms.count - 1) || base.event.tieStart

                // Accidental on base note
                var baseOctAlters = measureStepAlters[base.spelled.octave] ?? defaultKeyStepAlters
                let expectedBaseAlter = baseOctAlters[base.spelled.stepIndex]
                var accStr = ""
                if base.spelled.alter != expectedBaseAlter && !isContinuationAtom {
                    baseOctAlters[base.spelled.stepIndex] = base.spelled.alter
                    measureStepAlters[base.spelled.octave] = baseOctAlters
                    accStr = encodeAccidental(alter: base.spelled.alter)
                }

                // Octave mark on base note (suppressed on immediate cross-bar tied continuation of single note)
                var octStr = ""
                if !(base.event.tieStop && atomIdx == 0 && notes.count == 1 && !forceOctave) {
                    if shouldEmitOctave(
                        currOctave: base.spelled.octave,
                        currStep: base.spelled.stepIndex,
                        lastPitch: lastPitch,
                        forceOctave: forceOctave
                    ) {
                        octStr = encodeOctaveMark(base.spelled.octave)
                    }
                }
                lastPitch = (base.spelled.octave, base.spelled.stepIndex)
                forceOctave = false

                let noteCell = atom.brailleNoteCell(stepIndex: base.spelled.stepIndex)

                // Intervals for remaining notes (Table 5A)
                var intervalsStr = ""
                let baseDiatonic = base.spelled.octave * 7 + base.spelled.stepIndex
                var prevDiatonic = baseDiatonic
                for member in notes.dropFirst() {
                    var memOctAlters =
                        measureStepAlters[member.spelled.octave] ?? defaultKeyStepAlters
                    let expectedMemAlter = memOctAlters[member.spelled.stepIndex]
                    var memAcc = ""
                    if member.spelled.alter != expectedMemAlter && !isContinuationAtom {
                        memOctAlters[member.spelled.stepIndex] = member.spelled.alter
                        measureStepAlters[member.spelled.octave] = memOctAlters
                        memAcc = encodeAccidental(alter: member.spelled.alter)
                    }

                    let memDiatonic = member.spelled.octave * 7 + member.spelled.stepIndex
                    let deltaFromBase = max(0, memDiatonic - baseDiatonic)
                    let deltaFromPrev = max(0, memDiatonic - prevDiatonic)
                    prevDiatonic = memDiatonic

                    if deltaFromBase == 0 {
                        intervalsStr += "\(memAcc)\(encodeOctaveMark(member.spelled.octave))-"
                    } else {
                        let intervalIdx = ((deltaFromBase - 1) % 7) + 1
                        let needOct = deltaFromBase > 7 || deltaFromPrev >= 7
                        let intOct = needOct ? encodeOctaveMark(member.spelled.octave) : ""
                        intervalsStr += "\(memAcc)\(intOct)\(encodeIntervalSign(intervalIdx))"
                    }
                }

                let tieStr: String
                if needsInternalTie {
                    tieStr = notes.count > 1 ? ".C.C" : "@C"
                } else {
                    tieStr = ""
                }

                out += "\(accStr)\(octStr)\(noteCell)\(intervalsStr)\(tieStr)"
            }
            return out
        }

        // 2. Chord Symbol event
        if case .chord(let chord) = first.content {
            if isChordTrack {
                let sym = chord.brailleLiteraryString(keyOffset: first.state.keyOffset)
                let stem = atoms.first?.brailleChordStemSign ?? "_'"
                return "\(sym)\(stem)"
            } else {
                // Mode B: Voiced Interval Realization (Table 5A)
                let voiced = PitchMapping.spellChordVoicing(
                    chord, keyOffset: first.state.keyOffset)
                guard let base = voiced.first else { return "" }
                var out = ""
                for (atomIdx, atom) in atoms.enumerated() {
                    let isContinuation = atomIdx > 0
                    var baseOctAlters = measureStepAlters[base.octave] ?? defaultKeyStepAlters
                    var accStr = ""
                    if base.alter != baseOctAlters[base.stepIndex] && !isContinuation {
                        baseOctAlters[base.stepIndex] = base.alter
                        measureStepAlters[base.octave] = baseOctAlters
                        accStr = encodeAccidental(alter: base.alter)
                    }
                    let octStr =
                        shouldEmitOctave(
                            currOctave: base.octave,
                            currStep: base.stepIndex,
                            lastPitch: lastPitch,
                            forceOctave: forceOctave
                        ) ? encodeOctaveMark(base.octave) : ""
                    lastPitch = (base.octave, base.stepIndex)
                    forceOctave = false

                    let noteCell = atom.brailleNoteCell(stepIndex: base.stepIndex)
                    let baseDiatonic = base.octave * 7 + base.stepIndex
                    var intervalsStr = ""
                    for member in voiced.dropFirst() {
                        var memOctAlters = measureStepAlters[member.octave] ?? defaultKeyStepAlters
                        var memAcc = ""
                        if member.alter != memOctAlters[member.stepIndex] && !isContinuation {
                            memOctAlters[member.stepIndex] = member.alter
                            measureStepAlters[member.octave] = memOctAlters
                            memAcc = encodeAccidental(alter: member.alter)
                        }
                        let delta = max(1, (member.octave * 7 + member.stepIndex) - baseDiatonic)
                        let intIdx = ((delta - 1) % 7) + 1
                        let intOct = delta > 7 ? encodeOctaveMark(member.octave) : ""
                        intervalsStr += "\(memAcc)\(intOct)\(encodeIntervalSign(intIdx))"
                    }
                    let tieStr = atomIdx < atoms.count - 1 ? ".C.C" : ""
                    out += "\(accStr)\(octStr)\(noteCell)\(intervalsStr)\(tieStr)"
                }
                return out
            }
        }

        // 3. Percussion event (Section 7.5)
        if case .percussion(let pattern) = first.content {
            let clean = pattern.filter { !$0.isWhitespace && $0 != "(" && $0 != ")" }
            guard !clean.isEmpty else {
                return atoms.map(\.brailleRestCell).joined()
            }
            let subDur = first.duration / Double(clean.count)
            let subAtom =
                NotationDuration.decompose(quarterNotes: subDur).first
                ?? NotationDuration(baseDenominator: 4, isDotted: false, quarterValue: 1.0)
            var out = ""
            for ch in clean {
                if ch == "-" || ch == "." {
                    out += subAtom.brailleRestCell
                    continue
                }
                let (stepIdx, oct) = percussionStepAndOctave(for: ch)
                let octStr =
                    shouldEmitOctave(
                        currOctave: oct,
                        currStep: stepIdx,
                        lastPitch: lastPitch,
                        forceOctave: forceOctave
                    ) ? encodeOctaveMark(oct) : ""
                lastPitch = (oct, stepIdx)
                forceOctave = false
                out += "\(octStr)\(subAtom.brailleNoteCell(stepIndex: stepIdx))"
            }
            return out
        }

        // 4. Rest event
        let prefix = isChordTrack ? "\"" : ""
        return atoms.map { "\(prefix)\($0.brailleRestCell)" }.joined()
    }

    // MARK: - Braille Primitives & Tables

    private static func encodeFullMeasureRests(count: Int) -> String {
        guard count > 0 else { return "" }
        if count <= 3 {
            return String(repeating: "M", count: count)
        }
        return "#\(encodeUpperDigits(count))M"
    }

    private static func encodeOctaveMark(_ octave: Int) -> String {
        switch octave {
        case ..<1: return "@@"
        case 1: return "@"
        case 2: return "^"
        case 3: return "_"
        case 4: return "\""
        case 5: return "."
        case 6: return ";"
        case 7: return ","
        default: return ",,"
        }
    }

    private static func shouldEmitOctave(
        currOctave: Int,
        currStep: Int,
        lastPitch: (octave: Int, stepIndex: Int)?,
        forceOctave: Bool
    ) -> Bool {
        if forceOctave { return true }
        guard let last = lastPitch else { return true }
        let dCurr = currOctave * 7 + currStep
        let dPrev = last.octave * 7 + last.stepIndex
        let delta = abs(dCurr - dPrev)
        if delta <= 2 { return false }
        if delta == 3 || delta == 4 { return currOctave != last.octave }
        return true
    }

    fileprivate static func encodeAccidental(alter: Int) -> String {
        if alter <= -2 { return "<<" }
        if alter == -1 { return "<" }
        if alter == 0 { return "*" }
        if alter == 1 { return "%" }
        return "%%"
    }

    private static func encodeIntervalSign(_ interval1To7: Int) -> String {
        switch interval1To7 {
        case 1: return "/"
        case 2: return "+"
        case 3: return "#"
        case 4: return "9"
        case 5: return "0"
        case 6: return "3"
        default: return "-"
        }
    }

    private static func encodeKeySignature(forKey key: String) -> String {
        let fifths = PitchMapping.parseKeyModeAndFifths(key).fifths
        if fifths == 0 { return "" }
        let count = abs(fifths)
        let sign = fifths > 0 ? "%" : "<"
        if count <= 3 {
            return String(repeating: sign, count: count)
        }
        return "#\(encodeUpperDigits(count))\(sign)"
    }

    fileprivate static func encodeUpperDigits(_ number: Int) -> String {
        let upperMap: [Character: String] = [
            "1": "A", "2": "B", "3": "C", "4": "D", "5": "E",
            "6": "F", "7": "G", "8": "H", "9": "I", "0": "J",
        ]
        return String(max(0, number)).compactMap { upperMap[$0] }.joined()
    }

    fileprivate static func encodeLowerDigits(_ number: Int) -> String {
        let lowerMap: [Character: String] = [
            "1": "1", "2": "2", "3": "3", "4": "4", "5": "5",
            "6": "6", "7": "7", "8": "8", "9": "9", "0": "0",
        ]
        return String(max(0, number)).compactMap { lowerMap[$0] }.joined()
    }

    private static func isChordSymbolAssignment(_ instrument: String) -> Bool {
        let lower = instrument.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower == "chord" || lower == "chords"
    }

    private static func isPercussionAssignment(_ instrument: String, entries: [Entry]) -> Bool {
        let lower = instrument.lowercased()
        if lower.contains("drum") || lower.contains("perc") || lower.contains("kit") {
            return true
        }
        return entries.contains { entry in
            guard entry.assignment?.caseInsensitiveCompare(instrument) == .orderedSame else {
                return false
            }
            return entry.sections.contains { sec in
                sec.unitGroups.contains { grp in
                    grp.units.contains {
                        if case .percussion = $0 { return true }
                        return false
                    }
                }
            }
        }
    }

    private static func percussionStepAndOctave(for token: Character) -> (stepIndex: Int, octave: Int) {
        switch token {
        case "D", "d", "B", "b": return (3, 4)  // F4
        case "T", "t": return (5, 4)  // A4
        case "S", "s": return (1, 5)  // D5
        case "X", "x": return (3, 5)  // F5
        case "O", "o": return (4, 5)  // G5
        case "C", "c": return (5, 5)  // A5
        default: return (1, 5)
        }
    }

    /// Returns true if the given Braille ASCII character contains dot 1, dot 2, or dot 3.
    /// Octave marks (`@`, `^`, `_`, `"`, `.`, `;`, `,`) use only dots 4, 5, and 6.
    private static func cellUsesDots123(_ asciiChar: Character) -> Bool {
        let dots456Only: Set<Character> = ["@", "^", "_", "\"", ".", ";", ",", " "]
        return !dots456Only.contains(asciiChar)
    }

    // MARK: - 64-Cell Braille ASCII to Unicode Braille Table (Section 2.1)

    private static let asciiToUnicodeMap: [Character: Character] = [
        "!": "⠮", "\"": "⠐", "#": "⠼", "$": "⠫", "%": "⠩", "&": "⠯", "'": "⠄", "(": "⠷",
        ")": "⠾", "*": "⠡", "+": "⠬", ",": "⠠", "-": "⠤", ".": "⠨", "/": "⠌",
        "0": "⠴", "1": "⠂", "2": "⠆", "3": "⠒", "4": "⠲", "5": "⠢", "6": "⠖", "7": "⠶",
        "8": "⠦", "9": "⠔", ":": "⠱", ";": "⠰", "<": "⠣", "=": "⠿", ">": "⠜", "?": "⠹",
        "@": "⠈",
        "A": "⠁", "B": "⠃", "C": "⠉", "D": "⠙", "E": "⠑", "F": "⠋", "G": "⠛", "H": "⠓",
        "I": "⠊", "J": "⠚", "K": "⠅", "L": "⠇", "M": "⠍", "N": "⠝", "O": "⠕", "P": "⠏",
        "Q": "⠟", "R": "⠗", "S": "⠎", "T": "⠞", "U": "⠥", "V": "⠧", "W": "⠺", "X": "⠭",
        "Y": "⠽", "Z": "⠵",
        "[": "⠪", "\\": "⠳", "]": "⠻", "^": "⠘", "_": "⠸",
    ]

    /// Converts a North American Braille ASCII string into Unicode Braille (`U+2800`–`U+28FF`).
    public static func asciiToUnicodeBraille(_ ascii: String) -> String {
        var result = String.UnicodeScalarView()
        result.reserveCapacity(ascii.count)
        for ch in ascii {
            let upper = Character(String(ch).uppercased())
            if let mapped = asciiToUnicodeMap[upper] {
                result.append(contentsOf: mapped.unicodeScalars)
            } else {
                result.append(contentsOf: ch.unicodeScalars)
            }
        }
        return String(result)
    }
}

// MARK: - Domain Type Braille Extensions

private extension ChordQuality {
    /// North American Braille ASCII literary suffix for the chord quality (Section 5.2, Table 12A).
    var brailleLiterarySuffix: String {
        switch self {
        case .major:
            return ""
        case .minor:
            return "M"
        case .dominant7:
            return "#G"
        case .major7:
            return "MAJ#G"
        case .minor7:
            return "M#G"
        case .diminished:
            return "DIM"
        case .halfDiminished:
            return "M#G-#E"
        case .augmented:
            return "AUG"
        case .suspended:
            return "SUS#D"
        case .power:
            return "#E"
        case .custom(let suffix):
            return suffix.brailleLiteraryString
        }
    }
}

private extension ChordSymbol {
    /// Encodes a `ChordSymbol` into Grade 1 Literary + Music Braille ASCII (`Section 5.2 Mode A`).
    func brailleLiteraryString(keyOffset: Int) -> String {
        let rootPitch = PitchMapping.spell(chordRoot: root, keyOffset: keyOffset)
        var out = ",\(rootPitch.step.uppercased())"
        if rootPitch.alter != 0 {
            out += TmdBrailleGenerator.encodeAccidental(alter: rootPitch.alter)
        }
        out += quality.brailleLiterarySuffix
        if let bass {
            let bassPitch = PitchMapping.spell(chordRoot: bass, keyOffset: keyOffset)
            out += "/,\(bassPitch.step.uppercased())"
            if bassPitch.alter != 0 {
                out += TmdBrailleGenerator.encodeAccidental(alter: bassPitch.alter)
            }
        }
        return out
    }
}

private extension NotationDuration {
    private static let wholeOr16thCells = ["Y", "Z", "&", "=", "(", "!", ")"]
    private static let halfOr32ndCells = ["N", "O", "P", "Q", "R", "S", "T"]
    private static let quarterOr64thCells = ["?", ":", "$", "]", "\\", "[", "W"]
    private static let eighthOr128thCells = ["D", "E", "F", "G", "H", "I", "J"]

    /// Encodes a pitched note cell (`Section 3.1, Table 1`) for the given diatonic step (`0 = C` ... `6 = B`).
    func brailleNoteCell(stepIndex: Int) -> String {
        let idx = max(0, min(6, stepIndex))
        let cell: String
        switch baseDenominator {
        case 1, 16:
            cell = Self.wholeOr16thCells[idx]
        case 2, 32:
            cell = Self.halfOr32ndCells[idx]
        case 4, 64:
            cell = Self.quarterOr64thCells[idx]
        default:
            cell = Self.eighthOr128thCells[idx]
        }
        return isDotted ? "\(cell)'" : cell
    }

    /// Encodes a rest cell (`Section 3.2, Table 2`).
    var brailleRestCell: String {
        let cell: String
        switch baseDenominator {
        case 1, 16: cell = "M"
        case 2, 32: cell = "U"
        case 4, 64: cell = "V"
        default: cell = "X"
        }
        return isDotted ? "\(cell)'" : cell
    }

    /// Encodes a rhythmic stem sign for lead-sheet chord symbols (`Section 5.2, Table 13`).
    var brailleChordStemSign: String {
        let base: String
        switch baseDenominator {
        case 1: base = "_'"
        case 2: base = "_K"
        case 4: base = "_A"
        case 8: base = "_B"
        case 16: base = "_L"
        default: base = "_1"
        }
        return isDotted ? "\(base)'" : base
    }
}

private extension Beat {
    /// Encodes a time signature into Music Braille ASCII (`Section 4.2, Table 7B`).
    var brailleTimeSignature: String {
        let c = max(1, count)
        let n = max(1, noteValue)
        return "#\(TmdBrailleGenerator.encodeUpperDigits(c))\(TmdBrailleGenerator.encodeLowerDigits(n))"
    }
}

private extension String {
    /// Transliterates text into uncontracted Grade 1 Literary Braille ASCII.
    var brailleLiteraryString: String {
        var out = ""
        var inNumber = false
        for ch in self {
            if ch.isNumber {
                if !inNumber {
                    out += "#"
                    inNumber = true
                }
                if let digit = Int(String(ch)) {
                    out += TmdBrailleGenerator.encodeUpperDigits(digit)
                }
            } else {
                inNumber = false
                if ch.isUppercase && ch.isASCII {
                    out += ",\(String(ch).uppercased())"
                } else if ch.isLowercase && ch.isASCII {
                    out += String(ch).uppercased()
                } else if ch == " " {
                    out += " "
                } else if ch == "-" || ch == "_" {
                    out += "-"
                }
            }
        }
        return out
    }

    /// Resolves the canonical Music Braille part prefix (`Section 6.2`) for a TMD assignment name.
    var braillePartPrefixAscii: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        switch lower {
        case "piano": return ">PN'"
        case "pianorh", "righthand": return ".>"
        case "pianolh", "lefthand": return "_>"
        case "organpedal": return "^>"
        case "violin": return ">VL'"
        case "violin1", "v1": return ">VL1'"
        case "violin2", "v2": return ">VL2'"
        case "violin3", "v3": return ">VL3'"
        case "viola": return ">VLA'"
        case "cello", "violoncello": return ">VC'"
        case "contrabass", "doublebass": return ">CB'"
        case "bass": return ">BS'"
        case "guitar": return ">GT'"
        case "flute": return ">FL'"
        case "oboe": return ">OB'"
        case "clarinet": return ">CL'"
        case "bassoon": return ">BSN'"
        case "horn": return ">HN'"
        case "trumpet": return ">TR'"
        case "trombone": return ">TBN'"
        case "tuba": return ">TBA'"
        case "timpani": return ">TIM'"
        case "drums", "percussion": return ">DR'"
        case "soprano": return ">S'"
        case "alto": return ">A'"
        case "tenor": return ">T'"
        case "vocal", "solo": return "\">"
        case "chord", "chords": return "3>"
        default:
            let letters = lower.filter { $0.isLetter && $0.isASCII }
            let digits = lower.filter { $0.isNumber }
            let abbr: String
            if letters.count <= 3 {
                abbr = letters.isEmpty ? "PN" : letters.uppercased()
            } else {
                let first = String(letters.first!).uppercased()
                let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
                let consonants = letters.dropFirst().filter { !vowels.contains($0) }
                if consonants.count >= 2 {
                    abbr = first + String(consonants.prefix(2)).uppercased()
                } else {
                    abbr = String(letters.prefix(3)).uppercased()
                }
            }
            let numSuffix = digits.isEmpty ? "" : digits
            return ">\(abbr)\(numSuffix)'"
        }
    }
}
