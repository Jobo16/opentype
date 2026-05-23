import Foundation
import os

/// Persistent history store — JSON file at ~/Library/Application Support/OpenType/history.json.
final class HistoryStore: Sendable {

    static let shared = HistoryStore()

    private let logger = Logger(subsystem: "com.opentype.history", category: "HistoryStore")
    private let lock = NSLock()
    private let maxRecords = 1000
    private static let fileName = "history.json"

    // MARK: - Data Model

    struct Record: Codable, Identifiable, Sendable {
        let id: UUID
        let rawText: String
        let optimizedText: String
        let mode: String
        let timestamp: Date
        let duration: TimeInterval

        var displayText: String {
            optimizedText.isEmpty ? rawText : optimizedText
        }

        init(rawText: String, optimizedText: String = "", mode: String = "default", duration: TimeInterval = 0) {
            self.id = UUID()
            self.rawText = rawText
            self.optimizedText = optimizedText
            self.mode = mode
            self.timestamp = Date()
            self.duration = duration
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

    private func loadAll() -> [Record] {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return records
    }

    private func saveAll(_ records: [Record]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(records)
        try data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: - Public API

    func add(_ record: Record) {
        lock.lock()
        defer { lock.unlock() }
        var records = loadAll()
        records.insert(record, at: 0)
        // Auto-cleanup: keep only maxRecords
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        do {
            try saveAll(records)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var records = loadAll()
        records.removeAll { $0.id == id }
        do {
            try saveAll(records)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }

    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        do {
            try saveAll([])
        } catch {
            logger.error("Failed to clear history: \(error.localizedDescription)")
        }
    }

    func getAll() -> [Record] {
        lock.lock()
        defer { lock.unlock() }
        return loadAll()
    }

    func search(keyword: String) -> [Record] {
        lock.lock()
        defer { lock.unlock() }
        let records = loadAll()
        guard !keyword.isEmpty else { return records }
        let lower = keyword.lowercased()
        return records.filter {
            $0.rawText.lowercased().contains(lower) ||
            $0.optimizedText.lowercased().contains(lower)
        }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadAll().count
    }

    // MARK: - CSV Export

    func exportCSV(filtered records: [Record]? = nil) -> URL? {
        let records = records ?? getAll()
        var csv = "时间,原始文本,优化文本,模式,时长(秒)\n"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        for r in records {
            let row = [
                formatter.string(from: r.timestamp),
                csvEscape(r.rawText),
                csvEscape(r.optimizedText),
                csvEscape(r.mode),
                String(format: "%.1f", r.duration),
            ].joined(separator: ",")
            csv += row + "\n"
        }

        let dir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = dir.appendingPathComponent("OpenType_History_\(formatter.string(from: Date())).csv")

        guard let data = csv.data(using: .utf8) else { return nil }
        try? data.write(to: url, options: .atomic)
        return url
    }

    private func csvEscape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
