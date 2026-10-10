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
            allGroups.append(contentsOf: s.unitGroups)
        }
        allGroups.reverse()

        var idx = 0
        return sections.map { s in
            let count = s.unitGroups.count
            let sub = Array(allGroups[idx..<idx + count])
            idx += count
            return Section(
                noteLength: s.noteLength, unitGroups: sub, directives: s.directives,
                barlinePositions: s.barlinePositions)
        }
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
