import AppKit
import SwiftUI

/// SwiftUI's read-only document doesn't become a keyboard scroll responder.
/// Attach inside its ScrollView so arrow keys can reach that specific viewport.
struct DocumentScrollKeys: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollKeyView {
        ScrollKeyView()
    }

    func updateNSView(_ nsView: ScrollKeyView, context: Context) {}

    static func dismantleNSView(_ nsView: ScrollKeyView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class ScrollKeyView: NSView {
        private var isReading = true
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window,
                  let scrollView = enclosingScrollView else { return event }

            if event.type == .leftMouseDown {
                // Clicking empty article space may leave the history list as
                // first responder. Track the actual pane rather than relying
                // on that stale responder to decide where arrows should go.
                let point = scrollView.convert(event.locationInWindow, from: nil)
                isReading = scrollView.bounds.contains(point)
                return event
            }

            guard isReading,
                  window.isKeyWindow, window.attachedSheet == nil,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  event.keyCode == 125 || event.keyCode == 126,
                  let documentView = scrollView.documentView else { return event }

            // Leave text editing and keyboard navigation in other panes alone.
            if let textView = window.firstResponder as? NSTextView, textView.isEditable {
                return event
            }
            if window.firstResponder is NSTextField { return event }
            if let selection = window.firstResponder as? DocumentSelection.SelectionView, selection.hasSelection {
                return event
            }

            let clipView = scrollView.contentView
            let down = event.keyCode == 125
            let direction: CGFloat = down == documentView.isFlipped ? 1 : -1
            var bounds = clipView.bounds
            bounds.origin.y += direction * max(scrollView.verticalLineScroll, 32)
            clipView.scroll(to: clipView.constrainBoundsRect(bounds).origin)
            scrollView.reflectScrolledClipView(clipView)
            return nil
        }

        deinit { stopMonitoring() }
    }
}
