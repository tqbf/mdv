import SwiftUI
import MarkdownUI
import AppKit
import CoreServices

/// One frame of browser-style back/forward state: which file, plus where
/// we were scrolled to inside it. Same-doc fragment clicks push a snapshot
/// with the same `entry` but a different `topBlockIndex`, so ⌘← can scroll
/// back to where the user was before they jumped to the heading.
struct NavSnapshot: Equatable {
    let entry: HistoryEntry
    let topBlockIndex: Int
}

struct ContentView: View {
    @EnvironmentObject var history: HistoryManager
    @EnvironmentObject var bookmarks: BookmarksManager
    @EnvironmentObject var themes: ThemeManager
    let initialURL: URL?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    @State private var selectedEntry: HistoryEntry?
    @State private var rawMarkdown: String = ""
    @State private var sidebarWidth: CGFloat = 240
    @State private var dragHandleHovered = false

    /// Sidebar collapse state. Defaults to false (sidebar open) on first
    /// launch; persists via @AppStorage so the user's choice survives
    /// quits. Toggled via View → Hide Sidebar (⌃⌘S), the hover-revealed
    /// chevron button on the drag handle, or the matching expand chevron
    /// in the left edge gutter when collapsed.
    @AppStorage("mdv_sidebar_collapsed") private var sidebarCollapsed: Bool = false
    /// Tracks hover on the collapsed-state edge gutter so the expand
    /// chevron only reveals when the mouse approaches the left edge.
    @State private var edgeGutterHovered = false

    // TOC + Bookmarks (right inspector)
    @AppStorage("mdv_inspector_visible") private var inspectorVisible: Bool = false
    @State private var tocSelectedBlock: Int? = nil
    @State private var tocScrollTrigger: Int? = nil
    @State private var hoveredHeading: Int? = nil
    @State private var tocSearchQuery: String = ""
    @State private var tocSearchVisible: Bool = false
    @FocusState private var tocSearchFocused: Bool
    private let inspectorWidth: CGFloat = 240

    // External editor (Edit button in toolbar)
    @AppStorage("mdv_editor_app_path") private var editorAppPath: String = ""

    /// User preference for SmartyPants-style typography. Default on. The
    /// effective state is gated by the current theme's
    /// `smartTypographyAllowed` flag — see `smartTypographyEnabled`.
    @AppStorage("mdv_smart_typography") private var userSmartTypography: Bool = true

    /// Whether `http(s)` images in markdown are fetched. Default off — a
    /// markdown viewer probably shouldn't be talking to arbitrary remote
    /// servers without consent (privacy + tracking-pixel hygiene). Toggle
    /// via View → Load Remote Images, or by clicking any remote-image
    /// placeholder in the rendered document.
    @AppStorage("mdv_load_remote_images") private var loadRemoteImages: Bool = false

    /// Watches the currently-loaded file so external-editor saves push
    /// fresh content into the viewer automatically.
    @State private var fileWatcher = FileWatcher()

    /// Browser-style back stack. Each entry pairs a HistoryEntry with the
    /// top-visible block index at the moment we left, so ⌘← restores
    /// both the file *and* the scroll position. Pushed by every
    /// navigation that changes the current view: cross-doc link clicks,
    /// sidebar selection, ⌘O, drag-drop, history search, bookmark jumps,
    /// and same-doc fragment clicks. ⌘← pops it. The
    /// `.onChange(of: selectedEntry)` handler in `body` covers cross-doc
    /// pushes; same-doc fragment pushes happen inline in `handleLinkClick`
    /// because `selectedEntry` doesn't change on a fragment-only click.
    /// `goBack` / `goForward` suppress the centralized push via
    /// `suppressBackStackPush` so stack walks don't push themselves back on.
    @State private var backStack: [NavSnapshot] = []
    /// Forward stack — populated when the user goes back, so ⌘→ can
    /// re-enter what they just left. Cleared on any fresh navigation that
    /// branches the history (i.e. anything that pushes onto backStack).
    @State private var forwardStack: [NavSnapshot] = []
    /// Last value of `selectedEntry` — `.onChange` reads this to know
    /// what to push to `backStack`. macOS 13's single-arg onChange
    /// doesn't surface the old value directly.
    @State private var previousSelectedEntry: HistoryEntry?
    /// Set true by `goBack` / `goForward` immediately before they mutate
    /// `selectedEntry` so the resulting onChange tick skips the backStack
    /// push. Cleared at the end of that tick.
    @State private var suppressBackStackPush = false
    /// Mirror of `topVisibleBlock` updated via `.onChange`. Used as the
    /// "scroll snapshot we're leaving" when pushing onto `backStack`,
    /// because the computed `topVisibleBlock` reflects whatever's visible
    /// *now* — by the time we want to capture it on a navigation event,
    /// `visibleBlocks` may have started churning.
    @State private var currentTopBlock: Int = 0
    /// If a fragment-bearing link triggers a cross-document load, the
    /// fragment is stashed here and consumed once `rawMarkdown` updates
    /// (the headings only exist after the file is read).
    @State private var pendingFragment: String? = nil

    // Bookmarks pane (lives below TOC inside the inspector)
    @AppStorage("mdv_bookmarks_height") private var bookmarksHeight: Double = 240
    @AppStorage("mdv_bookmarks_expanded") private var bookmarksExpandedRaw: Bool = false
    @State private var bookmarksDividerHovered = false
    @State private var hoveredBookmark: Int64? = nil
    @State private var dropTargetBookmarkID: Int64? = nil
    @State private var hoveredPlaceholder = false

    /// Block-indices currently visible in the markdown viewport. Updated via
    /// each block's .onAppear / .onDisappear. The minimum is the topmost
    /// visible block, which is what we anchor a new bookmark to.
    @State private var visibleBlocks: Set<Int> = []
    /// Block the mouse is currently hovering. Drives the bookmark-anchor
    /// indicator (subtle accent stripe + tint) so the user can see what
    /// ⌘D will bookmark — there's no caret in a viewer.
    @State private var hoveredBlock: Int? = nil
    /// When non-nil, the markdown view scrolls to this block on next layout.
    /// Used after loading a file via a bookmark / ⌘0 to land on the anchor.
    @State private var pendingAnchorBlock: Int? = nil
    /// Set by jumpTo(...) when the file is being reloaded; consumed once the
    /// new document's blocks are computed. We can't resolve the fingerprint
    /// against the document until rawMarkdown updates.
    @State private var pendingPostLoadAnchor: (blockIndex: Int, fingerprint: String)? = nil
    /// Mirror of `selectedEntry` updated *after* `loadCurrentEntry` runs, so
    /// we always know which file is currently in `rawMarkdown` independently
    /// of `selectedEntry` (which flips synchronously when a sidebar click /
    /// link / bookmark jump fires, before `loadCurrentEntry` mutates
    /// `rawMarkdown`). Used by the cross-doc onChange handler to identify
    /// the file being left so we can persist its scroll position before
    /// `rawMarkdown` flips to the new file.
    @State private var lastLoadedEntry: HistoryEntry? = nil
    /// Set by `loadCurrentEntry` immediately before it mutates `rawMarkdown`.
    /// The `.onChange(of: rawMarkdown)` handler consumes this to decide
    /// whether to restore a saved scroll position. Gating on this flag means
    /// FileWatcher-driven reloads (the user is reading and the file gets
    /// rewritten by an external editor) do NOT snap the viewport back —
    /// FileWatcher mutates rawMarkdown directly, bypassing `loadCurrentEntry`.
    @State private var pendingScrollRestore: Bool = false

    /// In-memory placeholder slot (⌘0). Holds "the spot I want to flip back to."
    /// Not persisted — pure per-window navigation state, like Vim's last-jump
    /// register but bidirectional.
    struct PlaceholderAnchor: Equatable {
        let path: String
        let title: String
        let blockIndex: Int
        let blockFingerprint: String
    }
    @State private var placeholder: PlaceholderAnchor? = nil

    /// Highlights "the bookmark you're currently on" in the panel. Set by
    /// loadBookmark / addBookmarkAtCurrentSpot; cleared by any non-bookmark
    /// file-open path (history click, drag-drop, ⌘O, Open-URL).
    @State private var currentBookmarkID: Int64? = nil
    /// Same idea for the ⌘0 placeholder row.
    @State private var placeholderIsCurrent: Bool = false
    /// Suppresses the clear-on-selectedEntry-change in onChange while a
    /// bookmark navigation is in flight (which itself flips selectedEntry).
    @State private var bookmarkNavInProgress: Bool = false

    struct TOCHeading: Identifiable {
        let level: Int
        let text: String
        let blockIndex: Int
        var id: Int { blockIndex }
    }

    // Find
    @State private var isSearching = false
    @State private var query = ""
    @State private var matches: [SearchMatch] = []
    @State private var currentMatchIndex: Int = 0
    @State private var findFieldRequestFocus: Bool = false
    @StateObject private var keyMonitor = KeyMonitor()

    // Global (cross-history) search
    @State private var globalQuery: String = ""
    @State private var globalSearchVisible: Bool = false
    @State private var globalHits: [Database.SearchHit] = []
    @State private var globalSearchToken: Int = 0
    @State private var hoveredHit: UUID? = nil
    @FocusState private var globalSearchFocused: Bool

    /// Tracks which pane the user most recently clicked into, so Cmd-F can route
    /// the find action correctly. SwiftUI's List on macOS doesn't reliably hand
    /// first-responder status to its underlying NSTableView, and `simultaneousGesture`
    /// loses to the text-selection gesture inside the markdown view — so we hook an
    /// NSEvent local mouse-down monitor and classify clicks by x-coordinate relative
    /// to the sidebar.
    enum PaneFocus { case sidebar, viewer }
    @StateObject private var paneTracker = PaneTracker()

