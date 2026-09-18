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

            // Paragraph header: identifier:identifier@...{
            if case .identifier(let pName) = tok.token,
               pos + 1 < tokensWithRanges.count, tokensWithRanges[pos + 1].token == .colon {
                let paraStartLine = tok.range.start.line
                _ = advance() // pName
                _ = advance() // :

                var instName = ""
                if let instTok = advance(), case .identifier(let iName) = instTok.token {
                    instName = iName
                }

                // Extract start offset from @|start| if present
                var startOffset = 0
                while pos < tokensWithRanges.count && current()?.token != .openBrace {
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
                        }
                        break
                    }
                    _ = advance()
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

                while pos < tokensWithRanges.count && current()?.token != .closeBrace {
                    guard let item = current() else { break }

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
                    case .number(let n):
                        _ = advance()
                        paragraphQuarterNotes += unitQuarterNotes
                        if insideBar {
                            currentMeasureUnits += 1
                            currentMeasureSnippet.append(String(n))
                        }
                    default:
                        _ = advance()
                    }
                }

                if current()?.token == .closeBrace {
                    _ = advance() // }
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
            } else {
                _ = advance()
            }
        }

        // Section length consistency check
        // Group paragraphs by paragraphName (section name)
        var paragraphsBySection: [String: [ParagraphSpanInfo]] = [:]
        for p in paragraphInfos {
            paragraphsBySection[p.paragraphName, default: []].append(p)
        }

        for (sectionName, list) in paragraphsBySection {
            guard list.count > 1 else { continue }
            // Determine baseline: find the longest track by endMeasure (and endQuarterNotes)
            guard let maxTrack = list.max(by: {
                if $0.endMeasure != $1.endMeasure {
                    return $0.endMeasure < $1.endMeasure
                }
                return $0.endQuarterNotes < $1.endQuarterNotes
            }) else { continue }

            let expectedMeasures = maxTrack.endMeasure
            let expectedBeats = maxTrack.endQuarterNotes

            for track in list {
                // If the track ends at fewer positive measures than expected, report issue
                if track.endMeasure < expectedMeasures {
                    let diffBeats = track.endQuarterNotes - expectedBeats
                    let diffBeatsStr = diffBeats > 0 ? "+\(String(format: "%.1f", diffBeats))" : String(format: "%.1f", diffBeats)
                    let expectedBeatsStr = String(format: "%.1f", expectedBeats)
                    let trackBeatsStr = String(format: "%.1f", track.endQuarterNotes)

                    let snippet = "\(expectedBeatsStr) beats based on \(maxTrack.instrument); found \(trackBeatsStr) beats, \(diffBeatsStr) beats"
                    issues.append(TMDMeasureIssue(
                        paragraphName: sectionName,
                        instrument: track.instrument,
                        lineNumber: track.startLine,
                        measureIndex: 0,
                        expectedUnits: expectedMeasures,
                        actualUnits: track.endMeasure,
                        noteLength: 4,
                        beat: beat,
                        snippet: snippet
                    ))
                } else if track.endMeasure == expectedMeasures && track.startOffset >= 0 && maxTrack.startOffset >= 0 && track.endQuarterNotes + 1e-4 < expectedBeats {
                    // Both are non-pickup tracks with same nominal measure count, but beat durations differ
                    let diffBeats = track.endQuarterNotes - expectedBeats
                    let diffBeatsStr = diffBeats > 0 ? "+\(String(format: "%.1f", diffBeats))" : String(format: "%.1f", diffBeats)
                    let expectedBeatsStr = String(format: "%.1f", expectedBeats)
                    let trackBeatsStr = String(format: "%.1f", track.endQuarterNotes)

                    let snippet = "\(expectedBeatsStr) beats based on \(maxTrack.instrument); found \(trackBeatsStr) beats, \(diffBeatsStr) beats"
                    issues.append(TMDMeasureIssue(
                        paragraphName: sectionName,
                        instrument: track.instrument,
                        lineNumber: track.startLine,
                        measureIndex: 0,
                        expectedUnits: expectedMeasures,
                        actualUnits: track.endMeasure,
                        noteLength: 4,
                        beat: beat,
                        snippet: snippet
                    ))
                }
            }
        }

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
