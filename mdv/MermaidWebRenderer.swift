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

        let html = buildHTML(source: source, theme: theme)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildHTML(source: String, theme: MDVTheme) -> String {
        let mermaidTheme = theme.isDark ? "dark" : "default"
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
          .mermaid { padding: 12px 18px; }
          .mermaid svg { max-width: 100%; height: auto; display: block; }
        </style>
        </head>
        <body>
        <div class="mermaid">\(escaped)</div>
        <script>\(Self.mermaidJS)</script>
        <script>
          mermaid.initialize({ startOnLoad: false, theme: '\(mermaidTheme)' });
          mermaid.run().then(function() {
            var svg = document.querySelector('.mermaid svg');
            if (!svg) {
              window.webkit.messageHandlers.mermaidHeight.postMessage({ ok: false, error: 'no SVG produced' });
              return;
            }
            function report() {
              var h = svg.getBoundingClientRect().height + 24;
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