    final class PaneTracker: ObservableObject {
        @Published var lastFocusedPane: PaneFocus = .viewer
        var sidebarRightEdge: CGFloat = 240
        private var monitor: Any?

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                // Only classify clicks that land inside an actual content window.
                // Menu-bar items, popovers, etc. have nil event.window and would
                // otherwise misclassify by their screen-space x-coordinate.
                guard let window = event.window else { return event }
                let p = event.locationInWindow
                // Skip the title bar / toolbar strip — clicking the title doesn't
                // mean the user shifted focus into the viewer pane.
                let titleBarHeight: CGFloat = 52
                guard p.y < window.frame.height - titleBarHeight else { return event }
                self.lastFocusedPane = (p.x <= self.sidebarRightEdge) ? .sidebar : .viewer
                return event
            }
        }

        func uninstall() {
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        }

        deinit { uninstall() }
    }

    struct SearchMatch: Equatable {
        let blockIndex: Int
    }

    final class KeyMonitor: ObservableObject {
        private var monitor: Any?

        func install(onEscape: @escaping () -> Void) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    onEscape()
                    return nil
                }
                return event
            }
        }

        func uninstall() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit { uninstall() }
    }

    private let minSidebarWidth: CGFloat = 180
    private let maxSidebarWidth: CGFloat = 400

    var body: some View {
        ZStack {
            // Solid theme color extending under the (transparent) title bar
            // and behind every pane. The pane backgrounds paint over this
            // for the rest of the window, so all that's left visible from
            // this layer is the strip behind the unified title-bar/toolbar.
            themes.current.background
                .ignoresSafeArea()
            layoutBody
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarColorScheme(themes.current.isDark ? .dark : .light, for: .windowToolbar)
        .preferredColorScheme(themes.current.isDark ? .dark : .light)
        .environment(\.openURL, OpenURLAction { url in handleLinkClick(url) })
        .background(WindowAccessor { window in
            applyThemeToWindow(window)
        })
        .onChange(of: themes.current.id) { _ in
            for window in NSApp.windows { applyThemeToWindow(window) }
        }
        .onChange(of: selectedEntry) { _ in
            // Cross-doc back-stack push. Skip if a stack walk
            // (goBack/goForward) is in progress, if there's no previous
            // entry (first load), or if the path didn't actually change
            // (history.add creates a fresh entry on every visit — those
            // re-visits shouldn't clutter the stack). `currentTopBlock`
            // here still reflects the doc we're leaving because the new
            // doc's blocks haven't fired their onAppear yet.
            let leavingTop = currentTopBlock
            defer {
                suppressBackStackPush = false
                previousSelectedEntry = selectedEntry
                // New doc — visibleBlocks will repopulate from 0 upward
                // as blocks appear; reset the mirror so we don't carry
                // the leaving doc's value.
                currentTopBlock = 0
            }
            guard !suppressBackStackPush,
                  let prev = previousSelectedEntry,
                  prev.path != selectedEntry?.path else { return }
            backStack.append(NavSnapshot(entry: prev, topBlockIndex: leavingTop))
            forwardStack.removeAll()
        }
        .onChange(of: topVisibleBlock) { newValue in
            currentTopBlock = newValue
        }
    }

    /// HStack + toolbar + every notification / lifecycle handler. Split out
    /// from `body` because the full modifier chain blew the SwiftUI
    /// type-checker's expression-complexity budget when theming modifiers
    /// were stacked on top.
    private var layoutBody: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                sidebar
                    .frame(width: sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                dragHandle
            } else {
                edgeGutter
            }

            markdownView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if inspectorVisible {
                Divider()
                inspectorPanel
                    .frame(width: inspectorWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: inspectorVisible)
        .animation(.easeOut(duration: 0.22), value: sidebarCollapsed)
        .navigationTitle(selectedEntry?.filename ?? "mdv")
        .toolbar { toolbarContent }
        .modifier(NotificationHandlers(
            openFile: openFileDialog,
            openFileInNewWindow: openFileDialogInNewWindow,
            openURLInWindow: { url in loadFile(url) },
            findInDocument: {
                if shouldRouteToGlobalSearch() { focusGlobalSearch() } else { openFind() }
            },
            searchHistory: focusGlobalSearch,
            toggleBookmark: addBookmarkAtCurrentSpot,
            openBookmarkSlot: { n in openBookmarkSlot(n) },
            setPlaceholder: setPlaceholder,
            jumpToPlaceholder: jumpToPlaceholder,
            chooseExternalEditor: pickEditor,
            openInExternalEditor: {
                if editorAppPath.isEmpty { pickEditor() } else { openCurrentFileInEditor() }
            },
            forgetExternalEditor: { editorAppPath = "" },
            navigateBack: goBack,
            navigateForward: goForward,
            toggleSidebar: toggleSidebar
        ))
        .onOpenURL { url in
            loadFile(url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onChange(of: selectedEntry) { _ in
            // Persist the leaving file's scroll position FIRST, before we touch
            // `rawMarkdown` via `loadCurrentEntry`. We deliberately use
            // `lastLoadedEntry` (mirror updated *after* loadCurrentEntry on
            // prior ticks) instead of `previousSelectedEntry` (which is
            // managed by the back-stack handler on `body` and whose
            // observation order vs. this handler isn't guaranteed). At this
            // point `rawMarkdown` and `blocks` still reflect that file.
            if let leaving = lastLoadedEntry, leaving.path != selectedEntry?.path {
                persistScrollPosition(for: leaving)
            }
            // Selection changed by something other than a bookmark/placeholder
            // jump? Then drop the "active bookmark" highlight.
            if !bookmarkNavInProgress {
                currentBookmarkID = nil
                placeholderIsCurrent = false
            }
            bookmarkNavInProgress = false
            loadCurrentEntry()
            lastLoadedEntry = selectedEntry
        }
        .onChange(of: rawMarkdown) { _ in
            if isSearching { recomputeMatches() }
            // Visible-block tracking carries indices from the leaving doc.
            // We can't just `removeAll()`: SwiftUI's `ForEach(id: \.offset)`
            // keeps blocks with the same offset mounted across a doc swap,
            // so their `.onAppear` does NOT refire on the new doc — wiping
            // the set leaves it permanently empty for indices that share
            // identity with the old doc, and `topVisibleBlock` collapses
            // to 0 even when the user is reading mid-document. Instead,
            // drop only the indices that don't exist in the new doc; the
            // surviving entries correctly reflect blocks still on screen
            // (because their views were never unmounted), and SwiftUI's
            // `.onAppear` / `.onDisappear` will manage the rest as the
            // user scrolls.
            visibleBlocks = visibleBlocks.filter { $0 < blocks.count }
            // Anchor precedence on a new document load:
            //   1. bookmark / placeholder jump (pendingPostLoadAnchor)
            //   2. fragment link click (pendingFragment)
            //   3. saved scroll position from a previous visit
            // Bookmarks set pendingAnchorBlock; fragments scroll asynchronously
            // via tocScrollTrigger. Either claims the spot — only restore the
            // saved scroll position if neither did.
            var anchorClaimed = false
            if let anchor = pendingPostLoadAnchor {
                let resolved = resolveBookmarkAnchor(
                    blocks: blocks,
                    storedIndex: anchor.blockIndex,
                    fingerprint: anchor.fingerprint
                )
                pendingPostLoadAnchor = nil
                pendingAnchorBlock = resolved
                anchorClaimed = true
            }
            // Cross-document fragment scroll, deferred until headings exist.
            if let frag = pendingFragment {
                pendingFragment = nil
                // One runloop tick so tocHeadings is up-to-date for the new content.
                DispatchQueue.main.async { scrollToFragment(frag) }
                anchorClaimed = true
            }
            // Restore the scroll position on every fresh-from-disk load
            // (`pendingScrollRestore` is set by `loadCurrentEntry`).
            // FileWatcher reloads mutate rawMarkdown directly without
            // setting the flag, so external edits don't yank the viewport
            // back to where the user last left off.
            //
            // Always end up setting `pendingAnchorBlock` to *something*,
            // even on a never-visited file or an invalidated anchor —
            // ScrollView retains its offset across doc swaps, so leaving
            // `pendingAnchorBlock` nil leaves the user wherever the
            // previous doc was scrolled to. Defaulting to 0 (top of doc)
            // makes the landing deterministic.
            let shouldRestoreScroll = pendingScrollRestore && !anchorClaimed
            pendingScrollRestore = false
            if shouldRestoreScroll, let entry = selectedEntry {
                var landingBlock = 0
                if let saved = Database.shared.loadScrollPosition(path: entry.path),
                   saved.blockIndex > 0 {
                    // Two safety nets before honoring the saved anchor:
                    //   1. mtime — markdown files change behind our back
                    //      (user edits in another app, git checkout,
                    //      etc.). If the file's mtime differs from what
                    //      we recorded, treat the anchor as stale and
                    //      fall back to the top rather than dropping the
                    //      user into possibly-shifted content. The
                    //      fingerprint handles *small* edits; mtime is
                    //      the bigger hammer.
                    //   2. bounds — if the recorded index is past the
                    //      end of the (now shorter) document, fall back
                    //      to the top explicitly rather than silently
                    //      clamping to the last block.
                    let currentMtime = (try? FileManager.default.attributesOfItem(atPath: entry.path)[.modificationDate] as? Date)??.timeIntervalSince1970
                    let mtimeMatches = currentMtime.map { abs($0 - saved.fileMtime) < 1.0 } ?? false
                    let inBounds = saved.blockIndex < blocks.count
                    if mtimeMatches && inBounds {
                        landingBlock = resolveBookmarkAnchor(
                            blocks: blocks,
                            storedIndex: saved.blockIndex,
                            fingerprint: saved.blockFingerprint
                        )
                    }
                }
                pendingAnchorBlock = landingBlock
            }
        }
        .onChange(of: isSearching) { active in
            if active {
                keyMonitor.install(onEscape: { closeFind() })
            } else {
                keyMonitor.uninstall()
            }
        }
        .onAppear {
            paneTracker.sidebarRightEdge = sidebarCollapsed ? 0 : (sidebarWidth + 8) // include drag handle width
            paneTracker.install()
            if let url = initialURL {
                loadFile(url)
            } else if let last = history.entries.first {
                selectedEntry = last
                loadCurrentEntry()
                lastLoadedEntry = last
            }
        }
        .onDisappear {
            // Window close / app quit: persist the current file's scroll
            // position so the next launch lands on the same spot.
            if let entry = selectedEntry {
                persistScrollPosition(for: entry)
            }
            paneTracker.uninstall()
        }
        .onChange(of: sidebarWidth) { newValue in
            if !sidebarCollapsed {
                paneTracker.sidebarRightEdge = newValue + 8
            }
        }
    }

    /// Pushes the current theme into the host NSWindow. We let SwiftUI's
    /// `.toolbarBackground(...)` paint the unified title-bar/toolbar strip,
    /// and use the AppKit window only for things SwiftUI can't reach:
    ///
    /// - solid `backgroundColor` so empty regions / window edges show theme
    ///   instead of the desktop bleeding through
    /// - `appearance` so the traffic-light buttons and any remaining
    ///   system-tinted chrome flip with the theme's light/dark preference
    private func applyThemeToWindow(_ window: NSWindow) {
        let theme = themes.current
        let bg = NSColor(theme.background)

        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = bg
        window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)

        // SwiftUI's `.toolbarBackground(.hidden, for: .windowToolbar)`
        // only hides the *material*; the underlying NSView for the title
        // bar / toolbar strip is still opaque, paints itself with the
        // system frame color, and covers everything we did above. Force
        // its backing layer to the theme color so the strip actually
        // matches the rest of the window.
        //
        // The titlebar container view holds the traffic-light area AND
        // the toolbar items, so coloring it once handles the whole
        // unified strip. Walked from `closeButton.superview.superview`
        // because Apple's view-hierarchy class names (`_NSTitlebarView`,
        // `_NSTitlebarContainerView`) are private — the relative path is
        // the stable handle.
        if let titlebar = window.standardWindowButton(.closeButton)?.superview,
           let container = titlebar.superview {
            container.wantsLayer = true
            container.layer?.backgroundColor = bg.cgColor
            titlebar.wantsLayer = true
            titlebar.layer?.backgroundColor = bg.cgColor
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(themes.current.tertiaryText)
                Spacer()
                if !globalSearchVisible {
                    Button {
                        withAnimation(.easeOut(duration: 0.20)) {
                            globalSearchVisible = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            globalSearchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(themes.current.tertiaryText)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Search history")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if globalSearchVisible {
                sidebarSearchField
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !globalQuery.isEmpty {
                globalSearchResults
            } else if history.entries.isEmpty {
                emptyHistory
            } else {
                historyList
            }
        }
        .background(themes.current.secondaryBackground)
        .environment(\.colorScheme, themes.current.isDark ? .dark : .light)
        .tint(themes.current.accent)
    }

    private func closeSidebarSearch() {
        clearGlobalSearch()
        withAnimation(.easeOut(duration: 0.20)) {
            globalSearchVisible = false
        }
    }

    private var historyList: some View {
        List(selection: $selectedEntry) {
            ForEach(history.entries) { entry in
                sidebarRow(entry)
                    .tag(entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            delete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)])
                        }
                        Divider()
                        Button(role: .destructive) {
                            delete(entry)
                        } label: {
                            Text("Remove from History")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Sidebar search field

    private var sidebarSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(themes.current.secondaryText)
            TextField("Search history", text: $globalQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(themes.current.text)
                .focused($globalSearchFocused)
                .onSubmit {
                    if let first = globalHits.first { openHit(first) }
                }
                .onExitCommand {
                    closeSidebarSearch()
                }
            Button(action: closeSidebarSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(themes.current.tertiaryText)
            }
            .buttonStyle(.plain)
            .help("Close (esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(themes.current.text.opacity(globalSearchFocused ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(globalSearchFocused ? themes.current.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: globalSearchFocused)
        .onChange(of: globalQuery) { _ in runGlobalSearch() }
    }

    // MARK: - Global search results

    private var globalSearchResults: some View {
        Group {
            if globalHits.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text("\(globalHits.count) match\(globalHits.count == 1 ? "" : "es")")
                                .font(.system(size: 11, weight: .semibold))
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .foregroundStyle(.tertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 6)

                        ForEach(globalHits) { hit in
                            hitRow(hit)
                                .contextMenu {
                                    Button("Open") { openHit(hit) }
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hit.path)])
                                    }
                                }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func hitRow(_ hit: Database.SearchHit) -> some View {
        let isHovered = hoveredHit == hit.id
        let isCurrent = selectedEntry?.path == hit.path

        return Button {
            openHit(hit)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(isCurrent ? Color.white : Color.secondary)
                    Text(hit.filename)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isCurrent ? Color.white : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                snippetView(hit.snippet, dim: isCurrent)
                    .font(.system(size: 11))
                    .foregroundStyle(isCurrent ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Group {
                    if isCurrent {
                        Text(prettyPath(hit.path)).foregroundStyle(Color.white.opacity(0.7))
                    } else {
                        Text(prettyPath(hit.path)).foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.head)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isCurrent ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { inside in
            hoveredHit = inside ? hit.id : nil
        }
    }

    /// Render an FTS5 snippet, bolding the marked match spans (delimited by U+0002/U+0003).
    private func snippetView(_ snippet: String, dim: Bool) -> Text {
        var out = Text("")
        var inMatch = false
        var buffer = ""
        let flush: (inout Text, String, Bool) -> Void = { acc, str, hl in
            guard !str.isEmpty else { return }
            if hl {
                acc = acc + Text(str).fontWeight(.semibold).foregroundColor(dim ? .white : .primary)
            } else {
                acc = acc + Text(str)
            }
        }
        for ch in snippet {
            if ch == "\u{2}" {
                flush(&out, buffer, inMatch); buffer.removeAll()
                inMatch = true
            } else if ch == "\u{3}" {
                flush(&out, buffer, inMatch); buffer.removeAll()
                inMatch = false
            } else {
                buffer.append(ch)
            }
        }
        flush(&out, buffer, inMatch)
        return out
    }

    // MARK: - Global search actions

    private func runGlobalSearch() {
        let q = globalQuery
        globalSearchToken &+= 1
        let token = globalSearchToken
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            globalHits = []
            return
        }
        Database.shared.search(query: q) { hits in
            // Drop stale results from a query the user has since edited.
            guard token == globalSearchToken else { return }
            globalHits = hits
        }
    }

    private func openHit(_ hit: Database.SearchHit) {
        let q = globalQuery
        if let entry = history.entries.first(where: { $0.path == hit.path }) {
            selectedEntry = entry
        } else {
            // Fallback if the file is in the index but not in the in-memory history
            // (shouldn't happen today, but guards against future drift).
            loadFile(URL(fileURLWithPath: hit.path))
        }
        // Keep the search field focused and the hit list visible so the user can
        // click multiple results in turn without re-typing. Seed the in-document find
        // with the same query so matches in the rendered article are highlighted.
        // recomputeMatches() runs explicitly because the findBar's onChange(of: query)
        // only fires while the bar is in the view hierarchy, but we set query before
        // isSearching flips on.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            query = q
            recomputeMatches()
            withAnimation(.easeOut(duration: 0.18)) {
                isSearching = true
            }
            // The button click stole focus from the search field; restore it so the
            // user can keep typing or just hit ↑/↓ to walk through results.
            globalSearchFocused = true
        }
    }

    private func clearGlobalSearch() {
        globalQuery = ""
        globalHits = []
        globalSearchFocused = false
    }

    private func focusGlobalSearch() {
        if !globalSearchVisible {
            withAnimation(.easeOut(duration: 0.20)) {
                globalSearchVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                globalSearchFocused = true
            }
        } else {
            globalSearchFocused = true
        }
    }

    /// Cmd-F is context-sensitive: if the user is currently working inside the sidebar
    /// (either list or search field), it focuses the global search. Anywhere else,
    /// it opens the in-document find bar.
    private func shouldRouteToGlobalSearch() -> Bool {
        if globalSearchFocused { return true }
        return paneTracker.lastFocusedPane == .sidebar
    }

    private func sidebarRow(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(themes.current.secondaryText)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.filename)
                    .font(.system(size: 13))
                    .foregroundStyle(themes.current.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(prettyPath(entry.path))
                    .font(.system(size: 11))
                    .foregroundStyle(themes.current.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 2)
    }

    private var emptyHistory: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No files yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ entry: HistoryEntry) {
        let wasSelected = selectedEntry?.id == entry.id
        history.remove(entry)
        if wasSelected {
            selectedEntry = history.entries.first
        }
    }

    private func prettyPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Theme Menu (toolbar)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: openFileDialog) {
                Image(systemName: "plus")
            }
            .help("Open file (⌘O)")
        }
        ToolbarItem(placement: .primaryAction) { editButton }
        ToolbarItem(placement: .primaryAction) { themeMenu }
        ToolbarItem(placement: .primaryAction) {
            Button {
                addBookmarkAtCurrentSpot()
            } label: {
                Image(systemName: hasAnyBookmarkForCurrentFile ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(hasAnyBookmarkForCurrentFile ? Color.accentColor : Color.primary)
            }
            .help("Bookmark Current Spot (⌘D)")
            .disabled(selectedEntry == nil)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                inspectorVisible.toggle()
                if inspectorVisible { bookmarks.refreshFileExistence() }
            } label: {
                Image(systemName: "sidebar.right")
                    .foregroundStyle(inspectorVisible ? Color.accentColor : Color.primary)
            }
            .help("Toggle Inspector (⌥⌘0)")
            .keyboardShortcut("0", modifiers: [.command, .option])
        }
    }

    /// Toolbar pop-up menu for switching the document theme. Shows a paintpalette
    /// icon (no label) so it stays visually unobtrusive next to the other toolbar
    /// glyphs; the popup itself shows full theme names with a checkmark on the
    /// active one. Selection persists via ThemeManager (@AppStorage).
    private var themeMenu: some View {
        Menu {
            Button {
                themes.setSelection(ThemeManager.systemID)
            } label: {
                if themes.selectedID == ThemeManager.systemID {
                    Label(ThemeManager.systemDisplayName, systemImage: "checkmark")
                } else {
                    Text(ThemeManager.systemDisplayName)
                }
            }
            Divider()
            ForEach(MDVTheme.all) { theme in
                Button {
                    themes.set(theme)
                } label: {
                    if themes.selectedID == theme.id {
                        Label(theme.name, systemImage: "checkmark")
                    } else {
                        Text(theme.name)
                    }
                }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(themeMenuHelpText)
    }

    private var themeMenuHelpText: String {
        if themes.selectedID == ThemeManager.systemID {
            return "Theme: System — \(themes.current.name)"
        }
        return "Theme: \(themes.current.name)"
    }

    // MARK: - External editor

    /// Toolbar button that opens the current file in the user's chosen
    /// external editor. First click (no editor saved yet) pops the picker;
    /// afterwards the choice is remembered in `@AppStorage`. The picker
    /// itself lives in the File menu so the toolbar stays single-purpose.
    private var editButton: some View {
        Button {
            if editorAppPath.isEmpty {
                pickEditor()
            } else {
                openCurrentFileInEditor()
            }
        } label: {
            Image(systemName: "pencil")
        }
        .disabled(!editorAppPath.isEmpty && selectedEntry == nil)
        .help(editorAppPath.isEmpty
              ? "Edit (choose an external editor)"
              : "Edit in \(editorDisplayName(forAppPath: editorAppPath))")
    }

    private func editorDisplayName(forAppPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: url),
           let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName")
                       ?? bundle.object(forInfoDictionaryKey: "CFBundleName")) as? String {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func pickEditor() {
        let panel = NSOpenPanel()
        panel.title = "Choose External Editor"
        panel.message = "Pick an application to edit Markdown files in."
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            editorAppPath = url.path
            // If the user picked while a file is open, jump straight in —
            // it's what they were trying to do anyway.
            if selectedEntry != nil { openCurrentFileInEditor() }
        }
    }

    private func openCurrentFileInEditor() {
        guard let entry = selectedEntry else { return }
        guard !editorAppPath.isEmpty else { pickEditor(); return }
        let appURL = URL(fileURLWithPath: editorAppPath)
        let fileURL = URL(fileURLWithPath: entry.path)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: cfg) { _, error in
            if let error = error {
                NSLog("[mdv] failed to open in editor: \(error)")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't open in external editor"
                    alert.informativeText = error.localizedDescription
                    alert.addButton(withTitle: "Choose Different Editor…")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        self.pickEditor()
                    }
                }
            }
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        ZStack {
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
            Rectangle()
                .fill(dragHandleHovered ? themes.current.accent.opacity(0.5) : themes.current.divider)
                .frame(width: dragHandleHovered ? 2 : 1)
                .animation(.easeInOut(duration: 0.15), value: dragHandleHovered)

            // Hover-revealed collapse affordance: a small chevron-left button
            // that fades in only while the mouse is over the divider area.
            // The Button consumes its own click before the surrounding
            // DragGesture sees it, so drag-to-resize and click-to-collapse
            // coexist on the same 8pt strip without a mode toggle.
            collapseChevron(direction: .left, visible: dragHandleHovered) {
                toggleSidebar()
            }
        }
        .onHover { inside in
            dragHandleHovered = inside
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let newWidth = sidebarWidth + value.translation.width
                    sidebarWidth = min(max(newWidth, minSidebarWidth), maxSidebarWidth)
                }
        )
    }

    /// Thin (6pt) hot zone painted on the left edge while the sidebar is
    /// collapsed. The chevron-right expand button stays visible at all
    /// times — when the sidebar is hidden there's no other cue that it
    /// can be brought back, so discoverability beats minimalism here.
    /// The 1pt accent-tinted stripe still only appears on hover so the
    /// edge isn't always wearing a visible rule.
    private var edgeGutter: some View {
        ZStack {
            Color.clear
                .frame(width: 6)
                .contentShape(Rectangle())
            Rectangle()
                .fill(edgeGutterHovered ? themes.current.accent.opacity(0.5) : Color.clear)
                .frame(width: edgeGutterHovered ? 2 : 1)
                .animation(.easeInOut(duration: 0.15), value: edgeGutterHovered)

            collapseChevron(direction: .right, visible: true) {
                toggleSidebar()
            }
        }
        .onHover { inside in
            edgeGutterHovered = inside
        }
    }

    /// Shared chevron button used by both the expanded-state drag handle
    /// (chevron points left → collapse) and the collapsed-state edge
    /// gutter (chevron points right → expand). Fades in/out on hover via
    /// `.opacity` so the surrounding strip doesn't reflow when the mouse
    /// arrives or leaves. Sized small (16×22) and placed in the top
    /// quarter of the strip — high enough to feel like an affordance, not
    /// a button bar.
    private enum ChevronDirection { case left, right }

    private func collapseChevron(direction: ChevronDirection, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(themes.current.text.opacity(0.55))
                .frame(width: 16, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(themes.current.background.opacity(0.85))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(themes.current.divider, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.18), value: visible)
        .help(direction == .left ? "Hide Sidebar (⌃⌘S)" : "Show Sidebar (⌃⌘S)")
        // Anchor near the top of the strip so the button is in a
        // glanceable, predictable spot — not floating in dead center.
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 14)
        .allowsHitTesting(visible)
    }

    private func toggleSidebar() {
        sidebarCollapsed.toggle()
        // Pane tracker classifies clicks by x-coord against the right edge
        // of the sidebar (drag handle included). Collapsed → 0 means every
        // click routes to the viewer pane, so ⌘F lands in the in-doc find.
        paneTracker.sidebarRightEdge = sidebarCollapsed ? 0 : (sidebarWidth + 8)
    }

    // MARK: - Markdown View

    private var markdownView: some View {
        Group {
            if rawMarkdown.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(blocks.enumerated()), id: \.offset) { (idx, block) in
                                blockView(block: block, idx: idx)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(blockBackground(forBlock: idx))
                                            .animation(.easeOut(duration: 0.18), value: currentMatchIndex)
                                            .animation(.easeOut(duration: 0.18), value: matches)
                                            .animation(.easeOut(duration: 0.18), value: isSearching)
                                            .animation(.easeOut(duration: 0.12), value: hoveredBlock)
                                    )
                                    .overlay(alignment: .leading) {
                                        // Accent stripe along the left edge of the hovered block —
                                        // this is the "you will bookmark here" affordance, since a
                                        // read-only viewer has no insertion caret.
                                        if hoveredBlock == idx && highlightColor(forBlock: idx) == .clear {
                                            Rectangle()
                                                .fill(themes.current.accent)
                                                .frame(width: 2)
                                                .padding(.vertical, 1)
                                                .transition(.opacity)
                                        }
                                    }
                                    .id("block-\(idx)")
                                    .onAppear { visibleBlocks.insert(idx) }
                                    .onDisappear {
                                        visibleBlocks.remove(idx)
                                        if hoveredBlock == idx { hoveredBlock = nil }
                                    }
                                    .onHover { inside in
                                        if inside {
                                            hoveredBlock = idx
                                        } else if hoveredBlock == idx {
                                            hoveredBlock = nil
                                        }
                                    }
                            }
                        }
                        .textSelection(.enabled)
                        .padding(.horizontal, themes.current.articleHorizontalPadding)
                        .padding(.vertical, 28)
                        .frame(maxWidth: themes.current.articleMaxWidth ?? .infinity, alignment: .leading)
                        .frame(maxWidth: .infinity,
                               alignment: themes.current.articleMaxWidth == nil ? .leading : .center)
                    }
                    .onChange(of: currentMatchIndex) { _ in
                        scrollToCurrentMatch(proxy: proxy)
                    }
                    .onChange(of: tocScrollTrigger) { newValue in
                        guard let target = newValue else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("block-\(target)", anchor: .top)
                        }
                        DispatchQueue.main.async {
                            tocScrollTrigger = nil
                        }
                    }
                    .onChange(of: pendingAnchorBlock) { newValue in
                        guard let target = newValue else { return }
                        // The blocks may not all be laid out yet on first paint —
                        // give SwiftUI a tick before scrolling.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("block-\(target)", anchor: .top)
                            }
                            pendingAnchorBlock = nil
                        }
                    }
                }
            }
        }
        .background(themes.current.background)
        .environment(\.colorScheme, themes.current.isDark ? .dark : .light)
        .overlay(alignment: .topTrailing) {
            if !isSearching {
                Button {
                    openFind()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(themes.current.secondaryText)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle().fill(themes.current.secondaryBackground)
                        )
                        .overlay(
                            Circle().stroke(themes.current.border, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                .padding(.trailing, 12)
                .help("Find in document (⌘F)")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if isSearching {
                findBar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.20), value: isSearching)
    }

    private var blocks: [String] {
        // Fence-aware split. A blank line ends a paragraph block normally,
        // but blank lines INSIDE a fenced code block (``` or ~~~) are part
        // of the code and must not split the block — otherwise multi-
        // paragraph code samples get shredded into separate single-line
        // code-blocks-or-prose, which mangles syntax highlighting.
        var result: [String] = []
        var current: [String] = []
        var fenceMarker: String? = nil  // nil → outside, "```" or "~~~" → inside
        let lines = rawMarkdown.components(separatedBy: "\n")

        func flush() {
            let joined = current.joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !joined.isEmpty { result.append(joined) }
            current.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmedStart = line.drop(while: { $0 == " " })
            if let marker = fenceMarker {
                current.append(line)
                if trimmedStart.hasPrefix(marker) {
                    fenceMarker = nil
                }
                continue
            }
            if trimmedStart.hasPrefix("```") {
                if !current.isEmpty { flush() }
                current.append(line)
                fenceMarker = "```"
                continue
            }
            if trimmedStart.hasPrefix("~~~") {
                if !current.isEmpty { flush() }
                current.append(line)
                fenceMarker = "~~~"
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return result
    }

    // MARK: - Table of Contents

    private var tocHeadings: [TOCHeading] {
        var result: [TOCHeading] = []
        for (idx, block) in blocks.enumerated() {
            let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip fenced code blocks even if they start with #
            if trimmed.hasPrefix("```") { continue }
            let level: Int
            let prefix: String
            if trimmed.hasPrefix("### ") {
                level = 3; prefix = "### "
            } else if trimmed.hasPrefix("## ") {
                level = 2; prefix = "## "
            } else if trimmed.hasPrefix("# ") {
                level = 1; prefix = "# "
            } else {
                continue
            }
            // Single-line headings only
            let firstLine = trimmed.components(separatedBy: "\n").first ?? trimmed
            let raw = String(firstLine.dropFirst(prefix.count))
            let text = stripInlineMarkdown(raw)
            result.append(TOCHeading(level: level, text: text, blockIndex: idx))
        }
        return result
    }

    /// `tocHeadings`, optionally narrowed to entries matching `tocSearchQuery`
    /// (case-/diacritic-insensitive substring on the heading text). Empty
    /// query passes everything through.
    private var filteredTocHeadings: [TOCHeading] {
        let q = tocSearchQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tocHeadings }
        return tocHeadings.filter {
            $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private func stripInlineMarkdown(_ s: String) -> String {
        var out = s
        // Trailing #'s of ATX headings
        out = out.replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
        // Inline code / bold / italic markers
        out = out.replacingOccurrences(of: "**", with: "")
        out = out.replacingOccurrences(of: "__", with: "")
        out = out.replacingOccurrences(of: "`", with: "")
        // Bare * and _ around words (single-char emphasis)
        out = out.replacingOccurrences(of: #"(?<!\\)\*"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: #"(?<![A-Za-z0-9])_(?=[^_]+_)"#, with: "", options: .regularExpression)
        // Markdown links [text](url) → text
        out = out.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        return out.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Right inspector (TOC + Bookmarks)

    private var inspectorPanel: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                tocPane
                    .frame(maxHeight: .infinity)

                if bookmarksExpandedRaw {
                    inspectorDivider(totalHeight: geo.size.height)
                }

                bookmarksHeader

                if bookmarksExpandedRaw {
                    bookmarksContent
                        .frame(height: clampedBookmarksHeight(total: geo.size.height))
                }
            }
        }
        .background(themes.current.secondaryBackground)
        .environment(\.colorScheme, themes.current.isDark ? .dark : .light)
        .tint(themes.current.accent)
    }

    private func clampedBookmarksHeight(total: CGFloat) -> CGFloat {
        let header: CGFloat = 32
        let minToc: CGFloat = 80
        let minBookmarks: CGFloat = 120
        let maxBookmarks = max(minBookmarks, total - minToc - header - 8)
        return min(max(CGFloat(bookmarksHeight), minBookmarks), maxBookmarks)
    }

    private func inspectorDivider(totalHeight: CGFloat) -> some View {
        ZStack {
            // 12pt-tall transparent hit-target so the divider is comfortably grabbable.
            // The visible 1pt rule is centered inside it.
            Color.clear
                .frame(height: 12)
                .contentShape(Rectangle())
            Rectangle()
                .fill(bookmarksDividerHovered ? themes.current.accent.opacity(0.5) : themes.current.divider)
                .frame(height: bookmarksDividerHovered ? 2 : 1)
                .animation(.easeInOut(duration: 0.15), value: bookmarksDividerHovered)
        }
        .onHover { inside in
            bookmarksDividerHovered = inside
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let header: CGFloat = 32
                    let minToc: CGFloat = 80
                    let minBookmarks: CGFloat = 120
                    let maxBookmarks = max(minBookmarks, totalHeight - minToc - header - 8)
                    let proposed = CGFloat(bookmarksHeight) - value.translation.height
                    bookmarksHeight = Double(min(max(proposed, minBookmarks), maxBookmarks))
                }
        )
    }

    private var tocPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("On this page")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(themes.current.tertiaryText)
                Spacer()
                if !tocSearchVisible {
                    Button {
                        withAnimation(.easeOut(duration: 0.20)) {
                            tocSearchVisible = true
                        }
                        // Focus once the field has appeared. Without the
                        // delay SwiftUI hands the focus request to a view
                        // that doesn't yet exist and the field stays cold.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            tocSearchFocused = true
                        }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(themes.current.tertiaryText)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Filter headings")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if tocSearchVisible {
                tocSearchField
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if tocHeadings.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(themes.current.tertiaryText)
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundStyle(themes.current.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredTocHeadings.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text("No matches")
                        .font(.system(size: 12))
                        .foregroundStyle(themes.current.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredTocHeadings) { heading in
                            tocRow(heading)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var tocSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(themes.current.secondaryText)
            TextField("Filter headings", text: $tocSearchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(themes.current.text)
                .focused($tocSearchFocused)
                .onExitCommand { closeTocSearch() }
            Button(action: closeTocSearch) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(themes.current.tertiaryText)
            }
            .buttonStyle(.plain)
            .help("Close (esc)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(themes.current.text.opacity(tocSearchFocused ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tocSearchFocused ? themes.current.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    private func closeTocSearch() {
        tocSearchQuery = ""
        tocSearchFocused = false
        withAnimation(.easeOut(duration: 0.20)) {
            tocSearchVisible = false
        }
    }

    // MARK: - Bookmarks pane

    private var bookmarksHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: bookmarksExpandedRaw ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(themes.current.tertiaryText)
                .frame(width: 10)
            Text("Bookmarks")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(themes.current.tertiaryText)
            Spacer()
            if !bookmarks.bookmarks.isEmpty {
                Text("\(bookmarks.bookmarks.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(themes.current.tertiaryText)
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(themes.current.text.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.18)) {
                bookmarksExpandedRaw.toggle()
            }
        }
    }

    @ViewBuilder
    private var bookmarksContent: some View {
        if bookmarks.bookmarks.isEmpty && placeholder == nil {
            VStack(spacing: 8) {
                Spacer(minLength: 8)
                Image(systemName: "bookmark")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No bookmarks")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("Press").font(.system(size: 10)).foregroundStyle(.tertiary)
                    keyCap("⌘"); keyCap("D")
                    Text("at a spot in any file").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            bookmarksList
        }
    }

    private var bookmarksList: some View {
        // ScrollView + LazyVStack instead of List because SwiftUI List on macOS
        // doesn't fire .onMove from a plain mouse drag without an explicit drag
        // handle in the row. We use .draggable/.dropDestination (macOS 13+)
        // rather than .onDrag/.onDrop because the latter combo is broken on
        // macOS 14.x — drags from a Button don't fire reliably.
        ScrollView {
            LazyVStack(spacing: 1) {
                if let p = placeholder {
                    placeholderRow(p)
                        .padding(.bottom, 2)
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }

                ForEach(Array(bookmarks.bookmarks.enumerated()), id: \.element.id) { (idx, bookmark) in
                    bookmarkRow(bookmark)
                        .contextMenu {
                            Button("Go to Bookmark") { loadBookmark(bookmark) }
                                .disabled(!bookmark.fileExists)
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bookmark.path)])
                            }
                            .disabled(!bookmark.fileExists)
                            Divider()
                            Button("Move Up") { bookmarks.moveBookmarkUp(id: bookmark.id) }
                                .disabled(idx == 0)
                            Button("Move Down") { bookmarks.moveBookmarkDown(id: bookmark.id) }
                                .disabled(idx >= bookmarks.bookmarks.count - 1)
                            Button("Move to Top") { bookmarks.moveBookmarkToStart(id: bookmark.id) }
                                .disabled(idx == 0)
                            Button("Move to Bottom") { bookmarks.moveBookmarkToEnd(id: bookmark.id) }
                                .disabled(idx >= bookmarks.bookmarks.count - 1)
                            Divider()
                            Button(role: .destructive) {
                                bookmarks.remove(id: bookmark.id)
                            } label: {
                                Text("Remove Bookmark")
                            }
                        }
                        .draggable("mdv-bookmark:\(bookmark.id)") {
                            bookmarkRow(bookmark)
                                .frame(width: inspectorWidth - 12)
                        }
                        .dropDestination(for: String.self) { items, _ in
                            handleBookmarkDrop(items, targetID: bookmark.id)
                        } isTargeted: { hovering in
                            if hovering {
                                dropTargetBookmarkID = bookmark.id
                            } else if dropTargetBookmarkID == bookmark.id {
                                dropTargetBookmarkID = nil
                            }
                        }
                }
                Color.clear
                    .frame(height: 24)
                    .dropDestination(for: String.self) { items, _ in
                        handleBookmarkDrop(items, targetID: nil)
                    }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }

    private func placeholderRow(_ p: PlaceholderAnchor) -> some View {
        let missing = !FileManager.default.fileExists(atPath: p.path)
        let isCurrent = placeholderIsCurrent
        return Button {
            jumpToPlaceholder()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(
                        missing ? Color.orange :
                        (isCurrent ? Color.white : Color.accentColor)
                    )
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(
                            isCurrent ? Color.white :
                            (missing ? Color.secondary : Color.primary)
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(URL(fileURLWithPath: p.path).lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                hotkeyBadge(0, onAccent: isCurrent)
            }
            .opacity(missing && !isCurrent ? 0.6 : 1.0)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isCurrent ? Color.accentColor :
                        (hoveredPlaceholder ? Color.primary.opacity(0.06) : Color.accentColor.opacity(0.08))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isCurrent ? Color.clear : Color.accentColor.opacity(0.25), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredPlaceholder = inside
        }
        .help("Placeholder — ⌘0 to jump here, ⇧⌘0 to overwrite")
        .contextMenu {
            Button("Clear Placeholder") { placeholder = nil }
        }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        let slot = bookmarks.slotIndex(for: bookmark.id)
        let missing = !bookmark.fileExists
        let hovered = hoveredBookmark == bookmark.id
        let dropHover = dropTargetBookmarkID == bookmark.id
        let isCurrent = currentBookmarkID == bookmark.id
        let filename = URL(fileURLWithPath: bookmark.path).lastPathComponent

        return Button {
            loadBookmark(bookmark)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: missing ? "exclamationmark.triangle.fill" : "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        missing ? Color.orange :
                        (isCurrent ? Color.white : Color.accentColor.opacity(0.7))
                    )
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.title.isEmpty ? "(unnamed)" : bookmark.title)
                        .font(.system(size: 13))
                        .foregroundStyle(
                            isCurrent ? Color.white :
                            (missing ? Color.secondary : Color.primary)
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(filename)
                        .font(.system(size: 10))
                        .foregroundStyle(isCurrent ? Color.white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if let n = slot {
                    hotkeyBadge(n, onAccent: isCurrent)
                }
            }
            .opacity(missing && !isCurrent ? 0.6 : 1.0)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(
                        isCurrent ? Color.accentColor :
                        (dropHover ? Color.accentColor.opacity(0.18) :
                        (hovered ? Color.primary.opacity(0.06) : Color.clear))
                    )
            )
            .overlay(alignment: .top) {
                if dropHover {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredBookmark = inside ? bookmark.id : nil
        }
    }

    private func hotkeyBadge(_ n: Int, onAccent: Bool) -> some View {
        HStack(spacing: 0) {
            Text("⌘")
                .font(.system(size: 9, weight: .bold, design: .rounded))
            Text("\(n)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(onAccent ? Color.accentColor : Color.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(onAccent ? Color.white : Color.accentColor.opacity(0.85))
        )
    }

    private func tocRow(_ heading: TOCHeading) -> some View {
        let isCurrent = tocSelectedBlock == heading.blockIndex
        let isHovered = hoveredHeading == heading.blockIndex
        let leadingIndent: CGFloat = CGFloat(heading.level - 1) * 14
        let theme = themes.current
        let foreground: Color = {
            if isCurrent { return theme.background }
            return heading.level == 1 ? theme.text : theme.secondaryText
        }()
        let rowBackground: Color = {
            if isCurrent { return theme.accent }
            if isHovered { return theme.text.opacity(0.08) }
            return .clear
        }()

        return Button {
            // Treat a TOC click like a same-doc fragment click: push a
            // snapshot of where we were so ⌘← can scroll back.
            pushSameDocSnapshot()
            tocSelectedBlock = heading.blockIndex
            tocScrollTrigger = heading.blockIndex
        } label: {
            HStack(spacing: 0) {
                Spacer().frame(width: leadingIndent)
                Text(heading.text)
                    .font(.system(size: 12, weight: heading.level == 1 ? .semibold : .regular))
                    .foregroundStyle(foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(rowBackground)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredHeading = inside ? heading.blockIndex : nil
        }
    }

    // MARK: - Find Bar

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            FindField(
                text: $query,
                placeholder: "Find",
                requestFocus: $findFieldRequestFocus,
                onSubmit: { nextMatch() },
                onEscape: { closeFind() }
            )
            .frame(minWidth: 120)
            if !query.isEmpty {
                Text(matches.isEmpty ? "No matches" : "\(currentMatchIndex + 1) of \(matches.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Divider().frame(height: 16)
            Button(action: previousMatch) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(matches.isEmpty)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Previous match (⇧⌘G)")
            Button(action: nextMatch) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(matches.isEmpty)
            .keyboardShortcut("g", modifiers: .command)
            .help("Next match (⌘G)")
            Button(action: closeFind) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .help("Close (esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 10, x: 0, y: 4)
        .frame(maxWidth: 380)
        .onChange(of: query) { _ in
            recomputeMatches()
        }
    }

    /// Renders one markdown block. If find is active and the block contains
    /// a hit AND the block's structure is one we can losslessly re-render
    /// inline (paragraph / heading / list / blockquote — i.e. not code or
    /// table), swap MarkdownUI for an AttributedString-based Text so we
    /// can paint a yellow highlight on the matched substrings themselves.
    /// Other blocks keep MarkdownUI's full rendering and rely on the
    /// block-level tint for find feedback.
    @ViewBuilder
    private func blockView(block: String, idx: Int) -> some View {
        if shouldInlineHighlight(block: block, idx: idx) {
            // Find-highlight path: render straight punctuation. Smartening
            // here would shift character offsets and misalign the yellow
            // highlight ranges (which were computed against rawMarkdown).
            // The mismatch only surfaces while find is active in matched
            // blocks; everything else still gets smart typography.
            Text(highlightedAttributedString(for: block, idx: idx))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Markdown(smartTypographyEnabled ? smartenMarkdown(block) : block)
                .markdownTheme(themes.current.markdownTheme)
                .markdownCodeSyntaxHighlighter(.mdv(theme: themes.current))
                .markdownImageProvider(LocalImageProvider(
                    baseURL: currentDocumentDirectory,
                    loadRemoteImages: loadRemoteImages
                ))
        }
    }

    /// Whether to apply SmartyPants-style typography on the next render.
    /// Honors both the user's preference and the active theme's opt-out
    /// (Phosphor and Standard Erin Light/Dark force this off).
    private var smartTypographyEnabled: Bool {
        userSmartTypography && themes.current.smartTypographyAllowed
    }

    /// Directory the currently-loaded markdown file lives in. Relative
    /// image URLs in `![alt](path)` are resolved against this so an
    /// adjacent `diagram.png` works the same as it does in any other
    /// markdown viewer / GitHub render.
    private var currentDocumentDirectory: URL? {
        guard let path = selectedEntry?.path else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent()
    }

    /// Intercepts link clicks. md-to-md (and `.markdown` / `.mdown`)
    /// navigates inside the viewer; everything else (https, mailto,
    /// data, file:// to non-markdown) falls through to the system
    /// handler so it lands in the user's default browser / app.
    private func handleLinkClick(_ url: URL) -> OpenURLAction.Result {
        let mdExts: Set<String> = ["md", "markdown", "mdown"]
        let fragment = url.fragment

        // Same-document fragment (#section). Resolve to a heading and
        // scroll there. Push a snapshot of where we were so ⌘← can jump
        // back to it — selectedEntry doesn't change on a same-doc
        // fragment click, so the centralized onChange-based push won't
        // fire here.
        if url.scheme == nil, let frag = fragment, !frag.isEmpty,
           url.path.isEmpty {
            pushSameDocSnapshot()
            scrollToFragment(frag)
            return .handled
        }

        // Resolve into a fully-absolute file URL so downstream logic and
        // any LaunchServices fallback see a well-formed URL. Relative
        // links (`README.md`, `./code.md`, `images/foo.png`) get joined
        // with the current document's parent directory using string-
        // level path arithmetic — `URL(fileURLWithPath:relativeTo:)`
        // makes a relative URL whose `.path` can return just the
        // relative portion, which silently breaks `fileExists(atPath:)`
        // and downstream consumers.
        let resolved: URL = {
            if let scheme = url.scheme, scheme != "file" {
                return url
            }
            let rawPath: String
            if url.scheme == "file" {
                rawPath = url.path
            } else {
                rawPath = url.path
            }
            if rawPath.hasPrefix("/") {
                return URL(fileURLWithPath: rawPath).standardizedFileURL
            }
            guard let base = currentDocumentDirectory else {
                return URL(fileURLWithPath: rawPath).standardizedFileURL
            }
            let joined = (base.path as NSString).appendingPathComponent(rawPath)
            let standardized = (joined as NSString).standardizingPath
            return URL(fileURLWithPath: standardized)
        }()

        // Local markdown that exists? Load it inline.
        if resolved.isFileURL,
           mdExts.contains(resolved.pathExtension.lowercased()),
           FileManager.default.fileExists(atPath: resolved.path) {
            // The back/forward stacks are managed centrally by the
            // `.onChange(of: selectedEntry)` handler in `body`, so a
            // link click that ends up calling `loadFile` will be pushed
            // there. Same-path "fragment only" clicks don't push because
            // the path comparison short-circuits.
            // Cross-document fragment: stash, scroll once the new
            // doc's blocks are computed. Same-document fragment falls
            // out as an immediate scroll because rawMarkdown won't
            // change.
            if let frag = fragment, !frag.isEmpty {
                if selectedEntry?.path == resolved.path {
                    scrollToFragment(frag)
                } else {
                    pendingFragment = frag
                }
            }
            loadFile(resolved)
            return .handled
        }

        // Local non-markdown file → system handler (Preview, etc.).
        // Only if the file exists; otherwise fall through and let the
        // system put up its own "couldn't be opened" dialog with the
        // ORIGINAL URL so the user sees what they actually clicked.
        if resolved.isFileURL, FileManager.default.fileExists(atPath: resolved.path) {
            return .systemAction(resolved)
        }

        // Anything else (http, mailto, custom schemes, broken refs).
        return .systemAction
    }

    private func goBack() {
        guard let prev = backStack.popLast() else { return }
        if let current = selectedEntry {
            forwardStack.append(NavSnapshot(entry: current, topBlockIndex: currentTopBlock))
        }
        applySnapshot(prev)
    }

    private func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = selectedEntry {
            backStack.append(NavSnapshot(entry: current, topBlockIndex: currentTopBlock))
        }
        applySnapshot(next)
    }

    /// Push a snapshot of the current view onto `backStack` for a
    /// within-document jump (TOC click, same-doc fragment link). Clears
    /// the forward stack — a fresh jump branches the history. No-op when
    /// nothing is loaded yet.
    private func pushSameDocSnapshot() {
        guard let current = selectedEntry else { return }
        backStack.append(NavSnapshot(entry: current, topBlockIndex: currentTopBlock))
        forwardStack.removeAll()
    }

    /// Restore a stack frame: switch the file (suppressing the centralized
    /// back-stack push so the walk doesn't push itself back on) and scroll
    /// to the captured block. Same-doc snapshots skip the file switch and
    /// just scroll.
    private func applySnapshot(_ snap: NavSnapshot) {
        if snap.entry.path == selectedEntry?.path {
            tocScrollTrigger = snap.topBlockIndex
        } else {
            suppressBackStackPush = true
            selectedEntry = snap.entry
            // The new doc's blocks aren't laid out synchronously;
            // pendingAnchorBlock is consumed by the ScrollViewReader
            // once the layout settles (~50ms — see its onChange handler).
            pendingAnchorBlock = snap.topBlockIndex
        }
    }

    /// Scrolls the markdown viewport to the heading whose GitHub-flavored
    /// slug matches `fragment`. No-op if there's no match (link is stale
    /// or pointed at something the parser didn't classify as a heading).
    private func scrollToFragment(_ fragment: String) {
        let target = headingSlug(fragment)
        guard let heading = tocHeadings.first(where: { headingSlug($0.text) == target }) else {
            return
        }
        tocScrollTrigger = heading.blockIndex
    }

    /// GitHub-style heading slug: lowercase, drop everything that isn't a
    /// letter, digit, hyphen, or underscore, and collapse runs of
    /// whitespace into single hyphens. Idempotent for already-slug input
    /// so it can be applied to both the URL fragment and the heading
    /// text without thinking about which is which.
    private func headingSlug(_ s: String) -> String {
        var out = ""
        var lastWasHyphen = false
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasHyphen = false
            } else if ch == "-" || ch == "_" {
                if !out.isEmpty {
                    out.append(ch)
                    lastWasHyphen = (ch == "-")
                }
            } else if ch.isWhitespace {
                if !out.isEmpty && !lastWasHyphen {
                    out.append("-")
                    lastWasHyphen = true
                }
            }
        }
        while out.last == "-" || out.last == "_" { out.removeLast() }
        return out
    }

    private func shouldInlineHighlight(block: String, idx: Int) -> Bool {
        guard isSearching, !query.isEmpty else { return false }
        guard matches.contains(where: { $0.blockIndex == idx }) else { return false }
        let trimmed = block.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return false }
        // Crude table detection: header row of pipes followed by an alignment row.
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count >= 2,
           lines[0].contains("|"),
           lines[1].allSatisfy({ "-:| ".contains($0) }) {
            return false
        }
        // Inline-highlight strips block markers and renders via Text, which
        // doesn't render embedded images. Defer to MarkdownUI for any block
        // containing an image so the image survives — the user still gets
        // the block-level yellow tint as a find affordance.
        if trimmed.contains("![") { return false }
        return true
    }

    private func highlightedAttributedString(for block: String, idx: Int) -> AttributedString {
        let theme = themes.current
        let isCurrentBlock = matches.indices.contains(currentMatchIndex)
                          && matches[currentMatchIndex].blockIndex == idx

        // Strip block-level markers per line so the inline render reads
        // cleanly. Lists keep a literal bullet so the user sees the list
        // shape; headings/blockquotes/numbered lists drop the marker.
        let cleaned = block.components(separatedBy: "\n").map { line -> String in
            var l = line
            l = l.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
            l = l.replacingOccurrences(of: #"^[-*+]\s+"#, with: "• ", options: .regularExpression)
            l = l.replacingOccurrences(of: #"^\d+\.\s+"#, with: "", options: .regularExpression)
            return l
        }.joined(separator: "\n")

        var attr: AttributedString
        do {
            attr = try AttributedString(
                markdown: cleaned,
                options: AttributedString.MarkdownParsingOptions(
                    allowsExtendedAttributes: true,
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            attr = AttributedString(cleaned)
        }
        attr.foregroundColor = NSColor(theme.text)

        // Highlight each occurrence of the query. Current-match block gets
        // a stronger yellow so the navigation focus is obvious.
        let alpha = isCurrentBlock ? 0.55 : 0.32
        let highlight = NSColor.systemYellow.withAlphaComponent(alpha)
        var cursor = attr.startIndex
        while cursor < attr.endIndex,
              let range = attr[cursor...].range(of: query, options: .caseInsensitive) {
            attr[range].backgroundColor = highlight
            cursor = range.upperBound
        }
        return attr
    }

    private func recomputeMatches() {
        guard !query.isEmpty else {
            matches = []
            currentMatchIndex = 0
            return
        }
        var found: [SearchMatch] = []
        for (i, block) in blocks.enumerated() {
            var searchRange = block.startIndex..<block.endIndex
            while let r = block.range(of: query, options: .caseInsensitive, range: searchRange) {
                found.append(SearchMatch(blockIndex: i))
                searchRange = r.upperBound..<block.endIndex
            }
        }
        matches = found
        currentMatchIndex = 0
    }

    private func openFind() {
        withAnimation(.easeOut(duration: 0.2)) {
            isSearching = true
        }
        DispatchQueue.main.async {
            findFieldRequestFocus = true
        }
    }

    private func closeFind() {
        withAnimation(.easeOut(duration: 0.2)) {
            isSearching = false
        }
        query = ""
        matches = []
        currentMatchIndex = 0
    }

    private func nextMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matches.count
    }

    private func previousMatch() {
        guard !matches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    }

    private func highlightColor(forBlock idx: Int) -> Color {
        guard isSearching, !matches.isEmpty else { return .clear }
        let isCurrent = matches.indices.contains(currentMatchIndex)
            && matches[currentMatchIndex].blockIndex == idx
        if isCurrent { return Color.yellow.opacity(0.35) }
        if matches.contains(where: { $0.blockIndex == idx }) {
            return Color.yellow.opacity(0.12)
        }
        return .clear
    }

    /// Background fill for a markdown block. Find highlights win over hover so
    /// search-in-progress feedback isn't drowned out by mouse position.
    private func blockBackground(forBlock idx: Int) -> Color {
        let find = highlightColor(forBlock: idx)
        if find != .clear { return find }
        if hoveredBlock == idx { return themes.current.accent.opacity(0.07) }
        return .clear
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard matches.indices.contains(currentMatchIndex) else { return }
        let match = matches[currentMatchIndex]
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("block-\(match.blockIndex)", anchor: .center)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("No file open")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("Drag and drop, or press")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    keyCap("⌘")
                    keyCap("O")
                }
            }
            Button(action: openFileDialog) {
                Text("Open File…")
                    .frame(minWidth: 100)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func keyCap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(minWidth: 16)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }

    // MARK: - Actions

    private func openFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!,
                                     .init(filenameExtension: "markdown")!,
                                     .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Markdown file"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url)
    }

    private func openFileDialogInNewWindow() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!,
                                     .init(filenameExtension: "markdown")!,
                                     .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Markdown file"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        spawnNewWindow(with: url)
    }

    private func spawnNewWindow(with url: URL) {
        let view = ContentView(initialURL: url)
            .environmentObject(history)
            .environmentObject(bookmarks)
            .environmentObject(themes)
            .frame(minWidth: 760, minHeight: 520)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.setContentSize(NSSize(width: 1080, height: 720))
        window.title = url.lastPathComponent
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func loadFile(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue {
            loadDirectory(url)
            return
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return }
        let entry = history.add(path: url.path)
        selectedEntry = entry
    }

    /// When opened with a directory: pick README.md (case-insensitive) — or
    /// the alphabetically-first markdown file if there is no README — as the
    /// document to render, and seed history with the rest of the directory's
    /// markdown files so the sidebar surfaces them as siblings.
    private func loadDirectory(_ url: URL) {
        let exts: Set<String> = ["md", "markdown", "mdown"]
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let mdFiles = contents
            .filter { exts.contains($0.pathExtension.lowercased()) }
            .filter { fm.isReadableFile(atPath: $0.path) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        guard !mdFiles.isEmpty else { return }

        let primary = mdFiles.first {
            $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare("README") == .orderedSame
        } ?? mdFiles[0]

        // Seed siblings into history first (in reverse-alpha order, so once
        // each insert prepends, they end up alphabetical underneath the
        // primary). Primary is added last so it lands at the top.
        let siblings = mdFiles.filter { $0 != primary }.reversed()
        for sibling in siblings {
            _ = history.add(path: sibling.path)
        }
        let entry = history.add(path: primary.path)
        selectedEntry = entry
    }

    // MARK: - Bookmarks

    private var hasAnyBookmarkForCurrentFile: Bool {
        guard let path = selectedEntry?.path else { return false }
        return bookmarks.hasAnyBookmark(forPath: path)
    }

    /// Index of the topmost block currently visible in the markdown viewport.
    /// Falls back to 0 if nothing has reported visible yet.
    private var topVisibleBlock: Int {
        visibleBlocks.min() ?? 0
    }

    /// Compute a human-readable title for a block: nearest preceding ATX heading
    /// if there is one within reach, else the block's own first 40 chars.
    private func bookmarkTitle(forBlockAt index: Int) -> String {
        let docBlocks = self.blocks
        guard !docBlocks.isEmpty else { return "(empty)" }
        let clamped = max(0, min(index, docBlocks.count - 1))
        // Walk backwards looking for a heading. Cap the search so we don't
        // mislabel a deep-in-the-doc bookmark with a very distant section header.
        let lookback = 40
        for i in stride(from: clamped, through: max(0, clamped - lookback), by: -1) {
            let block = docBlocks[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if block.hasPrefix("```") { continue }
            let prefix: String?
            if block.hasPrefix("### ") { prefix = "### " }
            else if block.hasPrefix("## ") { prefix = "## " }
            else if block.hasPrefix("# ") { prefix = "# " }
            else { prefix = nil }
            if let pfx = prefix {
                let firstLine = block.components(separatedBy: "\n").first ?? block
                return stripInlineMarkdown(String(firstLine.dropFirst(pfx.count)))
            }
        }
        // No heading nearby; use the block's own first content line as a label.
        let block = docBlocks[clamped]
        let firstLine = block.components(separatedBy: "\n").first ?? block
        let cleaned = stripInlineMarkdown(firstLine).trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return "(line \(clamped + 1))" }
        return String(cleaned.prefix(60))
    }

    private func currentAnchorTitle() -> String {
        bookmarkTitle(forBlockAt: topVisibleBlock)
    }

    private func currentBlockFingerprint() -> String {
        let docBlocks = self.blocks
        let idx = max(0, min(topVisibleBlock, docBlocks.count - 1))
        guard idx < docBlocks.count else { return "" }
        return bookmarkFingerprint(forBlock: docBlocks[idx])
    }

    private func addBookmarkAtCurrentSpot() {
        guard let entry = selectedEntry else { return }
        // Prefer whatever block the user is currently pointing at. The hover
        // highlight is the "you'll bookmark here" indicator; if no block is
        // hovered (e.g. user pressed ⌘D from a non-mouse path), fall back to
        // the topmost-visible block.
        let block = hoveredBlock ?? topVisibleBlock
        let docBlocks = blocks
        let fp = (block < docBlocks.count) ? bookmarkFingerprint(forBlock: docBlocks[block]) : ""
        let added = bookmarks.add(
            path: entry.path,
            title: bookmarkTitle(forBlockAt: block),
            blockIndex: block,
            fingerprint: fp
        )
        // The bookmark you just added is the one you're "on."
        if let id = added?.id {
            currentBookmarkID = id
            placeholderIsCurrent = false
        }
        if bookmarks.bookmarks.count == 1 {
            withAnimation(.easeOut(duration: 0.22)) {
                bookmarksExpandedRaw = true
                inspectorVisible = true
            }
        }
    }

    /// Jump to a bookmark's anchor. If the file is already loaded, just scroll.
    /// Otherwise reload the file and scroll once it lands.
    private func loadBookmark(_ bookmark: Bookmark) {
        if !bookmark.fileExists {
            bookmarks.refreshFileExistence()
            guard FileManager.default.fileExists(atPath: bookmark.path) else {
                NSSound.beep()
                return
            }
        }
        currentBookmarkID = bookmark.id
        placeholderIsCurrent = false
        bookmarkNavInProgress = true
        jumpTo(
            path: bookmark.path,
            blockIndex: bookmark.blockIndex,
            fingerprint: bookmark.blockFingerprint
        )
    }

    private func openBookmarkSlot(_ n: Int) {
        guard let bookmark = bookmarks.bookmark(forSlot: n) else {
            NSSound.beep()
            return
        }
        loadBookmark(bookmark)
    }

    /// Parse a dropped "mdv-bookmark:<id>" payload and reorder. `targetID == nil`
    /// means the drop landed on the tail spacer below the last row.
    private func handleBookmarkDrop(_ items: [String], targetID: Int64?) -> Bool {
        defer { dropTargetBookmarkID = nil }
        guard let str = items.first else { return false }
        let parts = str.components(separatedBy: ":")
        guard parts.count == 2, parts[0] == "mdv-bookmark", let id = Int64(parts[1]) else { return false }
        if let targetID = targetID,
           let dest = bookmarks.bookmarks.firstIndex(where: { $0.id == targetID }) {
            bookmarks.moveBookmark(id: id, toIndex: dest)
        } else {
            bookmarks.moveBookmarkToEnd(id: id)
        }
        return true
    }

    /// Common path for navigating to (path, anchor) — used by saved bookmarks
    /// and by the ⌘0 placeholder. If `path` matches the currently-loaded file
    /// we skip the reload and just scroll.
    private func jumpTo(path: String, blockIndex: Int, fingerprint: String) {
        let url = URL(fileURLWithPath: path)
        if selectedEntry?.path == path && !rawMarkdown.isEmpty {
            // Same file; resolve the anchor against the current document and scroll.
            let resolved = resolveBookmarkAnchor(
                blocks: blocks,
                storedIndex: blockIndex,
                fingerprint: fingerprint
            )
            pendingAnchorBlock = resolved
        } else {
            // Different file. Stash the anchor; loadFile will trigger a
            // rawMarkdown change, after which we resolve and scroll.
            pendingPostLoadAnchor = (blockIndex, fingerprint)
            loadFile(url)
        }
    }

    /// ⇧⌘0: capture current spot as the placeholder. Overwrites any prior value.
    private func setPlaceholder() {
        guard let entry = selectedEntry else { return }
        let block = hoveredBlock ?? topVisibleBlock
        let docBlocks = blocks
        let fp = (block < docBlocks.count) ? bookmarkFingerprint(forBlock: docBlocks[block]) : ""
        placeholder = PlaceholderAnchor(
            path: entry.path,
            title: bookmarkTitle(forBlockAt: block),
            blockIndex: block,
            blockFingerprint: fp
        )
        placeholderIsCurrent = true
        currentBookmarkID = nil
        // Make sure the user actually sees the row that just appeared.
        withAnimation(.easeOut(duration: 0.22)) {
            bookmarksExpandedRaw = true
            inspectorVisible = true
        }
    }

    /// ⌘0: jump to the placeholder if one is set; beep otherwise.
    private func jumpToPlaceholder() {
        guard let p = placeholder else {
            NSSound.beep()
            return
        }
        placeholderIsCurrent = true
        currentBookmarkID = nil
        bookmarkNavInProgress = true
        jumpTo(path: p.path, blockIndex: p.blockIndex, fingerprint: p.blockFingerprint)
    }

    private func loadCurrentEntry() {
        guard let entry = selectedEntry else {
            rawMarkdown = ""
            fileWatcher.cancel()
            return
        }
        let url = URL(fileURLWithPath: entry.path)
        // Mark the upcoming `rawMarkdown` change as a fresh load so the
        // rawMarkdown onChange handler will restore the saved scroll
        // anchor for this file (if any). FileWatcher takes a different
        // path that doesn't set this flag — its reloads should leave
        // the viewport where it is.
        pendingScrollRestore = true
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            rawMarkdown = content
        } else {
            rawMarkdown = ""
        }
        // Re-arm the watcher for the (possibly new) selected file so an
        // external editor saving the file pushes the changes back into
        // the viewer without the user having to reopen.
        let watchedPath = entry.path
        fileWatcher.watch(path: watchedPath) {
            // Still on the same entry? Re-read from disk.
            guard let current = self.selectedEntry, current.path == watchedPath else { return }
            let fresh = (try? String(contentsOfFile: watchedPath, encoding: .utf8)) ?? ""
            if fresh != self.rawMarkdown {
                self.rawMarkdown = fresh
            }
        }
    }

    /// Persist the current scroll anchor for `entry`. Reads `topVisibleBlock`
    /// directly (== `visibleBlocks.min()`) rather than the `currentTopBlock`
    /// mirror, because the back-stack handler on `body` resets
    /// `currentTopBlock = 0` in its defer block, and SwiftUI's invocation
    /// order across multiple onChange handlers for the same key isn't
    /// guaranteed — empirically that defer can fire before this save runs.
    /// `visibleBlocks` is safe to read here: it's only wiped by the
    /// `.onChange(of: rawMarkdown)` handler, which fires on the *next*
    /// runloop tick after `loadCurrentEntry` mutates `rawMarkdown`, well
    /// after we've already saved.
    ///
    /// Caller must invoke this BEFORE any code path that mutates `rawMarkdown`
    /// for a different file — otherwise `blocks` will already reflect the
    /// new file and the fingerprint will be wrong.
    private func persistScrollPosition(for entry: HistoryEntry) {
        let docBlocks = blocks
        let idx = topVisibleBlock
        let fp = (idx >= 0 && idx < docBlocks.count)
            ? bookmarkFingerprint(forBlock: docBlocks[idx])
            : ""
        // Stamp the file's current mtime alongside the anchor — on restore we
        // compare to the file's mtime at load time and invalidate the anchor
        // if the file has changed under us. The fingerprint already gives us
        // resilience to *small* edits, but a wholesale rewrite could leave the
        // user dropped into nonsense.
        let mtime = (try? FileManager.default.attributesOfItem(atPath: entry.path)[.modificationDate] as? Date)??.timeIntervalSince1970 ?? 0
        Database.shared.saveScrollPosition(
            path: entry.path,
            blockIndex: idx,
            fingerprint: fp,
            fileMtime: mtime
        )
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            guard ["md", "markdown", "txt", "mdown", "mkd"].contains(ext) else { return }
            DispatchQueue.main.async {
                loadFile(url)
            }
        }
        return true
    }
}

// MARK: - Find text field

struct FindField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    @Binding var requestFocus: Bool
    let onSubmit: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.stringValue = text
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onEscape = onEscape
        if requestFocus {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                requestFocus = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit, onEscape: onEscape)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        var onEscape: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void, onEscape: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
            self.onEscape = onEscape
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onEscape()
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Visual Effect (vibrancy)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Window accessor

/// Hands the host NSWindow back to a SwiftUI closure once it's attached,
/// and again on every `updateNSView`. Used to push theme-derived
/// background / appearance / titlebar settings down to the AppKit window
/// since SwiftUI's Scene-level styling can't reach those properties.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // .window is nil at make-time; defer to the next runloop tick so
        // SwiftUI has hooked the view into the window hierarchy.
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}

// MARK: - Notification handlers

/// Bundles every NotificationCenter publisher the main view subscribes to
/// into a single ViewModifier. Splitting these out of `body` keeps the
/// SwiftUI expression below the type-checker's complexity budget — the
/// modifier chain lives inside `body(content:)` instead of dangling off
/// the `HStack`.
private struct NotificationHandlers: ViewModifier {
    let openFile: () -> Void
    let openFileInNewWindow: () -> Void
    let openURLInWindow: (URL) -> Void
    let findInDocument: () -> Void
    let searchHistory: () -> Void
    let toggleBookmark: () -> Void
    let openBookmarkSlot: (Int) -> Void
    let setPlaceholder: () -> Void
    let jumpToPlaceholder: () -> Void
    let chooseExternalEditor: () -> Void
    let openInExternalEditor: () -> Void
    let forgetExternalEditor: () -> Void
    let navigateBack: () -> Void
    let navigateForward: () -> Void
    let toggleSidebar: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in toggleSidebar() }
            .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in openFile() }
            .onReceive(NotificationCenter.default.publisher(for: .openFileInNewWindow)) { _ in openFileInNewWindow() }
            .onReceive(NotificationCenter.default.publisher(for: .openURLInWindow)) { notif in
                if let url = notif.object as? URL { openURLInWindow(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .findInDocument)) { _ in findInDocument() }
            .onReceive(NotificationCenter.default.publisher(for: .searchHistory)) { _ in searchHistory() }
            .onReceive(NotificationCenter.default.publisher(for: .toggleBookmark)) { _ in toggleBookmark() }
            .onReceive(NotificationCenter.default.publisher(for: .openBookmarkSlot)) { notif in
                if let n = notif.object as? Int { openBookmarkSlot(n) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .setPlaceholder)) { _ in setPlaceholder() }
            .onReceive(NotificationCenter.default.publisher(for: .jumpToPlaceholder)) { _ in jumpToPlaceholder() }
            .onReceive(NotificationCenter.default.publisher(for: .chooseExternalEditor)) { _ in chooseExternalEditor() }
            .onReceive(NotificationCenter.default.publisher(for: .openInExternalEditor)) { _ in openInExternalEditor() }
            .onReceive(NotificationCenter.default.publisher(for: .forgetExternalEditor)) { _ in forgetExternalEditor() }
            .onReceive(NotificationCenter.default.publisher(for: .navigateBack)) { _ in navigateBack() }
            .onReceive(NotificationCenter.default.publisher(for: .navigateForward)) { _ in navigateForward() }
    }
}

// MARK: - File watcher

/// Watches a single file path on disk and runs a callback on the main
/// queue whenever it changes (write, atomic rename-replace, deletion,
/// attribute change). Built on FSEvents — a path-based API that watches
/// the parent directory and reports per-file events, so atomic-rename
/// saves (VSCode, BBEdit, Sublime, Vim with backup) are handled
/// naturally without re-opening file descriptors.
final class FileWatcher {
    private var stream: FSEventStreamRef?
    fileprivate var onChange: (() -> Void)?
    fileprivate var watchedPathResolved: String = ""

    deinit { cancel() }

    func watch(path: String, _ onChange: @escaping () -> Void) {
        cancel()
        // Resolve symlinks once up front so the FSEvents callback can
        // compare paths cheaply. macOS frequently rewrites `/tmp` →
        // `/private/tmp` and editors that save to a canonical path will
        // fire events with the rewritten form.
        let resolved = (path as NSString).resolvingSymlinksInPath
        self.watchedPathResolved = resolved
        self.onChange = onChange

        let dir = (resolved as NSString).deletingLastPathComponent
        guard !dir.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagUseCFTypes
        )
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
            let target = watcher.watchedPathResolved
            var matched = false
            for case let raw as String in array {
                if (raw as NSString).resolvingSymlinksInPath == target {
                    matched = true
                    break
                }
            }
            guard matched, let onChange = watcher.onChange else { return }
            DispatchQueue.main.async(execute: onChange)
        }

        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [dir] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,                // 50ms coalescing — fast enough to feel "immediate"
            flags
        ) else {
            return
        }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        self.stream = created
    }

    func cancel() {
        if let s = stream {
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            stream = nil
        }
        onChange = nil
        watchedPathResolved = ""
    }
}

