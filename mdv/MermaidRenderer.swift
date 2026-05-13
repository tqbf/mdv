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
    @State private var style: MermaidRenderStyle = .document
    @State private var copied = false
    @State private var copyGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chromeRow
            contentView
        }
        .background(palette.background ?? theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .contextMenu { contextMenuItems }
    }

    private var chromeRow: some View {
        HStack(spacing: 0) {
            Text(displayLanguage)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundColor(theme.tertiaryText)
                .opacity(displayLanguage.isEmpty ? 0 : 0.85)
                .padding(.leading, 14)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                styleMenu

                iconButton(
                    systemName: showSource ? "point.3.connected.trianglepath.dotted" : "curlybraces",
                    tinted: showSource,
                    help: showSource ? "Show diagram" : "Show Mermaid source"
                ) { showSource.toggle() }

                iconButton(
                    systemName: "square.and.arrow.down",
                    tinted: false,
                    help: "Export diagram as PNG"
                ) { MDVMermaidImage.exportPNG(source: content, theme: theme, style: style) }

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
    }

    private var styleMenu: some View {
        Menu {
            styleChoices
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(style == .document ? theme.secondaryText : theme.accent)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22, height: 22)
        .help("Change Mermaid diagram style")
    }

    @ViewBuilder
    private var styleChoices: some View {
        ForEach(MermaidRenderStyle.allCases) { candidate in
            Toggle(candidate.displayName, isOn: Binding(
                get: { style == candidate },
                set: { picked in if picked { style = candidate } }
            ))
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if showSource {
            Text(CodeRenderer.shared.render(code: content, languageHint: "mermaid", theme: theme))
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.225))
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            MDVMermaidDiagramView(source: content, theme: theme, style: style)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Copy Code") { copy() }
        Button(showSource ? "Show Diagram" : "Show Mermaid Source") {
            showSource.toggle()
        }
        Menu("Diagram Style") {
            styleChoices
        }
        Button("Export Diagram as PNG") {
            MDVMermaidImage.exportPNG(source: content, theme: theme, style: style)
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
        Group {
            if let image {
                GeometryReader { proxy in
                    ScrollView([.horizontal, .vertical], showsIndicators: zoom > 1.01) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: max(proxy.size.width - 36, 1) * zoom)
                            .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: diagramHeight(for: image))
                .gesture(mermaidZoomGesture)
                .accessibilityLabel("Mermaid diagram")
            } else if failed {
                MermaidFallbackView(source: source, theme: theme)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 180)
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

    private func diagramHeight(for image: NSImage) -> CGFloat {
        guard image.size.width > 0 else { return 220 }
        let aspectHeight = 720 * image.size.height / image.size.width
        return min(max(aspectHeight * zoom + 32, 180), 720)
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

private struct MermaidFallbackView: View {
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
