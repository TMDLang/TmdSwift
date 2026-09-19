import Foundation
import TmdSwift
import TmdMIDI

/// Options for configuring VOCALOID format exports.
public struct VocaloidExportOptions: Sendable, Equatable {
    /// Name of singer to embed in the file (default: "Miku").
    public var singerName: String
    /// Pre-measure count in 4/4 bars (default: 4 measures = 7680 ticks at 480 PPQ).
    public var preMeasure: Int
    /// Default lyric to use if none is specified for a note.
    public var defaultLyric: String

    public init(
        singerName: String = "Miku",
        preMeasure: Int = 4,
        defaultLyric: String = "a"
    ) {
        self.singerName = singerName
        self.preMeasure = preMeasure
        self.defaultLyric = defaultLyric
    }
}

/// Exporter for VOCALOID2 `.vsq` format.
///
/// A `.vsq` file is a Standard MIDI File (SMF Format 1) containing text meta events (`0xFF 0x01`)
/// that concatenate into a Windows INI text document describing the vocal track and lyric events.
public struct TMDVSQGenerator: Sendable {
    public static let ticksPerQuarter: UInt16 = 480

    /// Generates VOCALOID2 `.vsq` binary data from a TMD `Sheet`.
    public static func generateVSQ(
        from sheet: Sheet,
        targetInstrument: String? = nil,
        options: VocaloidExportOptions = VocaloidExportOptions()
    ) -> Data {
        let selectedInstrument = resolveTargetInstrument(sheet: sheet, requested: targetInstrument)
        let timeline = TMDPlaybackRenderer.render(sheet: sheet, instrument: selectedInstrument)

        // Track 0: Conductor Track (Tempo & Time Signature)
        let tempo = sheet.speed > 0 ? sheet.speed : 120.0
        let conductorTrackData = TMDMIDIEncoder.encodeTrack(events: [
            MIDIEvent(tick: 0, message: .trackName(sheet.name.isEmpty ? "TMD VOCALOID Score" : sheet.name)),
            MIDIEvent(tick: 0, message: .tempo(tempo)),
            MIDIEvent(tick: 0, message: .timeSignature(sheet.beat))
        ])

        // Track 1: Vocal Track (MIDI Notes + INI Text chunks)
        let vsqTrackData = generateVsqTrack(
            timeline: timeline,
            instrumentName: selectedInstrument,
            options: options
        )

        return TMDMIDIEncoder.encodeFile(tracks: [conductorTrackData, vsqTrackData], ticksPerQuarter: ticksPerQuarter)
    }

    private static func resolveTargetInstrument(sheet: Sheet, requested: String?) -> String {
        sheet.resolveVocalInstrument(requested: requested)
    }

