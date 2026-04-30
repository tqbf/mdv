import AppKit
import CGrammars
import Foundation
import MarkdownUI
import SwiftTreeSitter
import SwiftUI

/// Syntax-highlights fenced code blocks with tree-sitter and produces a
/// styled `AttributedString` for SwiftUI `Text(_:)`. One `Language` and one
/// `Query` per supported language are loaded once and cached; per-render
/// state (a fresh `Parser`) is created on demand because tree-sitter's
/// parser is not safe to share across parses.
///
/// Render results are cached by `(language, themeID, code)` so theme
/// flips and find-bar redraws don't re-tokenize. Synchronous from the
/// caller's perspective so it slots into MarkdownUI's `CodeSyntaxHighlighter`
/// protocol — parse + query is well under a millisecond for typical
/// fenced blocks on Apple silicon.
final class CodeRenderer {
    static let shared = CodeRenderer()

    enum SupportedLanguage: String, CaseIterable, Hashable {
        case c, go, rust, bash, javascript, yaml, toml, python, ruby

        var queryResource: String { "\(rawValue)-highlights" }

        var languagePointer: OpaquePointer {
            // tree_sitter_<lang>() bridges as OpaquePointer? since the C
            // signature is `const TSLanguage *`; in practice these always
            // return a static, non-null pointer compiled into parser.c.
            switch self {
            case .c:          return tree_sitter_c()!
            case .go:         return tree_sitter_go()!
            case .rust:       return tree_sitter_rust()!
            case .bash:       return tree_sitter_bash()!
            case .javascript: return tree_sitter_javascript()!
            case .yaml:       return tree_sitter_yaml()!
            case .toml:       return tree_sitter_toml()!
            case .python:     return tree_sitter_python()!
            case .ruby:       return tree_sitter_ruby()!
            }
        }

        /// Resolve a fence info string (`go`, `js`, `Rust`, `sh`, …) to a
        /// supported language, or nil if we don't have a grammar for it.
        static func resolve(_ rawHint: String?) -> SupportedLanguage? {
            guard let raw = rawHint?.lowercased() else { return nil }
            let stripped = raw.split(separator: " ", maxSplits: 1).first.map(String.init) ?? raw
            if let direct = SupportedLanguage(rawValue: stripped) { return direct }
            switch stripped {
            case "js", "jsx", "javascriptreact", "node": return .javascript
            case "sh", "zsh", "shell":                    return .bash
            case "py", "python3":                         return .python
            case "rb":                                    return .ruby
            case "yml":                                   return .yaml
            case "rs":                                    return .rust
            case "golang":                                return .go
            case "h", "objective-c", "objc":              return .c
            default: return nil
            }
        }
    }

    private let lock = NSLock()
    private var languages: [SupportedLanguage: Language] = [:]
    private var queries: [SupportedLanguage: Query?] = [:]  // nil sentinel: tried + failed; don't retry

    private struct CacheKey: Hashable {
        let lang: SupportedLanguage?     // nil → unknown / no grammar
        let themeID: String
        let codeHash: Int
    }
    private var cache: [CacheKey: AttributedString] = [:]
    private let cacheLimit = 256

    /// Render a fenced code block. Always returns *something* — a plain
    /// monospaced AttributedString in theme `plain` color if no grammar
    /// matches, the query fails to load, or parsing errors out.
    func render(code: String, languageHint: String?, theme: MDVTheme) -> AttributedString {
        let lang = SupportedLanguage.resolve(languageHint)
        let palette = theme.resolvedCodePalette
        let fontSize = round(theme.baseFontSize * 0.85 * 100) / 100

        lock.lock()
        let key = CacheKey(lang: lang, themeID: theme.id, codeHash: code.hashValue)
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result: AttributedString
        if let lang {
            result = highlight(code: code, language: lang, palette: palette, fontSize: fontSize)
        } else {
            result = plainAttributedString(code: code, palette: palette, fontSize: fontSize)
        }

        lock.lock()
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = result
        lock.unlock()
        return result
    }

    // MARK: - Parser/Query plumbing

    private func tsLanguage(for lang: SupportedLanguage) -> Language {
        if let cached = languages[lang] { return cached }
        let l = Language(language: lang.languagePointer)
        languages[lang] = l
        return l
    }

    private func tsQuery(for lang: SupportedLanguage, language: Language) -> Query? {
        if let cached = queries[lang] { return cached }   // outer Optional means "tried"
        guard let url = Bundle.main.url(forResource: lang.queryResource, withExtension: "scm") else {
            queries[lang] = .some(nil)
            return nil
        }
        // Some grammars' nvim-treesitter-derived queries reference unknown
        // captures or predicates that SwiftTreeSitter rejects. We fall back
        // to plain monospaced rendering rather than crashing the viewer.
        let q = try? language.query(contentsOf: url)
        queries[lang] = .some(q)
        return q
    }

    // MARK: - Rendering

