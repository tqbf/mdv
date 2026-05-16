@preconcurrency import AppKit
import BeautifulMermaid
import SwiftUI
import UniformTypeIdentifiers

enum MermaidRenderStyle: String, CaseIterable, Hashable, Identifiable {
    case document
    case light
    case dark
    case tokyoNight
    case catppuccin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .document: return "Document"
        case .light: return "Light"
        case .dark: return "Dark"
        case .tokyoNight: return "Tokyo Night"
        case .catppuccin: return "Catppuccin"
        }
    }

    func diagramTheme(for theme: MDVTheme) -> DiagramTheme {
        switch self {
        case .document:
            return theme.mermaidDiagramTheme
        case .light:
            return .zincLight
        case .dark:
            return .zincDark
        case .tokyoNight:
            return .tokyoNight
        case .catppuccin:
            return theme.isDark ? .catppuccinMocha : .catppuccinLatte
        }
    }
}

struct MermaidCodeBlockChrome: View {
    let content: String
    let displayLanguage: String
    let theme: MDVTheme
    let palette: CodePalette

    @State private var hovering = false
    @State private var showSource = false
    @State private var wrap = false
    // Style is a document-wide appearance choice, not a per-block preference:
    // pick a palette once and every diagram updates and persists across launches.
    @AppStorage("mdv.mermaid.style") private var style: MermaidRenderStyle = .document
    @State private var copied = false
    @State private var copyGeneration = 0

    // The style picker only drives BeautifulMermaid's palette; the WKWebView
    // fallback for gantt/pie/etc. honours just light/dark via mermaid.js's
    // own theme. Showing the menu for those diagrams would mislead users
    // into thinking it does something it can't.
    private var nativeRenderer: Bool { isBeautifulMermaidSupported(content) }

    var body: some View {
        if showSource {
            sourceChrome
        } else {
            diagramChrome
        }
    }

    // Diagram view: the diagram fills the box; the toolbar floats top-right
    // as a translucent capsule, like Preview/Quick Look. Hover-revealed.
    private var diagramChrome: some View {
        MDVMermaidDiagramView(source: content, theme: theme, style: style)
            .frame(maxWidth: .infinity)
            .background(palette.background ?? theme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topTrailing) { floatingToolbar }
            .onHover { hovering = $0 }
            .contextMenu { contextMenuItems }
    }

