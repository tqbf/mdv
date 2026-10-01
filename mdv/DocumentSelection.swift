import AppKit
import MarkdownUI
import SwiftUI

/// Selection coordinates are local to a Markdown block, so mounting an earlier
/// lazy row cannot shift either endpoint. Text comes from the actual rendered
/// fields where available; unmounted rows use MarkdownUI's plain-text export.
struct DocumentTextSelection {
    struct Position: Equatable, Comparable {
        var block: Int
        var offset: Int
        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.block == rhs.block ? lhs.offset < rhs.offset : lhs.block < rhs.block
        }
    }

    var text: [String] = []
    var anchor: Position?
    var extent: Position?
    var selectsAll = false

    var hasSelection: Bool { selectsAll || (anchor != nil && extent != nil && anchor != extent) }

    mutating func clear() { anchor = nil; extent = nil; selectsAll = false }

    func range(in block: Int) -> NSRange? {
        guard text.indices.contains(block) else { return nil }
        let length = (text[block] as NSString).length
        if selectsAll { return NSRange(location: 0, length: length) }
        guard let anchor, let extent else { return nil }
        let start = min(anchor, extent), end = max(anchor, extent)
        guard block >= start.block && block <= end.block else { return nil }
        let lo = block == start.block ? min(start.offset, length) : 0
        let hi = block == end.block ? min(end.offset, length) : length
        return NSRange(location: lo, length: max(0, hi - lo))
    }

    var copiedText: String {
        text.indices.compactMap { block in
            guard let range = range(in: block) else { return nil }
            return (text[block] as NSString).substring(with: range)
        }.joined(separator: "\n\n")
    }
}

