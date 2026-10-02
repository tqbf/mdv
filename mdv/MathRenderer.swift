@preconcurrency import AppKit
import MarkdownUI
import SwiftMath
import SwiftUI

// LaTeX math: `$…$` inline and `$$…$$` display.
//
// MarkdownUI (cmark-gfm underneath) has no math extension, so we don't try to
// teach it one. Instead, before a block reaches `Markdown(...)`, every math
// span is rewritten into an image reference —
//
//     ![](mdv-math://inline/<base64url latex>?s=<pt>&c=<rrggbbaa>)
//
// — and our image providers (`MathInlineImageProvider` for spans inside
// text, `MathDisplayView` via `LocalImageProvider` for a paragraph that is
// nothing but a `$$` block) recognise that scheme and typeset the LaTeX with
// SwiftMath. Size and colour ride along in the URL so the provider is
// stateless and MarkdownUI's `task(id: inlines)` re-renders on theme change.
//
// Known limitation: SwiftUI places an inline `Text(Image)` with its bottom
// on the baseline, and MarkdownUI gives us no hook to apply a baseline
// offset, so inline math with descenders (subscripts, fractions) sits a few
// points high. Display math is unaffected.

/// One math span, as encoded in an `mdv-math://` URL.
struct MathSpec: Hashable {
    static let scheme = "mdv-math"

    let latex: String
    let display: Bool
    let fontSize: CGFloat
    /// sRGB, packed 0xRRGGBBAA.
    let colorRGBA: UInt32

    var color: NSColor {
        NSColor(
            srgbRed: CGFloat((colorRGBA >> 24) & 0xFF) / 255,
            green: CGFloat((colorRGBA >> 16) & 0xFF) / 255,
            blue: CGFloat((colorRGBA >> 8) & 0xFF) / 255,
            alpha: CGFloat(colorRGBA & 0xFF) / 255
        )
    }

    var url: String {
        let payload = Data(latex.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let size = String(format: "%.1f", fontSize)
        let color = String(format: "%08X", colorRGBA)
        return "\(Self.scheme)://\(display ? "display" : "inline")/\(payload)?s=\(size)&c=\(color)"
    }

    init(latex: String, display: Bool, fontSize: CGFloat, colorRGBA: UInt32) {
        self.latex = latex
        self.display = display
        self.fontSize = fontSize
        self.colorRGBA = colorRGBA
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme,
              let host = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var payload = String(url.path.dropFirst())   // strip leading "/"
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let latex = String(data: data, encoding: .utf8) else { return nil }
        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { _, last in last }
        )
        guard let size = query["s"].flatMap(Double.init),
              let color = query["c"].flatMap({ UInt32($0, radix: 16) }) else { return nil }
        self.latex = latex
        self.display = host == "display"
        self.fontSize = CGFloat(size)
        self.colorRGBA = color
    }
}

// MARK: - Source rewriting

enum MathMarkdown {
    /// Replaces `$…$` / `$$…$$` spans in one markdown block with
    /// `mdv-math://` image references. Fenced code blocks and inline code
    /// spans are left alone; `\$` stays a literal dollar.
    ///
    /// Delimiter rules follow Pandoc's `tex_math_dollars`: an opening `$`
    /// must be followed by non-whitespace, a closing `$` must be preceded by
    /// non-whitespace and not followed by a digit, and a span can't contain
    /// a bare `$`. That keeps "$5 and $10" prose intact.
    /// - Parameters:
    ///   - fontSize: body size in points; math inside an ATX heading is
    ///     scaled by `headingSizeEms[level - 1]` so `# The $\pi$ estimator`
    ///     gets heading-sized π.
    static func rewrite(
        _ block: String,
        fontSize: CGFloat,
        headingSizeEms: [CGFloat] = [],
        color: NSColor
    ) -> String {
        guard block.contains("$") else { return block }
        let trimmed = block.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { return block }

        let rgba = Self.rgba(color)
        let chars = Array(block)
        let n = chars.count
        var out = ""
        out.reserveCapacity(block.count)
        var i = 0
        var codeRun = 0   // length of the open inline-code backtick run, 0 outside

        // Font scale for the line a span starts on: heading em or 1.
        let lineScales = headingLineScales(chars, headingSizeEms)
        var lineStarts = [0]
        for (k, c) in chars.enumerated() where c == "\n" { lineStarts.append(k + 1) }
        func scale(at index: Int) -> CGFloat {
            var lo = 0, hi = lineStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= index { lo = mid } else { hi = mid - 1 }
            }
            return lineScales[lo]
        }

