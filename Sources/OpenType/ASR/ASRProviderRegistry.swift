import Foundation

/// Maps ASR providers to their config types and client factories.
enum ASRProviderRegistry {

    struct Entry: Sendable {
        let capabilities: ASRCapabilities
        let createClient: @Sendable () -> any SpeechRecognizer
    }

    private static let all: [ASRProvider: Entry] = [
        .volcano: Entry(
            capabilities: ASRCapabilities(available: true, supportsStreaming: true),
            createClient: { VolcASRClient() }
        ),
    ]

    /// Returns the registry entry for a provider, or nil if unknown.
    static func entry(for provider: ASRProvider) -> Entry? {
        all[provider]
    }

    /// Create a new client instance for the given provider.
    static func makeClient(for provider: ASRProvider) -> (any SpeechRecognizer)? {
        all[provider]?.createClient()
    }

    /// Whether a provider supports streaming recognition.
    static func supportsStreaming(_ provider: ASRProvider) -> Bool {
        all[provider]?.capabilities.supportsStreaming ?? false
    }
}
