import Foundation
import os

/// Core state machine: idle → recording → transcribing → injecting → done.
///
/// Orchestrates AudioCaptureEngine, SpeechRecognizer, and TextInjectionEngine.
actor RecognitionSession {

    enum Phase: Sendable {
        case idle
        case recording
        case transcribing
        case optimizing
        case injecting
        case done
        case error(String)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording),
                 (.transcribing, .transcribing), (.optimizing, .optimizing),
                 (.injecting, .injecting),
                 (.done, .done): return true
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    private let logger = Logger(subsystem: "com.opentype.session", category: "Session")

    private let audioEngine = AudioCaptureEngine()
    private var transcriber: (any SpeechRecognizer)?
    private let injector = TextInjectionEngine()

    private(set) var phase: Phase = .idle
    private var eventContinuation: AsyncStream<Phase>.Continuation?
    private var _phaseEvents: AsyncStream<Phase>?

    /// Stream of phase changes for the UI overlay.
    var phaseEvents: AsyncStream<Phase> {
        if let existing = _phaseEvents { return existing }
        let (stream, continuation) = AsyncStream<Phase>.makeStream()
        self.eventContinuation = continuation
        self._phaseEvents = stream
        return stream
    }

    /// Audio level for UI metering.
    nonisolated func setAudioLevelHandler(_ handler: @escaping @Sendable (Float) -> Void) {
        Task { @Sendable in
            await self.audioEngine.setOnAudioLevel(handler)
        }
    }

    /// The final transcribed text after injection.
    private(set) var lastResult: String = ""

    // MARK: - Pipeline

    func start(config: any ASRProviderConfig, options: ASRRequestOptions = ASRRequestOptions()) async {
        guard phase == .idle || phase == .done else { return }
        setPhase(.recording)

        do {
            // 1. Start audio capture.
            try await audioEngine.start()

            // 2. Connect ASR client.
            guard let client = ASRProviderRegistry.makeClient(for: config.provider) else {
                setPhase(.error("Unsupported ASR provider"))
                return
            }
            self.transcriber = client
            try await client.connect(config: config, options: options)

            // 3. Stream audio → ASR until capture stops.
            setPhase(.recording)
            try await streamAudioToASR(client: client)

            // 4. Signal end of audio.
            try await client.endAudio()

            // 5. Wait for final transcript.
            setPhase(.transcribing)
            let finalText = await waitForFinalTranscript(client: client)
            await client.disconnect()
            self.transcriber = nil

            guard !finalText.isEmpty else {
                setPhase(.done)
                return
            }

            // 6. Optional LLM post-processing.
            let processedText: String
            if CredentialService.isLLMEnabled {
                setPhase(.optimizing)
                processedText = await optimizeWithLLM(finalText)
            } else {
                processedText = finalText
            }

            // 7. Inject text into the active app.
            setPhase(.injecting)
            try await injector.inject(processedText)
            self.lastResult = processedText
            setPhase(.done)

        } catch {
            logger.error("Pipeline failed: \(error.localizedDescription)")
            setPhase(.error(error.localizedDescription))
        }
    }

    func cancel() async {
        await audioEngine.stop()
        await transcriber?.disconnect()
        self.transcriber = nil
        setPhase(.idle)
    }

    // MARK: - Helpers

    private func streamAudioToASR(client: any SpeechRecognizer) async throws {
        // Send audio in 200 ms chunks (16 kHz × 0.2 s = 3200 samples = 6400 bytes Float32 → 6400 raw).
        let chunkSize = 3200  // samples
        while await phase == .recording {
            let samples = await audioEngine.getRecordedAudio()
            guard samples.count >= chunkSize else {
                try await Task.sleep(nanoseconds: 20_000_000)  // 20 ms
                continue
            }
            // Send the oldest unsent chunk.
            let chunk = Array(samples.prefix(chunkSize))
            let data = chunk.withUnsafeBytes { Data($0) }
            try await client.sendAudio(data)
        }
    }

    private func waitForFinalTranscript(client: any SpeechRecognizer) async -> String {
        var finalText = ""
        for await event in client.events {
            switch event {
            case .transcript(let t):
                if t.isFinal {
                    finalText = t.authoritativeText.isEmpty ? t.displayText : t.authoritativeText
                }
            case .error(let error):
                logger.error("ASR error: \(error.localizedDescription)")
                return ""
            case .completed:
                return finalText
            }
        }
        return finalText
    }

    private func setPhase(_ newPhase: Phase) {
        self.phase = newPhase
        eventContinuation?.yield(newPhase)
    }

    private func optimizeWithLLM(_ text: String) async -> String {
        let config = CredentialService.loadLLMConfig()
        guard config.isValid else {
            logger.warning("LLM not configured, using raw ASR text")
            return text
        }
        let client = DeepSeekClient()
        let prompt = PromptBuilder.buildPrompt()
        do {
            let result = try await client.chat(systemPrompt: prompt, userMessage: text, config: config)
            guard !result.isEmpty else { return text }
            logger.info("LLM optimized: \(text.count) → \(result.count) chars")
            return result
        } catch {
            logger.error("LLM failed: \(error.localizedDescription), using raw text")
            return text
        }
    }
}
