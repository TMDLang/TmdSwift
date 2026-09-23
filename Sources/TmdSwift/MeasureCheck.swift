import Foundation

/// Represents a detected measure duration issue within a TMD score.
public struct TMDMeasureIssue: Equatable, CustomStringConvertible, Sendable {
    public let paragraphName: String
    public let instrument: String
    public let lineNumber: Int
    public let measureIndex: Int
    public let expectedUnits: Int
    public let actualUnits: Int
    public let noteLength: Int
    public let beat: Beat
    public let snippet: String

    public var deltaUnits: Int {
        actualUnits - expectedUnits
    }

    public var description: String {
        if instrument == "Order" {
            if !paragraphName.isEmpty {
                return "Order (line \(lineNumber)): Undefined section '\(paragraphName)' in playback order (\(snippet))"
            } else {
                return "Order (line \(lineNumber)): \(snippet)"
            }
        }
        if snippet.hasPrefix("Unclosed paragraph") {
            return "\(paragraphName):\(instrument) (line \(lineNumber)): \(snippet)"
        }
        let diffStr = deltaUnits > 0 ? "+\(deltaUnits)" : "\(deltaUnits)"
        if measureIndex == 0 {
            // Section-level instrument length mismatch issue
            var desc = "\(paragraphName):\(instrument) (line \(lineNumber)): "
            desc += "Expected \(expectedUnits) measures (\(snippet)), found \(actualUnits) measures (\(diffStr) measures)"
            return desc
        } else {
            var desc = "\(paragraphName):\(instrument) (line \(lineNumber), measure \(measureIndex)): "
            desc += "Expected \(expectedUnits) units (\(beat.count)/\(beat.noteValue) at <\(noteLength)*>), found \(actualUnits) units (\(diffStr) units)"
            if !snippet.isEmpty {
                desc += "\n  --> | \(snippet) |"
            }
            return desc
        }
    }
}

