import Foundation

extension TmdRefactor {
    /// Transposes notes and chords in a TMD score or snippet by semitones or diatonic steps.
    public static func transpose(
        source: String,
        semitones: Int = 0,
        diatonicSteps: Int = 0,
        keySignature: String? = nil,
        updateKeySignature: Bool = false,
        target: TmdRefactorTarget? = nil
    ) -> String {
        if semitones == 0 && diatonicSteps == 0 && !updateKeySignature {
            return source
        }

        var currentKeySig = keySignature ?? "C"
        let keyRegex = try? NSRegularExpression(
            pattern: "(?:^|\\n)\\s*\\?=\\s*([A-Ga-g0-9',#b]+)", options: [])
        let nsSource = source as NSString
        if let match = keyRegex?.firstMatch(
            in: source, options: [], range: NSRange(location: 0, length: nsSource.length))
        {
            currentKeySig = nsSource.substring(with: match.range(at: 1))
        }

        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []

        var insideParagraph = false
        var inMatchingPara = true

        let isFullScore =
            source.contains("::SCORE::")
            || (try? NSRegularExpression(
                pattern:
                    "(^|\\n)\\s*[a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+:[a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+@",
                options: []))?
                .firstMatch(
                    in: source, options: [], range: NSRange(location: 0, length: nsSource.length))
                != nil

        let headerRegex = try? NSRegularExpression(
            pattern:
                "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
            options: []
        )

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if updateKeySignature && (trimmed.hasPrefix("?=") || trimmed.hasPrefix("? =")) {
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                let oldKeyStr =
                    trimmed.hasPrefix("? =")
                    ? String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    : String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                let newKeyStr = transposeKeySignature(oldKeyStr, semitones: semitones)
                resultLines.append("\(indent)?= \(newKeyStr)")
                currentKeySig = newKeyStr
                continue
            }

            let nsTrimmed = trimmed as NSString
            if let m = headerRegex?.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            {
                insideParagraph = true
                let pSec = nsTrimmed.substring(with: m.range(at: 1))
                let pInst = nsTrimmed.substring(with: m.range(at: 2))
                inMatchingPara =
                    (target?.section == nil || target?.section == pSec)
                    && (target?.instrument == nil || target?.instrument == pInst)
                resultLines.append(rawLine)
                continue
            }

            if trimmed == "}" {
                insideParagraph = false
                inMatchingPara = true
                resultLines.append(rawLine)
                continue
            }

            if (!isFullScore || (insideParagraph && inMatchingPara))
                && containsTransposableUnit(in: trimmed)
            {
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                let transformed = transposeUnitsInLine(
                    trimmed,
                    semitones: semitones,
                    diatonicSteps: diatonicSteps,
                    keySignature: currentKeySig
                )
                resultLines.append(indent + transformed)
                continue
            }

            resultLines.append(rawLine)
        }

