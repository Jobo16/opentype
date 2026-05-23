import Foundation
import Compression

// MARK: - Result Types

struct VolcUtterance: Sendable, Equatable {
    let text: String
    let definite: Bool
}

struct VolcASRResult: Sendable, Equatable {
    let text: String
    let utterances: [VolcUtterance]
}

struct VolcServerResponse: Sendable, Equatable {
    let header: VolcHeader
    let result: VolcASRResult
}

// MARK: - Protocol Functions

enum VolcProtocol: Sendable {

    // MARK: - Build Client Request JSON

    static func buildClientRequest(
        uid: String,
        format: String = "pcm",
        codec: String = "raw",
        rate: Int = 16000,
        bits: Int = 16,
        channel: Int = 1,
        showUtterances: Bool = true,
        resultType: String = "full",
        hotwords: [String] = []
    ) -> Data {
        var requestDict: [String: Any] = [
            "model_name": "bigmodel",
            "enable_punc": true,
            "enable_ddc": true,
            "enable_nonstream": true,
            "show_utterances": showUtterances,
            "result_type": resultType,
            "end_window_size": 3000,
            "force_to_speech_time": 0,
        ]

        let cleanedHotwords = hotwords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleanedHotwords.isEmpty {
            let contextObject: [String: Any] = [
                "hotwords": cleanedHotwords.map { ["word": $0, "scale": 5.0] as [String: Any] }
            ]
            if let contextData = try? JSONSerialization.data(withJSONObject: contextObject),
               let contextString = String(data: contextData, encoding: .utf8) {
                requestDict["context"] = contextString
            }
        }

        let payload: [String: Any] = [
            "user": ["uid": uid],
            "audio": [
                "format": format,
                "codec": codec,
                "rate": rate,
                "bits": bits,
                "channel": channel,
            ],
            "request": requestDict,
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - Encode Full Binary Message

    static func encodeMessage(
        header: VolcHeader,
        payload: Data,
        sequenceNumber: Int32? = nil
    ) -> Data {
        var message = header.encode()

        if let seq = sequenceNumber {
            var seqBig = seq.bigEndian
            message.append(Data(bytes: &seqBig, count: 4))
        }

        var size = UInt32(payload.count).bigEndian
        message.append(Data(bytes: &size, count: 4))
        message.append(payload)

        return message
    }

    // MARK: - Encode Audio Packet

    static func encodeAudioPacket(audioData: Data, isLast: Bool) -> Data {
        let flags: VolcMessageFlags = isLast ? .lastPacketNoSequence : .noSequence
        let header = VolcHeader(
            messageType: .audioOnlyRequest,
            flags: flags,
            serialization: .none,
            compression: .none
        )
        return encodeMessage(header: header, payload: audioData)
    }

    // MARK: - Decode Server Message

    static func decodeServerResponse(_ data: Data) throws -> VolcServerResponse {
        let header = try VolcHeader.decode(from: data)
        let headerBytes = Int(header.headerSize) * 4
        var offset = headerBytes

        if header.flags == .positiveSequence || header.flags == .negativeSequenceLast {
            offset += 4
        }

        guard data.count >= offset + 4 else {
            throw VolcProtocolError.invalidPayload
        }

        let sizeBytes = data[data.startIndex + offset ..< data.startIndex + offset + 4]
        let payloadSize = Int(UInt32(bigEndian: sizeBytes.withUnsafeBytes { $0.load(as: UInt32.self) }))
        offset += 4

        guard data.count >= offset + payloadSize else {
            throw VolcProtocolError.invalidPayload
        }

        var payload = data[data.startIndex + offset ..< data.startIndex + offset + payloadSize]

        if header.messageType == .serverError {
            if header.compression == .gzip {
                payload = try gzipDecompress(Data(payload))
            }
            if header.serialization == .json, !payload.isEmpty {
                if let json = try? JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any] {
                    let code = json["code"] as? Int
                    let message = json["message"] as? String
                    throw VolcProtocolError.serverError(code: code, message: message)
                }
            }
            throw VolcProtocolError.serverError(code: nil, message: nil)
        }

        if header.compression == .gzip {
            payload = try gzipDecompress(Data(payload))
        }

        guard header.serialization == .json else {
            throw VolcProtocolError.invalidPayload
        }

        guard let json = try JSONSerialization.jsonObject(with: Data(payload)) as? [String: Any] else {
            throw VolcProtocolError.invalidPayload
        }

        let resultObj = json["result"] as? [String: Any]
        let text = resultObj?["text"] as? String ?? json["text"] as? String ?? ""
        var utterances: [VolcUtterance] = []

        let uttsSource = resultObj?["utterances"] as? [[String: Any]]
            ?? json["utterances"] as? [[String: Any]]
        if let utts = uttsSource {
            utterances = utts.map { u in
                VolcUtterance(
                    text: u["text"] as? String ?? "",
                    definite: u["definite"] as? Bool ?? false
                )
            }
        }

        return VolcServerResponse(
            header: header,
            result: VolcASRResult(text: text, utterances: utterances)
        )
    }

    // MARK: - Gzip

    private static func processStream(
        operation: compression_stream_operation,
        source: Data
    ) -> Data? {
        let pageSize = 16384
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: pageSize)
        defer { dstBuffer.deallocate() }

        let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { streamPtr.deallocate() }

        let initStatus = compression_stream_init(streamPtr, operation, COMPRESSION_ZLIB)
        guard initStatus == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(streamPtr) }

        return source.withUnsafeBytes { (srcPointer: UnsafeRawBufferPointer) -> Data? in
            guard let srcBase = srcPointer.baseAddress else { return nil }

            streamPtr.pointee.src_ptr = srcBase.assumingMemoryBound(to: UInt8.self)
            streamPtr.pointee.src_size = source.count

            var output = Data()

            repeat {
                streamPtr.pointee.dst_ptr = dstBuffer
                streamPtr.pointee.dst_size = pageSize

                let status = compression_stream_process(streamPtr, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))

                let produced = pageSize - streamPtr.pointee.dst_size
                if produced > 0 {
                    output.append(dstBuffer, count: produced)
                }

                if status == COMPRESSION_STATUS_END { break }
                if status == COMPRESSION_STATUS_ERROR { return nil }
            } while true

            return output
        }
    }

    static func gzipCompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        guard let result = processStream(operation: COMPRESSION_STREAM_ENCODE, source: data) else {
            throw VolcProtocolError.compressionFailed
        }
        return result
    }

    static func gzipDecompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        guard let result = processStream(operation: COMPRESSION_STREAM_DECODE, source: data) else {
            throw VolcProtocolError.decompressionFailed
        }
        return result
    }
}
