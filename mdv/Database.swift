import Foundation
import SQLite3

// SQLite expects this sentinel to copy bound text into its own buffer.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Single shared SQLite store for mdv. Lives at
/// `~/Library/Application Support/com.mdv.app/mdv.db`.
///
/// Schema is intentionally small but designed to grow: add new tables as needed
/// alongside `articles` / `articles_fts`, and bump `meta.schema_version` for migrations.
final class Database {
    static let shared = Database()

    private let queue = DispatchQueue(label: "com.mdv.app.db", qos: .utility)
    private var db: OpaquePointer?

    struct SearchHit: Identifiable, Hashable {
        let id = UUID()
        let path: String
        let filename: String
        /// Snippet text with FTS5 markers `\u{2}` (start) / `\u{3}` (end) wrapping matched terms.
        let snippet: String
    }

    private init() {
        let url = Database.databaseURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            NSLog("[mdv] failed to open db at %@", url.path)
            db = nil
            return
        }
        // Performance / durability tradeoff: WAL + NORMAL is the standard "fast and safe enough" combo.
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA synchronous = NORMAL;")
        migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    static let databaseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("mdv", isDirectory: true)
            .appendingPathComponent("mdv.db")
    }()

    // MARK: - Schema

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS articles (
            id          INTEGER PRIMARY KEY,
            path        TEXT NOT NULL UNIQUE,
            filename    TEXT NOT NULL,
            content     TEXT NOT NULL DEFAULT '',
            indexed_at  INTEGER NOT NULL,
            file_mtime  INTEGER NOT NULL DEFAULT 0,
            file_size   INTEGER NOT NULL DEFAULT 0
        );
        """)
        exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS articles_fts USING fts5(
            filename,
            content,
            path UNINDEXED,
            content='articles',
            content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        """)
        // Triggers keep the FTS shadow table in sync with `articles`.
        exec("""
        CREATE TRIGGER IF NOT EXISTS articles_ai AFTER INSERT ON articles BEGIN
            INSERT INTO articles_fts(rowid, filename, content, path)
            VALUES (new.id, new.filename, new.content, new.path);
        END;
        """)
        exec("""
        CREATE TRIGGER IF NOT EXISTS articles_ad AFTER DELETE ON articles BEGIN
            INSERT INTO articles_fts(articles_fts, rowid, filename, content, path)
            VALUES ('delete', old.id, old.filename, old.content, old.path);
        END;
        """)
        exec("""
        CREATE TRIGGER IF NOT EXISTS articles_au AFTER UPDATE ON articles BEGIN
            INSERT INTO articles_fts(articles_fts, rowid, filename, content, path)
            VALUES ('delete', old.id, old.filename, old.content, old.path);
            INSERT INTO articles_fts(rowid, filename, content, path)
            VALUES (new.id, new.filename, new.content, new.path);
        END;
        """)
        exec("INSERT OR IGNORE INTO meta(key, value) VALUES ('schema_version', '1');")
    }

    // MARK: - Indexing

    /// Index or refresh a file. Skips work if the on-disk mtime matches what we already stored.
    func indexFile(at path: String) {
        queue.async { [weak self] in
            self?._indexFile(at: path)
        }
    }

    /// Re-index every path in `paths` in the background. Mtime-aware.
    func reindex(paths: [String]) {
        queue.async { [weak self] in
            for p in paths { self?._indexFile(at: p) }
        }
    }

    func removeFile(at path: String) {
        queue.async { [weak self] in
            guard let self, let db = self.db else { return }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            if sqlite3_prepare_v2(db, "DELETE FROM articles WHERE path = ?;", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
                _ = sqlite3_step(stmt)
            }
        }
    }

    private func _indexFile(at path: String) {
        guard let db = db else { return }
        let url = URL(fileURLWithPath: path)
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970,
            let size  = attrs[.size] as? Int
        else { return }
        let mtimeI = Int64(mtime)
        let sizeI  = Int64(size)

        // Skip if the existing row is already up-to-date.
        if let existing = scalarInt64(sql: "SELECT file_mtime FROM articles WHERE path = ?;", bindText1: path),
           existing == mtimeI {
            return
        }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let filename = url.lastPathComponent
        let now = Int64(Date().timeIntervalSince1970)

        let sql = """
        INSERT INTO articles (path, filename, content, indexed_at, file_mtime, file_size)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET
            filename   = excluded.filename,
            content    = excluded.content,
            indexed_at = excluded.indexed_at,
            file_mtime = excluded.file_mtime,
            file_size  = excluded.file_size;
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, filename, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, content, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, now)
        sqlite3_bind_int64(stmt, 5, mtimeI)
        sqlite3_bind_int64(stmt, 6, sizeI)
        if sqlite3_step(stmt) != SQLITE_DONE {
            NSLog("[mdv] indexFile insert failed for %@", path)
        }
    }

    // MARK: - Search

    /// Full-text search across every indexed article. Tokens get prefix-matched (typing
    /// "auth" finds "authentication"). Highlighted snippets come back via the `snippet`
    /// field on each hit.
    func search(query rawQuery: String, limit: Int = 80, completion: @escaping ([SearchHit]) -> Void) {
        queue.async { [weak self] in
            let hits = self?._search(rawQuery: rawQuery, limit: limit) ?? []
            DispatchQueue.main.async { completion(hits) }
        }
    }

    private func _search(rawQuery: String, limit: Int) -> [SearchHit] {
        guard let db = db else { return [] }
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let ftsQuery = Database.makeFTSQuery(from: trimmed)
        guard !ftsQuery.isEmpty else { return [] }

        // Use control characters as match delimiters so they can never collide with
        // anything a user might type.
        let sql = """
        SELECT
            a.path,
            a.filename,
            snippet(articles_fts, 1, char(2), char(3), '…', 14)
        FROM articles_fts f
        JOIN articles a ON a.id = f.rowid
        WHERE articles_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var hits: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let path     = String(cString: sqlite3_column_text(stmt, 0))
            let filename = String(cString: sqlite3_column_text(stmt, 1))
            let snippet  = String(cString: sqlite3_column_text(stmt, 2))
            hits.append(SearchHit(path: path, filename: filename, snippet: snippet))
        }
        return hits
    }

    /// Build a safe FTS5 MATCH expression: each token wrapped in double-quotes (escaping
    /// embedded `"` per FTS5 rules), suffixed with `*` for prefix matching, ANDed together.
    static func makeFTSQuery(from input: String) -> String {
        let tokens = input
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let parts: [String] = tokens.compactMap { tok in
            let stripped = tok.unicodeScalars.filter { scalar in
                // Drop FTS5 syntax characters that would break a phrase. Keep letters,
                // digits, hyphens, underscores, and CJK / Unicode word chars.
                let bad: Set<UnicodeScalar> = ["\"", "(", ")", ":", "*", "^"]
                return !bad.contains(scalar)
            }
            let cleaned = String(String.UnicodeScalarView(stripped))
            guard !cleaned.isEmpty else { return nil }
            return "\"\(cleaned)\"*"
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Helpers

    private func exec(_ sql: String) {
        guard let db = db else { return }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let err {
                NSLog("[mdv] sqlite exec error: %s", err)
                sqlite3_free(err)
            }
        }
    }

    private func scalarInt64(sql: String, bindText1: String) -> Int64? {
        guard let db = db else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, bindText1, -1, SQLITE_TRANSIENT)
        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        return nil
    }
}
