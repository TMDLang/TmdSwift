import Foundation
import TmdSwift

public struct TmdLSPCompletionEngine {
    public static let standardInstruments: [String] = [
        // Keyboard & Piano
        "Piano", "AcousticGrandPiano", "BrightAcousticPiano", "ElectricGrandPiano",
        "HonkyTonkPiano", "ElectricPiano", "Harpsichord", "Clavinet",
        // Strings
        "Violin", "Viola", "Cello", "Contrabass", "Strings", "StringEnsemble", "PizzicatoStrings",
        "OrchestralHarp",
        // Guitars & Bass
        "AcousticGuitar", "NylonGuitar", "SteelGuitar", "CleanGuitar", "OverdrivenGuitar",
        "DistortionGuitar",
        "Bass", "AcousticBass", "ElectricBass", "ElectricBassFinger", "ElectricBassPick",
        "SlapBass", "SynthBass",
        // Brass & Woodwinds
        "Trumpet", "Trombone", "Tuba", "MutedTrumpet", "FrenchHorn", "BrassSection",
        "SopranoSax", "AltoSax", "TenorSax", "BaritoneSax", "Oboe", "EnglishHorn", "Bassoon",
        "Clarinet", "Piccolo", "Flute", "PanFlute",
        // Voices
        "Vocal", "Choir", "VoiceOohs", "SynthVoice",
        // Percussion
        "Drums", "Percussion", "Timpani", "SteelDrums", "TaikoDrum", "MelodicTom",
    ]

    public static let macroSnippets: [(label: String, insertText: String, detail: String)] = [
        (
            "canon", "(canon ${1:Theme} (${2:Violin1 Violin2}) ${3:2})",
            "Polyphonic Canon: (canon <theme> (<instruments...>) <offset_bars>)"
        ),
        (
            "loop", "(loop ${1:Theme} ${2:Cello} ${3:4})",
            "Sequential Loop: (loop <theme> <assignment> <times>) or (loop <section> <times>)"
        ),
        (
            "layer", "(layer\n\t${1:expr1}\n\t${2:expr2})",
            "Parallel Concurrency: (layer <expr1> <expr2> ...)"
        ),
        ("seq", "(seq\n\t${1:expr1}\n\t${2:expr2})", "Sequential Chain: (seq <expr1> <expr2> ...)"),
        ("reverse", "(reverse ${1:Theme})", "Retrograde Inversion: (reverse <theme|expr>)"),
        ("flip", "(flip ${1:Theme})", "Melodic Inversion: (flip <theme|expr> [axis])"),
        (
            "transpose", "(transpose ${1:Theme} ${2:7})",
            "Semitone Transposition: (transpose <theme|expr> <semitones>)"
        ),
        (
            "vary", "(vary ${1:Theme} ${2:reverse} ${3:12})",
            "Chained Transformations: (vary <theme> <trans1> ...)"
        ),
        ("minor", "(minor ${1:Theme})", "Parallel Minor Modal Transform: (minor <theme>)"),
        ("major", "(major ${1:Theme})", "Parallel Major Modal Transform: (major <theme>)"),
        ("play", "(play ${1:Theme} ${2:Violin})", "Track Binding: (play <theme> <assignment>)"),
    ]

    public static let sectionDirectiveCompletions: [TmdLSPCompletionItem] = [
        TmdLSPCompletionItem(
            label: "!= 120", kind: .snippet, detail: "Absolute Tempo (BPM)",
            insertText: "!= ${1:120}}", insertTextFormat: 2),
        TmdLSPCompletionItem(
            label: "!+ 10", kind: .snippet, detail: "Relative Tempo Change (+BPM)",
            insertText: "!+ ${1:10}}", insertTextFormat: 2),
        TmdLSPCompletionItem(
            label: "?= C", kind: .snippet, detail: "Movable-do Base", insertText: "?= ${1:C}}",
            insertTextFormat: 2),
        TmdLSPCompletionItem(
            label: "?+ 2", kind: .snippet, detail: "Relative Movable-do Transposition (+semitones)",
            insertText: "?+ ${1:2}}", insertTextFormat: 2),
        TmdLSPCompletionItem(
            label: "?- 2", kind: .snippet, detail: "Relative Movable-do Transposition (-semitones)",
            insertText: "?- ${1:2}}", insertTextFormat: 2),
        TmdLSPCompletionItem(
            label: "key= Bm", kind: .snippet, detail: "Explicit Tonality (B minor)",
            insertText: "key= ${1:Bm}}", insertTextFormat: 2),
        TmdLSPCompletionItem(
            label: "ppp", kind: .value, detail: "Dynamics (ppp)", insertText: "ppp}"),
        TmdLSPCompletionItem(label: "pp", kind: .value, detail: "Dynamics (pp)", insertText: "pp}"),
        TmdLSPCompletionItem(label: "p", kind: .value, detail: "Dynamics (p)", insertText: "p}"),
        TmdLSPCompletionItem(label: "mp", kind: .value, detail: "Dynamics (mp)", insertText: "mp}"),
        TmdLSPCompletionItem(label: "mf", kind: .value, detail: "Dynamics (mf)", insertText: "mf}"),
        TmdLSPCompletionItem(label: "f", kind: .value, detail: "Dynamics (f)", insertText: "f}"),
        TmdLSPCompletionItem(label: "ff", kind: .value, detail: "Dynamics (ff)", insertText: "ff}"),
        TmdLSPCompletionItem(
            label: "fff", kind: .value, detail: "Dynamics (fff)", insertText: "fff}"),
        TmdLSPCompletionItem(
            label: "<4/4>", kind: .snippet, detail: "Time Signature Change",
            insertText: "<${1:4}/${2:4}>}", insertTextFormat: 2),
    ]