// MARK: - Image provider

/// MarkdownUI image provider that loads local files and data: URIs from
/// disk, and falls back to MarkdownUI's network-backed default for
/// `http(s)` URLs. Relative paths in `![alt](path)` are resolved
/// against the markdown file's parent directory so adjacent images
/// "just work" the way they do on GitHub or any other viewer.
struct LocalImageProvider: ImageProvider {
    let baseURL: URL?
    /// Gate for `http(s)` images. When false, remote URLs render a clickable
    /// "Remote image blocked" placeholder instead of triggering a network
    /// fetch. Default off — viewers shouldn't reach out to arbitrary servers
    /// without the user opting in (privacy + tracking-pixel hygiene, mirrors
    /// Apple Mail's default behavior).
    let loadRemoteImages: Bool

    func makeImage(url: URL?) -> some View {
        Group {
            if let url = url {
                content(for: url)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func content(for url: URL) -> some View {
        let resolved = resolve(url)
        if resolved.scheme == "data" {
            dataURIImage(resolved)
        } else if resolved.isFileURL {
            localFileImage(resolved)
        } else if loadRemoteImages {
            // Use our own fetcher so we control the failure path. MarkdownUI's
            // `DefaultImageProvider` silently renders nothing on a 404 / DNS
            // failure / non-image response, which leaves the user staring at
            // an empty space wondering whether the toggle worked.
            RemoteImageView(url: resolved)
        } else {
            blockedRemoteImagePlaceholder(for: resolved)
        }
    }

    private func resolve(_ url: URL) -> URL {
        // Already absolute (file://, https://, data:, …)? Use as-is.
        if url.scheme != nil { return url }
        // Relative — resolve against the document's directory if we have one.
        if let base = baseURL {
            return URL(fileURLWithPath: url.path, relativeTo: base).standardizedFileURL
        }
        // No base — best effort: treat as file path relative to cwd.
        return URL(fileURLWithPath: url.path).standardizedFileURL
    }

    @ViewBuilder
    private func localFileImage(_ url: URL) -> some View {
        if let nsImage = NSImage(contentsOf: url) {
            // Cap at the image's intrinsic pixel size so we don't upscale
            // small assets; the column will naturally shrink it for narrow
            // windows because of `.aspectRatio(contentMode: .fit)`.
            let size = nsImage.size
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: size.width > 0 ? size.width : nil)
        } else {
            missingImagePlaceholder(for: url.lastPathComponent)
        }
    }

    @ViewBuilder
    private func dataURIImage(_ url: URL) -> some View {
        if let nsImage = decodeDataURIImage(url) {
            let size = nsImage.size
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: size.width > 0 ? size.width : nil)
        } else {
            missingImagePlaceholder(for: "inline data:")
        }
    }

    private func decodeDataURIImage(_ url: URL) -> NSImage? {
        // data:[<mime>][;base64],<payload>
        let raw = url.absoluteString
        guard raw.hasPrefix("data:"),
              let comma = raw.firstIndex(of: ",") else { return nil }
        let metaStart = raw.index(raw.startIndex, offsetBy: 5)
        let meta = String(raw[metaStart..<comma])
        let payload = String(raw[raw.index(after: comma)...])
        guard let data = decodeDataURIPayload(meta: meta, payload: payload) else { return nil }
        return NSImage(data: data)
    }

    private func decodeDataURIPayload(meta: String, payload: String) -> Data? {
        if meta.contains(";base64") {
            return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }

    private func missingImagePlaceholder(for name: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text("image not found: \(name)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.08))
        )
    }

    /// Inert stand-in for a remote image when remote fetching is off. Click
    /// pops the View menu open with "Load Remote Images" pre-highlighted at
    /// the cursor (`NSMenu.popUp(positioning:at:in:)`), which gives the user
    /// a one-click path from "I see a blocked image" to the persistent
    /// preference toggle.
    private func blockedRemoteImagePlaceholder(for url: URL) -> some View {
        Button(action: { Self.revealRemoteImagesMenuItem() }) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Remote image blocked")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(url.host ?? url.absoluteString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Text("Click to enable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 480, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            )
        }
        .buttonStyle(.plain)
        .help("Remote images are disabled. Click to open View → Load Remote Images.")
    }

