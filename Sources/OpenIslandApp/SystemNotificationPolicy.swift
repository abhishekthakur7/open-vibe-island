/// Decides whether a permission/question event is worth interrupting the
/// user with a macOS system notification (AB-239 #2).
///
/// Kept pure and free of `UNUserNotificationCenter` so it can be unit tested
/// in isolation — `swift test` runs outside an app bundle, and
/// `UNUserNotificationCenter` requires one, so nothing here may touch it.
///
/// Frontmost-session suppression (`AppModel.suppressFrontmostNotifications`)
/// is handled upstream, before `AppModel.presentNotificationSurface` (and
/// therefore this policy) is ever consulted — see
/// `scheduleNotificationSurfacePresentationIfNeeded`. This function only
/// adds the AB-239-specific "is the user actually looking at the overlay's
/// display" check on top of that.
enum SystemNotificationPolicy {
    /// - Parameters:
    ///   - eventKind: The event driving this notification card. Completion
    ///     events never post a system notification, per the ticket's scope
    ///     (only permission/question events do); pass `nil` for phases that
    ///     never reach a notification card (`.running`) — also never posts.
    ///   - overlayScreenID: The screen the overlay currently targets
    ///     (`OverlayPlacementDiagnostics.targetScreenID`).
    ///   - activeScreenID: A best-effort id of the screen the user is
    ///     currently on (see `OverlayDisplayResolver.activeScreenID`).
    static func shouldPost(
        eventKind: NotificationEventKind?,
        overlayScreenID: String?,
        activeScreenID: String?
    ) -> Bool {
        guard eventKind == .permission || eventKind == .question else {
            return false
        }

        // If either screen can't be resolved, default to posting — a missed
        // attention notification is worse than an occasional redundant one.
        guard let overlayScreenID, let activeScreenID else {
            return true
        }

        return overlayScreenID != activeScreenID
    }
}
