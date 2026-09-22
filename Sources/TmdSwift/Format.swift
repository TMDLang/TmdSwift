import Foundation

// MARK: - Summary and TMD Formatting

extension Sheet {
    /// Generates a human-readable summary of the sheet structure.
    public func summary() -> String {
        var lines: [String] = []
        lines.append("Name:         \(name)")
        lines.append("Speed:        \(speed) BPM")
        lines.append("KeySignature: \(keySignature)")
        lines.append("Beat:         \(beat.count)/\(beat.noteValue)")
        lines.append("Paragraphs:   \(paragraphs.count)")
        for (idx, p) in paragraphs.enumerated() {
            let secCount = p.sections.count
            let totalUnits = p.sections.reduce(0) { $0 + $1.unitGroups.count }
            lines.append("  [\(idx + 1)] \(p.name) (Instrument: \(p.instrument), Start: \(p.start), Sections: \(secCount), UnitGroups: \(totalUnits))")
        }
        lines.append("Orders:       \(orders.count)")
        for (idx, order) in orders.enumerated() {
            switch order {
            case .name(let n):
                lines.append("  [\(idx + 1)] -> \(n)")
            case .relative(let rel):
                lines.append("  [\(idx + 1)] -> {?\(rel)}")
            case .absolute(let abs):
                lines.append("  [\(idx + 1)] -> {?=\(abs)}")
            case .macro(let expr):
                lines.append("  [\(idx + 1)] -> \(expr)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Formats the Sheet back into the TMD markup language string.
    ///
    /// Corresponds to `std::ostream& operator<<(std::ostream& o, const Sheet& value)` in Aguai's C++ code.
    public func format() -> String {
        var result = ""
        result += "::SCORE::\n"
        result += "** \(name) **\n"
        result += "!=\(speed.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(speed)) : String(speed))\n"
        result += "?=\(keySignature)\n"
        result += "<\(beat.count)/\(beat.noteValue)>\n\n"

        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            if ["lyrics", "composer", "arranger"].contains(key.lowercased()) {
                result += "~ \"\(value)\"\n"
            } else {
                result += "=~:__\(key.uppercased())__= \"\(value)\"\n"
            }
        }
        if !metadata.isEmpty { result += "\n" }

        for paragraph in paragraphs {
            result += paragraph.format()
        }

        var counter = 0
        for order in orders {
            result += "-> \(order.format()) "
            counter += 1
            if counter % 4 == 0 {
                result += "\n"
            }
        }
        result += "->#\n"
        return result
    }
}

extension Sheet: CustomStringConvertible {
    public var description: String {
        format()
    }
}

extension Note {
    /// Formats note into TMD representation (e.g. `1`, `1'`, `7,`, `3^`, `4_`).
    public func format() -> String {
        var str = "\(degree.rawValue)"
        switch accidental {
        case .sharp:
            str += "'"
        case .flat:
            str += ","
        case .natural:
            break
        }
        if octave > 0 {
            str += String(repeating: "^", count: octave)
        } else if octave < 0 {
            str += String(repeating: "_", count: -octave)
        }
        return str
    }
}

extension Unit {
    /// Formats unit into TMD representation.
    public func format() -> String {
        switch self {
        case .note(let n):
            n.format()
        case .chord(let ch):
            "[\(ch)]"
        case .tie:
            "-"
        case .rest:
            "0"
        case .percussion(let pattern):
            pattern
        }
    }
}

extension UnitGroup {
    /// Formats unit group into TMD representation.
    public func format() -> String {
        if units.count == 1 && length == 1 {
            return units[0].format()
        } else {
            let unitsStr = units.map { $0.format() }.joined()
            let lengthStr = String(repeating: "-", count: length)
            return "(\(unitsStr))%(\(lengthStr))"
        }
    }
}

extension Section {
    /// Formats section into TMD representation.
    public func format() -> String {
        var result = "\t<\(noteLength)*>"
        var counter = 0
        var directiveIndex = 0
        let sortedDirectives = directives.sorted { $0.position < $1.position }
        func appendDirectives(at position: Int, to result: inout String) {
            while directiveIndex < sortedDirectives.count && sortedDirectives[directiveIndex].position == position {
                result += "\(sortedDirectives[directiveIndex].format()) "
                directiveIndex += 1
            }
        }
        var position = 0
        appendDirectives(at: position, to: &result)
        for unitGroup in unitGroups {
            if counter % 8 == 0 || counter >= 8 {
                result += "\n\t"
                counter = 0
            }
            result += "\(unitGroup.format()) "
            counter += unitGroup.length
            position += unitGroup.length
            appendDirectives(at: position, to: &result)
        }
        while directiveIndex < sortedDirectives.count {
            result += "\(sortedDirectives[directiveIndex].format()) "
            directiveIndex += 1
        }
        result += "\n\n"
        return result
    }
}

extension SectionDirective {
    public func format() -> String {
        return switch kind {
        case .tempo(let value):
            "{!=\(value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value))}"
        case .relativeTempo(let value):
            "{!+\(value)}"
        case .absoluteKey(let key):
            "{?=\(key)}"
        case .relativeKey(let value):
            "{?\(value >= 0 ? "+\(value)" : String(value))}"
        case .timeSignature(let beat):
            "{<\(beat.count)/\(beat.noteValue)>}"
        }
    }
}

extension Paragraph {
    /// Formats paragraph into TMD representation.
    public func format() -> String {
        if let showProgram {
            let time = executionTime ?? ""
            return "\(name):\(instrument)@\(time){\n\"\"\"\(showProgram)\"\"\"\n}\n\n"
        }
        var result = ""
        if instrument.isEmpty {
            result = "\(name) {\n"
        } else {
            result = "\(name):\(instrument)@|"
            if start > 0 {
                result += "+\(start)"
            } else {
                result += "\(start)"
            }
            result += "|{\n"
        }

        for section in sections {
            result += section.format()
        }
        result += "}\n\n"
        return result
    }
}

extension Order {
    /// Formats order instruction into TMD representation.
    public func format() -> String {
        switch self {
        case .name(let n):
            n
        case .relative(let rel):
            "{?\(rel)}"
        case .absolute(let abs):
            "{?=\(abs)}"
        case .macro(let expr):
            expr.description
        }
    }
}
