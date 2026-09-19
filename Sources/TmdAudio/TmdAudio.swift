import Foundation
import TmdSwift
import TmdMIDI

#if canImport(AudioToolbox) && canImport(AVFoundation)
import AudioToolbox
import AVFoundation

public enum TmdAudioError: Error, LocalizedError {
    case unsupportedPlatform
    case soundBankNotFound
    case failedToCreatePlayer
    case renderFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Audio rendering is only supported on Apple platforms (macOS / iOS)."
        case .soundBankNotFound:
            return "Could not locate a DLS or SoundFont (.sf2) soundbank."
        case .failedToCreatePlayer:
            return "Failed to initialize AudioToolbox MusicPlayer sequence."
        case .renderFailed(let status):
            return "CoreAudio offline render failed with status code \(status)."
        }
    }
}

public struct TMDWAVRenderer {
    public static let defaultSoundBankPath = "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"

    /// Renders a Sheet into 44.1kHz 16-bit stereo WAV audio data.
    ///
    /// - Parameters:
    ///   - sheet: The TMD Sheet AST to render.
    ///   - soundBankURL: Optional custom SoundFont (.sf2) or DLS soundbank URL. If nil, uses macOS default Roland GS soundbank.
    ///   - sampleRate: Sample rate in Hz (default: 44100).
    ///   - targetParagraph: Optional section filter.
    ///   - targetInstrument: Optional instrument filter.
    public static func renderWAV(
        from sheet: Sheet,
        soundBankURL: URL? = nil,
        sampleRate: Double = 44100.0,
        targetParagraph: String? = nil,
        targetInstrument: String? = nil
    ) throws -> Data {
        let midiData = TMDMIDIGenerator.generateMIDI(
            from: sheet,
            targetParagraph: targetParagraph,
            targetInstrument: targetInstrument
        )
        return try renderWAV(fromMIDIData: midiData, soundBankURL: soundBankURL, sampleRate: sampleRate)
    }

    /// Renders Standard MIDI Data into 44.1kHz 16-bit stereo WAV audio data.
    public static func renderWAV(
        fromMIDIData midiData: Data,
        soundBankURL: URL? = nil,
        sampleRate: Double = 44100.0
    ) throws -> Data {
        // Resolve soundbank URL
        let bankURL: URL
        if let customURL = soundBankURL {
            bankURL = customURL
        } else {
            let defaultURL = URL(fileURLWithPath: defaultSoundBankPath)
            guard FileManager.default.fileExists(atPath: defaultURL.path) else {
                throw TmdAudioError.soundBankNotFound
            }
            bankURL = defaultURL
        }

        // Create MusicSequence from MIDI data
        var sequence: MusicSequence?
        var status = NewMusicSequence(&sequence)
        guard status == noErr, let musicSequence = sequence else {
            throw TmdAudioError.failedToCreatePlayer
        }
        defer { DisposeMusicSequence(musicSequence) }

        // Write temp MIDI file for MusicSequenceFileLoad
        let tempMIDIURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".mid")
        try midiData.write(to: tempMIDIURL)
        defer { try? FileManager.default.removeItem(at: tempMIDIURL) }

        status = MusicSequenceFileLoad(musicSequence, tempMIDIURL as CFURL, .midiType, MusicSequenceLoadFlags())
        guard status == noErr else {
            throw TmdAudioError.renderFailed(status)
        }

