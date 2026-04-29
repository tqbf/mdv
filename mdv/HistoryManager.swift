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
        return entry
    }

    func remove(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
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
