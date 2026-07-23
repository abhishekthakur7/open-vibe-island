import Foundation
import Testing
@testable import OpenIslandCore

/// AB-235: unit tests for the line-based diff computer that powers the
/// approval card's inline diff preview for Edit/Write permission requests.
struct PermissionDiffTests {
    @Test
    func identicalTextProducesEmptyResult() {
        let result = PermissionDiff.compute(oldText: "same\nlines", newText: "same\nlines")

        #expect(result.isEmpty)
        #expect(result.addedCount == 0)
        #expect(result.removedCount == 0)
        #expect(result.lines.allSatisfy { $0.kind == .unchanged })
    }

    @Test
    func bothEmptyProducesEmptyResult() {
        let result = PermissionDiff.compute(oldText: "", newText: "")

        #expect(result.isEmpty)
        #expect(result.lines.isEmpty)
    }

    @Test
    func writeStyleAllContentTreatedAsAdded() {
        // Write's tool_input only carries `content` — no "before" text — so
        // the whole thing renders as added, matching `permissionFileDiffSource`'s
        // `oldText: ""` convention for the Write tool.
        let result = PermissionDiff.compute(oldText: "", newText: "line one\nline two\nline three")

        #expect(!result.isEmpty)
        #expect(result.addedCount == 3)
        #expect(result.removedCount == 0)
        #expect(result.lines.allSatisfy { $0.kind == .added })
        #expect(result.lines.map(\.text) == ["line one", "line two", "line three"])
    }

    @Test
    func emptyNewTextTreatedAsAllRemoved() {
        let result = PermissionDiff.compute(oldText: "line one\nline two", newText: "")

        #expect(result.addedCount == 0)
        #expect(result.removedCount == 2)
        #expect(result.lines.allSatisfy { $0.kind == .removed })
    }

    @Test
    func editStyleReplacementProducesCountsMatchingTheReferenceExample() {
        // Mirrors the ticket's own example: a compact edit with an
        // "Updated (+N −M)" summary distinct from the raw line count.
        let old = (1...23).map { "old line \($0)" }.joined(separator: "\n")
        let new = (1...8).map { "new line \($0)" }.joined(separator: "\n")

        let result = PermissionDiff.compute(oldText: old, newText: new)

        #expect(result.addedCount == 8)
        #expect(result.removedCount == 23)
    }

    @Test
    func singleLineChangeInTheMiddlePreservesSurroundingContextAsUnchanged() {
        let old = "line1\nline2\nline3"
        let new = "line1\nlineTWO\nline3"

        let result = PermissionDiff.compute(oldText: old, newText: new)

        #expect(result.addedCount == 1)
        #expect(result.removedCount == 1)
        #expect(result.lines.map(\.kind) == [.unchanged, .removed, .added, .unchanged])
        #expect(result.lines.map(\.text) == ["line1", "line2", "lineTWO", "line3"])
    }

    @Test
    func purelyAdditiveChangeHasNoRemovedLines() {
        let old = "line1\nline2"
        let new = "line1\nline2\nline3"

        let result = PermissionDiff.compute(oldText: old, newText: new)

        #expect(result.addedCount == 1)
        #expect(result.removedCount == 0)
        #expect(result.lines.map(\.kind) == [.unchanged, .unchanged, .added])
    }

    @Test
    func fallsBackToNaiveDiffWhenAboveTheComparisonCellCap() {
        // Two large-but-different texts whose line-count product exceeds
        // `PermissionDiff.maxComparisonCells` must not attempt the O(n*m)
        // LCS table — falls back to "everything removed, then everything
        // added" so counts stay correct without the expensive table.
        let lineCount = 2_100
        let old = (0..<lineCount).map { "old-\($0)" }.joined(separator: "\n")
        let new = (0..<lineCount).map { "new-\($0)" }.joined(separator: "\n")
        #expect(lineCount * lineCount > PermissionDiff.maxComparisonCells)

        let result = PermissionDiff.compute(oldText: old, newText: new)

        #expect(result.addedCount == lineCount)
        #expect(result.removedCount == lineCount)
        #expect(result.lines.prefix(lineCount).allSatisfy { $0.kind == .removed })
        #expect(result.lines.suffix(lineCount).allSatisfy { $0.kind == .added })
    }
}
