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
        for s in sections {
            for g in s.unitGroups {
                allGroups.append(UnitGroup(units: Array(g.units.reversed()), length: g.length))
            }
        }
        allGroups.reverse()

        var idx = 0
        return sections.map { s in
            let count = s.unitGroups.count
            let sub = Array(allGroups[idx..<idx + count])
            idx += count
            let reversedLyrics = s.lyrics.reversed().map { line in
                reverseLyricLine(line, sectionGroupCount: count)
            }
            return Section(
                noteLength: s.noteLength, unitGroups: sub, directives: s.directives,
                barlinePositions: s.barlinePositions, lyrics: reversedLyrics)
        }
    }

    private static func reverseLyricLine(_ line: LyricLine, sectionGroupCount: Int) -> LyricLine {
        func reverseRange(_ range: Range<Int>) -> Range<Int> {
            let lower = max(0, min(sectionGroupCount, sectionGroupCount - range.upperBound))
            let upper = max(lower, min(sectionGroupCount, sectionGroupCount - range.lowerBound))
            return lower..<upper
        }
        func unitToElement(_ unit: LyricSoundingUnit) -> LyricElement {
            switch unit {
            case .syllable(let syl): return .syllable(syl.rawText)
            case .tie: return .tie
            case .rest: return .rest
            }
        }
        func slotToElement(_ slot: LyricSlot) -> LyricElement {
            switch slot {
            case .unit(let u):
                return unitToElement(u)
            case .group(let units):
                return .group(units.reversed().map(unitToElement))
            }
        }
        let reversedMeasures = line.measures.reversed().map { measure in
            LyricMeasure(elements: measure.slots.reversed().map(slotToElement))
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
