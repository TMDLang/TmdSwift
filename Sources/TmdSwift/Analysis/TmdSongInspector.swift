import Foundation

/// Pitch descriptor with MIDI note number, canonical note name (e.g. "C4", "A5"), and source section context.
public enum TmdSongInspector {

    /// Inspects a parsed TMD `Sheet` and produces an in-depth `TmdSongProfile`.
    public static func inspect(
        sheet inputSheet: Sheet,
        targetInstrument: String? = nil,
        locale: TmdLocale = .zhHant
    ) -> TmdSongProfile {
        let sheet = TmdMacroEvaluator.expandOrTrap(inputSheet)
        let title = sheet.name.isEmpty ? "Untitled" : sheet.name
        let initialTempo = sheet.speed > 0 ? sheet.speed : 120.0
        let initialKey = sheet.keySignature.description
        let initialMeter = "\(sheet.beat.count)/\(sheet.beat.noteValue)"

        // 1. Timing & Structure Profile
        let timelineDirectives = collectTimelineDirectives(sheet: sheet)
        let timingProfile = buildTimingProfile(sheet: sheet, timelineDirectives: timelineDirectives)

        // 2. Instrument & Pitch Ranges
        let instruments = sheet.distinctInstruments(fallbackToDefault: false)
        var instrumentRanges: [TmdPitchRangeProfile] = []

        for inst in instruments {
            if let profile = buildPitchProfile(
                for: inst, sheet: sheet, timingProfile: timingProfile,
                timelineDirectives: timelineDirectives)
            {
                instrumentRanges.append(profile)
            }
        }

        // 3. Vocal Range (picks target vocal instrument or specified target)
        let targetVocalInst: String
        if let targetInstrument, instruments.contains(targetInstrument) {
            targetVocalInst = targetInstrument
        } else {
            targetVocalInst = sheet.resolveVocalInstrument()
        }
        let vocalRange = instrumentRanges.first { $0.assignment == targetVocalInst }

        // 4. Harmony & Chord Profile
        let harmonyProfile = buildHarmonyProfile(sheet: sheet)

        // 5. Arrangement & Density Profile
        let densityProfile = buildDensityProfile(sheet: sheet)

        // 6. Tonality & Pitch-Class Profile
        let tonalityProfile = buildTonalityProfile(
            sheet: sheet, timingProfile: timingProfile, locale: locale)

        return TmdSongProfile(
            title: title,
            initialTempo: initialTempo,
            initialKey: initialKey,
            initialTimeSignature: initialMeter,
            timing: timingProfile,
            vocalRange: vocalRange,
            instrumentRanges: instrumentRanges,
            harmony: harmonyProfile,
            density: densityProfile,
            tonality: tonalityProfile,
            locale: locale
        )
    }

    private static func buildTimingProfile(
        sheet: Sheet, timelineDirectives: [PlaybackDirectiveEvent]
    ) -> TmdTimingProfile {
        TmdSongTimingAnalyzer.analyze(
            sheet: sheet, timelineDirectives: timelineDirectives)
    }

    private static func buildPitchProfile(
        for instrument: String,
        sheet: Sheet,
        timingProfile: TmdTimingProfile,
        timelineDirectives: [PlaybackDirectiveEvent]
    ) -> TmdPitchRangeProfile? {
        return TmdSongPitchRangeAnalyzer.analyze(
            instrument: instrument, sheet: sheet, timingProfile: timingProfile,
            timelineDirectives: timelineDirectives)
    }

    /// Evaluates pitch span difficulty based on semitones range.
    public static func evaluateDifficulty(spanSemitones: Int) -> TmdPitchRangeDifficulty {
        TmdSongPitchRangeAnalyzer.evaluateDifficulty(spanSemitones: spanSemitones)
    }

    /// Classical standard vocal ranges with amateur/pop margin and male octave displacement.
    public static func evaluateSuitableVoiceTypes(lowestMidi: Int, highestMidi: Int)
        -> [TmdVocalClassification]
    {
        TmdSongPitchRangeAnalyzer.evaluateSuitableVoiceTypes(
            lowestMidi: lowestMidi, highestMidi: highestMidi)
    }

