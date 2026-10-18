import Foundation

/// Errors thrown when encoding or decoding TMD Studio share URLs and hashes.
public enum TmdStudioShareError: Error, LocalizedError, Equatable {
    case scoreTooLarge
    case invalidShareHash
    case invalidUTF8Payload

    public var errorDescription: String? {
        switch self {
        case .scoreTooLarge:
            return "Shared score is too large"
        case .invalidShareHash:
            return "Invalid or damaged TMD Studio share link"
        case .invalidUTF8Payload:
            return "Decoded share payload is not valid UTF-8"
        }
    }
}

/// Encodes and decodes TMD Studio share links (`#tmd=<base64url(deflate-raw(utf8))>`).
public enum TmdStudioShare {
    public static let hashPrefix = "#tmd="
    public static let defaultBaseURL = "https://tmdlang.github.io/Tmd-TS/"
    public static let maxSharedChars = 1_000_000

    /// Encodes a TMD score string into a URL hash (`#tmd=...`) compatible with TMD Studio.
    public static func encodeShareHash(_ text: String) throws -> String {
        guard text.utf16.count <= maxSharedChars else {
            throw TmdStudioShareError.scoreTooLarge
        }
        let utf8Data = Data(text.utf8)
        let compressed = try compressRawDeflate(utf8Data)
        return hashPrefix + base64URLEncode(compressed)
    }

    /// Decodes a TMD Studio URL hash (`#tmd=...`) back into the original TMD score string.
    /// Returns `nil` when `hash` does not start with `#tmd=`.
    public static func decodeShareHash(_ hash: String) throws -> String? {
        guard hash.hasPrefix(hashPrefix) else {
            return nil
        }
        let encoded = String(hash.dropFirst(hashPrefix.count))
        guard let compressed = base64URLDecode(encoded) else {
            throw TmdStudioShareError.invalidShareHash
        }
        let decompressed = try decompressRawDeflate(
            compressed,
            maxUTF16Units: maxSharedChars
        )
        guard let text = String(data: decompressed, encoding: .utf8) else {
            throw TmdStudioShareError.invalidUTF8Payload
        }
        guard text.utf16.count <= maxSharedChars else {
            throw TmdStudioShareError.scoreTooLarge
        }
        return text
    }

    /// Generates a complete TMD Studio share URL for the given TMD score text.
    public static func generateStudioURL(
        for text: String,
        baseURL: String = defaultBaseURL
    ) throws -> String {
        let hash = try encodeShareHash(text)
        let normalizedBase = normalizeBaseURL(baseURL)
        return normalizedBase + hash
    }

    private static func normalizeBaseURL(_ rawBaseURL: String) -> String {
        let trimmed = rawBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutFragment = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? trimmed
        guard !withoutFragment.isEmpty else {
            return defaultBaseURL
        }
        if withoutFragment.hasSuffix("/")
            || withoutFragment.contains("?")
            || withoutFragment.lowercased().hasSuffix(".html")
            || withoutFragment.lowercased().hasSuffix(".htm")
        {
            return withoutFragment
        }
        return withoutFragment + "/"
    }

    // MARK: - Base64URL

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        guard
            string.allSatisfy({
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
            })
        else {
            return nil
        }
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 {
            return nil
        } else if remainder > 1 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    // MARK: - RFC 1951 Raw DEFLATE Tables

