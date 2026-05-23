@preconcurrency import AVFoundation
import os

/// Captures 16 kHz mono PCM audio from the system default input device.
///
/// Audio format: 16 kHz, mono, Float32 samples (normalised to -1…1).
/// The `onAudioLevel` callback fires ~every 50 ms for UI metering.
actor AudioCaptureEngine {

    private let logger = Logger(subsystem: "com.opentype.audio", category: "Capture")

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var isCapturing = false

    /// Buffered PCM samples (Float32, 16 kHz mono).
    private var recordedSamples: [Float] = []

    /// RMS audio level in 0…1, emitted every ~50 ms.
    private var _onAudioLevel: (@Sendable (Float) -> Void)?

    func setOnAudioLevel(_ handler: @escaping @Sendable (Float) -> Void) {
        self._onAudioLevel = handler
    }

    /// Returns the full recorded buffer after capture stops.
    func getRecordedAudio() -> [Float] {
        recordedSamples
    }

    // MARK: - Start / Stop

    func start() async throws {
        guard !isCapturing else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)

        // Target format: 16 kHz mono Float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        // Install a tap that converts to 16 kHz mono on the fly.
        let converter = AVAudioConverter(from: hwFormat, to: targetFormat)!
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, time in
            Task { [weak self] in
                guard let self else { return }
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: targetBufferFormat,
                    frameCapacity: AVAudioFrameCount(buffer.frameLength)
                )!
                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                guard status == .haveData else { return }
                let samples = Array(
                    UnsafeBufferPointer(
                        start: convertedBuffer.floatChannelData![0],
                        count: Int(convertedBuffer.frameLength)
                    )
                )
                await self.processSamples(samples)
            }
        }

        try engine.start()
        self.audioEngine = engine
        self.inputNode = input
        self.isCapturing = true
        self.recordedSamples = []
        logger.info("Capture started (hw format: \(hwFormat), target: 16 kHz mono)")
    }

    // Keep a reference so the converter closure can access it.
    private let targetBufferFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    func stop() {
        guard isCapturing else { return }
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isCapturing = false
        logger.info("Capture stopped (\(self.recordedSamples.count) samples)")
    }

    // MARK: - Internal

    private func processSamples(_ samples: [Float]) {
        recordedSamples.append(contentsOf: samples)
        // Compute RMS for level metering (~50 ms window at 16 kHz = 800 samples).
        let windowSize = min(800, samples.count)
        guard windowSize > 0 else { return }
        let slice = samples.suffix(windowSize)
        let rms = sqrt(slice.reduce(0.0) { $0 + $1 * $1 } / Float(windowSize))
        let level = min(1.0, rms * 3.0)  // scale for perceptual loudness
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
