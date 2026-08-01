import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct SystemNotificationPolicyTests {
    @Test
    func completionEventsNeverPostRegardlessOfScreen() {
        #expect(!SystemNotificationPolicy.shouldPost(eventKind: .completion, overlayScreenID: "A", activeScreenID: "B"))
        #expect(!SystemNotificationPolicy.shouldPost(eventKind: .completion, overlayScreenID: nil, activeScreenID: nil))
    }

    @Test
    func permissionEventsPostOnlyWhenUserIsOnADifferentScreen() {
        #expect(!SystemNotificationPolicy.shouldPost(eventKind: .permission, overlayScreenID: "A", activeScreenID: "A"))
        #expect(SystemNotificationPolicy.shouldPost(eventKind: .permission, overlayScreenID: "A", activeScreenID: "B"))
    }

    /// A missed attention notification is worse than an occasional redundant
    /// one, so an unresolved screen id (either side) defaults to posting.
    @Test
    func unresolvedScreensDefaultToPosting() {
        #expect(SystemNotificationPolicy.shouldPost(eventKind: .permission, overlayScreenID: nil, activeScreenID: "B"))
        #expect(SystemNotificationPolicy.shouldPost(eventKind: .question, overlayScreenID: "A", activeScreenID: nil))
        #expect(SystemNotificationPolicy.shouldPost(eventKind: .permission, overlayScreenID: nil, activeScreenID: nil))
    }
}
