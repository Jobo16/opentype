import Foundation

/// Events emitted by an ASR session.
enum RecognitionEvent: Sendable {
    case transcript(RecognitionTranscript)
    case error(Error)
    case completed
}

/// A snapshot of the current transcription state.
struct RecognitionTranscript: Sendable, Equatable {
    /// Server-confirmed final segments.
    let confirmedSegments: [String]
    /// Current in-progress partial text.
    let partialText: String
    /// Full authoritative text (available on final).
    let authoritativeText: String
    /// Whether this is the final result for the session.
    let isFinal: Bool

    static let empty = RecognitionTranscript(
        confirmedSegments: [],
        partialText: "",
        authoritativeText: "",
        isFinal: false
    )

    /// Display text: confirmed segments + current partial.
    var displayText: String {
        (confirmedSegments + (partialText.isEmpty ? [] : [partialText])).joined()
    }
}

/// Options passed to an ASR request.
struct ASRRequestOptions: Sendable {
    var hotwords: [String] = []
    var boostingTableID: String?
    var contextHistoryLength: Int = 0
}

/// Protocol that all ASR clients must implement.
///
/// Lifecycle: connect → sendAudio (N times) → endAudio → receive events → disconnect.
@preconcurrency
protocol SpeechRecognizer: AnyObject, Sendable {
    /// Stream of recognition events (transcripts, errors, completion).
    nonisolated var events: AsyncStream<RecognitionEvent> { get }

    /// Open a connection to the ASR service.
    func connect(config: any ASRProviderConfig, options: ASRRequestOptions) async throws

    /// Send a chunk of raw PCM audio data.
    func sendAudio(_ data: Data) async throws

    /// Signal that all audio has been sent; server will finalize results.
    func endAudio() async throws

    /// Tear down the connection.
    nonisolated func disconnect()
}