    public static func complete(source: String, position: TmdLSPPosition) -> [TmdLSPCompletionItem]
    {
        let lines = source.components(separatedBy: "\n")
        guard position.line < lines.count else { return [] }
        let currentLine = lines[position.line]
        let utf16 = currentLine.utf16
        let clampedOffset = min(max(0, position.character), utf16.count)
        let utf16SplitIndex = utf16.index(utf16.startIndex, offsetBy: clampedOffset)
        let splitIndex =
            utf16SplitIndex.samePosition(in: currentLine)
            ?? currentLine.unicodeScalars.index(before: utf16SplitIndex).samePosition(
                in: currentLine)
            ?? currentLine.startIndex
        let prefix = String(currentLine[..<splitIndex])

        // 1. Check for S-Expression macro completion: inside "-> (" or "(" or "(<word>"
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        let isInsideMacro: Bool = {
            if trimmedPrefix.hasSuffix("-> (") || trimmedPrefix.hasSuffix("(") {
                return true
            }
            if let lastParenIndex = prefix.lastIndex(of: "(") {
                let afterParen = prefix[prefix.index(after: lastParenIndex)...]
                // If there is no closing parenthesis after the opening paren, and only letters/digits typed so far
                if !afterParen.contains(")") && !afterParen.contains(" ") && !afterParen.isEmpty {
                    return true
                }
            }
            return false
        }()

        let remainder = String(currentLine[splitIndex...])
        let nextChar = remainder.first

        if prefix.range(of: #":\s*[A-Za-z][A-Za-z0-9_-]*\[$"#, options: .regularExpression) != nil {
            return [
                TmdLSPCompletionItem(
                    label: "pitchMode=fixed",
                    kind: .value,
                    detail: "Fixed Pitch Entry Attribute",
                    documentation:
                        "Keep this entry at its written pitch during playback transposition.",
                    insertText: "pitchMode=fixed]"
                )
            ]
        }

        if isInsideMacro {
            return macroSnippets.map {
                let rawInsert = $0.insertText
                var cleanInsert =
                    rawInsert.hasPrefix("(") ? String(rawInsert.dropFirst()) : rawInsert
                if nextChar == ")" && cleanInsert.hasSuffix(")") {
                    cleanInsert.removeLast()
                }
                return TmdLSPCompletionItem(
                    label: $0.label,
                    kind: .snippet,
                    detail: $0.detail,
                    documentation: $0.detail,
                    insertText: cleanInsert,
                    insertTextFormat: 2  // Snippet
                )
            }
        }

        // 2. Check for playback section completion: after "-> "
        if prefix.trimmingCharacters(in: .whitespaces).hasSuffix("->")
            || prefix.trimmingCharacters(in: .whitespaces).contains("->")
        {
            let sectionNames = TmdOutlineGenerator.extractSectionNames(source: source)
            return sectionNames.map {
                TmdLSPCompletionItem(
                    label: $0,
                    kind: .field,
                    detail: "TMD Section: \($0)",
                    documentation: "Playback section or abstract theme"
                )
            }
        }

        // 3. Check for assignment completion: after ":"
        if prefix.trimmingCharacters(in: .whitespaces).hasSuffix(":") {
            return standardInstruments.map {
                TmdLSPCompletionItem(
                    label: $0,
                    kind: .keyword,
                    detail: "General MIDI Assignment: \($0)",
                    documentation: "Standard assignment sound"
                )
            }
        }

        // 4. Check for Chord completion: after "[" (including typed prefix like "[6" or "[F")
        if let lastBracketIndex = prefix.lastIndex(of: "[") {
            let afterBracket = String(prefix[prefix.index(after: lastBracketIndex)...])
            if !afterBracket.contains("]") && afterBracket.count <= 12 {
                let typed = afterBracket.trimmingCharacters(in: .whitespaces)
                let appendClosingBracket = nextChar != "]"
                var items: [TmdLSPCompletionItem] = []

                // A. Scale Degree Chords (Key-agnostic, pop progression friendly: 1, 4, 5, 3m, 6m, etc.)
                for chord in scaleDegreeChords {
                    if typed.isEmpty || chord.hasPrefix(typed) {
                        items.append(
                            TmdLSPCompletionItem(
                                label: chord,
                                kind: .value,
                                detail: "Scale Degree Chord: [\(chord)]",
                                documentation:
                                    "Key-independent scale degree notation for pop progression and transposition.",
                                insertText: appendClosingBracket ? "\(chord)]" : chord
                            ))
                    }
                }

                // B. Diatonic Letter Chords for current key
                let sheet = TmdParser.parse(string: source)
                let keyStr = sheet?.keySignature.description ?? "C"
                let diatonicChords = getDiatonicChords(for: keyStr)
                for chord in diatonicChords {
                    if typed.isEmpty || chord.hasPrefix(typed) {
                        items.append(
                            TmdLSPCompletionItem(
                                label: chord,
                                kind: .value,
                                detail: "Diatonic Chord in \(keyStr)",
                                documentation: "Absolute diatonic chord in key of \(keyStr).",
                                insertText: appendClosingBracket ? "\(chord)]" : chord
                            ))
                    }
                }

                return items
            }
        }

        // 5. Section directives: after an open brace, filtered by the typed prefix.
        if let lastBraceIndex = prefix.lastIndex(of: "{") {
            let afterBrace = String(prefix[prefix.index(after: lastBraceIndex)...])
            if !afterBrace.contains("}") && afterBrace.count <= 16 {
                let typed = afterBrace.trimmingCharacters(in: .whitespaces).lowercased()
                let matches = sectionDirectiveCompletions.filter {
                    typed.isEmpty || $0.label.lowercased().hasPrefix(typed)
                }
                guard nextChar == "}" else { return matches }

                // VS Code usually inserts a matching `}` when the user types
                // `{`. Reuse that brace instead of inserting a second one.
                return matches.map { item in
                    guard let insertText = item.insertText, insertText.hasSuffix("}") else {
                        return item
                    }
                    return TmdLSPCompletionItem(
                        label: item.label,
                        kind: item.kind,
                        detail: item.detail,
                        documentation: item.documentation,
                        insertText: String(insertText.dropLast()),
                        insertTextFormat: item.insertTextFormat
                    )
                }
            }
        }

        return []
    }

