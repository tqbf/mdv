import AppKit
import SwiftUI

/// One TextKit document, so a selection can cross every Markdown block.
/// AppKit owns mouse/keyboard selection, autoscroll, accessibility and copying.
struct SelectableDocumentView: NSViewRepresentable {
    let blocks: [String]
    let smartTypography: Bool
    let identity: String
    let theme: MDVTheme
    let scale: CGFloat
    let baseURL: URL?
    let loadRemoteImages: Bool
    let query: String
    let isSearching: Bool
    let matchBlock: Int?
    let matchOccurrence: Int
    @Binding var scrollTarget: Int?
    @Binding var visibleBlocks: Set<Int>
    @Binding var hoveredBlock: Int?
    let openLink: OpenURLAction

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let text = DocumentTextView(frame: scroll.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.importsGraphics = false
        text.allowsUndo = false
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = false
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.lineFragmentPadding = 0
        text.delegate = context.coordinator
        text.diagramStyleChanged = { [weak coordinator = context.coordinator] in coordinator?.scheduleUpdate() }
        text.setAccessibilityLabel("Document")
        scroll.documentView = text
        context.coordinator.text = text
        text.hoverChanged = { [weak coordinator = context.coordinator] block in
            DispatchQueue.main.async {
                guard let coordinator, coordinator.isActive, coordinator.parent.hoveredBlock != block else { return }
                coordinator.parent.hoveredBlock = block
            }
        }
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak coordinator = context.coordinator] _ in coordinator?.reportViewport() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let text = coordinator.text else { return }
        text.articlePadding = theme.articleHorizontalPadding
        text.articleWidth = theme.articleMaxWidth
        text.backgroundColor = NSColor(theme.background)
        scroll.backgroundColor = NSColor(theme.background)
        text.linkTextAttributes = [.foregroundColor: NSColor(theme.link), .cursor: NSCursor.pointingHand]
        text.resizeArticle()
        // The HTML importer can service the main run loop. Never invoke it in
        // a SwiftUI layout transaction; coalesce updates on the next turn.
        coordinator.scheduleUpdate()
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.isActive = false
        coordinator.work?.cancel()
        coordinator.imageTasks.forEach { $0.cancel() }
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableDocumentView
        var isActive = true
        weak var text: DocumentTextView?
        var observer: NSObjectProtocol?
        var work: DispatchWorkItem?
        var imageTasks: [Task<Void, Never>] = []
        var renderedKey: RenderKey?
        var lastMatch: Int?
        var lastOccurrence = -1
        var activeMatchRange: NSRange?
        private var isUpdating = false
        private var updateRequested = false
        var lastQuery = ""
        var wasSearching = false
        var generation = 0

        struct RenderKey: Equatable {
            let blocks: [String]
            let smartTypography: Bool
            let identity: String
            let theme: MDVTheme
            let scale: CGFloat
            let remote: Bool
            let diagramStyle: String
        }

        init(_ parent: SelectableDocumentView) { self.parent = parent }

