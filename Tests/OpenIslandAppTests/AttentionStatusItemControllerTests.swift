import AppKit
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
struct AttentionStatusItemControllerTests {
    @Test
    func entryTitleDistinguishesQuestionsFromPermissions() {
        let lang = LanguageManager.shared
        let session = AgentSession(
            id: "s2",
            title: "Claude · repo",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForAnswer,
            summary: "Pick one",
            updatedAt: .now
        )

        let title = AttentionStatusItemController.entryTitle(for: session, lang: lang)
        #expect(title.contains(lang.t("island.section.needsAnswer")))
        #expect(!title.contains(lang.t("island.section.needsApproval")))
    }

    @Test
    func setEnabledTogglesTheStatusItemLifecycle() {
        let controller = AttentionStatusItemController()

        controller.setEnabled(true)
        #expect(controller.isEnabled)

        controller.setEnabled(true)
        #expect(controller.isEnabled, "Re-enabling while already enabled must stay a no-op, not recreate the item.")

        controller.setEnabled(false)
        #expect(!controller.isEnabled)
    }

    @Test
    func selectingAMenuEntryInvokesTheCallbackWithItsSessionID() {
        let controller = AttentionStatusItemController()
        var selectedID: String?
        controller.onSelectSession = { selectedID = $0 }

        // Drives the exact same handler the real `NSMenuItem` target/action
        // wiring calls (see `buildMenu`), without depending on
        // `NSStatusItem.menu`'s live internal item instances.
        let item = NSMenuItem(title: "Codex · repo", action: nil, keyEquivalent: "")
        item.representedObject = "s5"
        controller.handleSelect(item)

        #expect(selectedID == "s5")
    }
}