    private static func buildHarmonyProfile(sheet: Sheet) -> TmdHarmonyProfile {
        TmdSongHarmonyAnalyzer.analyze(sheet: sheet)
    }

    private static func buildDensityProfile(sheet: Sheet) -> TmdArrangementDensityProfile {
        var sectionDict: [String: [String]] = [:]
        for p in sheet.entries {
            guard let assignment = p.assignment else { continue }
            sectionDict[p.name, default: []].append(assignment)
        }

        var sectionDensities: [TmdArrangementDensityProfile.SectionDensity] = []
        var maxTracks = 0

        for (secName, instList) in sectionDict {
            let uniqueInst = Array(Set(instList)).sorted()
            if uniqueInst.count > maxTracks {
                maxTracks = uniqueInst.count
            }
            sectionDensities.append(
                TmdArrangementDensityProfile.SectionDensity(
                    sectionName: secName,
                    trackCount: uniqueInst.count,
                    instruments: uniqueInst
                ))
        }

        return TmdArrangementDensityProfile(
            maxConcurrentTracks: maxTracks,
            sectionDensities: sectionDensities.sorted(by: { $0.sectionName < $1.sectionName })
        )
    }

    private static func formatNoteLocation(_ note: TmdNotePitchInfo) -> String {
        let mins = Int(note.timeSeconds) / 60
        let secs = Int(note.timeSeconds) % 60
        let timeStr = String(format: "%d:%02d", mins, secs)
        if !note.sectionName.isEmpty {
            return
                "[\(note.sectionName) #\(note.sectionOccurrence) @ m.\(note.measure), \(timeStr)]"
        } else {
            return "[@ m.\(note.measure), \(timeStr)]"
        }
    }

