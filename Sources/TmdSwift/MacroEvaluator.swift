import Foundation

/// Errors that occur during S-expression macro expansion in TMD scores.
public struct TMDMacroError: Error, LocalizedError, Equatable, Sendable {
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
public enum TMDMacroEvaluator {

    /// Maps pitch in semitones (0-11) to ScaleDegree and Accidental.
    public static func semitoneToDegreeAccidental(_ semi: Int) -> (degree: ScaleDegree, accidental: Accidental) {
        let normalized = (semi % 12 + 12) % 12
        switch normalized {
        case 0: return (.c, .natural)
        case 1: return (.c, .sharp)
        case 2: return (.d, .natural)
        case 3: return (.d, .sharp)
        case 4: return (.e, .natural)
        case 5: return (.f, .natural)
        case 6: return (.f, .sharp)
        case 7: return (.g, .natural)
        case 8: return (.g, .sharp)
        case 9: return (.a, .natural)
        case 10: return (.a, .sharp)
        case 11: return (.b, .natural)
        default: return (.c, .natural)
        }
    }

    public static func noteToTotalSemitones(_ note: Note) -> Int {
        note.degree.semitoneOffset + note.accidental.semitoneOffset + note.octave * 12
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
                    if case .note(let note) = unit {
                        let curTotal = noteToTotalSemitones(note)
                        return .note(totalSemitonesToNote(curTotal + semitones))
                    }
                    return unit
                }
                return UnitGroup(units: newUnits, length: group.length)
            }
            return Section(noteLength: section.noteLength, unitGroups: newGroups, directives: section.directives)
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
            return Section(noteLength: s.noteLength, unitGroups: sub, directives: s.directives)
        }
    }

    public static func invertSections(_ sections: [Section], axisPitchSemitones: Int? = nil) -> [Section] {
        var axis = axisPitchSemitones
        if axis == nil {
            outer: for s in sections {
                for g in s.unitGroups {
                    for u in g.units {
                        if case .note(let note) = u {
                            axis = noteToTotalSemitones(note)
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
                    if case .note(let note) = u {
                        let origSemitones = noteToTotalSemitones(note)
                        let diff = origSemitones - axis
                        let invertedSemitones = axis - diff
                        return .note(totalSemitonesToNote(invertedSemitones))
                    }
                    return u
                }
                return UnitGroup(units: newUnits, length: g.length)
            }
            return Section(noteLength: s.noteLength, unitGroups: newGroups, directives: s.directives)
        }
    }

    public static func toMinorSections(_ sections: [Section]) -> [Section] {
        sections.map { s in
            let newGroups = s.unitGroups.map { g in
                let newUnits = g.units.map { u -> Unit in
                    if case .note(let note) = u {
                        if (note.degree == .e || note.degree == .a || note.degree == .b) && note.accidental == .natural {
                            return .note(Note(accidental: .flat, degree: note.degree, octave: note.octave))
                        }
                    }
                    return u
                }
                return UnitGroup(units: newUnits, length: g.length)
            }
            return Section(noteLength: s.noteLength, unitGroups: newGroups, directives: s.directives)
        }
    }

    public static func toMajorSections(_ sections: [Section]) -> [Section] {
        sections.map { s in
            let newGroups = s.unitGroups.map { g in
                let newUnits = g.units.map { u -> Unit in
                    if case .note(let note) = u {
                        if (note.degree == .e || note.degree == .a || note.degree == .b) && note.accidental == .flat {
                            return .note(Note(accidental: .natural, degree: note.degree, octave: note.octave))
                        }
                    }
                    return u
                }
                return UnitGroup(units: newUnits, length: g.length)
            }
            return Section(noteLength: s.noteLength, unitGroups: newGroups, directives: s.directives)
        }
    }

    /// Expands all S-expression macro orders (`Order.macro`) in a Sheet into concrete
    /// paragraphs and concrete order sequences.
    /// If the sheet contains no macro orders, it returns the sheet unchanged.
    public static func expand(_ sheet: Sheet) -> Sheet {
        let hasMacro = sheet.orders.contains { if case .macro = $0 { return true } else { return false } }
        if !hasMacro {
            return sheet
        }

        var abstractMap: [String: Paragraph] = [:]
        for p in sheet.paragraphs where p.instrument.isEmpty {
            abstractMap[p.name] = p
        }

        var concreteParagraphs: [Paragraph] = sheet.paragraphs.filter { !$0.instrument.isEmpty }
        var newOrders: [Order] = []
        var genCounter = 0

        func createSyntheticParagraph(
            baseName: String,
            instrument: String,
            startOffset: Int,
            sections: [Section]
        ) -> Paragraph {
            genCounter += 1
            let uniqueName = "__macro_\(baseName)_\(genCounter)"
            let p = Paragraph(
                name: uniqueName,
                instrument: instrument,
                start: startOffset,
                sections: sections
            )
            concreteParagraphs.append(p)
            return p
        }

        func getThemeSections(_ themeArg: SExpr) throws -> (name: String, sections: [Section]) {
            if case .list(let items) = themeArg {
                if items.isEmpty {
                    return ("empty", [])
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
                        throw TMDMacroError("'transpose' requires theme and semitones offset, e.g. (transpose Theme 7)")
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
                    return ("\(sub.name)_tr\(signStr)", transposeSections(sub.sections, semitones: semitones))
                }

                if head == "reverse" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'reverse' requires a target theme, e.g. (reverse Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_rev", reverseSections(sub.sections))
                }

                if head == "flip" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'flip' requires a target theme, e.g. (flip Theme)")
                    }
                    var axis: Int? = nil
                    if items.count >= 3, case .number(let a) = items[2] {
                        axis = a
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_flip", invertSections(sub.sections, axisPitchSemitones: axis))
                }

                if head == "minor" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'minor' requires a target theme, e.g. (minor Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_minor", toMinorSections(sub.sections))
                }

                if head == "major" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'major' requires a target theme, e.g. (major Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_major", toMajorSections(sub.sections))
                }

                if head == "vary" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'vary' requires a target theme, e.g. (vary Theme +7 reverse)")
                    }
                    var current = try getThemeSections(items[1])
                    for i in 2..<items.count {
                        let transform = items[i]
                        switch transform {
                        case .list(let tList):
                            guard !tList.isEmpty, case .symbol(let tOpRaw) = tList[0] else { continue }
                            let tOp = tOpRaw.lowercased()
                            if tOp == "transpose" {
                                var semi = 0
                                if tList.count >= 2, case .number(let n) = tList[1] { semi = n }
                                let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                                current = ("\(current.name)_tr\(sign)", transposeSections(current.sections, semitones: semi))
                            } else if tOp == "reverse" {
                                current = ("\(current.name)_rev", reverseSections(current.sections))
                            } else if tOp == "flip" {
                                var axis: Int? = nil
                                if tList.count >= 2, case .number(let a) = tList[1] { axis = a }
                                current = ("\(current.name)_flip", invertSections(current.sections, axisPitchSemitones: axis))
                            } else if tOp == "minor" {
                                current = ("\(current.name)_minor", toMinorSections(current.sections))
                            } else if tOp == "major" {
                                current = ("\(current.name)_major", toMajorSections(current.sections))
                            }
                        case .symbol(let sym):
                            let lower = sym.lowercased()
                            if lower == "reverse" {
                                current = ("\(current.name)_rev", reverseSections(current.sections))
                            } else if lower == "flip" {
                                current = ("\(current.name)_flip", invertSections(current.sections))
                            } else if lower == "minor" {
                                current = ("\(current.name)_minor", toMinorSections(current.sections))
                            } else if lower == "major" {
                                current = ("\(current.name)_major", toMajorSections(current.sections))
                            } else if let semi = Int(sym) {
                                let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                                current = ("\(current.name)_tr\(sign)", transposeSections(current.sections, semitones: semi))
                            }
                        case .number(let semi):
                            let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                            current = ("\(current.name)_tr\(sign)", transposeSections(current.sections, semitones: semi))
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

            if let p = abstractMap[themeName] ?? sheet.paragraphs.first(where: { $0.name == themeName }) {
                return (themeName, p.sections)
            }
            throw TMDMacroError("Theme '\(themeName)' not found")
        }

        func evalExpr(_ expr: SExpr) throws -> [String] {
            guard case .list(let items) = expr else {
                let targetName = expr.description
                let matching = concreteParagraphs.filter { $0.name == targetName }
                if !matching.isEmpty {
                    var clonedNames: [String] = []
                    for p in matching {
                        let synthetic = createSyntheticParagraph(
                            baseName: p.name,
                            instrument: p.instrument,
                            startOffset: p.start,
                            sections: p.sections
                        )
                        clonedNames.append(synthetic.name)
                    }
                    return clonedNames
                }
                throw TMDMacroError("Target '\(targetName)' is not a valid section or macro expression")
            }

            guard !items.isEmpty, case .symbol(let opRaw) = items[0] else {
                return []
            }

            let op = opRaw.lowercased()

            switch op {
            case "play":
                guard items.count >= 3 else {
                    throw TMDMacroError("'play' requires theme and instrument, e.g. (play Theme Violin)")
                }
                let themeTarget = items[1]
                let instrument = items[2].description
                var atOffset = 0
                if items.count >= 5, case .symbol(let atFlag) = items[3], atFlag.lowercased() == ":at" {
                    if case .number(let n) = items[4] { atOffset = n }
                } else if items.count >= 4, case .number(let n) = items[3] {
                    atOffset = n
                }

                let (themeName, sections) = try getThemeSections(themeTarget)
                let p = createSyntheticParagraph(
                    baseName: themeName,
                    instrument: instrument,
                    startOffset: atOffset,
                    sections: sections
                )
                return [p.name]

            case "loop":
                guard items.count >= 3 else {
                    throw TMDMacroError("'loop' requires theme and instrument (or theme and times), e.g. (loop B 10) or (loop Theme Cello 4)")
                }
                let themeTarget = items[1]
                var instrument = ""
                var times = 1

                if items.count == 3, case .number(let n) = items[2] {
                    times = n
                    let targetName = themeTarget.description
                    if let match = sheet.paragraphs.first(where: { $0.name == targetName && !$0.instrument.isEmpty }) {
                        instrument = match.instrument
                    } else {
                        throw TMDMacroError("'loop' with 2 arguments requires a concrete section with an instrument, but '\(targetName)' has no instrument")
                    }
                } else {
                    instrument = items[2].description
                    if items.count >= 4, case .number(let n) = items[3] {
                        times = n
                    }
                }

                let (themeName, baseSections) = try getThemeSections(themeTarget)
                var loopedSections: [Section] = []
                for _ in 0..<times {
                    loopedSections.append(contentsOf: baseSections)
                }

                let p = createSyntheticParagraph(
                    baseName: themeName,
                    instrument: instrument,
                    startOffset: 0,
                    sections: loopedSections
                )
                return [p.name]

            case "canon":
                guard items.count >= 3 else {
                    throw TMDMacroError("'canon' requires theme and instruments, e.g. (canon Theme (Violin1 Violin2) 2)")
                }
                let themeTarget = items[1]
                var instruments: [String] = []
                if case .list(let instList) = items[2] {
                    instruments = instList.map(\.description)
                } else {
                    instruments = [items[2].description]
                }
                var offsetBars = 0
                if items.count >= 4, case .number(let n) = items[3] {
                    offsetBars = n
                }

                // Check if themeTarget is a nested sub-expression
                func isSubExpr(_ node: SExpr) -> Bool {
                    guard case .list(let subItems) = node, !subItems.isEmpty else { return false }
                    guard case .symbol(let hRaw) = subItems[0] else { return false }
                    let h = hRaw.lowercased()
                    if ["canon", "layer", "play", "loop", "seq"].contains(h) { return true }
                    if ["reverse", "flip", "minor", "major", "vary", "transpose"].contains(h) {
                        return (subItems.count >= 2 && isSubExpr(subItems[1])) || (subItems.count >= 3 && isSubExpr(subItems[2]))
                    }
                    return false
                }

                if isSubExpr(themeTarget) {
                    let innerNames = try evalExpr(themeTarget)
                    let innerParagraphs = concreteParagraphs.filter { innerNames.contains($0.name) }

                    var innerDistinctInsts: [String] = []
                    for ip in innerParagraphs where !innerDistinctInsts.contains(ip.instrument) {
                        innerDistinctInsts.append(ip.instrument)
                    }

                    genCounter += 1
                    let outerCanonSectionName = "__nested_canon_\(genCounter)"

                    if !instruments.isEmpty {
                        for ip in innerParagraphs {
                            let instIdx = innerDistinctInsts.firstIndex(of: ip.instrument) ?? -1
                            let mappedInst = (instIdx >= 0 && instIdx < instruments.count) ? instruments[instIdx] : ip.instrument

                            let outerP = createSyntheticParagraph(
                                baseName: ip.name,
                                instrument: mappedInst,
                                startOffset: ip.start + offsetBars,
                                sections: ip.sections
                            )
                            concreteParagraphs.removeAll { $0.name == outerP.name }
                            concreteParagraphs.append(Paragraph(
                                name: outerCanonSectionName,
                                instrument: mappedInst,
                                start: ip.start + offsetBars,
                                sections: ip.sections
                            ))
                        }
                    }

                    for i in 0..<concreteParagraphs.count {
                        if innerNames.contains(concreteParagraphs[i].name) {
                            concreteParagraphs[i] = Paragraph(
                                name: outerCanonSectionName,
                                instrument: concreteParagraphs[i].instrument,
                                start: concreteParagraphs[i].start,
                                sections: concreteParagraphs[i].sections
                            )
                        }
                    }

                    return [outerCanonSectionName]
                }

                let (themeName, sections) = try getThemeSections(themeTarget)
                genCounter += 1
                let canonSectionName = "__canon_\(themeName)_\(genCounter)"

                for (idx, inst) in instruments.enumerated() {
                    let startOffset = idx * offsetBars
                    let p = Paragraph(
                        name: canonSectionName,
                        instrument: inst,
                        start: startOffset,
                        sections: sections
                    )
                    concreteParagraphs.append(p)
                }

                return [canonSectionName]

            case "layer":
                var childNames: [String] = []
                for i in 1..<items.count {
                    let names = try evalExpr(items[i])
                    childNames.append(contentsOf: names)
                }

                genCounter += 1
                let layerSectionName = "__layer_\(genCounter)"
                for i in 0..<concreteParagraphs.count {
                    if childNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: layerSectionName,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: concreteParagraphs[i].sections
                        )
                    }
                }
                return [layerSectionName]

            case "seq":
                var seqNames: [String] = []
                for i in 1..<items.count {
                    let names = try evalExpr(items[i])
                    seqNames.append(contentsOf: names)
                }
                return seqNames

            case "reverse":
                guard items.count >= 2 else {
                    throw TMDMacroError("'reverse' requires a target theme or expression, e.g. (reverse Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: reverseSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "flip":
                guard items.count >= 2 else {
                    throw TMDMacroError("'flip' requires a target theme or expression, e.g. (flip Theme)")
                }
                var axis: Int? = nil
                if items.count >= 3, case .number(let a) = items[2] { axis = a }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: invertSections(concreteParagraphs[i].sections, axisPitchSemitones: axis)
                        )
                    }
                }
                return innerNames

            case "minor":
                guard items.count >= 2 else {
                    throw TMDMacroError("'minor' requires a target theme or expression, e.g. (minor Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: toMinorSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "major":
                guard items.count >= 2 else {
                    throw TMDMacroError("'major' requires a target theme or expression, e.g. (major Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: toMajorSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "transpose":
                guard items.count >= 3 else {
                    throw TMDMacroError("'transpose' requires theme and semitones offset, e.g. (transpose Theme 7)")
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
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: transposeSections(concreteParagraphs[i].sections, semitones: semitones)
                        )
                    }
                }
                return innerNames

            case "vary":
                guard items.count >= 2 else {
                    throw TMDMacroError("'vary' requires a target theme or expression, e.g. (vary Theme +7 reverse)")
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
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: transposeSections(concreteParagraphs[idx].sections, semitones: semi)
                                )
                            }
                        } else if tOp == "reverse" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: reverseSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if tOp == "flip" {
                            var axis: Int? = nil
                            if tList.count >= 2, case .number(let a) = tList[1] { axis = a }
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: invertSections(concreteParagraphs[idx].sections, axisPitchSemitones: axis)
                                )
                            }
                        } else if tOp == "minor" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMinorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if tOp == "major" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMajorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        }
                    case .symbol(let sym):
                        let lower = sym.lowercased()
                        if lower == "reverse" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: reverseSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "flip" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: invertSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "minor" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMinorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "major" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMajorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if let semi = Int(sym) {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: transposeSections(concreteParagraphs[idx].sections, semitones: semi)
                                )
                            }
                        }
                    case .number(let semi):
                        for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                            concreteParagraphs[idx] = Paragraph(
                                name: concreteParagraphs[idx].name,
                                instrument: concreteParagraphs[idx].instrument,
                                start: concreteParagraphs[idx].start,
                                sections: transposeSections(concreteParagraphs[idx].sections, semitones: semi)
                            )
                        }
                    }
                }
                return innerNames

            default:
                throw TMDMacroError("Unknown macro operation '\(op)' in S-expression")
            }
        }

        do {
            for order in sheet.orders {
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
        } catch {
            // Re-throw or propagate
            print("\(error.localizedDescription)")
        }

        return Sheet(
            name: sheet.name,
            speed: sheet.speed,
            keySignature: sheet.keySignature,
            beat: sheet.beat,
            paragraphs: concreteParagraphs,
            orders: newOrders,
            metadata: sheet.metadata
        )
    }

    /// Throwing variant of expand.
    public static func expandThrowing(_ sheet: Sheet) throws -> Sheet {
        let hasMacro = sheet.orders.contains { if case .macro = $0 { return true } else { return false } }
        if !hasMacro {
            return sheet
        }

        var abstractMap: [String: Paragraph] = [:]
        for p in sheet.paragraphs where p.instrument.isEmpty {
            abstractMap[p.name] = p
        }

        var concreteParagraphs: [Paragraph] = sheet.paragraphs.filter { !$0.instrument.isEmpty }
        var newOrders: [Order] = []
        var genCounter = 0

        func createSyntheticParagraph(
            baseName: String,
            instrument: String,
            startOffset: Int,
            sections: [Section]
        ) -> Paragraph {
            genCounter += 1
            let uniqueName = "__macro_\(baseName)_\(genCounter)"
            let p = Paragraph(
                name: uniqueName,
                instrument: instrument,
                start: startOffset,
                sections: sections
            )
            concreteParagraphs.append(p)
            return p
        }

        func getThemeSections(_ themeArg: SExpr) throws -> (name: String, sections: [Section]) {
            if case .list(let items) = themeArg {
                if items.isEmpty {
                    return ("empty", [])
                }

                guard case .symbol(let headRaw) = items[0] else {
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
                        throw TMDMacroError("'transpose' requires theme and semitones offset, e.g. (transpose Theme 7)")
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
                    return ("\(sub.name)_tr\(signStr)", transposeSections(sub.sections, semitones: semitones))
                }

                if head == "reverse" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'reverse' requires a target theme, e.g. (reverse Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_rev", reverseSections(sub.sections))
                }

                if head == "flip" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'flip' requires a target theme, e.g. (flip Theme)")
                    }
                    var axis: Int? = nil
                    if items.count >= 3, case .number(let a) = items[2] {
                        axis = a
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_flip", invertSections(sub.sections, axisPitchSemitones: axis))
                }

                if head == "minor" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'minor' requires a target theme, e.g. (minor Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_minor", toMinorSections(sub.sections))
                }

                if head == "major" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'major' requires a target theme, e.g. (major Theme)")
                    }
                    let sub = try getThemeSections(items[1])
                    return ("\(sub.name)_major", toMajorSections(sub.sections))
                }

                if head == "vary" {
                    guard items.count >= 2 else {
                        throw TMDMacroError("'vary' requires a target theme, e.g. (vary Theme +7 reverse)")
                    }
                    var current = try getThemeSections(items[1])
                    for i in 2..<items.count {
                        let transform = items[i]
                        switch transform {
                        case .list(let tList):
                            guard !tList.isEmpty, case .symbol(let tOpRaw) = tList[0] else { continue }
                            let tOp = tOpRaw.lowercased()
                            if tOp == "transpose" {
                                var semi = 0
                                if tList.count >= 2, case .number(let n) = tList[1] { semi = n }
                                let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                                current = ("\(current.name)_tr\(sign)", transposeSections(current.sections, semitones: semi))
                            } else if tOp == "reverse" {
                                current = ("\(current.name)_rev", reverseSections(current.sections))
                            } else if tOp == "flip" {
                                var axis: Int? = nil
                                if tList.count >= 2, case .number(let a) = tList[1] { axis = a }
                                current = ("\(current.name)_flip", invertSections(current.sections, axisPitchSemitones: axis))
                            } else if tOp == "minor" {
                                current = ("\(current.name)_minor", toMinorSections(current.sections))
                            } else if tOp == "major" {
                                current = ("\(current.name)_major", toMajorSections(current.sections))
                            }
                        case .symbol(let sym):
                            let lower = sym.lowercased()
                            if lower == "reverse" {
                                current = ("\(current.name)_rev", reverseSections(current.sections))
                            } else if lower == "flip" {
                                current = ("\(current.name)_flip", invertSections(current.sections))
                            } else if lower == "minor" {
                                current = ("\(current.name)_minor", toMinorSections(current.sections))
                            } else if lower == "major" {
                                current = ("\(current.name)_major", toMajorSections(current.sections))
                            } else if let semi = Int(sym) {
                                let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                                current = ("\(current.name)_tr\(sign)", transposeSections(current.sections, semitones: semi))
                            }
                        case .number(let semi):
                            let sign = semi >= 0 ? "+\(semi)" : "\(semi)"
                            current = ("\(current.name)_tr\(sign)", transposeSections(current.sections, semitones: semi))
                        }
                    }
                    return current
                }

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

            if let p = abstractMap[themeName] ?? sheet.paragraphs.first(where: { $0.name == themeName }) {
                return (themeName, p.sections)
            }
            throw TMDMacroError("Theme '\(themeName)' not found")
        }

        func evalExpr(_ expr: SExpr) throws -> [String] {
            guard case .list(let items) = expr else {
                let targetName = expr.description
                let matching = concreteParagraphs.filter { $0.name == targetName }
                if !matching.isEmpty {
                    var clonedNames: [String] = []
                    for p in matching {
                        let synthetic = createSyntheticParagraph(
                            baseName: p.name,
                            instrument: p.instrument,
                            startOffset: p.start,
                            sections: p.sections
                        )
                        clonedNames.append(synthetic.name)
                    }
                    return clonedNames
                }
                throw TMDMacroError("Target '\(targetName)' is not a valid section or macro expression")
            }

            guard !items.isEmpty, case .symbol(let opRaw) = items[0] else {
                return []
            }

            let op = opRaw.lowercased()

            switch op {
            case "play":
                guard items.count >= 3 else {
                    throw TMDMacroError("'play' requires theme and instrument, e.g. (play Theme Violin)")
                }
                let themeTarget = items[1]
                let instrument = items[2].description
                var atOffset = 0
                if items.count >= 5, case .symbol(let atFlag) = items[3], atFlag.lowercased() == ":at" {
                    if case .number(let n) = items[4] { atOffset = n }
                } else if items.count >= 4, case .number(let n) = items[3] {
                    atOffset = n
                }

                let (themeName, sections) = try getThemeSections(themeTarget)
                let p = createSyntheticParagraph(
                    baseName: themeName,
                    instrument: instrument,
                    startOffset: atOffset,
                    sections: sections
                )
                return [p.name]

            case "loop":
                guard items.count >= 3 else {
                    throw TMDMacroError("'loop' requires theme and instrument (or theme and times), e.g. (loop B 10) or (loop Theme Cello 4)")
                }
                let themeTarget = items[1]
                var instrument = ""
                var times = 1

                if items.count == 3, case .number(let n) = items[2] {
                    times = n
                    let targetName = themeTarget.description
                    if let match = sheet.paragraphs.first(where: { $0.name == targetName && !$0.instrument.isEmpty }) {
                        instrument = match.instrument
                    } else {
                        throw TMDMacroError("'loop' with 2 arguments requires a concrete section with an instrument, but '\(targetName)' has no instrument")
                    }
                } else {
                    instrument = items[2].description
                    if items.count >= 4, case .number(let n) = items[3] {
                        times = n
                    }
                }

                let (themeName, baseSections) = try getThemeSections(themeTarget)
                var loopedSections: [Section] = []
                for _ in 0..<times {
                    loopedSections.append(contentsOf: baseSections)
                }

                let p = createSyntheticParagraph(
                    baseName: themeName,
                    instrument: instrument,
                    startOffset: 0,
                    sections: loopedSections
                )
                return [p.name]

            case "canon":
                guard items.count >= 3 else {
                    throw TMDMacroError("'canon' requires theme and instruments, e.g. (canon Theme (Violin1 Violin2) 2)")
                }
                let themeTarget = items[1]
                var instruments: [String] = []
                if case .list(let instList) = items[2] {
                    instruments = instList.map(\.description)
                } else {
                    instruments = [items[2].description]
                }
                var offsetBars = 0
                if items.count >= 4, case .number(let n) = items[3] {
                    offsetBars = n
                }

                func isSubExpr(_ node: SExpr) -> Bool {
                    guard case .list(let subItems) = node, !subItems.isEmpty else { return false }
                    guard case .symbol(let hRaw) = subItems[0] else { return false }
                    let h = hRaw.lowercased()
                    if ["canon", "layer", "play", "loop", "seq"].contains(h) { return true }
                    if ["reverse", "flip", "minor", "major", "vary", "transpose"].contains(h) {
                        return (subItems.count >= 2 && isSubExpr(subItems[1])) || (subItems.count >= 3 && isSubExpr(subItems[2]))
                    }
                    return false
                }

                if isSubExpr(themeTarget) {
                    let innerNames = try evalExpr(themeTarget)
                    let innerParagraphs = concreteParagraphs.filter { innerNames.contains($0.name) }

                    var innerDistinctInsts: [String] = []
                    for ip in innerParagraphs where !innerDistinctInsts.contains(ip.instrument) {
                        innerDistinctInsts.append(ip.instrument)
                    }

                    genCounter += 1
                    let outerCanonSectionName = "__nested_canon_\(genCounter)"

                    if !instruments.isEmpty {
                        for ip in innerParagraphs {
                            let instIdx = innerDistinctInsts.firstIndex(of: ip.instrument) ?? -1
                            let mappedInst = (instIdx >= 0 && instIdx < instruments.count) ? instruments[instIdx] : ip.instrument

                            let outerP = createSyntheticParagraph(
                                baseName: ip.name,
                                instrument: mappedInst,
                                startOffset: ip.start + offsetBars,
                                sections: ip.sections
                            )
                            concreteParagraphs.removeAll { $0.name == outerP.name }
                            concreteParagraphs.append(Paragraph(
                                name: outerCanonSectionName,
                                instrument: mappedInst,
                                start: ip.start + offsetBars,
                                sections: ip.sections
                            ))
                        }
                    }

                    for i in 0..<concreteParagraphs.count {
                        if innerNames.contains(concreteParagraphs[i].name) {
                            concreteParagraphs[i] = Paragraph(
                                name: outerCanonSectionName,
                                instrument: concreteParagraphs[i].instrument,
                                start: concreteParagraphs[i].start,
                                sections: concreteParagraphs[i].sections
                            )
                        }
                    }

                    return [outerCanonSectionName]
                }

                let (themeName, sections) = try getThemeSections(themeTarget)
                genCounter += 1
                let canonSectionName = "__canon_\(themeName)_\(genCounter)"

                for (idx, inst) in instruments.enumerated() {
                    let startOffset = idx * offsetBars
                    let p = Paragraph(
                        name: canonSectionName,
                        instrument: inst,
                        start: startOffset,
                        sections: sections
                    )
                    concreteParagraphs.append(p)
                }

                return [canonSectionName]

            case "layer":
                var childNames: [String] = []
                for i in 1..<items.count {
                    let names = try evalExpr(items[i])
                    childNames.append(contentsOf: names)
                }

                genCounter += 1
                let layerSectionName = "__layer_\(genCounter)"
                for i in 0..<concreteParagraphs.count {
                    if childNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: layerSectionName,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: concreteParagraphs[i].sections
                        )
                    }
                }
                return [layerSectionName]

            case "seq":
                var seqNames: [String] = []
                for i in 1..<items.count {
                    let names = try evalExpr(items[i])
                    seqNames.append(contentsOf: names)
                }
                return seqNames

            case "reverse":
                guard items.count >= 2 else {
                    throw TMDMacroError("'reverse' requires a target theme or expression, e.g. (reverse Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: reverseSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "flip":
                guard items.count >= 2 else {
                    throw TMDMacroError("'flip' requires a target theme or expression, e.g. (flip Theme)")
                }
                var axis: Int? = nil
                if items.count >= 3, case .number(let a) = items[2] { axis = a }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: invertSections(concreteParagraphs[i].sections, axisPitchSemitones: axis)
                        )
                    }
                }
                return innerNames

            case "minor":
                guard items.count >= 2 else {
                    throw TMDMacroError("'minor' requires a target theme or expression, e.g. (minor Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: toMinorSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "major":
                guard items.count >= 2 else {
                    throw TMDMacroError("'major' requires a target theme or expression, e.g. (major Theme)")
                }
                let innerNames = try evalExpr(items[1])
                for i in 0..<concreteParagraphs.count {
                    if innerNames.contains(concreteParagraphs[i].name) {
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: toMajorSections(concreteParagraphs[i].sections)
                        )
                    }
                }
                return innerNames

            case "transpose":
                guard items.count >= 3 else {
                    throw TMDMacroError("'transpose' requires theme and semitones offset, e.g. (transpose Theme 7)")
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
                        concreteParagraphs[i] = Paragraph(
                            name: concreteParagraphs[i].name,
                            instrument: concreteParagraphs[i].instrument,
                            start: concreteParagraphs[i].start,
                            sections: transposeSections(concreteParagraphs[i].sections, semitones: semitones)
                        )
                    }
                }
                return innerNames

            case "vary":
                guard items.count >= 2 else {
                    throw TMDMacroError("'vary' requires a target theme or expression, e.g. (vary Theme +7 reverse)")
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
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: transposeSections(concreteParagraphs[idx].sections, semitones: semi)
                                )
                            }
                        } else if tOp == "reverse" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: reverseSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if tOp == "flip" {
                            var axis: Int? = nil
                            if tList.count >= 2, case .number(let a) = tList[1] { axis = a }
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: invertSections(concreteParagraphs[idx].sections, axisPitchSemitones: axis)
                                )
                            }
                        } else if tOp == "minor" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMinorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if tOp == "major" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMajorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        }
                    case .symbol(let sym):
                        let lower = sym.lowercased()
                        if lower == "reverse" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: reverseSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "flip" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: invertSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "minor" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMinorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if lower == "major" {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: toMajorSections(concreteParagraphs[idx].sections)
                                )
                            }
                        } else if let semi = Int(sym) {
                            for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                                concreteParagraphs[idx] = Paragraph(
                                    name: concreteParagraphs[idx].name,
                                    instrument: concreteParagraphs[idx].instrument,
                                    start: concreteParagraphs[idx].start,
                                    sections: transposeSections(concreteParagraphs[idx].sections, semitones: semi)
                                )
                            }
                        }
                    case .number(let semi):
                        for idx in 0..<concreteParagraphs.count where innerNames.contains(concreteParagraphs[idx].name) {
                            concreteParagraphs[idx] = Paragraph(
                                name: concreteParagraphs[idx].name,
                                instrument: concreteParagraphs[idx].instrument,
                                start: concreteParagraphs[idx].start,
                                sections: transposeSections(concreteParagraphs[idx].sections, semitones: semi)
                            )
                        }
                    }
                }
                return innerNames

            default:
                throw TMDMacroError("Unknown macro operation '\(op)' in S-expression")
            }
        }

        for order in sheet.orders {
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
            paragraphs: concreteParagraphs,
            orders: newOrders,
            metadata: sheet.metadata
        )
    }
}
