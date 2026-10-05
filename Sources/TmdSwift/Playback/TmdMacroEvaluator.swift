import Foundation

/// Errors that occur during S-expression macro expansion in TMD scores.
public struct TmdMacroError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public let line: Int?
    public let column: Int?

    public init(_ message: String, line: Int? = nil, column: Int? = nil) {
        self.message = message
        self.line = line
        self.column = column
    }

    public var errorDescription: String? {
        if let line = line, let column = column {
            return "Macro error at line \(line), col \(column): \(message)"
        }
        return "Macro error: \(message)"
    }
}

/// Evaluator that expands S-Expression macro orders (`Order.macro`) and abstract paragraphs
/// into concrete paragraphs and concrete playback orders.
public enum TmdMacroEvaluator {

    /// Maps pitch in semitones (0-11) to ScaleDegree and Accidental.
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
    private static func expandCanonical(_ sheet: Sheet) throws -> Sheet {
        let hasMacro = sheet.playback.contains {
            if case .macro = $0 { return true } else { return false }
        }
        if !hasMacro {
            return sheet
        }

        var abstractMap: [String: Entry] = [:]
        for p in sheet.entries where p.assignment == nil {
            abstractMap[p.name] = p
        }

        var concreteParagraphs: [Entry] = sheet.entries.filter { $0.assignment != nil }
        var newOrders: [Playback] = []
        var genCounter = 0

        func createSyntheticParagraph(
            baseName: String,
            assignment: String,
            startOffset: Int,
            sections: [Section]
        ) -> Entry {
            genCounter += 1
            let uniqueName = "__macro_\(baseName)_\(genCounter)"
            let p = Entry(
                name: uniqueName,
                assignment: assignment,
                start: startOffset,
                sections: sections
            )
            concreteParagraphs.append(p)
            return p
        }

        func getThemeSections(_ themeArg: SExpr) throws -> (name: String, sections: [Section]) {
            if case .list(let items) = themeArg {
                if items.isEmpty {
                    throw TmdMacroError("Empty prototype list")
                }

                guard case .symbol(let headRaw) = items[0] else {
                    // Sequential list of theme items: (ThemeA ThemeB)
                    var combinedSections: [Section] = []
                    var names: [String] = []
                    for item in items {
                        let sub = try getThemeSections(item)
                        names.append(sub.name)
                        combinedSections.append(contentsOf: sub.sections)
                    }
                    return (names.joined(separator: "_"), combinedSections)
                }

                let head = headRaw.lowercased()

                if head == "transpose" {
                    guard items.count >= 3 else {
                        throw TmdMacroError(
                            "'transpose' requires theme and semitones offset, e.g. (transpose Theme 7)"
                        )
                    }
                    var target = items[1]
                    var semitones = 0
                    if case .number(let n) = items[2] {
                        semitones = n
                    } else if case .number(let n) = items[1] {
                        semitones = n
                        target = items[2]
                    }
                    let sub = try getThemeSections(target)
                    let signStr = semitones >= 0 ? "+\(semitones)" : "\(semitones)"
                    return (
                        "\(sub.name)_tr\(signStr)",
                        transposeSections(sub.sections, semitones: semitones)
                    )
                }

                if head == "reverse" {
                    guard items.count >= 2 else {
                        throw TmdMacroError(
                            "'reverse' requires a target theme, e.g. (reverse Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_rev", reverseSections(sub.sections))
                }

                if head == "flip" {
                    guard items.count >= 2 else {
                        throw TmdMacroError("'flip' requires a target theme, e.g. (flip Theme)")
                    }
                    var axis: Int? = nil
                    if items.count >= 3, case .number(let a) = items[2] {
                        axis = a
                    }
                    let sub = try getThemeSections(items[1])
                    return (
                        "\(sub.name)_flip", invertSections(sub.sections, axisPitchSemitones: axis)
                    )
                }

                if head == "minor" {
                    guard items.count >= 2 else {
                        throw TmdMacroError("'minor' requires a target theme, e.g. (minor Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_minor", toMinorSections(sub.sections))
                }

                if head == "major" {
                    guard items.count >= 2 else {
                        throw TmdMacroError("'major' requires a target theme, e.g. (major Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_major", toMajorSections(sub.sections))
                }

                if head == "vary" {
                    guard items.count >= 2 else {
                        throw TmdMacroError(
                            "'vary' requires a target theme, e.g. (vary Theme +7 reverse)")
                    }
                    var current = try getThemeSections(items[1])
                    for i in 2..<items.count {
                        let transform = items[i]
                        switch transform {
                        case .list(let tList):
                            guard !tList.isEmpty, case .symbol(let tOpRaw) = tList[0] else {
                                continue
                            }
                            let tOp = tOpRaw.lowercased()
                            if tOp == "transpose" {
                                var semi = 0
                                if tList.count >= 2, case .number(let n) = tList[1] { semi = n }
                                let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                                current = (
                                    "\(current.name)_tr\(sign)",
                                    transposeSections(current.sections, semitones: semi)
                                )
                            } else if tOp == "reverse" {
                                current = ("\(current.name)_rev", reverseSections(current.sections))
                            } else if tOp == "flip" {
                                var axis: Int? = nil
                                if tList.count >= 2, case .number(let a) = tList[1] { axis = a }
                                current = (
                                    "\(current.name)_flip",
                                    invertSections(current.sections, axisPitchSemitones: axis)
                                )
                            } else if tOp == "minor" {
                                current = (
                                    "\(current.name)_minor", toMinorSections(current.sections)
                                )
                            } else if tOp == "major" {
                                current = (
                                    "\(current.name)_major", toMajorSections(current.sections)
                                )
                            }
                        case .symbol(let sym):
                            let lower = sym.lowercased()
                            if lower == "reverse" {
                                current = ("\(current.name)_rev", reverseSections(current.sections))
                            } else if lower == "flip" {
                                current = ("\(current.name)_flip", invertSections(current.sections))
                            } else if lower == "minor" {
                                current = (
                                    "\(current.name)_minor", toMinorSections(current.sections)
                                )
                            } else if lower == "major" {
                                current = (
                                    "\(current.name)_major", toMajorSections(current.sections)
                                )
                            } else if let semi = Int(sym) {
                                let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                                current = (
                                    "\(current.name)_tr\(sign)",
                                    transposeSections(current.sections, semitones: semi)
                                )
                            }
                        case .number(let semi):
                            let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                            current = (
                                "\(current.name)_tr\(sign)",
                                transposeSections(current.sections, semitones: semi)
                            )
                        }
                    }
                    return current
                }

                // Sequential list of theme items: (ThemeA ThemeB)
                var combinedSections: [Section] = []
                var names: [String] = []
                for item in items {
                    let sub = try getThemeSections(item)
                    names.append(sub.name)
                    combinedSections.append(contentsOf: sub.sections)
                }
                return (names.joined(separator: "_"), combinedSections)
            }

            let themeName: String
            switch themeArg {
            case .symbol(let s): themeName = s
            case .number(let n): themeName = String(n)
            case .list: themeName = ""
            }

            if let p = abstractMap[themeName] {
                return (themeName, p.sections)
            }
            throw TmdMacroError("Unknown prototype '\(themeName)'")
        }

        func evalExpr(_ expr: SExpr) throws -> [String] {
            guard case .list(let items) = expr else {
                let targetName = expr.description
                throw TmdMacroError("Concrete section '\(targetName)' is not a valid macro source")
            }

            guard !items.isEmpty, case .symbol(let opRaw) = items[0] else {
                return []
            }

            let op = opRaw.lowercased()

            switch op {
            case "play":
                guard items.count == 3 || items.count == 4 || items.count == 5 else {
                    throw TmdMacroError(
                        "'play' requires theme and instrument, e.g. (play Theme Violin)")
                }
                let themeTarget = items[1]
                let instrument = items[2].description
                var atOffset = 0
                if items.count == 5 {
                    guard case .symbol(let atFlag) = items[3], atFlag.lowercased() == ":at",
                        case .number(let n) = items[4]
                    else {
                        throw TmdMacroError("'play' offset must be an integer after :at")
                    }
                    atOffset = n
                } else if items.count == 4 {
                    guard case .number(let n) = items[3] else {
                        throw TmdMacroError("'play' offset must be an integer")
                    }
                    atOffset = n
                }

                let (themeName, sections) = try getThemeSections(themeTarget)
                let p = createSyntheticParagraph(
                    baseName: themeName,
                    assignment: instrument,
                    startOffset: atOffset,
                    sections: sections
                )
                return [p.name]

            case "loop":
                guard items.count == 4 else {
                    throw TmdMacroError(
                        "'loop' requires theme, instrument, and a positive integer count")
                }
                let themeTarget = items[1]
                let instrument = items[2].description
                guard case .number(let times) = items[3], times > 0 else {
                    throw TmdMacroError("'loop' count must be a positive integer")
                }

                let (themeName, baseSections) = try getThemeSections(themeTarget)
                var loopedSections: [Section] = []
                for _ in 0..<times {
                    loopedSections.append(contentsOf: baseSections)
                }

                let p = createSyntheticParagraph(
                    baseName: themeName,
                    assignment: instrument,
                    startOffset: 0,
                    sections: loopedSections
                )
                return [p.name]

            case "canon":
                guard items.count == 4 else {
                    throw TmdMacroError(
                        "'canon' requires a prototype, non-empty instrument list, and non-negative integer offset"
                    )
                }
                let themeTarget = items[1]
                guard case .list(let instList) = items[2], !instList.isEmpty else {
                    throw TmdMacroError("'canon' requires a non-empty instrument list")
                }
                let instruments = instList.map(\.description)
                guard case .number(let offsetBars) = items[3], offsetBars >= 0 else {
                    throw TmdMacroError("'canon' offset must be a non-negative integer")
                }

                // Check if themeTarget is a nested sub-expression
                func isSubExpr(_ node: SExpr) -> Bool {
                    guard case .list(let subItems) = node, !subItems.isEmpty else { return false }
                    guard case .symbol(let hRaw) = subItems[0] else { return false }
                    let h = hRaw.lowercased()
                    if ["canon", "layer", "play", "loop", "seq"].contains(h) { return true }
                    if ["reverse", "flip", "minor", "major", "vary", "transpose"].contains(h) {
                        return (subItems.count >= 2 && isSubExpr(subItems[1]))
                            || (subItems.count >= 3 && isSubExpr(subItems[2]))
                    }
                    return false
                }

                if isSubExpr(themeTarget) {
                    let innerNames = try evalExpr(themeTarget)
                    let innerParagraphs = concreteParagraphs.filter { innerNames.contains($0.name) }

                    var innerDistinctInsts: [String] = []
                    for ip in innerParagraphs
                    where !innerDistinctInsts.contains(ip.assignment ?? "") {
                        innerDistinctInsts.append(ip.assignment ?? "")
                    }

                    genCounter += 1
                    let outerCanonSectionName = "__nested_canon_\(genCounter)"

                    if !instruments.isEmpty {
                        for ip in innerParagraphs {
                            let instIdx =
                                innerDistinctInsts.firstIndex(of: ip.assignment ?? "") ?? -1
                            let mappedInst =
                                (instIdx >= 0 && instIdx < instruments.count)
                                ? instruments[instIdx] : (ip.assignment ?? "")

                            let outerP = createSyntheticParagraph(
                                baseName: ip.name,
                                assignment: mappedInst,
                                startOffset: ip.start + offsetBars,
                                sections: ip.sections
                            )
                            concreteParagraphs.removeAll { $0.name == outerP.name }
                            concreteParagraphs.append(
                                Entry(
                                    name: outerCanonSectionName,
                                    assignment: mappedInst,
                                    start: ip.start + offsetBars,
                                    sections: ip.sections
                                ))
                        }
                    }

                    for i in 0..<concreteParagraphs.count {
                        if innerNames.contains(concreteParagraphs[i].name) {
                            concreteParagraphs[i] = Entry(
                                name: outerCanonSectionName,
                                assignment: concreteParagraphs[i].assignment,
                                start: concreteParagraphs[i].start,
                                sections: concreteParagraphs[i].sections
                            )
                        }
                    }

                    return [outerCanonSectionName]
                }

                let (themeName, sections) = try getThemeSections(themeTarget)
                let prototypeQuarterDuration = sections.reduce(0.0) { total, section in
                    let unitDuration = 4.0 / Double(max(1, section.noteLength))
                    return total
                        + section.unitGroups.reduce(0.0) {
                            $0 + Double(max(0, $1.length)) * unitDuration
                        }
                }
                let prototypeBars =
                    prototypeQuarterDuration / TmdPlaybackRenderer.measureDuration(for: sheet.beat)
                if let lastIndex = instruments.indices.last,
                    Double(lastIndex * offsetBars) > prototypeBars
                {
                    throw TmdMacroError(
                        "Canon voice \(lastIndex + 1) enters after the combined prototype ends")
                }
                genCounter += 1
                let canonSectionName = "__canon_\(themeName)_\(genCounter)"

                for (idx, inst) in instruments.enumerated() {
                    let startOffset = idx * offsetBars
                    let p = Entry(
                        name: canonSectionName,
                        assignment: inst,
                        start: startOffset,
                        sections: sections
                    )
                    concreteParagraphs.append(p)
                }

                return [canonSectionName]

            case "layer":
                guard items.count > 1 else {
                    throw TmdMacroError("'layer' requires at least one child expression")
                }
                var childNames: [String] = []
                for i in 1..<items.count {
                    let names = try evalExpr(items[i])
                    childNames.append(contentsOf: names)
                }

                genCounter += 1
                let layerSectionName = "__layer_\(genCounter)"
                for i in 0..<concreteParagraphs.count {
                    if childNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Entry(
                            name: layerSectionName,
                            assignment: concreteParagraphs[i].assignment,
                            start: concreteParagraphs[i].start,
                            sections: concreteParagraphs[i].sections
                        )
                    }
                }
                return [layerSectionName]

            case "seq":
                guard items.count > 1 else {
                    throw TmdMacroError("'seq' requires at least one child expression")
                }
                var seqNames: [String] = []
                for i in 1..<items.count {
                    let names = try evalExpr(items[i])
                    seqNames.append(contentsOf: names)
                }
                return seqNames

            case "reverse":
                guard items.count >= 2 else {
                    throw TmdMacroError(
                        "'reverse' requires a target theme or expression, e.g. (reverse Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Entry(
                            name: concreteParagraphs[i].name,
                            assignment: concreteParagraphs[i].assignment,
                            start: concreteParagraphs[i].start,
                            sections: reverseSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "flip":
                guard items.count >= 2 else {
                    throw TmdMacroError(
                        "'flip' requires a target theme or expression, e.g. (flip Theme)")
                }
                var axis: Int? = nil
                if items.count >= 3, case .number(let a) = items[2] { axis = a }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Entry(
                            name: concreteParagraphs[i].name,
                            assignment: concreteParagraphs[i].assignment,
                            start: concreteParagraphs[i].start,
                            sections: invertSections(
                                concreteParagraphs[i].sections, axisPitchSemitones: axis)
                        )
                    }
                }
                return innerNames

            case "minor":
                guard items.count >= 2 else {
                    throw TmdMacroError(
                        "'minor' requires a target theme or expression, e.g. (minor Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Entry(
                            name: concreteParagraphs[i].name,
                            assignment: concreteParagraphs[i].assignment,
                            start: concreteParagraphs[i].start,
                            sections: toMinorSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "major":
                guard items.count >= 2 else {
                    throw TmdMacroError(
                        "'major' requires a target theme or expression, e.g. (major Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Entry(
                            name: concreteParagraphs[i].name,
                            assignment: concreteParagraphs[i].assignment,
                            start: concreteParagraphs[i].start,
                            sections: toMajorSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "transpose":
                guard items.count >= 3 else {
                    throw TmdMacroError(
                        "'transpose' requires theme and semitones offset, e.g. (transpose Theme 7)")
                }
                var target = items[1]
                var semitones = 0
                if case .number(let n) = items[2] {
                    semitones = n
                } else if case .number(let n) = items[1] {
                    semitones = n
                    target = items[2]
                }
                let innerNames = try evalExpr(target)
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Entry(
                            name: concreteParagraphs[i].name,
                            assignment: concreteParagraphs[i].assignment,
                            start: concreteParagraphs[i].start,
                            sections: transposeSections(
                                concreteParagraphs[i].sections, semitones: semitones)
                        )
                    }
                }
                return innerNames

            case "vary":
                guard items.count >= 2 else {
                    throw TmdMacroError(
                        "'vary' requires a target theme or expression, e.g. (vary Theme +7 reverse)"
                    )
                }
                let innerNames = try evalExpr(items[1])
                for i in 2..<items.count {
                    let transform = items[i]
                    switch transform {
                    case .list(let tList):
                        guard !tList.isEmpty, case .symbol(let tOpRaw) = tList[0] else { continue }
                        let tOp = tOpRaw.lowercased()
                        if tOp == "transpose" {
                            var semi = 0
                            if tList.count >= 2, case .number(let n) = tList[1] { semi = n }
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: transposeSections(
                                        concreteParagraphs[idx].sections, semitones: semi)
                                )
                            }
                        } else if tOp == "reverse" {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: reverseSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if tOp == "flip" {
                            var axis: Int? = nil
                            if tList.count >= 2, case .number(let a) = tList[1] { axis = a }
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: invertSections(
                                        concreteParagraphs[idx].sections, axisPitchSemitones: axis)
                                )
                            }
                        } else if tOp == "minor" {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMinorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if tOp == "major" {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMajorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        }
                    case .symbol(let sym):
                        let lower = sym.lowercased()
                        if lower == "reverse" {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: reverseSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "flip" {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: invertSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "minor" {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMinorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "major" {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMajorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if let semi = Int(sym) {
                            for idx in 0..<concreteParagraphs.count
                            where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Entry(
                                    name: concreteParagraphs[idx].name,
                                    assignment: concreteParagraphs[idx].assignment,
                                    start: concreteParagraphs[idx].start,
                                    sections: transposeSections(
                                        concreteParagraphs[idx].sections, semitones: semi)
                                )
                            }
                        }
                    case .number(let semi):
                        for idx in 0..<concreteParagraphs.count
                        where innerNames.contains(concreteParagraphs[idx].name) {
                            concreteParagraphs[idx] = Entry(
                                name: concreteParagraphs[idx].name,
                                assignment: concreteParagraphs[idx].assignment,
                                start: concreteParagraphs[idx].start,
                                sections: transposeSections(
                                    concreteParagraphs[idx].sections, semitones: semi)
                            )
                        }
                    }
                }
                return innerNames

            default:
                throw TmdMacroError("Unknown macro operation '\(op)' in S-expression")
            }
        }

        for order in sheet.playback {
            switch order {
            case .macro(let expr):
                let names = try evalExpr(expr)
                var added: Set<String> = []
                for name in names where !added.contains(name) {
                    added.insert(name)
                    newOrders.append(.name(name))
                }
            default:
                newOrders.append(order)
            }
        }

        return Sheet(
            name: sheet.name,
            speed: sheet.speed,
            keySignature: sheet.keySignature,
            beat: sheet.beat,
            entries: concreteParagraphs,
            playback: newOrders,
            metadata: sheet.metadata
        )
    }

    /// Deprecated compatibility API. Macro failures are no longer silently suppressed.
    @available(*, deprecated, message: "Use expandThrowing(_:) and handle TmdMacroError explicitly.")
    public static func expand(_ sheet: Sheet) -> Sheet {
        return expandOrTrap(sheet)
    }

    /// Bridge for legacy non-throwing rendering APIs. It preserves their signatures while
    /// ensuring that macro diagnostics cannot be silently discarded.
    public static func expandOrTrap(_ sheet: Sheet) -> Sheet {
        do {
            return try expandThrowing(sheet)
        } catch {
            preconditionFailure("TMD macro expansion failed: \(error)")
        }
    }

    /// Throwing API that exposes macro expansion diagnostics.
    public static func expandThrowing(_ sheet: Sheet) throws -> Sheet {
        return try expandCanonical(sheet)
    }

}