        func spec(_ latex: String, display: Bool, at index: Int) -> String {
            let s = MathSpec(latex: latex, display: display, fontSize: fontSize * scale(at: index), colorRGBA: rgba)
            return "![](\(s.url))"
        }

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
            if c == "\\", i + 1 < n {
                out.append(c); out.append(chars[i + 1]); i += 2; continue
            }
            if c != "$" {
                out.append(c); i += 1; continue
            }

            // `$$…$$`
            if i + 1 < n, chars[i + 1] == "$" {
                if let close = findDisplayClose(chars, from: i + 2) {
                    let latex = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if latex.isEmpty {
                        out.append("$$"); i += 2; continue
                    }
                    let after = close + 2
                    if isLineStart(out), isLineEnd(chars, at: after) {
                        // Own paragraph, so MarkdownUI's block-image path picks
                        // it up and it renders centred, not inline in a sentence.
                        // Keep the line's indentation (list continuation).
                        let lineStart = out.lastIndex(of: "\n").map { out.index(after: $0) } ?? out.startIndex
                        let indent = String(out[lineStart...])
                        var head = String(out[..<lineStart])
                        if !head.isEmpty {
                            while !head.hasSuffix("\n\n") { head.append("\n") }
                        }
                        out = head + indent + spec(latex, display: true, at: i)
                        i = after
                        while i < n, chars[i] == " " || chars[i] == "\t" { i += 1 }
                        if i < n, chars[i] == "\n" { i += 1 }
                        if i < n { out.append("\n\n") }
                    } else {
                        out.append(spec(latex, display: true, at: i))
                        i = after
                    }
                    continue
                }
                out.append("$$"); i += 2; continue
            }

            // `$…$`
            if let close = findInlineClose(chars, from: i + 1) {
                let latex = String(chars[(i + 1)..<close])
                out.append(spec(latex, display: false, at: i))
                i = close + 1
                continue
            }
            out.append("$"); i += 1
        }
        return out
    }

    /// Per-line font scale: the heading em for `#`–`######` lines (up to
    /// three leading spaces, as CommonMark allows), 1 for everything else.
    private static func headingLineScales(_ chars: [Character], _ ems: [CGFloat]) -> [CGFloat] {
        var scales: [CGFloat] = []
        var lineStart = 0
        for k in 0...chars.count where k == chars.count || chars[k] == "\n" {
            var j = lineStart
            var spaces = 0
            while j < k, chars[j] == " ", spaces < 3 { j += 1; spaces += 1 }
            var hashes = 0
            while j < k, chars[j] == "#", hashes <= 6 { j += 1; hashes += 1 }
            let isHeading = hashes >= 1 && hashes <= 6 && (j == k || chars[j] == " " || chars[j] == "\t")
            scales.append(isHeading && hashes <= ems.count ? ems[hashes - 1] : 1)
            lineStart = k + 1
        }
        return scales
    }

    private static func findDisplayClose(_ chars: [Character], from start: Int) -> Int? {
        var j = start
        while j + 1 < chars.count {
            if chars[j] == "\\" { j += 2; continue }
            if chars[j] == "`" { return nil }
            if chars[j] == "$", chars[j + 1] == "$" { return j }
            j += 1
        }
        return nil
    }

    private static func findInlineClose(_ chars: [Character], from start: Int) -> Int? {
        guard start < chars.count, !chars[start].isWhitespace, chars[start] != "$" else { return nil }
        var j = start
        while j < chars.count {
            let c = chars[j]
            if c == "\\" { j += 2; continue }
            if c == "`" { return nil }   // ran into a code span — not math
            if c == "$" {
                let prevOK = !chars[j - 1].isWhitespace
                let nextOK = j + 1 >= chars.count || !chars[j + 1].isNumber
                return (prevOK && nextOK && j > start) ? j : nil
            }
            j += 1
        }
        return nil
    }

    /// True when everything emitted since the last newline is whitespace.
    private static func isLineStart(_ out: String) -> Bool {
        for c in out.reversed() {
            if c == "\n" { return true }
            if c != " " && c != "\t" { return false }
        }
        return true
    }

    private static func isLineEnd(_ chars: [Character], at index: Int) -> Bool {
        var j = index
        while j < chars.count {
            if chars[j] == "\n" { return true }
            if chars[j] != " " && chars[j] != "\t" { return false }
            j += 1
        }
        return true
    }

    private static func rgba(_ color: NSColor) -> UInt32 {
        let c = color.usingColorSpace(.sRGB) ?? .black
        func byte(_ v: CGFloat) -> UInt32 { UInt32((max(0, min(1, v)) * 255).rounded()) }
        return byte(c.redComponent) << 24 | byte(c.greenComponent) << 16 | byte(c.blueComponent) << 8 | byte(c.alphaComponent)
    }
}

