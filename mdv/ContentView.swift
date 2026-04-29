import SwiftUI
import MarkdownUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var history: HistoryManager
    let initialURL: URL?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    @State private var selectedEntry: HistoryEntry?
    @State private var rawMarkdown: String = ""
    @State private var sidebarWidth: CGFloat = 240
    @State private var dragHandleHovered = false

    // TOC
    @State private var tocVisible: Bool = false
    @State private var tocSelectedBlock: Int? = nil
    @State private var tocScrollTrigger: Int? = nil
    @State private var hoveredHeading: Int? = nil
    private let tocWidth: CGFloat = 220

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

            if tocVisible {
                Divider()
                tocSidebar
                    .frame(width: tocWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.22), value: tocVisible)
        .navigationTitle(selectedEntry?.filename ?? "mdv")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: openFileDialog) {
                    Image(systemName: "plus")
                }
                .help("Open file (⌘O)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    tocVisible.toggle()
                } label: {
                    Image(systemName: tocVisible ? "sidebar.right" : "sidebar.right")
                        .foregroundStyle(tocVisible ? Color.accentColor : Color.primary)
                }
                .help("Toggle Outline (⌥⌘0)")
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(tocHeadings.isEmpty)
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
        .onOpenURL { url in
            loadFile(url)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onChange(of: selectedEntry) { _ in
            loadCurrentEntry()
        }
        .onChange(of: rawMarkdown) { _ in
            if isSearching { recomputeMatches() }
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
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
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
                                    .markdownTheme(.gitHub)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(highlightColor(forBlock: idx))
                                            .animation(.easeOut(duration: 0.18), value: currentMatchIndex)
                                            .animation(.easeOut(duration: 0.18), value: matches)
                                            .animation(.easeOut(duration: 0.18), value: isSearching)
                                    )
                                    .id("block-\(idx)")
                            }
                        }
                        .textSelection(.enabled)
                        .padding(.horizontal, 34)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
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

    private var tocSidebar: some View {
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
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
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
