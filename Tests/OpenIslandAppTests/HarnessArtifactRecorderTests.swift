import Foundation
import Testing
@testable import OpenIslandApp

@Suite
struct HarnessArtifactRecorderTests {
    @Test
    @MainActor
    func boolValueAcceptsCFBooleans() {
        #expect(HarnessArtifactRecorder.boolValue(from: kCFBooleanTrue) == true)
        #expect(HarnessArtifactRecorder.boolValue(from: kCFBooleanFalse) == false)
    }

    @Test(arguments: [NSNumber(value: 0), NSNumber(value: 1), NSNumber(value: 2)])
    @MainActor
    func boolValueRejectsNumericNSNumbers(_ value: NSNumber) {
        #expect(HarnessArtifactRecorder.boolValue(from: value) == nil)
    }

    @Test(arguments: ["true", "false"])
    @MainActor
    func boolValueRejectsStrings(_ value: String) {
        #expect(HarnessArtifactRecorder.boolValue(from: value) == nil)
    }

    @Test
    func accessibilityNodeKeepsRawAXAttributesSeparateFromLegacyLabel() throws {
        let node = HarnessArtifactReport.AccessibilityNode(
            typeName: "AXUIElement",
            role: "AXButton",
            subrole: nil,
            identifier: "open-island.question.primary-action",
            title: "Submit & next",
            description: "Advances to the next question",
            help: "Requires an answer",
            enabled: false,
            accessibleName: "Submit & next",
            accessibleNameSource: .title,
            label: "Submit & next",
            value: nil,
            children: []
        )

        let data = try JSONEncoder().encode(node)
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["identifier"] as? String == "open-island.question.primary-action")
        #expect(object["title"] as? String == "Submit & next")
        #expect(object["description"] as? String == "Advances to the next question")
        #expect(object["help"] as? String == "Requires an answer")
        #expect(object["enabled"] as? Bool == false)
        #expect(object["accessibleName"] as? String == "Submit & next")
        #expect(object["accessibleNameSource"] as? String == "AXTitle")
        #expect(object["label"] as? String == "Submit & next")
    }

    @Test
    func accessibilityNodeDecodesLegacyArtifactsWithoutRawAXAttributes() throws {
        let data = Data(
            """
            {
              "typeName": "AXUIElement",
              "role": "AXButton",
              "subrole": null,
              "label": "Submit & next",
              "value": null,
              "children": []
            }
            """.utf8
        )

        let node = try JSONDecoder().decode(
            HarnessArtifactReport.AccessibilityNode.self,
            from: data
        )

        #expect(node.title == nil)
        #expect(node.description == nil)
        #expect(node.help == nil)
        #expect(node.enabled == nil)
        #expect(node.identifier == nil)
        #expect(node.accessibleName == nil)
        #expect(node.accessibleNameSource == nil)
        #expect(node.label == "Submit & next")
    }

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

    @Test
    func accessibleNameIsAbsentForNonButtonsAndHelpOnlyButtons() {
        #expect(
            HarnessArtifactReport.AccessibilityNode.resolvedAccessibleName(
                role: "AXStaticText",
                title: "Submit & next",
                description: nil
            ) == nil
        )
        #expect(
            HarnessArtifactReport.AccessibilityNode.resolvedAccessibleName(
                role: "AXButton",
                title: nil,
                description: nil
            ) == nil
        )
    }
}
