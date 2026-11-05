import Foundation

extension TmdMacroEvaluator {
    public static func semitoneToDegreeAccidental(_ semi: Int) -> (
        degree: ScaleDegree, accidental: Accidental
    ) {
        PitchMapping.semitoneToDegreeAccidental(semi)
    }

    public static func noteToTotalSemitones(_ note: Note) -> Int {
        note.totalSemitones
    }

    public static func totalSemitonesToNote(_ totalSemitones: Int) -> Note {
        let octave = Int(floor(Double(totalSemitones) / 12.0))
        var semiInOctave = totalSemitones % 12
        if semiInOctave < 0 {
            semiInOctave += 12
        }
        let (degree, accidental) = semitoneToDegreeAccidental(semiInOctave)
        return Note(accidental: accidental, degree: degree, octave: octave)
    }

    public static func transposeSections(_ sections: [Section], semitones: Int) -> [Section] {
        if semitones == 0 { return sections }
        return sections.mapNotes { note in
            totalSemitonesToNote(noteToTotalSemitones(note) + semitones)
        }
    }

    public static func reverseSections(_ sections: [Section]) -> [Section] {
        var allGroups: [UnitGroup] = []
        var globalLyrics: [LyricLine] = []
        var origOffset = 0
        for s in sections {
            for g in s.unitGroups {
                allGroups.append(UnitGroup(units: Array(g.units.reversed()), length: g.length))
            }
            for line in s.lyrics {
                let shiftedRange =
                    (line.unitGroupRange.lowerBound + origOffset)..<(line.unitGroupRange.upperBound
                        + origOffset)
                let shiftedMeasureRanges = line.measureUnitGroupRanges.map {
                    ($0.lowerBound + origOffset)..<($0.upperBound + origOffset)
                }
                globalLyrics.append(
                    LyricLine(
                        stanza: line.stanza,
                        measures: line.measures,
                        unitGroupRange: shiftedRange,
                        measureUnitGroupRanges: shiftedMeasureRanges,
                        sourceLine: line.sourceLine
                    )
                )
            }
            origOffset += s.unitGroups.count
        }
        let totalGroupCount = allGroups.count
        allGroups.reverse()

        let reversedGlobalLyrics = globalLyrics.reversed().map { line in
            reverseLyricLine(line, sectionGroupCount: totalGroupCount)
        }

        var idx = 0
        return sections.map { s in
            let count = s.unitGroups.count
            let secRange = idx..<(idx + count)
            let sub = Array(allGroups[secRange])
            idx += count
            let sectionLyrics = reversedGlobalLyrics.compactMap { line -> LyricLine? in
                guard line.unitGroupRange.overlaps(secRange) else { return nil }
                var slicedMeasures: [LyricMeasure] = []
                var slicedRanges: [Range<Int>] = []
                let pairCount = min(line.measures.count, line.measureUnitGroupRanges.count)
                for i in 0..<pairCount {
                    let m = line.measures[i]
                    let r = line.measureUnitGroupRanges[i]
                    guard r.overlaps(secRange) else { continue }
                    let overlap = r.clamped(to: secRange)
                    let localRange = (overlap.lowerBound - secRange.lowerBound)..<(overlap.upperBound - secRange.lowerBound)
                    if overlap == r {
                        slicedMeasures.append(m)
                    } else {
                        let startSlot = max(0, min(m.slots.count, overlap.lowerBound - r.lowerBound))
                        let endSlot = max(startSlot, min(m.slots.count, overlap.upperBound - r.lowerBound))
                        let subSlots = Array(m.slots[startSlot..<endSlot])
                        slicedMeasures.append(LyricMeasure(elements: subSlots.map(slotToElement)))
                    }
                    slicedRanges.append(localRange)
                }
                guard !slicedMeasures.isEmpty else { return nil }
                let clampedUnitRange = line.unitGroupRange.clamped(to: secRange)
                let localUnitRange =
                    (clampedUnitRange.lowerBound - secRange.lowerBound)..<(clampedUnitRange.upperBound
                        - secRange.lowerBound)
                return LyricLine(
                    stanza: line.stanza,
                    measures: slicedMeasures,
                    unitGroupRange: localUnitRange,
                    measureUnitGroupRanges: slicedRanges,
                    sourceLine: line.sourceLine
                )
            }
            return Section(
                noteLength: s.noteLength, unitGroups: sub, directives: s.directives,
                barlinePositions: s.barlinePositions, lyrics: sectionLyrics)
        }
    }

    private static func unitToElement(_ unit: LyricSoundingUnit) -> LyricElement {
        switch unit {
        case .syllable(let syl): return .syllable(syl.rawText)
        case .tie: return .tie
        case .rest: return .rest
        }
    }

    private static func slotToElement(_ slot: LyricSlot) -> LyricElement {
        switch slot {
        case .unit(let u):
            return unitToElement(u)
        case .group(let units):
            return .group(units.map(unitToElement))
        }
    }

    private static func reverseLyricLine(_ line: LyricLine, sectionGroupCount: Int) -> LyricLine {
        func reverseRange(_ range: Range<Int>) -> Range<Int> {
            let lower = max(0, min(sectionGroupCount, sectionGroupCount - range.upperBound))
            let upper = max(lower, min(sectionGroupCount, sectionGroupCount - range.lowerBound))
            return lower..<upper
        }
        func reversedSlotToElement(_ slot: LyricSlot) -> LyricElement {
            switch slot {
            case .unit(let u):
                return unitToElement(u)
            case .group(let units):
                return .group(units.reversed().map(unitToElement))
            }
        }
        let reversedMeasures = line.measures.reversed().map { measure in
            LyricMeasure(elements: measure.slots.reversed().map(reversedSlotToElement))
        }
        let reversedMeasureRanges = line.measureUnitGroupRanges.reversed().map(reverseRange)
        return LyricLine(
            stanza: line.stanza,
            measures: reversedMeasures,
            unitGroupRange: reverseRange(line.unitGroupRange),
            measureUnitGroupRanges: reversedMeasureRanges,
            sourceLine: line.sourceLine
        )
    }

    public static func invertSections(_ sections: [Section], axisPitchSemitones: Int? = nil)
        -> [Section]
    {
        var axis = axisPitchSemitones
        if axis == nil {
            outer: for s in sections {
                for g in s.unitGroups {
                    for u in g.units {
                        if case .note(let note) = u {
                            axis = noteToTotalSemitones(note)
                            break outer
                        } else if case .multiNote(let notes) = u, let firstNote = notes.first {
                            axis = noteToTotalSemitones(firstNote)
                            break outer
                        }
                    }
                }
            }
        }

        guard let axis = axis else {
            return sections
        }

        return sections.mapNotes { note in
            let origSemitones = noteToTotalSemitones(note)
            let diff = origSemitones - axis
            return totalSemitonesToNote(axis - diff)
        }
    }

    public static func toMinorSections(_ sections: [Section]) -> [Section] {
        sections.mapNotes { note in
            if (note.degree == .e || note.degree == .a || note.degree == .b)
                && note.accidental == .natural
            {
                return Note(accidental: .flat, degree: note.degree, octave: note.octave)
            }
            return note
        }
    }

    public static func toMajorSections(_ sections: [Section]) -> [Section] {
        sections.mapNotes { note in
            if (note.degree == .e || note.degree == .a || note.degree == .b)
                && note.accidental == .flat
            {
                return Note(accidental: .natural, degree: note.degree, octave: note.octave)
            }
            return note
        }
    }

    /// Canonical throwing implementation for expanding all S-expression macro orders.
}
