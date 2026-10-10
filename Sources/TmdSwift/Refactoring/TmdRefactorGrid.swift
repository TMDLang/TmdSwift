import Foundation

extension TmdRefactor {
    /// Doubles grid resolution (<4*> -> <8*>) padding units with ties, doubling tuplet dash lengths.
    public static func doubleGrid(source: String, target: TmdRefactorTarget? = nil) throws -> String
    {
        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []

        var inMatchingPara = false
        var insideParagraph = false

        let headerRegex = try NSRegularExpression(
            pattern:
                "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
            options: []
        )
        let gridRegex = try NSRegularExpression(pattern: "^<(\\d+)\\*>", options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            let nsTrimmed = trimmed as NSString
            let match = headerRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let m = match {
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
                inMatchingPara = false
                resultLines.append(rawLine)
                continue
            }

            if !insideParagraph || !inMatchingPara {
                resultLines.append(rawLine)
                continue
            }

            let gMatch = gridRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let gm = gMatch {
                let lenStr = nsTrimmed.substring(with: gm.range(at: 1))
                let curLen = Int(lenStr) ?? 4
                let newLen = curLen * 2
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                resultLines.append("\(indent)<\(newLen)*>")
                continue
            }

            if trimmed.contains("|")
                || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "01234567[]-")) != nil
            {
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                let transformed = doubleGridInLine(trimmed)
                resultLines.append(indent + transformed)
            } else {
                resultLines.append(rawLine)
            }
        }

        return format(resultLines.joined(separator: "\n"))
    }

    /// Halves grid resolution (<8*> -> <4*>) collapsing ties and halving tuplet lengths.
    public static func halveGrid(source: String, target: TmdRefactorTarget? = nil) throws -> String
    {
        let rawLines = source.components(separatedBy: .newlines)
        var resultLines: [String] = []

        var inMatchingPara = false
        var insideParagraph = false

        let headerRegex = try NSRegularExpression(
            pattern:
                "^([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)\\s*:\\s*([a-zA-Z0-9_\\-\\u4e00-\\u9fa5]+)(@[^{]*)?\\s*\\{",
            options: []
        )
        let gridRegex = try NSRegularExpression(pattern: "^<(\\d+)\\*>", options: [])

        for rawLine in rawLines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let nsTrimmed = trimmed as NSString

            let match = headerRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let m = match {
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
                inMatchingPara = false
                resultLines.append(rawLine)
                continue
            }

            if !insideParagraph || !inMatchingPara {
                resultLines.append(rawLine)
                continue
            }

            let gMatch = gridRegex.firstMatch(
                in: trimmed, options: [], range: NSRange(location: 0, length: nsTrimmed.length))
            if let gm = gMatch {
                let lenStr = nsTrimmed.substring(with: gm.range(at: 1))
                let curLen = Int(lenStr) ?? 4
                if curLen % 2 != 0 {
                    throw TmdRefactorError.invalidOperation("Cannot halve odd grid <\(curLen)*>")
                }
                let newLen = curLen / 2
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                resultLines.append("\(indent)<\(newLen)*>")
                continue
            }

            if trimmed.contains("|")
                || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "01234567[]-")) != nil
            {
                let indent = String(rawLine.prefix(while: { $0 == " " || $0 == "\t" }))
                let transformed = try halveGridInLine(trimmed)
                resultLines.append(indent + transformed)
            } else {
                resultLines.append(rawLine)
            }
        }

        return format(resultLines.joined(separator: "\n"))
    }

    static func parseTupletToken(_ tok: String) -> (inner: String, dashes: String)? {
        guard tok.hasPrefix("(") && tok.contains(")") else { return nil }

        // Match `(inner) % (dashes)` or `(inner)%(dashes)`
        let patternWithLen = "^\\(([^)]+)\\)\\s*%\\s*\\(([-]+)\\)$"
        if let regex = try? NSRegularExpression(pattern: patternWithLen, options: []) {
            let nsTok = tok as NSString
            if let m = regex.firstMatch(
                in: tok, options: [], range: NSRange(location: 0, length: nsTok.length))
            {
                let inner = nsTok.substring(with: m.range(at: 1)).trimmingCharacters(
                    in: .whitespaces)
                let dashes = nsTok.substring(with: m.range(at: 2))
                return (inner: inner, dashes: dashes)
            }
        }

        // Match standalone `(inner)` without `%`
        let patternWithoutLen = "^\\(([^)]+)\\)$"
        if let regex = try? NSRegularExpression(pattern: patternWithoutLen, options: []) {
            let nsTok = tok as NSString
            if let m = regex.firstMatch(
                in: tok, options: [], range: NSRange(location: 0, length: nsTok.length))
            {
                let inner = nsTok.substring(with: m.range(at: 1)).trimmingCharacters(
                    in: .whitespaces)
                return (inner: inner, dashes: "-")
            }
        }

        return nil
    }

    static func doubleGridInLine(_ line: String) -> String {
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

            if let tuplet = parseTupletToken(tok) {
                let doubledDashes = tuplet.dashes + tuplet.dashes
                outTokens.append("(\(tuplet.inner))%(\(doubledDashes))")
                continue
            }

            // Regular unit: append a tie '-'
            outTokens.append(tok)
            outTokens.append("-")
        }

        return outTokens.joined(separator: " ") + commentSuffix
    }

    static func halveGridInLine(_ line: String) throws -> String {
        var working = line
        var commentSuffix = ""
        if let commentStart = working.range(of: "/*") {
            commentSuffix = " " + String(working[commentStart.lowerBound...])
            working = String(working[..<commentStart.lowerBound]).trimmingCharacters(
                in: .whitespaces)
        }

        let tokens = measureUnits(in: working)
        var outTokens: [String] = []
        var currentMeasure: [String] = []

        func processMeasure(_ measureTokens: [String]) throws {
            var i = 0
            while i < measureTokens.count {
                let u1 = measureTokens[i]
                if let tuplet = parseTupletToken(u1) {
                    if tuplet.dashes.count % 2 != 0 {
                        throw TmdRefactorError.invalidOperation(
                            "Cannot halve tuplet with odd length: '\(u1)' in | \(measureTokens.joined(separator: " ")) |"
                        )
                    }
                    let halfLen = tuplet.dashes.count / 2
                    let halvedDashes = String(repeating: "-", count: halfLen)
                    outTokens.append("(\(tuplet.inner))%(\(halvedDashes))")
                    i += 1
                    continue
                }

                if i + 1 >= measureTokens.count {
                    throw TmdRefactorError.invalidOperation(
                        "Cannot halve measure with odd number of units: | \(measureTokens.joined(separator: " ")) |"
                    )
                }
                let u2 = measureTokens[i + 1]
                if u2 != "-" {
                    throw TmdRefactorError.invalidOperation(
                        "Cannot halve grid: unit '\(u1) \(u2)' does not sustain with a tie '-'"
                    )
                }
                outTokens.append(u1)
                i += 2
            }
        }

        for tok in tokens {
            if tok == "|" {
                if !currentMeasure.isEmpty {
                    try processMeasure(currentMeasure)
                    currentMeasure = []
                }
                outTokens.append("|")
            } else {
                currentMeasure.append(tok)
            }
        }

        if !currentMeasure.isEmpty {
            try processMeasure(currentMeasure)
        }

        return outTokens.joined(separator: " ") + commentSuffix
    }

    /// Groups the canonical Lexer tokens into the measure units consumed by refactors.
    ///
    /// The Lexer remains the only source of token boundaries. This layer only combines
    /// adjacent syntax that is one refactor unit, such as a note followed immediately by
    /// ties or a complete tuplet expression.
    static func measureUnits(in line: String) -> [String] {
        let lexed = Lexer(string: line).tokenizeWithRanges()
            .filter { $0.token != .eof }
        var units: [String] = []
        var index = 0

        while index < lexed.count {
            let current = lexed[index]

            if current.token == .pipe {
                units.append(current.text)
                index += 1
                continue
            }

            if current.token == .openParen,
                let innerEnd = lexed[index...].firstIndex(where: { $0.token == .closeParen })
            {
                let inner = lexed[(index + 1)..<innerEnd].map(\.text).joined(separator: " ")
                var end = innerEnd + 1
                var dashes = ""

                if end < lexed.count, lexed[end].token == .percentOpenParen,
                    let dashEnd = lexed[(end + 1)...].firstIndex(where: { $0.token == .closeParen })
                {
                    dashes = lexed[(end + 1)..<dashEnd]
                        .filter { $0.token == .tie }
                        .map { _ in "-" }
                        .joined()
                    end = dashEnd + 1
                }

                if !dashes.isEmpty {
                    units.append("(\(inner))%(\(dashes))")
                } else {
                    units.append("(\(inner))")
                }
                index = end
                continue
            }

            var unit = current.text
            var end = index + 1
            while end < lexed.count,
                lexed[end].token == .tie,
                lexed[end - 1].range.endOffset == lexed[end].range.start.offset
            {
                unit += lexed[end].text
                end += 1
            }
            units.append(unit)
            index = end
        }

        return units
    }

    static func containsTransposableUnit(in line: String) -> Bool {
        guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("<") else {
            return false
        }
        return Lexer(string: line).tokenize().contains(where: \.isTransposableUnit)
    }

    // MARK: - Private Formatting Helpers


    /// Optimizes and compresses grid resolution repeatedly until minimal noteLength is reached.
    public static func optimizeGrid(source: String, target: TmdRefactorTarget? = nil) -> String {
        if target?.section != nil || target?.instrument != nil {
            var current = source
            while true {
                do {
                    let next = try halveGrid(source: current, target: target)
                    if next == current { break }
                    current = next
                } catch {
                    break
                }
            }
            return current
        }

        // Optimize each paragraph independently so one indivisible track does not block other tracks
        var current = source
        if let sheet = try? TmdParser.parseThrowing(string: current) {
            for p in sheet.entries {
                var paraCurrent = current
                let pTarget = TmdRefactorTarget(section: p.name, instrument: p.assignment)
                while true {
                    do {
                        let next = try halveGrid(source: paraCurrent, target: pTarget)
                        if next == paraCurrent { break }
                        paraCurrent = next
                    } catch {
                        break
                    }
                }
                current = paraCurrent
            }
        }
        return current
    }
}