    private func plainAttributedString(code: String, palette: CodePalette, fontSize: CGFloat) -> AttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let nsAttr = NSMutableAttributedString(string: code)
        let full = NSRange(location: 0, length: nsAttr.length)
        nsAttr.addAttribute(.font, value: mono, range: full)
        nsAttr.addAttribute(.foregroundColor, value: NSColor(palette.plain), range: full)
        return AttributedString(nsAttr)
    }

    private func highlight(
        code: String,
        language: SupportedLanguage,
        palette: CodePalette,
        fontSize: CGFloat
    ) -> AttributedString {
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let plainColor = NSColor(palette.plain)

        let nsAttr = NSMutableAttributedString(string: code)
        let full = NSRange(location: 0, length: nsAttr.length)
        nsAttr.addAttribute(.font, value: mono, range: full)
        nsAttr.addAttribute(.foregroundColor, value: plainColor, range: full)

        let lang = tsLanguage(for: language)
        let parser = Parser()
        do { try parser.setLanguage(lang) } catch { return AttributedString(nsAttr) }
        guard let tree = parser.parse(code) else { return AttributedString(nsAttr) }
        guard let query = tsQuery(for: language, language: lang) else { return AttributedString(nsAttr) }

        let cursor = query.execute(in: tree)
        let highlights = cursor
            .resolve(with: Predicate.Context(string: code))
            .highlights()

        let italicMono = NSFontManager.shared.convert(mono, toHaveTrait: .italicFontMask)

        for namedRange in highlights {
            let byteStart = Int(namedRange.tsRange.bytes.lowerBound)
            let byteEnd = Int(namedRange.tsRange.bytes.upperBound)
            guard byteEnd >= byteStart,
                  let nsRange = byteRangeToNSRange(byteStart..<byteEnd, in: code) else {
                continue
            }
            let captureName = namedRange.nameComponents.first ?? ""
            let color = NSColor(palette.color(forCaptureNameComponents: namedRange.nameComponents))
            nsAttr.addAttribute(.foregroundColor, value: color, range: nsRange)
            if captureName == "comment" {
                nsAttr.addAttribute(.font, value: italicMono, range: nsRange)
            }
        }

        return AttributedString(nsAttr)
    }

    private func byteRangeToNSRange(_ byteRange: Range<Int>, in source: String) -> NSRange? {
        // SwiftTreeSitter's `Parser.parse(_:)` encodes the source as UTF-16LE
        // before handing it to tree-sitter, so the byte offsets returned in
        // `TSRange.bytes` are UTF-16 *byte* offsets, not UTF-8. Each UTF-16
        // code unit is two bytes (including surrogates which are also 2 each
        // and span two units), so dividing by 2 gives a UTF-16 code-unit
        // index — which is exactly what `NSRange` uses.
        let lo = byteRange.lowerBound / 2
        let hi = byteRange.upperBound / 2
        let utf16Length = source.utf16.count
        guard lo >= 0, hi <= utf16Length, lo <= hi else { return nil }
        return NSRange(location: lo, length: hi - lo)
    }
}

// MARK: - MarkdownUI adapter

/// Adapts `CodeRenderer.shared` to MarkdownUI's `CodeSyntaxHighlighter`.
/// MarkdownUI calls this synchronously while building the view tree;
/// `CodeRenderer` is fast enough to handle that without bouncing async.
struct MDVCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    let theme: MDVTheme

    func highlightCode(_ content: String, language: String?) -> Text {
        let attr = CodeRenderer.shared.render(code: content, languageHint: language, theme: theme)
        return Text(attr)
    }
}

extension CodeSyntaxHighlighter where Self == MDVCodeSyntaxHighlighter {
    static func mdv(theme: MDVTheme) -> Self {
        MDVCodeSyntaxHighlighter(theme: theme)
    }
}

// MARK: - Code block chrome (Phase 2: hover toolbar + language label)

/// Wraps a fenced code block in:
/// - A small always-visible language label (top-left, dimmed).
/// - A hover-revealed toolbar (top-right) with Copy and Wrap buttons.
/// - A right-click menu mirroring the toolbar, plus Copy Without Prompts
///   for shell blocks that contain `$ `/`# ` lines.
/// - The horizontal-scroll container that used to live directly inside
///   the MarkdownUI `.codeBlock` builder, with a wrap-toggle that swaps
///   it out for soft-wrapped layout.
struct CodeBlockChrome: View {
    let configuration: CodeBlockConfiguration
    let theme: MDVTheme

    @State private var hovering = false
    @State private var wrap = false
    @State private var copied = false
    /// Counter incremented every time we trigger a copy flash. Used to
    /// invalidate stale reset callbacks: only the most-recent dispatch
    /// (matching the current generation) actually resets `copied`. Avoids
    /// the structured-concurrency / @State / struct-self mismatch we hit
    /// trying to do this with `Task<Void, Never>?`.
    @State private var copyGeneration: Int = 0

    private var palette: CodePalette { theme.resolvedCodePalette }

    private var displayLanguage: String {
        guard let raw = configuration.language?.trimmingCharacters(in: .whitespaces).lowercased(),
              !raw.isEmpty else { return "" }
        // Some fences carry extra info ("python title=foo.py") — keep just
        // the leading word for the label.
        return raw.split(separator: " ").first.map(String.init) ?? raw
    }

