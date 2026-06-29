//
//  HistoryStore.swift
//  App4Crawl
//
//  Persists the local crawl history to disk under ~/.app4crawl/config
//  (PROJECTBRIEF §5). No database for v1; a single JSON file is sufficient.
//

import Foundation

/// Loads, stores, and mutates the local crawl history.
@MainActor
final class HistoryStore: ObservableObject {
    /// Records, most recent first.
    @Published private(set) var records: [CrawlRecord] = []

    private let fileURL: URL
    private let maxRecords: Int

    init(fileURL: URL = AppPaths.configDir.appendingPathComponent("history.json"),
         maxRecords: Int = 100) {
        self.fileURL = fileURL
        self.maxRecords = maxRecords
        load()
    }

    /// Add a record to the top of the history and persist.
    func add(_ record: CrawlRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    /// Replace an existing record (e.g. after a rename) and persist.
    func update(_ record: CrawlRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        save()
    }

    /// Delete a record and persist.
    func delete(_ record: CrawlRecord) {
        records.removeAll { $0.id == record.id }
        save()
    }

    /// Remove all history and persist.
    func clear() {
        records.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([CrawlRecord].self, from: data) {
            records = decoded
        }
    }

    private func save() {
        do {
            try AppPaths.ensureDirectories()
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // History is non-critical; a write failure should not crash the app.
            NSLog("App4Crawl: failed to save history: \(error.localizedDescription)")
        }
    }
}
