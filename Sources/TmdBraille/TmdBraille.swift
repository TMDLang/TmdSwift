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
    public var lineWidth: Int?
    public var targetSection: String?
    public var targetInstrument: String?

    public init(
        encoding: TmdBrailleEncoding = .unicode,
        layout: TmdBrailleLayout = .partByPart,
        lineWidth: Int? = 40,
        targetSection: String? = nil,
        targetInstrument: String? = nil
    ) {
        self.encoding = encoding
        self.layout = layout
        self.lineWidth = lineWidth
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
        let (workingSheet, _) = inputSheet.preparedForExport(
            fallbackToDefault: false,
            targetParagraph: options.targetSection,
            targetInstrument: options.targetInstrument
        )
        var instruments = distinctMusicalInstruments(in: workingSheet)
        if let targetInstrument = options.targetInstrument, !targetInstrument.isEmpty {
            instruments = instruments.filter {
                $0.caseInsensitiveCompare(targetInstrument) == .orderedSame
            }
        }

        let isSolo = instruments.count == 1 && options.layout == .partByPart
        var asciiLines: [String] = []

        // 1. Score Title Header (Grade 1 Uncontracted Literary Braille)
        let title = workingSheet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleAscii = title.isEmpty ? "" : title.brailleLiteraryString

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
        let headerAscii = "\(metronomeAscii) \(keySigAscii)\(timeSigAscii)"

        if isSolo, let width = options.lineWidth, width > 0 {
            if !titleAscii.isEmpty {
                asciiLines.append(centerBrailleLine(titleAscii, width: width))
                asciiLines.append("")
            }
            asciiLines.append(centerBrailleLine(headerAscii, width: width))
        } else {
            if !titleAscii.isEmpty {
                asciiLines.append(titleAscii)
            }
            asciiLines.append(headerAscii)
        }

        if instruments.isEmpty {
            let rawAscii = asciiLines.joined(separator: "\n") + "\n"
            return options.encoding == .unicode ? asciiToUnicodeBraille(rawAscii) : rawAscii
        }

        switch options.layout {
        case .partByPart:
            for inst in instruments {
                let prefix = isSolo ? "#A" : inst.braillePartPrefixAscii
                let trackLines = renderPartByPartTrackLines(
                    instrument: inst,
                    sheet: workingSheet,
                    isSolo: isSolo,
                    initialPrefix: prefix,
                    lineWidth: options.lineWidth
                )
                asciiLines.append(contentsOf: trackLines)
            }

        case .barOverBar:
            let renderedTracks = instruments.map { inst in
                renderTrackMeasures(instrument: inst, sheet: workingSheet, isSolo: false)
            }
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

    private static func centerBrailleLine(_ text: String, width: Int) -> String {
        let pad = max(3, (width - text.count) / 2)
        return String(repeating: " ", count: pad) + text
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

    private static func isBassClefInstrument(_ instrument: String) -> Bool {
        let clean = instrument.lowercased().filter { $0.isLetter || $0.isNumber }
        if clean.contains("bass") || clean.contains("cello") || clean.contains("trombone")
            || clean.contains("tuba") || clean.contains("euphonium") || clean.contains("timpani")
            || clean.contains("lefthand") || clean.contains("pianolh")
            || clean.contains("organpedal") || clean == "lh"
        {
            return true
        }
        return false
    }

    // MARK: - Track Measure Rendering & Line Wrapping

    private struct RenderedBrailleMeasure {
        let index: Int
        let isFullMeasureRest: Bool
        let hasLeadingKeyOrMeterChange: Bool
        let preMeasureDirectivesAscii: String
        let ascii: String
        let groupTokens: [String]
        let endsWithCrossBarTie: Bool
        let startsWithCrossBarTie: Bool
    }

    private struct RenderedBrailleTrack {
        let instrument: String
        let measures: [RenderedBrailleMeasure]
    }

    private struct MeasurePreparation {
        let measure: Measure
        let isFullMeasureRest: Bool
        let preDirectives: [String]
        let inlineDirectivesByOffset: [(offset: Double, ascii: String)]
        let defaultKeyStepAlters: [Int]
        let activeBeat: Beat
        let forceOctaveAtMeasureStart: Bool
        let startsWithTie: Bool
        let endsWithTie: Bool
    }

    private static func prepareTrackMeasures(
        instrument: String,
        sheet: Sheet
    ) -> (
        preparations: [MeasurePreparation],
        isChordTrack: Bool,
        isPercussion: Bool
    ) {
        let measures = TmdMeasureRenderer.renderMeasures(sheet: sheet, instrument: instrument)
        let isFixedPitchTrack = sheet.entries.contains {
            $0.assignment?.caseInsensitiveCompare(instrument) == .orderedSame
                && $0.pitchMode == .fixed
        }
        let isChordTrack = Sheet.isChordSymbolTrack(instrument)
        let isPercussion = sheet.isPercussionTrack(instrument: instrument)

        var activeWrittenKey =
            isFixedPitchTrack
            ? "C"
            : (sheet.declaredKey
                ?? PitchMapping.tonicScaleInfo(forKeyOffset: sheet.keySignature.semitoneOffset)
                .name)
        var activeKeyOffset = isFixedPitchTrack ? 0 : sheet.keySignature.semitoneOffset
        var defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: activeWrittenKey)
        var activeBeat = sheet.beat

        var preparations: [MeasurePreparation] = []

        for (mIdx, measure) in measures.enumerated() {
            var preDirectives: [String] = []
            var inlineDirectivesByOffset: [(offset: Double, ascii: String)] = []
            var forceOctaveAtStart = (mIdx == 0)

            for directive in measure.directives {
                switch directive.kind {
                case .explicitKey(let key), .absoluteKey(let key):
                    if !isFixedPitchTrack && key != activeWrittenKey {
                        let ks = encodeKeySignatureChange(from: activeWrittenKey, to: key)
                        activeWrittenKey = key
                        defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: key)
                        if !ks.isEmpty {
                            preDirectives.append(ks)
                        }
                        forceOctaveAtStart = true
                    }
                case .relativeKey:
                    if !isFixedPitchTrack && sheet.declaredKey == nil {
                        let newKey = PitchMapping.tonicScaleInfo(
                            forKeyOffset: directive.state.keyOffset
                        ).name
                        if newKey != activeWrittenKey {
                            let ks = encodeKeySignatureChange(from: activeWrittenKey, to: newKey)
                            activeWrittenKey = newKey
                            activeKeyOffset = directive.state.keyOffset
                            defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(
                                forKey: newKey)
                            if !ks.isEmpty {
                                preDirectives.append(ks)
                            }
                            forceOctaveAtStart = true
                        }
                    }
                case .fixedPitch:
                    activeWrittenKey = "C"
                    defaultKeyStepAlters = [0, 0, 0, 0, 0, 0, 0]
                case .timeSignature(let beat):
                    if beat != activeBeat {
                        activeBeat = beat
                        preDirectives.append(beat.brailleTimeSignature)
                        forceOctaveAtStart = true
                    }
                case .tempo, .relativeTempo:
                    let bpm = Int(directive.state.tempo.rounded())
                    preDirectives.append("?7#\(encodeUpperDigits(bpm))")
                    forceOctaveAtStart = true
                case .dynamics(let mark):
                    let relOffset = max(0.0, directive.position - measure.startTime)
                    inlineDirectivesByOffset.append((relOffset, ">\(mark.rawValue.uppercased())"))
                }
            }

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
                    let ks = encodeKeySignatureChange(from: activeWrittenKey, to: newKey)
                    activeWrittenKey = newKey
                    defaultKeyStepAlters = PitchMapping.keySignatureStepAlters(forKey: newKey)
                    if !ks.isEmpty {
                        preDirectives.append(ks)
                    }
                    forceOctaveAtStart = true
                }
            }

            let isFullRest = nonRestEvents.isEmpty && inlineDirectivesByOffset.isEmpty
            let groups = measure.simultaneousEventGroups
            let startsWithTie = groups.first?.contains(where: { $0.tieStop }) ?? false
            let endsWithTie = groups.last?.contains(where: { $0.tieStart }) ?? false

            preparations.append(
                MeasurePreparation(
                    measure: measure,
                    isFullMeasureRest: isFullRest,
                    preDirectives: preDirectives,
                    inlineDirectivesByOffset: inlineDirectivesByOffset,
                    defaultKeyStepAlters: defaultKeyStepAlters,
                    activeBeat: activeBeat,
                    forceOctaveAtMeasureStart: forceOctaveAtStart,
                    startsWithTie: startsWithTie,
                    endsWithTie: endsWithTie
                )
            )
        }

        return (preparations, isChordTrack, isPercussion)
    }

    private static func renderSinglePreparedMeasure(
        prep: MeasurePreparation,
        isChordTrack: Bool,
        isPercussion: Bool,
        useTopDownIntervals: Bool,
        lastPitch: inout (octave: Int, stepIndex: Int)?,
        forceOctave: inout Bool
    ) -> RenderedBrailleMeasure {
        if prep.forceOctaveAtMeasureStart {
            forceOctave = true
        }
        if prep.isFullMeasureRest {
            return RenderedBrailleMeasure(
                index: prep.measure.index,
                isFullMeasureRest: true,
                hasLeadingKeyOrMeterChange: !prep.preDirectives.isEmpty,
                preMeasureDirectivesAscii: prep.preDirectives.joined(separator: " "),
                ascii: "M",
                groupTokens: ["M"],
                endsWithCrossBarTie: false,
                startsWithCrossBarTie: false
            )
        }

        let groups = prep.measure.simultaneousEventGroups
        let specs = groups.map { grp -> BrailleDurationSpec in
            guard let first = grp.first else {
                return BrailleDurationSpec(
                    atoms: [NotationDuration(baseDenominator: 4, isDotted: false, quarterValue: 1.0)],
                    tuplet: nil
                )
            }
            return resolveBrailleDuration(quarterNotes: first.duration)
        }

        // Build flat rhythmic items for BANA Par. 8.1 grouping and Par. 2.4 value distinction
        var flatItems: [MeasureRhythmicItem] = []
        for (gIdx, grp) in groups.enumerated() {
            guard let primary = grp.first else { continue }
            let isRest: Bool
            if case .rest = primary.content { isRest = true } else { isRest = false }
            let spec = specs[gIdx]
            var curOffset = primary.startOffset
            for (aIdx, atom) in spec.atoms.enumerated() {
                flatItems.append(
                    MeasureRhythmicItem(
                        groupIndex: gIdx,
                        atomIndex: aIdx,
                        baseDenominator: atom.baseDenominator,
                        isDotted: atom.isDotted,
                        quarterValue: atom.quarterValue,
                        startOffset: curOffset,
                        isRest: isRest,
                        tuplet: spec.tuplet
                    )
                )
                curOffset += atom.quarterValue
            }
        }

        let (groupedFlatIndices, distinctionHints) =
            (isChordTrack || isPercussion)
            ? (Set<Int>(), [Int: ValueDistinctionHint]())
            : planMeasureGroupingAndHints(
                items: flatItems,
                meter: prep.activeBeat,
                nominalDuration: prep.measure.nominalDuration
            )

        var flatIndexByGroupAtom: [String: Int] = [:]
        for (fIdx, item) in flatItems.enumerated() {
            flatIndexByGroupAtom["\(item.groupIndex):\(item.atomIndex)"] = fIdx
        }

        var measureStepAlters: [Int: [Int]] = [:]
        var consumedDirectiveIndices: Set<Int> = []
        var groupTokens: [String] = []
        var tupletRemaining = 0
        var activeTupletActual = 0

        for (gIdx, group) in groups.enumerated() {
            guard let primary = group.first else { continue }
            let spec = specs[gIdx]

            // Check tuplet prefix on the first atom of this group
            var tupletPrefixAscii = ""
            if let tup = spec.tuplet {
                if tupletRemaining == 0 || activeTupletActual != tup.actual {
                    tupletPrefixAscii =
                        tup.actual == 3 ? "2" : "_\(encodeLowerDigits(tup.actual))'"
                    activeTupletActual = tup.actual
                    tupletRemaining = tup.actual - 1
                } else {
                    tupletRemaining -= 1
                }
            } else {
                tupletRemaining = 0
                activeTupletActual = 0
            }

            // Emit any inline dynamics at or before primary.startOffset
            var pendingDynamicAscii = ""
            for (dIdx, item) in prep.inlineDirectivesByOffset.enumerated()
            where !consumedDirectiveIndices.contains(dIdx)
                && item.offset <= primary.startOffset + 1e-4
            {
                consumedDirectiveIndices.insert(dIdx)
                pendingDynamicAscii += item.ascii
                forceOctave = true
            }

            let groupAscii = renderEventGroup(
                group: group,
                groupIndex: gIdx,
                spec: spec,
                flatIndexByGroupAtom: flatIndexByGroupAtom,
                groupedFlatIndices: groupedFlatIndices,
                distinctionHints: distinctionHints,
                tupletPrefixAscii: tupletPrefixAscii,
                pendingDynamicAscii: pendingDynamicAscii,
                isChordTrack: isChordTrack,
                isPercussion: isPercussion,
                useTopDownIntervals: useTopDownIntervals,
                defaultKeyStepAlters: prep.defaultKeyStepAlters,
                measureStepAlters: &measureStepAlters,
                lastPitch: &lastPitch,
                forceOctave: &forceOctave
            )
            groupTokens.append(groupAscii)
        }

        return RenderedBrailleMeasure(
            index: prep.measure.index,
            isFullMeasureRest: false,
            hasLeadingKeyOrMeterChange: !prep.preDirectives.isEmpty,
            preMeasureDirectivesAscii: prep.preDirectives.joined(separator: " "),
            ascii: groupTokens.joined(),
            groupTokens: groupTokens,
            endsWithCrossBarTie: prep.endsWithTie,
            startsWithCrossBarTie: prep.startsWithTie
        )
    }

    private static func renderTrackMeasures(
        instrument: String,
        sheet: Sheet,
        isSolo: Bool
    ) -> RenderedBrailleTrack {
        let (preparations, isChordTrack, isPercussion) = prepareTrackMeasures(
            instrument: instrument, sheet: sheet)
        let useTopDownIntervals = isSolo && !isPercussion && !isBassClefInstrument(instrument)
        var lastPitch: (octave: Int, stepIndex: Int)? = nil
        var forceOctave = true
        let outMeasures = preparations.map { prep in
            renderSinglePreparedMeasure(
                prep: prep,
                isChordTrack: isChordTrack,
                isPercussion: isPercussion,
                useTopDownIntervals: useTopDownIntervals,
                lastPitch: &lastPitch,
                forceOctave: &forceOctave
            )
        }
        return RenderedBrailleTrack(instrument: instrument, measures: outMeasures)
    }

    private static func renderPartByPartTrackLines(
        instrument: String,
        sheet: Sheet,
        isSolo: Bool,
        initialPrefix: String,
        lineWidth: Int?
    ) -> [String] {
        let (preparations, isChordTrack, isPercussion) = prepareTrackMeasures(
            instrument: instrument, sheet: sheet)
        let useTopDownIntervals = isSolo && !isPercussion && !isBassClefInstrument(instrument)

        // Group consecutive full-measure rests and cross-barline tied measures into atomic blocks
        enum TrackBlock {
            case restRun(preDirectives: String, count: Int)
            case measureChain(indices: [Int])
        }

        var blocks: [TrackBlock] = []
        var i = 0
        while i < preparations.count {
            let p = preparations[i]
            if p.isFullMeasureRest {
                var restCount = 1
                var j = i + 1
                while j < preparations.count && preparations[j].isFullMeasureRest
                    && preparations[j].preDirectives.isEmpty
                {
                    restCount += 1
                    j += 1
                }
                blocks.append(
                    .restRun(
                        preDirectives: p.preDirectives.joined(separator: " "),
                        count: restCount
                    ))
                i = j
            } else {
                var chain = [i]
                var cur = p
                var j = i + 1
                while j < preparations.count && cur.endsWithTie
                    && preparations[j].startsWithTie
                    && preparations[j].preDirectives.isEmpty
                    && !preparations[j].isFullMeasureRest
                {
                    chain.append(j)
                    cur = preparations[j]
                    j += 1
                }
                blocks.append(.measureChain(indices: chain))
                i = j
            }
        }

        guard let maxW = lineWidth, maxW > 0 else {
            let rendered = renderTrackMeasures(instrument: instrument, sheet: sheet, isSolo: isSolo)
            let body = joinTrackMeasuresAscii(rendered.measures)
            return ["\(initialPrefix) \(body)<K"]
        }

        var lines: [String] = []
        var currentLine = initialPrefix
        var lastPitch: (octave: Int, stepIndex: Int)? = nil
        var forceOctave = true

        func appendSimpleToken(_ token: String) {
            guard !token.isEmpty else { return }
            let sep = currentLine.hasSuffix(" ") ? "" : " "
            if currentLine.trimmingCharacters(in: .whitespaces).isEmpty {
                currentLine += token
            } else if currentLine.count + sep.count + token.count <= maxW {
                currentLine += sep + token
            } else {
                lines.append(currentLine)
                currentLine = "  " + token
                forceOctave = true
            }
        }

        for (bIdx, block) in blocks.enumerated() {
            let isLastBlock = (bIdx == blocks.count - 1)
            let suffix = isLastBlock ? "<K" : ""

            switch block {
            case .restRun(let preDirectives, let count):
                if !preDirectives.isEmpty {
                    appendSimpleToken(preDirectives)
                }
                let restToken = encodeFullMeasureRests(count: count) + suffix
                appendSimpleToken(restToken)

            case .measureChain(let indices):
                let firstPrep = preparations[indices[0]]
                let preDir = firstPrep.preDirectives.joined(separator: " ")
                if !preDir.isEmpty {
                    appendSimpleToken(preDir)
                }

                let savedPitch = lastPitch
                let savedForce = forceOctave
                var trialPitch = savedPitch
                var trialForce = savedForce
                var trialMeasures: [RenderedBrailleMeasure] = []
                for idx in indices {
                    trialMeasures.append(
                        renderSinglePreparedMeasure(
                            prep: preparations[idx],
                            isChordTrack: isChordTrack,
                            isPercussion: isPercussion,
                            useTopDownIntervals: useTopDownIntervals,
                            lastPitch: &trialPitch,
                            forceOctave: &trialForce
                        )
                    )
                }
                let combinedAscii = trialMeasures.map(\.ascii).joined() + suffix
                let sep = currentLine.hasSuffix(" ") ? "" : " "
                let lineHasMusicContent = !currentLine.trimmingCharacters(in: .whitespaces).isEmpty

                if !lineHasMusicContent && currentLine.count + combinedAscii.count <= maxW {
                    currentLine += combinedAscii
                    lastPitch = trialPitch
                    forceOctave = trialForce
                } else if lineHasMusicContent
                    && currentLine.count + sep.count + combinedAscii.count <= maxW
                {
                    currentLine += sep + combinedAscii
                    lastPitch = trialPitch
                    forceOctave = trialForce
                } else {
                    // Wrap to a new continuation line (`  `) and force octave mark on first pitched note (Par. CN-4)
                    if lineHasMusicContent {
                        lines.append(currentLine)
                        currentLine = "  "
                    }
                    var newLinePitch = savedPitch
                    var newLineForce = true
                    var newLineMeasures: [RenderedBrailleMeasure] = []
                    for idx in indices {
                        newLineMeasures.append(
                            renderSinglePreparedMeasure(
                                prep: preparations[idx],
                                isChordTrack: isChordTrack,
                                isPercussion: isPercussion,
                                useTopDownIntervals: useTopDownIntervals,
                                lastPitch: &newLinePitch,
                                forceOctave: &newLineForce
                            )
                        )
                    }
                    let newCombined = newLineMeasures.map(\.ascii).joined() + suffix
                    let newSep =
                        (currentLine == "  " || currentLine.hasSuffix(" ")) ? "" : " "
                    if currentLine.count + newSep.count + newCombined.count <= maxW {
                        currentLine += newSep + newCombined
                        lastPitch = newLinePitch
                        forceOctave = newLineForce
                    } else {
                        // Single measure / chain exceeds maxW: split between event groups with unfinished-measure hyphen `"`
                        if !newSep.isEmpty {
                            currentLine += newSep
                        }
                        let allGroups = newLineMeasures.flatMap(\.groupTokens)
                        for (gIdx, gToken) in allGroups.enumerated() {
                            let isLastGroup = (gIdx == allGroups.count - 1)
                            let tokWithSuffix = isLastGroup ? (gToken + suffix) : gToken
                            let reserve = isLastGroup ? 0 : 1  // reserve 1 cell for `"` hyphen
                            if currentLine.count + tokWithSuffix.count + reserve > maxW
                                && !currentLine.trimmingCharacters(in: .whitespaces).isEmpty
                            {
                                lines.append(currentLine + "\"")
                                currentLine = "  " + tokWithSuffix
                            } else {
                                currentLine += tokWithSuffix
                            }
                        }
                        lastPitch = newLinePitch
                        forceOctave = newLineForce
                    }
                }
            }
        }

        if !currentLine.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(currentLine)
        }
        return lines
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

    // MARK: - Duration, Tuplet, Grouping (Par. 8.1), and Value Distinction (Par. 2.4)

    private struct BrailleDurationSpec {
        let atoms: [NotationDuration]
        let tuplet: (actual: Int, normal: Int)?
    }

    private static let brailleStandardValues: [NotationDuration] = [
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
        NotationDuration(baseDenominator: 64, isDotted: true, quarterValue: 0.09375),
        NotationDuration(baseDenominator: 64, isDotted: false, quarterValue: 0.0625),
        NotationDuration(baseDenominator: 128, isDotted: false, quarterValue: 0.03125),
    ]

    private static func resolveBrailleDuration(quarterNotes: Double) -> BrailleDurationSpec {
        let epsilon = 1e-4
        for std in brailleStandardValues {
            if abs(quarterNotes - std.quarterValue) < epsilon {
                return BrailleDurationSpec(atoms: [std], tuplet: nil)
            }
        }

        let tupletRatios: [(actual: Int, normal: Int)] = [
            (3, 2),
            (5, 4), (5, 3),
            (7, 4), (7, 5), (7, 6),
            (9, 8),
            (11, 8), (11, 7),
            (13, 8),
            (2, 3),
            (4, 3),
            (6, 4),
        ]
        let baseDenominators = [1, 2, 4, 8, 16, 32, 64, 128]
        for ratio in tupletRatios {
            for baseDen in baseDenominators {
                let faceQ = 4.0 / Double(baseDen)
                let tupQ = faceQ * Double(ratio.normal) / Double(ratio.actual)
                if abs(quarterNotes - tupQ) < epsilon {
                    return BrailleDurationSpec(
                        atoms: [
                            NotationDuration(
                                baseDenominator: baseDen,
                                isDotted: false,
                                quarterValue: quarterNotes
                            )
                        ],
                        tuplet: ratio
                    )
                }
            }
        }

        var remaining = quarterNotes
        var result: [NotationDuration] = []
        while remaining > epsilon {
            var matched = false
            for std in brailleStandardValues {
                if remaining >= std.quarterValue - epsilon {
                    result.append(std)
                    remaining -= std.quarterValue
                    matched = true
                    break
                }
            }
            if !matched {
                if remaining > 1e-6 {
                    result.append(
                        NotationDuration(
                            baseDenominator: 128, isDotted: false, quarterValue: remaining)
                    )
                }
                break
            }
        }
        if result.isEmpty {
            result.append(NotationDuration(baseDenominator: 4, isDotted: false, quarterValue: 1.0))
        }
        return BrailleDurationSpec(atoms: result, tuplet: nil)
    }

    private struct MeasureRhythmicItem {
        let groupIndex: Int
        let atomIndex: Int
        let baseDenominator: Int
        let isDotted: Bool
        let quarterValue: Double
        let startOffset: Double
        let isRest: Bool
        let tuplet: (actual: Int, normal: Int)?
    }

    private enum ValueDistinctionHint: String {
        case large = "^<1"
        case small = ",<1"
    }

    private static func valueClass(for baseDenominator: Int) -> Int {
        switch baseDenominator {
        case 1, 16: return 0
        case 2, 32: return 1
        case 4, 64: return 2
        default: return 3
        }
    }

    private static func planMeasureGroupingAndHints(
        items: [MeasureRhythmicItem],
        meter: Beat,
        nominalDuration: Double
    ) -> (groupedIndices: Set<Int>, hints: [Int: ValueDistinctionHint]) {
        guard !items.isEmpty else { return ([], [:]) }

        // Special single 16th-rest rule (BANA Par. 2.4)
        if items.count == 1 && items[0].isRest && items[0].baseDenominator == 16
            && !items[0].isDotted && items[0].tuplet == nil
        {
            return ([], [0: .small])
        }

        let actualTotal = items.reduce(0.0) { $0 + $1.quarterValue }
        let mismatch = abs(actualTotal - nominalDuration) > 1e-3

        // 1. Compute 16th/32nd/64th beat grouping (BANA Par. 8.1)
        var groupedIndices: Set<Int> = []
        if !mismatch {
            let num = max(1, meter.count)
            let den = max(1, meter.noteValue)
            let compound = (num % 3 == 0 && num > 3)
            let beatQ = compound ? (12.0 / Double(den)) : (4.0 / Double(den))
            let candidateUnits = compound ? [beatQ, 4.0 / Double(den)] : [beatQ, beatQ / 2.0]

            var idx = 0
            while idx < items.count {
                let ev = items[idx]
                var grouped = false
                if ev.baseDenominator >= 16 && ev.baseDenominator <= 64 && !ev.isDotted
                    && ev.tuplet == nil
                {
                    let nv = 4.0 / Double(ev.baseDenominator)
                    var cands: [(u: Double, count: Int)] = []
                    for u in candidateUnits {
                        let c = Int((u / nv).rounded())
                        if c >= 3 && abs(Double(c) * nv - u) < 1e-4 {
                            cands.append((u, c))
                        }
                    }
                    cands.sort { $0.u < $1.u }
                    let pick =
                        cands.contains(where: { $0.count >= 4 })
                        ? cands.filter { $0.count >= 4 } : cands

                    for cand in pick {
                        let gridRatio = ev.startOffset / cand.u
                        let gridAligned = abs(gridRatio - gridRatio.rounded()) < 1e-3
                        guard gridAligned, idx + cand.count <= items.count else { continue }
                        var allPlainNotes = true
                        for k in 1..<cand.count {
                            let nextItem = items[idx + k]
                            if nextItem.isRest || nextItem.baseDenominator != ev.baseDenominator
                                || nextItem.isDotted || nextItem.tuplet != nil
                            {
                                allPlainNotes = false
                                break
                            }
                        }
                        guard allPlainNotes else { continue }
                        let hasFollowingEighth = items[(idx + cand.count)...].contains {
                            $0.baseDenominator == 8
                        }
                        guard !hasFollowingEighth else { continue }
                        for k in 1..<cand.count {
                            groupedIndices.insert(idx + k)
                        }
                        idx += cand.count
                        grouped = true
                        break
                    }
                }
                if !grouped {
                    idx += 1
                }
            }
        }

        // 2. Check if value distinction signs (`^<1` / `,<1`) are needed (Par. 1-4 / BANA Par. 2.4)
        var hints: [Int: ValueDistinctionHint] = [:]
        let hasSmall = items.contains { $0.baseDenominator >= 16 }
        guard hasSmall || mismatch else {
            return (groupedIndices, hints)
        }

        // Check same-class coexistence between large (1..8) and small (16..128) values (1996 Manual Par. 1-4)
        var largeClasses: Set<Int> = []
        var smallClasses: Set<Int> = []
        for (idx, it) in items.enumerated() {
            let effectiveDen = groupedIndices.contains(idx) ? 8 : it.baseDenominator
            let cls = valueClass(for: effectiveDen)
            if it.baseDenominator >= 16 {
                smallClasses.insert(cls)
            } else {
                largeClasses.insert(cls)
            }
        }
        let sharedClasses = largeClasses.intersection(smallClasses)
        if !sharedClasses.isEmpty {
            var currentModeIsSmall: Bool? = nil
            for (idx, it) in items.enumerated() {
                let isSmall = it.baseDenominator >= 16
                let cls = valueClass(for: it.baseDenominator)
                if let prevSmall = currentModeIsSmall {
                    if isSmall != prevSmall && sharedClasses.contains(cls) {
                        hints[idx] = isSmall ? .small : .large
                    }
                }
                currentModeIsSmall = isSmall
            }
        }

        if mismatch && hints.isEmpty {
            for (idx, it) in items.enumerated() {
                if it.baseDenominator >= 16 {
                    hints[idx] = .small
                    break
                }
            }
        }

        return (groupedIndices, hints)
    }

    // MARK: - Event Group Encoding

    private static func renderEventGroup(
        group: [MeasureEvent],
        groupIndex: Int,
        spec: BrailleDurationSpec,
        flatIndexByGroupAtom: [String: Int],
        groupedFlatIndices: Set<Int>,
        distinctionHints: [Int: ValueDistinctionHint],
        tupletPrefixAscii: String,
        pendingDynamicAscii: String,
        isChordTrack: Bool,
        isPercussion: Bool,
        useTopDownIntervals: Bool,
        defaultKeyStepAlters: [Int],
        measureStepAlters: inout [Int: [Int]],
        lastPitch: inout (octave: Int, stepIndex: Int)?,
        forceOctave: inout Bool
    ) -> String {
        guard let first = group.first else { return "" }
        let atoms = spec.atoms

        // 1. Check if group contains simultaneous pitched notes
        var notes: [(note: Note, event: MeasureEvent, spelled: SpelledPitch)] = []
        for ev in group {
            if case .note(let n) = ev.content {
                let spelled = PitchMapping.spell(note: n, keyOffset: ev.state.keyOffset)
                notes.append((n, ev, spelled))
            }
        }

        if !notes.isEmpty {
            if useTopDownIntervals {
                // Sort top-down (highest pitch first) for treble-clef solo parts (Par. 5-2 / BANA Par. 9.2)
                notes.sort {
                    let d0 = $0.spelled.octave * 7 + $0.spelled.stepIndex
                    let d1 = $1.spelled.octave * 7 + $1.spelled.stepIndex
                    if d0 != d1 { return d0 > d1 }
                    return $0.spelled.midiPitch > $1.spelled.midiPitch
                }
            } else {
                // Sort bottom-up (lowest pitch first) for bass-clef solo and all multi-track parts (Par. 20-6)
                notes.sort {
                    let d0 = $0.spelled.octave * 7 + $0.spelled.stepIndex
                    let d1 = $1.spelled.octave * 7 + $1.spelled.stepIndex
                    if d0 != d1 { return d0 < d1 }
                    return $0.spelled.midiPitch < $1.spelled.midiPitch
                }
            }

            var out = ""
            for (atomIdx, atom) in atoms.enumerated() {
                let flatIdx = flatIndexByGroupAtom["\(groupIndex):\(atomIdx)"] ?? -1
                let hintStr = distinctionHints[flatIdx]?.rawValue ?? ""
                if !hintStr.isEmpty {
                    forceOctave = true
                }
                let effectiveAtom =
                    groupedFlatIndices.contains(flatIdx)
                    ? NotationDuration(
                        baseDenominator: 8, isDotted: false, quarterValue: atom.quarterValue)
                    : atom

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

                let noteCell = effectiveAtom.brailleNoteCell(stepIndex: base.spelled.stepIndex)

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
                    let deltaFromBase =
                        useTopDownIntervals
                        ? max(0, baseDiatonic - memDiatonic)
                        : max(0, memDiatonic - baseDiatonic)
                    let deltaFromPrev =
                        useTopDownIntervals
                        ? max(0, prevDiatonic - memDiatonic)
                        : max(0, memDiatonic - prevDiatonic)
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
                    tieStr = notes.count > 1 ? ".C" : "@C"
                } else {
                    tieStr = ""
                }

                let tupStr = atomIdx == 0 ? tupletPrefixAscii : ""
                let coreBody = "\(tupStr)\(accStr)\(octStr)\(noteCell)\(intervalsStr)\(tieStr)"
                let dynStr: String
                if atomIdx == 0 && !pendingDynamicAscii.isEmpty {
                    if let firstChar = coreBody.first, cellUsesDots123(firstChar) {
                        dynStr = "\(pendingDynamicAscii)'"
                    } else {
                        dynStr = pendingDynamicAscii
                    }
                } else {
                    dynStr = ""
                }

                out += "\(hintStr)\(dynStr)\(coreBody)"
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
                let rawVoiced = PitchMapping.spellChordVoicing(
                    chord, keyOffset: first.state.keyOffset)
                let voiced = useTopDownIntervals ? Array(rawVoiced.reversed()) : rawVoiced
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
                        let memDiatonic = member.octave * 7 + member.stepIndex
                        let delta =
                            useTopDownIntervals
                            ? max(1, baseDiatonic - memDiatonic)
                            : max(1, memDiatonic - baseDiatonic)
                        let intIdx = ((delta - 1) % 7) + 1
                        let intOct = delta > 7 ? encodeOctaveMark(member.octave) : ""
                        intervalsStr += "\(memAcc)\(intOct)\(encodeIntervalSign(intIdx))"
                    }
                    let tieStr = atomIdx < atoms.count - 1 ? ".C" : ""
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
                resolveBrailleDuration(quarterNotes: subDur).atoms.first
                ?? NotationDuration(baseDenominator: 4, isDotted: false, quarterValue: 1.0)
            var out = ""
            for ch in clean {
                if ch == "-" || ch == "." {
                    out += subAtom.brailleRestCell
                    continue
                }
                let pos =
                    PercussionStroke(character: ch)?.unpitchedDisplayPosition
                    ?? PercussionStroke.snare.unpitchedDisplayPosition
                let (stepIdx, oct) = (pos.stepIndex, pos.octave)
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
        var restOut = ""
        for (atomIdx, atom) in atoms.enumerated() {
            let flatIdx = flatIndexByGroupAtom["\(groupIndex):\(atomIdx)"] ?? -1
            let hintStr = distinctionHints[flatIdx]?.rawValue ?? ""
            if !hintStr.isEmpty {
                forceOctave = true
            }
            let tupStr = atomIdx == 0 ? tupletPrefixAscii : ""
            restOut += "\(hintStr)\(tupStr)\(prefix)\(atom.brailleRestCell)"
        }
        return restOut
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

    private static func encodeNaturalCancellation(count: Int) -> String {
        guard count > 0 else { return "" }
        if count <= 3 {
            return String(repeating: "*", count: count)
        }
        return "#\(encodeUpperDigits(count))*"
    }

    private static func encodeKeySignatureChange(from previousKey: String, to newKey: String) -> String {
        let p = PitchMapping.parseKeyModeAndFifths(previousKey).fifths
        let k = PitchMapping.parseKeyModeAndFifths(newKey).fifths
        if p == k { return "" }
        let cancelCount: Int
        if p != 0 && (k == 0 || (p > 0) != (k > 0)) {
            cancelCount = abs(p)
        } else if p != 0 && abs(k) < abs(p) {
            cancelCount = abs(p) - abs(k)
        } else {
            cancelCount = 0
        }
        return encodeNaturalCancellation(count: cancelCount) + encodeKeySignature(forKey: newKey)
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
