import AppKit
import MarkdownUI
import SwiftUI

/// Prints the rendered markdown document (⌘P → NSPrintOperation, whose
/// dialog's PDF dropdown doubles as Save-as-PDF).
///
/// Strategy: re-render every block through the same MarkdownUI pipeline the
/// screen uses, but via SwiftUI's `ImageRenderer` into one small vector PDF
/// per block. A plain flipped NSView composites those PDF pages in
/// `draw(_:)` and NSPrintOperation paginates it; `adjustPageHeightNew`
/// pushes a block that would straddle a page break onto the next page, so
/// breaks land in the gutters between blocks instead of through a line of
/// text.
///
/// Why ImageRenderer and not NSHostingView: hosting views composite through
/// the CoreAnimation render server, and their content never reaches
/// AppKit's print drawing context from an offscreen window — they print
/// blank. ImageRenderer renders without any window, and its CGContext path
/// keeps text as vector glyphs in the final PDF.
///
/// Mermaid diagrams render asynchronously on screen (`.task` →
/// MDVMermaidImageCache); ImageRenderer never runs async work, so mermaid
/// blocks are pre-rendered to NSImages through the same cache before the
/// view tree is built, and a fence whose render fails is re-tagged
/// `mermaid` → `text` so it prints as a plain code block rather than as an
/// empty box.
@MainActor
enum PrintController {

    struct Request {
        let blocks: [String]
        let jobTitle: String
        let theme: MDVTheme
        let baseURL: URL?
        /// Effective flag — caller has already ANDed the user preference
        /// with the *print* theme's `smartTypographyAllowed`.
        let smartTypography: Bool
        /// Sheet parent. nil → app-modal dialog.
        let window: NSWindow?
    }

    static func printDocument(_ request: Request) {
        // A print sheet is already up — don't stack a second modal session.
        guard activeSession == nil else {
            NSSound.beep()
            return
        }
        Task { @MainActor in
            let mermaid = await preRenderMermaid(blocks: request.blocks, theme: request.theme)
            // Leave the task context before building views or presenting the
            // panel: the macOS 26 print panel is SwiftUI-backed and its view
            // updates interrogate the current Swift-concurrency executor;
            // presented from inside this short-lived Task it crashes
            // (EXC_BAD_ACCESS in swift_task_isCurrentExecutor / DesignLibrary)
            // once the task is gone. A plain main-queue callout has no task
            // context to go stale. Reproduced 5/5 without this hop, 0/N with.
            DispatchQueue.main.async {
                let printInfo = makePrintInfo()
                let container = buildContainer(request: request, mermaid: mermaid, printInfo: printInfo)
                runOperation(container: container, printInfo: printInfo, request: request)
            }
        }
    }

    // MARK: - Print info

    private static func makePrintInfo() -> NSPrintInfo {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        // AppKit's standard header (job title + date) and footer (page
        // numbers), fed by PrintContainerView.printJobTitle.
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = NSNumber(value: true)
        return info
    }

    // MARK: - Mermaid pre-pass

    private struct MermaidPrePass {
        var images: [Int: NSImage] = [:]
        var failed: Set<Int> = []
    }

    private static func preRenderMermaid(blocks: [String], theme: MDVTheme) async -> MermaidPrePass {
        // Same style preference MermaidCodeBlockChrome persists via
        // @AppStorage("mdv.mermaid.style").
        let style = UserDefaults.standard.string(forKey: "mdv.mermaid.style")
            .flatMap(MermaidRenderStyle.init(rawValue:)) ?? .document
        var result = MermaidPrePass()
        for (idx, block) in blocks.enumerated() {
            guard let source = mermaidSource(fromFencedBlock: block) else { continue }
            let key = MDVMermaidRenderKey(source: source, theme: theme, style: style)
            if let image = await MDVMermaidImageCache.shared.image(
                source: source, theme: theme, style: style, key: key
            ) {
                result.images[idx] = image
            } else {
                result.failed.insert(idx)
            }
        }
        return result
    }