    // Source view: matches the normal CodeBlockChrome look — language label
    // top-left, hover-revealed toolbar top-right, syntax-highlighted content.
    private var sourceChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceChromeRow
            sourceContent
        }
        .background(palette.background ?? theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .contextMenu { contextMenuItems }
    }

    private var floatingToolbar: some View {
        HStack(spacing: 2) {
            if nativeRenderer { styleMenu }

            iconButton(
                systemName: "curlybraces",
                tinted: false,
                help: "Show Mermaid source"
            ) { showSource = true }

            if nativeRenderer {
                iconButton(
                    systemName: "square.and.arrow.down",
                    tinted: false,
                    help: "Export diagram as PNG"
                ) { MDVMermaidImage.exportPNG(source: content, theme: theme, style: style) }
            }

            iconButton(
                systemName: copied ? "checkmark" : "doc.on.doc",
                tinted: copied,
                help: copied ? "Copied" : "Copy code"
            ) { copy() }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(theme.secondaryText.opacity(0.18), lineWidth: 0.5)
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
        .opacity(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hovering)
        .animation(.easeInOut(duration: 0.18), value: copied)
    }

    private var sourceChromeRow: some View {
        HStack(spacing: 0) {
            Text(displayLanguage)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.tertiaryText)
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
                    systemName: "point.3.connected.trianglepath.dotted",
                    tinted: true,
                    help: "Show diagram"
                ) { showSource = false }

                iconButton(
                    systemName: copied ? "checkmark" : "doc.on.doc",
                    tinted: copied,
                    help: copied ? "Copied" : "Copy code"
                ) { copy() }
            }
            .padding(.trailing, 6)
            .opacity(hovering ? 1 : 0)
        }
        .frame(height: 26)
        .padding(.top, 4)
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .animation(.easeInOut(duration: 0.18), value: copied)
        .animation(.easeInOut(duration: 0.18), value: wrap)
    }

    @ViewBuilder
    private var sourceContent: some View {
        let body = Text(CodeRenderer.shared.render(code: content, languageHint: "mermaid", theme: theme))
            .fixedSize(horizontal: false, vertical: true)
            .relativeLineSpacing(.em(0.225))
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 14)

        if wrap {
            body.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                body
            }
        }
    }

    private var styleMenu: some View {
        Menu {
            stylePicker
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(style == .document ? theme.secondaryText : theme.accent)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
        .help("Change Mermaid diagram style")
    }

    private var stylePicker: some View {
        Picker("Diagram style", selection: $style) {
            ForEach(MermaidRenderStyle.allCases) { candidate in
                Text(candidate.displayName).tag(candidate)
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy Code") { copy() }
        Button(showSource ? "Show Diagram" : "Show Mermaid Source") {
            showSource.toggle()
        }
        if showSource {
            Button(wrap ? "Disable Wrap" : "Wrap Long Lines") { wrap.toggle() }
        } else {
            if nativeRenderer {
                Menu("Diagram Style") {
                    stylePicker
                }
                Button("Export Diagram as PNG") {
                    MDVMermaidImage.exportPNG(source: content, theme: theme, style: style)
                }
            }
        }
    }

    private func iconButton(
        systemName: String,
        tinted: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tinted ? theme.accent : theme.secondaryText)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        flashCopied()
    }

    private func flashCopied() {
        copyGeneration &+= 1
        let myGeneration = copyGeneration
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if myGeneration == copyGeneration { copied = false }
        }
    }
}

/// Returns the first line of `source` that is meaningful for diagram-type
/// dispatch — i.e. not blank, not a `%%` comment, not a `%%{ init: … }%%`
/// directive, and not inside a `--- … ---` frontmatter block. Lowercased.
///
/// Mermaid lets users put any combination of those preamble forms before
/// the actual diagram keyword (`gantt`, `flowchart LR`, …); naively
/// inspecting the first physical line therefore false-routes those
/// diagrams into the WKWebView path even when BeautifulMermaid could
/// render them natively.
private func firstMermaidDirectiveLine(in source: String) -> String {
    var inFrontmatter = false
    var inDirective = false

    for raw in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }

        if inFrontmatter {
            if line == "---" { inFrontmatter = false }
            continue
        }
        if inDirective {
            if line.contains("}%%") { inDirective = false }
            continue
        }

        if line == "---" { inFrontmatter = true; continue }
        if line.hasPrefix("%%{") {
            // Single-line `%%{ init: … }%%` is consumed here; only flip the
            // multi-line flag if the closer isn't on the same line.
            if !line.contains("}%%") { inDirective = true }
            continue
        }
        if line.hasPrefix("%%") { continue }

        return line.lowercased()
    }
    return ""
}

private func isBeautifulMermaidSupported(_ source: String) -> Bool {
    let first = firstMermaidDirectiveLine(in: source)
    if first.isEmpty { return false }

    // Match the keyword exactly, or with any whitespace separator (spaces,
    // tabs) before the diagram-specific arguments. Avoids the previous
    // `"graph "` literal, which missed `graph\tLR` and bare `graph` on
    // its own line, and avoids over-matching `graphfoo`.
    func matches(_ keyword: String) -> Bool {
        if first == keyword { return true }
        guard first.hasPrefix(keyword) else { return false }
        let next = first[first.index(first.startIndex, offsetBy: keyword.count)]
        return next.isWhitespace
    }

    // BeautifulMermaid covers exactly these six families. `statediagram`
    // matches both `stateDiagram` and `stateDiagram-v2`; same idea for
    // `xychart` covering `xychart-beta`. `flowchart-elk` is intentionally
    // *not* matched — ELK is a different layout backend that
    // BeautifulMermaid doesn't speak.
    if matches("flowchart") { return true }
    if matches("graph") { return true }
    if matches("sequencediagram") { return true }
    if matches("classdiagram") { return true }
    if matches("erdiagram") { return true }
    if first.hasPrefix("statediagram") { return true } // statediagram-v2
    if first.hasPrefix("xychart") { return true }      // xychart-beta
    return false
}

