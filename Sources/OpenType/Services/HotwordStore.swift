import Foundation
import os

/// Persistent hotword store — JSON file at ~/Library/Application Support/OpenType/hotwords.json.
final class HotwordStore: Sendable {

    static let shared = HotwordStore()

    private let logger = Logger(subsystem: "com.opentype.hotword", category: "HotwordStore")
    private let lock = NSLock()
    private let maxEntries = 500
    private static let fileName = "hotwords.json"

    // MARK: - Data Model

    struct Entry: Codable, Identifiable, Sendable {
        let id: UUID
        var word: String
        var addedAt: Date
        var source: Source

        enum Source: String, Codable, Sendable {
            case manual
            case learned
        }

        init(word: String, source: Source = .manual) {
            self.id = UUID()
            self.word = word.trimmingCharacters(in: .whitespacesAndNewlines)
            self.addedAt = Date()
            self.source = source
        }
    }

    // MARK: - File URL

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("OpenType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    // MARK: - Read / Write

    private func loadAll() -> [Entry] {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries
    }

    private func saveAll(_ entries: [Entry]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(entries)
        try data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Public API

    func getAll() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return loadAll()
    }

    func getAllWords() -> [String] {
        getAll().map(\.word)
    }

    func add(_ word: String, source: Entry.Source = .manual) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let cleaned = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty, cleaned.count >= 2 else { return false }

        var entries = loadAll()

        // Deduplicate (case-insensitive)
        if entries.contains(where: { $0.word.lowercased() == cleaned }) {
            return false
        }

        // Enforce max limit: remove oldest learned entries first, then oldest manual
        if entries.count >= maxEntries {
            if let learnedIdx = entries.lastIndex(where: { $0.source == .learned }) {
                entries.remove(at: learnedIdx)
            } else if let oldestIdx = entries.indices.min(by: { entries[$0].addedAt < entries[$1].addedAt }) {
                entries.remove(at: oldestIdx)
            }
        }

        entries.append(Entry(word: cleaned, source: source))
        do {
            try saveAll(entries)
            logger.info("Added hotword: \(cleaned) (source=\(source.rawValue))")
            return true
        } catch {
            logger.error("Failed to save hotwords: \(error.localizedDescription)")
            return false
        }
    }

    func addBatch(_ words: [String], source: Entry.Source = .manual) -> Int {
        var added = 0
        for word in words {
            if add(word, source: source) { added += 1 }
        }
        return added
    }

    func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var entries = loadAll()
        entries.removeAll { $0.id == id }
        do { try saveAll(entries) }
        catch { logger.error("Failed to save hotwords: \(error.localizedDescription)") }
    }

    func remove(word: String) {
        lock.lock()
        defer { lock.unlock() }
        var entries = loadAll()
        let lower = word.lowercased()
        entries.removeAll { $0.word.lowercased() == lower }
        do { try saveAll(entries) }
        catch { logger.error("Failed to save hotwords: \(error.localizedDescription)") }
    }

    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        do { try saveAll([]) }
        catch { logger.error("Failed to clear hotwords: \(error.localizedDescription)") }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadAll().count
    }

    func contains(_ word: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let lower = word.lowercased()
        return loadAll().contains { $0.word.lowercased() == lower }
    }

    // MARK: - LLM Validation

    func addWithLLMValidation(_ word: String) async -> Bool {
        let config = CredentialService.loadLLMConfig()
        guard config.isValid else {
            // No LLM configured, add directly
            return add(word, source: .learned)
        }

        // Check if similar word already exists
        if contains(word) { return false }

        let client = DeepSeekClient()
        let prompt = """
        A user corrected an ASR (speech recognition) output. \
        Is this a valid phonetic or contextual correction that should be remembered?

        Correction: "\(word)"

        Answer only: YES or NO
        """

        do {
            let reply = try await client.chat(
                systemPrompt: "You are a speech recognition correction validator.",
                userMessage: prompt,
                config: config
            )
            if reply.uppercased().contains("YES") {
                return add(word, source: .learned)
            }
            return false
        } catch {
            // LLM failed, add anyway
            return add(word, source: .learned)
        }
    }
}