    private static let lengthBases: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
    ]

    private static let lengthExtraBits: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]

    private static let distBases: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ]

    private static let distExtraBits: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
    ]

    private static let codeLengthOrder: [Int] = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
    ]

    // MARK: - RFC 1951 Raw DEFLATE Compressor (LZ77 + Fixed Huffman)

    static func compressRawDeflate(_ data: Data) throws -> Data {
        let bytes = Array(data)
        var writer = BitWriter()
        // Final block (BFINAL = 1), Fixed Huffman (BTYPE = 01)
        writer.writeBits(1, count: 1)
        writer.writeBits(1, count: 2)

        let n = bytes.count
        if n == 0 {
            writeFixedLiteralOrLength(256, to: &writer)
            return writer.finish()
        }

        let windowSize = 32768
        let hashBits = 15
        let hashSize = 1 << hashBits
        let hashMask = hashSize - 1
        var head = [Int](repeating: -1, count: hashSize)
        var prev = [Int](repeating: -1, count: n)

        @inline(__always)
        func hash3(_ idx: Int) -> Int {
            ((Int(bytes[idx]) << 10) ^ (Int(bytes[idx + 1]) << 5) ^ Int(bytes[idx + 2])) & hashMask
        }

        var pos = 0
        while pos < n {
            var bestLen = 0
            var bestDist = 0

            if pos + 2 < n {
                let h = hash3(pos)
                var candidate = head[h]
                prev[pos] = candidate
                head[h] = pos

                let maxLen = min(258, n - pos)
                var chainLimit = 64
                while candidate >= 0 && (pos - candidate) <= windowSize && chainLimit > 0 {
                    chainLimit -= 1
                    if bytes[candidate + bestLen] == bytes[pos + bestLen] {
                        var matchLen = 0
                        while matchLen < maxLen && bytes[candidate + matchLen] == bytes[pos + matchLen] {
                            matchLen += 1
                        }
                        if matchLen >= 3 && matchLen > bestLen {
                            bestLen = matchLen
                            bestDist = pos - candidate
                            if bestLen == maxLen {
                                break
                            }
                        }
                    }
                    candidate = prev[candidate]
                }
            }

            if bestLen >= 3 {
                writeFixedLengthDistance(length: bestLen, distance: bestDist, to: &writer)
                let endPos = pos + bestLen
                pos += 1
                while pos < endPos {
                    if pos + 2 < n {
                        let h = hash3(pos)
                        prev[pos] = head[h]
                        head[h] = pos
                    }
                    pos += 1
                }
            } else {
                writeFixedLiteralOrLength(Int(bytes[pos]), to: &writer)
                pos += 1
            }
        }

        // End of block symbol (256)
        writeFixedLiteralOrLength(256, to: &writer)
        return writer.finish()
    }

    private static func writeFixedLiteralOrLength(_ symbol: Int, to writer: inout BitWriter) {
        if symbol <= 143 {
            writer.writeHuffmanCode(symbol + 0x30, length: 8)
        } else if symbol <= 255 {
            writer.writeHuffmanCode(symbol - 144 + 0x190, length: 9)
        } else if symbol <= 279 {
            writer.writeHuffmanCode(symbol - 256, length: 7)
        } else {
            writer.writeHuffmanCode(symbol - 280 + 0xC0, length: 8)
        }
    }

    private static func writeFixedLengthDistance(
        length: Int,
        distance: Int,
        to writer: inout BitWriter
    ) {
        var lenCodeIndex = 0
        for i in (0..<lengthBases.count).reversed() {
            if length >= lengthBases[i] {
                lenCodeIndex = i
                break
            }
        }
        writeFixedLiteralOrLength(257 + lenCodeIndex, to: &writer)
        let extraLenBits = lengthExtraBits[lenCodeIndex]
        if extraLenBits > 0 {
            writer.writeBits(length - lengthBases[lenCodeIndex], count: extraLenBits)
        }

        var distCodeIndex = 0
        for i in (0..<distBases.count).reversed() {
            if distance >= distBases[i] {
                distCodeIndex = i
                break
            }
        }
        // Fixed distance codes are 5-bit big-endian (Huffman MSB-first)
        writer.writeHuffmanCode(distCodeIndex, length: 5)
        let extraDistBits = distExtraBits[distCodeIndex]
        if extraDistBits > 0 {
            writer.writeBits(distance - distBases[distCodeIndex], count: extraDistBits)
        }
    }

    // MARK: - RFC 1951 Raw DEFLATE Decompressor

    static func decompressRawDeflate(_ data: Data, maxUTF16Units: Int) throws -> Data {
        let bytes = Array(data)
        guard !bytes.isEmpty else {
            throw TmdStudioShareError.invalidShareHash
        }
        var reader = BitReader(bytes: bytes)
        var output: [UInt8] = []
        var utf16UnitEstimate = 0

        @inline(__always)
        func appendDecodedByte(_ byte: UInt8) throws {
            output.append(byte)
            // In UTF-8:
            // - 0x00..0x7F (1-byte sequence) contributes 1 UTF-16 unit
            // - 0xC0..0xEF (2- or 3-byte starter) contributes 1 UTF-16 unit
            // - 0xF0..0xF7 (4-byte starter) contributes 2 UTF-16 units
            // - 0x80..0xBF (continuation byte) contributes 0 additional units
            if (byte & 0xC0) != 0x80 {
                utf16UnitEstimate += (byte >= 0xF0) ? 2 : 1
                if utf16UnitEstimate > maxUTF16Units {
                    throw TmdStudioShareError.scoreTooLarge
                }
            }
        }

        var isFinal = false
        while !isFinal {
            isFinal = (try reader.readBits(1)) == 1
            let btype = try reader.readBits(2)

            switch btype {
            case 0:
                // Uncompressed stored block
                reader.alignToByte()
                let len = try reader.readUInt16LE()
                let nlen = try reader.readUInt16LE()
                guard len == (~nlen & 0xFFFF) else {
                    throw TmdStudioShareError.invalidShareHash
                }
                for _ in 0..<Int(len) {
                    let b = try reader.readAlignedByte()
                    try appendDecodedByte(b)
                }

            case 1, 2:
                let litLenTree: HuffmanDecoder
                let distTree: HuffmanDecoder
                if btype == 1 {
                    litLenTree = fixedLitLenDecoder
                    distTree = fixedDistDecoder
                } else {
                    (litLenTree, distTree) = try decodeDynamicTrees(from: &reader)
                }

                while true {
                    let sym = try litLenTree.decode(from: &reader)
                    if sym < 256 {
                        try appendDecodedByte(UInt8(sym))
                    } else if sym == 256 {
                        break
                    } else {
                        let lenIdx = sym - 257
                        guard lenIdx >= 0 && lenIdx < lengthBases.count else {
                            throw TmdStudioShareError.invalidShareHash
                        }
                        let extraLen = try reader.readBits(lengthExtraBits[lenIdx])
                        let length = lengthBases[lenIdx] + extraLen

                        let distSym = try distTree.decode(from: &reader)
                        guard distSym >= 0 && distSym < distBases.count else {
                            throw TmdStudioShareError.invalidShareHash
                        }
                        let extraDist = try reader.readBits(distExtraBits[distSym])
                        let distance = distBases[distSym] + extraDist

                        guard distance > 0 && distance <= output.count else {
                            throw TmdStudioShareError.invalidShareHash
                        }
                        for _ in 0..<length {
                            let b = output[output.count - distance]
                            try appendDecodedByte(b)
                        }
                    }
                }

            default:
                throw TmdStudioShareError.invalidShareHash
            }
        }

        return Data(output)
    }

    private static let fixedLitLenDecoder: HuffmanDecoder = {
        var lengths = [Int](repeating: 0, count: 288)
        for i in 0...143 { lengths[i] = 8 }
        for i in 144...255 { lengths[i] = 9 }
        for i in 256...279 { lengths[i] = 7 }
        for i in 280...287 { lengths[i] = 8 }
        return try! HuffmanDecoder(codeLengths: lengths)
    }()

    private static let fixedDistDecoder: HuffmanDecoder = {
        let lengths = [Int](repeating: 5, count: 32)
        return try! HuffmanDecoder(codeLengths: lengths)
    }()

    private static func decodeDynamicTrees(
        from reader: inout BitReader
    ) throws -> (HuffmanDecoder, HuffmanDecoder) {
        let hlit = try reader.readBits(5) + 257
        let hdist = try reader.readBits(5) + 1
        let hclen = try reader.readBits(4) + 4
        guard hlit <= 286 && hdist <= 30 else {
            throw TmdStudioShareError.invalidShareHash
        }

        var codeLengthLengths = [Int](repeating: 0, count: 19)
        for i in 0..<hclen {
            codeLengthLengths[codeLengthOrder[i]] = try reader.readBits(3)
        }
        let codeLenDecoder = try HuffmanDecoder(codeLengths: codeLengthLengths)

        let totalCodes = hlit + hdist
        var lengths: [Int] = []
        lengths.reserveCapacity(totalCodes)

        while lengths.count < totalCodes {
            let sym = try codeLenDecoder.decode(from: &reader)
            switch sym {
            case 0...15:
                lengths.append(sym)
            case 16:
                guard let prev = lengths.last else {
                    throw TmdStudioShareError.invalidShareHash
                }
                let repeatCount = try reader.readBits(2) + 3
                guard lengths.count + repeatCount <= totalCodes else {
                    throw TmdStudioShareError.invalidShareHash
                }
                for _ in 0..<repeatCount { lengths.append(prev) }
            case 17:
                let repeatCount = try reader.readBits(3) + 3
                guard lengths.count + repeatCount <= totalCodes else {
                    throw TmdStudioShareError.invalidShareHash
                }
                for _ in 0..<repeatCount { lengths.append(0) }
            case 18:
                let repeatCount = try reader.readBits(7) + 11
                guard lengths.count + repeatCount <= totalCodes else {
                    throw TmdStudioShareError.invalidShareHash
                }
                for _ in 0..<repeatCount { lengths.append(0) }
            default:
                throw TmdStudioShareError.invalidShareHash
            }
        }

        let litLenLengths = Array(lengths[0..<hlit])
        let distLengths = Array(lengths[hlit..<totalCodes])
        guard litLenLengths.count > 256 && litLenLengths[256] > 0 else {
            throw TmdStudioShareError.invalidShareHash
        }
        let litLenDecoder = try HuffmanDecoder(codeLengths: litLenLengths)
        let distDecoder = try HuffmanDecoder(codeLengths: distLengths, allowEmpty: true)
        return (litLenDecoder, distDecoder)
    }
}

