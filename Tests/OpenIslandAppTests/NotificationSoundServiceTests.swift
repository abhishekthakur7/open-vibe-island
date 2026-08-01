import Foundation
import Testing
@testable import OpenIslandApp

/// AB-239: previously every event played `NotificationSoundService.selectedSoundName`.
/// These tests cover the per-event replacement, especially the upgrade path —
/// an existing user's single sound choice must keep applying to every event
/// until they customize one individually, so today's behavior is unchanged
/// by default.
@MainActor
@Suite(.serialized)
struct NotificationSoundServiceTests {
    init() {
        [
            "notification.sound.name",
            "notification.sound.name.permission",
            "notification.sound.name.question",
            "notification.sound.name.completion",
        ].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    @Test
    func legacySingleSoundSeedsAllThreeEventsUntilCustomized() {
        UserDefaults.standard.set("Glass", forKey: "notification.sound.name")

        #expect(NotificationSoundService.soundName(for: .permission) == "Glass")
        #expect(NotificationSoundService.soundName(for: .question) == "Glass")
        #expect(NotificationSoundService.soundName(for: .completion) == "Glass")

        NotificationSoundService.setSoundName("Pop", for: .question)

        #expect(NotificationSoundService.soundName(for: .question) == "Pop")
        // Untouched events keep reading through to the legacy preference.
        #expect(NotificationSoundService.soundName(for: .permission) == "Glass")
        #expect(NotificationSoundService.soundName(for: .completion) == "Glass")
    }
}
