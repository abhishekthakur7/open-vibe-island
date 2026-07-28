import XCTest

@testable import OpenIslandApp

@MainActor
final class NativeMarkdownTextTests: XCTestCase {
    func testMultilineParagraphsRemainSeparateBlocks() {
        XCTAssertEqual(
            LocalMarkdownText.blocks(for: "Kimi.\n2 files changed\n\nSupport matrix updated."),
            [
                .paragraph("Kimi. 2 files changed"),
                .paragraph("Support matrix updated."),
            ]
        )
    }

    func testUnorderedAndOrderedListsPreserveItemsAndMarkers() {
        XCTAssertEqual(
            LocalMarkdownText.blocks(for: "- first\n* second\n\n1. prepare\n2) ship"),
            [
                .unorderedList(["first", "second"]),
                .orderedList([
                    .init(ordinal: 1, text: "prepare"),
                    .init(ordinal: 2, text: "ship"),
                ]),
            ]
        )
    }

    func testHeadingCodeAndBlockquoteRemainDistinctBlocks() {
        XCTAssertEqual(
            LocalMarkdownText.blocks(for: "## Status\n\n> Review locally\n> before merging\n\n```swift\nprint(\"ok\")\n```"),
            [
                .heading(level: 2, text: "Status"),
                .quote("Review locally\nbefore merging"),
                .code("print(\"ok\")"),
            ]
        )
    }

    func testImageMarkdownUsesAltTextWithoutItsURL() {
        let blocks = LocalMarkdownText.blocks(
            for: "Hello **world** — ![tracking pixel](https://example.invalid/pixel.png)"
        )

        XCTAssertEqual(blocks, [.paragraph("Hello **world** — tracking pixel")])
        XCTAssertFalse(String(describing: blocks).contains("example.invalid"))
    }
}
