import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
struct IslandDiffRendererTests {
    @Test
    func rowModelAlwaysCarriesGutterAndDedicatedMarker() {
        let result = PermissionDiffResult(lines: [
            PermissionDiffLine(kind: .unchanged, text: "+ source text is not a marker"),
            PermissionDiffLine(kind: .removed, text: "- source text is not a marker"),
            PermissionDiffLine(kind: .added, text: "plain replacement"),
        ], addedCount: 1, removedCount: 1)

        let rows = IslandDiffRenderer.rows(for: result)

        #expect(rows.map(\.gutter) == [1, 2, 2])
        #expect(rows.map(\.marker) == ["", "\u{2212}", "+"])
        #expect(rows.map(\.line.text) == ["+ source text is not a marker", "- source text is not a marker", "plain replacement"])
    }

    @Test
    func rowModelCapsAtFiveHundredLines() {
        let lines = (0..<IslandDiffRenderer.maxRenderedLines + 1).map {
            PermissionDiffLine(kind: .unchanged, text: "line \($0)")
        }
        let result = PermissionDiffResult(lines: lines, addedCount: 0, removedCount: 0)

        #expect(IslandDiffRenderer.rows(for: result).count == 500)
        #expect(IslandDiffRenderer.maxHeight == 180)
    }
}