    private static func generateVsqTrack(
        timeline: PlaybackTimeline,
        instrumentName: String,
        options: VocaloidExportOptions
    ) -> Data {
        let preMeasureTicks = UInt32(options.preMeasure * 4 * Int(ticksPerQuarter))

        // Collect note items
        struct NoteItem {
            let tick: UInt32
            let dur: UInt32
            let pitch: UInt8
            let lyric: String
            let phoneme: String
        }

        var noteItems: [NoteItem] = []
        for event in timeline.events {
            guard case .note(let note) = event.content else { continue }
            let tick = preMeasureTicks + midiTick(event.position)
            let dur = max(1, midiTick(event.duration))
            let pitch = TMDMIDIGenerator.noteToMIDIPitch(note, keyOffset: event.state.keyOffset)
            guard (0...127).contains(pitch) else { continue }
            let lyric = options.defaultLyric
            let phoneme = VocaloidPhoneme.resolvePhoneme(for: lyric)
            noteItems.append(NoteItem(tick: tick, dur: dur, pitch: UInt8(pitch), lyric: lyric, phoneme: phoneme))
        }

        // Build INI content
        var ini = ""
        ini += "[Common]\n"
        ini += "Version=DSB301\n"
        ini += "Name=\(instrumentName)\n"
        ini += "Color=181,110,147\n"
        ini += "DynamicsMode=1\n"
        ini += "PlayMode=1\n\n"

        ini += "[Master]\n"
        ini += "PreMeasure=\(options.preMeasure)\n\n"

        ini += "[Mixer]\n"
        ini += "MasterFeder=0\n"
        ini += "MasterPanpot=0\n"
        ini += "MasterMute=0\n"
        ini += "OutputMode=0\n"
        ini += "Tracks=1\n"
        ini += "Feder0=0\n"
        ini += "Panpot0=0\n"
        ini += "Mute0=0\n"
        ini += "Solo0=0\n\n"

        // [EventList]
        ini += "[EventList]\n"
        ini += "0=ID#0000\n"
        for (i, note) in noteItems.enumerated() {
            let idString = String(format: "ID#%04d", i + 1)
            ini += "\(note.tick)=\(idString)\n"
        }
        ini += "[ID#0000]\n"
        ini += "Type=Singer\n"
        ini += "IconHandle=h#0000\n\n"

        for (i, note) in noteItems.enumerated() {
            let idString = String(format: "ID#%04d", i + 1)
            let handleString = String(format: "h#%04d", i + 1)
            ini += "[\(idString)]\n"
            ini += "Type=Anote\n"
            ini += "Length=\(note.dur)\n"
            ini += "Note#=\(note.pitch)\n"
            ini += "Dynamics=64\n"
            ini += "PMBendDepth=0\n"
            ini += "PMBendLength=0\n"
            ini += "PMbmd=0\n"
            ini += "DEMdecGainRate=50\n"
            ini += "DEMaccent=50\n"
            ini += "LyricHandle=\(handleString)\n\n"
        }

        // Handles
        ini += "[h#0000]\n"
        ini += "IconID=$07010001\n"
        ini += "IDS=\(options.singerName)\n"
        ini += "Original=0\n"
        ini += "Caption=\n"
        ini += "Length=1\n"
        ini += "Language=0\n"
        ini += "Program=0\n\n"

        for (i, note) in noteItems.enumerated() {
            let handleString = String(format: "h#%04d", i + 1)
            ini += "[\(handleString)]\n"
            ini += "L0=\"\(note.lyric)\",\"\(note.phoneme)\",0.000000,0.000000,0\n\n"
        }

        // Chunk INI string into 119-byte text events at tick 0
        var midiEvents: [MIDIEvent] = []
        midiEvents.append(MIDIEvent(tick: 0, message: .trackName("Voice1")))

        let iniBytes = Array(ini.utf8)
        let chunkSize = 119
        var offset = 0
        while offset < iniBytes.count {
            let end = min(offset + chunkSize, iniBytes.count)
            let chunkData = Data(iniBytes[offset..<end])
            if let chunkStr = String(data: chunkData, encoding: .isoLatin1) ?? String(data: chunkData, encoding: .utf8) {
                midiEvents.append(MIDIEvent(tick: 0, message: .text(chunkStr)))
            }
            offset += chunkSize
        }

        // Add standard MIDI Note On / Note Off events
        for note in noteItems {
            midiEvents.append(MIDIEvent(tick: note.tick, message: .noteOn(channel: 0, note: note.pitch, velocity: 64)))
            let offTick = note.tick + note.dur
            midiEvents.append(MIDIEvent(tick: offTick, message: .noteOff(channel: 0, note: note.pitch)))
        }

        return TMDMIDIEncoder.encodeTrack(events: midiEvents)
    }

    private static func midiTick(_ quarterNotes: Double) -> UInt32 {
        let ticks = (quarterNotes * Double(ticksPerQuarter)).rounded()
        guard ticks.isFinite else { return 0 }
        return UInt32(min(max(0, ticks), Double(UInt32.max)))
    }
}
