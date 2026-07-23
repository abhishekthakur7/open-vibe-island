import Foundation

/// A single rendered line in a computed diff (AB-235). `unchanged` lines are
/// kept (rather than collapsed) so the approval card can show a little
/// surrounding context around each change.
public struct PermissionDiffLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case unchanged
        case added
        case removed
    }

    public var kind: Kind
    public var text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Line-level diff result: the rendered lines plus the +/- counts the
/// approval card surfaces as e.g. "Updated (+8 −23)".
public struct PermissionDiffResult: Equatable, Sendable {
    public var lines: [PermissionDiffLine]
    public var addedCount: Int
    public var removedCount: Int

    public init(lines: [PermissionDiffLine], addedCount: Int, removedCount: Int) {
        self.lines = lines
        self.addedCount = addedCount
        self.removedCount = removedCount
    }

    /// True when there is nothing to show — old and new text were identical
    /// (or both empty). Callers use this to suppress the diff card entirely.
    public var isEmpty: Bool {
        addedCount == 0 && removedCount == 0
    }
}

/// Small, self-contained line-based diff used to render inline diffs for
/// Edit/Write permission requests (AB-235). Deliberately simple — it
/// compares whole lines via a classic LCS dynamic-programming table, which
/// is enough for the approval card's "what would change" preview. Not
/// intended as a general-purpose diff library (no word-level diffing, no
/// move detection).
public enum PermissionDiff {
    /// Above this many (old-lines * new-lines) table cells, the O(n*m)
    /// LCS table would be too slow/memory-hungry to compute synchronously
    /// on the main actor while rendering a view. Fall back to a naive
    /// "everything removed, then everything added" diff instead — the
    /// +/- counts are still correct, just without line-level matching.
    static let maxComparisonCells = 4_000_000

    public static func compute(oldText: String, newText: String) -> PermissionDiffResult {
        let oldLines = splitLines(oldText)
        let newLines = splitLines(newText)

        if oldLines.isEmpty, newLines.isEmpty {
            return PermissionDiffResult(lines: [], addedCount: 0, removedCount: 0)
        }

        if oldLines == newLines {
            let lines = oldLines.map { PermissionDiffLine(kind: .unchanged, text: $0) }
            return PermissionDiffResult(lines: lines, addedCount: 0, removedCount: 0)
        }

        if oldLines.isEmpty {
            let lines = newLines.map { PermissionDiffLine(kind: .added, text: $0) }
            return PermissionDiffResult(lines: lines, addedCount: newLines.count, removedCount: 0)
        }

        if newLines.isEmpty {
            let lines = oldLines.map { PermissionDiffLine(kind: .removed, text: $0) }
            return PermissionDiffResult(lines: lines, addedCount: 0, removedCount: oldLines.count)
        }

        guard oldLines.count * newLines.count <= maxComparisonCells else {
            var lines = oldLines.map { PermissionDiffLine(kind: .removed, text: $0) }
            lines.append(contentsOf: newLines.map { PermissionDiffLine(kind: .added, text: $0) })
            return PermissionDiffResult(lines: lines, addedCount: newLines.count, removedCount: oldLines.count)
        }

        return lcsDiff(oldLines: oldLines, newLines: newLines)
    }

    private static func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.components(separatedBy: "\n")
    }

    /// Classic LCS table (`table[i][j]` = length of the longest common
    /// subsequence of `oldLines[i...]` and `newLines[j...]`), backtracked
    /// from `(0, 0)` into a line-by-line hunk list.
    private static func lcsDiff(oldLines: [String], newLines: [String]) -> PermissionDiffResult {
        let oldCount = oldLines.count
        let newCount = newLines.count

        var table = [[Int32]](repeating: [Int32](repeating: 0, count: newCount + 1), count: oldCount + 1)
        for i in stride(from: oldCount - 1, through: 0, by: -1) {
            for j in stride(from: newCount - 1, through: 0, by: -1) {
                if oldLines[i] == newLines[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var lines: [PermissionDiffLine] = []
        var addedCount = 0
        var removedCount = 0
        var i = 0
        var j = 0

        while i < oldCount, j < newCount {
            if oldLines[i] == newLines[j] {
                lines.append(PermissionDiffLine(kind: .unchanged, text: oldLines[i]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                lines.append(PermissionDiffLine(kind: .removed, text: oldLines[i]))
                removedCount += 1
                i += 1
            } else {
                lines.append(PermissionDiffLine(kind: .added, text: newLines[j]))
                addedCount += 1
                j += 1
            }
        }
        while i < oldCount {
            lines.append(PermissionDiffLine(kind: .removed, text: oldLines[i]))
            removedCount += 1
            i += 1
        }
        while j < newCount {
            lines.append(PermissionDiffLine(kind: .added, text: newLines[j]))
            addedCount += 1
            j += 1
        }

        return PermissionDiffResult(lines: lines, addedCount: addedCount, removedCount: removedCount)
    }
}
