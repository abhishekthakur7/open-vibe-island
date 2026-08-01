import Foundation
import Testing
@testable import OpenIslandApp

@Suite
struct HarnessArtifactRecorderTests {
    @Test(arguments: [
        ("AXTitle", "AXDescription", "AXHelp", "AXTitle", HarnessArtifactReport.AccessibilityNode.AccessibleNameSource.title),
        (nil, "AXDescription", "AXHelp", "AXDescription", HarnessArtifactReport.AccessibilityNode.AccessibleNameSource.description),
        ("  ", "AXDescription", "AXHelp", "AXDescription", HarnessArtifactReport.AccessibilityNode.AccessibleNameSource.description),
    ])
    func buttonAccessibleNamePrefersTitleThenDescriptionNeverHelp(
        title: String?,
        description: String?,
        help: String,
        expectedName: String,
        expectedSource: HarnessArtifactReport.AccessibilityNode.AccessibleNameSource
    ) {
        let resolved = HarnessArtifactReport.AccessibilityNode.resolvedAccessibleName(
            role: "AXButton",
            title: title,
            description: description
        )

        #expect(resolved?.name == expectedName)
        #expect(resolved?.source == expectedSource)
        #expect(resolved?.name != help)
    }
}