    /// Pops the View menu open at the current mouse location, with the
    /// "Load Remote Images" item positioned (and pre-highlighted) under the
    /// cursor. Walks `NSApp.mainMenu` rather than holding a menu reference
    /// because the menu is constructed by SwiftUI's `CommandGroup` and we
    /// don't get a handle back from that API.
    static func revealRemoteImagesMenuItem() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        let target = viewMenu.items.first(where: {
            $0.title.localizedCaseInsensitiveContains("remote image")
        })
        let location = NSEvent.mouseLocation
        viewMenu.popUp(positioning: target, at: location, in: nil)
    }
}

/// Async fetcher for `http(s)` images, used when the user has opted in via
/// View → Load Remote Images. Replaces MarkdownUI's `DefaultImageProvider`
/// because the default silently renders nothing on a 404, DNS failure, or
/// non-image response — that's a confusing UX right after the user
/// explicitly enabled remote loading. Three states: loading (small
/// progress indicator on a placeholder), loaded (sized image), failed
/// (error placeholder showing host + reason).
///
/// In-process cache is a single static `NSCache<NSString, NSImage>` keyed
/// on the URL's absolute string. Cap is the `NSCache` default; macOS
/// will purge under memory pressure. No persistent disk cache —
/// URLSession's default cache layer covers HTTP-level reuse.
struct RemoteImageView: View {
    let url: URL