// MARK: - Bit Stream Helpers

private struct BitWriter {
    private var bytes: [UInt8] = []
    private var currentByte: UInt8 = 0
    private var bitOffset: Int = 0

    mutating func writeBits(_ value: Int, count: Int) {
        var v = value
        for _ in 0..<count {
            if (v & 1) != 0 {
                currentByte |= UInt8(1 << bitOffset)
            }
            bitOffset += 1
            if bitOffset == 8 {
                bytes.append(currentByte)
                currentByte = 0
                bitOffset = 0
            }
            v >>= 1
        }
    }

    mutating func writeHuffmanCode(_ code: Int, length: Int) {
        for i in (0..<length).reversed() {
            let bit = (code >> i) & 1
            if bit != 0 {
                currentByte |= UInt8(1 << bitOffset)
            }
            bitOffset += 1
            if bitOffset == 8 {
                bytes.append(currentByte)
                currentByte = 0
                bitOffset = 0
            }
        }
    }

    mutating func finish() -> Data {
        if bitOffset > 0 {
            bytes.append(currentByte)
            currentByte = 0
            bitOffset = 0
        }
        return Data(bytes)
    }
}

private struct BitReader {
    let bytes: [UInt8]
    var byteIndex: Int = 0
    var bitOffset: Int = 0

