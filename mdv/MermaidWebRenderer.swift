import AppKit
import SwiftUI
import WebKit

struct MermaidWebViewContainer: View {
    let source: String
    let theme: MDVTheme

    // Start small + show a spinner instead of holding a 300pt placeholder
    // open until the first measurement arrives. The document then reflows
    // exactly once — when mermaid actually reports the rendered SVG height
    // — rather than jumping from 300 to the real value mid-scroll.
    @State private var height: CGFloat = 60
    @State private var measured = false
    @State private var failed = false

    var body: some View {
        Group {
            if failed {
                MermaidFallbackView(source: source, theme: theme)
            } else {
                MermaidWebView(source: source, theme: theme,
                               height: $height, measured: $measured, failed: $failed)
                    .frame(height: max(height, 60))
                    .overlay {
                        if !measured {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
            }
        }
        // Match the native renderer's accessibility surface
        // (`MDVMermaidDiagramView.diagramBody` exposes the same label).
        // The embedded WebView's own AX tree is opaque to VoiceOver, so
        // collapsing this subtree to a single labeled element is more
        // useful than leaking whatever the WebView happens to expose.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mermaid diagram")
        .accessibilityHint("Use Show Mermaid Source to view the diagram code.")
    }
}

struct MermaidWebView: NSViewRepresentable {
    let source: String
    let theme: MDVTheme
    @Binding var height: CGFloat
    @Binding var measured: Bool
    @Binding var failed: Bool

    struct LoadKey: Equatable {
        let source: String
        let themeID: String
        let isDark: Bool
    }

    private static let mermaidJS: String = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }()

    /// Render a SwiftUI `Color` as a CSS `rgb(...)` literal in sRGB so the
    /// HTML body can be painted to match the surrounding chrome without a
    /// transparent WebView. Falls back to `transparent` if the conversion
    /// can't be done (which collapses to the WebView's default background
    /// — uglier but never crashes the build).
    static func cssColor(_ color: Color) -> String {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return "transparent" }
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return "rgb(\(r),\(g),\(b))"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, measured: $measured, failed: $failed)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "mermaidHeight")
        let webView = WKWebView(frame: .zero, configuration: config)
        // We used to KVC `drawsBackground = false` here so the chrome's
        // themed background showed through, but that's a private-API hack.
        // Instead, paint the same color from inside the HTML body — see
        // `buildHTML` — and let the WebView stay opaque.
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // `WKUserContentController.add(_:name:)` retains the script-message
        // handler. SwiftUI tears the representable down when the diagram
        // scrolls out of identity, but the configuration's userContentController
        // would keep the coordinator alive (with its bindings) until the
        // WebView itself is collected. Explicit removal here keeps lifecycle
        // honest and is the documented Apple pattern.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mermaidHeight")
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Reload only when source/theme actually change. Without this guard,
        // every SwiftUI update (including the height write we trigger from JS)
        // would reload the page, which would re-measure and re-write height,
        // creating a feedback loop — see CLAUDE.md.
        let key = LoadKey(source: source, themeID: theme.id, isDark: theme.isDark)
        guard context.coordinator.lastLoadKey != key else { return }
        context.coordinator.lastLoadKey = key
        context.coordinator.lastMeasuredHeight = nil

        // A previous render may have failed; we're loading fresh content,
        // so clear the flag before the new render reports back.
        DispatchQueue.main.async { self.failed = false }

        let html = Self.buildHTML(source: source, theme: theme)
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func buildHTML(source: String, theme: MDVTheme, chrome: Bool = true) -> String {
        let mermaidTheme = theme.isDark ? "dark" : "default"
        let pollFallback = chrome ? "" : """
            // Print path: the offscreen window may never receive animation
            // frames, so the double-rAF report above can starve. Timers
            // always fire, so poll until the height stabilizes (3 identical
            // reads) or a deadline passes.
            var mdvT0 = Date.now(), mdvLast = -1, mdvStable = 0;
            var mdvTimer = setInterval(function() {
              var h = svg.getBoundingClientRect().height;
              if (h === mdvLast) { mdvStable++; } else { mdvStable = 0; mdvLast = h; }
              if (mdvStable >= 3 || Date.now() - mdvT0 > 3000) {
                clearInterval(mdvTimer);
                report();
              }
            }, 50);
            """
        let escaped = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        // Match the chrome background painted by `MermaidCodeBlockChrome`
        // (theme.secondaryBackground). The WebView itself is opaque now,
        // so without this the diagram zone would show whatever the system
        // default WebView background is and clash with the surrounding
        // chrome on every dark-and-not-quite-black theme.
        let bgCSS = Self.cssColor(theme.secondaryBackground)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { background: \(bgCSS); }
          .mermaid { padding: \(chrome ? "12px 18px" : "0"); }
          .mermaid svg { max-width: 100%; height: auto; display: block; }
        </style>
        </head>
        <body>
        <div class="mermaid">\(escaped)</div>
        <script>\(Self.mermaidJS)</script>
        <script>
          // `securityLevel: 'strict'` is the mermaid.js default in v11, but
          // pinning it here means the bundled JS can ship with whatever
          // default it likes in the future without quietly downgrading the
          // sandbox around user-supplied diagram source.
          mermaid.initialize({
            startOnLoad: false,
            theme: '\(mermaidTheme)',
            securityLevel: 'strict'
          });
          mermaid.run().then(function() {
            var svg = document.querySelector('.mermaid svg');
            if (!svg) {
              window.webkit.messageHandlers.mermaidHeight.postMessage({ ok: false, error: 'no SVG produced' });
              return;
            }
            function report() {
              var h = svg.getBoundingClientRect().height + \(chrome ? 24 : 0);
              window.webkit.messageHandlers.mermaidHeight.postMessage({ ok: true, height: h });
            }
            // Some diagram types (journey, quadrantChart, requirementDiagram)
            // finalize their SVG dimensions *after* the run() promise resolves.
            // A bare `getBoundingClientRect()` here returns a stale ~60pt
            // height; waiting two animation frames lets the browser complete
            // its first paint, and a ResizeObserver catches any further
            // adjustments. The Swift side filters sub-pixel noise so the
            // tail of ResizeObserver callbacks doesn't churn @State.
            requestAnimationFrame(function() {
              requestAnimationFrame(report);
            });
            if (typeof ResizeObserver !== 'undefined') {
              new ResizeObserver(report).observe(svg);
            }
            \(pollFallback)
          }).catch(function(err) {
            window.webkit.messageHandlers.mermaidHeight.postMessage({ ok: false, error: String(err) });
          });
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        @Binding var height: CGFloat
        @Binding var measured: Bool
        @Binding var failed: Bool
        var lastLoadKey: LoadKey?
        var lastMeasuredHeight: CGFloat?

        init(height: Binding<CGFloat>, measured: Binding<Bool>, failed: Binding<Bool>) {
            _height = height
            _measured = measured
            _failed = failed
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mermaidHeight",
                  let body = message.body as? [String: Any],
                  let ok = body["ok"] as? Bool else { return }

            if !ok {
                DispatchQueue.main.async { self.failed = true }
                return
            }

            guard let h = body["height"] as? Double, h > 0 else {
                DispatchQueue.main.async { self.failed = true }
                return
            }
            let newHeight = CGFloat(h)
            // Avoid noise: only republish when the measurement materially
            // changes. SwiftUI re-renders are cheap, but the @State write here
            // is what feeds back into updateNSView; the LoadKey guard there
            // catches reloads, but suppressing micro-deltas keeps things calm.
            if let last = lastMeasuredHeight, abs(last - newHeight) < 0.5 { return }
            lastMeasuredHeight = newHeight
            DispatchQueue.main.async {
                self.height = newHeight
                // First successful measurement: drop the ProgressView overlay.
                // We never flip back to false on subsequent reloads (theme
                // change, etc.) so the existing render stays on screen until
                // the new one settles, instead of flashing a spinner.
                if !self.measured { self.measured = true }
            }
        }
    }
}

