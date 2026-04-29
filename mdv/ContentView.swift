import SwiftUI
import MarkdownUI
import AppKit

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

    // TOC + Bookmarks (right inspector)
    @State private var inspectorVisible: Bool = false
    @State private var tocSelectedBlock: Int? = nil
    @State private var tocScrollTrigger: Int? = nil
    @State private var hoveredHeading: Int? = nil
    private let inspectorWidth: CGFloat = 240

    // Bookmarks pane (lives below TOC inside the inspector)
    @AppStorage("mdv_bookmarks_height") private var bookmarksHeight: Double = 240
    @AppStorage("mdv_bookmarks_expanded") private var bookmarksExpandedRaw: Bool = false
    @State private var bookmarksDividerHovered = false
    @State private var hoveredBookmark: Int64? = nil
    @State private var draggingBookmarkID: Int64? = nil
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
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)

            dragHandle

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
        .navigationTitle(selectedEntry?.filename ?? "mdv")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openFileDialog) {
                    Image(systemName: "plus")
                }
                .help("Open file (⌘O)")
            }
            ToolbarItem(placement: .primaryAction) {
                themeMenu
            }
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
        .onReceive(NotificationCenter.default.publisher(for: .openFile)) { _ in
            openFileDialog()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileInNewWindow)) { _ in
            openFileDialogInNewWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openURLInWindow)) { notif in
            if let url = notif.object as? URL {
                loadFile(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .findInDocument)) { _ in
            if shouldRouteToGlobalSearch() {
                focusGlobalSearch()
            } else {
                openFind()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchHistory)) { _ in
            focusGlobalSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleBookmark)) { _ in
            addBookmarkAtCurrentSpot()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBookmarkSlot)) { notif in
            if let n = notif.object as? Int { openBookmarkSlot(n) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .setPlaceholder)) { _ in
            setPlaceholder()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jumpToPlaceholder)) { _ in
            jumpToPlaceholder()
        }
        .onOpenURL { url in
            loadFile(url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onChange(of: selectedEntry) { _ in
            // Selection changed by something other than a bookmark/placeholder
            // jump? Then drop the "active bookmark" highlight.
            if !bookmarkNavInProgress {
                currentBookmarkID = nil
                placeholderIsCurrent = false
            }
            bookmarkNavInProgress = false
            loadCurrentEntry()
        }
        .onChange(of: rawMarkdown) { _ in
            if isSearching { recomputeMatches() }
            // Visible-block tracking is per-document; reset so the topmost-visible
            // calculation doesn't use indices from the previous file before its
            // blocks finish disappearing.
            visibleBlocks.removeAll()
            // If we got here via jumpTo() with a pending anchor, resolve it now
            // that the new document's blocks exist.
            if let anchor = pendingPostLoadAnchor {
                let resolved = resolveBookmarkAnchor(
                    blocks: blocks,
                    storedIndex: anchor.blockIndex,
                    fingerprint: anchor.fingerprint
                )
                pendingPostLoadAnchor = nil
                pendingAnchorBlock = resolved
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
            paneTracker.sidebarRightEdge = sidebarWidth + 8 // include drag handle width
            paneTracker.install()
            if let url = initialURL {
                loadFile(url)
            } else if let last = history.entries.first {
                selectedEntry = last
                loadCurrentEntry()
            }
        }
        .onDisappear {
            paneTracker.uninstall()
        }
        .onChange(of: sidebarWidth) { newValue in
            paneTracker.sidebarRightEdge = newValue + 8
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarSearchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if !globalQuery.isEmpty {
                globalSearchResults
            } else if history.entries.isEmpty {
                emptyHistory
            } else {
                historyList
            }
        }
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .overlay(themes.current.sidebarTint.opacity(themes.current.sidebarTintOpacity))
        )
    }

    private var historyList: some View {
        List(selection: $selectedEntry) {
            Section("History") {
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
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Sidebar search field

    private var sidebarSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("Search history", text: $globalQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($globalSearchFocused)
                .onSubmit {
                    if let first = globalHits.first { openHit(first) }
                }
                .onExitCommand {
                    clearGlobalSearch()
                }
            if !globalQuery.isEmpty {
                Button {
                    clearGlobalSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear (esc)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(globalSearchFocused ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(globalSearchFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
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
        globalSearchFocused = true
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
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.filename)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(prettyPath(entry.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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

    /// Toolbar pop-up menu for switching the document theme. Shows a paintpalette
    /// icon (no label) so it stays visually unobtrusive next to the other toolbar
    /// glyphs; the popup itself shows full theme names with a checkmark on the
    /// active one. Selection persists via ThemeManager (@AppStorage).
    private var themeMenu: some View {
        Menu {
            ForEach(MDVTheme.all) { theme in
                Button {
                    themes.set(theme)
                } label: {
                    if themes.current.id == theme.id {
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
        .help("Theme: \(themes.current.name)")
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        ZStack {
            Color.clear
                .frame(width: 8)
                .contentShape(Rectangle())
            Rectangle()
                .fill(dragHandleHovered ? Color.accentColor.opacity(0.5) : Color.black.opacity(0.08))
                .frame(width: dragHandleHovered ? 2 : 1)
                .animation(.easeInOut(duration: 0.15), value: dragHandleHovered)
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
                                Markdown(block)
                                    .markdownTheme(themes.current.markdownTheme)
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
        .overlay(alignment: .top) {
            if isSearching {
                findBar
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var blocks: [String] {
        let parts = rawMarkdown.components(separatedBy: "\n\n")
        return parts
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
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
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .overlay(themes.current.sidebarTint.opacity(themes.current.sidebarTintOpacity))
        )
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
                .fill(bookmarksDividerHovered ? Color.accentColor.opacity(0.5) : Color.black.opacity(0.08))
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
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 6)

            if tocHeadings.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No headings")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(tocHeadings) { heading in
                            tocRow(heading)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Bookmarks pane

    private var bookmarksHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: bookmarksExpandedRaw ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
            Text("Bookmarks")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Spacer()
            if !bookmarks.bookmarks.isEmpty {
                Text("\(bookmarks.bookmarks.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
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
        // handle in the row. Hand-rolled .onDrag/.onDrop gives us mouse-drag
        // reordering with a row-shaped drag preview, which is what the user
        // expects when they grab a bookmark to push it into a hotkey slot.
        ScrollView {
            LazyVStack(spacing: 1) {
                if let p = placeholder {
                    placeholderRow(p)
                        .padding(.bottom, 2)
                    Divider()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }

                ForEach(bookmarks.bookmarks) { bookmark in
                    bookmarkRow(bookmark)
                        .contextMenu {
                            Button("Go to Bookmark") { loadBookmark(bookmark) }
                                .disabled(!bookmark.fileExists)
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bookmark.path)])
                            }
                            .disabled(!bookmark.fileExists)
                            Divider()
                            Button(role: .destructive) {
                                bookmarks.remove(id: bookmark.id)
                            } label: {
                                Text("Remove Bookmark")
                            }
                        }
                        .onDrag {
                            draggingBookmarkID = bookmark.id
                            return NSItemProvider(object: "mdv-bookmark:\(bookmark.id)" as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: BookmarkDropDelegate(
                                target: bookmark,
                                manager: bookmarks,
                                hovered: $dropTargetBookmarkID,
                                dragging: $draggingBookmarkID
                            )
                        )
                }
                Color.clear
                    .frame(height: 24)
                    .onDrop(
                        of: [.text],
                        delegate: BookmarkDropTailDelegate(
                            manager: bookmarks,
                            dragging: $draggingBookmarkID
                        )
                    )
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
        let dragging = draggingBookmarkID == bookmark.id
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
            .opacity(missing && !isCurrent ? 0.6 : (dragging ? 0.4 : 1.0))
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

        return Button {
            tocSelectedBlock = heading.blockIndex
            tocScrollTrigger = heading.blockIndex
        } label: {
            HStack(spacing: 0) {
                Spacer().frame(width: leadingIndent)
                Text(heading.text)
                    .font(.system(size: 12, weight: heading.level == 1 ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? Color.white : (heading.level == 1 ? Color.primary : Color.secondary))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCurrent ? Color.accentColor : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
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
        guard FileManager.default.isReadableFile(atPath: url.path) else { return }
        let entry = history.add(path: url.path)
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
            return
        }
        let url = URL(fileURLWithPath: entry.path)
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            rawMarkdown = content
        } else {
            rawMarkdown = ""
        }
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

// MARK: - Bookmark drag-drop

/// Handles drops onto a specific bookmark row — the dragged bookmark is moved
/// to that target row's index. Tail drops (past the last row) are handled by
/// `BookmarkDropTailDelegate` because a row delegate can't see "below the list."
private struct BookmarkDropDelegate: DropDelegate {
    let target: Bookmark
    let manager: BookmarksManager
    @Binding var hovered: Int64?
    @Binding var dragging: Int64?

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        // Don't show a drop indicator on the row being dragged (no-op move).
        if let dragging, dragging == target.id {
            hovered = nil
        } else {
            hovered = target.id
        }
    }

    func dropExited(info: DropInfo) {
        if hovered == target.id { hovered = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            hovered = nil
            dragging = nil
        }
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let mgr = manager
        let targetID = target.id
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let str = item as? String else { return }
            // Payload format: "mdv-bookmark:<id>"
            let parts = str.components(separatedBy: ":")
            guard parts.count == 2, parts[0] == "mdv-bookmark", let id = Int64(parts[1]) else { return }
            DispatchQueue.main.async {
                guard let dest = mgr.bookmarks.firstIndex(where: { $0.id == targetID }) else { return }
                mgr.moveBookmark(id: id, toIndex: dest)
            }
        }
        return true
    }
}

/// Drop target for the spacer below the last bookmark — sends the dragged item
/// to the very end of the list.
private struct BookmarkDropTailDelegate: DropDelegate {
    let manager: BookmarksManager
    @Binding var dragging: Int64?

    func validateDrop(info: DropInfo) -> Bool { true }

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        let mgr = manager
        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let str = item as? String else { return }
            let parts = str.components(separatedBy: ":")
            guard parts.count == 2, parts[0] == "mdv-bookmark", let id = Int64(parts[1]) else { return }
            DispatchQueue.main.async {
                mgr.moveBookmarkToEnd(id: id)
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
