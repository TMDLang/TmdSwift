import Foundation

/// A monophonic note detected from a humming or singing performance.
public struct HummingNoteEvent: Equatable, Sendable {
    public let startTimeSeconds: Double
    public let durationSeconds: Double
    public let pitchMIDI: Double
    public let amplitude: Double

    public init(startTimeSeconds: Double, durationSeconds: Double, pitchMIDI: Double, amplitude: Double) {
        self.startTimeSeconds = startTimeSeconds
        self.durationSeconds = durationSeconds
        self.pitchMIDI = pitchMIDI
        self.amplitude = amplitude
    }
}

/// Configuration for converting detected note events into one TMD section.
public struct HummingQuantizationOptions: Equatable, Sendable {
    public let sectionName: String
    public let instrument: String
    public let bpm: Double
    public let grid: Int
    public let key: String
    public let beatsPerMeasure: Int
    public let snapToScale: Bool

    public init(
        sectionName: String = "hummed",
        instrument: String = "Vocal",
        bpm: Double,
        grid: Int = 8,
        key: String = "AUTO",
        beatsPerMeasure: Int = 4,
        snapToScale: Bool = false
    ) {
        self.sectionName = sectionName
        self.instrument = instrument
        self.bpm = bpm
        self.grid = grid
        self.key = key
        self.beatsPerMeasure = beatsPerMeasure
        self.snapToScale = snapToScale
    }
}

/// Deterministic conversion layer shared by humming UI and non-UI hosts.
public enum HummingQuantizer {
    private static let semitoneToJianpu = ["1", "1'", "2", "2'", "3", "4", "4'", "5", "5'", "6", "6'", "7"]
    private static let diatonicSemitones = [0, 0, 2, 2, 4, 5, 5, 7, 7, 9, 9, 11]
    private static let majorProfile = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let pitchClasses = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    /// Returns the most likely major tonic using duration- and amplitude-weighted chroma.
    public static func detectTonic(_ events: [HummingNoteEvent]) -> String {
        guard !events.isEmpty else { return "C" }
        var chroma = Array(repeating: 0.0, count: 12)
        for event in events where event.amplitude > 0.05 && event.durationSeconds > 0.05 {
            let pitch = Int(event.pitchMIDI.rounded())
            let semitone = ((pitch % 12) + 12) % 12
            chroma[semitone] += max(0.1, event.durationSeconds) * event.amplitude
        }

        let chromaMean = chroma.reduce(0, +) / 12.0
        let profileMean = majorProfile.reduce(0, +) / 12.0
        var bestKey = "C"
        var bestScore = -Double.infinity

        for root in 0..<12 {
            var numerator = 0.0
            var chromaDenominator = 0.0
            var profileDenominator = 0.0
            for index in 0..<12 {
                let chromaValue = chroma[(root + index) % 12] - chromaMean
                let profileValue = majorProfile[index] - profileMean
                numerator += chromaValue * profileValue
                chromaDenominator += chromaValue * chromaValue
                profileDenominator += profileValue * profileValue
            }
            let denominator = sqrt(chromaDenominator * profileDenominator)
            let score = denominator == 0 ? 0 : numerator / denominator
            if score > bestScore {
                bestScore = score
                bestKey = pitchClasses[root]
            }
        }
        return bestKey
    }

    /// Converts a MIDI pitch to TMD numbered notation relative to a major tonic.
    public static func jianpu(forMIDI pitchMIDI: Double, key: String = "C", snapToScale: Bool = false) -> String {
        let keySignature = KeySignature(string: key)
        let relativePitch = Int(pitchMIDI.rounded()) - 60 - keySignature.semitoneOffset
        let octave = Int(floor(Double(relativePitch) / 12.0))
        var semitone = ((relativePitch % 12) + 12) % 12
        if snapToScale {
            semitone = diatonicSemitones[semitone]
        }

        let base = semitoneToJianpu[semitone]
        let octaveMark: String
        if octave > 0 {
            octaveMark = String(repeating: "^", count: octave)
        } else if octave < 0 {
            octaveMark = String(repeating: "_", count: -octave)
        } else {
            octaveMark = ""
        }
        return base + octaveMark
    }

    /// Quantizes note events to the TMD source representation used by the TS web client.
    public static func quantize(_ events: [HummingNoteEvent], options: HummingQuantizationOptions) -> String {
        let bpm = max(20, options.bpm)
        let grid = max(1, options.grid)
        let beatsPerMeasure = max(1, options.beatsPerMeasure)
        let key = options.key == "AUTO" || options.key.isEmpty ? detectTonic(events) : options.key
        let slotDuration = (4.0 / Double(grid)) * (60.0 / bpm)

        guard !events.isEmpty else {
            return emptySection(name: options.sectionName, instrument: options.instrument, grid: grid)
        }

        let minimumDuration = max(0.1, slotDuration * 0.4)
        let validEvents = events
            .filter { $0.amplitude > 0.15 && $0.durationSeconds >= minimumDuration }
            .sorted { $0.startTimeSeconds < $1.startTimeSeconds }
        guard !validEvents.isEmpty else {
            return emptySection(name: options.sectionName, instrument: options.instrument, grid: grid)
        }

        let lastEvent = validEvents[validEvents.count - 1]
        let rawTotalSlots = Int(ceil((lastEvent.startTimeSeconds + lastEvent.durationSeconds) / slotDuration))
        let slotsPerMeasure = max(1, Int((Double(grid) / 4.0 * Double(beatsPerMeasure)).rounded()))
        let totalSlots = max(slotsPerMeasure, Int(ceil(Double(rawTotalSlots) / Double(slotsPerMeasure))) * slotsPerMeasure)
        var slots = Array<String?>(repeating: nil, count: totalSlots)

        for event in validEvents {
            let startSlot = max(0, Int((event.startTimeSeconds / slotDuration).rounded()))
            let durationSlots = max(1, Int((event.durationSeconds / slotDuration).rounded()))
            guard startSlot < totalSlots else { continue }
            slots[startSlot] = jianpu(forMIDI: event.pitchMIDI, key: key, snapToScale: options.snapToScale)
            if durationSlots > 1 {
                for index in 1..<durationSlots where startSlot + index < totalSlots {
                    if slots[startSlot + index] == nil {
                        slots[startSlot + index] = "-"
                    }
                }
            }
        }

        var measures: [String] = []
        for start in stride(from: 0, to: totalSlots, by: slotsPerMeasure) {
            let end = min(start + slotsPerMeasure, totalSlots)
            let tokens = (start..<end).map { slots[$0] ?? "0" }
            measures.append("    | \(tokens.joined(separator: " ")) |")
        }
        return "\(options.sectionName):\(options.instrument)@|0|{\n    <\(grid)*>\n\(measures.joined(separator: "\n"))\n}"
    }

    private static func emptySection(name: String, instrument: String, grid: Int) -> String {
        "\(name):\(instrument)@|0|{\n    <\(grid)*>\n    0\n}"
    }
}