/// Verifies whether measures bounded by bar lines `|` in a TMD score conform to the expected time signature and subdivision grid.
public struct TMDMeasureChecker {
    /// Checks a TMD source text string for measure length discrepancies.
    public static func check(source: String) -> [TMDMeasureIssue] {
        let lexer = Lexer(string: source)
        let tokensWithRanges = lexer.tokenizeWithRanges()

        // First, extract song-level default beat (<4/4>)
        var beat = Beat(count: 4, noteValue: 4)
        for i in 0..<tokensWithRanges.count {
            if tokensWithRanges[i].token == .openAngle {
                if i + 3 < tokensWithRanges.count,
                   tokensWithRanges[i + 2].token == .slash,
                   tokensWithRanges[i + 4].token == .closeAngle {
                    let c = intValueOfToken(tokensWithRanges[i + 1].token) ?? 4
                    let n = intValueOfToken(tokensWithRanges[i + 3].token) ?? 4
                    beat = Beat(count: c, noteValue: n)
                    break
                }
            }
        }

        var issues: [TMDMeasureIssue] = []
        var paragraphInfos: [ParagraphSpanInfo] = []
        var orderSections: [(name: String, line: Int)] = []
        var hasOrder = false
        var terminatedWithHash = false
        var lastOrderTokenLine = 1
        var pos = 0

        func current() -> LexedToken? {
            pos < tokensWithRanges.count ? tokensWithRanges[pos] : nil
        }

        func advance() -> LexedToken? {
            guard pos < tokensWithRanges.count else { return nil }
            let tok = tokensWithRanges[pos]
            pos += 1
            return tok
        }

        while pos < tokensWithRanges.count {
            guard let tok = current() else { break }

            // Score title block: ** Title **
            if tok.token == .doubleAsterisk {
                _ = advance()
                while pos < tokensWithRanges.count && current()?.token != .doubleAsterisk {
                    _ = advance()
                }
                if current()?.token == .doubleAsterisk {
                    _ = advance()
                }
                continue
            }

            // Paragraph header: identifier:identifier@...{
            if case .identifier(let pName) = tok.token,
               pos + 3 < tokensWithRanges.count,
               tokensWithRanges[pos + 1].token == .colon,
               case .identifier = tokensWithRanges[pos + 2].token,
               tokensWithRanges[pos + 3].token == .at {
                let paraStartLine = tok.range.start.line
                _ = advance() // pName
                _ = advance() // :

                var instName = ""
                if let instTok = advance(), case .identifier(let iName) = instTok.token {
                    instName = iName
                }

                // Extract start offset from @|start| if present
                var startOffset = 0
                if current()?.token == .at {
                    _ = advance()
                    if current()?.token == .pipe {
                        _ = advance()
                        var sign = 1
                        if current()?.token == .tie {
                            sign = -1
                            _ = advance()
                        }
                        if let numTok = current() {
                            if case .number(let n) = numTok.token {
                                startOffset = sign * n
                                _ = advance()
                            } else if case .positiveNumber(let n) = numTok.token {
                                startOffset = sign * n
                                _ = advance()
                            } else if case .note(let note) = numTok.token {
                                startOffset = sign * note.degree.rawValue
                                _ = advance()
                            }
                        }
                        if current()?.token == .pipe { _ = advance() }
                    } else if case .identifier = current()?.token {
                        // executionTime
                        _ = advance()
                    }
                }

                // Advance until `{`
                while pos < tokensWithRanges.count && current()?.token != .openBrace {
                    _ = advance()
                }
                guard current()?.token == .openBrace else { continue }
                _ = advance() // {

                // Parse inside paragraph
                var noteLength = 4
                var currentMeasureUnits = 0
                var currentMeasureSnippet: [String] = []
                var measureCount = 0
                var insideBar = false
                var measureStartLine = paraStartLine
                var paragraphQuarterNotes = 0.0

                func expectedUnitsForMeasure() -> Int {
                    // expected units = beat.count * (noteLength / beat.noteValue)
                    // If noteLength / beat.noteValue is fractional, calculate carefully
                    let numerator = beat.count * noteLength
                    return max(1, numerator / beat.noteValue)
                }

                var unclosedParagraph = false
                while pos < tokensWithRanges.count && current()?.token != .closeBrace {
                    guard let item = current() else { break }

                    // If we hit an order arrow (->) or arrowEnd (->#) or another paragraph header,
                    // the current paragraph was not properly closed with '}'. Break out to avoid swallowing orders!
                    var isNextParagraphHeader = false
                    if case .identifier = item.token, pos + 1 < tokensWithRanges.count && tokensWithRanges[pos + 1].token == .colon {
                        isNextParagraphHeader = true
                    }
                    if item.token == .arrow || item.token == .arrowEnd || isNextParagraphHeader {
                        unclosedParagraph = true
                        break
                    }

                    // Check for Section subdivision header: < noteLength * >
                    if item.token == .openAngle {
                        if pos + 2 < tokensWithRanges.count && tokensWithRanges[pos + 2].token == .asterisk {
                            _ = advance() // <
                            if let lenTok = advance(), let val = intValueOfToken(lenTok.token) {
                                noteLength = val
                            }
                            _ = advance() // *
                            if current()?.token == .closeAngle {
                                _ = advance() // >
                            }
                            continue
                        }
                    }

                    if item.token == .pipe {
                        let pipeLine = item.range.start.line
                        _ = advance() // |

                        if insideBar && currentMeasureUnits > 0 {
                            measureCount += 1
                            let expected = expectedUnitsForMeasure()
                            // Check if pickup measure at beginning (only when paragraph start offset is negative)
                            let isPickup = (startOffset < 0) && measureCount == 1 && currentMeasureUnits < expected && currentMeasureUnits > 0
                            if currentMeasureUnits != expected && !isPickup {
                                issues.append(TMDMeasureIssue(
                                    paragraphName: pName,
                                    instrument: instName,
                                    lineNumber: measureStartLine,
                                    measureIndex: measureCount,
                                    expectedUnits: expected,
                                    actualUnits: currentMeasureUnits,
                                    noteLength: noteLength,
                                    beat: beat,
                                    snippet: currentMeasureSnippet.joined(separator: " ")
                                ))
                            }
                            currentMeasureUnits = 0
                            currentMeasureSnippet = []
                            measureStartLine = pipeLine
                        } else {
                            insideBar = true
                            currentMeasureUnits = 0
                            currentMeasureSnippet = []
                            measureStartLine = pipeLine
                        }
                        continue
                    }

                    // Count unit duration
                    let unitQuarterNotes = 4.0 / Double(max(1, noteLength))

                    if item.token == .openParen {
                        // Tuplet / unit group: ( ... ) % ( -- )
                        _ = advance() // (
                        var innerUnits: [String] = []
                        while pos < tokensWithRanges.count && current()?.token != .closeParen {
                            if let inner = advance() {
                                innerUnits.append(inner.text)
                            }
                        }
                        if current()?.token == .closeParen { _ = advance() }

                        var length = 1
                        if current()?.token == .percentOpenParen {
                            _ = advance() // %(
                            var dashes = 0
                            while pos < tokensWithRanges.count && current()?.token == .tie {
                                dashes += 1
                                _ = advance()
                            }
                            if current()?.token == .closeParen { _ = advance() }
                            length = max(1, dashes)
                        }

                        paragraphQuarterNotes += Double(length) * unitQuarterNotes
                        if insideBar {
                            currentMeasureUnits += length
                            currentMeasureSnippet.append("(\(innerUnits.joined(separator: " ")))")
                        }
                        continue
                    }

                    // Check for standard units: note, chord, tie, percussion, rest, drum identifiers
                    switch item.token {
                    case .note, .chord, .tie, .percussion:
                        _ = advance()
                        paragraphQuarterNotes += unitQuarterNotes
                        if insideBar {
                            currentMeasureUnits += 1
                            currentMeasureSnippet.append(item.text)
                        }
                    case .identifier(let value) where !value.isEmpty && value.allSatisfy({ "XxTtSsDdBbOoCc".contains($0) }):
                        _ = advance()
                        paragraphQuarterNotes += unitQuarterNotes
                        if insideBar {
                            currentMeasureUnits += 1
                            currentMeasureSnippet.append(item.text)
                        }
                    case .number, .positiveNumber:
                        _ = advance()
                        let digitCount = max(1, item.text.filter { $0.isNumber }.count)
                        paragraphQuarterNotes += Double(digitCount) * unitQuarterNotes
                        if insideBar {
                            currentMeasureUnits += digitCount
                            currentMeasureSnippet.append(item.text)
                        }
                    default:
                        _ = advance()
                    }
                }

                if current()?.token == .closeBrace {
                    _ = advance() // }
                } else {
                    unclosedParagraph = true
                }

                if unclosedParagraph {
                    issues.append(TMDMeasureIssue(
                        paragraphName: pName,
                        instrument: instName,
                        lineNumber: paraStartLine,
                        measureIndex: 0,
                        expectedUnits: 0,
                        actualUnits: 0,
                        noteLength: noteLength,
                        beat: beat,
                        snippet: "Unclosed paragraph '{' for \(pName):\(instName)"
                    ))
                }

                // If measureCount was counted via bar lines, use measureCount.
                // Otherwise calculate measure count based on total quarter notes / measure duration.
                let nominalMeasureDur = Double(max(1, beat.count)) * 4.0 / Double(max(1, beat.noteValue))
                let calculatedMeasures = Int(round(paragraphQuarterNotes / nominalMeasureDur))
                let actualMeasures = measureCount > 0 ? measureCount : max(1, calculatedMeasures)

                // When startOffset < 0 (e.g. -1 for pickup measure), the positive measures spanned are (startOffset + actualMeasures)
                let endMeasure = startOffset < 0 ? max(0, startOffset + actualMeasures) : startOffset + actualMeasures
                let positiveQuarterNotes = startOffset < 0 ? max(0, paragraphQuarterNotes + Double(startOffset) * nominalMeasureDur) : Double(startOffset) * nominalMeasureDur + paragraphQuarterNotes

                let info = ParagraphSpanInfo(
                    paragraphName: pName,
                    instrument: instName,
                    startLine: paraStartLine,
                    startOffset: startOffset,
                    measures: actualMeasures,
                    endMeasure: endMeasure,
                    quarterNotes: paragraphQuarterNotes,
                    endQuarterNotes: positiveQuarterNotes
                )
                paragraphInfos.append(info)
            } else if tok.token == .arrow {
                let arrowLine = tok.range.start.line
                lastOrderTokenLine = arrowLine
                hasOrder = true
                _ = advance() // ->
                if let nextTok = current() {
                    lastOrderTokenLine = nextTok.range.start.line != 0 ? nextTok.range.start.line : arrowLine
                    if nextTok.token == .arrowEnd {
                        terminatedWithHash = true
                        _ = advance()
                    } else if case .identifier(let orderSecName) = nextTok.token {
                        if orderSecName == "#" {
                            terminatedWithHash = true
                        }
                        orderSections.append((name: orderSecName, line: lastOrderTokenLine))
                        _ = advance()
                    } else if nextTok.token == .openParen {
                        // S-expression macro: skip balanced parens
                        var parenDepth = 0
                        while pos < tokensWithRanges.count {
                            guard let pTok = current() else { break }
                            if pTok.token == .openParen {
                                parenDepth += 1
                            } else if pTok.token == .closeParen {
                                parenDepth -= 1
                                if parenDepth == 0 {
                                    _ = advance()
                                    break
                                }
                            }
                            _ = advance()
                        }
                    }
                }
            } else if tok.token == .arrowEnd {
                lastOrderTokenLine = tok.range.start.line
                hasOrder = true
                terminatedWithHash = true
                _ = advance()
            } else {
                _ = advance()
            }
        }

        // Check playback order existence and termination
        if !hasOrder {
            let lastLine = tokensWithRanges.last(where: { $0.token != .eof })?.range.start.line ?? 1
            issues.append(TMDMeasureIssue(
                paragraphName: "",
                instrument: "Order",
                lineNumber: lastLine,
                measureIndex: 0,
                expectedUnits: 0,
                actualUnits: 0,
                noteLength: 4,
                beat: beat,
                snippet: "Missing playback order"
            ))
        } else if !terminatedWithHash {
            issues.append(TMDMeasureIssue(
                paragraphName: "",
                instrument: "Order",
                lineNumber: lastOrderTokenLine,
                measureIndex: 0,
                expectedUnits: 0,
                actualUnits: 0,
                noteLength: 4,
                beat: beat,
                snippet: "Playback order must terminate with '#'"
            ))
        }

        // Check for undefined sections referenced in execution orders (-> section)
        let definedSectionNames = Set(paragraphInfos.map(\.paragraphName))
        for order in orderSections {
            if order.name == "#" {
                continue
            }
            if !definedSectionNames.contains(order.name) {
                issues.append(TMDMeasureIssue(
                    paragraphName: order.name,
                    instrument: "Order",
                    lineNumber: order.line,
                    measureIndex: 0,
                    expectedUnits: 0,
                    actualUnits: 0,
                    noteLength: 4,
                    beat: beat,
                    snippet: "-> \(order.name)"
                ))
            }
        }

        // Note: in TMD, tracks within the same section may enter and exit freely (staggered entrance,
        // early exit / solos / breakdowns). TMDPlaybackRenderer pads trailing silence up to durationOf(section),
        // so shorter tracks are considered natural implicit rests rather than errors.

        return issues
    }

    private struct ParagraphSpanInfo {
        let paragraphName: String
        let instrument: String
        let startLine: Int
        let startOffset: Int
        let measures: Int
        let endMeasure: Int
        let quarterNotes: Double
        let endQuarterNotes: Double
    }

    private static func intValueOfToken(_ token: Token) -> Int? {
        switch token {
        case .number(let n): return n
        case .positiveNumber(let n): return n
        case .note(let note): return note.degree.rawValue
        default: return nil
        }
    }
}