// MARK: - Plain-text rendering (TOC, bookmark titles)

extension MathMarkdown {
    /// Replaces math spans with a readable Unicode approximation, for places
    /// that show heading text as a plain string (the TOC sidebar, bookmark
    /// names): `$\pi$` → π, `$x^2 \le y_1$` → x² ≤ y₁, `$\frac{a}{b}$` → a/b.
    /// Commands without a mapping keep their name minus the backslash.
    static func plainText(_ s: String) -> String {
        guard s.contains("$") else { return s }
        let chars = Array(s)
        var out = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count {
                out.append(chars[i + 1]); i += 2; continue
            }
            if c == "$" {
                // Same delimiter rules as `rewrite`, so "$5 and $x$" agrees.
                if i + 1 < chars.count, chars[i + 1] == "$", let close = findDisplayClose(chars, from: i + 2) {
                    out += latexToUnicode(String(chars[(i + 2)..<close]))
                    i = close + 2
                    continue
                }
                if let close = findInlineClose(chars, from: i + 1) {
                    out += latexToUnicode(String(chars[(i + 1)..<close]))
                    i = close + 1
                    continue
                }
            }
            out.append(c); i += 1
        }
        return out
    }

    /// Unicode approximation of one LaTeX expression (no delimiters).
    static func latexToUnicode(_ latex: String) -> String {
        var s = latex
        // \frac{a}{b} → a/b, \sqrt{x} → √x, wrappers → contents
        s = s.replacingOccurrences(of: #"\\frac\{([^{}]*)\}\{([^{}]*)\}"#, with: "$1/$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\sqrt\{([^{}]*)\}"#, with: "√$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\\(?:text|mathrm|mathbf|mathit|mathcal|mathbb|operatorname|boldsymbol|bm|hat|vec|bar|tilde)\{([^{}]*)\}"#, with: "$1", options: .regularExpression)

        let chars = Array(s)
        var result = ""
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                var name = ""
                var j = i + 1
                while j < chars.count, chars[j].isLetter { name.append(chars[j]); j += 1 }
                if name.isEmpty, j < chars.count { name = String(chars[j]); j += 1 }   // \, \; \{ …
                result += symbolTable[name] ?? name
                i = j
                continue
            }
            if c == "^" || c == "_" {
                // Script: `^2`, `_i`, `^{10}`, `_{n+1}` → Unicode if every
                // character has a form, else keep the `^`/`_` verbatim.
                let table = c == "^" ? superscripts : subscripts
                var body = ""
                var j = i + 1
                if j < chars.count, chars[j] == "{" {
                    j += 1
                    while j < chars.count, chars[j] != "}" { body.append(chars[j]); j += 1 }
                    j = min(j + 1, chars.count)
                } else if j < chars.count {
                    body = String(chars[j]); j += 1
                }
                let mapped = body.map { table[$0].map(String.init) }
                if !body.isEmpty, mapped.allSatisfy({ $0 != nil }) {
                    result += mapped.compactMap { $0 }.joined()
                } else {
                    result.append(c); result += body
                }
                i = j
                continue
            }
            if c == "{" || c == "}" { i += 1; continue }
            result.append(c); i += 1
        }
        return result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "n": "ⁿ", "i": "ⁱ",
    ]
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "i": "ᵢ", "j": "ⱼ", "n": "ₙ", "k": "ₖ", "x": "ₓ",
    ]
    private static let symbolTable: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ",
        "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
        "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "approx": "≈",
        "sim": "∼", "simeq": "≃", "equiv": "≡", "propto": "∝", "ll": "≪", "gg": "≫",
        "gtrsim": "≳", "lesssim": "≲", "times": "×", "cdot": "·", "pm": "±", "mp": "∓",
        "div": "÷", "infty": "∞", "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏",
        "int": "∫", "sqrt": "√", "to": "→", "rightarrow": "→", "leftarrow": "←",
        "Rightarrow": "⇒", "Leftrightarrow": "⇔", "iff": "⇔", "implies": "⇒", "mapsto": "↦",
        "in": "∈", "notin": "∉", "subset": "⊂", "subseteq": "⊆", "cup": "∪", "cap": "∩",
        "forall": "∀", "exists": "∃", "neg": "¬", "land": "∧", "lor": "∨", "emptyset": "∅",
        "ldots": "…", "cdots": "⋯", "dots": "…", "hbar": "ℏ", "ell": "ℓ", "degree": "°",
        "quad": " ", "qquad": "  ", ",": " ", ";": " ", "!": "",
        "langle": "⟨", "rangle": "⟩", "lceil": "⌈", "rceil": "⌉", "lfloor": "⌊", "rfloor": "⌋",
        "log": "log", "ln": "ln", "sin": "sin", "cos": "cos", "tan": "tan", "exp": "exp",
        "lim": "lim", "max": "max", "min": "min",
    ]
}

