@preconcurrency import AVFoundation
import os

/// Captures 16 kHz mono Int16 PCM audio from the system default input device.
actor AudioCaptureEngine {

    private let logger = Logger(subsystem: "com.opentype.audio", category: "Capture")

    private static let sampleRate: Double = 16000
    private static let channels: AVAudioChannelCount = 1

    /// Target format: 16 kHz mono Int16 interleaved — matches Volcano ASR `bits: 16`.
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: sampleRate,
        channels: channels,
        interleaved: true
    )!

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var isCapturing = false

    /// Buffered PCM bytes (Int16, 16 kHz mono).
    private var recordedBytes = Data()

    private var _onAudioLevel: (@Sendable (Float) -> Void)?

    func setOnAudioLevel(_ handler: @escaping @Sendable (Float) -> Void) {
        self._onAudioLevel = handler
    }

    /// Consume and return the next `byteCount` bytes from the buffer.
    func consumeBytes(count: Int) -> Data? {
        guard recordedBytes.count >= count else { return nil }
        let chunk = recordedBytes.prefix(count)
        recordedBytes.removeFirst(count)
        return chunk
    }

    /// Returns the full remaining buffer.
    func flushRemainingBytes() -> Data {
        let remaining = recordedBytes
        recordedBytes.removeAll()
        return remaining
    }

    // MARK: - Start / Stop

    func start() async throws {
        guard !isCapturing else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)

        let converter = AVAudioConverter(from: hwFormat, to: Self.targetFormat)!

        // Buffer for accumulating Int16 bytes from the converter
        var int16Buffer = Data()

        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, time in
            Task { [weak self] in
                guard let self else { return }
                guard await self.isCapturingActive else { return }

                let frameCount = AVAudioFrameCount(buffer.frameLength)
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: Self.targetFormat,
                    frameCapacity: frameCount
                ) else { return }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                guard status == .haveData else { return }

                // Extract raw Int16 bytes
                if let channelData = convertedBuffer.int16ChannelData {
                    let count = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                    let bytes = Data(bytes: channelData[0], count: count)
                    await self.appendAudioBytes(bytes)
                }
            }
        }

        try engine.start()
        self.audioEngine = engine
        self.inputNode = input
        self.isCapturing = true
        self.recordedBytes = Data()
        DebugLog.log("AudioCaptureEngine started (Int16 16kHz mono)")
    }

    var isCapturingActive: Bool { isCapturing }

    func stop() -> Data? {
        guard isCapturing else { return nil }
        isCapturing = false
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        DebugLog.log("AudioCaptureEngine stopped (\(recordedBytes.count) bytes)")
        // Save recorded audio to file for debugging
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("opentype_recording.pcm")
        try? recordedBytes.write(to: url)
        DebugLog.log("Saved recording to \(url.path) (\(recordedBytes.count) bytes)")
        let remaining = recordedBytes
        recordedBytes = Data()
        return remaining
    }

    // MARK: - Internal

    private func appendAudioBytes(_ bytes: Data) {
        recordedBytes.append(bytes)
        let sampleCount = bytes.count / 2
        guard sampleCount > 0 else { return }
        var sum: Float = 0
        bytes.withUnsafeBytes { ptr in
            let samples = ptr.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let s = Float(samples[i]) / 32768.0
                sum += s * s
            }
        }
        let rms = sqrt(sum / Float(sampleCount))
        let level = min(1.0, rms * 3.0)
        _onAudioLevel?(level)
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case formatError
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .formatError: return "Failed to create target audio format"
        case .noInputDevice: return "No audio input device available"
        }
    }
}
