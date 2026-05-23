import Foundation
import os

enum VolcASRError: Error, LocalizedError {
    case unsupportedConfig
    case serverRejected(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unsupportedConfig: return "VolcASRClient requires VolcanoASRConfig"
        case .serverRejected(let code, let message): return message ?? "HTTP \(code)"
        }
    }
}

/// Volcano Engine (火山引擎) streaming ASR client.
///
/// Uses the bigmodel_async WebSocket endpoint with the custom binary frame protocol.
/// Sends 16kHz mono PCM audio; receives streaming partial results and a final response.
actor VolcASRClient: SpeechRecognizer {

    private static let endpoint =
        URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!

    private let logger = Logger(subsystem: "com.opentype.asr", category: "VolcASRClient")

    // MARK: - State

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Never>?
    nonisolated(unsafe) private var eventContinuation: AsyncStream<RecognitionEvent>.Continuation?
    nonisolated(unsafe) private var _events: AsyncStream<RecognitionEvent>?
    private var audioPacketCount = 0
    private var didRequestEnd = false
    private var lastTranscript: RecognitionTranscript = .empty
    private var localConfirmedSegments: [String] = []
    private var lastPartialText = ""
    private var lastServerConfirmedCount = 0

    nonisolated var events: AsyncStream<RecognitionEvent> {
        if let existing = _events { return existing }
        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        self._events = stream
        self.eventContinuation = continuation
        return stream
    }

    // MARK: - Connect

    func connect(config: any ASRProviderConfig, options: ASRRequestOptions = ASRRequestOptions()) async throws {
        guard let volcConfig = config as? VolcanoASRConfig else {
            throw VolcASRError.unsupportedConfig
        }

        // Ensure fresh event stream.
        let (stream, continuation) = AsyncStream<RecognitionEvent>.makeStream()
        self.eventContinuation = continuation
        self._events = stream

        let connectId = UUID().uuidString
        var request = URLRequest(url: Self.endpoint)
        request.setValue(volcConfig.appKey,    forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(volcConfig.accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(volcConfig.resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId,            forHTTPHeaderField: "X-Api-Connect-Id")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()
        self.session = session
        self.webSocketTask = task

        let payload = VolcProtocol.buildClientRequest(
            uid: volcConfig.uid,
            hotwords: options.hotwords
        )
        let header = VolcHeader(
            messageType: .fullClientRequest,
            flags: .noSequence,
            serialization: .json,
            compression: .none
        )
        let message = VolcProtocol.encodeMessage(header: header, payload: payload)

        audioPacketCount = 0
        didRequestEnd = false
        lastTranscript = .empty
        localConfirmedSegments = []
        lastPartialText = ""
        lastServerConfirmedCount = 0

        do {
            try await task.send(.data(message))
        } catch {
            throw error
        }

        startReceiveLoop()
    }

    // MARK: - Send Audio

    func sendAudio(_ data: Data) async throws {
        guard let task = webSocketTask else { return }
        let packet = VolcProtocol.encodeAudioPacket(audioData: data, isLast: false)
        try await task.send(.data(packet))
        audioPacketCount += 1
    }

    // MARK: - End Audio

    func endAudio() async throws {
        guard let task = webSocketTask else { return }
        let packet = VolcProtocol.encodeAudioPacket(audioData: Data(), isLast: true)
        didRequestEnd = true
        try await task.send(.data(packet))
    }

    // MARK: - Disconnect

    nonisolated func disconnect() {
        Task { @Sendable [weak self] in
            guard let self else { return }
            await self._disconnect()
        }
    }

    private func _disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session = nil
        eventContinuation?.finish()
        eventContinuation = nil
        _events = nil
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    guard let task = await self.webSocketTask else { break }
                    let message = try await task.receive()
                    await self.handleMessage(message)
                } catch {
                    if !Task.isCancelled {
                        let (endRequested, packetCount) = await (self.didRequestEnd, self.audioPacketCount)
                        if !endRequested && packetCount > 0 {
                            await self.emitEvent(.error(error))
                        }
                        await self.emitEvent(.completed)
                    }
                    break
                }
            }
            await self.eventContinuation?.finish()
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            let headerByte1 = data.count > 1 ? data[1] : 0
            let msgType = (headerByte1 >> 4) & 0x0F

            if msgType == 0x0F {
                if audioPacketCount == 0 {
                    do {
                        _ = try VolcProtocol.decodeServerResponse(data)
                    } catch {
                        emitEvent(.error(error))
                    }
                }
                emitEvent(.completed)
                webSocketTask?.cancel(with: .normalClosure, reason: nil)
                webSocketTask = nil
                return
            }

            do {
                let response = try VolcProtocol.decodeServerResponse(data)
                let transcript = makeTranscript(
                    from: response.result,
                    isFinal: response.header.flags == .asyncFinal
                )
                guard transcript != lastTranscript else { return }
                lastTranscript = transcript
                emitEvent(.transcript(transcript))
            } catch {
                emitEvent(.error(error))
            }

        case .string(let text):
            logger.warning("Unexpected text message: \(text)")

        @unknown default:
            break
        }
    }

    private func emitEvent(_ event: RecognitionEvent) {
        eventContinuation?.yield(event)
    }

    // MARK: - Transcript Assembly

    private func makeTranscript(from result: VolcASRResult, isFinal: Bool) -> RecognitionTranscript {
        let serverConfirmed = result.utterances
            .filter(\.definite)
            .map(\.text)
            .filter { !$0.isEmpty }
        let partialText = result.utterances
            .last(where: { !$0.definite && !$0.text.isEmpty })?.text ?? ""

        let prevServerConfirmedCount = lastServerConfirmedCount
        lastServerConfirmedCount = serverConfirmed.count

        if serverConfirmed.count > localConfirmedSegments.count {
            localConfirmedSegments = serverConfirmed
        }

        // Detect dropped partial: server started a new utterance without confirming the old one.
        if !isFinal,
           serverConfirmed.count <= prevServerConfirmedCount,
           lastPartialText.count >= 4 {
            if partialText.isEmpty {
                localConfirmedSegments.append(lastPartialText)
            } else {
                let lcp = longestCommonPrefixLength(lastPartialText, partialText)
                let ratio = Double(lcp) / Double(lastPartialText.count)
                if ratio < 0.5 {
                    localConfirmedSegments.append(lastPartialText)
                }
            }
        }

        lastPartialText = partialText

        // Guard against false promotion.
        if !partialText.isEmpty && localConfirmedSegments.count > serverConfirmed.count {
            let lastPromoted = localConfirmedSegments.last!
            let lcp = longestCommonPrefixLength(lastPromoted, partialText)
            let ratio = Double(lcp) / Double(lastPromoted.count)
            if ratio >= 0.5 {
                localConfirmedSegments.removeLast()
            }
        }

        let effectiveConfirmed = localConfirmedSegments.count > serverConfirmed.count
            ? localConfirmedSegments : serverConfirmed
        let composedText = (effectiveConfirmed + (partialText.isEmpty ? [] : [partialText])).joined()
        let authoritativeText = result.text.isEmpty ? composedText : result.text

        return RecognitionTranscript(
            confirmedSegments: effectiveConfirmed,
            partialText: partialText,
            authoritativeText: authoritativeText,
            isFinal: isFinal
        )
    }

    private func longestCommonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        var ai = a.startIndex, bi = b.startIndex
        while ai < a.endIndex, bi < b.endIndex, a[ai] == b[bi] {
            count += 1
            ai = a.index(after: ai)
            bi = b.index(after: bi)
        }
        return count
    }
}
