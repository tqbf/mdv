import SwiftUI
import AppKit

@main
struct mdvApp: App {
    @StateObject private var history = HistoryManager()
    @StateObject private var bookmarks = BookmarksManager()
    @StateObject private var themes = ThemeManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// User preference: SmartyPants-style typography on prose. Default on.
    /// Effective state is `userSmartTypography && themes.current.smartTypographyAllowed`
    /// — themes whose aesthetic or audience argues against curling
    /// punctuation (Phosphor, Standard Erin) ignore the preference.
    @AppStorage("mdv_smart_typography") private var userSmartTypography: Bool = true

    /// Persistent toggle for fetching remote (`http(s)`) images. Default
    /// off; lifted into App scope so the View menu Toggle can bind to it
    /// without a notification round-trip.
    @AppStorage("mdv_load_remote_images") private var loadRemoteImages: Bool = false

    /// Persistent toggle for showing a document's metadata header. Default
    /// on; lifted into App scope for the View menu Toggle the same way as
    /// the preferences above.
    @AppStorage("mdv_show_frontmatter") private var showFrontmatter: Bool = true

    /// Mirror of the per-window collapse state, so the View menu can show
    /// "Hide Sidebar" vs. "Show Sidebar" and the menu-bar toggle title
    /// reflects reality. Single-window app, so a global @AppStorage matches
    /// the ContentView's @AppStorage 1:1.
    @AppStorage("mdv_sidebar_collapsed") private var sidebarCollapsed: Bool = false

    /// Mirror of the sidebar selection (the open file's path, empty for
    /// none), so the File menu can enable/disable its Close items. Same
    /// @AppStorage mirroring as `sidebarCollapsed` above: one line at each
    /// end for a single-window app, where a FocusedValue key would need a
    /// key type, an extension, and a scene-value modifier to say the same
    /// thing.
    @AppStorage("mdv_selected_path") private var selectedPath: String = ""

    init() {
        // Register the bundled Alegreya weights into the process-local font
        // space before any view hierarchy resolves a custom font name. Done
        // once at App init so SwiftUI's Font.custom("Alegreya", ...) resolves
        // for every window we open.
        FontRegistration.registerBundledFonts()
    }

