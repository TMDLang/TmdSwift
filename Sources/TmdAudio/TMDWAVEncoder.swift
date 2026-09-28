import Foundation

/// Encodes stereo PCM samples into a RIFF/WAV file.
final class TMDWAVEncoder {
    static func encode(left: [Float], right: [Float], sampleRate: UInt32) -> Data {
        let sampleCount = min(left.count, right.count)
        let format = WAVFormat(sampleRate: sampleRate, channels: 2, bitsPerSample: 16)
        let samples = (0..<sampleCount).flatMap { index in
            [left[index], right[index]].map(Self.pcm16)
        }
        let data = samples.reduce(into: Data()) { data, sample in
            data.append(contentsOf: sample.littleEndianBytes)
        }
        return WAVFile(format: format, data: data).encoded()
    }

    private static func pcm16(_ sample: Float) -> Int16 {
        Int16(max(-1.0, min(1.0, sample)) * 32767.0)
    }
}

private struct WAVFormat {
    let sampleRate: UInt32
    let channels: UInt16
    let bitsPerSample: UInt16

    var blockAlign: UInt16 { channels * bitsPerSample / 8 }
    var byteRate: UInt32 { UInt32(clamping: UInt64(sampleRate) * UInt64(blockAlign)) }
}

private struct WAVFile {
    let format: WAVFormat
    let data: Data

    func encoded() -> Data {
        let dataSize = UInt32(clamping: data.count)
        let chunkSize = UInt32(clamping: UInt64(36) + UInt64(dataSize))
        let chunks: [Data] = [
            Data("RIFF".utf8),
            Data(chunkSize.littleEndianBytes),
            Data("WAVE".utf8),
            Data("fmt ".utf8),
            Data(UInt32(16).littleEndianBytes),
            Data(UInt16(1).littleEndianBytes),
            Data(format.channels.littleEndianBytes),
            Data(format.sampleRate.littleEndianBytes),
            Data(format.byteRate.littleEndianBytes),
            Data(format.blockAlign.littleEndianBytes),
            Data(format.bitsPerSample.littleEndianBytes),
            Data("data".utf8),
            Data(dataSize.littleEndianBytes),
        ]
        let header = chunks.reduce(into: Data()) { result, chunk in
            result.append(chunk)
        }
        return header + data
    }
}

extension FixedWidthInteger {
    fileprivate var littleEndianBytes: [UInt8] {
        var value = littleEndian
        return withUnsafeBytes(of: &value) { Array($0) }
    }
}
