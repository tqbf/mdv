import SwiftUI
import WebKit

struct MermaidWebViewContainer: View {
    let source: String
    let theme: MDVTheme

    @State private var height: CGFloat = 300
    @State private var failed = false

    var body: some View {
        if failed {
            MermaidFallbackView(source: source, theme: theme)
        } else {
            MermaidWebView(source: source, theme: theme, height: $height, failed: $failed)
                .frame(height: max(height, 60))
        }
    }
}

struct MermaidWebView: NSViewRepresentable {
    let source: String
    let theme: MDVTheme
    @Binding var height: CGFloat
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

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, failed: $failed) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "mermaidHeight")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
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

        let html = buildHTML(source: source, isDark: theme.isDark)
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func buildHTML(source: String, isDark: Bool) -> String {
        let mermaidTheme = isDark ? "dark" : "default"
        let escaped = source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="UTF-8">
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { background: transparent; }
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
            if (svg) {
              var h = svg.getBoundingClientRect().height + 24;
              window.webkit.messageHandlers.mermaidHeight.postMessage({ ok: true, height: h });
            } else {
              window.webkit.messageHandlers.mermaidHeight.postMessage({ ok: false, error: 'no SVG produced' });
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
        @Binding var failed: Bool
        var lastLoadKey: LoadKey?
        var lastMeasuredHeight: CGFloat?

        init(height: Binding<CGFloat>, failed: Binding<Bool>) {
            _height = height
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
            DispatchQueue.main.async { self.height = newHeight }
        }
    }
}
