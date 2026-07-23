import OpenIslandCore

/// Which kind of attention event a session's current phase represents.
///
/// AB-239 introduces per-event sounds and screen-aware system notifications,
/// both of which need to distinguish "needs a permission decision" from
/// "needs a question answered" from "just finished" — this is the shared
/// vocabulary for that distinction. `nil` (no case) covers `.running`, which
/// never drives a notification card, sound, or system notification.
enum NotificationEventKind: String, CaseIterable, Sendable {
    case permission
    case question
    case completion

    init?(phase: SessionPhase) {
        switch phase {
        case .waitingForApproval:
            self = .permission
        case .waitingForAnswer:
            self = .question
        case .completed:
            self = .completion
        case .running:
            return nil
        }
    }
}