    /// If `block` is a single fenced code block whose info string names
    /// mermaid, returns the fence body; otherwise nil. The document's block
    /// splitter is fence-aware, so a mermaid fence is exactly one block.
    /// Language detection mirrors `CodeBlockChrome.displayLanguage` (first
    /// token of the info string).
    private static func mermaidSource(fromFencedBlock block: String) -> String? {
        var lines = block.components(separatedBy: "\n")
        guard let first = lines.first else { return nil }
        let trimmed = first.drop(while: { $0 == " " })
        let marker: String
        if trimmed.hasPrefix("```") { marker = "```" }
        else if trimmed.hasPrefix("~~~") { marker = "~~~" }
        else { return nil }
        let info = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let language = info.split(separator: " ").first.map { $0.lowercased() } ?? ""
        guard language == "mermaid" else { return nil }
        lines.removeFirst()
        // Tolerate an unterminated fence at EOF.
        if let last = lines.last, last.drop(while: { $0 == " " }).hasPrefix(marker) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    /// Failed mermaid render → print the source as a plain code block.
    /// Re-tagging the fence keeps it out of MermaidCodeBlockChrome (whose
    /// diagram view renders via `.task` and would print as an empty box).
    private static func retagMermaidFence(_ block: String) -> String {
        var lines = block.components(separatedBy: "\n")
        guard let first = lines.first,
              let range = first.range(of: "mermaid", options: .caseInsensitive) else { return block }
        lines[0] = first.replacingCharacters(in: range, with: "text")
        return lines.joined(separator: "\n")
    }

    // MARK: - Container construction

    private static func buildContainer(
        request: Request,
        mermaid: MermaidPrePass,
        printInfo: NSPrintInfo
    ) -> PrintContainerView {
        let contentWidth = printInfo.paperSize.width
            - printInfo.leftMargin - printInfo.rightMargin
        let container = PrintContainerView(frame: .zero)
        container.pageBackground = NSColor(request.theme.background)
        container.jobTitle = request.jobTitle

        // Screen rhythm: LazyVStack spacing 8 + each block's 2pt vertical
        // hover padding × 2.
        let spacing: CGFloat = 12
        var y: CGFloat = 0
        for (idx, block) in request.blocks.enumerated() {
            let source = mermaid.failed.contains(idx) ? retagMermaidFence(block) : block
            let markdown = request.smartTypography ? smartenMarkdown(source) : source
            let root = PrintBlockView(
                markdown: markdown,
                mermaidImage: mermaid.images[idx],
                theme: request.theme,
                baseURL: request.baseURL
            )
            // Pinning the width inside the root view makes ImageRenderer
            // report the ideal height at that width.
            .frame(width: contentWidth, alignment: .topLeading)
            .environment(\.colorScheme, request.theme.isDark ? .dark : .light)

            guard let render = renderBlockPDF(root: AnyView(root), width: contentWidth) else {
                continue
            }
            let frame = NSRect(x: 0, y: y, width: contentWidth, height: ceil(render.size.height))
            container.blockRenders.append(
                PrintContainerView.BlockRender(
                    frame: frame, document: render.document, page: render.page
                )
            )
            y += frame.height + spacing
        }
        container.frame = NSRect(x: 0, y: 0, width: contentWidth, height: max(y - spacing, 1))
        return container
    }

    /// Renders one block view into a single-page vector PDF at the given
    /// width, returning the PDF document, its first page, and the laid-out
    /// size. Text stays vector all the way into the print/Save-as-PDF
    /// output.
    ///
    /// The `document` is returned alongside the `page` and MUST be retained
    /// for as long as the page is used: a `CGPDFPage` does not retain its
    /// parent document, so dropping the document frees the page's backing
    /// bytes and any later `drawPDFPage` is a use-after-free.
    private static func renderBlockPDF(
        root: AnyView, width: CGFloat
    ) -> (document: CGPDFDocument, page: CGPDFPage, size: CGSize)? {
        let renderer = ImageRenderer(content: root)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)

        var laidOutSize = CGSize.zero
        let data = NSMutableData()
        renderer.render { size, renderInContext in
            laidOutSize = size
            guard size.width > 0, size.height > 0,
                  let consumer = CGDataConsumer(data: data as CFMutableData) else { return }
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
        }
        guard laidOutSize.width > 0, laidOutSize.height > 0,
              let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        return (document, page, laidOutSize)
    }

    // MARK: - Run

    /// Keeps the container alive until the sheet-based print operation's
    /// did-run callback — `runModal(for:...)` returns immediately, so
    /// without this the view could be released mid-print.
    @MainActor
    private final class PrintSession: NSObject {
        let container: PrintContainerView
        var operation: NSPrintOperation?

        init(container: PrintContainerView) {
            self.container = container
        }

        // NSPrintOperation invokes the did-run selector on the main thread.
        @objc func printOperationDidRun(
            _ printOperation: NSPrintOperation,
            success: Bool,
            contextInfo: UnsafeMutableRawPointer?
        ) {
            PrintController.activeSession = nil
        }
    }

    private static var activeSession: PrintSession?

