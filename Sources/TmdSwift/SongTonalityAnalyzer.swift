import Foundation

/// Extracts pitch-class weighting, tonality inference, and modulation narratives.
public enum TMDSongTonalityAnalyzer {
    public static func analyze(
        sheet: Sheet,
        timingProfile: TMDTimingProfile,
        locale: TMDLocale
    ) -> TMDTonalityProfile {
        let localizer = TMDLocalizer(locale: locale)
        let distinctInsts = sheet.distinctInstruments(fallbackToDefault: false)
        var allEvents: [PlaybackEvent] = []
        for inst in distinctInsts {
            let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: inst)
            allEvents.append(contentsOf: timeline.events)
        }

        var globalWeights = [Double](repeating: 0.0, count: 12)
        var noteWeight = 0.0
        var chordWeight = 0.0
        var sectionWeights: [Int: [Double]] = [:]  // Section index in timingProfile -> 12 weights
        for idx in 0..<timingProfile.sections.count {
            sectionWeights[idx] = [Double](repeating: 0.0, count: 12)
        }

        // 1. Accumulate melody notes
        for event in allEvents {
            guard case .note(let note) = event.content else { continue }
            let pitch = note.midiPitch(keyOffset: event.state.keyOffset)
            let pc = (pitch % 12 + 12) % 12
            let dur = event.duration

            globalWeights[pc] += dur
            noteWeight += dur

            for (secIdx, sec) in timingProfile.sections.enumerated() {
                let overlap = overlapDuration(
                    eventPosition: event.position,
                    eventDuration: dur,
                    sectionStart: sec.startPositionQuarterNotes,
                    sectionDuration: sec.durationQuarterNotes
                )
                if overlap > 0.0 {
                    sectionWeights[secIdx]![pc] += overlap
                }
            }
        }

        // 2. Accumulate chord symbol constituents
        for event in allEvents {
            guard case .chord(let chord) = event.content else { continue }
            let dur = event.duration
            let chordPCs = chordPitchClasses(chord, keyOffset: event.state.keyOffset)
            for (pc, weightFactor) in chordPCs {
                let w = dur * weightFactor
                globalWeights[pc] += w
                chordWeight += w
                for (secIdx, sec) in timingProfile.sections.enumerated() {
                    let overlap = overlapDuration(
                        eventPosition: event.position,
                        eventDuration: dur,
                        sectionStart: sec.startPositionQuarterNotes,
                        sectionDuration: sec.durationQuarterNotes
                    )
                    if overlap > 0.0 {
                        sectionWeights[secIdx]![pc] += weightFactor * overlap
                    }
                }
            }
        }

        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let baseKey = sheet.keySignature.description

        // Infer tonality from sounding evidence. The movable-do base is only playback context.
        let globalInference = evaluateTonality(
            weights: globalWeights,
            evidence: TMDTonalityEvidence(noteWeight: noteWeight, chordWeight: chordWeight))
        let globalTonicOffset =
            globalInference.tonic.map { pitchClassOffset($0) } ?? sheet.keySignature.semitoneOffset
        let globalDisplayMode =
            globalInference.mode == .ambiguous
            ? (globalInference.topCandidates.first?.mode ?? .major) : globalInference.mode
        let globalDist = makePitchClassDistribution(
            weights: globalWeights, tonicOffset: globalTonicOffset, mode: globalDisplayMode)

        // Sections
        var sectionProfiles: [TMDSectionTonalityProfile] = []
        var circleOfFifthsPath: [Int] = []

        for (secIdx, sec) in timingProfile.sections.enumerated() {
            let weights = sectionWeights[secIdx] ?? [Double](repeating: 0.0, count: 12)
            let fixedPitch = sheet.entries
                .filter { $0.name == sec.name }
                .contains { paragraph in
                    paragraph.sections.contains { section in
                        section.directives.contains { directive in
                            if case .fixedPitch = directive.kind { return true }
                            return false
                        }
                    }
                }
            // PlaybackState.keyOffset already includes the initial score key.
            // Adding sheet.keySignature here would apply that key twice for
            // scores whose initial key is not C.
            let secInference = evaluateTonality(weights: weights)
            let secTonicOffset =
                secInference.tonic.map { pitchClassOffset($0) } ?? (sec.keyOffset % 12 + 12) % 12
            let secDisplayMode =
                secInference.mode == .ambiguous
                ? (secInference.topCandidates.first?.mode ?? .major) : secInference.mode
            let secDist = makePitchClassDistribution(
                weights: weights, tonicOffset: secTonicOffset, mode: secDisplayMode)

            let diatonicMask = diatonicPitchClassMask(
                tonicOffset: secTonicOffset, mode: secDisplayMode)
            var nonDiatonic: [String] = []
            for pc in 0..<12 {
                if !diatonicMask.contains(pc) && weights[pc] > 0.001 {
                    nonDiatonic.append(pitchClassNames[pc])
                }
            }

            let fifthsStep = circleOfFifthsStep(tonicOffset: secTonicOffset)
            circleOfFifthsPath.append(fifthsStep)

            sectionProfiles.append(
                TMDSectionTonalityProfile(
                    sectionName: sec.name,
                    occurrenceIndex: sec.occurrenceIndex,
                    playbackContext: TMDPlaybackContext(
                        movableDoBase: baseKey, transpositionOffset: sec.keyOffset,
                        fixedPitch: fixedPitch),
                    fifthsPosition: fifthsStep,
                    pitchClasses: secDist,
                    inferredTonality: secInference,
                    nonDiatonicNotes: nonDiatonic
                ))
        }