    var body: some Scene {
        Window("mdv", id: "main") {
            ContentView()
                .environmentObject(history)
                .environmentObject(bookmarks)
                .environmentObject(themes)
                .frame(minWidth: 760, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 720)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(after: .appInfo) {
                Divider()
                Button("Install Command Line Tool…") {
                    CLIInstaller.install()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.postToKeyWindow(.openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Open in New Window…") {
                    NotificationCenter.default.postToKeyWindow(.openFileInNewWindow, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Menu("Edit") {
                    Button("Edit Current File") {
                        NotificationCenter.default.postToKeyWindow(.openInExternalEditor, object: nil)
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    Button("Choose Editor…") {
                        NotificationCenter.default.postToKeyWindow(.chooseExternalEditor, object: nil)
                    }
                    Button("Forget Editor") {
                        NotificationCenter.default.postToKeyWindow(.forgetExternalEditor, object: nil)
                    }
                }
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    NotificationCenter.default.post(name: .printDocument, object: nil)
                }
                .keyboardShortcut("p", modifiers: .command)
            }
            // Replaces the default File → Close, which closed the only
            // window and left the app running with nothing on screen. ⌘W
            // now closes the open *file* (the sidebar entry, like a tab)
            // and ⇧⌘W closes the window — the standard macOS split once
            // ⌘W means close-tab.
            CommandGroup(replacing: .saveItem) {
                Button("Close File") {
                    NotificationCenter.default.post(name: .closeFile, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(selectedPath.isEmpty)
                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                Divider()
                Button("Close All") {
                    NotificationCenter.default.post(name: .closeAllFiles, object: nil)
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
                .disabled(history.entries.isEmpty)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.postToKeyWindow(.findInDocument, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                Button("Search History…") {
                    NotificationCenter.default.postToKeyWindow(.searchHistory, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            CommandMenu("Navigate") {
                Button("Back") {
                    NotificationCenter.default.postToKeyWindow(.navigateBack, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Forward") {
                    NotificationCenter.default.postToKeyWindow(.navigateForward, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                Divider()
                // Step the sidebar list itself, in list order. ⌃⇥ / ⌃⇧⇥ are
                // bound to the same pair by a key monitor in ContentView,
                // since a menu item can only carry one key equivalent.
                Button("Next File") {
                    NotificationCenter.default.post(name: .nextFile, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                .disabled(!hasNextFile)
                Button("Previous File") {
                    NotificationCenter.default.post(name: .previousFile, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                .disabled(!hasPreviousFile)
            }
            // View menu addition: Smart Typography toggle. Sits in the
            // SwiftUI-generated View menu (CommandGroup(after: .toolbar)).
            // The toggle persists user intent; the *effective* state is
            // ANDed with the current theme's `smartTypographyAllowed`
            // flag. When the active theme blocks smart typography we
            // disable the menu item and append "(off for this theme)"
            // so the user understands why their preference isn't taking
            // effect — instead of silently ignoring it.
            CommandGroup(after: .toolbar) {
                Button(sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar") {
                    NotificationCenter.default.postToKeyWindow(.toggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Divider()
                // Zoom: scales body type via ThemeManager.fontScale.
                // Headings are em-relative so they scale with body. ⌘= is
                // the macOS-standard "zoom in" binding (same physical key
                // as ⌘+ — shift is irrelevant under .command). ⌘0 is
                // already taken by Jump-to-Placeholder, so Actual Size
                // gets a menu item only.
                Button("Zoom In") { themes.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(themes.fontScale >= ThemeManager.fontScaleMax)
                Button("Zoom Out") { themes.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(themes.fontScale <= ThemeManager.fontScaleMin)
                Button("Actual Size") { themes.resetZoom() }
                    .disabled(themes.fontScale == 1.0)
                Divider()
                Toggle(
                    themes.current.smartTypographyAllowed
                        ? "Smart Typography"
                        : "Smart Typography (off for this theme)",
                    isOn: $userSmartTypography
                )
                .disabled(!themes.current.smartTypographyAllowed)
                // Looked up by title from `LocalImageProvider.revealRemoteImagesMenuItem`,
                // so don't change the visible string without updating that match.
                Toggle("Load Remote Images", isOn: $loadRemoteImages)
                Toggle("Show Frontmatter", isOn: $showFrontmatter)
            }
            CommandGroup(replacing: .help) {
                Button("mdv Help") {
                    if let url = HelpManager.openHelp() {
                        NotificationCenter.default.postToKeyWindow(.openURLInWindow, object: url)
                        if let win = NSApp.keyWindow ?? NSApp.windows.first {
                            win.makeKeyAndOrderFront(nil)
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .keyboardShortcut("?", modifiers: .command)
            }
            CommandMenu("Bookmarks") {
                Button("Bookmark Current Spot") {
                    NotificationCenter.default.postToKeyWindow(.toggleBookmark, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Button("Set Placeholder") {
                    NotificationCenter.default.postToKeyWindow(.setPlaceholder, object: nil)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])

                Button("Jump to Placeholder") {
                    NotificationCenter.default.postToKeyWindow(.jumpToPlaceholder, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                ForEach(1...BookmarksManager.maxSlots, id: \.self) { n in
                    let bookmark = bookmarks.bookmark(forSlot: n)
                    Button(bookmarkSlotLabel(n: n, bookmark: bookmark)) {
                        NotificationCenter.default.postToKeyWindow(.openBookmarkSlot, object: n)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                    .disabled(bookmark == nil)
                }
            }
        }
    }

    /// Row of the open file in the sidebar list, or nil when nothing is
    /// open. Drives the Next / Previous File enabled state, which clamps
    /// at both ends of the list rather than wrapping.
    private var selectedIndex: Int? {
        guard !selectedPath.isEmpty else { return nil }
        return history.entries.firstIndex { $0.path == selectedPath }
    }

    private var hasNextFile: Bool {
        guard let i = selectedIndex else { return false }
        return i + 1 < history.entries.count
    }

    private var hasPreviousFile: Bool {
        guard let i = selectedIndex else { return false }
        return i > 0
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
        // Route into the key window's ContentView (or the first window
        // at a cold start) via an addressed notification, instead of
        // letting SwiftUI spawn new windows (SPEC R-01, E-26). The
        // ContentView listens for `.openURLInWindow` and calls loadFile.
        // `NSApp.keyWindow` is nil while the app is inactive (the usual case
        // for `open -a` from a terminal or a Finder double-click), and
        // `NSApp.windows` holds SwiftUI's hidden helper windows too — so
        // address the frontmost *document* window in z-order.
        let target = DocumentWindows.frontmost
        for url in urls {
            NotificationCenter.default.post(name: .openURLInWindow, object: url, userInfo: Notification.targetInfo(target))
        }
        // Launch Services already activates the app for a normal open
        // (Finder, `open`, the command line helper). Activating here too
        // would override a background open, so only bring the window
        // forward when we are already the active app.
        guard NSApp.isActive else { return }
        if let target {
            target.makeKeyAndOrderFront(nil)
        }
    }
}

/// The windows that host a `ContentView`, registered by `WindowAccessor`
/// as each one attaches, so open events can be addressed to a document
/// window rather than to whatever `NSApp.windows.first` happens to be.
enum DocumentWindows {
    private static let table = NSHashTable<NSWindow>.weakObjects()

    static func register(_ window: NSWindow) { table.add(window) }

    static func contains(_ window: NSWindow) -> Bool { table.contains(window) }

    /// The key window when it is a document window; otherwise the
    /// frontmost registered window (`orderedWindows` is front-to-back).
    static var frontmost: NSWindow? {
        if let key = NSApp.keyWindow, contains(key) { return key }
        return NSApp.orderedWindows.first(where: { contains($0) && $0.isVisible })
            ?? NSApp.windows.first(where: contains)
    }
}

extension Notification {
    /// `userInfo` key naming the `NSWindow` a command is addressed to.
    static let targetWindowKey = "mdv.targetWindow"

    static func targetInfo(_ window: NSWindow?) -> [AnyHashable: Any]? {
        window.map { [targetWindowKey: $0] }
    }

    /// The window this notification is addressed to, if any.
    var targetWindow: NSWindow? {
        userInfo?[Notification.targetWindowKey] as? NSWindow
    }
}

extension NotificationCenter {
    /// Post a menu command addressed to the key window, so that with several
    /// windows open only the one the reader is looking at acts (SPEC E-26).
    func postToKeyWindow(_ name: Notification.Name, object: Any? = nil) {
        post(name: name, object: object, userInfo: Notification.targetInfo(DocumentWindows.frontmost))
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
    static let chooseExternalEditor = Notification.Name("chooseExternalEditor")
    static let openInExternalEditor = Notification.Name("openInExternalEditor")
    static let forgetExternalEditor = Notification.Name("forgetExternalEditor")
    static let navigateBack = Notification.Name("navigateBack")
    static let navigateForward = Notification.Name("navigateForward")
    static let toggleSidebar = Notification.Name("toggleSidebar")
    static let printDocument = Notification.Name("printDocument")
    static let closeFile = Notification.Name("closeFile")
    static let closeAllFiles = Notification.Name("closeAllFiles")
    static let nextFile = Notification.Name("nextFile")
    static let previousFile = Notification.Name("previousFile")
}