    private static func runOperation(
        container: PrintContainerView,
        printInfo: NSPrintInfo,
        request: Request
    ) {
        let op = NSPrintOperation(view: container, printInfo: printInfo)
        op.jobTitle = request.jobTitle
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling])

        if let parent = request.window {
            let session = PrintSession(container: container)
            session.operation = op
            activeSession = session
            op.runModal(
                for: parent,
                delegate: session,
                didRun: #selector(PrintSession.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        } else {
            op.run()
        }
    }
}

// MARK: - Per-block print view

/// Print-side equivalent of ContentView.blockView: the plain Markdown path
/// only (no find highlights, hover stripes, or selection tints), scale
/// fixed at 1.0 regardless of screen zoom, remote images forced to the
/// blocked placeholder so nothing in the tree depends on async work.
private struct PrintBlockView: View {
    let markdown: String
    let mermaidImage: NSImage?
    let theme: MDVTheme
    let baseURL: URL?

    var body: some View {
        if let image = mermaidImage {
            // Mirrors MermaidCodeBlockChrome.diagramChrome / diagramBody
            // (unzoomed), minus the hover toolbar.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(
                    image.size.height > 0 ? image.size.width / image.size.height : 1,
                    contentMode: .fit
                )
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(theme.resolvedCodePalette.background ?? theme.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Markdown(markdown)
                .markdownTheme(theme.markdownTheme(scale: 1.0, forPrint: true))
                .markdownCodeSyntaxHighlighter(.mdv(theme: theme))
                .markdownImageProvider(LocalImageProvider(
                    baseURL: baseURL,
                    loadRemoteImages: false
                ))
        }
    }
}

// MARK: - Container view

/// Flipped canvas that composites the per-block vector PDF pages in
/// `draw(_:)`. Pagination happens here: AppKit proposes a page bottom and
/// `adjustPageHeightNew` moves it up to the nearest block boundary when a
/// block would otherwise be sliced.
final class PrintContainerView: NSView {
    struct BlockRender {
        /// Container coordinates (flipped: y grows downward), sorted top-down.
        let frame: NSRect
        /// Retained so `page` stays valid — a CGPDFPage does not retain its
        /// parent document, and dropping the document frees the page's bytes.
        let document: CGPDFDocument
        let page: CGPDFPage
    }

    var blockRenders: [BlockRender] = []
    var pageBackground: NSColor = .white
    var jobTitle: String = "mdv"

    override var isFlipped: Bool { true }

    /// Feeds AppKit's standard print header.
    override var printJobTitle: String { jobTitle }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        pageBackground.setFill()
        dirtyRect.fill()
        for block in blockRenders where block.frame.intersects(dirtyRect) {
            ctx.saveGState()
            // Block PDFs are y-up; the container is flipped. Anchor at the
            // block's bottom edge and flip back to PDF coordinates.
            ctx.translateBy(x: block.frame.minX, y: block.frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.drawPDFPage(block.page)
            ctx.restoreGState()
        }
    }

    /// How far a page break may be pulled up, as a fraction of the page.
    /// AppKit's default is 0.2 — any block-boundary push larger than 20%
    /// of a page would be clamped and the block sliced anyway. 0.9 lets
    /// blocks up to ~90% of a page move wholesale to the next page.
    override var heightAdjustLimit: CGFloat { 0.9 }

    /// Flipped coordinates: y grows downward, `top < bottom`. `limit` is
    /// the highest allowed break (`top + (1 − heightAdjustLimit) × pageHeight`)
    /// — except on the document's final partial page, where AppKit still
    /// computes it from the full page height and it can land BEYOND
    /// `bottom`. The returned value must never exceed `bottom` ("*new not
    /// set or increased" assertion), so the bottom clamp is applied last.
    /// A block that straddles the proposed break and fits on a single page
    /// moves wholesale to the next page; blocks taller than a page (or
    /// starting exactly at the page top) slice at the default break.
    override func adjustPageHeightNew(
        _ newBottom: UnsafeMutablePointer<CGFloat>,
        top oldTop: CGFloat,
        bottom oldBottom: CGFloat,
        limit bottomLimit: CGFloat
    ) {
        var proposed = oldBottom
        let pageHeight = oldBottom - oldTop
        for block in blockRenders {
            let frame = block.frame
            if frame.minY >= oldBottom { break }       // below the break — done
            guard frame.maxY > oldBottom else { continue }  // fully above
            // This block straddles the proposed page break.
            if frame.height <= pageHeight && frame.minY > oldTop {
                proposed = frame.minY
            }
            break
        }
        newBottom.pointee = min(max(proposed, bottomLimit), oldBottom)
    }
}
