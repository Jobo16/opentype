import Foundation

/// Supported ASR providers. OpenType is cloud-only; all providers require network access.
enum ASRProvider: String, CaseIterable, Sendable {
    case volcano = "volcano"
    // Future: deepgram, openai, etc.
}

/// Defines what credentials a provider needs for the Settings UI.
struct CredentialField: Sendable {
    let key: String
    let label: String
    let placeholder: String
    let isSecure: Bool
    let isOptional: Bool
    let defaultValue: String
    let options: [FieldOption]

    init(
        key: String,
        label: String,
        placeholder: String = "",
        isSecure: Bool = false,
        isOptional: Bool = false,
        defaultValue: String = "",
        options: [FieldOption] = []
    ) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.isOptional = isOptional
        self.defaultValue = defaultValue
        self.options = options
    }
}

struct FieldOption: Sendable {
    let value: String
    let label: String
}

/// Protocol that every ASR provider config must implement.
protocol ASRProviderConfig: Sendable {
    static var provider: ASRProvider { get }
    var provider: ASRProvider { get }
    static var displayName: String { get }
    static var credentialFields: [CredentialField] { get }

    init?(credentials: [String: String])
    func toCredentials() -> [String: String]
    var isValid: Bool { get }
}

/// Capabilities reported by the registry for each provider.
struct ASRCapabilities: Sendable {
    let available: Bool
    let supportsStreaming: Bool
}