/// The height handshake for one offscreen mermaid render.
///
/// Deliberately not actor-isolated: the report arrives on WebKit's message
/// thread, the wait is started from the main actor, and the timeout and
/// cancellation paths run wherever those land — so the state is lock-guarded
/// instead of pretending to belong to an actor. (It sits outside
/// `MermaidWebRenderer` because a type nested in a `@MainActor` type inherits
/// that isolation, which is precisely what the cancellation handler cannot
/// honour.)
/// `@unchecked Sendable`: every mutable field is read and written under
/// `lock`, which is what lets the timeout block hold it across the queue hop.
private final class MermaidHeightReport: @unchecked Sendable {
    private let lock = NSLock()
    private var token = 0
    /// The latest height, or a negative sentinel for a failed render, so a
    /// report that lands before anyone waits is not lost.
    private var value: CGFloat?
    private var pending: (token: Int, cont: CheckedContinuation<CGFloat?, Never>)?

    private var reported: CGFloat? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    /// Records a height (`nil` = the page failed) and resumes a waiter.
    func record(_ height: CGFloat?) {
        lock.lock()
        value = height ?? -1
        let waiter = pending
        pending = nil
        lock.unlock()
        waiter?.cont.resume(returning: height)
    }

    func wait(timeout: TimeInterval) async -> CGFloat? {
        if let reported { return reported < 0 ? nil : reported }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<CGFloat?, Never>) in
                lock.lock()
                let myToken = token &+ 1
                token = myToken
                pending = (token: myToken, cont: cont)
                lock.unlock()
                // A page whose render never settles (broken JS, a type the
                // bundled mermaid.js rejects) must not hang the print job.
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    self.giveUp(token: myToken)
                }
            }
        } onCancel: {
            self.giveUp(token: nil)
        }
    }

    /// Resumes the installed waiter with `nil` — the timeout passes its own
    /// token (so it cannot steal a later wait), cancellation passes none.
    private func giveUp(token expected: Int?) {
        lock.lock()
        guard let waiter = pending, expected == nil || waiter.token == expected else {
            lock.unlock()
            return
        }
        pending = nil
        lock.unlock()
        waiter.cont.resume(returning: nil)
    }
}

