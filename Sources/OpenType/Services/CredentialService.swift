import Foundation

/// Credential storage service. Pure JSON — no Keychain, no permission prompts.
enum CredentialService {

    private static let lock = NSLock()
    private static var cachedJSON: [String: Any]?
    private static let jsonFileName = "config.json"

    private static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(jsonFileName)
    }

    // MARK: - JSON persistence

    private static func loadJSON() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedJSON { return cached }
        guard let data = try? Data(contentsOf: configURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        cachedJSON = dict
        return dict
    }

    private static func saveJSON(_ dict: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        try data.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configURL.path
        )
        cachedJSON = dict
    }

    // MARK: - ASR Credentials

    private static func storageKey(for provider: ASRProvider) -> String {
        "asr_\(provider.rawValue)"
    }

    static func saveASRCredentials(for provider: ASRProvider, values: [String: String]) throws {
        lock.lock()
        defer { lock.unlock() }
        var dict = _loadJSONUnlocked()
        let key = storageKey(for: provider)
        let cleaned = values.filter { !$0.value.isEmpty }
        if cleaned.isEmpty {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = cleaned
        }
        try saveJSON(dict)
    }

    static func loadASRCredentials(for provider: ASRProvider) -> [String: String]? {
        let dict = loadJSON()
        let key = storageKey(for: provider)
        let values = dict[key] as? [String: String] ?? [:]
        return values.isEmpty ? nil : values
    }

    static func loadASRConfig(for provider: ASRProvider) -> (any ASRProviderConfig)? {
        guard let configType = ASRProviderRegistry.configType(for: provider) else { return nil }
        if let values = loadASRCredentials(for: provider) {
            return configType.init(credentials: values)
        }
        let defaults: [String: String] = Dictionary(
            uniqueKeysWithValues: configType.credentialFields.compactMap { field -> (String, String)? in
                guard !field.defaultValue.isEmpty else { return nil }
                return (field.key, field.defaultValue)
            }
        )
        return configType.init(credentials: defaults)
    }

    // MARK: - LLM Config

    private static let llmKey = "llm_config"

    static func saveLLMConfig(_ config: LLMConfig) throws {
        lock.lock()
        defer { lock.unlock() }
        var dict = _loadJSONUnlocked()
        dict[llmKey] = [
            "apiKey": config.apiKey,
            "model": config.model,
            "baseURL": config.baseURL,
        ]
        try saveJSON(dict)
    }

    static func loadLLMConfig() -> LLMConfig {
        let dict = loadJSON()
        let llmDict = dict[llmKey] as? [String: String] ?? [:]
        return LLMConfig(
            apiKey: llmDict["apiKey"] ?? "",
            model: llmDict["model"] ?? "deepseek-v4-flash",
            baseURL: llmDict["baseURL"] ?? "https://api.deepseek.com"
        )
    }

    // MARK: - LLM enabled flag

    private static let llmEnabledKey = "ot_llm_enabled"

    static var isLLMEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: llmEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: llmEnabledKey) }
    }

    // MARK: - Hotkey (UserDefaults)

    private static let hotkeyKey = "ot_hotkey"

    static var hotkeyString: String {
        get { UserDefaults.standard.string(forKey: hotkeyKey) ?? "Option+Space" }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyKey) }
    }

    // MARK: - Internal

    private static func _loadJSONUnlocked() -> [String: Any] {
        if let cached = cachedJSON { return cached }
        guard let data = try? Data(contentsOf: configURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        cachedJSON = dict
        return dict
    }
}
