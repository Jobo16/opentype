import Foundation

enum VolcProtocolError: Error, Sendable, LocalizedError {
    case headerTooShort
    case unknownMessageType(UInt8)
    case unknownFlags(UInt8)
    case unknownSerialization(UInt8)
    case unknownCompression(UInt8)
    case invalidPayload
    case decompressionFailed
    case compressionFailed
    case serverError(code: Int?, message: String?)

    var errorDescription: String? {
        switch self {
        case .headerTooShort: return "Header too short"
        case .unknownMessageType(let v): return "Unknown message type: 0x\(String(v, radix: 16))"
        case .unknownFlags(let v): return "Unknown flags: 0x\(String(v, radix: 16))"
        case .unknownSerialization(let v): return "Unknown serialization: 0x\(String(v, radix: 16))"
        case .unknownCompression(let v): return "Unknown compression: 0x\(String(v, radix: 16))"
        case .invalidPayload: return "Invalid payload"
        case .decompressionFailed: return "Decompression failed"
        case .compressionFailed: return "Compression failed"
        case .serverError(let code, let message):
            return "Server error \(code.map { "\($0)" } ?? "?"): \(message ?? "unknown")"
        }
    }
}