    /// Generates human-readable plain text / ASCII inspection report.
    public static func generateReport(_ profile: TmdSongProfile, locale: TmdLocale? = nil) -> String
    {
        let strings = TmdReportStrings(localizer: TmdLocalizer(locale: locale ?? profile.locale))
        let mins = Int(profile.timing.totalDurationSeconds) / 60
        let secs = Int(profile.timing.totalDurationSeconds) % 60
        let timeFormatted = String(
            format: "%d:%02d (%0.1fs)", mins, secs, profile.timing.totalDurationSeconds)

        var lines: [String] = []
        lines.append(
            "================================================================================")
        lines.append("📊 \(strings.songProfile): [ \(profile.title) ]")
        lines.append(
            "================================================================================")
        lines.append(
            "⏱  \(strings.duration):       \(timeFormatted), \(profile.timing.totalMeasures) \(strings.measuresTotal)"
        )
        lines.append(
            "🎼 \(strings.keyAndTempo):    \(strings.localizer.text(.playbackBase)) \(profile.initialKey), != \(profile.initialTempo) BPM, <\(profile.initialTimeSignature)>"
        )
        lines.append("   - \(strings.analysisScope)")

        if let vocal = profile.vocalRange {
            let octaves = String(format: "%0.1f", vocal.spanOctaves)
            lines.append(
                "🎤 Vocal Range:    \(vocal.lowestNote.noteName) (MIDI \(vocal.lowestNote.midiPitch)) – \(vocal.highestNote.noteName) (MIDI \(vocal.highestNote.midiPitch)) [Span: \(vocal.spanSemitones) semitones / \(octaves) octaves, Difficulty: \(vocal.difficulty.rawValue)]"
            )
            lines.append(
                "   - Lowest Note:  \(vocal.lowestNote.noteName) in \(formatNoteLocation(vocal.lowestNote))"
            )
            lines.append(
                "   - Highest Note: \(vocal.highestNote.noteName) in \(formatNoteLocation(vocal.highestNote))"
            )
            if !vocal.suitableVoiceTypes.isEmpty {
                let voiceNames = vocal.suitableVoiceTypes.map(\.rawValue).joined(separator: ", ")
                lines.append("   - Suitable For: \(voiceNames)")
            }
        }

        lines.append(
            "🏛  \(strings.structure):      "
                + profile.timing.sections.map {
                    "\($0.name) (\(String(format: "%0.1fs", $0.durationSeconds)))"
                }.joined(separator: " -> "))
        lines.append(
            "⚡ \(strings.density):        Peak \(profile.density.maxConcurrentTracks) \(strings.tracksConcurrently)"
        )

        if !profile.harmony.distinctChords.isEmpty {
            lines.append(
                "🎹 \(strings.harmony):        "
                    + profile.harmony.distinctChords.joined(separator: " "))
        }

        if let tonality = profile.tonality {
            let stabStr = tonality.globalInference.stability.rawValue.capitalized
            let corrStr = String(format: "%0.2f", tonality.globalInference.bestCorrelation)
            let diatonicPct = String(
                format: "%0.1f%%", tonality.globalPitchClasses.diatonicRatio * 100.0)
            let topPitches = tonality.globalPitchClasses.topPitchClasses.prefix(5).joined(
                separator: ", ")

            lines.append("🗝  \(strings.tonalityDiagnosis)       \(tonality.summaryText)")
            lines.append("   - \(strings.mood):    \(tonality.moodDescription)")
            lines.append("   - \(strings.modulationJourney):    \(tonality.modulationStory)")
            lines.append("   - \(strings.tonalCore):  \(topPitches)")
            let inferredLabel =
                "\(tonality.globalInference.tonic ?? "?") \(modeLabel(tonality.globalInference.mode, localizer: strings.localizer))"
            lines.append(
                "   - \(strings.tonalMetrics):    \(inferredLabel) [\(strings.correlation): \(corrStr), \(strings.stability): \(stabStr), \(strings.diatonicPurity): \(diatonicPct)]"
            )

            let candidateStr = tonality.globalInference.topCandidates.prefix(3).map {
                "\($0.tonic) \(modeLabel($0.mode, localizer: strings.localizer)) (\(String(format: "%0.2f", $0.correlation)))"
            }.joined(separator: ", ")
            if !candidateStr.isEmpty {
                lines.append("   - \(strings.candidateKeys): \(candidateStr)")
            }

            let pathStr = tonality.circleOfFifthsPath.map { "\($0 >= 0 ? "+" : "")\($0)" }.joined(
                separator: " -> ")
            if !pathStr.isEmpty {
                lines.append("   - \(strings.circleOfFifths):   \(pathStr)")
            }

            if !tonality.sections.isEmpty {
                lines.append("   - \(strings.sectionDetails):")
                for sec in tonality.sections {
                    let secCorr = String(format: "%0.2f", sec.inferredTonality.bestCorrelation)
                    let secDiatonic = String(
                        format: "%0.1f%%", sec.pitchClasses.diatonicRatio * 100.0)
                    let sectionLabel =
                        "\(sec.inferredTonality.tonic ?? "?") \(modeLabel(sec.inferredTonality.mode, localizer: strings.localizer))"
                    var secLine =
                        "     • [\(sec.sectionName) #\(sec.occurrenceIndex)]: \(sectionLabel) (r: \(secCorr), \(strings.diatonicPurity): \(secDiatonic)"
                    if !sec.nonDiatonicNotes.isEmpty {
                        secLine +=
                            ", \(strings.nonDiatonic): \(sec.nonDiatonicNotes.joined(separator: ", "))"
                    }
                    secLine += ")"
                    lines.append(secLine)
                }
            }

            // ASCII Visualizations
            lines.append("")
            lines.append("  [ Circle of Fifths Trajectory ]")
            lines.append(renderAsciiCircleOfFifths(tonality: tonality))
            lines.append("")
            lines.append("  [ Pitch Class Weight Distribution ]")
            lines.append(renderPitchClassHistogram(tonality: tonality))
        }

        lines.append(
            "--------------------------------------------------------------------------------")
        lines.append(strings.instrumentRanges)
        for inst in profile.instrumentRanges {
            let octaves = String(format: "%0.1f", inst.spanOctaves)
            lines.append(
                "  - \(inst.assignment.padding(toLength: 14, withPad: " ", startingAt: 0)): \(inst.lowestNote.noteName) – \(inst.highestNote.noteName) (\(inst.spanSemitones) semitones / \(octaves) octaves, \(inst.totalNotes) notes)"
            )
        }
        lines.append(
            "================================================================================")

        return lines.joined(separator: "\n")
    }

    // MARK: - Tonality & Key Profile Analysis Engine