    mutating func readBit() throws -> Int {
        guard byteIndex < bytes.count else {
            throw TmdStudioShareError.invalidShareHash
        }
        let bit = Int((bytes[byteIndex] >> bitOffset) & 1)
        bitOffset += 1
        if bitOffset == 8 {
            bitOffset = 0
            byteIndex += 1
        }
        return bit
    }

    mutating func readBits(_ count: Int) throws -> Int {
        var result = 0
        for i in 0..<count {
            let b = try readBit()
            result |= (b << i)
        }
        return result
    }

    mutating func alignToByte() {
        if bitOffset != 0 {
            bitOffset = 0
            byteIndex += 1
        }
    }

    mutating func readAlignedByte() throws -> UInt8 {
        guard bitOffset == 0 && byteIndex < bytes.count else {
            throw TmdStudioShareError.invalidShareHash
        }
        let b = bytes[byteIndex]
        byteIndex += 1
        return b
    }

    mutating func readUInt16LE() throws -> UInt16 {
        let lo = UInt16(try readAlignedByte())
        let hi = UInt16(try readAlignedByte())
        return lo | (hi << 8)
    }
}

private struct HuffmanDecoder: Sendable {
    private let maxBits: Int
    private let counts: [Int]
    private let symbols: [Int]
    private let isEmpty: Bool

    init(codeLengths: [Int], allowEmpty: Bool = false) throws {
        let maxLen = codeLengths.max() ?? 0
        if maxLen == 0 {
            guard allowEmpty else {
                throw TmdStudioShareError.invalidShareHash
            }
            self.maxBits = 0
            self.counts = []
            self.symbols = []
            self.isEmpty = true
            return
        }
        guard maxLen <= 15 else {
            throw TmdStudioShareError.invalidShareHash
        }
        var blCount = [Int](repeating: 0, count: maxLen + 1)
        for len in codeLengths where len > 0 {
            blCount[len] += 1
        }

        // Check for oversubscribed tree
        var left = 1
        for bits in 1...maxLen {
            left <<= 1
            left -= blCount[bits]
            if left < 0 {
                throw TmdStudioShareError.invalidShareHash
            }
        }

        var offsets = [Int](repeating: 0, count: maxLen + 1)
        var totalSymbols = 0
        for bits in 1...maxLen {
            offsets[bits] = totalSymbols
            totalSymbols += blCount[bits]
        }

        var sortedSymbols = [Int](repeating: 0, count: totalSymbols)
        for (sym, len) in codeLengths.enumerated() where len > 0 {
            sortedSymbols[offsets[len]] = sym
            offsets[len] += 1
        }

        self.maxBits = maxLen
        self.counts = blCount
        self.symbols = sortedSymbols
        self.isEmpty = false
    }

    func decode(from reader: inout BitReader) throws -> Int {
        guard !isEmpty else {
            throw TmdStudioShareError.invalidShareHash
        }
        var code = 0
        var first = 0
        var index = 0
        for len in 1...maxBits {
            code |= try reader.readBit()
            let count = counts[len]
            if code - count < first {
                return symbols[index + (code - first)]
            }
            index += count
            first += count
            first <<= 1
            code <<= 1
        }
        throw TmdStudioShareError.invalidShareHash
    }
}
