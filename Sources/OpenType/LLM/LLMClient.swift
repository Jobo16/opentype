import Foundation

/// Protocol for LLM chat completion clients.
protocol LLMClient: Sendable {
    func chat(
        systemPrompt: String,
        userMessage: String,
        config: LLMConfig
    ) async throws -> String
}

/// Configuration for an LLM provider.
struct LLMConfig: Sendable {
    let apiKey: String
    let model: String
    let baseURL: String

    static let deepseek = LLMConfig(
        apiKey: "",
        model: "deepseek-v4-flash",
        baseURL: "https://api.deepseek.com"
    )

    var isValid: Bool {
        !apiKey.isEmpty && !model.isEmpty
    }
}
