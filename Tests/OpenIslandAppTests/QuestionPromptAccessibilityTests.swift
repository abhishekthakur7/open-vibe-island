import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite
struct QuestionPromptAccessibilityTests {
    private static func islandPanelViewSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/OpenIslandApp/Views/IslandPanelView.swift"),
            encoding: .utf8
        )
    }

    /// Poured parity Slice 5 · `PI-A11Y-001` part F. The shared question
    /// interior used to read **no** accessibility environment at all — the §F
    /// hero's only adaptation was the gold wash flattening one level up in
    /// `PouredSessionRow.questionHeroWash`, so the option chrome, selection ring
    /// and digit chips inside the hero never responded to Increase Contrast or
    /// Reduce Transparency.
    ///
    /// A source scan rather than a rendered assertion because SwiftUI
    /// `@Environment` reads aren't observable from a test without a host — the
    /// same reason `primaryActionIdentifier` below is pinned this way. What it
    /// buys is the regression guard: deleting either read silently reopens the
    /// gap.
    @Test
    func questionInteriorReadsTheAccessibilityEnvironment() throws {
        let source = try Self.islandPanelViewSource()
        let interior = try #require(
            source.range(of: "struct StructuredQuestionPromptView: View {").map {
                String(source[$0.lowerBound...])
            }
        )

        #expect(interior.contains("@Environment(\\.accessibilityReduceTransparency) private var reduceTransparency"))
        #expect(interior.contains("@Environment(\\.colorSchemeContrast) private var colorSchemeContrast"))
    }

    /// The `.q-head` seam Poured's hero wrapper injects its session-scoped
    /// facts through (Slice 5 §F). Value semantics only — the rendering itself
    /// lives behind `isPoured` in the shared interior.
    @Test
    func headContextCarriesTheWorkspaceAndBrandTint() {
        let context = QuestionPromptHeadContext(workspaceName: "niche-radar", brandColor: .orange)
        #expect(context.workspaceName == "niche-radar")
        #expect(context == QuestionPromptHeadContext(workspaceName: "niche-radar", brandColor: .orange))
        #expect(context != QuestionPromptHeadContext(workspaceName: "the-automator", brandColor: .orange))
    }

    @Test
    func primaryActionIdentifierIsStableAndAppliedOnlyAtSharedSubmitSeam() throws {
        #expect(
            QuestionPromptAccessibility.primaryActionIdentifier
                == "open-island.question.primary-action"
        )

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/OpenIslandApp/Views/IslandPanelView.swift"),
            encoding: .utf8
        )
        let identifierApplication = ".accessibilityIdentifier(QuestionPromptAccessibility.primaryActionIdentifier)"

        // The themed and fallback branches are mutually exclusive, so every
        // rendered prompt has one identified primary action, never two.
        #expect(source.components(separatedBy: identifierApplication).count - 1 == 2)
    }
}
