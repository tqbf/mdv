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

    /// Mirror of the per-window collapse state, so the View menu can show
    /// "Hide Sidebar" vs. "Show Sidebar" and the menu-bar toggle title
    /// reflects reality. Single-window app, so a global @AppStorage matches
    /// the ContentView's @AppStorage 1:1.
    @AppStorage("mdv_sidebar_collapsed") private var sidebarCollapsed: Bool = false

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
                    NotificationCenter.default.post(name: .openFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("Open in New Window…") {
                    NotificationCenter.default.post(name: .openFileInNewWindow, object: nil)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Menu("Edit") {
                    Button("Edit Current File") {
                        NotificationCenter.default.post(name: .openInExternalEditor, object: nil)
                    }
                    .keyboardShortcut("e", modifiers: .command)
                    Button("Choose Editor…") {
                        NotificationCenter.default.post(name: .chooseExternalEditor, object: nil)
                    }
                    Button("Forget Editor") {
                        NotificationCenter.default.post(name: .forgetExternalEditor, object: nil)
                    }
                }
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
            CommandMenu("Navigate") {
                Button("Back") {
                    NotificationCenter.default.post(name: .navigateBack, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Forward") {
                    NotificationCenter.default.post(name: .navigateForward, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
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
                    NotificationCenter.default.post(name: .toggleSidebar, object: nil)
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
            }
            CommandGroup(replacing: .help) {
                Button("mdv Help") {
                    if let url = HelpManager.openHelp() {
                        NotificationCenter.default.post(name: .openURLInWindow, object: url)
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
    static let chooseExternalEditor = Notification.Name("chooseExternalEditor")
    static let openInExternalEditor = Notification.Name("openInExternalEditor")
    static let forgetExternalEditor = Notification.Name("forgetExternalEditor")
    static let navigateBack = Notification.Name("navigateBack")
    static let navigateForward = Notification.Name("navigateForward")
    static let toggleSidebar = Notification.Name("toggleSidebar")
}