struct MDVMermaidDiagramView: View {
    let source: String
    let theme: MDVTheme
    let style: MermaidRenderStyle

    @State private var image: NSImage?
    @State private var failed = false
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1

    private var renderKey: MDVMermaidRenderKey {
        MDVMermaidRenderKey(source: source, theme: theme, style: style)
    }

    var body: some View {
        if isBeautifulMermaidSupported(source) {
            Group {
                if let image {
                    diagramBody(for: image)
                } else if failed {
                    MermaidFallbackView(source: source, theme: theme)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
            }
            .task(id: renderKey) {
                failed = false
                image = nil
                zoom = 1
                committedZoom = 1
                if let rendered = await MDVMermaidImageCache.shared.image(source: source, theme: theme, style: style, key: renderKey) {
                    if !Task.isCancelled { image = rendered }
                } else if !Task.isCancelled {
                    failed = true
                }
            }
        } else {
            MermaidWebViewContainer(source: source, theme: theme)
        }
    }

    @ViewBuilder
    private func diagramBody(for image: NSImage) -> some View {
        let aspect = image.size.width > 0 ? image.size.width / image.size.height : 1
        let baseImage = Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(aspect, contentMode: .fit)

        if zoom > 1.01 {
            // Zoomed: inner ScrollView for panning. Pin the container height
            // to the unzoomed fit height so the document doesn't reflow during pinch.
            GeometryReader { proxy in
                let fitWidth = max(proxy.size.width - 36, 1)
                let fitHeight = fitWidth / aspect
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    baseImage
                        .frame(width: fitWidth * zoom, height: fitHeight * zoom)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                }
            }
            .frame(height: 540)
            .gesture(mermaidZoomGesture)
            .accessibilityLabel("Mermaid diagram")
        } else {
            // Unzoomed: render inline at the container width × intrinsic aspect.
            // No inner ScrollView, so wheel events bubble up to the document scroll.
            baseImage
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .gesture(mermaidZoomGesture)
                .accessibilityLabel("Mermaid diagram")
        }
    }

    private var mermaidZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = clampedZoom(committedZoom * value)
            }
            .onEnded { value in
                committedZoom = clampedZoom(committedZoom * value)
                zoom = committedZoom
            }
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.5), 4)
    }
}

struct MDVMermaidRenderKey: Hashable {
    let sourceHash: Int
    let sourceLength: Int
    let themeID: String
    let style: MermaidRenderStyle
    let scale: CGFloat

    init(source: String, theme: MDVTheme, style: MermaidRenderStyle) {
        self.sourceHash = source.hashValue
        self.sourceLength = source.count
        self.themeID = theme.id
        self.style = style
        self.scale = NSScreen.main?.backingScaleFactor ?? 2
    }

    var cacheID: NSString {
        "\(themeID)|\(style.rawValue)|\(scale)|\(sourceLength)|\(sourceHash)" as NSString
    }
}

final class MDVMermaidImageCache {
    static let shared = MDVMermaidImageCache()