/// A geometry marker only. It neither renders text nor changes block layout.
struct DocumentSelectionBlock: NSViewRepresentable {
    let index: Int
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.index = index }
    final class Marker: NSView {
        var index = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Coordinates SwiftUI's existing selectable NSTextFields, using their public
/// accessibility geometry for hit testing and highlight rectangles. The original
/// MarkdownUI/SwiftUI renderer still owns every glyph, image and control.
struct DocumentSelection: NSViewRepresentable {
    let blocks: [String]
    let identity: String
    let smartTypography: Bool
    let openURL: OpenURLAction
    let scrollToBlock: (Int) -> Void

    func makeNSView(context: Context) -> SelectionView { SelectionView() }
    func updateNSView(_ view: SelectionView, context: Context) {
        view.openURL = openURL
        view.scrollToBlock = scrollToBlock
        view.updateDocument(blocks: blocks, identity: identity, smartTypography: smartTypography)
        view.scheduleRefresh()
    }
    static func dismantleNSView(_ view: SelectionView, coordinator: ()) { view.stop() }

    final class SelectionView: NSView, NSUserInterfaceValidations {
        struct Run {
            let field: NSTextField
            let block: Int
            let offset: Int
            let string: String
            let rect: NSRect
            var length: Int { (string as NSString).length }
        }
        var selection = DocumentTextSelection()
        var openURL = OpenURLAction { _ in .systemAction }
        var scrollToBlock: (Int) -> Void = { _ in }
        private var revealAfterLayout = false
        private var source: [String] = []
        private var documentID = ""
        private var smart = false
        private var runs: [Run] = []
        private var monitor: Any?
        private var scrollObserver: NSObjectProtocol?
        private var refreshWork: DispatchWorkItem?
        private var dragTimer: Timer?
        private var mouseDownPoint: NSPoint?
        private var dragPoint: NSPoint?
        private var dragged = false
        private var clickedLink: URL?
        private var wordAnchor: (DocumentTextSelection.Position, DocumentTextSelection.Position)?
        private var active = true
        private var isReading = true

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        var hasSelection: Bool { selection.hasSelection }

        func updateDocument(blocks: [String], identity: String, smartTypography: Bool) {
            guard blocks != source || identity != documentID || smartTypography != smart else { return }
            source = blocks; documentID = identity; smart = smartTypography
            selection.clear()
            isReading = true
            revealAfterLayout = false
            selection.text = blocks.map {
                // A diagram has no selectable source until its Source control is used.
                let visibleSource = $0.replacingOccurrences(
                    of: #"(?ims)^ {0,3}(`{3,}|~{3,})mermaid[^\n]*\n.*?^ {0,3}\1[ \t]*(?:\n|$)"#,
                    with: "", options: .regularExpression)
                return MarkdownContent(smartTypography ? smartenMarkdown(visibleSource) : visibleSource).renderPlainText()
            }
            runs = []
            needsDisplay = true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            active = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, let clip = notification.object as? NSClipView,
                      let scroll = self.enclosingScrollView, clip.isDescendant(of: scroll) else { return }
                self.scheduleRefresh()
            }
            scheduleRefresh()
        }

        func stop() {
            active = false
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollObserver = nil
            refreshWork?.cancel()
            dragTimer?.invalidate(); dragTimer = nil
        }
        deinit { stop() }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            scheduleRefresh()
        }

        func scheduleRefresh() {
            guard active else { return }
            refreshWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.active else { return }
                self.refreshRuns()
                if self.revealAfterLayout { self.revealExtent() }
                self.needsDisplay = true
            }
            refreshWork = work
            DispatchQueue.main.async(execute: work)
        }

        private func refreshRuns() {
            guard let root = enclosingScrollView?.documentView else { return }
            var markers: [(Int, NSRect)] = []
            var fields: [NSTextField] = []
            func visit(_ view: NSView) {
                if let marker = view as? DocumentSelectionBlock.Marker {
                    markers.append((marker.index, convert(marker.bounds, from: marker)))
                } else if let field = view as? NSTextField, field.isSelectable, !field.isEditable, !field.isHidden {
                    fields.append(field)
                }
                for child in view.subviews { visit(child) }
            }
            visit(root)
            markers.sort { $0.0 < $1.0 }
            var grouped: [Int: [(NSTextField, NSRect)]] = [:]
            for field in fields where !field.stringValue.isEmpty {
                let rect = convert(field.bounds, from: field)
                guard let marker = markers.first(where: { rect.midY >= $0.1.minY - 1 && rect.midY <= $0.1.maxY + 1 }) else { continue }
                grouped[marker.0, default: []].append((field, rect))
            }
            runs = []
            for (index, _) in markers where selection.text.indices.contains(index) {
                guard let fields = grouped[index], !fields.isEmpty else { continue }
                let sorted = fields.sorted {
                    abs($0.1.minY - $1.1.minY) < 3 ? $0.1.minX < $1.1.minX : $0.1.minY < $1.1.minY
                }
                var text = ""
                var previous: NSRect?
                for (field, rect) in sorted {
                    if let previous { text += abs(previous.minY - rect.minY) < 3 ? "\t" : "\n" }
                    runs.append(Run(field: field, block: index, offset: (text as NSString).length, string: field.stringValue, rect: rect))
                    text += field.stringValue
                    previous = rect
                }
                selection.text[index] = text
                let length = (text as NSString).length
                if var anchor = selection.anchor, anchor.block == index {
                    anchor.offset = min(anchor.offset, length)
                    selection.anchor = anchor
                }
                if var extent = selection.extent, extent.block == index {
                    extent.offset = min(extent.offset, length)
                    selection.extent = extent
                }
            }
        }

        private func frame(_ range: NSRange, in run: Run) -> NSRect {
            guard let cell = run.field.cell, let window else { return .zero }
            return convert(window.convertFromScreen(cell.accessibilityFrame(for: range)), from: nil)
        }

        private func lines(in run: Run) -> [NSRange] {
            guard run.length > 0, let cell = run.field.cell else { return [] }
            let last = cell.accessibilityLine(for: run.length - 1)
            guard last >= 0, last < run.length else { return [NSRange(location: 0, length: run.length)] }
            return (0...last).compactMap { line in
                let range = cell.accessibilityRange(forLine: line)
                return range.location != NSNotFound && range.length > 0 && NSMaxRange(range) <= run.length ? range : nil
            }
        }

        private func position(at point: NSPoint, includingOffscreen: Bool = false) -> (DocumentTextSelection.Position, Run)? {
            let candidates = includingOffscreen ? runs : runs.filter { !convert($0.field.visibleRect, from: $0.field).isEmpty }
            func distance(_ rect: NSRect) -> CGFloat {
                let dy = max(rect.minY - point.y, point.y - rect.maxY, 0)
                let dx = max(rect.minX - point.x, point.x - rect.maxX, 0)
                return dy * 10000 + dx
            }
            guard let run = candidates.min(by: { distance($0.rect) < distance($1.rect) }) else { return nil }
            let lineRanges = lines(in: run)
            guard let line = lineRanges.min(by: { distance(frame($0, in: run)) < distance(frame($1, in: run)) }) else { return nil }
            let string = run.string as NSString
            var index = line.location
            var bestOffset = index
            var bestDistance = CGFloat.greatestFiniteMagnitude
            while index < NSMaxRange(line) {
                let character = string.rangeOfComposedCharacterSequence(at: index)
                let rect = frame(character, in: run)
                let rtl = index + character.length < NSMaxRange(line)
                    && frame(NSRange(location: index + character.length, length: 1), in: run).minX < rect.minX
                for (x, offset) in [(rtl ? rect.maxX : rect.minX, character.location), (rtl ? rect.minX : rect.maxX, NSMaxRange(character))] {
                    let d = abs(point.x - x)
                    if d < bestDistance { bestDistance = d; bestOffset = offset }
                }
                index = NSMaxRange(character)
            }
            return (.init(block: run.block, offset: run.offset + bestOffset), run)
        }

        override func draw(_ dirtyRect: NSRect) {
            guard selection.hasSelection else { return }
            NSColor.selectedTextBackgroundColor.withAlphaComponent(window?.isKeyWindow == true ? 0.35 : 0.18).setFill()
            for run in runs {
                guard let selected = selection.range(in: run.block) else { continue }
                let intersection = NSIntersectionRange(selected, NSRange(location: run.offset, length: run.length))
                guard intersection.length > 0 else { continue }
                let local = NSRange(location: intersection.location - run.offset, length: intersection.length)
                let clip = convert(run.field.visibleRect, from: run.field).intersection(visibleRect)
                guard !clip.isEmpty else { continue }
                for line in lines(in: run) {
                    let range = NSIntersectionRange(local, line)
                    guard range.length > 0 else { continue }
                    let rect = frame(range, in: run).intersection(clip)
                    if rect.intersects(dirtyRect) { rect.fill() }
                }
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard active, let window, event.window === window, window.attachedSheet == nil,
                  let scroll = enclosingScrollView else { return event }
            if event.type == .keyDown {
                guard isReading, window.isKeyWindow, event.keyCode == 0,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command else { return event }
                if let editor = window.firstResponder as? NSTextView, editor.isEditable { return event }
                if let field = window.firstResponder as? NSTextField, field.isEditable { return event }
                window.makeFirstResponder(self)
                selectAll(nil)
                return nil
            }
            let point = convert(event.locationInWindow, from: nil)
            let viewport = convert(scroll.contentView.bounds, from: scroll.contentView)
            if event.type == .leftMouseDown { isReading = viewport.contains(point) }
            if event.type == .leftMouseDragged || event.type == .leftMouseUp {
                guard mouseDownPoint != nil else { return event }
                if event.type == .leftMouseDragged {
                    dragPoint = event.locationInWindow
                    if let start = mouseDownPoint, hypot(start.x - point.x, start.y - point.y) > 3 { dragged = true }
                    if dragged { extendDrag(to: point) }
                } else {
                    if !dragged, let clickedLink { openURL(clickedLink) }
                    mouseDownPoint = nil; dragPoint = nil; clickedLink = nil
                    dragTimer?.invalidate(); dragTimer = nil
                }
                return nil
            }
            guard viewport.contains(point), bounds.contains(point) else { return event }
            refreshRuns()
            // Only text initiates selection. This leaves all SwiftUI buttons,
            // diagram controls, scrollers and context menus on their existing path.
            guard runs.contains(where: { convert($0.field.visibleRect, from: $0.field).contains(point) }) else {
                if event.type == .leftMouseDown {
                    selection.clear(); needsDisplay = true
                }
                return event
            }
            if event.type == .rightMouseDown {
                guard selection.hasSelection else { return event }
                let menu = NSMenu()
                let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
                copy.target = self; menu.addItem(copy)
                let all = NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "")
                all.target = self; menu.addItem(all)
                NSMenu.popUpContextMenu(menu, with: event, for: self)
                return nil
            }
            guard let (position, run) = position(at: point) else { return event }
            window.makeFirstResponder(self)
            mouseDownPoint = point; dragPoint = event.locationInWindow; dragged = false
            clickedLink = nil; wordAnchor = nil
            let local = min(max(position.offset - run.offset, 0), max(0, run.length - 1))
            if event.clickCount == 1, !event.modifierFlags.contains(.shift), run.length > 0 {
                let link = run.field.attributedStringValue.attribute(.link, at: local, effectiveRange: nil)
                clickedLink = link as? URL ?? (link as? String).flatMap(URL.init(string:))
            }
            if event.clickCount >= 2 {
                let string = run.string as NSString
                let range = event.clickCount >= 3 ? string.paragraphRange(for: NSRange(location: local, length: 0)) : run.field.attributedStringValue.doubleClick(at: local)
                let start = DocumentTextSelection.Position(block: run.block, offset: run.offset + range.location)
                let end = DocumentTextSelection.Position(block: run.block, offset: run.offset + NSMaxRange(range))
                selection.anchor = start; selection.extent = end; wordAnchor = (start, end)
            } else if event.modifierFlags.contains(.shift), selection.anchor != nil {
                selection.extent = position
            } else {
                selection.anchor = position; selection.extent = position
            }
            selection.selectsAll = false
            needsDisplay = true
            dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.autoscrollDrag() }
            return nil
        }

        private func extendDrag(to point: NSPoint) {
            guard let (position, run) = position(at: point) else { return }
            if let (start, end) = wordAnchor {
                let index = min(max(position.offset - run.offset, 0), run.length - 1)
                let word = run.field.attributedStringValue.doubleClick(at: index)
                if position < start {
                    selection.anchor = end
                    selection.extent = .init(block: run.block, offset: run.offset + word.location)
                } else {
                    selection.anchor = start
                    selection.extent = .init(block: run.block, offset: run.offset + NSMaxRange(word))
                }
            } else { selection.extent = position }
            needsDisplay = true
        }

        private func autoscrollDrag() {
            guard dragged, let dragPoint, let scroll = enclosingScrollView else { return }
            let clip = scroll.contentView
            let point = clip.convert(dragPoint, from: nil)
            let margin: CGFloat = 20
            let dy = point.y < clip.bounds.minY + margin ? point.y - clip.bounds.minY - margin
                : point.y > clip.bounds.maxY - margin ? point.y - clip.bounds.maxY + margin : 0
            guard dy != 0 else { return }
            var bounds = clip.bounds
            bounds.origin.y += min(28, max(-28, dy))
            clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
            scroll.reflectScrolledClipView(clip)
            refreshRuns()
            extendDrag(to: convert(dragPoint, from: nil))
        }

        @objc func copy(_ sender: Any?) {
            guard selection.hasSelection else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selection.copiedText, forType: .string)
        }
        override func selectAll(_ sender: Any?) {
            refreshRuns()
            selection.selectsAll = true
            selection.anchor = .init(block: 0, offset: 0)
            if let last = selection.text.indices.last {
                selection.extent = .init(block: last, offset: (selection.text[last] as NSString).length)
            }
            needsDisplay = true
        }
        func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
            if item.action == #selector(copy(_:)) { return selection.hasSelection }
            if item.action == #selector(selectAll(_:)) { return !selection.text.isEmpty }
            return false
        }

        override func keyDown(with event: NSEvent) {
            guard [123, 124, 125, 126].contains(event.keyCode) else { super.keyDown(with: event); return }
            refreshRuns()
            guard !selection.text.isEmpty else { return }
            let forward = event.keyCode == 124 || event.keyCode == 125
            let modify = event.modifierFlags.contains(.shift)
            if selection.selectsAll {
                selection.anchor = .init(block: 0, offset: 0)
                selection.extent = .init(block: selection.text.count - 1, offset: (selection.text.last! as NSString).length)
                selection.selectsAll = false
            }
            var position = selection.extent ?? .init(block: 0, offset: 0)
            if !modify, let anchor = selection.anchor, let extent = selection.extent, anchor != extent {
                position = forward ? max(anchor, extent) : min(anchor, extent)
            } else if event.modifierFlags.contains(.command) && (event.keyCode == 125 || event.keyCode == 126) {
                position = forward ? .init(block: selection.text.count - 1, offset: (selection.text.last! as NSString).length) : .init(block: 0, offset: 0)
            } else if event.modifierFlags.contains(.command) {
                if let run = run(containing: position) {
                    let local = min(position.offset - run.offset, run.length - 1)
                    if let line = lines(in: run).first(where: { NSLocationInRange(local, $0) }) {
                        position.offset = run.offset + (forward ? NSMaxRange(line) : line.location)
                    }
                }
            } else if event.keyCode == 125 || event.keyCode == 126 {
                if let run = runs.first(where: { $0.block == position.block && position.offset >= $0.offset && position.offset <= $0.offset + $0.length }) {
                    let index = min(max(0, position.offset - run.offset), run.length - 1)
                    let rect = frame(NSRange(location: index, length: 1), in: run)
                    let candidates = runs.flatMap { run in lines(in: run).map { frame($0, in: run) } }
                        .filter { forward ? $0.minY > rect.minY + 2 : $0.minY < rect.minY - 2 }
                    if let target = candidates.min(by: { abs($0.minY - rect.minY) < abs($1.minY - rect.minY) }) {
                        position = self.position(at: NSPoint(x: rect.minX, y: target.midY), includingOffscreen: true)?.0 ?? position
                    } else if forward, position.block + 1 < selection.text.count {
                        position = .init(block: position.block + 1, offset: 0)
                    } else if !forward, position.block > 0 {
                        position = .init(block: position.block - 1, offset: (selection.text[position.block - 1] as NSString).length)
                    }
                }
            } else {
                let string = selection.text[position.block] as NSString
                let offset = min(position.offset, string.length)
                if event.modifierFlags.contains(.option) {
                    position.offset = NSAttributedString(string: string as String).nextWord(from: offset, forward: forward)
                } else if forward, offset < string.length {
                    position.offset = NSMaxRange(string.rangeOfComposedCharacterSequence(at: offset))
                } else if !forward, offset > 0 {
                    position.offset = string.rangeOfComposedCharacterSequence(at: offset - 1).location
                } else if forward, position.block + 1 < selection.text.count {
                    position = .init(block: position.block + 1, offset: 0)
                } else if !forward, position.block > 0 {
                    position = .init(block: position.block - 1, offset: (selection.text[position.block - 1] as NSString).length)
                }
            }
            if !modify || selection.anchor == nil { selection.anchor = position }
            selection.extent = position
            revealExtent()
            needsDisplay = true
        }

        private func run(containing position: DocumentTextSelection.Position) -> Run? {
            runs.first { $0.block == position.block && position.offset >= $0.offset && position.offset <= $0.offset + $0.length }
        }

        private func revealExtent() {
            guard let position = selection.extent else { return }
            if let run = run(containing: position) {
                revealAfterLayout = false
                let index = min(max(0, position.offset - run.offset), run.length - 1)
                scrollToVisible(frame(NSRange(location: index, length: 1), in: run).insetBy(dx: 0, dy: -4))
            } else if !revealAfterLayout {
                revealAfterLayout = true
                scrollToBlock(position.block)
            }
        }
    }
}
