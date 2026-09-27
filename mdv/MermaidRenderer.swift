@preconcurrency import AppKit
import BeautifulMermaid
import SwiftMath
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
    var scale: CGFloat = 1.0

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
        let body = Text(CodeRenderer.shared.render(code: content, languageHint: "mermaid", theme: theme, scale: scale))
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

/// Diagram-type dispatch for the mermaid fence: the six families
/// BeautifulMermaid renders natively, versus everything else that goes
/// through the bundled mermaid.js. Consulted by both the on-screen
/// renderer and the print pre-pass.
func isBeautifulMermaidSupported(_ source: String) -> Bool {
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

    @State private var prepared: MDVMermaidPrepared?
    @State private var image: NSImage?
    @State private var failed = false
    @State private var availableWidth: CGFloat = 0
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1

    private var renderKey: MDVMermaidRenderKey {
        MDVMermaidRenderKey(source: source, theme: theme, style: style)
    }

    /// Width the diagram is drawn at: its natural width, or the column if
    /// that's narrower. Never upscaled — a bitmap stretched past 1:1 is
    /// what "washed out" looks like. Whole points so the raster lands on
    /// the pixel grid.
    private var displayWidth: CGFloat {
        guard let prepared, availableWidth > 0 else { return 0 }
        return floor(min(prepared.size.width, max(availableWidth - 36, 1)))
    }

    private var displayHeight: CGFloat {
        guard let prepared, displayWidth > 0 else { return 0 }
        return MDVMermaidPipeline.displaySize(for: prepared, width: displayWidth).height
    }

    var body: some View {
        if isBeautifulMermaidSupported(source) {
            Group {
                if failed {
                    MermaidFallbackView(source: source, theme: theme)
                } else if let image, prepared != nil {
                    diagramBody(for: image)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { availableWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { availableWidth = $0 }
                }
            )
            .task(id: renderKey) {
                failed = false
                prepared = nil
                image = nil
                zoom = 1
                committedZoom = 1
                if let result = await MDVMermaidImageCache.shared.prepared(source: source, theme: theme, style: style, key: renderKey) {
                    if !Task.isCancelled { prepared = result }
                } else if !Task.isCancelled {
                    failed = true
                }
            }
            // Re-rasterize when the column width or the committed zoom changes.
            // Layout is cached; this is just CoreText drawing at the new size.
            .task(id: RasterRequest(key: renderKey, width: displayWidth * committedZoom, ready: prepared != nil)) {
                guard let prepared, displayWidth > 0 else { return }
                let width = floor(displayWidth * committedZoom)
                let raster = await MDVMermaidImageCache.shared.raster(prepared, key: renderKey, width: width)
                if !Task.isCancelled { image = raster }
            }
        } else {
            MermaidWebViewContainer(source: source, theme: theme)
        }
    }

    private struct RasterRequest: Hashable {
        let key: MDVMermaidRenderKey
        let width: CGFloat
        let ready: Bool
    }

    @ViewBuilder
    private func diagramBody(for image: NSImage) -> some View {
        // Not `.resizable()`: the raster already is the display size, and a
        // resizable Image goes through a resampling draw even at 1:1. While
        // a pinch is in flight the bitmap is scaled visually; on release
        // it's re-rasterised at the committed zoom.
        let inFlight = committedZoom > 0 ? zoom / committedZoom : 1
        let baseImage = Image(nsImage: image)
            .scaleEffect(inFlight)
            .frame(width: image.size.width * inFlight, height: image.size.height * inFlight)

        if zoom > 1.01 {
            // Zoomed: inner ScrollView for panning. Pin the container height
            // to the unzoomed fit height so the document doesn't reflow.
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                baseImage
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
            .frame(height: min(displayHeight + 24, 540))
            .gesture(mermaidZoomGesture)
            .accessibilityLabel("Mermaid diagram")
        } else {
            // Unzoomed: drawn 1:1 at displayWidth, centred in the column. No
            // inner ScrollView, so wheel events bubble up to the document scroll.
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

    init(source: String, theme: MDVTheme, style: MermaidRenderStyle, scale: CGFloat? = nil) {
        self.sourceHash = source.hashValue
        self.sourceLength = source.count
        self.themeID = theme.id
        self.style = style
        self.scale = scale ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    var cacheID: NSString {
        "\(themeID)|\(style.rawValue)|\(scale)|\(sourceLength)|\(sourceHash)" as NSString
    }
}

/// Layout output, kept so the diagram can be re-drawn at any width without
/// running ELK again. `math` holds typeset `$$` node labels (block-based
/// NSImages, so they re-rasterize crisply at whatever scale they're drawn).
final class MDVMermaidPrepared: @unchecked Sendable {
    let positioned: PositionedGraph
    let theme: DiagramTheme
    let math: [String: NSImage]
    /// Sequence-diagram message labels that contained `<br>`, by message
    /// index, drawn by `rasterize` since the library draws one line only.
    let messageLines: [Int: [String]]
    /// `autonumber` was set: draw a numbered badge at each message's tail.
    let autonumber: Bool
    /// Natural size in points.
    let size: CGSize

    init(positioned: PositionedGraph, theme: DiagramTheme, math: [String: NSImage], messageLines: [Int: [String]] = [:], autonumber: Bool = false) {
        self.positioned = positioned
        self.theme = theme
        self.math = math
        self.messageLines = messageLines
        self.autonumber = autonumber
        self.size = CGSize(width: max(1, positioned.width), height: max(1, positioned.height))
    }
}

final class MDVMermaidImageCache {
    static let shared = MDVMermaidImageCache()

    private let layouts: NSCache<NSString, MDVMermaidPrepared> = {
        let cache = NSCache<NSString, MDVMermaidPrepared>()
        cache.countLimit = 96
        return cache
    }()

    private let rasters: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 192
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    func prepared(source: String, theme: MDVTheme, style: MermaidRenderStyle, key: MDVMermaidRenderKey) async -> MDVMermaidPrepared? {
        if let cached = layouts.object(forKey: key.cacheID) { return cached }
        let diagramTheme = style.diagramTheme(for: theme)
        let result = await Task.detached(priority: .userInitiated) {
            try? MDVMermaidPipeline.prepare(source: source, theme: diagramTheme)
        }.value
        if let result { layouts.setObject(result, forKey: key.cacheID) }
        return result
    }

    /// The diagram drawn `width` points wide at the key's backing scale.
    func raster(_ prepared: MDVMermaidPrepared, key: MDVMermaidRenderKey, width: CGFloat) async -> NSImage? {
        let id = "\(key.cacheID)|w=\(width)" as NSString
        if let cached = rasters.object(forKey: id) { return cached }
        let scale = key.scale
        let image = await Task.detached(priority: .userInitiated) {
            SendableMermaidImage(image: MDVMermaidPipeline.rasterize(prepared, width: width, scale: scale))
        }.value.image
        if let image { rasters.setObject(image, forKey: id, cost: max(image.bitmapCost, 1)) }
        return image
    }

    /// Natural-size image at 2× — for PNG export.
    func image(source: String, theme: MDVTheme, style: MermaidRenderStyle, key: MDVMermaidRenderKey) async -> NSImage? {
        guard let prepared = await prepared(source: source, theme: theme, style: style, key: key) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            SendableMermaidImage(image: MDVMermaidPipeline.rasterize(prepared, width: ceil(prepared.size.width), scale: 2))
        }.value.image
    }
}

// Parse → normalize → layout → render, instead of the library's one-shot
// `MermaidRenderer.renderImage`, so we can repair the parsed model before it
// reaches the ELK layout engine. ELK enforces its invariants with `assert`,
// which is uncatchable and takes the whole app down.
enum MDVMermaidPipeline {
    /// Parse, repair, typeset math labels, and run ELK. The expensive half;
    /// `rasterize` does the rest and can be repeated at any width.
    static func prepare(source: String, theme: DiagramTheme) throws -> MDVMermaidPrepared {
        var graph = try MermaidParser.parse(sanitize(source))
        var mathNodes: [String: NSImage] = [:]
        var messageLines: [Int: [String]] = [:]
        switch graph.typedPayload {
        case .flowchart(var model), .stateDiagram(var model):
            normalizeSubgraphOwnership(model)
            if graph.type == .stateDiagram { applyStateStyles(in: &model, source: sanitize(source)) }
            mathNodes = substituteMath(in: &model, theme: theme)
            graph.payload = model
        case .sequenceDiagram(var seq):
            messageLines = resolveLineBreaks(in: &seq)
            graph.payload = seq
        default:
            break
        }
        var positioned = try GraphLayout().layout(graph)
        var autonumber = false
        if graph.type == .sequenceDiagram {
            widenActorGaps(&positioned, messageLines: messageLines)
            expandRows(&positioned, for: messageLines)
            fitBlocksAroundNotes(&positioned)
            autonumber = source.range(of: #"(?m)^\s*autonumber\b"#, options: .regularExpression) != nil
        }
        return MDVMermaidPrepared(positioned: positioned, theme: theme, math: mathNodes, messageLines: messageLines, autonumber: autonumber)
    }

    /// The layout spaces actors by their box widths only, so a long message
    /// label runs straight through the neighbouring lifelines (Mermaid.js
    /// widens the gap to fit). Grow each gap until every message's label
    /// fits between its endpoints, then remap every x in the diagram through
    /// the old→new actor centres (piecewise linear, so block edges and note
    /// boxes anchored between actors move with them).
    private static func widenActorGaps(_ positioned: inout PositionedGraph, messageLines: [Int: [String]]) {
        guard case .sequenceDiagram(var actors, var messages, var blocks, var lifelines, var activations, var notes) = positioned.content,
              actors.count > 1 else { return }
        let font = NSFont.systemFont(ofSize: 11)
        func width(_ text: String) -> Double { (text as NSString).size(withAttributes: [.font: font]).width }
        let index = Dictionary(actors.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldX = actors.map(\.x)
        var gaps = (1..<actors.count).map { oldX[$0] - oldX[$0 - 1] }

        for (i, msg) in messages.enumerated() {
            guard let a = index[msg.from], let b = index[msg.to] else { continue }
            let lines = messageLines[i] ?? [msg.label]
            let needed = (lines.map(width).max() ?? 0) + 24
            if a == b {
                // Self message: label sits to the right of the loop, before the next lifeline.
                guard a + 1 < actors.count else { continue }
                let have = gaps[a] - actors[a + 1].width / 2
                if have < needed + 36 { gaps[a] += needed + 36 - have }
            } else {
                let lo = min(a, b), hi = max(a, b)
                let span = (lo..<hi).reduce(0.0) { $0 + gaps[$1] }
                if span < needed { gaps[hi - 1] += needed - span }
            }
        }

        var newX = [oldX[0]]
        for g in gaps { newX.append(newX[newX.count - 1] + g) }
        guard newX != oldX else { return }

        func remap(_ x: Double) -> Double {
            if x <= oldX[0] { return x + (newX[0] - oldX[0]) }
            for k in 1..<oldX.count where x <= oldX[k] {
                let t = (x - oldX[k - 1]) / max(oldX[k] - oldX[k - 1], 0.001)
                return newX[k - 1] + t * (newX[k] - newX[k - 1])
            }
            return x + (newX[newX.count - 1] - oldX[oldX.count - 1])
        }

        for i in actors.indices { actors[i].x = newX[i] }
        for i in lifelines.indices { lifelines[i].x = remap(lifelines[i].x) }
        for i in activations.indices { activations[i].x = remap(activations[i].x + activations[i].width / 2) - activations[i].width / 2 }
        for i in messages.indices {
            messages[i].x1 = remap(messages[i].x1)
            messages[i].x2 = remap(messages[i].x2)
        }
        for i in notes.indices {
            // Keep the box size; move its anchor (centre for "over", the near edge otherwise).
            switch notes[i].position {
            case "left":  notes[i].x = remap(notes[i].x + notes[i].width) - notes[i].width
            case "right": notes[i].x = remap(notes[i].x)
            default:      notes[i].x = remap(notes[i].x + notes[i].width / 2) - notes[i].width / 2
            }
        }
        for i in blocks.indices {
            let left = remap(blocks[i].x), right = remap(blocks[i].x + blocks[i].width)
            blocks[i].x = left
            blocks[i].width = right - left
        }
        positioned.width += newX[newX.count - 1] - oldX[oldX.count - 1]
        positioned.content = .sequenceDiagram(
            actors: actors, messages: messages, blocks: blocks,
            lifelines: lifelines, activations: activations, notes: notes
        )
    }

    /// A note placed after the last message of a block is laid out below
    /// the block's bottom edge (the layout ends blocks at the last message).
    /// Extend such blocks to enclose the note.
    private static func fitBlocksAroundNotes(_ positioned: inout PositionedGraph) {
        guard case .sequenceDiagram(let actors, let messages, var blocks, let lifelines, let activations, let notes) = positioned.content,
              !notes.isEmpty else { return }
        for i in blocks.indices {
            let bottom = blocks[i].y + blocks[i].height
            for note in notes {
                let noteBottom = note.y + note.height
                let overlapsX = note.x < blocks[i].x + blocks[i].width && note.x + note.width > blocks[i].x
                if overlapsX, note.y > blocks[i].y, note.y < bottom, noteBottom + 8 > bottom {
                    blocks[i].height = noteBottom + 8 - blocks[i].y
                }
            }
        }
        positioned.content = .sequenceDiagram(
            actors: actors, messages: messages, blocks: blocks,
            lifelines: lifelines, activations: activations, notes: notes
        )
    }

    /// Line pitch of message labels drawn by `drawMessageLines`.
    private static let messageLineHeight: Double = 13

    /// The layout gives every message a fixed 40pt row. Open up the rows of
    /// multi-line messages by pushing the message and everything below it
    /// down `(lines − 1) × lineHeight`, and growing the blocks, lifelines
    /// and diagram height that span it. Items above (previous arrow, block
    /// header, divider) stay put, so the gap grows.
    private static func expandRows(_ positioned: inout PositionedGraph, for messageLines: [Int: [String]]) {
        guard case .sequenceDiagram(let actors, var messages, var blocks, var lifelines, var activations, var notes) = positioned.content else { return }
        var total = 0.0
        for index in messageLines.keys.sorted() {
            guard messages.indices.contains(index), let lines = messageLines[index], lines.count > 1 else { continue }
            let extra = Double(lines.count - 1) * messageLineHeight + 4
            let threshold = messages[index].y - 0.5
            for i in messages.indices where messages[i].y >= threshold { messages[i].y += extra }
            for i in notes.indices where notes[i].y >= threshold { notes[i].y += extra }
            for i in activations.indices {
                if activations[i].topY >= threshold { activations[i].topY += extra }
                if activations[i].bottomY >= threshold { activations[i].bottomY += extra }
            }
            for i in lifelines.indices where lifelines[i].bottomY >= threshold { lifelines[i].bottomY += extra }
            for i in blocks.indices {
                if blocks[i].y >= threshold {
                    blocks[i].y += extra
                } else if blocks[i].y + blocks[i].height >= threshold {
                    blocks[i].height += extra
                }
                for d in blocks[i].dividers.indices where blocks[i].dividers[d].y >= threshold {
                    blocks[i].dividers[d].y += extra
                }
            }
            total += extra
        }
        positioned.height += total
        positioned.content = .sequenceDiagram(
            actors: actors, messages: messages, blocks: blocks,
            lifelines: lifelines, activations: activations, notes: notes
        )
    }

    // MARK: Sequence diagrams: <br> in labels

    /// The sequence parser normalises `<br/>` to `<br>` and leaves it in the
    /// label; only notes get real line breaks from the renderer. Notes: make
    /// them newlines. Actors: the box is a fixed 40pt, so join with a space
    /// (its width follows the label). Messages: the library draws one line
    /// centred on the arrow, so blank the label and keep the lines for
    /// `rasterize` to stack above the arrow.
    private static func resolveLineBreaks(in seq: inout SequenceDiagram) -> [Int: [String]] {
        let br = #"<br\s*/?>"#
        for i in seq.notes.indices {
            seq.notes[i].text = seq.notes[i].text.replacingOccurrences(of: br, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        for i in seq.actors.indices {
            seq.actors[i].label = seq.actors[i].label.replacingOccurrences(of: br, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        var lines: [Int: [String]] = [:]
        for i in seq.messages.indices {
            let label = seq.messages[i].label
            guard label.range(of: br, options: [.regularExpression, .caseInsensitive]) != nil else { continue }
            lines[i] = label
                .replacingOccurrences(of: br, with: "\n", options: [.regularExpression, .caseInsensitive])
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            seq.messages[i].label = ""
        }
        return lines
    }

    /// Mermaid's `autonumber`: a filled disc with the 1-based message
    /// number on the tail of each arrow. The library ignores the keyword.
    private static func drawAutonumbers(_ prepared: MDVMermaidPrepared, size: CGSize, fitX: CGFloat, fitY: CGFloat, in ctx: CGContext) {
        guard case .sequenceDiagram(_, let messages, _, _, _, _) = prepared.positioned.content else { return }
        let radius = 8 * fitX
        let font = NSFont.systemFont(ofSize: 9 * fitX, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: prepared.theme.background]
        for (i, msg) in messages.enumerated() {
            let cx = msg.x1 * fitX
            let cy = size.height - msg.y * fitY
            ctx.setFillColor(prepared.theme.foreground.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - radius, y: cy - radius, width: 2 * radius, height: 2 * radius))
            let text = NSAttributedString(string: "\(i + 1)", attributes: attributes)
            let w = text.size().width, h = text.size().height
            text.draw(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
        }
    }

    /// Mirrors the library's message-label placement (11pt edge-label font in
    /// the muted colour; centred 8pt above a normal arrow, left of a self
    /// loop) but stacks lines upward so none crosses the arrow.
    private static func drawMessageLines(_ prepared: MDVMermaidPrepared, size: CGSize, fitX: CGFloat, fitY: CGFloat) {
        guard case .sequenceDiagram(_, let messages, _, _, _, _) = prepared.positioned.content else { return }
        let font = NSFont.systemFont(ofSize: 11 * fitX)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: prepared.theme.effectiveMuted()]
        let lineHeight = messageLineHeight * fitY
        for (index, lines) in prepared.messageLines {
            guard messages.indices.contains(index) else { continue }
            let msg = messages[index]
            let sized = lines.map { NSAttributedString(string: $0, attributes: attributes) }
            if msg.isSelf {
                // Self loop: 28×20, label to its right, block centred on the loop.
                let x = (msg.x1 + 28 + 4) * fitX
                let centerY = size.height - (msg.y + 10) * fitY
                var top = centerY + CGFloat(sized.count) * lineHeight / 2
                for line in sized {
                    line.draw(in: CGRect(x: x, y: top - lineHeight, width: line.size().width + 2, height: lineHeight))
                    top -= lineHeight
                }
            } else {
                let centerX = (msg.x1 + msg.x2) / 2 * fitX
                var bottom = size.height - (msg.y - 2) * fitY   // lowest line sits just above the arrow
                for line in sized.reversed() {
                    let w = line.size().width + 2
                    line.draw(in: CGRect(x: centerX - w / 2, y: bottom, width: w, height: lineHeight))
                    bottom += lineHeight
                }
            }
        }
    }

    /// Whole-point size a diagram is shown at when drawn `width` points
    /// wide. Shared by the view (frame) and `rasterize` (bitmap) so the two
    /// can never disagree.
    static func displaySize(for prepared: MDVMermaidPrepared, width: CGFloat) -> CGSize {
        let w = max(1, floor(width))
        return CGSize(width: w, height: max(1, ceil(w * prepared.size.height / prepared.size.width)))
    }

    /// Draws the laid-out diagram `width` points wide (aspect preserved) into
    /// a bitmap at `scale` px/pt, upright. Text is drawn by CoreText at the
    /// final size instead of being drawn once and resampled, which is what
    /// keeps labels as sharp as the document text around them.
    static func rasterize(_ prepared: MDVMermaidPrepared, width: CGFloat, scale: CGFloat) -> NSImage? {
        let size = displaySize(for: prepared, width: width)
        guard let ctx = CGContext(
            data: nil,
            width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsFontSmoothing(true)
        draw(prepared, in: ctx, size: size, scale: scale)
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: size)
    }

    /// The laid-out diagram as a PDF page, for print.
    ///
    /// Everything the renderer draws goes through CoreGraphics and CoreText, so
    /// a PDF context keeps the labels as glyphs — the same trick as printed
    /// formulas, and the reason a printed diagram's text stops looking soft
    /// next to vector prose.
    static func pdf(_ prepared: MDVMermaidPrepared, width: CGFloat) -> (document: CGPDFDocument, page: CGPDFPage, size: CGSize)? {
        let size = displaySize(for: prepared, width: width)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        ctx.beginPDFPage(nil)
        draw(prepared, in: ctx, size: size, scale: 1)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        return (document, page, size)
    }

    /// Draws the diagram into `ctx`, which may be a bitmap or a PDF context.
    private static func draw(_ prepared: MDVMermaidPrepared, in ctx: CGContext, size: CGSize, scale: CGFloat) {
        let natural = prepared.size
        // The drawing is exactly `displaySize(for:width:)` points — the same
        // numbers the view uses for its frame — so it's shown 1:1. An
        // off-by-one from floor(natural × fit) here was enough to make
        // SwiftUI resample the whole diagram and soften every label.
        let fitX = size.width / natural.width
        let fitY = size.height / natural.height
        ctx.setShouldSmoothFonts(true)

        // The library draws y-down. Flip once here instead of flipping the
        // finished bitmap.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: fitX, y: -fitY)
        DiagramRenderer(theme: prepared.theme).render(
            prepared.positioned,
            in: ctx,
            bounds: CGRect(origin: .zero, size: natural)
        )
        ctx.restoreGState()

        if !prepared.messageLines.isEmpty || prepared.autonumber {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            drawMessageLines(prepared, size: size, fitX: fitX, fitY: fitY)
            if prepared.autonumber { drawAutonumbers(prepared, size: size, fitX: fitX, fitY: fitY, in: ctx) }
            NSGraphicsContext.restoreGraphicsState()
        }

        // Typeset math over its nodes (y-up, in display points).
        if !prepared.math.isEmpty, let nodes = prepared.positioned.flowchartNodes {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            // Plain fill, same as document math. (A faux-bold fill+stroke was
            // tried: it spreads ink into grey fringe and reads *lighter*.)
            // Snap the destination to the pixel grid: NSImage rasterises a
            // handler-backed image into a cache and then composites it, and
            // a fractional origin means that composite is resampled — the
            // glyphs come out visibly lighter and softer than the same
            // formula drawn in the document.
            func snap(_ v: CGFloat) -> CGFloat { (v * scale).rounded() / scale }
            for node in nodes {
                guard let image = prepared.math[node.id] else { continue }
                let w = snap(image.size.width * fitX), h = snap(image.size.height * fitY)
                let x = snap((node.x + (node.width - image.size.width) / 2) * fitX)
                let yTop = snap((node.y + (node.height - image.size.height) / 2) * fitY)
                image.draw(in: CGRect(x: x, y: size.height - yTop - h, width: w, height: h))
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: LaTeX in labels

    /// Mermaid.js renders `$$…$$` inside node/edge labels with KaTeX;
    /// BeautifulMermaid draws the dollars verbatim. A node whose label is
    /// nothing but one math span gets typeset properly: the label is swapped
    /// for a blank placeholder the layout measures to the same size, and the
    /// math image is drawn over the node afterwards (`composite`). Math mixed
    /// with text, and math in edge labels, falls back to the Unicode
    /// approximation the TOC uses (`x²`, `≤`, `a/b`).
    /// Body-text size rather than the 13pt node-label size: Latin Modern is
    /// a light serif and at node-label size next to 500-weight system text it
    /// reads as washed out. Same size as document display math.
    private static let mathLabelFontSize: CGFloat = 16

    private static func substituteMath(in model: inout ParsedGraphModel, theme: DiagramTheme) -> [String: NSImage] {
        var images: [String: NSImage] = [:]
        for idx in model.nodesInOrder.indices {
            let label = model.nodesInOrder[idx].node.label
            guard label.contains("$$") else { continue }
            if let latex = wholeMathSpan(label), let image = typeset(latex, color: theme.foreground) {
                images[model.nodesInOrder[idx].id] = image
                model.nodesInOrder[idx].node.label = placeholder(for: image.size)
            } else {
                model.nodesInOrder[idx].node.label = MathMarkdown.plainText(label)
            }
        }
        for idx in model.edges.indices {
            if let label = model.edges[idx].label, label.contains("$$") {
                model.edges[idx].label = MathMarkdown.plainText(label)
            }
        }
        return images
    }

    /// The LaTeX if `label` is exactly one `$$…$$` span (whitespace and
    /// line breaks around it allowed), else nil.
    private static func wholeMathSpan(_ label: String) -> String? {
        let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("$$"), t.hasSuffix("$$"), t.count > 4 else { return nil }
        let inner = t.dropFirst(2).dropLast(2)
        guard !inner.contains("$$") else { return nil }
        let latex = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        return latex.isEmpty ? nil : latex
    }

    private static func typeset(_ latex: String, color: NSColor) -> NSImage? {
        MathSymbols.registerOnce()
        var math = MathImage(
            latex: MathSymbols.preprocess(latex),
            fontSize: mathLabelFontSize,
            textColor: color,
            labelMode: .display,
            textAlignment: .center
        )
        let (error, image, _) = math.asImage()
        return error == nil ? image : nil
    }

    /// Blank text the library measures to at least `size`: spaces for width,
    /// extra lines for height. Node padding is added by the layout as usual.
    private static func placeholder(for size: CGSize) -> String {
        let fontSize = original_src_styles.FONT_SIZES.nodeLabel
        let weight = original_src_styles.FONT_WEIGHTS.nodeLabel
        var line = " "
        while original_src_text_metrics.measureMultilineText(line, fontSize: fontSize, fontWeight: weight).width < size.width,
              line.count < 400 {
            line.append(" ")
        }
        var text = line
        while original_src_text_metrics.measureMultilineText(text, fontSize: fontSize, fontWeight: weight).height < size.height,
              text.count < 4000 {
            text += "\n" + line
        }
        return text
    }

    /// Two things Mermaid.js accepts that BeautifulMermaid's parser doesn't:
    ///
    /// - A YAML front-matter block (`---\nconfig: …\n---`) before the
    ///   diagram type. It only carries config we can't honour anyway
    ///   (`wrappingWidth`, themes), so drop it rather than fail with
    ///   `invalidHeader("---")`.
    /// - Inline HTML formatting in labels (`<b>`, `<i>`, `<code>`, …).
    ///   The parser passes those through as literal text. Strip the tags
    ///   and keep the content; `<br/>` is understood and left alone.
    static func sanitize(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        // Front matter: leading `---` line … next `---` line.
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].trimmingCharacters(in: .whitespaces) == "---",
           let close = lines[(first + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(first...close)
        }
        var joined = lines.joined(separator: "\n")
        // xychart: `line "interest" [...]` / `bar "x" [...]` — the parser
        // only knows the unnamed form.
        if joined.contains("xychart") {
            joined = joined.replacingOccurrences(
                of: #"(?m)^(\s*)(line|bar)\s+"[^"]*"\s*\["#,
                with: "$1$2 [",
                options: .regularExpression
            )
        }
        joined = normalizeColors(in: joined)
        joined = mergeStateDescriptions(in: joined)
        // Parallelogram shapes `id[/text/]` and `id[\text\]`: the parser only
        // knows the trapezoids `[/…\]` / `[\…/]`, so these fall through to the
        // rectangle rule with the slashes (and quotes) left in the label.
        // Draw them as plain rectangles; the shape is lost, the text isn't.
        joined = joined.replacingOccurrences(
            of: #"([\w-]+)\[/([^\]]+?)/\]"#, with: "$1[$2]", options: .regularExpression)
        joined = joined.replacingOccurrences(
            of: #"([\w-]+)\[\\([^\]]+?)\\\]"#, with: "$1[$2]", options: .regularExpression)
        guard joined.contains("<") else { return joined }
        return joined.replacingOccurrences(
            of: #"</?(?:b|i|u|s|strong|em|small|sup|sub|span|code|tt|font|mark)(?:\s[^<>]*)?>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// stateDiagram: Mermaid lets a state carry several `ID: text` lines
    /// (the first is its title, the rest its body). The library's parser
    /// keeps whichever registration of the ID comes first — often the bare
    /// transition — and drops the rest. Fold all descriptions into one
    /// `state "line<br/>line" as ID` alias placed right after the header,
    /// which the parser does honour.
    static func mergeStateDescriptions(in source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("statediagram")
        }) else { return source }
        let descRegex = try! NSRegularExpression(pattern: #"^\s*([\w\p{L}-]+)\s*:\s*(.+?)\s*$"#)
        let transitionRegex = try! NSRegularExpression(pattern: #"^\s*(\[\*\]|[\w\p{L}-]+)\s*-->"#)
        var descriptions: [(id: String, lines: [String])] = []
        var remove = IndexSet()
        for (i, line) in lines.enumerated() where i > header {
            let range = NSRange(line.startIndex..., in: line)
            guard transitionRegex.firstMatch(in: line, range: range) == nil,
                  let m = descRegex.firstMatch(in: line, range: range),
                  let idRange = Range(m.range(at: 1), in: line),
                  let textRange = Range(m.range(at: 2), in: line) else { continue }
            let id = String(line[idRange])
            let keywords: Set<String> = ["state", "direction", "classDef", "class", "style", "note", "linkStyle"]
            if keywords.contains(id) { continue }
            let text = String(line[textRange])
            if let k = descriptions.firstIndex(where: { $0.id == id }) {
                descriptions[k].lines.append(text)
            } else {
                descriptions.append((id, [text]))
            }
            remove.insert(i)
        }
        guard !descriptions.isEmpty else { return source }
        for i in remove.sorted(by: >) { lines.remove(at: i) }
        let aliases = descriptions.map { desc -> String in
            let label = desc.lines.joined(separator: "<br/>").replacingOccurrences(of: "\"", with: "'")
            return "    state \"\(label)\" as \(desc.id)"
        }
        lines.insert(contentsOf: aliases, at: header + 1)
        return lines.joined(separator: "\n")
    }

    /// stateDiagram: the parser ignores `classDef` / `class` / `style` lines
    /// (flowcharts get them). Read them from the source and put them on the
    /// model, where the shared layout resolves them like a flowchart's.
    private static func applyStateStyles(in model: inout ParsedGraphModel, source: String) {
        func props(_ text: String) -> [String: String] {
            var out: [String: String] = [:]
            for pair in text.replacingOccurrences(of: #";\s*$"#, with: "", options: .regularExpression).split(separator: ",") {
                guard let colon = pair.firstIndex(of: ":") else { continue }
                let key = pair[..<colon].trimmingCharacters(in: .whitespaces)
                let value = pair[pair.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty, !value.isEmpty { out[key] = value }
            }
            return out
        }
        for raw in source.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = line.range(of: #"^classDef\s+(\w+)\s+(.+)$"#, options: .regularExpression) {
                let parts = String(line[m]).dropFirst("classDef".count).trimmingCharacters(in: .whitespaces)
                if let space = parts.firstIndex(of: " ") {
                    model.classDefs[String(parts[..<space])] = props(String(parts[parts.index(after: space)...]))
                }
            } else if let m = line.range(of: #"^class\s+([\w\p{L}-]+(?:\s*,\s*[\w\p{L}-]+)*)\s+(\w+)\s*$"#, options: .regularExpression) {
                let parts = String(line[m]).dropFirst("class".count).trimmingCharacters(in: .whitespaces)
                guard let space = parts.lastIndex(of: " ") else { continue }
                let className = String(parts[parts.index(after: space)...])
                for id in parts[..<space].split(separator: ",") {
                    model.classAssignments[id.trimmingCharacters(in: .whitespaces)] = className
                }
            } else if let m = line.range(of: #"^style\s+([\w\p{L}-]+)\s+(.+)$"#, options: .regularExpression) {
                let parts = String(line[m]).dropFirst("style".count).trimmingCharacters(in: .whitespaces)
                if let space = parts.firstIndex(of: " ") {
                    model.nodeStyles[String(parts[..<space])] = props(String(parts[parts.index(after: space)...]))
                }
            }
        }
    }

    /// The library's `BMColor(hex:)` accepts only 6- or 8-digit hex and turns
    /// anything else into black — so `style RET fill:#eee` painted a black
    /// box. Expand CSS shorthand (`#eee` → `#eeeeee`, `#abcd` → `#aabbccdd`)
    /// and translate the CSS colour names Mermaid docs actually use.
    static func normalizeColors(in source: String) -> String {
        guard source.contains("fill") || source.contains("stroke") || source.contains("color") else { return source }
        var out = source
        // Only touch styling lines; a label could legitimately contain "#abc".
        let lines = out.components(separatedBy: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("style ") || t.hasPrefix("classDef ") || t.hasPrefix("linkStyle ") else { return line }
            var l = line.replacingOccurrences(
                of: #"#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])?\b"#,
                with: "#$1$1$2$2$3$3$4$4",
                options: .regularExpression
            )
            for (name, hex) in cssColorNames {
                l = l.replacingOccurrences(
                    of: #"(?i)((?:fill|stroke|color)\s*:\s*)\#(name)\b"#,
                    with: "$1\(hex)",
                    options: .regularExpression
                )
            }
            return l
        }
        out = lines.joined(separator: "\n")
        return out
    }

    private static let cssColorNames: [(String, String)] = [
        ("white", "#ffffff"), ("black", "#000000"), ("red", "#ff0000"), ("green", "#008000"),
        ("blue", "#0000ff"), ("yellow", "#ffff00"), ("orange", "#ffa500"), ("purple", "#800080"),
        ("gray", "#808080"), ("grey", "#808080"), ("lightgray", "#d3d3d3"), ("lightgrey", "#d3d3d3"),
        ("darkgray", "#a9a9a9"), ("silver", "#c0c0c0"), ("pink", "#ffc0cb"), ("lightblue", "#add8e6"),
        ("lightgreen", "#90ee90"), ("lightyellow", "#ffffe0"), ("gold", "#ffd700"), ("teal", "#008080"),
        ("navy", "#000080"), ("maroon", "#800000"), ("olive", "#808000"), ("cyan", "#00ffff"),
        ("magenta", "#ff00ff"), ("brown", "#a52a2a"), ("beige", "#f5f5dc"), ("ivory", "#fffff0"),
        ("lavender", "#e6e6fa"), ("coral", "#ff7f50"), ("salmon", "#fa8072"), ("tomato", "#ff6347"),
        ("crimson", "#dc143c"), ("indigo", "#4b0082"), ("violet", "#ee82ee"), ("khaki", "#f0e68c"),
        ("tan", "#d2b48c"), ("wheat", "#f5deb3"), ("mintcream", "#f5fffa"), ("honeydew", "#f0fff0"),
        ("aliceblue", "#f0f8ff"), ("whitesmoke", "#f5f5f5"), ("gainsboro", "#dcdcdc"), ("snow", "#fffafa"),
        ("transparent", "#00000000"), ("none", "#00000000"),
    ]

    // The parser lets a node be claimed by several subgraphs (e.g. `A --> B`
    // inside `subgraph X` and `B` declared in `subgraph Y`). The layout builder
    // then emits B as a child of both compound nodes, and ELK asserts on the
    // edge-container mismatch. Mermaid.js gives the node to the subgraph that
    // mentioned it last; do the same so each node has exactly one owner.
    private static func normalizeSubgraphOwnership(_ model: ParsedGraphModel) {
        var owner: [String: ObjectIdentifier] = [:]
        func claim(_ subgraph: original_src_types.MermaidSubgraph) {
            for id in subgraph.nodeIds { owner[id] = ObjectIdentifier(subgraph) }
            subgraph.children.forEach(claim)
        }
        func prune(_ subgraph: original_src_types.MermaidSubgraph) {
            let me = ObjectIdentifier(subgraph)
            subgraph.nodeIds.removeAll { owner[$0] != me }
            subgraph.children.forEach(prune)
        }
        model.subgraphs.forEach(claim)
        model.subgraphs.forEach(prune)
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
}

private extension MDVTheme {
    var mermaidDiagramTheme: DiagramTheme {
        let backgroundColor = nsColor(for: resolvedCodePalette.background ?? secondaryBackground, fallbackRGBA: isDark ? 0x252D40FF : 0xF6F8FAFF)
        let foregroundColor = nsColor(for: text, fallbackRGBA: isDark ? 0xC9D1D9FF : 0x24292FFF)
        let accentColor = nsColor(for: accent, fallbackRGBA: isDark ? 0x58A6FFFF : 0x0969DAFF)
        let lineColor = backgroundColor.mixed(with: foregroundColor, amount: isDark ? 0.70 : 0.62)
        // Light themes: nodes take the page colour so labels — and typeset
        // math especially — sit on the same ground as the body text instead
        // of a grey that's darker than the panel; the border keeps them
        // legible where page and code backgrounds coincide. Dark themes
        // keep the lifted surface.
        let pageColor = nsColor(for: background, fallbackRGBA: 0xFFFFFFFF)
        let nodeSurfaceColor = isDark
            ? backgroundColor.mixed(with: foregroundColor, amount: 0.16)
            : pageColor.mixed(with: backgroundColor, amount: 0.25)
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