    @State private var image: NSImage?
    @State private var failure: String?

    static private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    var body: some View {
        Group {
            if let image {
                let size = image.size
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: size.width > 0 ? size.width : nil)
            } else if let failure {
                failurePlaceholder(reason: failure)
            } else {
                loadingPlaceholder
            }
        }
        .task(id: url.absoluteString) {
            await load()
        }
    }

    private func load() async {
        let key = url.absoluteString as NSString
        if let cached = Self.cache.object(forKey: key) {
            self.image = cached
            return
        }
        // Reset state when the URL changes mid-life (.task rerun).
        self.image = nil
        self.failure = nil
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                self.failure = "HTTP \(http.statusCode)"
                return
            }
            guard let img = NSImage(data: data), img.size.width > 0 else {
                self.failure = "not an image"
                return
            }
            Self.cache.setObject(img, forKey: key)
            self.image = img
        } catch is CancellationError {
            // .task cancelled (URL changed / view recycled). Don't surface
            // as a failure — caller will re-run with the new URL.
            return
        } catch {
            self.failure = (error as NSError).localizedDescription
        }
    }

    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(url.host ?? url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 480, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private func failurePlaceholder(reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't load remote image")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(url.host ?? url.absoluteString) — \(reason)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 480, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        )
    }
}

