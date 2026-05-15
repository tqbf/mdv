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

        init(height: Binding<CGFloat>) { _height = height }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mermaidHeight",
                  let h = message.body as? Double, h > 0 else { return }
            DispatchQueue.main.async { self.height = CGFloat(h) }
        }
    }
}
