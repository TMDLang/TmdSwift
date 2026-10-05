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
        return sections.map { section in
            let newGroups = section.unitGroups.map { group in
                let newUnits = group.units.map { unit -> Unit in
                    switch unit {
                    case .note(let note):
                        let curTotal = noteToTotalSemitones(note)
                        return .note(totalSemitonesToNote(curTotal + semitones))
                    case .multiNote(let notes):
                        let newNotes = notes.map { note in
                            let curTotal = noteToTotalSemitones(note)
                            return totalSemitonesToNote(curTotal + semitones)
                        }
                        return .multiNote(newNotes)
                    default:
                        return unit
                    }
                }
                return UnitGroup(units: newUnits, length: group.length)
            }
            return Section(
                noteLength: section.noteLength, unitGroups: newGroups,
                directives: section.directives, barlinePositions: section.barlinePositions)
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

        return sections.map { s in
            let newGroups = s.unitGroups.map { g in
                let newUnits = g.units.map { u -> Unit in
                    switch u {
                    case .note(let note):
                        let origSemitones = noteToTotalSemitones(note)
                        let diff = origSemitones - axis
                        let invertedSemitones = axis - diff
                        return .note(totalSemitonesToNote(invertedSemitones))
                    case .multiNote(let notes):
                        let newNotes = notes.map { note in
                            let origSemitones = noteToTotalSemitones(note)
                            let diff = origSemitones - axis
                            let invertedSemitones = axis - diff
                            return totalSemitonesToNote(invertedSemitones)
                        }
                        return .multiNote(newNotes)
                    default:
                        return u
                    }
                }
                return UnitGroup(units: newUnits, length: g.length)
            }
            return Section(
                noteLength: s.noteLength, unitGroups: newGroups, directives: s.directives,
                barlinePositions: s.barlinePositions)
        }
    }

    public static func toMinorSections(_ sections: [Section]) -> [Section] {
        sections.map { s in
            let newGroups = s.unitGroups.map { g in
                let newUnits = g.units.map { u -> Unit in
                    switch u {
                    case .note(let note):
                        if (note.degree == .e || note.degree == .a || note.degree == .b)
                            && note.accidental == .natural
                        {
                            return .note(
                                Note(accidental: .flat, degree: note.degree, octave: note.octave))
                        }
                        return u
                    case .multiNote(let notes):
                        let newNotes = notes.map { note in
                            if (note.degree == .e || note.degree == .a || note.degree == .b)
                                && note.accidental == .natural
                            {
                                return Note(
                                    accidental: .flat, degree: note.degree, octave: note.octave)
                            }
                            return note
                        }
                        return .multiNote(newNotes)
                    default:
                        return u
                    }
                }
                return UnitGroup(units: newUnits, length: g.length)
            }
            return Section(
                noteLength: s.noteLength, unitGroups: newGroups, directives: s.directives,
                barlinePositions: s.barlinePositions)
        }
    }

    public static func toMajorSections(_ sections: [Section]) -> [Section] {
        sections.map { s in
            let newGroups = s.unitGroups.map { g in
                let newUnits = g.units.map { u -> Unit in
                    switch u {
                    case .note(let note):
                        if (note.degree == .e || note.degree == .a || note.degree == .b)
                            && note.accidental == .flat
                        {
                            return .note(
                                Note(accidental: .natural, degree: note.degree, octave: note.octave)
                            )
                        }
                        return u
                    case .multiNote(let notes):
                        let newNotes = notes.map { note in
                            if (note.degree == .e || note.degree == .a || note.degree == .b)
                                && note.accidental == .flat
                            {
                                return Note(
                                    accidental: .natural, degree: note.degree, octave: note.octave)
                            }
                            return note
                        }
                        return .multiNote(newNotes)
                    default:
                        return u
                    }
                }
                return UnitGroup(units: newUnits, length: g.length)
            }
            return Section(
                noteLength: s.noteLength, unitGroups: newGroups, directives: s.directives,
                barlinePositions: s.barlinePositions)
        }
    }

    /// Canonical throwing implementation for expanding all S-expression macro orders.
}
