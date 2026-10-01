import AppKit
import XCTest
@testable import mdv

final class DocumentSelectionTests: XCTestCase {
    func testPartialSelectionSpansSeveralRenderedBlocksInEitherDirection() {
        var selection = DocumentTextSelection(text: ["First paragraph", "Second heading", "Last paragraph"])
        selection.anchor = .init(block: 0, offset: 6)
        selection.extent = .init(block: 2, offset: 4)
        XCTAssertEqual(selection.copiedText, "paragraph\n\nSecond heading\n\nLast")
        XCTAssertEqual(selection.range(in: 1), NSRange(location: 0, length: 14))
        let start = selection.anchor
        selection.anchor = selection.extent
        selection.extent = start
        XCTAssertEqual(selection.copiedText, "paragraph\n\nSecond heading\n\nLast")
    }

    func testSelectionIncludesSeparatorsBetweenBlockBoundaries() {
        var selection = DocumentTextSelection(text: ["First", "Second"])
        selection.anchor = .init(block: 0, offset: 5)
        selection.extent = .init(block: 1, offset: 0)
        XCTAssertEqual(selection.copiedText, "\n\n")
    }

    func testUnicodeOffsetsAndTableCells() {
        let first = "café 👩🏽‍💻" as NSString
        let last = "Name\tValue\nAlpha\t123"
        var selection = DocumentTextSelection(text: [first as String, last])
        selection.anchor = .init(block: 0, offset: first.range(of: "👩🏽‍💻").location)
        selection.extent = .init(block: 1, offset: (last as NSString).range(of: "123").location)
        XCTAssertEqual(selection.copiedText, "👩🏽‍💻\n\nName\tValue\nAlpha\t")
    }

    func testMountingEarlierLazyBlocksDoesNotMoveSelection() {
        var selection = DocumentTextSelection(text: ["Fallback", "Start here", "End here"])
        selection.anchor = .init(block: 1, offset: 6)
        selection.extent = .init(block: 2, offset: 3)
        selection.text[0] = "A much longer rendered text snapshot"
        XCTAssertEqual(selection.copiedText, "here\n\nEnd")
        XCTAssertNil(selection.range(in: 0))
    }

    @MainActor func testSelectAllIncludesUnmountedDocumentText() {
        let view = DocumentSelection.SelectionView()
        let blocks = ["# Heading", "Paragraph with **bold** text.", "```swift\nlet x = 42\n```", "Last paragraph"]
        view.updateDocument(blocks: blocks, identity: "one.md", smartTypography: false)
        // No window or rendered NSTextFields: every block is offscreen.
        view.selectAll(nil)
        XCTAssertTrue(view.selection.copiedText.contains("Heading"))
        XCTAssertTrue(view.selection.copiedText.contains("let x = 42"))
        XCTAssertTrue(view.selection.copiedText.contains("Last paragraph"))
        XCTAssertFalse(view.selection.copiedText.contains("**bold**"))
        XCTAssertFalse(view.selection.copiedText.contains("```"))
    }

    @MainActor func testDiagramFallbackPreservesFollowingProse() {
        let view = DocumentSelection.SelectionView()
        view.updateDocument(blocks: ["~~~Mermaid\ngraph TD; A-->B\n~~~\nFollowing paragraph"], identity: "diagram.md", smartTypography: false)
        view.selectAll(nil)
        XCTAssertEqual(view.selection.copiedText, "Following paragraph")
    }

    @MainActor func testChangingDocumentsClearsSelection() {
        let view = DocumentSelection.SelectionView()
        view.updateDocument(blocks: ["Same content"], identity: "one.md", smartTypography: false)
        view.selectAll(nil)
        XCTAssertTrue(view.hasSelection)
        view.updateDocument(blocks: ["Same content"], identity: "two.md", smartTypography: false)
        XCTAssertFalse(view.hasSelection)
        XCTAssertEqual(view.selection.copiedText, "")
    }
}
