import Foundation

struct HistoryEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let path: String
    let addedAt: Date

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

class HistoryManager: ObservableObject {
    @Published var entries: [HistoryEntry] = []

    private let key = "mdv_history"
    private let maxEntries = 100

    init() {
        load()
        // Bring the FTS index into sync with what's on disk for any entries
        // that pre-date the search feature, or files that have been edited
        // since they were last opened. Mtime-aware, so it's cheap.
        Database.shared.reindex(paths: entries.map { $0.path })
    }

    @discardableResult
    func add(path: String) -> HistoryEntry {
        // Move to top if already present
        entries.removeAll { $0.path == path }

        let entry = HistoryEntry(id: UUID(), path: path, addedAt: Date())
        entries.insert(entry, at: 0)

        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        save()
        Database.shared.indexFile(at: path)
        return entry
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
        Database.shared.removeFile(at: entry.path)
    }

    func clear() {
        let removed = entries.map { $0.path }
        entries.removeAll()
        save()
        for p in removed { Database.shared.removeFile(at: p) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }
}