        // Human-friendly producer narrative synthesis
        let diatonicRatio = globalDist.diatonicRatio
        let moodKey: TMDLocalizationKey
        if globalInference.mode == .insufficient {
            moodKey = .moodInsufficient
        } else if globalInference.mode == .minor && diatonicRatio >= 0.95 {
            moodKey = .moodCleanMinor
        } else if globalInference.mode == .minor && diatonicRatio >= 0.80 {
            moodKey = .moodContemporaryMinor
        } else if diatonicRatio >= 0.95 {
            moodKey = .moodCleanMajor
        } else if diatonicRatio >= 0.80 {
            moodKey = .moodContemporaryMajor
        } else {
            moodKey = .moodModal
        }
        let moodDescription = localizer.text(moodKey)

        // Modulation story
        var modTransitions: [String] = []
        var inferredModulationPath: [TMDTonalityTransition] = []
        var previousInference: TMDTonalityInference?
        var prevOffset = globalTonicOffset
        var prevFifths = circleOfFifthsStep(tonicOffset: prevOffset)
        for sec in sectionProfiles {
            let current = sec.inferredTonality
            if let previous = previousInference, isStable(previous), isStable(current),
                current.tonic != previous.tonic || current.mode != previous.mode,
                let currentTonic = current.tonic
            {
                let currentOffset = pitchClassOffset(currentTonic)
                let diff = currentOffset - prevOffset
                let semitoneDiff = diff >= 0 ? "+\(diff)" : "\(diff)"
                var stepDiff = circleOfFifthsStep(tonicOffset: currentOffset) - prevFifths
                if stepDiff > 6 { stepDiff -= 12 }
                if stepDiff < -6 { stepDiff += 12 }
                let stepStr = stepDiff >= 0 ? "+\(stepDiff)" : "\(stepDiff)"
                modTransitions.append(
                    localizer.text(
                        .modulationStep,
                        arguments: [
                            sec.sectionName,
                            "\(currentTonic) \(modeLabel(current.mode, localizer: localizer))",
                            semitoneDiff, stepStr,
                        ]
                    ))
                inferredModulationPath.append(
                    TMDTonalityTransition(
                        sectionName: sec.sectionName, tonic: currentTonic, mode: current.mode,
                        semitoneDiff: diff, fifthsStepDiff: stepDiff))
                prevOffset = currentOffset
                prevFifths = circleOfFifthsStep(tonicOffset: currentOffset)
            }
            previousInference = current
        }

        let modulationStory: String
        if modTransitions.isEmpty {
            modulationStory = localizer.text(.modulationNone)
        } else {
            modulationStory =
                localizer.text(
                    .modulationStart,
                    arguments: [
                        globalInference.tonic ?? "?",
                        modeLabel(globalInference.mode, localizer: localizer),
                    ]) + " ➔ " + modTransitions.joined(separator: " ➔ ")
        }

        let summaryText: String
        if modTransitions.isEmpty {
            let moodSummary: String
            if globalInference.mode == .minor {
                moodSummary =
                    diatonicRatio >= 0.95
                    ? localizer.text(.summaryCleanMinor) : localizer.text(.summaryColorMinor)
            } else {
                moodSummary =
                    diatonicRatio >= 0.95
                    ? localizer.text(.summaryClean) : localizer.text(.summaryColor)
            }
            summaryText = localizer.text(
                .summaryStable,
                arguments: [
                    globalInference.tonic ?? "?",
                    modeLabel(globalInference.mode, localizer: localizer), moodSummary,
                ])
        } else {
            summaryText = localizer.text(
                .summaryModulating,
                arguments: [
                    globalInference.tonic ?? "?",
                    modeLabel(globalInference.mode, localizer: localizer),
                    String(modTransitions.count),
                ])
        }

