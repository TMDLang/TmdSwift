import Foundation

// MARK: - Summary and TMD Formatting

extension Sheet {
    /// Generates a human-readable summary of the sheet structure.
    public func summary() -> String {
        var lines: [String] = []
        lines.append("Name:         \(name)")
        lines.append("Speed:        \(speed) BPM")
        lines.append("KeySignature: \(keySignature)")
        if let declaredKey {
            lines.append("DeclaredKey:  \(declaredKey)")
        }
        lines.append("Beat:         \(beat.count)/\(beat.noteValue)")
        lines.append("Entries:      \(entries.count)")
        for (idx, p) in entries.enumerated() {
            let secCount = p.sections.count
            let totalUnits = p.sections.reduce(0) { $0 + $1.unitGroups.count }
            lines.append(
                "  [\(idx + 1)] \(p.name) (Assignment: \(p.assignment ?? ""), Start: \(p.start), Sections: \(secCount), UnitGroups: \(totalUnits))"
            )
        }
        lines.append("Playback:     \(playback.count)")
        for (idx, order) in playback.enumerated() {
            lines.append("  [\(idx + 1)] -> \(order.format())")
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
        result +=
            "!= \(speed.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(speed)) : String(speed))\n"
        result += "?= \(keySignature)\n"
        if let declaredKey {
            result += "key= \(declaredKey)\n"
        }
        result += "<\(beat.count)/\(beat.noteValue)>\n\n"

        for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
            if ["lyrics", "composer", "arranger"].contains(key.lowercased()) {
                result += "~ \"\(value)\"\n"
            } else {
                result += "=~:__\(key.uppercased())__= \"\(value)\"\n"
            }
        }
        if !metadata.isEmpty { result += "\n" }

        for paragraph in entries {
            result += paragraph.format()
        }

        let orderTokens = playback.map { "-> \($0.format())" } + ["->#"]
        result += orderTokens.joined(separator: " ") + "\n"
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
        var str = "\(degree.rawValue)\(accidental.tmdSymbol)"
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
        case .multiNote(let notes):
            notes.map { $0.format() }.joined(separator: "+")
        }
    }
}

extension UnitGroup {
    /// Formats unit group into TMD representation.
    public func format() -> String {
        if units.count == 1 && length == 1 {
            return units[0].format()
        } else {
            let unitsStr = units.map { $0.format() }.joined(separator: " ")
            let lengthStr = String(repeating: "-", count: length)
            return "(\(unitsStr))%(\(lengthStr))"
        }
    }
}

extension Section {
    /// Formats section into TMD representation.
    public func format() -> String {
        var lines: [String] = ["    <\(noteLength)*>"]
        var currentLineTokens: [String] = []
        var counter = 0
        var directiveIndex = 0
        let sortedDirectives = directives.sorted { $0.position < $1.position }

        func ensureLineStarted() {
            if currentLineTokens.isEmpty {
                currentLineTokens.append("|")
            }
        }

        func flushCurrentLine() {
            guard !currentLineTokens.isEmpty else { return }
            if currentLineTokens.last != "|" {
                currentLineTokens.append("|")
            }
            lines.append("    " + currentLineTokens.joined(separator: " "))
            currentLineTokens.removeAll()
        }

        func appendDirectives(at position: Int) {
            while directiveIndex < sortedDirectives.count
                && sortedDirectives[directiveIndex].position == position
            {
                ensureLineStarted()
                currentLineTokens.append(sortedDirectives[directiveIndex].format())
                directiveIndex += 1
            }
        }

        var position = 0
        let barlines = Set(barlinePositions)
        let lyricStarts = Set(lyrics.map { $0.unitGroupRange.lowerBound })
        var lyricsByEnd: [Int: [LyricLine]] = [:]
        for line in lyrics {
            lyricsByEnd[line.unitGroupRange.upperBound, default: []].append(line)
        }
        func isInsideLyricPhrase(_ groupIndex: Int) -> Bool {
            lyrics.contains {
                groupIndex > $0.unitGroupRange.lowerBound && groupIndex < $0.unitGroupRange.upperBound
            }
        }
        func flushLyricsEnding(at groupIndex: Int) {
            guard let attached = lyricsByEnd[groupIndex], !attached.isEmpty else { return }
            flushCurrentLine()
            counter = 0
            let sortedLyrics = attached.sorted { lhs, rhs in
                (lhs.stanza ?? 0) < (rhs.stanza ?? 0)
            }
            for lyricLine in sortedLyrics {
                lines.append("    " + lyricLine.format())
            }
        }

        appendDirectives(at: position)
        flushLyricsEnding(at: 0)
        for (groupIndex, unitGroup) in unitGroups.enumerated() {
            if lyricStarts.contains(groupIndex) && !currentLineTokens.isEmpty {
                flushCurrentLine()
                counter = 0
            } else if counter >= 8 && !isInsideLyricPhrase(groupIndex) {
                flushCurrentLine()
                counter = 0
            } else if position > 0 && barlines.contains(position) {
                ensureLineStarted()
                if currentLineTokens.last != "|" {
                    currentLineTokens.append("|")
                }
            }
            ensureLineStarted()
            currentLineTokens.append(unitGroup.format())
            counter += unitGroup.length
            position += unitGroup.length
            appendDirectives(at: position)
            flushLyricsEnding(at: groupIndex + 1)
        }
        while directiveIndex < sortedDirectives.count {
            ensureLineStarted()
            currentLineTokens.append(sortedDirectives[directiveIndex].format())
            directiveIndex += 1
        }
        flushCurrentLine()
        return lines.joined(separator: "\n") + "\n"
    }
}

extension SectionDirectiveKind {
    /// Formats a section directive kind into TMD representation.
    public func format() -> String {
        switch self {
        case .tempo(let value):
            "{!=\(value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value))}"
        case .relativeTempo(let value):
            "{!+\(value)}"
        case .absoluteKey(let key):
            "{?=\(key)}"
        case .relativeKey(let value):
            "{?\(value >= 0 ? "+\(value)" : String(value))}"
        case .explicitKey(let key):
            "{key= \(key)}"
        case .dynamics(let mark):
            "{\(mark.rawValue)}"
        case .fixedPitch:
            "{?=fixed}"
        case .timeSignature(let beat):
            "{<\(beat.count)/\(beat.noteValue)>}"
        }
    }
}

extension SectionDirective {
    public func format() -> String {
        kind.format()
    }
}

extension Entry {
    /// Formats paragraph into TMD representation.
    public func format() -> String {
        if let showProgram {
            let time = executionTime ?? ""
            let assignmentName = assignment ?? ""
            return "\(name):\(assignmentName)@\(time){\n\"\"\"\(showProgram)\"\"\"\n}\n\n"
        }
        var result = ""
        if (assignment ?? "").isEmpty {
            result = "\(name) {\n"
        } else {
            result = "\(name):\(assignment ?? "")"
            if pitchMode == .fixed {
                result += "[pitchMode=fixed]"
            }
            result += "@|"
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

extension Playback {
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
