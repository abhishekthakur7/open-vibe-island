import OpenIslandCore

/// The callbacks a session row hands back to `AppModel` — approve a pending
/// permission request, answer a question, reply to a finished session, jump
/// to where it lives, dismiss it from the list.
///
/// AB-297: bundled into one value so a themed row receives the whole action
/// surface as a single input instead of re-declaring five closure properties.
/// Optionality mirrors what the row already expected: `jump` always exists,
/// `approve`/`answer` are only wired for the phases that use them, `reply` is
/// nil when the session can't be replied to, and `dismiss` is nil for rows
/// that aren't dismissible (today: the notification card).
struct RowActions {
    var approve: ((ApprovalAction) -> Void)? = nil
    var answer: ((QuestionPromptResponse) -> Void)? = nil
    var reply: ((String) -> Void)? = nil
    var jump: () -> Void
    var dismiss: (() -> Void)? = nil
}