    private static func buildTonalityProfile(
        sheet: Sheet,
        timingProfile: TmdTimingProfile,
        locale: TmdLocale
    ) -> TmdTonalityProfile {
        TmdSongTonalityAnalyzer.analyze(
            sheet: sheet, timingProfile: timingProfile, locale: locale)
    }

    private static func modeLabel(_ mode: TmdTonalityMode, localizer: TmdLocalizer) -> String {
        TmdSongTonalityAnalyzer.modeLabel(mode, localizer: localizer)
    }

    private static func collectTimelineDirectives(sheet: Sheet) -> [PlaybackDirectiveEvent] {
        let paragraphs = sheet.entries
        let instruments = Set(paragraphs.compactMap(\.assignment).filter { !$0.isEmpty })
        var directives: [PlaybackDirectiveEvent] = []
        for instrument in instruments {
            directives.append(
                contentsOf: TmdPlaybackRenderer.render(sheet: sheet, instrument: instrument)
                    .directives)
        }
        directives.sort(by: { $0.position < $1.position })

        var filtered: [PlaybackDirectiveEvent] = []
        for directive in directives {
            if let last = filtered.last {
                if last.position == directive.position
                    && last.state.tempo == directive.state.tempo
                    && last.state.timeSignature.count == directive.state.timeSignature.count
                    && last.state.timeSignature.noteValue == directive.state.timeSignature.noteValue
                {
                    continue
                }
            }
            filtered.append(directive)
        }
        return filtered
    }

    private static func measureDuration(for beat: Beat) -> Double {
        Double(max(1, beat.count)) * 4.0 / Double(max(1, beat.noteValue))
    }

    // MARK: - ASCII / Unicode Tonality Visualizers

    private static func renderAsciiCircleOfFifths(tonality: TmdTonalityProfile) -> String {
        // Collect active fifths steps from sections
        var activeSteps = Set<Int>()
        for sec in tonality.sections {
            activeSteps.insert(sec.fifthsPosition)
        }

        func node(_ name: String, _ step: Int) -> String {
            if activeSteps.contains(step) {
                return "[\(name.padding(toLength: 2, withPad: " ", startingAt: 0))]*"
            } else {
                return " \(name.padding(toLength: 2, withPad: " ", startingAt: 0)) "
            }
        }

        // 12-clock positions:
        //        0: C
        //  -1: F       +1: G
        // -2: Bb        +2: D
        // -3: Eb        +3: A
        //  -4: Ab      +4: E
        //   -5: Db    +5: B
        //       +6: F#
        let c = node("C", 0)
        let g = node("G", 1)
        let d = node("D", 2)
        let a = node("A", 3)
        let e = node("E", 4)
        let b = node("B", 5)
        let fs = node("F#", 6)
        let db = node("Db", -5)
        let ab = node("Ab", -4)
        let eb = node("Eb", -3)
        let bb = node("Bb", -2)
        let f = node("F", -1)

        var lines: [String] = []
        lines.append("              \(c)")
        lines.append("        \(f)         \(g)")
        lines.append("     \(bb)             \(d)")
        lines.append("     \(eb)             \(a)")
        lines.append("        \(ab)         \(e)")
        lines.append("           \(db)     \(b)")
        lines.append("              \(fs)")
        lines.append("     (* = active key center)")
        return lines.joined(separator: "\n")
    }

    private static func renderPitchClassHistogram(tonality: TmdTonalityProfile) -> String {
        let pitchClassNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let weights = tonality.globalPitchClasses.weights
        let maxWeight = weights.max() ?? 1.0
        guard maxWeight > 0.0001 else { return "     (no pitch data)" }

        let barMaxWidth = 24
        var lines: [String] = []
        for pc in 0..<12 {
            let w = weights[pc]
            let ratio = w / maxWeight
            let barLen = Int(round(ratio * Double(barMaxWidth)))
            let bar = String(repeating: "█", count: barLen)
            let name = pitchClassNames[pc].padding(toLength: 3, withPad: " ", startingAt: 0)
            let pct = String(format: "%5.1f%%", (w / (weights.reduce(0.0, +) + 1e-9)) * 100.0)
            lines.append(
                "     \(name): \(bar.padding(toLength: barMaxWidth, withPad: " ", startingAt: 0)) \(pct)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
