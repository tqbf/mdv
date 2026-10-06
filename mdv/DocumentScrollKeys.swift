import AppKit
import SwiftUI

/// SwiftUI's read-only document doesn't become a keyboard scroll responder.
/// Attach inside its ScrollView so the arrow, page, Space, Home and End keys
/// can reach that specific viewport.
struct DocumentScrollKeys: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollKeyView {
        ScrollKeyView()
    }

    func updateNSView(_ nsView: ScrollKeyView, context: Context) {}

    static func dismantleNSView(_ nsView: ScrollKeyView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class ScrollKeyView: NSView {
        /// Virtual key codes of the keys that scroll the document.
        private enum Key: UInt16 {
            case down = 125, up = 126, pageDown = 121, pageUp = 116, space = 49, home = 115, end = 119
        }

        private var isReading = true
        private var monitor: Any?
        /// Bumped by every scroll key, so a later key cancels an End that is
        /// still settling.
        private var generation = 0

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

            // Shift belongs to text selection, except on Space, where it pages up.
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard isReading,
                  window.isKeyWindow, window.attachedSheet == nil,
                  mods.isEmpty || (mods == .shift && event.keyCode == Key.space.rawValue),
                  let key = Key(rawValue: event.keyCode),
                  let documentView = scrollView.documentView else { return event }

            // Leave text editing and keyboard navigation in other panes alone.
            if let textView = window.firstResponder as? NSTextView, textView.isEditable {
                return event
            }
            if window.firstResponder is NSTextField { return event }
            // A selection takes the arrows to move its caret. It has no use for
            // the other keys, which scroll with or without one.
            if key == .down || key == .up,
               let selection = window.firstResponder as? DocumentSelection.SelectionView, selection.hasSelection {
                return event
            }

            let clipView = scrollView.contentView
            let down = key == .space ? mods.isEmpty : [.down, .pageDown, .end].contains(key)
            let direction: CGFloat = down == documentView.isFlipped ? 1 : -1
            let lineStep = max(scrollView.verticalLineScroll, 32)
            let y: CGFloat
            switch key {
            case .down, .up:
                y = clipView.bounds.origin.y + direction * lineStep
            case .pageDown, .pageUp, .space:
                // A screen less an eighth, as Safari pages: the overlap lets the
                // eye find its line again. The clip view runs up under the
                // full-size title bar, so a screen is the height its content
                // insets leave readable, not the raw clip height.
                let insets = scrollView.contentInsets
                let usable = clipView.bounds.height - insets.top - insets.bottom
                y = clipView.bounds.origin.y + direction * max(0.875 * usable, lineStep)
            case .home, .end:
                y = direction * Self.pastEnds(of: scrollView)
            }
            generation += 1
            let landed = scroll(scrollView, toY: y)
            if key == .end { settleAtEnd(scrollView, direction: direction, landed: landed, framesLeft: 10) }
            return nil
        }

        /// Far enough past either end of the document that the clamp lands
        /// exactly on that end. Not `.infinity`: `constrainBoundsRect` does
        /// arithmetic on the proposed rect, and an unbounded origin comes
        /// back as a no-op.
        private static func pastEnds(of scrollView: NSScrollView) -> CGFloat {
            (scrollView.documentView?.frame.height ?? 0) + scrollView.contentView.bounds.height
        }

        /// Scrolls to `y` as AppKit clamps it and returns where it landed.
        /// `constrainBoundsRect` knows the document size and the content
        /// insets: under a full-size title bar the true top is a negative
        /// origin, not zero.
        private func scroll(_ scrollView: NSScrollView, toY y: CGFloat) -> CGFloat {
            let clipView = scrollView.contentView
            var bounds = clipView.bounds
            bounds.origin.y = y
            let origin = clipView.constrainBoundsRect(bounds).origin
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
            return origin.y
        }

        /// One jump to the end of a LazyVStack lands short: the blocks near
        /// the end are realized only once they are in view, and the stack
        /// grows as they are. Re-aim on later frames until the landing stops
        /// moving, and give up after `framesLeft` frames regardless, so a
        /// document that keeps growing cannot hold us here.
        private func settleAtEnd(_ scrollView: NSScrollView, direction: CGFloat, landed: CGFloat, framesLeft: Int) {
            guard framesLeft > 0 else { return }
            let generation = self.generation
            // A frame apart, not a bare hop through the main queue: a retry is
            // worth something only after a layout pass has had a chance to
            // grow the stack.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self, weak scrollView] in
                guard let self, let scrollView, generation == self.generation else { return }
                let y = self.scroll(scrollView, toY: direction * Self.pastEnds(of: scrollView))
                if y != landed {
                    self.settleAtEnd(scrollView, direction: direction, landed: y, framesLeft: framesLeft - 1)
                }
            }
        }

        deinit { stopMonitoring() }
    }
}
