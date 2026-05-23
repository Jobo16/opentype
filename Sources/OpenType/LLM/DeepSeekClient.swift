import Foundation
import os

/// OpenAI-compatible chat completion client. Works with DeepSeek and any compatible API.
struct DeepSeekClient: LLMClient {

    private let logger = Logger(subsystem: "com.opentype.llm", category: "DeepSeek")

    func chat(
        systemPrompt: String,
        userMessage: String,
        config: LLMConfig
    ) async throws -> String {
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage],
            ],
            "temperature": 0.1,
            "max_tokens": 4096,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            logger.error("API error \(http.statusCode): \(detail)")
            throw LLMError.apiError(statusCode: http.statusCode, detail: detail)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.invalidResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LLMError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, detail: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid API response"
        case .apiError(let code, let detail): return "API error \(code): \(detail)"
        case .notConfigured: return "LLM not configured"
        }
    }
}
