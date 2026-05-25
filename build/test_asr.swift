#!/usr/bin/env swift

import Foundation

// Quick ASR test — reads credentials from config.json, sends PCM audio, gets transcript.

let configDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    .appendingPathComponent("OpenType", isDirectory: true)
let configURL = configDir.appendingPathComponent("config.json")
let pcmURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/Users/jobo/projects/OpenType/opentype/build/test_audio.pcm")

guard let configData = try? Data(contentsOf: configURL),
      let config = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
      let asrDict = config["asr_volcano"] as? [String: String],
      let appKey = asrDict["appKey"], !appKey.isEmpty,
      let accessKey = asrDict["accessKey"], !accessKey.isEmpty else {
    print("ERROR: No ASR credentials in \(configURL.path)")
    exit(1)
}

let rawResourceId = asrDict["resourceId"] ?? "volc.seedasr.sauc.duration"
let resourceId = (rawResourceId == "auto" || rawResourceId.isEmpty) ? "volc.seedasr.sauc.duration" : rawResourceId
let pcmData = try Data(contentsOf: pcmURL)
let sampleCount = pcmData.count / 4

print("=== ASR Test ===")
print("Key: \(appKey.prefix(8))... | Resource: \(resourceId) | PCM: \(sampleCount) samples (\(Double(sampleCount)/16000)s)")

// --- Binary protocol helpers ---
func makeHeader(msgType: UInt8, flags: UInt8) -> Data {
    Data([0x11, (msgType << 4) | (flags & 0x0F), 0x10, 0x00])
}

func wrapMessage(header: Data, payload: Data) -> Data {
    var msg = header
    var size = UInt32(payload.count).bigEndian
    msg.append(Data(bytes: &size, count: 4))
    msg.append(payload)
    return msg
}

func makeAudioPacket(audioData: Data, isLast: Bool) -> Data {
    let flags: UInt8 = isLast ? 0x02 : 0x00  // lastPacketNoSequence vs noSequence
    let header = makeHeader(msgType: 0x02, flags: flags)
    return wrapMessage(header: header, payload: audioData)
}

// --- WebSocket ---
let semaphore = DispatchSemaphore(value: 0)
var resultText = ""
var errorMsg = ""

let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
var request = URLRequest(url: endpoint)
request.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")

let session = URLSession(configuration: .default)
let task = session.webSocketTask(with: request)
task.resume()

// Handshake payload
let handshake: [String: Any] = [
    "user": ["uid": UUID().uuidString],
    "audio": ["format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1],
    "request": [
        "model_name": "bigmodel",
        "enable_punc": true,
        "enable_ddc": true,
        "show_utterances": true,
        "result_type": "full",
    ]
]
let handshakePayload = try JSONSerialization.data(withJSONObject: handshake)
let handshakeMsg = wrapMessage(
    header: makeHeader(msgType: 0x01, flags: 0x00),
    payload: handshakePayload
)

print("Sending handshake...")
task.send(.data(handshakeMsg)) { err in
    if let err { errorMsg = "Handshake: \(err.localizedDescription)"; semaphore.signal(); return }

    print("Handshake OK, sending \(pcmData.count) bytes audio...")
    var offset = 0
    let chunkBytes = 3200 * 4  // 3200 samples × 4 bytes

    func sendNext() {
        if offset >= pcmData.count {
            print("Audio done, sending end...")
            task.send(.data(makeAudioPacket(audioData: Data(), isLast: true))) { err in
                if let err { errorMsg = "EndAudio: \(err.localizedDescription)"; semaphore.signal(); return }
                print("Waiting for server response...")
                listen()
            }
            return
        }
        let end = min(offset + chunkBytes, pcmData.count)
        let chunk = pcmData[offset..<end]
        offset = end
        task.send(.data(makeAudioPacket(audioData: chunk, isLast: false))) { err in
            if let err { errorMsg = "Audio@\(offset): \(err.localizedDescription)"; semaphore.signal(); return }
            sendNext()
        }
    }

    func listen() {
        task.receive { result in
            switch result {
            case .success(.data(let data)):
                guard data.count >= 2 else { listen(); return }
                let msgType = (data[1] >> 4) & 0x0F
                if msgType == 0x0F {
                    // Error
                    let start = data.count > 8 ? 8 : 4
                    if let json = try? JSONSerialization.jsonObject(with: data[start...]) as? [String: Any] {
                        errorMsg = "Server error: code=\(json["code"] ?? "?"), msg=\(json["message"] ?? "?")"
                    } else {
                        errorMsg = "Server error (0x0F), \(data.count) bytes"
                    }
                    semaphore.signal()
                    return
                }
                // Try to extract text
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? [String: Any],
                   let text = result["text"] as? String, !text.isEmpty {
                    resultText = text
                    print("  → \"\(text)\"")
                }
                listen()
            case .success(.string(let s)):
                print("String: \(s)")
                listen()
            case .failure(let err):
                if errorMsg.isEmpty { errorMsg = "Recv: \(err.localizedDescription)" }
                semaphore.signal()
            }
        }
    }

    sendNext()
}

// 15s timeout
DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
    if errorMsg.isEmpty && resultText.isEmpty { errorMsg = "Timeout 15s"; semaphore.signal() }
}

semaphore.wait()

print("\n=== RESULT ===")
if !resultText.isEmpty {
    print("✓ SUCCESS: \"\(resultText)\"")
} else if !errorMsg.isEmpty {
    print("✗ ERROR: \(errorMsg)")
} else {
    print("(empty — sine tone may produce no text, connection was OK)")
}
task.cancel(with: .normalClosure, reason: nil)