        func scheduleUpdate() {
            guard isActive else { return }
            work?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.update() }
            self.work = work
            DispatchQueue.main.async(execute: work)
        }

        func update() {
            guard isActive else { return }
            guard !isUpdating else { updateRequested = true; return }
            isUpdating = true
            defer {
                isUpdating = false
                if updateRequested { updateRequested = false; scheduleUpdate() }
            }
            guard let text, let storage = text.textStorage else { return }
            let key = RenderKey(blocks: parent.blocks, smartTypography: parent.smartTypography, identity: parent.identity,
                                theme: parent.theme, scale: parent.scale, remote: parent.loadRemoteImages,
                                diagramStyle: UserDefaults.standard.string(forKey: "mdv.mermaid.style") ?? "document")
            if renderedKey != key {
                let sameDocument = renderedKey?.identity == key.identity
                let selection = text.selectedRanges
                let origin = text.enclosingScrollView?.contentView.bounds.origin ?? .zero
                renderedKey = key
                generation += 1
                imageTasks.forEach { $0.cancel() }
                imageTasks.removeAll()
                let rendered = NativeMarkdownDocument.render(blocks: parent.blocks.map { parent.smartTypography ? smartenMarkdown($0) : $0 }, theme: parent.theme, scale: parent.scale)
                guard isActive else { return }
                storage.setAttributedString(rendered.text)
                text.resizeArticle()
                if sameDocument {
                    let validSelection = selection.filter { NSMaxRange($0.rangeValue) <= storage.length }
                    text.selectedRanges = validSelection.isEmpty ? [NSValue(range: NSRange(location: 0, length: 0))] : validSelection
                    text.enclosingScrollView?.contentView.scroll(to: origin)
                } else {
                    text.setSelectedRange(NSRange(location: 0, length: 0))
                    text.scrollToBeginningOfDocument(nil)
                    text.window?.makeFirstResponder(text)
                }
                loadImages(rendered.images)
                lastQuery = ""
                lastMatch = nil
            }
            highlightMatches()
            if let target = parent.scrollTarget {
                scroll(to: target)
                parent.scrollTarget = nil
            } else if lastMatch != parent.matchBlock || lastOccurrence != parent.matchOccurrence || lastQuery != parent.query {
                if let range = activeMatchRange { text.scrollRangeToVisible(range) }
                else if let target = parent.matchBlock { scroll(to: target) }
            }
            lastMatch = parent.matchBlock
            lastOccurrence = parent.matchOccurrence
            lastQuery = parent.query
            if wasSearching && !parent.isSearching { text.window?.makeFirstResponder(text) }
            wasSearching = parent.isSearching
            reportViewport()
        }

        func highlightMatches() {
            guard let text, let storage = text.textStorage, let layout = text.layoutManager else { return }
            let full = NSRange(location: 0, length: storage.length)
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
            activeMatchRange = nil
            guard !parent.query.isEmpty else { return }
            var blockOccurrence = 0
            let string = storage.string as NSString
            var remaining = full
            while remaining.length > 0 {
                let range = string.range(of: parent.query, options: [.caseInsensitive, .diacriticInsensitive], range: remaining)
                guard range.location != NSNotFound else { break }
                let inCurrentBlock = storage.attribute(.documentBlock, at: range.location, effectiveRange: nil) as? Int == parent.matchBlock
                let current = inCurrentBlock && blockOccurrence == parent.matchOccurrence
                if inCurrentBlock { blockOccurrence += 1 }
                if current { activeMatchRange = range }
                layout.addTemporaryAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(current ? 0.65 : 0.3), forCharacterRange: range)
                remaining = NSRange(location: NSMaxRange(range), length: storage.length - NSMaxRange(range))
            }
        }

        func scroll(to block: Int) {
            guard let text, let storage = text.textStorage else { return }
            var target: NSRange?
            storage.enumerateAttribute(.documentBlock, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                if value as? Int == block { target = range; stop.pointee = true }
            }
            if let target {
                text.scrollRangeToVisible(NSRange(location: target.location, length: min(target.length, 1)))
            }
        }

        func reportViewport() {
            guard let text, let layout = text.layoutManager, let container = text.textContainer,
                  let storage = text.textStorage else { return }
            var rect = text.visibleRect
            rect.origin.x -= text.textContainerOrigin.x
            rect.origin.y -= text.textContainerOrigin.y
            let glyphs = layout.glyphRange(forBoundingRect: rect, in: container)
            let range = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard NSMaxRange(range) <= storage.length else { return }
            var visible = Set<Int>()
            storage.enumerateAttribute(.documentBlock, in: range) { value, _, _ in
                if let block = value as? Int { visible.insert(block) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive, self.parent.visibleBlocks != visible else { return }
                self.parent.visibleBlocks = visible
            }
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            if let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) { parent.openLink(url) }
            return true
        }

        func loadImages(_ images: [NativeMarkdownDocument.ImageReference]) {
            let generation = self.generation
            let base = parent.baseURL
            let remote = parent.loadRemoteImages
            let theme = parent.theme
            for reference in images {
                imageTasks.append(Task { @MainActor [weak self] in
                    let image: NSImage?
                    if let source = reference.mermaid {
                        let style = MermaidRenderStyle(rawValue: UserDefaults.standard.string(forKey: "mdv.mermaid.style") ?? "") ?? .document
                        image = await MDVMermaidImageCache.shared.image(source: source, theme: theme, style: style,
                            key: MDVMermaidRenderKey(source: source, theme: theme, style: style))
                    } else if let raw = reference.url, let url = URL(string: raw, relativeTo: base)?.absoluteURL {
                        if url.isFileURL {
                            image = NSImage(contentsOf: url)
                        } else if url.scheme == "data", let comma = raw.firstIndex(of: ",") {
                            let metadata = raw[..<comma]
                            let payload = String(raw[raw.index(after: comma)...])
                            let data = metadata.contains(";base64") ? Data(base64Encoded: payload) : payload.removingPercentEncoding?.data(using: .utf8)
                            image = data.flatMap(NSImage.init(data:))
                        } else if remote && ["http", "https"].contains(url.scheme ?? ""),
                                  let (data, _) = try? await URLSession.shared.data(from: url) {
                            image = NSImage(data: data)
                        } else { image = nil }
                    } else { image = nil }
                    guard !Task.isCancelled, let self, self.generation == generation,
                          let text = self.text, let storage = text.textStorage else { return }
                    var found: NSRange?
                    storage.enumerateAttribute(.documentImage, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
                        if value as? String == reference.marker { found = range; stop.pointee = true }
                    }
                    guard let range = found else { return }
                    let attributes = storage.attributes(at: range.location, effectiveRange: nil)
                    let value: NSMutableAttributedString
                    if let image {
                        let attachment = NSTextAttachment()
                        attachment.image = image
                        value = NSMutableAttributedString(attachment: attachment)
                        if reference.mermaid != nil {
                            value.addAttribute(.documentDiagramAttachment, value: attachment, range: NSRange(location: 0, length: 1))
                        }
                    } else {
                        let blocked = !remote && reference.url.map { $0.hasPrefix("http:") || $0.hasPrefix("https:") } == true
                        let fallback = reference.mermaid ?? "[\(blocked ? "Remote image blocked" : "Image unavailable"): \(reference.label)]"
                        value = NSMutableAttributedString(string: fallback)
                    }
                    value.addAttributes(attributes, range: NSRange(location: 0, length: value.length))
                    let selected = text.selectedRange()
                    storage.replaceCharacters(in: range, with: value)
                    // Preserve selection endpoints when an image finishes loading.
                    func remap(_ offset: Int) -> Int {
                        if offset <= range.location { return offset }
                        if offset >= NSMaxRange(range) { return offset + value.length - range.length }
                        return range.location + value.length
                    }
                    let start = remap(selected.location), end = remap(NSMaxRange(selected))
                    text.setSelectedRange(NSRange(location: start, length: end - start))
                    text.resizeArticle()
                    self.highlightMatches()
                    self.reportViewport()
                })
            }
        }
    }
}