        return format(resultLines.joined(separator: "\n"))
    }

    static func transposeKeySignature(_ keyStr: String, semitones: Int) -> String {
        let currentKey = KeySignature(string: keyStr.isEmpty ? "C" : keyStr)
        let oldOffset = currentKey.semitoneOffset
        let newOffset = ((oldOffset + semitones) % 12 + 12) % 12
        return PitchMapping.keyName(forSemitone: newOffset)
    }

    static func transposeTmdNote(
        _ noteStr: String,
        semitones: Int,
        diatonicSteps: Int,
        keySignature: String
    ) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: "^([1-7])(['#,]*)(\\^*|_*)?$", options: [])
        else {
            return noteStr
        }
        let nsStr = noteStr as NSString
        guard
            let match = regex.firstMatch(
                in: noteStr, options: [], range: NSRange(location: 0, length: nsStr.length))
        else {
            return noteStr
        }

        guard let deg = Int(nsStr.substring(with: match.range(at: 1))) else { return noteStr }
        let acc =
            match.range(at: 2).location != NSNotFound
            ? nsStr.substring(with: match.range(at: 2)) : ""
        let oct =
            match.range(at: 3).location != NSNotFound
            ? nsStr.substring(with: match.range(at: 3)) : ""

        var octaveDelta = 0
        if oct.hasPrefix("^") {
            octaveDelta = oct.count
        } else if oct.hasPrefix("_") {
            octaveDelta = -oct.count
        }

        if diatonicSteps != 0 && semitones == 0 {
            let zeroIndexed = deg - 1
            let newZero = zeroIndexed + diatonicSteps
            let newDeg = (((newZero % 7) + 7) % 7) + 1
            let addedOctaves = Int(floor(Double(newZero) / 7.0))
            let finalOctave = octaveDelta + addedOctaves

            var newOctStr = ""
            if finalOctave > 0 {
                newOctStr = String(repeating: "^", count: finalOctave)
            } else if finalOctave < 0 {
                newOctStr = String(repeating: "_", count: -finalOctave)
            }
            return "\(newDeg)\(acc)\(newOctStr)"
        }

        var accSemitone = 0
        if acc.contains("'") || acc.contains("#") {
            accSemitone = 1
        } else if acc.contains(",") {
            accSemitone = -1
        }

        let baseDegreeSemitone = (ScaleDegree(rawValue: deg)?.semitoneOffset ?? 0) + accSemitone
        let totalSemitonesRelTonic = baseDegreeSemitone + octaveDelta * 12 + semitones

        let semitoneInOct = ((totalSemitonesRelTonic % 12) + 12) % 12
        let finalOctave = Int(floor(Double(totalSemitonesRelTonic) / 12.0))

        let mapped = PitchMapping.semitoneToDegreeAccidental(semitoneInOct)
        var newOctStr = ""
        if finalOctave > 0 {
            newOctStr = String(repeating: "^", count: finalOctave)
        } else if finalOctave < 0 {
            newOctStr = String(repeating: "_", count: -finalOctave)
        }

        return "\(mapped.degree.rawValue)\(PitchMapping.accidentalSymbol(mapped.accidental))\(newOctStr)"
    }

    static func transposeTmdNoteUnit(
        _ unit: String,
        semitones: Int,
        diatonicSteps: Int,
        keySignature: String
    ) -> String {
        guard let tieStart = unit.firstIndex(of: "-") else {
            return transposeTmdNote(
                unit, semitones: semitones, diatonicSteps: diatonicSteps,
                keySignature: keySignature)
        }

        let note = String(unit[..<tieStart])
        let ties = String(unit[tieStart...])
        return transposeTmdNote(
            note, semitones: semitones, diatonicSteps: diatonicSteps,
            keySignature: keySignature) + ties
    }

    static func transposeChordToken(
        _ chordStr: String,
        semitones: Int,
        diatonicSteps: Int
    ) -> String {
        guard chordStr.hasPrefix("[") && chordStr.hasSuffix("]") && chordStr.count >= 2 else {
            return chordStr
        }
        let inner = String(chordStr.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        guard let firstChar = inner.first else { return chordStr }

        if firstChar >= "1" && firstChar <= "7" {
            if diatonicSteps != 0 && semitones == 0 {
                let suffix = String(inner.dropFirst())
                let deg = Int(String(firstChar)) ?? 1
                let newDeg = ((((deg - 1 + diatonicSteps) % 7) + 7) % 7) + 1
                return "[\(newDeg)\(suffix)]"
            }
            return chordStr
        }

        guard let regex = try? NSRegularExpression(pattern: "^([A-Ga-g]['#,b]?)(.*)$", options: [])
        else {
            return chordStr
        }
        let nsInner = inner as NSString
        guard
            let match = regex.firstMatch(
                in: inner, options: [], range: NSRange(location: 0, length: nsInner.length))
        else {
            return chordStr
        }

        let rootLetter = nsInner.substring(with: match.range(at: 1))
        let suffix = nsInner.substring(with: match.range(at: 2))

        guard let firstLetter = rootLetter.first else { return chordStr }
        let letter = String(firstLetter).uppercased()
        let acc = String(rootLetter.dropFirst())

        let letterNames = ["C", "D", "E", "F", "G", "A", "B"]
        guard let letterIndex = letterNames.firstIndex(of: letter) else { return chordStr }
        var semitoneOffset = [0, 2, 4, 5, 7, 9, 11][letterIndex]
        if acc == "'" || acc == "#" {
            semitoneOffset += 1
        } else if acc == "," || acc == "b" {
            semitoneOffset -= 1
        }

        let newOffset = ((semitoneOffset + semitones) % 12 + 12) % 12
        let offsetToLetter: [Int: String] = [
            0: "C", 1: "C#", 2: "D", 3: "Eb", 4: "E", 5: "F",
            6: "F#", 7: "G", 8: "Ab", 9: "A", 10: "Bb", 11: "B",
        ]
        let newRoot = offsetToLetter[newOffset] ?? "C"
        return "[\(newRoot)\(suffix)]"
    }

    static func transposeUnitsInLine(
        _ line: String,
        semitones: Int,
        diatonicSteps: Int,
        keySignature: String
    ) -> String {
        var working = line
        var commentSuffix = ""
        if let commentStart = working.range(of: "/*") {
            commentSuffix = " " + String(working[commentStart.lowerBound...])
            working = String(working[..<commentStart.lowerBound]).trimmingCharacters(
                in: .whitespaces)
        }

        let tokens = measureUnits(in: working)
        var outTokens: [String] = []

        for tok in tokens {
            if tok == "|" {
                outTokens.append("|")
                continue
            }

            if tok.hasPrefix("[") && tok.hasSuffix("]") {
                outTokens.append(
                    transposeChordToken(tok, semitones: semitones, diatonicSteps: diatonicSteps))
                continue
            }

            if let tuplet = parseTupletToken(tok) {
                let innerTokens = measureUnits(in: tuplet.inner)
                let transposedInner = innerTokens.map { t -> String in
                    if let f = t.first, f >= "1" && f <= "7" {
                        return transposeTmdNoteUnit(
                            t, semitones: semitones, diatonicSteps: diatonicSteps,
                            keySignature: keySignature)
                    }
                    if t.hasPrefix("[") && t.hasSuffix("]") {
                        return transposeChordToken(
                            t, semitones: semitones, diatonicSteps: diatonicSteps)
                    }
                    return t
                }
                let dashSuffix = !tuplet.dashes.isEmpty ? "%(\(tuplet.dashes))" : ""
                outTokens.append("(\(transposedInner.joined(separator: " ")))\(dashSuffix)")
                continue
            }

            if let f = tok.first, f >= "1" && f <= "7" {
                outTokens.append(
                    transposeTmdNoteUnit(
                        tok, semitones: semitones, diatonicSteps: diatonicSteps,
                        keySignature: keySignature))
                continue
            }

            outTokens.append(tok)
        }

        return outTokens.joined(separator: " ") + commentSuffix
    }
}
