import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter` for AB-239's optional
/// system notifications.
///
/// Authorization is requested lazily — only from `AppModel.systemNotificationsEnabled`'s
/// `didSet`, i.e. only when the user actually turns "System notifications"
/// on in Settings — never at launch or from this type's initializer, so
/// enabling the feature is the only thing that can trigger the OS
/// permission prompt.
///
/// `center` is `lazy` so simply constructing this service (as `AppModel`
/// always does, even with the feature off) never touches
/// `UNUserNotificationCenter.current()`. That API expects a proper app
/// bundle/entitlement, which `swift test`'s bare executable doesn't have —
/// deferring first access until a real post/authorization call keeps every
/// existing `AppModel()`-constructing test safe.
@MainActor
final class UserNotificationService: NSObject {
    nonisolated static let sessionIDUserInfoKey = "openisland.sessionID"
    private static let identifierPrefix = "com.openisland.attention."

    /// Invoked when the user clicks a posted notification, with the session
    /// ID it was about. `AppModel` wires this to `presentOverlayFocused(onSessionID:)`
    /// so the click opens the overlay on the configured display, focused on
    /// that session.
    var onNotificationClicked: ((String) -> Void)?

    private lazy var center: UNUserNotificationCenter = {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        return center
    }()

    private var hasRequestedAuthorization = false

    /// Requests notification authorization if it hasn't been requested yet
    /// this launch. Safe to call repeatedly — the OS no-ops (just reports
    /// the existing decision) once the user has granted or denied access,
    /// so this never re-prompts.
    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// Posts an immediate, non-repeating notification for `sessionID`. Reuses
    /// a per-session identifier so a session that re-enters the same phase
    /// replaces its previous banner instead of stacking duplicates.
    func post(sessionID: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = [Self.sessionIDUserInfoKey: sessionID]

        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + sessionID,
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

extension UserNotificationService: UNUserNotificationCenterDelegate {
    /// Lets the banner show even while Open Island is the frontmost app —
    /// without this, macOS suppresses notifications from the active app by
    /// default, which would defeat the point of an off-notch attention cue.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let sessionID = response.notification.request.content.userInfo[Self.sessionIDUserInfoKey] as? String
        Task { @MainActor [weak self] in
            if let sessionID {
                self?.onNotificationClicked?(sessionID)
            }
        }
        completionHandler()
    }
}