// MARK: - One-shot print rendering

/// Renders a diagram once through the bundled mermaid.js for the print
/// pipeline. Same HTML and JS as the on-screen path, but instead of
/// measuring the live view it rasterizes the rendered page into an
/// `NSImage`, so web-path diagrams feed the print block pipeline exactly
/// like native rasters.
///
/// The webview must live in a window: a webview that is never ordered
/// front is never composited by the render server, and its snapshot comes
/// back blank. We order a borderless window far off every display, then
/// close it as soon as the image is in hand. Returns nil on render failure
/// or timeout; the caller falls back to printing the source as a code block.
@MainActor
enum MermaidWebRenderer {

    /// Renders the diagram once through the bundled mermaid.js and returns an
    /// image whose *point* size is `width`, at roughly `density` pixels per
    /// point.
    ///
    /// `density` is approximate by design: the offscreen window is rasterized
    /// at whatever backing scale the window gets, so the page is rendered
    /// `zoom` times larger (`zoom` times the width, with the body zoomed by
    /// the same factor, which leaves the layout untouched) and the point size
    /// is derived from the pixels that come back.
    /// `width` is the layout width the page is rendered at, which decides how
    /// a diagram *lays itself out* — mermaid's own label sizes are fixed
    /// pixels, so a Gantt chart laid out at a narrow width comes out with
    /// labels that are huge relative to the page. `displayWidth` is the size
    /// the result is drawn at; print lays a diagram out at the width the
    /// screen would give it and draws it smaller, exactly as it does with type
    /// and with formulas.
    /// The diagram as a PDF *page*, for print: WebKit keeps the page's text as
    /// text, so a printed diagram drawn from this is vector — crisp at any
    /// zoom, where a snapshot is a fixed resolution and its small labels read
    /// as fuzzy next to vector prose.
    ///
    /// `width` is the layout width, exactly as in `image(...)`.
    static func pdf(
        source: String,
        theme: MDVTheme,
        width: CGFloat
    ) async -> (document: CGPDFDocument, page: CGPDFPage, size: CGSize)? {
        guard let rendered = await renderToPDF(source: source, theme: theme, width: max(width, 1)) else { return nil }
        return rendered
    }

