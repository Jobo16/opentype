import Foundation
import Security

/// Dual-storage credential service: Keychain for secure fields, JSON for non-secure.
enum CredentialService {

    private static let lock = NSLock()
    private static var cachedJSON: [String: Any]?
    private static let keychainService = "com.opentype.secure"
    private static let jsonFileName = "config.json"

    private static var configURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(jsonFileName)
    }

    // MARK: - JSON persistence (non-secure fields)

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

    // MARK: - ASR Credentials (provider-aware)

    private static func storageKey(for provider: ASRProvider) -> String {
        "asr_\(provider.rawValue)"
    }

    static func saveASRCredentials(for provider: ASRProvider, values: [String: String]) throws {
        lock.lock()
        defer { lock.unlock() }

        var dict = _loadJSONUnlocked()
        let key = storageKey(for: provider)
        let fields = ASRProviderRegistry.configType(for: provider)?.credentialFields ?? []
        let split = splitCredentials(values, using: fields)

        // Secure → Keychain
        if split.secure.isEmpty {
            _ = deleteSecure(account: key)
        } else {
            try saveSecureValues(split.secure, account: key)
        }

        // Non-secure → JSON
        if split.plaintext.isEmpty {
            dict.removeValue(forKey: key)
        } else {
            dict[key] = split.plaintext
        }
        try saveJSON(dict)
    }

    static func loadASRCredentials(for provider: ASRProvider) -> [String: String]? {
        let dict = loadJSON()
        let key = storageKey(for: provider)
        let plaintext = dict[key] as? [String: String] ?? [:]
        let secure = loadSecureValues(account: key)
        let merged = plaintext.merging(secure) { _, secure in secure }
        return merged.isEmpty ? nil : merged
    }

    static func loadASRConfig(for provider: ASRProvider) -> (any ASRProviderConfig)? {
        guard let configType = ASRProviderRegistry.configType(for: provider) else { return nil }
        if let values = loadASRCredentials(for: provider) {
            return configType.init(credentials: values)
        }
        // Fall back to defaults
        let defaults: [String: String] = Dictionary(
            uniqueKeysWithValues: configType.credentialFields.compactMap { field -> (String, String)? in
                guard !field.defaultValue.isEmpty else { return nil }
                return (field.key, field.defaultValue)
            }
        )
        return configType.init(credentials: defaults)
    }

    // MARK: - Hotkey (UserDefaults)

    private static let hotkeyKey = "ot_hotkey"

    static var hotkeyString: String {
        get { UserDefaults.standard.string(forKey: hotkeyKey) ?? "Option+Space" }
        set { UserDefaults.standard.set(newValue, forKey: hotkeyKey) }
    }

    // MARK: - Keychain helpers

    private static func keychainQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static func saveSecureData(_ data: Data, account: String) throws {
        let query = keychainQuery(account: account)
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let s = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            guard s == errSecSuccess else { throw CredentialError.keychainSaveFailed(s) }
        case errSecItemNotFound:
            var addQuery = query
            addQuery.merge(attrs) { _, new in new }
            let s = SecItemAdd(addQuery as CFDictionary, nil)
            guard s == errSecSuccess else { throw CredentialError.keychainSaveFailed(s) }
        default:
            throw CredentialError.keychainSaveFailed(status)
        }
    }

    private static func loadSecureData(account: String) -> Data? {
        var query = keychainQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    private static func deleteSecure(account: String) -> Bool {
        let status = SecItemDelete(keychainQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func saveSecureValues(_ values: [String: String], account: String) throws {
        let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        try saveSecureData(data, account: account)
    }

    private static func loadSecureValues(account: String) -> [String: String] {
        guard let data = loadSecureData(account: account),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }

    // MARK: - Split credentials by security level

    private static func splitCredentials(
        _ values: [String: String],
        using fields: [CredentialField]
    ) -> (plaintext: [String: String], secure: [String: String]) {
        let secureKeys = Set(fields.filter(\.isSecure).map(\.key))
        guard !secureKeys.isEmpty else { return (values, [:]) }

        var plaintext: [String: String] = [:]
        var secure: [String: String] = [:]
        for (key, value) in values {
            if secureKeys.contains(key) {
                if !value.isEmpty { secure[key] = value }
            } else if !value.isEmpty {
                plaintext[key] = value
            }
        }
        return (plaintext, secure)
    }

    // MARK: - Internal unlocked helpers

    private static func _loadJSONUnlocked() -> [String: Any] {
        if let cached = cachedJSON { return cached }
        guard let data = try? Data(contentsOf: configURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        cachedJSON = dict
        return dict
    }
}

enum CredentialError: Error, LocalizedError {
    case keychainSaveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed(let status): return "Keychain save failed (OSStatus \(status))"
        }
    }
}