// MARK: - Typesetting + cache

final class MathRendered {
    let image: NSImage
    let ascent: CGFloat
    let descent: CGFloat
    /// Parse error message, if SwiftMath rejected the LaTeX. `image` then
    /// holds a plain-text rendering of the source so the span isn't lost.
    let error: String?

    init(image: NSImage, ascent: CGFloat, descent: CGFloat, error: String?) {
        self.image = image
        self.ascent = ascent
        self.descent = descent
        self.error = error
    }
}

final class MathImageCache {
    static let shared = MathImageCache()

    private let entries: NSCache<NSString, MathRendered> = {
        let cache = NSCache<NSString, MathRendered>()
        cache.countLimit = 2048
        return cache
    }()

    func cached(for spec: MathSpec) -> MathRendered? {
        entries.object(forKey: spec.url as NSString)
    }

    func rendered(for spec: MathSpec) async -> MathRendered {
        if let hit = cached(for: spec) { return hit }
        let result = await Task.detached(priority: .userInitiated) {
            SendableRendered(value: Self.typeset(spec))
        }.value.value
        entries.setObject(result, forKey: spec.url as NSString)
        return result
    }

    private static func typeset(_ spec: MathSpec) -> MathRendered {
        MathSymbols.registerOnce()
        var math = MathImage(
            latex: MathSymbols.preprocess(spec.latex),
            fontSize: spec.fontSize,
            textColor: spec.color,
            labelMode: spec.display ? .display : .text,
            textAlignment: .left
        )
        let (error, image, layout) = math.asImage()
        if error == nil, let image, let layout {
            // SwiftMath hands back a drawing-handler NSImage. Bake it to a
            // bitmap: SwiftUI treats handler-backed images inside `Text` as
            // dynamic and keeps re-resolving the paragraph, which showed up as
            // a steady 10–20 % CPU on any page with inline math.
            let baked = rasterized(image, scale: NSScreen.main?.backingScaleFactor ?? 2) ?? image
            return MathRendered(image: baked, ascent: layout.ascent, descent: layout.descent, error: nil)
        }
        let message = error?.localizedDescription ?? "LaTeX could not be rendered"
        return MathRendered(image: fallbackImage(for: spec), ascent: spec.fontSize, descent: 0, error: message)
    }

    private static func rasterized(_ image: NSImage, scale: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0,
              let ctx = CGContext(
                data: nil,
                width: Int(ceil(size.width * scale)), height: Int(ceil(size.height * scale)),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: size)
    }

    /// The raw source in monospace, so a span SwiftMath can't parse still
    /// reads as what the author wrote instead of vanishing.
    private static func fallbackImage(for spec: MathSpec) -> NSImage {
        let delimiter = spec.display ? "$$" : "$"
        let text = NSAttributedString(
            string: delimiter + spec.latex + delimiter,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: spec.fontSize * 0.9, weight: .regular),
                .foregroundColor: spec.color.withAlphaComponent(0.8),
            ]
        )
        let size = text.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { rect in
            text.draw(at: .zero)
            return true
        }
        return rasterized(image, scale: NSScreen.main?.backingScaleFactor ?? 2) ?? image
    }
}

// MARK: - Filling SwiftMath's LaTeX gaps

