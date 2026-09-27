import AppKit
import MarkdownUI
import SwiftUI

// Raw `<img>` tags, which cmark renders as literal text.
//
// GitHub sanitises HTML and renders `<img src=… width=…>` as an image, so
// READMEs use them for things Markdown can't express — a sized header image,
// most often. `MarkdownUI` has no HTML renderer, so the same trick as math
// applies: before a block reaches `Markdown(...)`, each tag becomes an image
// reference our providers recognise —
//
//     ![](mdv-img://<base64url src>?a=<base64url alt>&w=320&h=200)
//
// — and they draw it with the size the tag asked for. Nothing else about the
// HTML is interpreted; other tags keep printing as text.

/// One `<img>` tag, as encoded in an `mdv-img://` URL.
struct HTMLImageSpec: Hashable {
    static let scheme = "mdv-img"

    /// The `src`, as written — resolved against the document by the provider.
    let src: String
    let alt: String
    /// `width` / `height` attributes, in points. Either may be nil, in which
    /// case the image's own size decides.
    let width: CGFloat?
    let height: CGFloat?

    var url: String {
        var query: [String] = []
        if !alt.isEmpty { query.append("a=\(Self.encode(alt))") }
        if let width { query.append("w=\(Self.number(width))") }
        if let height { query.append("h=\(Self.number(height))") }
        let suffix = query.isEmpty ? "" : "?\(query.joined(separator: "&"))"
        return "\(Self.scheme)://\(Self.encode(src))\(suffix)"
    }

    init(src: String, alt: String, width: CGFloat?, height: CGFloat?) {
        self.src = src
        self.alt = alt
        self.width = width
        self.height = height
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let src = Self.decode(url.host ?? "") ?? Self.decode(String(url.path.dropFirst()))
        else { return nil }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last }
        )
        self.src = src
        self.alt = query["a"].flatMap(Self.decode) ?? ""
        self.width = query["w"].flatMap(Double.init).map { CGFloat($0) }
        self.height = query["h"].flatMap(Double.init).map { CGFloat($0) }
    }

    private static func encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ payload: String) -> String? {
        var payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func number(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }
}

enum RawHTMLImages {
    /// Replaces `<img …>` tags in one markdown block with `mdv-img://` image
    /// references. Fenced blocks and inline code are left alone, so a document
    /// *about* HTML still shows its HTML.
    static func rewrite(_ block: String) -> String {
        guard block.contains("<img") else { return block }
        let trimmed = block.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return block }

        let chars = Array(block)
        let n = chars.count
        var out = ""
        out.reserveCapacity(block.count)
        var i = 0
        var codeRun = 0   // length of the open inline-code backtick run, 0 outside

        while i < n {
            let c = chars[i]

            if c == "`" {
                var run = 0
                while i < n, chars[i] == "`" { out.append("`"); run += 1; i += 1 }
                if codeRun == 0 { codeRun = run } else if run == codeRun { codeRun = 0 }
                continue
            }
            if codeRun > 0 {
                out.append(c); i += 1; continue
            }
            guard c == "<", i + 4 <= n, String(chars[i..<min(i + 4, n)]) == "<img" else {
                out.append(c); i += 1; continue
            }
            guard let close = chars[i...].firstIndex(of: ">") else {
                out.append(c); i += 1; continue
            }
            let tag = String(chars[i...close])
            if let spec = spec(fromTag: tag) {
                out.append("![](\(spec.url))")
            } else {
                out.append(tag)   // not something we understand: leave it be
            }
            i = close + 1
        }
        return out
    }

    /// `src`, `alt`, `width` and `height` off one tag, with or without quotes.
    private static func spec(fromTag tag: String) -> HTMLImageSpec? {
        func attribute(_ name: String) -> String? {
            for quote in ["\"", "'", ""] {
                let pattern = quote.isEmpty
                    ? "(?i)\\b\(name)\\s*=\\s*([^\\s>\"']+)"
                    : "(?i)\\b\(name)\\s*=\\s*\(quote)([^\(quote)]*)\(quote)"
                guard let range = tag.range(of: pattern, options: .regularExpression),
                      let value = tag[range].split(separator: "=", maxSplits: 1).last
                else { continue }
                return String(value).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
            return nil
        }
        func length(_ name: String) -> CGFloat? {
            guard let raw = attribute(name) else { return nil }
            let digits = raw.replacingOccurrences(of: "px", with: "", options: .caseInsensitive)
            guard let value = Double(digits), value > 0 else { return nil }
            return CGFloat(value)
        }
        guard let src = attribute("src"), !src.isEmpty else { return nil }
        return HTMLImageSpec(
            src: src,
            alt: attribute("alt") ?? "",
            width: length("width"),
            height: length("height")
        )
    }
}

/// An `<img>` tag's image: the file beside the document, drawn at the size the
/// tag asked for, falling back to the image's own size.
struct HTMLImageView: View {
    let spec: HTMLImageSpec
    /// Loaded by the caller: block images load from disk synchronously (print
    /// renders without any async work), the inline path loads its own.
    let image: NSImage?

    var body: some View {
        if let image {
            let size = spec.displaySize(natural: image.size)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(image.size.height > 0 ? image.size.width / image.size.height : 1, contentMode: .fit)
                // Caps, not fixed sizes: a picture larger than the column
                // shrinks to it, the way every other image in a document does.
                .frame(maxWidth: size.width, maxHeight: size.height)
                .accessibilityLabel(spec.alt.isEmpty ? spec.src : spec.alt)
        } else {
            Text(spec.alt.isEmpty ? "Missing image: \(spec.src)" : spec.alt)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

extension HTMLImageSpec {
    /// The size to draw a picture at: `width` wins, a lone `height` derives the
    /// width from the aspect, neither means the image's own size — all as caps,
    /// never stretching. Used by both the view and the print pipeline, so a
    /// picture occupies the same space either way.
    func displaySize(natural: CGSize) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return natural }
        let ratio = natural.width / natural.height
        if let width, let height {
            return CGSize(width: min(width, height * ratio), height: min(height, width / ratio))
        }
        if let width {
            let w = min(width, natural.width)
            return CGSize(width: w, height: w / ratio)
        }
        if let height {
            let h = min(height, natural.height)
            return CGSize(width: h * ratio, height: h)
        }
        return natural
    }

    /// The `src` resolved against the document, the same way `![…](…)` is.
    func resolvedURL(baseURL: URL?) -> URL {
        if let url = URL(string: src), url.scheme != nil { return url }
        guard let base = baseURL else { return URL(fileURLWithPath: src).standardizedFileURL }
        return URL(fileURLWithPath: src, relativeTo: base).standardizedFileURL
    }
}
