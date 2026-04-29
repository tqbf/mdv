import Foundation
import SwiftUI

/// In-memory representation of a user bookmark.
///
/// Bookmarks anchor to a position inside the file (`blockIndex` plus a
/// `blockFingerprint` that lets us re-locate the spot if the file gets edited
/// and indices shift). Multiple bookmarks per file are allowed — markdown docs
/// can be huge, and bookmarks are the in-doc navigation primitive.
///
/// `fileExists` is recomputed at load and on demand; bookmarks survive even
/// when the underlying file disappears, but get visually dimmed.
struct Bookmark: Identifiable, Hashable {
    let id: Int64
    let path: String
    var title: String
    var sortOrder: Int
    let createdAt: Date
    let blockIndex: Int
    let blockFingerprint: String
    var fileExists: Bool
}

/// Owns the user's saved bookmarks.
///
/// "Slot" is implicit — the first five entries in `bookmarks` are the ⌘1…⌘5
/// hotkeys. Reordering the list is the only way to change which bookmark
/// owns which hotkey, which keeps the model dead simple.
///
/// The ⌘0 *placeholder* is intentionally NOT managed here. It's transient
/// per-window state owned by ContentView — see the Placeholder section there.
final class BookmarksManager: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    static let maxSlots = 5

    init() {
        reload()
    }

    func reload() {
        let rows = Database.shared.loadBookmarks()
        bookmarks = rows.map { row in
            Bookmark(
                id: row.id,
                path: row.path,
                title: row.title,
                sortOrder: row.sortOrder,
                createdAt: row.createdAt,
                blockIndex: row.blockIndex,
                blockFingerprint: row.blockFingerprint,
                fileExists: FileManager.default.fileExists(atPath: row.path)
            )
        }
    }

    func refreshFileExistence() {
        for i in bookmarks.indices {
            bookmarks[i].fileExists = FileManager.default.fileExists(atPath: bookmarks[i].path)
        }
    }

    /// True if this file has at least one bookmark anywhere. Used by the
    /// toolbar indicator (filled vs hollow icon) — multiple bookmarks per file
    /// are allowed, so this is a binary "any" test rather than a toggle.
    func hasAnyBookmark(forPath path: String) -> Bool {
        bookmarks.contains { $0.path == path }
    }

    @discardableResult
    func add(path: String, title: String, blockIndex: Int, fingerprint: String) -> Bookmark? {
        let nextOrder = bookmarks.count
        guard let row = Database.shared.addBookmark(
            path: path,
            title: title,
            sortOrder: nextOrder,
            blockIndex: blockIndex,
            blockFingerprint: fingerprint
        ) else { return nil }
        let bookmark = Bookmark(
            id: row.id,
            path: row.path,
            title: row.title,
            sortOrder: row.sortOrder,
            createdAt: row.createdAt,
            blockIndex: row.blockIndex,
            blockFingerprint: row.blockFingerprint,
            fileExists: FileManager.default.fileExists(atPath: row.path)
        )
        bookmarks.append(bookmark)
        return bookmark
    }

    func remove(id: Int64) {
        Database.shared.removeBookmark(id: id)
        bookmarks.removeAll { $0.id == id }
        renormalizeSortOrders()
    }

    func move(from source: IndexSet, to destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        renormalizeSortOrders()
    }

    /// Drag-drop entry point: move a bookmark by id to a target index.
    /// Used by the BookmarkDropDelegate where IndexSet semantics don't apply.
    func moveBookmark(id: Int64, toIndex destination: Int) {
        guard let from = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let clamped = max(0, min(destination, bookmarks.count - 1))
        guard from != clamped else { return }
        let item = bookmarks.remove(at: from)
        bookmarks.insert(item, at: clamped)
        renormalizeSortOrders()
    }

    /// Move a bookmark to the very end of the list (used when the user drops
    /// onto the tail spacer below the last row).
    func moveBookmarkToEnd(id: Int64) {
        guard let from = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        guard from != bookmarks.count - 1 else { return }
        let item = bookmarks.remove(at: from)
        bookmarks.append(item)
        renormalizeSortOrders()
    }

    /// 1-based slot number (1…5) if this bookmark is in a hotkey slot, else nil.
    func slotIndex(for bookmarkID: Int64) -> Int? {
        guard let i = bookmarks.firstIndex(where: { $0.id == bookmarkID }) else { return nil }
        return i < BookmarksManager.maxSlots ? i + 1 : nil
    }

    /// Look up the bookmark in slot `n` (1-based). Returns nil if the slot is empty.
    func bookmark(forSlot n: Int) -> Bookmark? {
        let i = n - 1
        guard i >= 0, i < min(BookmarksManager.maxSlots, bookmarks.count) else { return nil }
        return bookmarks[i]
    }

    private func renormalizeSortOrders() {
        for i in bookmarks.indices {
            bookmarks[i].sortOrder = i
        }
        Database.shared.setBookmarkOrder(idsInOrder: bookmarks.map { $0.id })
    }
}

// MARK: - Anchor matching

/// Normalize a chunk of markdown into a fingerprint. We strip excess whitespace
/// and lowercase so small editing diffs (added trailing spaces, casing tweaks
/// inside a heading) don't break the anchor.
func bookmarkFingerprint(forBlock block: String) -> String {
    let collapsed = block
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .lowercased()
    return String(collapsed.prefix(80))
}

/// Resolve a bookmark's anchor against a document's current blocks. Returns the
/// best-matching block index. Strategy: exact fingerprint match wins; failing
/// that we fall back to the stored block index, clamped to the doc's bounds.
func resolveBookmarkAnchor(
    blocks: [String],
    storedIndex: Int,
    fingerprint: String
) -> Int {
    guard !blocks.isEmpty else { return 0 }
    if !fingerprint.isEmpty {
        for (i, block) in blocks.enumerated() {
            if bookmarkFingerprint(forBlock: block) == fingerprint {
                return i
            }
        }
    }
    return max(0, min(storedIndex, blocks.count - 1))
}