        // Calculate sequence duration in seconds
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(musicSequence, &trackCount)
        var maxTrackBeats: MusicTimeStamp = 0
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(musicSequence, i, &track)
            if let trk = track {
                var trackLength: MusicTimeStamp = 0
                var propSize = UInt32(MemoryLayout<MusicTimeStamp>.size)
                MusicTrackGetProperty(trk, kSequenceTrackProperty_TrackLength, &trackLength, &propSize)
                if trackLength > maxTrackBeats {
                    maxTrackBeats = trackLength
                }
            }
        }

        // Setup AUGraph for Offline Rendering
        var graph: AUGraph?
        status = NewAUGraph(&graph)
        guard status == noErr, let audioGraph = graph else {
            throw TmdAudioError.renderFailed(status)
        }
        defer {
            AUGraphClose(audioGraph)
            DisposeAUGraph(audioGraph)
        }

        // Add DLS Synth Unit
        var synthDesc = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_MIDISynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var synthNode: AUNode = 0
        status = AUGraphAddNode(audioGraph, &synthDesc, &synthNode)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        // Add Generic Output Unit (for offline render)
        var outputDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_GenericOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var outputNode: AUNode = 0
        status = AUGraphAddNode(audioGraph, &outputDesc, &outputNode)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        status = AUGraphOpen(audioGraph)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        // Connect Synth to Output
        status = AUGraphConnectNodeInput(audioGraph, synthNode, 0, outputNode, 0)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        var synthUnit: AudioUnit?
        status = AUGraphNodeInfo(audioGraph, synthNode, nil, &synthUnit)
        guard status == noErr, let synth = synthUnit else { throw TmdAudioError.renderFailed(status) }

        var outputUnit: AudioUnit?
        status = AUGraphNodeInfo(audioGraph, outputNode, nil, &outputUnit)
        guard status == noErr, let output = outputUnit else { throw TmdAudioError.renderFailed(status) }

        // Set SoundBank URL on Synth
        var urlRef = bankURL as CFURL
        withUnsafePointer(to: &urlRef) { urlPtr in
            status = AudioUnitSetProperty(
                synth,
                kMusicDeviceProperty_SoundBankURL,
                kAudioUnitScope_Global,
                0,
                urlPtr,
                UInt32(MemoryLayout<CFURL>.size)
            )
        }
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        // Set Standard Stereo LPCM Format (Float32 for rendering)
        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        status = AudioUnitSetProperty(
            output,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            0,
            &streamFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        status = AUGraphInitialize(audioGraph)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        // Link MusicSequence to AUGraph
        status = MusicSequenceSetAUGraph(musicSequence, audioGraph)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        // Create MusicPlayer
        var player: MusicPlayer?
        status = NewMusicPlayer(&player)
        guard status == noErr, let musicPlayer = player else {
            throw TmdAudioError.renderFailed(status)
        }
        defer {
            MusicPlayerStop(musicPlayer)
            DisposeMusicPlayer(musicPlayer)
        }

        status = MusicPlayerSetSequence(musicPlayer, musicSequence)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        status = MusicPlayerPreroll(musicPlayer)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        status = MusicPlayerStart(musicPlayer)
        guard status == noErr else { throw TmdAudioError.renderFailed(status) }

        // Determine render duration: convert beats to approximate seconds + 2.5s release reverb tail
        var sequenceSeconds: Float64 = 0
        let timeStatus = MusicSequenceGetSecondsForBeats(musicSequence, maxTrackBeats, &sequenceSeconds)
        let baseSeconds: Double
        if timeStatus == noErr && sequenceSeconds > 0 {
            baseSeconds = sequenceSeconds
        } else {
            baseSeconds = Double(maxTrackBeats) * (60.0 / 120.0)
        }
        let totalSeconds = max(2.0, baseSeconds + 2.5)
        let totalFrames = clampedUInt32(totalSeconds * sampleRate)

        // Offline render loop
        let framesPerBuffer: UInt32 = 1024
        var renderedFrames: UInt32 = 0

        var pcmSamplesLeft: [Float] = []
        var pcmSamplesRight: [Float] = []
        pcmSamplesLeft.reserveCapacity(Int(totalFrames))
        pcmSamplesRight.reserveCapacity(Int(totalFrames))

        var timeStamp = AudioTimeStamp()
        timeStamp.mFlags = .sampleTimeValid
        timeStamp.mSampleTime = 0

        var bufferLeft = [Float](repeating: 0, count: Int(framesPerBuffer))
        var bufferRight = [Float](repeating: 0, count: Int(framesPerBuffer))

        while renderedFrames < totalFrames {
            let framesToRender = min(framesPerBuffer, totalFrames - renderedFrames)
            let audioBufferList = AudioBufferList.allocate(maximumBuffers: 2)
            defer { free(UnsafeMutableRawPointer(audioBufferList.unsafeMutablePointer)) }

            bufferLeft.withUnsafeMutableBufferPointer { leftPtr in
                bufferRight.withUnsafeMutableBufferPointer { rightPtr in
                    audioBufferList[0] = AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: framesToRender * 4,
                        mData: leftPtr.baseAddress
                    )
                    audioBufferList[1] = AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: framesToRender * 4,
                        mData: rightPtr.baseAddress
                    )

                    var actionFlags = AudioUnitRenderActionFlags()
                    let renderStatus = AudioUnitRender(
                        output,
                        &actionFlags,
                        &timeStamp,
                        0,
                        framesToRender,
                        audioBufferList.unsafeMutablePointer
                    )

                    if renderStatus == noErr {
                        pcmSamplesLeft.append(contentsOf: leftPtr.prefix(Int(framesToRender)))
                        pcmSamplesRight.append(contentsOf: rightPtr.prefix(Int(framesToRender)))
                    }
                }
            }

            timeStamp.mSampleTime += Float64(framesToRender)
            renderedFrames += framesToRender
        }

        // Encode into Standard 16-bit Linear PCM Stereo WAV
        return TMDWAVEncoder.encode(left: pcmSamplesLeft, right: pcmSamplesRight, sampleRate: clampedUInt32(sampleRate))
    }

    private static func clampedUInt32(_ value: Double) -> UInt32 {
        guard value.isFinite else { return value.sign == .minus ? 0 : UInt32.max }
        return UInt32(min(max(0, value), Double(UInt32.max)))
    }
}
#else
public enum TmdAudioError: Error, LocalizedError {
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Audio rendering is only supported on Apple platforms (macOS / iOS)."
        }
    }
}

public struct TMDWAVRenderer {
    public static func renderWAV(
        from sheet: Sheet,
        soundBankURL: URL? = nil,
        sampleRate: Double = 44100.0,
        targetParagraph: String? = nil,
        targetInstrument: String? = nil
    ) throws -> Data {
        throw TmdAudioError.unsupportedPlatform
    }

    public static func renderWAV(
        fromMIDIData midiData: Data,
        soundBankURL: URL? = nil,
        sampleRate: Double = 44100.0
    ) throws -> Data {
        throw TmdAudioError.unsupportedPlatform
    }
}
#endif