    private let entries: NSCache<NSString, MDVMermaidImageCacheEntry> = {
        let cache = NSCache<NSString, MDVMermaidImageCacheEntry>()
        cache.countLimit = 96
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()

    func image(source: String, theme: MDVTheme, style: MermaidRenderStyle, key: MDVMermaidRenderKey) async -> NSImage? {
        if let cached = entries.object(forKey: key.cacheID) { return cached.image }
        let rendered = await renderImage(source: source, theme: theme, style: style, scale: key.scale)
        let entry = MDVMermaidImageCacheEntry(image: rendered)
        entries.setObject(entry, forKey: key.cacheID, cost: max(rendered?.bitmapCost ?? 1, 1))
        return rendered
    }

    private func renderImage(source: String, theme: MDVTheme, style: MermaidRenderStyle, scale: CGFloat) async -> NSImage? {
        let diagramTheme = style.diagramTheme(for: theme)
        return await Task.detached(priority: .userInitiated) {
            guard let image = try? MermaidRenderer.renderImage(
                source: source,
                theme: diagramTheme,
                scale: scale
            ) else { return SendableMermaidImage(image: nil) }
            return SendableMermaidImage(image: image.flippedVertically())
        }.value.image
    }
}

final class MDVMermaidImageCacheEntry {
    let image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }
}

private struct SendableMermaidImage: @unchecked Sendable {
    let image: NSImage?
}

enum MDVMermaidImage {
    static func exportPNG(source: String, theme: MDVTheme, style: MermaidRenderStyle) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "mermaid-diagram.png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let key = MDVMermaidRenderKey(source: source, theme: theme, style: style)
        Task {
            guard let image = await MDVMermaidImageCache.shared.image(source: source, theme: theme, style: style, key: key),
                  let pngData = image.pngData else {
                NSSound.beep()
                return
            }

            do {
                try pngData.write(to: url, options: .atomic)
            } catch {
                NSSound.beep()
            }
        }
    }
}

struct MermaidFallbackView: View {
    let source: String
    let theme: MDVTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mermaid diagram could not be rendered")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Text(source)
                .font(.system(size: max(theme.baseFontSize * 0.82, 11), design: .monospaced))
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    var bitmapCost: Int {
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return max(Int(size.width * size.height * 4), 1)
        }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
    }

    func flippedVertically() -> NSImage? {
        var rect = CGRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: 0,
                space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(cgImage.height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))

        guard let flipped = context.makeImage() else { return nil }
        return NSImage(cgImage: flipped, size: size)
    }
}

private extension MDVTheme {
    var mermaidDiagramTheme: DiagramTheme {
        let backgroundColor = nsColor(for: resolvedCodePalette.background ?? secondaryBackground, fallbackRGBA: isDark ? 0x252D40FF : 0xF6F8FAFF)
        let foregroundColor = nsColor(for: text, fallbackRGBA: isDark ? 0xC9D1D9FF : 0x24292FFF)
        let accentColor = nsColor(for: accent, fallbackRGBA: isDark ? 0x58A6FFFF : 0x0969DAFF)
        let lineColor = backgroundColor.mixed(with: foregroundColor, amount: isDark ? 0.70 : 0.62)
        let nodeSurfaceColor = backgroundColor.mixed(with: foregroundColor, amount: isDark ? 0.16 : 0.06)
        let nodeBorderColor = backgroundColor.mixed(with: foregroundColor, amount: isDark ? 0.58 : 0.42)

        return DiagramTheme(
            background: backgroundColor,
            foreground: foregroundColor,
            line: lineColor,
            accent: accentColor,
            muted: backgroundColor.mixed(with: foregroundColor, amount: isDark ? 0.62 : 0.54),
            surface: nodeSurfaceColor,
            border: nodeBorderColor,
            font: .systemFont(ofSize: max(baseFontSize * 0.86, 12)),
            lineWidth: 2.1,
            cornerRadius: 8
        )
    }

    func nsColor(for color: Color, fallbackRGBA: UInt32) -> NSColor {
        NSColor(color).usingColorSpace(.sRGB)
            ?? NSColor(Color(rgba: fallbackRGBA)).usingColorSpace(.sRGB)
            ?? .black
    }
}
