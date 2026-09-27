import AppKit
import SwiftUI

/// Keyboard scrolling for the document pane. A SwiftUI ScrollView takes no
/// keyboard input of its own: arrow and page keys land on whichever block
/// happens to hold focus, walk focus from block to block, and stop dead at
/// the first one that will not take them — the system beep. So a local
/// keyDown monitor scrolls the backing NSScrollView directly, and the keys
/// behave the same whether or not anything in the document is focused.
///
/// The monitor goes live the moment `EnclosingScrollViewAccessor` hands it a
/// scroll view, and is torn down with the view state that owns it. No
/// lifecycle hook is needed at the call site: until the accessor reports in,
/// there is nothing to scroll and every key passes straight through.
///
/// The document gets the key only when nothing holds focus or a read-only
/// text block does. A field editor, the sidebar list or a keyboard-focused
/// button keeps its keys, as does anything carrying a command, option or
/// control modifier — the find bar, the search fields, list stepping and
/// every ⌘-chord still work.
final class ScrollKeyMonitor: ObservableObject {
    private var monitor: Any?

    /// Planted by the accessor in the document's background. Weak: a closed
    /// window's scroll view should not be pinned here.
    weak var scrollView: NSScrollView? {
        didSet { if scrollView != nil { install() } }
    }

    /// Arrow-key step, in points — about three lines of body text.
    private let lineStep: CGFloat = 40
    /// Fraction of the readable height a page key moves. Safari's figure:
    /// the remaining eighth is the overlap that lets the eye land on a line
    /// it has already read and carry on from there.
    private let pageFraction: CGFloat = 0.875

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let scroller = self.scrollView else { return event }
            let window = event.window ?? NSApp.keyWindow
            // One monitor per window, but local monitors see the whole app —
            // only scroll the document that belongs to the window the key was
            // typed into.
            guard scroller.window === window else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.isDisjoint(with: [.command, .option, .control]),
                  Self.documentOwnsKeys(in: window) else { return event }

            // The clip view runs up under the full-size title bar, so the
            // height that is actually readable is what the content insets
            // leave behind — page off that, not off the raw clip height.
            let insets = scroller.contentInsets
            let usable = scroller.contentView.bounds.height - insets.top - insets.bottom
            let page = max(usable * self.pageFraction, self.lineStep)
            let y = scroller.contentView.bounds.origin.y
            let target: CGFloat
            switch (event.keyCode, mods.contains(.shift)) {
            case (125, false): target = y + self.lineStep   // down arrow
            case (126, false): target = y - self.lineStep   // up arrow
            case (121, false): target = y + page            // page down
            case (116, false): target = y - page            // page up
            case (49, false):  target = y + page            // space
            case (49, true):   target = y - page            // shift-space
            // Deliberately past both ends: the clamp below turns these
            // into the real top and bottom, insets and all.
            case (115, false): target = -Self.beyondBottom(scroller)  // home
            case (119, false): target = Self.beyondBottom(scroller)   // end
            default: return event
            }
            Self.scroll(scroller, to: target)
            if event.keyCode == 119 { self.settleAtBottom(scroller, remaining: 10) }
            return nil
        }
    }

    /// A y far enough past the bottom of the document that the clamp lands
    /// exactly on it (negated, the same for the top). Infinity is no good
    /// here: `constrainBoundsRect` does arithmetic on the proposed rect, and
    /// an unbounded origin comes back out as a no-op.
    private static func beyondBottom(_ scroller: NSScrollView) -> CGFloat {
        (scroller.documentView?.frame.height ?? 0) + scroller.contentView.bounds.height
    }

    /// Scrolls to `y` and returns where it actually landed. The clamping is
    /// AppKit's own: `constrainBoundsRect` accounts for the document size and
    /// for the content insets, and with a full-size title bar the true top of
    /// the document is a negative origin rather than zero — clamping to zero
    /// by hand leaves the first heading tucked under the title bar.
    @discardableResult
    private static func scroll(_ scroller: NSScrollView, to y: CGFloat) -> CGFloat {
        let clip = scroller.contentView
        var bounds = clip.bounds
        bounds.origin.y = y
        let landed = clip.constrainBoundsRect(bounds).origin
        clip.scroll(to: landed)
        scroller.reflectScrolledClipView(clip)
        return landed.y
    }

    /// A lazy stack does not know its full height until the blocks near the
    /// end have been realized, so one jump to the bottom can land short. Aim
    /// at the bottom again on later frames, stopping as soon as the landing
    /// spot stops moving, and after `remaining` frames regardless, so a
    /// document that keeps growing cannot spin here.
    private func settleAtBottom(_ scroller: NSScrollView, remaining: Int) {
        guard remaining > 0 else { return }
        let before = scroller.contentView.bounds.origin.y
        // A frame apart rather than a bare hop through the main queue: the
        // retry is only worth anything once a layout pass has had its chance
        // to grow the stack, and several queued hops can drain before one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { [weak self] in
            guard Self.scroll(scroller, to: Self.beyondBottom(scroller)) != before else { return }
            self?.settleAtBottom(scroller, remaining: remaining - 1)
        }
    }

    /// The monitor takes a key only when nothing has focus, or when a
    /// read-only text block does — the selectable paragraphs, whose answer to
    /// an arrow is to walk focus to the next block. Anything else holding
    /// first responder (a field editor, the sidebar list, a button focused
    /// through Keyboard Navigation) keeps its keys. Naming the two states
    /// that belong to the document, rather than listing the ones that do
    /// not, is what keeps a newly focusable control from silently losing
    /// its Space bar to us.
    private static func documentOwnsKeys(in window: NSWindow?) -> Bool {
        guard let window, let responder = window.firstResponder, responder !== window else { return true }
        if let text = responder as? NSText { return !text.isEditable }
        return false
    }

    func uninstall() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    deinit { uninstall() }
}

/// Hands back the NSScrollView that encloses this view, which is how the
/// document scroller is found: drop the accessor into the ScrollView's own
/// content and walk up. Searching the window's view tree instead would have
/// to guess, since a window holds several scroll views — the sidebar list and
/// every code block too wide for the column each bring their own.
struct EnclosingScrollViewAccessor: NSViewRepresentable {
    let onScrollView: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Nothing is hooked into the hierarchy yet at make-time; defer to the
        // next runloop tick, same as WindowAccessor.
        DispatchQueue.main.async { onScrollView(view.enclosingScrollView) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onScrollView(nsView.enclosingScrollView) }
    }
}
