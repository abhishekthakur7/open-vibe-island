import Foundation
import Testing
@testable import OpenIslandApp

@Suite
struct QuestionPromptAccessibilityTests {
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
