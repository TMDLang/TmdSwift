import Foundation

// MARK: - JSON-RPC Frame & Codec

public enum TmdJSONRPCId: Equatable, Sendable, ExpressibleByIntegerLiteral,
    ExpressibleByStringLiteral
{
    case int(Int)
    case string(String)

    public init(integerLiteral value: Int) {
        self = .int(value)
    }

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public static func == (lhs: TmdJSONRPCId, rhs: Int) -> Bool {
        if case .int(let v) = lhs { return v == rhs }
        return false
    }

    public static func == (lhs: Int, rhs: TmdJSONRPCId) -> Bool {
        if case .int(let v) = rhs { return lhs == v }
        return false
    }

    fileprivate var jsonValue: Any {
        switch self {
        case .int(let v): return v
        case .string(let s): return s
        }
    }
}

public struct TmdJSONRPCFrame: @unchecked Sendable {
    public let id: TmdJSONRPCId?
    public let method: String?
    public let params: Any?

    public init(id: TmdJSONRPCId?, method: String?, params: Any? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct TmdJSONRPCResponse: @unchecked Sendable {
    public let id: TmdJSONRPCId?
    public let result: Any?
    public let error: Any?

    public init(id: TmdJSONRPCId?, result: Any? = nil, error: Any? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct TmdJSONRPCCodec {
    public static func decode(_ input: String) -> [TmdJSONRPCFrame] {
        var buffer = Data(input.utf8)
        return decode(buffer: &buffer)
    }

    public static func decode(buffer: inout Data) -> [TmdJSONRPCFrame] {
        var frames: [TmdJSONRPCFrame] = []
        let separator = Data("\r\n\r\n".utf8)

        while let range = buffer.range(of: separator) {
            let headerData = buffer.subdata(in: 0..<range.lowerBound)
            let headerStr = String(data: headerData, encoding: .utf8) ?? ""

            var contentLength: Int? = nil
            for line in headerStr.components(separatedBy: "\r\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if parts.count == 2 && parts[0].lowercased() == "content-length" {
                    contentLength = Int(parts[1])
                }
            }

            guard let length = contentLength else {
                break
            }

            let bodyStart = range.upperBound
            let bodyEnd = bodyStart + length
            guard buffer.count >= bodyEnd else {
                break
            }

            let bodyData = buffer.subdata(in: bodyStart..<bodyEnd)
            buffer = buffer.subdata(in: bodyEnd..<buffer.count)

            if let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                let id: TmdJSONRPCId?
                if let intId = obj["id"] as? Int {
                    id = .int(intId)
                } else if let strId = obj["id"] as? String {
                    id = .string(strId)
                } else {
                    id = nil
                }
                let method = obj["method"] as? String
                let params = obj["params"]
                frames.append(TmdJSONRPCFrame(id: id, method: method, params: params))
            }
        }
        return frames
    }

    public static func encode(_ response: TmdJSONRPCResponse) -> String {
        var dict: [String: Any] = [
            "jsonrpc": "2.0"
        ]
        if let id = response.id {
            dict["id"] = id.jsonValue
        } else {
            dict["id"] = NSNull()
        }
        if let result = response.result {
            dict["result"] = result
        }
        if let error = response.error {
            dict["error"] = error
        }
        return encodePayload(dict)
    }

    public static func encode(method: String, params: Any) -> String {
        let dict: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ]
        return encodePayload(dict)
    }

    private static func encodePayload(_ dict: [String: Any]) -> String {
        var options: JSONSerialization.WritingOptions = []
        if #available(macOS 10.15, *) {
            options.insert(.withoutEscapingSlashes)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: options),
            let jsonStr = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        let length = jsonStr.utf8.count
        return "Content-Length: \(length)\r\n\r\n\(jsonStr)"
    }
}

// MARK: - Completion Engine