    private static func renderToPDF(
        source: String,
        theme: MDVTheme,
        width: CGFloat
    ) async -> (document: CGPDFDocument, page: CGPDFPage, size: CGSize)? {
        let config = WKWebViewConfiguration()
        let handler = SnapshotHandler()
        config.userContentController.add(handler, name: "mermaidHeight")
        let window = RenderWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 400), configuration: config)
        window.contentView = webView
        // Deliberately *not* ordered front: this path asks WebKit for a PDF,
        // which it paints itself, so the render server never has to composite
        // the window — and an un-ordered window is never drawn, so the print
        // job no longer flashes a diagram-sized rectangle across the screen.
        // (The snapshot path below still needs one; see its comment.)
        webView.loadHTMLString(
            MermaidWebView.buildHTML(source: source, theme: theme, chrome: false),
            baseURL: nil
        )
        let height = await handler.waitForHeight(timeout: 5)
        guard let height, height > 0 else {
            window.close()
            return nil
        }
        webView.frame.size = NSSize(width: width, height: height)
        window.setContentSize(NSSize(width: width, height: height))
        try? await Task.sleep(for: .milliseconds(200))
        let data = await handler.pdf(webView, rect: CGRect(x: 0, y: 0, width: width, height: height))
        window.close()
        guard let data,
              let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        return (document, page, CGSize(width: width, height: height))
    }

    static func image(
        source: String,
        theme: MDVTheme,
        width: CGFloat,
        displayWidth: CGFloat? = nil,
        density: CGFloat = 2
    ) async -> NSImage? {
        let width = max(width, 1)
        let displayWidth = max(displayWidth ?? width, 1)
        let config = WKWebViewConfiguration()
        let handler = SnapshotHandler()
        config.userContentController.add(handler, name: "mermaidHeight")
        let window = RenderWindow(
            contentRect: CGRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // How much bigger than one point per pixel the capture should be. The
        // page itself is never re-laid-out — zooming the body changed mermaid's
        // own layout, which clipped a Gantt chart's labels — only the snapshot
        // is taken wider, and the point size below puts the pixels back.
        let backing = max(window.backingScaleFactor, 1)
        let zoom = max(1, density / backing)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 400), configuration: config)
        window.contentView = webView
        // Programmatically created NSWindows default to
        // `isReleasedWhenClosed == true`, which makes `close()` perform a raw
        // `release` on top of ARC's own reference — an over-release that
        // later traps as "message sent to deallocated instance" (seen as a
        // SIGSEGV in `-[_NSWindowTransformAnimation dealloc]` during a
        // CoreAnimation commit). ARC owns this window; AppKit must not.
        window.isReleasedWhenClosed = false
        // `makeKeyAndOrderFront` is load-bearing here and only here: a webview
        // whose window was never ordered front is never composited by the
        // render server, and its snapshot comes back blank. That is also why
        // this fallback (and not the PDF path) is the one that can flash.
        window.makeKeyAndOrderFront(nil)
        // Same HTML/JS as the on-screen path (chrome-less variant): without
        // this the webview stays blank, no height ever gets reported, and
        // every web-path diagram falls back to printing its source.
        webView.loadHTMLString(
            MermaidWebView.buildHTML(source: source, theme: theme, chrome: false),
            baseURL: nil
        )
        NSLog("MDV_SELFTEST: web render started (width \(width), zoom \(zoom))")

        let height = await handler.waitForHeight(timeout: 5)
        NSLog("MDV_SELFTEST: height reported: \(height.map { String(format: "%.1f", $0) } ?? "timeout")")
        guard let height, height > 0 else {
            window.close()
            return nil
        }
        // The SVG lays out at the webview width (max-width: 100%), which
        // never changed; resizing only trims the empty body below it. Give
        // the compositor one beat to settle before capturing.
        webView.frame.size = NSSize(width: width, height: height)
        window.setContentSize(NSSize(width: width, height: height))
        try? await Task.sleep(for: .milliseconds(200))
        let cg = await handler.snapshot(webView, width: displayWidth * zoom)
        NSLog("MDV_SELFTEST: snapshot \(cg == nil ? "nil" : "ok")")
        window.close()
        guard let cg else { return nil }
        // Point size is the width the view will draw at, and the height follows
        // the snapshot's own aspect — the snapshot's backing scale is whatever
        // the window got, which is not something to assume. The pixels carry
        // the resolution.
        let pointHeight = CGFloat(cg.height) / CGFloat(max(cg.width, 1)) * displayWidth
        return NSImage(cgImage: cg, size: NSSize(width: displayWidth, height: pointHeight))
    }

    private final class SnapshotHandler: NSObject, WKScriptMessageHandler {
        private let height = MermaidHeightReport()

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mermaidHeight",
                  let body = message.body as? [String: Any] else { return }
            if let ok = body["ok"] as? Bool, ok, let h = body["height"] as? Double, h > 0 {
                height.record(CGFloat(h))
            } else {
                height.record(nil)
            }
        }

        func waitForHeight(timeout: TimeInterval) async -> CGFloat? {
            await height.wait(timeout: timeout)
        }

        /// The page as a PDF of `rect` — vector text and all.
        func pdf(_ webView: WKWebView, rect: CGRect) async -> Data? {
            await withCheckedContinuation { continuation in
                let config = WKPDFConfiguration()
                config.rect = rect
                webView.createPDF(configuration: config) { result in
                    continuation.resume(returning: try? result.get())
                }
            }
        }

        func snapshot(_ webView: WKWebView, width: CGFloat) async -> CGImage? {
            await withCheckedContinuation { continuation in
                // `snapshotWidth` is in points and scales the capture, not the
                // page, so a diagram can be captured at print resolution
                // without disturbing how mermaid laid it out.
                let config = WKSnapshotConfiguration()
                config.snapshotWidth = NSNumber(value: Double(width))
                webView.takeSnapshot(with: config) { image, _ in
                    let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    continuation.resume(returning: cg)
                }
            }
        }
    }

    /// `.borderless` windows cannot become key by default, and a WKWebView
    /// whose window can never become key never runs page scripts — the
    /// height report (and with it the whole print render) would starve.
    private final class RenderWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }
}