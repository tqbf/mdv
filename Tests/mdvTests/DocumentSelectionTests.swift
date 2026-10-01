import AppKit
import XCTest
@testable import mdv

final class DocumentSelectionTests: XCTestCase {
    @MainActor func testResizeDoesNotReenterAndKeepsOneTextContainer() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let text = DocumentTextView(frame: scroll.bounds)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.textContainer?.widthTracksTextView = false
        scroll.documentView = text
        text.articleWidth = 620
        text.resizeArticle()
        XCTAssertEqual(text.textContainer?.containerSize.width, 540)
        text.setFrameSize(NSSize(width: 400, height: 800))
        text.resizeArticle()
        XCTAssertEqual(text.layoutManager?.textContainers.count, 1)
    }

    @MainActor func testContinuousSelectionIncludesOffscreenText() {
        let blocks = ["# Heading", "First paragraph with **bold** text.", "Second paragraph with café 👩🏽‍💻.", "```swift\nlet x = 42\n```", String(repeating: "Last paragraph. ", count: 200)]
        let document = NativeMarkdownDocument.render(blocks: blocks, theme: MDVTheme.all[0], scale: 1)
        let text = DocumentTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 200))
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = text
        window.makeFirstResponder(text)
        text.isEditable = false
        text.isSelectable = true
        text.textStorage?.setAttributedString(document.text)
        XCTAssertTrue(text.string.contains("Heading"))
        XCTAssertFalse(text.string.contains("**bold**"))
        XCTAssertTrue(text.string.contains("let x = 42"))
        XCTAssertFalse(text.string.contains("-END"))
        let string = text.string as NSString
        let start = string.range(of: "paragraph").location
        let end = NSMaxRange(string.range(of: "café 👩🏽‍💻"))
        text.setSelectedRange(NSRange(location: start, length: end - start))
        let selected = string.substring(with: text.selectedRange())
        XCTAssertTrue(selected.hasPrefix("paragraph with bold text."))
        XCTAssertTrue(selected.hasSuffix("café 👩🏽‍💻"))
        XCTAssertTrue(selected.contains("Second paragraph"))
        text.selectAll(nil)
        XCTAssertEqual(text.selectedRange(), NSRange(location: 0, length: string.length))
        var mapped = Set<Int>()
        document.text.enumerateAttribute(.documentBlock, in: NSRange(location: 0, length: document.text.length)) { value, _, _ in
            if let index = value as? Int { mapped.insert(index) }
        }
        XCTAssertEqual(mapped, Set(blocks.indices))
    }

    @MainActor func testTablePreservesCells() {
        let markdown = "| Name | Value |\n| --- | --- |\n| Alpha | 123 |\n| Beta | 456 |"
        let html = NativeMarkdownDocument.renderHTML(markdown)
        XCTAssertTrue(html.contains("<th>Name</th>"))
        XCTAssertTrue(html.contains("<td>123</td>"))
        let rendered = NativeMarkdownDocument.render(blocks: [markdown], theme: MDVTheme.all[0], scale: 1)
        let index = (rendered.text.string as NSString).range(of: "123").location
        XCTAssertNotEqual(index, NSNotFound)
        let paragraph = rendered.text.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertTrue(paragraph?.textBlocks.first is NSTextTableBlock)
    }

    @MainActor func testDiagramDoesNotSwallowFollowingParagraph() {
        let document = NativeMarkdownDocument.render(blocks: ["```mermaid\ngraph TD\n A --> B\n```\nText immediately after the fence."], theme: .default, scale: 1)
        XCTAssertTrue(document.text.string.contains("Text immediately after the fence."))
        XCTAssertEqual(document.images.first?.mermaid, "graph TD\n A --> B\n")
    }

    @MainActor func testLinksKeepRelativeAndFragmentDestinations() {
        let document = NativeMarkdownDocument.render(blocks: ["[heading](#second-heading) and [file](other.md#anchor) and [web](https://example.com/?a=1&b=2)"], theme: .default, scale: 1)
        var links: [String] = []
        document.text.enumerateAttribute(.link, in: NSRange(location: 0, length: document.text.length)) { value, _, _ in
            if let url = value as? URL { links.append(url.absoluteString) }
        }
        XCTAssertEqual(links, ["#second-heading", "other.md#anchor", "https://example.com/?a=1&b=2"])
    }

    @MainActor func testImagesAreNotFetchedByHTMLImporter() {
        let document = NativeMarkdownDocument.render(blocks: ["![remote](https://127.0.0.1:1/pixel.png?a=1&b=2)", "<script>alert('no')</script>"], theme: MDVTheme.all[0], scale: 1)
        XCTAssertEqual(document.images.count, 1)
        XCTAssertEqual(document.images.first?.url, "https://127.0.0.1:1/pixel.png?a=1&b=2")
        XCTAssertTrue(document.text.string.contains("remote"))
        XCTAssertFalse(document.text.string.contains("alert"))
    }
}