extension NSAttributedString.Key {
    static let documentBlock = NSAttributedString.Key("mdv.documentBlock")
    static let documentCode = NSAttributedString.Key("mdv.documentCode")
    static let documentImage = NSAttributedString.Key("mdv.documentImage")
    static let documentDiagramAttachment = NSAttributedString.Key("mdv.documentDiagramAttachment")
}

final class DocumentTextView: NSTextView {
    var articleWidth: CGFloat?
    var articlePadding: CGFloat = 40
    var hoverChanged: ((Int?) -> Void)?
    var diagramStyleChanged: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var resizingArticle = false

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = frame.width != newSize.width
        super.setFrameSize(newSize)
        if widthChanged { resizeArticle() }
    }

    func resizeArticle() {
        guard !resizingArticle else { return }
        resizingArticle = true
        defer { resizingArticle = false }
        let available = enclosingScrollView?.contentSize.width ?? bounds.width
        let width = max(1, min(available, articleWidth ?? available) - articlePadding * 2)
        let inset = NSSize(width: max(articlePadding, (available - width) / 2), height: 28)
        if textContainerInset != inset { textContainerInset = inset }
        let size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        if textContainer?.containerSize != size { textContainer?.containerSize = size }
        if let storage = textStorage {
            storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
                guard let attachment = value as? NSTextAttachment, let image = attachment.image else { return }
                let ratio = min(1, width / max(1, image.size.width))
                let bounds = NSRect(x: 0, y: 0, width: image.size.width * ratio, height: image.size.height * ratio)
                if attachment.bounds != bounds { attachment.bounds = bounds }
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if let storage = textStorage, index < storage.length,
           let code = storage.attribute(.documentCode, at: index, effectiveRange: nil) as? String {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Copy Code", action: #selector(copyCode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            menu.addItem(item)
        }
        if let storage = textStorage, index < storage.length,
           let attachment = storage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
           let image = attachment.image {
            let item = NSMenuItem(title: "Export Image as PNG…", action: #selector(exportImage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = image
            menu.addItem(item)
        }
        if let storage = textStorage, index < storage.length,
           storage.attribute(.documentDiagramAttachment, at: index, effectiveRange: nil) != nil,
           let id = storage.attribute(.documentImage, at: index, effectiveRange: nil) as? String {
            let showingImage = storage.attribute(.attachment, at: index, effectiveRange: nil) != nil
            let toggle = NSMenuItem(title: showingImage ? "Show Diagram Source" : "Show Diagram", action: #selector(toggleDiagram(_:)), keyEquivalent: "")
            toggle.target = self
            toggle.representedObject = id
            menu.addItem(toggle)
            let styles = NSMenuItem(title: "Diagram Style", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for style in MermaidRenderStyle.allCases {
                let item = NSMenuItem(title: style.displayName, action: #selector(changeDiagramStyle(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = style.rawValue
                item.state = (UserDefaults.standard.string(forKey: "mdv.mermaid.style") ?? "document") == style.rawValue ? .on : .off
                submenu.addItem(item)
            }
            styles.submenu = submenu
            menu.addItem(styles)
        }
        return menu
    }

    @objc private func copyCode(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    @objc private func exportImage(_ sender: NSMenuItem) {
        guard let image = sender.representedObject as? NSImage,
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "image.png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url) } catch { NSApp.presentError(error) }
    }

    @objc private func changeDiagramStyle(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? String else { return }
        UserDefaults.standard.set(style, forKey: "mdv.mermaid.style")
        diagramStyleChanged?()
    }

    @objc private func toggleDiagram(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let storage = textStorage else { return }
        var found: NSRange?
        storage.enumerateAttribute(.documentImage, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            if value as? String == id { found = range; stop.pointee = true }
        }
        guard let range = found,
              let attachment = storage.attribute(.documentDiagramAttachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
              let code = storage.attribute(.documentCode, at: range.location, effectiveRange: nil) as? String else { return }
        var attributes = storage.attributes(at: range.location, effectiveRange: nil)
        let showingImage = attributes.removeValue(forKey: .attachment) != nil
        let value = showingImage ? NSMutableAttributedString(string: code) : NSMutableAttributedString(attachment: attachment)
        if showingImage { attributes[.font] = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) }
        value.addAttributes(attributes, range: NSRange(location: 0, length: value.length))
        storage.replaceCharacters(in: range, with: value)
        setSelectedRange(NSRange(location: range.location, length: 0))
        resizeArticle()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let block = index < (textStorage?.length ?? 0) ? textStorage?.attribute(.documentBlock, at: index, effectiveRange: nil) as? Int : nil
        hoverChanged?(block)
    }

    override func mouseExited(with event: NSEvent) { hoverChanged?(nil) }
}
