import Foundation

// Materializes the bundled Help.md to a stable path under
// ~/Library/Application Support/mdv/ before opening it as a regular
// markdown document. Going through a stable path (instead of opening the
// bundle resource directly) keeps bookmarks valid across .app moves and
// reinstalls — bookmarks are keyed by absolute path, and the bundle's
// own path changes whenever you drag mdv.app to a new location.
//
// We rewrite the user-facing copy each time Help is opened so doc updates
// in newer builds flow through without needing the user to delete the
// stale file.
enum HelpManager {
    static func openHelp() -> URL? {
        guard let bundled = Bundle.main.url(forResource: "Help", withExtension: "md") else {
            return nil
        }
        let dest = userHelpURL()
        do {
            try FileManager.default.createDirectory(
                at: dest.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Always overwrite — keeps the content in sync with the running build.
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: bundled, to: dest)
        } catch {
            return nil
        }
        return dest
    }

    private static func userHelpURL() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return appSupport
            .appendingPathComponent("mdv", isDirectory: true)
            .appendingPathComponent("Help.md")
    }
}
