import SwiftUI
import AppKit

@main
struct mdvApp: App {
    @StateObject private var history = HistoryManager()
    @StateObject private var bookmarks = BookmarksManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("mdv", id: "main") {
            ContentView()
                .environmentObject(history)
                .environmentObject(bookmarks)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Open in New Window…") {
                    NotificationCenter.default.post(name: .openFileInNewWindow, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.post(name: .findInDocument, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Search History…") {
                    NotificationCenter.default.post(name: .searchHistory, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Bookmarks") {
                Button("Bookmark Current Spot") {
                    NotificationCenter.default.post(name: .toggleBookmark, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Set Placeholder") {
                    NotificationCenter.default.post(name: .setPlaceholder, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])

                Button("Jump to Placeholder") {
                    NotificationCenter.default.post(name: .jumpToPlaceholder, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                ForEach(1...BookmarksManager.maxSlots, id: \.self) { n in
                    let bookmark = bookmarks.bookmark(forSlot: n)
                    Button(bookmarkSlotLabel(n: n, bookmark: bookmark)) {
                        NotificationCenter.default.post(name: .openBookmarkSlot, object: n)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                    .disabled(bookmark == nil)
                }
            }
        }
    }

    private func bookmarkSlotLabel(n: Int, bookmark: Bookmark?) -> String {
        if let b = bookmark {
            return "\(n).  \(b.title)"
        }
        return "Slot \(n) — Empty"
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, open urls: [URL]) {
        // Always route into the active (or first) window's ContentView
        // via a notification, instead of letting SwiftUI spawn new windows.
        // The ContentView listens for `.openURLInWindow` and calls loadFile.
        for url in urls {
            NotificationCenter.default.post(name: .openURLInWindow, object: url)
        }
        if let win = NSApp.keyWindow ?? NSApp.windows.first {
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let openFile = Notification.Name("openFile")
    static let openFileInNewWindow = Notification.Name("openFileInNewWindow")
    static let openURLInWindow = Notification.Name("openURLInWindow")
    static let findInDocument = Notification.Name("findInDocument")
    static let searchHistory = Notification.Name("searchHistory")
    static let toggleBookmark = Notification.Name("toggleBookmark")
    static let openBookmarkSlot = Notification.Name("openBookmarkSlot")
    static let setPlaceholder = Notification.Name("setPlaceholder")
    static let jumpToPlaceholder = Notification.Name("jumpToPlaceholder")
}