        return TMDTonalityProfile(
            globalPitchClasses: globalDist,
            globalInference: globalInference,
            playbackContext: TMDPlaybackContext(
                movableDoBase: baseKey, transpositionOffset: sheet.keySignature.semitoneOffset,
                fixedPitch: false),
            playbackTranspositionPath: sectionProfiles.map {
                $0.playbackContext.transpositionOffset
            },
            inferredModulationPath: inferredModulationPath,
            circleOfFifthsPath: circleOfFifthsPath,
            sections: sectionProfiles,
            summaryText: summaryText,
            moodDescription: moodDescription,
            modulationStory: modulationStory,
            locale: locale,
            declaredKey: sheet.declaredKey
        )
    }

    private static func overlapDuration(
        eventPosition: Double,
        eventDuration: Double,
        sectionStart: Double,
        sectionDuration: Double
    ) -> Double {
        let eventEnd = eventPosition + max(0.0, eventDuration)
        let sectionEnd = sectionStart + max(0.0, sectionDuration)
        return max(0.0, min(eventEnd, sectionEnd) - max(eventPosition, sectionStart))
    }

    private static func chordPitchClasses(_ chord: ChordSymbol, keyOffset: Int) -> [(
        pc: Int, weight: Double
    )] {
        let rootOffset: Int
        if chord.root.isScaleDegree {
            rootOffset = (keyOffset + chord.root.semitoneOffset) % 12
        } else {
            rootOffset = chord.root.semitoneOffset % 12
        }
        let tonic = (rootOffset + 12) % 12
        var result: [(Int, Double)] = []

        let intervals = chord.quality.semitoneIntervals
        for (i, interval) in intervals.enumerated() {
            let pc = (tonic + interval) % 12
            let w: Double
            switch i {
            case 0: w = 1.0  // Root
            case 1: w = 0.8  // Third
            case 2: w = 0.8  // Fifth
            default: w = 0.6  // 7th / Extension
            }
            result.append((pc, w))
        }

        if let bass = chord.bass {
            let bassOffset: Int
            if bass.isScaleDegree {
                bassOffset = (keyOffset + bass.semitoneOffset) % 12
            } else {
                bassOffset = bass.semitoneOffset % 12
            }
            let bassPC = (bassOffset + 12) % 12
            result.append((bassPC, 0.8))
        }

        return result
    }

    private static func diatonicPitchClassMask(tonicOffset: Int, mode: TMDTonalityMode = .major)
        -> Set<Int>
    {
        let steps =
            mode == .minor ? [0, 2, 3, 5, 7, 8, 10] : mode == .major ? [0, 2, 4, 5, 7, 9, 11] : []
        var mask = Set<Int>()
        for step in steps {
            mask.insert((tonicOffset + step) % 12)
        }
        return mask
    }

    private static func makePitchClassDistribution(
        weights: [Double], tonicOffset: Int, mode: TMDTonalityMode = .major
    ) -> TMDPitchClassDistribution {
        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let total = weights.reduce(0.0, +)
        guard total > 0.0001 else {
            return TMDPitchClassDistribution(
                weights: weights,
                diatonicRatio: 1.0,
                chromaticRatio: 0.0,
                topPitchClasses: []
            )
        }

        let diatonicMask = diatonicPitchClassMask(tonicOffset: tonicOffset, mode: mode)
        var diatonicSum = 0.0
        for pc in 0..<12 {
            if diatonicMask.contains(pc) {
                diatonicSum += weights[pc]
            }
        }

        let diatonicRatio = diatonicSum / total
        let chromaticRatio = max(0.0, 1.0 - diatonicRatio)

        var indexed: [(name: String, weight: Double)] = []
        for i in 0..<12 {
            if weights[i] > 0.0001 {
                indexed.append((pitchClassNames[i], weights[i]))
            }
        }
        indexed.sort(by: { $0.weight > $1.weight })
        let topNames = indexed.map(\.name)

        return TMDPitchClassDistribution(
            weights: weights,
            diatonicRatio: diatonicRatio,
            chromaticRatio: chromaticRatio,
            topPitchClasses: topNames
        )
    }

    // Krumhansl-Schmuckler 12-pitch-class profiles for Major and Minor
    private static let ksMajorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
    ]
    private static let ksMinorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
    ]

    private static func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        guard x.count == y.count, !x.isEmpty else { return 0.0 }
        let n = Double(x.count)
        let meanX = x.reduce(0.0, +) / n
        let meanY = y.reduce(0.0, +) / n

        var num = 0.0
        var denomX = 0.0
        var denomY = 0.0

        for i in 0..<x.count {
            let dx = x[i] - meanX
            let dy = y[i] - meanY
            num += dx * dy
            denomX += dx * dx
            denomY += dy * dy
        }

        let denom = sqrt(denomX * denomY)
        if denom < 1e-9 { return 0.0 }
        return num / denom
    }

    private static func evaluateTonality(
        weights: [Double],
        evidence: TMDTonalityEvidence = TMDTonalityEvidence(noteWeight: 0, chordWeight: 0)
    ) -> TMDTonalityInference {
        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let total = weights.reduce(0.0, +)
        guard total > 0.0001 else {
            return TMDTonalityInference(
                tonic: nil, mode: .insufficient, scaleFamily: .unknown, confidence: 0, margin: 0,
                stability: .insufficient, bestCorrelation: 0, topCandidates: [], evidence: evidence)
        }
        var candidates: [TMDTonalityCandidate] = []

        // Evaluate all 12 Major and 12 Minor keys
        for tonic in 0..<12 {
            var rotWeights = [Double](repeating: 0.0, count: 12)
            for i in 0..<12 {
                rotWeights[i] = weights[(tonic + i) % 12]
            }

            let rMajor = pearsonCorrelation(rotWeights, ksMajorProfile)
            candidates.append(
                TMDTonalityCandidate(
                    tonic: pitchClassNames[tonic], mode: .major, scaleFamily: .major,
                    correlation: rMajor))

            let rMinor = pearsonCorrelation(rotWeights, ksMinorProfile)
            let seventhWeight = weights[(tonic + 11) % 12] / total
            let sixthWeight = weights[(tonic + 9) % 12] / total
            let scaleFamily: TMDScaleFamily =
                seventhWeight > 0.08 && sixthWeight > 0.08
                ? .melodicMinor : seventhWeight > 0.08 ? .harmonicMinor : .naturalMinor
            candidates.append(
                TMDTonalityCandidate(
                    tonic: pitchClassNames[tonic], mode: .minor, scaleFamily: scaleFamily,
                    correlation: rMinor))
        }

        candidates.sort(by: { $0.correlation > $1.correlation })

        let best = candidates[0]
        let second = candidates[1]
        let margin = best.correlation - second.correlation
        let confidence = max(
            0, min(1, ((best.correlation + 1) / 2) * (0.5 + min(1, margin / 0.20) * 0.5)))
        let stability: TMDKeyStability =
            confidence >= 0.75 && margin >= 0.08
            ? .high : confidence >= 0.50 && margin >= 0.03 ? .moderate : .ambiguous
        let mode: TMDTonalityMode = stability == .ambiguous ? .ambiguous : best.mode
        return TMDTonalityInference(
            tonic: best.tonic, mode: mode,
            scaleFamily: mode == .ambiguous ? .unknown : best.scaleFamily, confidence: confidence,
            margin: margin, stability: stability, bestCorrelation: best.correlation,
            topCandidates: Array(candidates.prefix(4)), evidence: evidence)
    }

    private static func pitchClassOffset(_ tonic: String) -> Int {
        ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"].firstIndex(of: tonic) ?? 0
    }

    private static func isStable(_ inference: TMDTonalityInference) -> Bool {
        inference.tonic != nil && (inference.mode == .major || inference.mode == .minor)
            && inference.stability != .ambiguous && inference.stability != .insufficient
    }

    public static func modeLabel(_ mode: TMDTonalityMode, localizer: TMDLocalizer) -> String {
        switch mode {
        case .major: localizer.text(.major)
        case .minor: localizer.text(.minor)
        case .modal: localizer.text(.modeModal)
        case .ambiguous: localizer.text(.modeAmbiguous)
        case .insufficient: localizer.text(.modeInsufficient)
        }
    }

    private static func keyName(forTonicOffset tonic: Int) -> String {
        let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
        return names[(tonic % 12 + 12) % 12]
    }

    private static func circleOfFifthsStep(tonicOffset: Int) -> Int {
        // C=0, G=+1, D=+2, A=+3, E=+4, B=+5, F#=+6, F=-1, Bb=-2, Eb=-3, Ab=-4, Db=-5
        switch (tonicOffset % 12 + 12) % 12 {
        case 0: return 0  // C
        case 7: return 1  // G
        case 2: return 2  // D
        case 9: return 3  // A
        case 4: return 4  // E
        case 11: return 5  // B
        case 6: return 6  // F# / Gb
        case 1: return -5  // Db / C#
        case 8: return -4  // Ab / G#
        case 3: return -3  // Eb
        case 10: return -2  // Bb
        case 5: return -1  // F
        default: return 0
        }
    }
}
