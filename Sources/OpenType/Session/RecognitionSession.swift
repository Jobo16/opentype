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

    /// Stream of phase changes for the UI overlay. Resets each session.
    private var _phaseEvents: AsyncStream<Phase>?
    private var _phaseContinuation: AsyncStream<Phase>.Continuation?

    var phaseEvents: AsyncStream<Phase> {
        if let existing = _phaseEvents { return existing }
        let (stream, continuation) = AsyncStream<Phase>.makeStream()
        self._phaseContinuation = continuation
        self._phaseEvents = stream
        return stream
    }

    nonisolated func setAudioLevelHandler(_ handler: @escaping @Sendable (Float) -> Void) {
        Task { @Sendable in
            await self.audioEngine.setOnAudioLevel(handler)
        }
    }

    private(set) var lastRawText: String = ""
    private(set) var lastResult: String = ""

    // MARK: - Pipeline

    func start(config: any ASRProviderConfig, options: ASRRequestOptions? = nil) async {
        DebugLog.log("=== Session.start() called, phase=\(String(describing: self.phase)) ===")
        guard phase == .idle || phase == .done else {
            DebugLog.log("start() BLOCKED: phase is \(String(describing: self.phase))")
            return
        }

        // Reset phaseEvents stream for this session
        _phaseContinuation?.finish()
        _phaseEvents = nil
        _phaseContinuation = nil

        setPhase(.recording)

        let hotwords = HotwordStore.shared.getAllWords()
        var effectiveOptions = options ?? ASRRequestOptions()
        if !hotwords.isEmpty {
            effectiveOptions.hotwords = hotwords
        }

        do {
            DebugLog.log("Step 1: Starting audio capture...")
            try await audioEngine.start()
            DebugLog.log("Step 1: Audio capture started")

            DebugLog.log("Step 2: Connecting ASR client (provider=\(String(describing: config.provider)))...")
            guard let client = ASRProviderRegistry.makeClient(for: config.provider) else {
                setPhase(.error("Unsupported ASR provider"))
                return
            }
            self.transcriber = client
            try await client.connect(config: config, options: effectiveOptions)
            DebugLog.log("Step 2: ASR connected, hotwords=\(hotwords.count)")

            // 3. Stream audio → ASR until capture stops.
            setPhase(.recording)
            DebugLog.log("Step 3: Streaming audio to ASR...")
            try await streamAudioToASR(client: client)
            DebugLog.log("Step 3: Audio stream ended, flushing remaining...")

            // 4. Flush any remaining audio data.
            let remaining = await audioEngine.flushRemainingBytes()
            if remaining.count > 100 {
                try await client.sendAudio(remaining)
                DebugLog.log("Flushed \(remaining.count) remaining bytes")
            }

            // 5. Signal end of audio.
            DebugLog.log("Step 5: Sending endAudio...")
            try await client.endAudio()
            DebugLog.log("Step 5: endAudio sent")

            // 6. Wait for final transcript.
            setPhase(.transcribing)
            DebugLog.log("Step 6: Waiting for final transcript...")
            let finalText = await waitForFinalTranscript(client: client)
            DebugLog.log("Step 6: Transcript received: \(finalText.count) chars")
            await client.disconnect()
            self.transcriber = nil

            guard !finalText.isEmpty else {
                setPhase(.done)
                return
            }

            self.lastRawText = finalText

            // 7. Optional LLM post-processing.
            let processedText: String
            if CredentialService.isLLMEnabled {
                setPhase(.optimizing)
                processedText = await optimizeWithLLM(finalText)
            } else {
                processedText = finalText
            }

            // 8. Inject text into the active app.
            setPhase(.injecting)
            try await injector.inject(processedText)
            self.lastResult = processedText
            setPhase(.done)

        } catch {
            DebugLog.log("Pipeline FAILED: \(error.localizedDescription)")
            setPhase(.error(error.localizedDescription))
        }
    }

    func cancel() async {
        _ = await audioEngine.stop()
        await transcriber?.disconnect()
        self.transcriber = nil
        _phaseContinuation?.finish()
        _phaseEvents = nil
        _phaseContinuation = nil
        setPhase(.idle)
    }

    /// Stop audio capture only — the pipeline loop will exit and continue to transcribe/inject.
    func stopRecording() async {
        _ = await audioEngine.stop()
    }

    // MARK: - Helpers

    private func streamAudioToASR(client: any SpeechRecognizer) async throws {
        let chunkBytes = 6400  // 3200 samples × 2 bytes (Int16) = 200ms at 16kHz
        var totalBytes = 0
        var chunkCount = 0
        while await phase == .recording {
            guard let data = await audioEngine.consumeBytes(count: chunkBytes) else {
                let active = await audioEngine.isCapturingActive
                if !active {
                    DebugLog.log("Audio stopped, exiting stream (sent \(totalBytes) bytes, \(chunkCount) chunks)")
                    break
                }
                try await Task.sleep(nanoseconds: 20_000_000)
                continue
            }
            // Check audio level of this chunk
            let rms = computeRMS(data)
            if chunkCount % 50 == 0 {  // log every ~1 second
                DebugLog.log("Chunk \(chunkCount): \(data.count) bytes, rms=\(String(format:"%.4f",rms)) total=\(totalBytes)")
            }
            try await client.sendAudio(data)
            totalBytes += data.count
            chunkCount += 1
        }
        DebugLog.log("streamAudioToASR done: \(totalBytes) bytes, \(chunkCount) chunks")
    }

    private func computeRMS(_ data: Data) -> Float {
        let count = data.count / 2  // Int16 = 2 bytes per sample
        guard count > 0 else { return 0 }
        var sum: Float = 0
        return data.withUnsafeBytes { ptr in
            let samples = ptr.bindMemory(to: Int16.self)
            for i in 0..<count {
                let s = Float(samples[i]) / 32768.0
                sum += s * s
            }
            return sqrt(sum / Float(count))
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
        _phaseContinuation?.yield(newPhase)
    }

    private func optimizeWithLLM(_ text: String) async -> String {
        let config = CredentialService.loadLLMConfig()
        guard config.isValid else {
            logger.warning("LLM not configured, using raw ASR text")
            return text
        }
        let client = DeepSeekClient()
        let hotwords = HotwordStore.shared.getAllWords()
        let prompt = PromptBuilder.buildPrompt(hotwords: hotwords)
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