    private var isShellLanguage: Bool {
        let shells: Set<String> = ["bash", "sh", "zsh", "fish", "shell", "console"]
        return shells.contains(displayLanguage)
    }

    /// Heuristic: ≥ 50 % of non-empty lines start with `$ ` or `# `.
    /// Cheap to compute on every render — typical blocks are small.
    private var hasShellPrompts: Bool {
        guard isShellLanguage else { return false }
        let lines = configuration.content
            .split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return false }
        let prompted = lines.filter { $0.hasPrefix("$ ") || $0.hasPrefix("# ") }.count
        return prompted * 2 >= lines.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chromeRow
            codeContent
        }
        .background(palette.background ?? theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .contextMenu { contextMenuItems }
    }

    // MARK: Chrome row

    private var chromeRow: some View {
        HStack(spacing: 0) {
            Text(displayLanguage)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundColor(theme.tertiaryText)
                .opacity(displayLanguage.isEmpty ? 0 : 0.85)
                .padding(.leading, 14)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                iconButton(
                    systemName: wrap ? "text.alignleft" : "text.append",
                    tinted: wrap,
                    help: wrap ? "Disable wrap" : "Wrap long lines"
                ) { wrap.toggle() }

                iconButton(
                    systemName: copied ? "checkmark" : "doc.on.doc",
                    tinted: copied,
                    help: copied ? "Copied" : "Copy code"
                ) { copy() }
            }
            .padding(.trailing, 6)
            .opacity(hovering ? 1 : 0)
            // Always reserve the toolbar's space so the label doesn't
            // jitter when hover toggles. The opacity transition stays
            // smooth without a layout shift.
        }
        .frame(height: 26)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.easeInOut(duration: 0.18), value: copied)
        .animation(.easeInOut(duration: 0.18), value: wrap)
    }

    // MARK: Code content

    @ViewBuilder
    private var codeContent: some View {
        if wrap {
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.225))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.225))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
            }
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy Code") { copy() }
        Button(wrap ? "Disable Wrap" : "Wrap Long Lines") { wrap.toggle() }
        if hasShellPrompts {
            Button("Copy Without Prompts") { copyWithoutPrompts() }
        }
    }

    // MARK: Helpers

    private func iconButton(
        systemName: String,
        tinted: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tinted ? theme.accent : theme.secondaryText)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(configuration.content, forType: .string)
        flashCopied()
    }

    private func copyWithoutPrompts() {
        let stripped = configuration.content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                if line.hasPrefix("$ ") { return String(line.dropFirst(2)) }
                if line.hasPrefix("# ") { return String(line.dropFirst(2)) }
                return String(line)
            }
            .joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(stripped, forType: .string)
        flashCopied()
    }

    private func flashCopied() {
        copyGeneration &+= 1
        let myGen = copyGeneration
        copied = true
        // DispatchQueue beats `Task { @MainActor in ... }` here — the
        // structured-concurrency variant works, but a stale generation
        // gives us the same coalescing-on-rapid-clicks behavior with
        // less ceremony.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if myGen == copyGeneration { copied = false }
        }
    }
}

// MARK: - CodePalette capture mapping

extension CodePalette {
    /// Walk the dotted capture name from most-specific to least-specific
    /// (`function.method.builtin` → `function.method` → `function`),
    /// returning the first slot that maps. Anything unmapped → `plain`.
    func color(forCaptureNameComponents components: [String]) -> Color {
        var idx = components.count
        while idx > 0 {
            let prefix = components[0..<idx].joined(separator: ".")
            if let c = colorForCapture(prefix) { return c }
            idx -= 1
        }
        return plain
    }

    fileprivate func colorForCapture(_ name: String) -> Color? {
        switch name {
        case "keyword",
             "keyword.control", "keyword.function", "keyword.operator",
             "keyword.return", "keyword.import", "keyword.export",
             "keyword.coroutine", "keyword.repeat", "keyword.conditional",
             "keyword.exception", "keyword.directive", "keyword.modifier",
             "keyword.storage", "keyword.type",
             "include", "conditional", "repeat", "exception":
            return keyword
        case "string",
             "string.special", "string.special.url", "string.regex",
             "string.escape", "string.documentation",
             "character", "character.special":
            return string
        case "number", "number.float", "float":
            return number
        case "comment", "comment.line", "comment.block",
             "comment.documentation":
            return comment
        case "type", "type.builtin", "type.definition", "type.qualifier",
             "storage.type", "storageclass", "class":
            return type
        case "function", "function.call", "function.method",
             "function.method.call", "function.macro", "function.builtin",
             "method", "constructor":
            return function
        case "attribute", "tag", "tag.attribute", "annotation",
             "decorator", "label":
            return attribute
        case "variable", "variable.parameter", "variable.builtin",
             "variable.member", "variable.other",
             "parameter", "field", "property":
            return variable
        case "constant", "constant.builtin", "constant.macro",
             "boolean":
            return constant
        case "operator", "punctuation.special", "punctuation.delimiter":
            return operatorColor
        default:
            return nil
        }
    }
}