/// SwiftMath covers core LaTeX/AMS math but not all of it. Two kinds of
/// gap are patched here: plain symbols are registered with the atom
/// factory (the Latin Modern Math font has the glyphs), and a few
/// commands that need syntax the parser lacks are rewritten to
/// equivalents it does have. Anything else still shows as source.
enum MathSymbols {
    private static let registration: Void = {
        func rel(_ v: String) -> MTMathAtom { MTMathAtom(type: .relation, value: v) }
        func ord(_ v: String) -> MTMathAtom { MTMathAtom(type: .ordinary, value: v) }
        func bin(_ v: String) -> MTMathAtom { MTMathAtom(type: .binaryOperator, value: v) }
        func op(_ v: String) -> MTMathAtom { MTMathAtomFactory.operatorWithName(v, limits: true) }

        let symbols: [String: MTMathAtom] = [
            // relations (amssymb)
            "gtrsim": rel("\u{2273}"), "lesssim": rel("\u{2272}"),
            "gtrapprox": rel("\u{2A86}"), "lessapprox": rel("\u{2A85}"),
            "leqslant": rel("\u{2A7D}"), "geqslant": rel("\u{2A7E}"),
            "lll": rel("\u{22D8}"), "ggg": rel("\u{22D9}"),
            "nless": rel("\u{226E}"), "ngtr": rel("\u{226F}"),
            "nleq": rel("\u{2270}"), "ngeq": rel("\u{2271}"),
            "doteq": rel("\u{2250}"), "triangleq": rel("\u{225C}"),
            "therefore": rel("\u{2234}"), "because": rel("\u{2235}"),
            "implies": rel("\u{27F9}"), "impliedby": rel("\u{27F8}"),
            "models": rel("\u{22A8}"), "vDash": rel("\u{22A8}"), "Vdash": rel("\u{22A9}"),
            "nparallel": rel("\u{2226}"), "nmid": rel("\u{2224}"),
            "subsetneq": rel("\u{228A}"), "supsetneq": rel("\u{228B}"),
            "nsubseteq": rel("\u{2288}"), "nsupseteq": rel("\u{2289}"),
            "sqsubseteq": rel("\u{2291}"), "sqsupseteq": rel("\u{2292}"),
            "precsim": rel("\u{227E}"), "succsim": rel("\u{227F}"),
            "hookrightarrow": rel("\u{21AA}"), "hookleftarrow": rel("\u{21A9}"),
            "rightharpoonup": rel("\u{21C0}"), "leftharpoonup": rel("\u{21BC}"),
            "rightleftharpoons": rel("\u{21CC}"), "leftrightharpoons": rel("\u{21CB}"),
            "nearrow": rel("\u{2197}"), "searrow": rel("\u{2198}"),
            "swarrow": rel("\u{2199}"), "nwarrow": rel("\u{2196}"),
            "longmapsto": rel("\u{27FC}"), "twoheadrightarrow": rel("\u{21A0}"),
            "rightsquigarrow": rel("\u{21DD}"), "leadsto": rel("\u{21DD}"),
            "rightrightarrows": rel("\u{21C9}"), "leftleftarrows": rel("\u{21C7}"),
            // ordinary symbols
            "dots": ord("\u{2026}"), "dotsc": ord("\u{2026}"), "dotsb": ord("\u{22EF}"),
            "varnothing": ord("\u{2205}"), "hslash": ord("\u{210F}"), "mho": ord("\u{2127}"),
            "Box": ord("\u{25A1}"), "square": ord("\u{25A1}"), "blacksquare": ord("\u{25A0}"),
            "bigstar": ord("\u{2605}"), "checkmark": ord("\u{2713}"),
            "ddagger": ord("\u{2021}"), "S": ord("\u{00A7}"), "P": ord("\u{00B6}"),
            "pounds": ord("\u{00A3}"), "copyright": ord("\u{00A9}"), "degree": ord("\u{00B0}"),
            "beth": ord("\u{2136}"), "gimel": ord("\u{2137}"), "wp": ord("\u{2118}"),
            "nexists": ord("\u{2204}"), "complement": ord("\u{2201}"),
            "#": ord("#"), "_": ord("_"),   // `\&` can't be done: `&` is the parser's column separator
            // large operators
            "iint": op("\u{222C}"), "iiint": op("\u{222D}"), "oiint": op("\u{222F}"),
            "bigsqcup": op("\u{2A06}"), "bigodot": op("\u{2A00}"),
            "bigotimes": op("\u{2A02}"), "biguplus": op("\u{2A04}"),
            // binary operators
            "intercal": bin("\u{22BA}"), "leftthreetimes": bin("\u{22CB}"),
            "rightthreetimes": bin("\u{22CC}"), "divideontimes": bin("\u{22C7}"),
        ]
        for (name, atom) in symbols where MTMathAtomFactory.atom(forLatexSymbol: name) == nil {
            MTMathAtomFactory.add(latexSymbol: name, value: atom)
        }
    }()