    private static let scaleDegreeChords: [String] = [
        // Diatonic triads
        "1", "2m", "3m", "4", "5", "6m", "7dim",
        // Secondary dominants & major variations
        "2", "3", "6",
        // Modal mixture & common alterations
        "4m", "b7", "7,", "2m7-5",
        // Seventh chords
        "1maj7", "2m7", "3m7", "4maj7", "57", "6m7", "7m7-5",
        // Suspended & extended chords
        "1sus4", "5sus4", "1add9", "4add9", "5add9",
        // Common slash & inversion chords
        "1/3", "1/5", "4/5", "5/4", "5/7", "6m/5",
    ]

    private static func getDiatonicChords(for keyStr: String) -> [String] {
        let normalized = keyStr.trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "C":
            return [
                "C", "Dm", "Em", "F", "G", "Am", "Bdim",
                "Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Gsus4",
                "C/E", "G/B", "F/A", "F/G", "C/G",
            ]
        case "G":
            return [
                "G", "Am", "Bm", "C", "D", "Em", "F#dim",
                "Gmaj7", "Am7", "Bm7", "Cmaj7", "D7", "Em7", "Dsus4",
                "G/B", "D/F#", "C/E", "C/D", "G/D",
            ]
        case "D":
            return [
                "D", "Em", "F#m", "G", "A", "Bm", "C#dim",
                "Dmaj7", "Em7", "F#m7", "Gmaj7", "A7", "Bm7", "Asus4",
                "D/F#", "A/C#", "G/B", "G/A", "D/A",
            ]
        case "A":
            return [
                "A", "Bm", "C#m", "D", "E", "F#m", "G#dim",
                "Amaj7", "Bm7", "C#m7", "Dmaj7", "E7", "F#m7", "Esus4",
                "A/C#", "E/G#", "D/F#", "D/E", "A/E",
            ]
        case "E":
            return [
                "E", "F#m", "G#m", "A", "B", "C#m", "D#dim",
                "Emaj7", "F#m7", "G#m7", "Amaj7", "B7", "C#m7", "Bsus4",
                "E/G#", "B/D#", "A/C#", "A/B", "E/B",
            ]
        case "B":
            return [
                "B", "C#m", "D#m", "E", "F#", "G#m", "A#dim",
                "Bmaj7", "C#m7", "D#m7", "Emaj7", "F#7", "G#m7", "F#sus4",
                "B/D#", "F#/A#", "E/G#", "E/F#", "B/F#",
            ]
        case "F#", "F'":
            return [
                "F#", "G#m", "A#m", "B", "C#", "D#m", "E#dim",
                "F#maj7", "G#m7", "A#m7", "Bmaj7", "C#7", "D#m7", "C#sus4",
                "F#/A#", "C#/E#", "B/D#", "B/C#", "F#/C#",
            ]
        case "F":
            return [
                "F", "Gm", "Am", "Bb", "C", "Dm", "Edim",
                "Fmaj7", "Gm7", "Am7", "Bbmaj7", "C7", "Dm7", "Csus4",
                "F/A", "C/E", "Bb/D", "Bb/C", "F/C",
            ]
        case "Bb", "B,":
            return [
                "Bb", "Cm", "Dm", "Eb", "F", "Gm", "Adim",
                "Bbmaj7", "Cm7", "Dm7", "Ebmaj7", "F7", "Gm7", "Fsus4",
                "Bb/D", "F/A", "Eb/G", "Eb/F", "Bb/F",
            ]
        case "Eb", "E,":
            return [
                "Eb", "Fm", "Gm", "Ab", "Bb", "Cm", "Ddim",
                "Ebmaj7", "Fm7", "Gm7", "Abmaj7", "Bb7", "Cm7", "Bbsus4",
                "Eb/G", "Bb/D", "Ab/C", "Ab/Bb", "Eb/Bb",
            ]
        case "Ab", "A,":
            return [
                "Ab", "Bbm", "Cm", "Db", "Eb", "Fm", "Gdim",
                "Abmaj7", "Bbm7", "Cm7", "Dbmaj7", "Eb7", "Fm7", "Ebsus4",
                "Ab/C", "Eb/G", "Db/F", "Db/Eb", "Ab/Eb",
            ]
        case "Db", "D,":
            return [
                "Db", "Ebm", "Fm", "Gb", "Ab", "Bbm", "Cdim",
                "Dbmaj7", "Ebm7", "Fm7", "Gbmaj7", "Ab7", "Bbm7", "Absus4",
                "Db/F", "Ab/C", "Gb/Bb", "Gb/Ab", "Db/Ab",
            ]
        case "Am":
            return [
                "Am", "Bdim", "C", "Dm", "Em", "F", "G", "E7",
                "Am7", "Dm7", "Em7", "Cmaj7", "Fmaj7", "G7", "Esus4",
                "Am/G", "C/E", "F/A", "Dm/F",
            ]
        case "Em":
            return [
                "Em", "F#dim", "G", "Am", "Bm", "C", "D", "B7",
                "Em7", "Am7", "Bm7", "Gmaj7", "Cmaj7", "D7", "Bsus4",
                "Em/D", "G/B", "C/E", "Am/C",
            ]
        case "Dm":
            return [
                "Dm", "Edim", "F", "Gm", "Am", "Bb", "C", "A7",
                "Dm7", "Gm7", "Am7", "Fmaj7", "Bbmaj7", "C7", "Asus4",
                "Dm/C", "F/A", "Bb/D", "Gm/Bb",
            ]
        default:
            if normalized.contains("m") {
                return ["Am", "Bdim", "C", "Dm", "Em", "F", "G", "E7", "Am7", "Dm7", "Cmaj7", "Fmaj7"]
            }
            return [
                "C", "Dm", "Em", "F", "G", "Am", "Bdim",
                "Cmaj7", "Dm7", "Em7", "Fmaj7", "G7", "Am7", "Gsus4",
                "C/E", "G/B", "F/A", "F/G", "C/G",
            ]
        }
    }
}

// MARK: - Diagnostic Engine

