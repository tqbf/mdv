import AppKit
import SwiftUI
import cmark_gfm
import cmark_gfm_extensions

/// Uses the same CommonMark/GFM parser as MarkdownUI. AppKit imports safe HTML
/// into a single attributed string; images are removed before importing so the
/// importer can never bypass the user's remote-image preference.
enum NativeMarkdownDocument {
    struct ImageReference {
        let marker: String
        let label: String
        let url: String?
        let mermaid: String?
    }
    struct Rendered {
        let text: NSAttributedString
        let images: [ImageReference]
    }

    static func render(blocks: [String], theme: MDVTheme, scale: CGFloat) -> Rendered {
        let token = UUID().uuidString
        var images: [ImageReference] = []
        var codeBlocks: [(Int, String, String)] = []
        var links: [String: URL] = [:]
        let html = blocks.enumerated().map { index, block -> String in
            var html = renderHTML(block)
            // Generated img attributes are XML-compatible; decode entities with
            // XMLParser instead of accidentally treating an escaped URL as a URL.
            let pattern = try! NSRegularExpression(pattern: #"<img\b[^>]*>"#)
            for match in pattern.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                let tag = (html as NSString).substring(with: match.range)
                let attributes = ImageAttributes.read(tag)
                let marker = "\(token)-image-\(images.count)"
                images.append(ImageReference(marker: marker, label: attributes["alt"] ?? "image", url: attributes["src"], mermaid: nil))
                html = (html as NSString).replacingCharacters(in: match.range, with: escape(marker))
            }
            let codePattern = try! NSRegularExpression(pattern: #"<pre><code(?: class="[^"]*")?>[\s\S]*?</code></pre>"#)
            for match in codePattern.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                let element = (html as NSString).substring(with: match.range)
                let parsed = ImageAttributes.parse(element)
                let language = String((parsed.attributes["class"] ?? "").dropFirst("language-".count))
                let code = parsed.text
                if language.lowercased() == "mermaid" {
                    let marker = "\(token)-image-\(images.count)"
                    images.append(ImageReference(marker: marker, label: "diagram", url: nil, mermaid: code))
                    html = (html as NSString).replacingCharacters(in: match.range, with: "<p>\(escape(marker))</p>")
                } else { codeBlocks.append((index, code, language)) }
            }
            let anchors = try! NSRegularExpression(pattern: #"<a\b[^>]*>"#)
            for match in anchors.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
                let tag = (html as NSString).substring(with: match.range)
                guard let href = ImageAttributes.read(tag)["href"], let url = URL(string: href) else { continue }
                let marker = "mdv-link://reference/\(links.count)"
                links[marker] = url
                html = (html as NSString).replacingCharacters(in: match.range, with: "<a href='\(marker)'>")
            }
            return "<div><span>\(token)-\(index)-END</span>\(html)</div>"
        }.joined()
        let source = "<html><head><meta charset='utf-8'><style>\(stylesheet(theme, scale))</style></head><body>\(html)</body></html>"
        let result = (try? NSMutableAttributedString(data: Data(source.utf8), options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ], documentAttributes: nil)) ?? NSMutableAttributedString(string: blocks.joined(separator: "\n\n"))
        let markers = try! NSRegularExpression(pattern: "\(token)-(\\d+)-END\\n?")
        let markedString = result.string as NSString
        let boundaries = markers.matches(in: result.string, range: NSRange(location: 0, length: result.length))
        var end = result.length
        for boundary in boundaries.reversed() {
            guard let index = Int(markedString.substring(with: boundary.range(at: 1))) else { continue }
            result.deleteCharacters(in: boundary.range)
            let length = end - boundary.range.length - boundary.range.location
            result.addAttribute(.documentBlock, value: index, range: NSRange(location: boundary.range.location, length: length))
            end = boundary.range.location
        }
        var blockRanges: [Int: NSRange] = [:]
        result.enumerateAttribute(.documentBlock, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            if let index = value as? Int { blockRanges[index] = range }
        }
        let renderedString = result.string as NSString
        for (block, code, language) in codeBlocks where !code.isEmpty {
            guard let blockRange = blockRanges[block] else { continue }
            let range = renderedString.range(of: code, range: blockRange)
            guard range.location != NSNotFound else { continue }
            result.addAttribute(.documentCode, value: code, range: range)
            let highlighted = NSAttributedString(CodeRenderer.shared.render(code: code, languageHint: language, theme: theme))
            highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attributes, local, _ in
                var attributes = attributes
                if let font = attributes[.font] as? NSFont { attributes[.font] = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * scale) }
                result.addAttributes(attributes, range: NSRange(location: range.location + local.location, length: local.length))
            }
        }
        result.enumerateAttribute(.link, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            let key = (value as? URL)?.absoluteString ?? value as? String ?? ""
            if let original = links[key] { result.addAttribute(.link, value: original, range: range) }
        }
        for reference in images {
            let range = (result.string as NSString).range(of: reference.marker)
            guard range.location != NSNotFound else { continue }
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            attributes[.documentImage] = reference.marker
            if let code = reference.mermaid { attributes[.documentCode] = code }
            result.replaceCharacters(in: range, with: NSAttributedString(string: "[Image: \(reference.label)]", attributes: attributes))
        }
        return Rendered(text: result, images: images)
    }

    private static let registerExtensions: Void = cmark_gfm_core_extensions_ensure_registered()

    static func renderHTML(_ markdown: String) -> String {
        _ = registerExtensions
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else { return escape(markdown) }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "autolink", "tagfilter", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) { cmark_parser_attach_syntax_extension(parser, ext) }
        }
        markdown.withCString { cmark_parser_feed(parser, $0, markdown.utf8.count) }
        guard let node = cmark_parser_finish(parser) else { return escape(markdown) }
        defer { cmark_node_free(node) }
        guard let html = cmark_render_html(node, CMARK_OPT_DEFAULT, cmark_parser_get_syntax_extensions(parser)) else { return escape(markdown) }
        defer { free(html) }
        return String(cString: html)
            .replacingOccurrences(of: #"<input[^>]*checked[^>]*>"#, with: "☑ ", options: .regularExpression)
            .replacingOccurrences(of: #"<input[^>]*>"#, with: "☐ ", options: .regularExpression)
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func stylesheet(_ theme: MDVTheme, _ scale: CGFloat) -> String {
        func color(_ value: Color) -> String {
            let c = NSColor(value).usingColorSpace(.sRGB) ?? .textColor
            return String(format: "#%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
        let family: String
        switch theme.bodyFontFamily {
        case .custom(let name): family = name
        case .system(let design): family = design == .monospaced ? "Menlo" : design == .serif ? "Georgia" : "Helvetica Neue"
        }
        let size = theme.baseFontSize * scale
        return """
        body { font-family: '\(family)'; font-size: \(size)px; color: \(color(theme.text)); }
        p { margin: 0 0 \(theme.paragraphBottomSpacing)px; line-height: \(1.2 + theme.paragraphLineSpacingEm); }
        h1,h2,h3,h4,h5,h6 { color: \(color(theme.heading)); font-weight: \(theme.headingFontWeight == .regular ? 400 : 600); }
        h1 { font-size: \(size * theme.h1SizeEm)px; margin: \(theme.h1TopSpacing)px 0 \(theme.h1BottomSpacing)px; }
        h2 { font-size: \(size * theme.h2SizeEm)px; margin: \(theme.h2TopSpacing)px 0 \(theme.h2BottomSpacing)px; }
        h3 { font-size: \(size * theme.h3SizeEm)px; margin: \(theme.h3TopSpacing)px 0 \(theme.h3BottomSpacing)px; }
        h1 { border-bottom: \(theme.showH1Rule ? "1px solid " + color(theme.divider) : "none"); }
        h2 { border-bottom: \(theme.showH2Rule ? "1px solid " + color(theme.divider) : "none"); }
        a { color: \(color(theme.link)); } strong { color: \(color(theme.strong)); }
        code,pre { font-family: Menlo; font-size: \(size * 0.9)px; background-color: \(color(theme.secondaryBackground)); }
        pre { white-space: pre-wrap; padding: 12px; margin: 12px 0 16px; }
        blockquote { color: \(color(theme.secondaryText)); margin-left: 20px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 16px; } td,th { border: 1px solid \(color(theme.border)); padding: 6px 12px; } th { background-color: \(color(theme.secondaryBackground)); }
        """
    }

    private final class ImageAttributes: NSObject, XMLParserDelegate {
        var attributes: [String: String] = [:]
        var text = ""
        static func parse(_ xml: String) -> ImageAttributes {
            let delegate = ImageAttributes()
            let parser = XMLParser(data: Data(xml.utf8))
            parser.delegate = delegate
            parser.parse()
            return delegate
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        static func read(_ tag: String) -> [String: String] {
            let xml = tag.hasSuffix("/>") ? tag : String(tag.dropLast()) + "/>"
            return parse(xml).attributes
        }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { attributes = attributeDict }
    }
}