    static func registerOnce() { _ = registration }

    /// Command-level rewrites for syntax SwiftMath's parser doesn't accept.
    static func preprocess(_ latex: String) -> String {
        guard latex.contains("\\") else { return latex }
        var s = latex
        for (pattern, replacement) in rewrites {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return s
    }

    private static let rewrites: [(String, String)] = [
        (#"\\operatorname\*?\s*\{"#, #"\\mathrm{"#),
        (#"\\(?:dfrac|tfrac)\b"#, #"\\frac"#),
        (#"\\boldsymbol\b"#, #"\\bm"#),
        (#"\\bmod\b"#, #"\\;\\mathrm{mod}\\;"#),
        (#"\\pmod\s*\{([^{}]*)\}"#, #"\\;(\\mathrm{mod}\\;$1)"#),
        (#"\\not\s*="#, #"\\neq"#),
        // \big( \Bigl[ \biggr\} \Bigg| … — size hints the parser doesn't know;
        // drop them and let the delimiter render at normal size.
        (#"\\[bB]igg?[lrm]?(?=\s*(?:[()\[\]|/]|\\[{}|]|\\[a-zA-Z]+))"#, ""),
        (#"\\coloneqq\b"#, ":="),
        (#"\\begin\{(align|equation|gather|multline)\*?\}"#, #"\\begin{$1}"#),
        (#"\\end\{(align|equation|gather|multline)\*?\}"#, #"\\end{$1}"#),
        (#"\\begin\{align\}"#, #"\\begin{aligned}"#),
        (#"\\end\{align\}"#, #"\\end{aligned}"#),
        (#"\\begin\{multline\}"#, #"\\begin{gather}"#),
        (#"\\end\{multline\}"#, #"\\end{gather}"#),
        (#"\\(?:begin|end)\{equation\}"#, ""),
    ]
}

private struct SendableRendered: @unchecked Sendable {
    let value: MathRendered
}

// MARK: - MarkdownUI providers

/// Inline images: math URLs are typeset here, everything else goes to
/// MarkdownUI's default loader as before.
struct MathInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        guard let spec = MathSpec(url: url) else {
            return try await DefaultInlineImageProvider().image(with: url, label: label)
        }
        let rendered = await MathImageCache.shared.rendered(for: spec)
        return Image(nsImage: rendered.image)
    }
}

/// A `$$` block on its own paragraph: centred, capped at its natural width,
/// scaled down to fit narrow columns. Right-click copies the LaTeX.
///
/// Also reached when an inline `$…$` is the *entire* content of a list item
/// or table cell — MarkdownUI routes image-only paragraphs here — in which
/// case it stays text-sized and leading-aligned like the prose around it.
struct MathDisplayView: View {
    let spec: MathSpec
    @State private var rendered: MathRendered?

    init(spec: MathSpec) {
        self.spec = spec
        _rendered = State(initialValue: MathImageCache.shared.cached(for: spec))
    }

    var body: some View {
        Group {
            if let rendered {
                if rendered.error == nil {
                    let size = rendered.image.size
                    Image(nsImage: rendered.image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: size.width > 0 ? size.width : nil)
                        .accessibilityLabel(spec.latex)
                } else {
                    fallback(rendered)
                }
            } else {
                Color.clear.frame(height: spec.fontSize * 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: spec.display ? .center : .leading)
        .padding(.vertical, spec.display ? 4 : 0)
        .contextMenu {
            Button("Copy LaTeX") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(spec.latex, forType: .string)
            }
        }
        .task(id: spec) {
            if rendered == nil {
                rendered = await MathImageCache.shared.rendered(for: spec)
            }
        }
    }

    private func fallback(_ rendered: MathRendered) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rendered.error ?? "LaTeX could not be rendered")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: spec.color).opacity(0.7))
            Text(spec.latex)
                .font(.system(size: max(spec.fontSize * 0.85, 11), design: .monospaced))
                .foregroundStyle(Color(nsColor: spec.color))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
