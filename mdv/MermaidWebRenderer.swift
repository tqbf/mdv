import SwiftUI
import WebKit

struct MermaidWebViewContainer: View {
    let source: String
    let theme: MDVTheme

    @State private var height: CGFloat = 300

    var body: some View {
        MermaidWebView(source: source, theme: theme, height: $height)
            .frame(height: max(height, 60))
    }
}

struct MermaidWebView: NSViewRepresentable {
    let source: String
    let theme: MDVTheme
    @Binding var height: CGFloat

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

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

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
            var h = svg ? svg.getBoundingClientRect().height + 24 : -1;
            window.webkit.messageHandlers.mermaidHeight.postMessage(h);
          }).catch(function() {
            window.webkit.messageHandlers.mermaidHeight.postMessage(-1);
          });
        </script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        @Binding var height: CGFloat
        var lastLoadKey: LoadKey?
        var lastMeasuredHeight: CGFloat?

        init(height: Binding<CGFloat>) { _height = height }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mermaidHeight",
                  let h = message.body as? Double, h > 0 else { return }
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
