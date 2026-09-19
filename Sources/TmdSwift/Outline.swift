import Foundation

/// Represents a source code position range for outline nodes (1-based line and column).
public struct TMDOutlineRange: Codable, Equatable, Sendable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int

    public init(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) {
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
    }

    public init(start: SourcePosition, end: SourcePosition) {
        self.startLine = start.line
        self.startColumn = start.column
        self.endLine = end.line
        self.endColumn = end.column
    }
}

/// Represents an outline symbol node conforming to standard DocumentSymbol hierarchies.
public struct TMDOutlineNode: Codable, Equatable, Sendable {
    public let name: String
    public let detail: String?
    public let kind: String // "file", "class", "namespace", "field", "method", "event", etc.
    public let range: TMDOutlineRange
    public let selectionRange: TMDOutlineRange
    public let children: [TMDOutlineNode]?

    public init(
        name: String,
        detail: String? = nil,
        kind: String,
        range: TMDOutlineRange,
        selectionRange: TMDOutlineRange? = nil,
        children: [TMDOutlineNode]? = nil
    ) {
        self.name = name
        self.detail = detail
        self.kind = kind
        self.range = range
        self.selectionRange = selectionRange ?? range
        self.children = children
    }
}

/// Generates an outline hierarchy from TMD source text.
public struct TMDOutlineGenerator {
    public static func generate(source: String) -> [TMDOutlineNode] {
        let lexer = Lexer(string: source)
        let tokens = lexer.tokenizeWithRanges()

        guard !tokens.isEmpty else { return [] }

        var result: [TMDOutlineNode] = []
        var pos = 0

        func current() -> LexedToken? {
            pos < tokens.count ? tokens[pos] : nil
        }

        func advance() -> LexedToken? {
            guard pos < tokens.count else { return nil }
            let tok = tokens[pos]
            pos += 1
            return tok
        }

        // 1. Scan Score header info
        var scoreName = ""
        var scoreSpeed: Double?
        var scoreKey: String?
        var scoreBeat: String?
        var scoreHeaderStart: SourcePosition?
        var scoreHeaderEnd: SourcePosition?

        struct TrackOccurrence {
            let sectionName: String
            let instrument: String
            let range: TMDOutlineRange
            let selectionRange: TMDOutlineRange
            let detail: String?
        }

        var trackOccurrences: [TrackOccurrence] = []

        struct OrderItem {
            let name: String
            let range: TMDOutlineRange
        }
        var orderItems: [OrderItem] = []
        var orderStartPos: SourcePosition?
        var orderEndPos: SourcePosition?
        var orderSnippet: [String] = []

        while pos < tokens.count {
            guard let tok = current() else { break }

            if tok.token == .scoreHeader {
                scoreHeaderStart = tok.range.start
                _ = advance()
                continue
            }

            if tok.token == .doubleAsterisk && scoreName.isEmpty {
                _ = advance()
                var parts: [String] = []
                while pos < tokens.count && current()?.token != .doubleAsterisk && current()?.token != .eof {
                    if let t = advance() {
                        parts.append(t.text)
                    }
                }
                if current()?.token == .doubleAsterisk {
                    let endTok = advance()
                    scoreHeaderEnd = endTok?.range.start
                }
                scoreName = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                continue
            }

            if tok.token == .speedPrefix {
                _ = advance()
                if let next = advance() {
                    if case .double(let d) = next.token { scoreSpeed = d }
                    else if case .number(let n) = next.token { scoreSpeed = Double(n) }
                    else if case .positiveNumber(let n) = next.token { scoreSpeed = Double(n) }
                }
                continue
            }

            if tok.token == .keySignaturePrefix {
                _ = advance()
                if let next = advance() {
                    scoreKey = next.text
                }
                continue
            }

            if tok.token == .openAngle {
                // Check if <c/n> beat
                if pos + 4 < tokens.count && tokens[pos + 2].token == .slash && tokens[pos + 4].token == .closeAngle {
                    let c = tokens[pos + 1].text
                    let n = tokens[pos + 3].text
                    scoreBeat = "\(c)/\(n)"
                    pos += 5
                    continue
                }
            }

            // Paragraph header: identifier:identifier@...{ ... }
            if case .identifier(let secName) = tok.token,
               pos + 1 < tokens.count, tokens[pos + 1].token == .colon {
                let paraStartTok = tok
                _ = advance() // secName
                _ = advance() // :

                var instName = "Track"
                var instTok = current()
                if let it = advance(), case .identifier(let iName) = it.token {
                    instName = iName
                    instTok = it
                }

                // Advance until {
                var startOffsetStr: String?
                while pos < tokens.count && current()?.token != .openBrace {
                    if current()?.token == .at {
                        _ = advance()
                        if current()?.token == .pipe {
                            _ = advance()
                            var offStr = ""
                            while pos < tokens.count && current()?.token != .pipe {
                                if let offTok = advance() {
                                    offStr += offTok.text
                                }
                            }
                            if current()?.token == .pipe { _ = advance() }
                            startOffsetStr = offStr
                        }
                    } else {
                        _ = advance()
                    }
                }

                var braceCount = 0
                var paraEndTok = paraStartTok
                if current()?.token == .openBrace {
                    _ = advance()
                    braceCount = 1

                    while pos < tokens.count && braceCount > 0 {
                        guard let bodyTok = advance() else { break }
                        paraEndTok = bodyTok

                        if bodyTok.token == .openBrace {
                            braceCount += 1
                        } else if bodyTok.token == .closeBrace {
                            braceCount -= 1
                            if braceCount == 0 { break }
                        }
                    }
                }

                let pStart = paraStartTok.range.start
                let pEnd = SourcePosition(
                    offset: paraEndTok.range.endOffset,
                    line: paraEndTok.range.start.line,
                    column: paraEndTok.range.start.column + paraEndTok.range.length
                )
                let range = TMDOutlineRange(start: pStart, end: pEnd)
                let selStart = instTok?.range.start ?? pStart
                let selEnd = SourcePosition(
                    offset: (instTok?.range.endOffset) ?? pEnd.offset,
                    line: instTok?.range.start.line ?? pEnd.line,
                    column: (instTok?.range.start.column ?? pEnd.column) + (instTok?.range.length ?? 0)
                )
                let selectionRange = TMDOutlineRange(start: selStart, end: selEnd)

                var detail: String?
                if let startOffsetStr = startOffsetStr, !startOffsetStr.isEmpty {
                    detail = "@|\(startOffsetStr)|"
                }

                trackOccurrences.append(TrackOccurrence(
                    sectionName: secName,
                    instrument: instName,
                    range: range,
                    selectionRange: selectionRange,
                    detail: detail
                ))
                continue
            }

            // Order directive: -> section ->#
            if tok.token == .arrow {
                if orderStartPos == nil {
                    orderStartPos = tok.range.start
                }
                orderSnippet.append("->")
                _ = advance()

                if let next = current() {
                    if next.token == .arrowEnd {
                        orderSnippet.append("#")
                        if let arrowEndTok = advance() {
                            orderEndPos = SourcePosition(
                                offset: arrowEndTok.range.endOffset,
                                line: arrowEndTok.range.start.line,
                                column: arrowEndTok.range.start.column + arrowEndTok.range.length
                            )
                        }
                    } else if case .identifier(let orderSec) = next.token {
                        orderSnippet.append(orderSec)
                        if let secTok = advance() {
                            let oRange = TMDOutlineRange(
                                start: secTok.range.start,
                                end: SourcePosition(
                                    offset: secTok.range.endOffset,
                                    line: secTok.range.start.line,
                                    column: secTok.range.start.column + secTok.range.length
                                )
                            )
                            orderItems.append(OrderItem(name: orderSec, range: oRange))
                            orderEndPos = oRange.endPosition(from: secTok)
                        }
                    } else if next.token == .relativeOrderPrefix || next.token == .absoluteOrderPrefix {
                        var bracketStr = next.token == .relativeOrderPrefix ? "{?" : "{?="
                        _ = advance()
                        while pos < tokens.count && current()?.token != .closeBrace && current()?.token != .eof {
                            if let piece = advance() {
                                bracketStr += piece.text
                            }
                        }
                        if current()?.token == .closeBrace {
                            bracketStr += "}"
                            if let braceTok = advance() {
                                orderEndPos = SourcePosition(
                                    offset: braceTok.range.endOffset,
                                    line: braceTok.range.start.line,
                                    column: braceTok.range.start.column + braceTok.range.length
                                )
                            }
                        }
                        orderSnippet.append(bracketStr)
                    } else {
                        orderSnippet.append(next.text)
                        _ = advance()
                    }
                }
                continue
            }

            if tok.token == .arrowEnd {
                if orderStartPos == nil {
                    orderStartPos = tok.range.start
                }
                orderSnippet.append("->#")
                if let arrowEndTok = advance() {
                    orderEndPos = SourcePosition(
                        offset: arrowEndTok.range.endOffset,
                        line: arrowEndTok.range.start.line,
                        column: arrowEndTok.range.start.column + arrowEndTok.range.length
                    )
                }
                continue
            }

            _ = advance()
        }

        // 1. Score Node
        let songName = scoreName.isEmpty ? "Untitled" : scoreName
        var scoreDetails: [String] = []
        if let s = scoreSpeed {
            scoreDetails.append("!= \(s.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(s)) : String(s))")
        }
        if let k = scoreKey {
            scoreDetails.append("?= \(k)")
        }
        if let b = scoreBeat {
            scoreDetails.append("<\(b)>")
        }
        let scoreDetailStr = scoreDetails.isEmpty ? nil : scoreDetails.joined(separator: ", ")

        let scoreStart = scoreHeaderStart ?? SourcePosition(offset: 0, line: 1, column: 1)
        let scoreEnd = scoreHeaderEnd ?? SourcePosition(offset: 0, line: 1, column: 1)
        let scoreRange = TMDOutlineRange(start: scoreStart, end: scoreEnd)

        result.append(TMDOutlineNode(
            name: "Score: \(songName)",
            detail: scoreDetailStr,
            kind: "class",
            range: scoreRange,
            selectionRange: scoreRange
        ))

        // 2. Sections Node
        // Group tracks by section name in original appearance order
        var sectionOrder: [String] = []
        var tracksBySection: [String: [TrackOccurrence]] = [:]
        for track in trackOccurrences {
            if tracksBySection[track.sectionName] == nil {
                sectionOrder.append(track.sectionName)
            }
            tracksBySection[track.sectionName, default: []].append(track)
        }

        var sectionNodes: [TMDOutlineNode] = []
        for secName in sectionOrder {
            guard let tracks = tracksBySection[secName], !tracks.isEmpty else { continue }
            let minLine = tracks.map(\.range.startLine).min() ?? 1
            let minCol = tracks.first?.range.startColumn ?? 1
            let maxLine = tracks.map(\.range.endLine).max() ?? 1
            let maxCol = tracks.last?.range.endColumn ?? 1
            let secRange = TMDOutlineRange(startLine: minLine, startColumn: minCol, endLine: maxLine, endColumn: maxCol)

            let trackNodes = tracks.map { track in
                TMDOutlineNode(
                    name: track.instrument,
                    detail: track.detail,
                    kind: "field",
                    range: track.range,
                    selectionRange: track.selectionRange
                )
            }

            sectionNodes.append(TMDOutlineNode(
                name: secName,
                detail: "\(trackNodes.count) track\(trackNodes.count == 1 ? "" : "s")",
                kind: "namespace",
                range: secRange,
                selectionRange: secRange,
                children: trackNodes
            ))
        }

        if !sectionNodes.isEmpty {
            let sRange = TMDOutlineRange(
                startLine: sectionNodes.first?.range.startLine ?? 1,
                startColumn: sectionNodes.first?.range.startColumn ?? 1,
                endLine: sectionNodes.last?.range.endLine ?? 1,
                endColumn: sectionNodes.last?.range.endColumn ?? 1
            )
            result.append(TMDOutlineNode(
                name: "Sections",
                detail: "\(sectionNodes.count) section\(sectionNodes.count == 1 ? "" : "s")",
                kind: "namespace",
                range: sRange,
                selectionRange: sRange,
                children: sectionNodes
            ))
        }

        // 3. Orders Node
        if !orderItems.isEmpty || orderStartPos != nil {
            let start = orderStartPos ?? SourcePosition(offset: 0, line: 1, column: 1)
            let end = orderEndPos ?? start
            let ordersRange = TMDOutlineRange(start: start, end: end)

            let orderChildNodes = orderItems.map { item in
                TMDOutlineNode(
                    name: item.name,
                    detail: nil,
                    kind: "method",
                    range: item.range,
                    selectionRange: item.range
                )
            }

            let fullSnippet = orderSnippet.joined(separator: " ")
            result.append(TMDOutlineNode(
                name: "Orders",
                detail: fullSnippet.isEmpty ? nil : fullSnippet,
                kind: "event",
                range: ordersRange,
                selectionRange: ordersRange,
                children: orderChildNodes
            ))
        }

        return result
    }
}

private extension TMDOutlineRange {
    func endPosition(from tok: LexedToken) -> SourcePosition {
        SourcePosition(
            offset: tok.range.endOffset,
            line: tok.range.start.line,
            column: tok.range.start.column + tok.range.length
        )
    }
}
