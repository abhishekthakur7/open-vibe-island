import Foundation
import OpenIslandCore

/// Manages the lifecycle of the Codex app-server connection.
///
/// The app-server transport is intentionally unavailable in local-only mode.
/// Hook and process-discovery events continue to flow through the standard
/// `SessionState` reducer without locating or launching Codex executables.
@Observable
@MainActor
final class CodexAppServerCoordinator {
    /// Callback to emit AgentEvents into AppModel.
    @ObservationIgnored
    var onEvent: ((AgentEvent) -> Void)?

    /// Callback to log status messages.
    @ObservationIgnored
    var onStatusMessage: ((String) -> Void)?

    /// Returns `true` if a session with the given id is already tracked.
    /// Used to avoid re-emitting `sessionStarted` (which rebuilds the
    /// session and wipes richer state from hooks/rediscovery).
    @ObservationIgnored
    var isSessionTracked: ((String) -> Bool)?

    private(set) var isConnected = false

    // MARK: - Public API

    /// App-server spawning is denied in local-only mode.
    func ensureConnected() {
        onStatusMessage?("Codex app-server integration is unavailable in local-only mode.")
    }

    /// Disconnect and clean up.  Called when Codex.app is no longer running.
    func disconnect() {
        isConnected = false
    }

    // MARK: - Thread sync

    // MARK: - Notification handling

    private func handleNotification(_ notification: CodexAppServerNotification) {
        switch notification {
        case .threadStarted(let thread):
            guard !thread.ephemeral else { return }
            guard isSessionTracked?(thread.id) != true else { return }
            emitSessionStarted(from: thread)

        case .threadStatusChanged(let threadId, let status):
            switch status.type {
            case .active:
                if status.isWaitingOnApproval {
                    onEvent?(.permissionRequested(
                        PermissionRequested(
                            sessionID: threadId,
                            request: PermissionRequest(
                                title: "Approval Required",
                                summary: "Codex is waiting for approval.",
                                affectedPath: "",
                                // Codex.app surfaces this purely as a status
                                // notification over the app-server JSON-RPC
                                // connection — there is no matching "submit
                                // decision" RPC on `CodexAppServerClient`, so
                                // Allow/Deny here would silently do nothing.
                                // The user has to switch to Codex.app itself
                                // (which shows its own native approval UI);
                                // the card instead offers a jump CTA (AB-235).
                                requiresTerminalApproval: true
                            ),
                            timestamp: .now
                        )
                    ))
                } else if status.isWaitingOnUserInput {
                    onEvent?(.questionAsked(
                        QuestionAsked(
                            sessionID: threadId,
                            prompt: QuestionPrompt(
                                title: "Codex is waiting for input.",
                                options: []
                            ),
                            timestamp: .now
                        )
                    ))
                } else {
                    onEvent?(.activityUpdated(
                        SessionActivityUpdated(
                            sessionID: threadId,
                            summary: "Codex is working…",
                            phase: .running,
                            timestamp: .now
                        )
                    ))
                }
            case .idle:
                // Idle means "between turns" in the same thread — the thread
                // is still open.  Only `thread/closed` truly ends a session.
                onEvent?(.activityUpdated(
                    SessionActivityUpdated(
                        sessionID: threadId,
                        summary: "Idle.",
                        phase: .completed,
                        timestamp: .now
                    )
                ))
            case .systemError:
                // Quota limits and other hard failures can leave the thread in
                // systemError without a turn/completed notification. Mark the
                // turn as finished so the island does not stay stuck running.
                onEvent?(.activityUpdated(
                    SessionActivityUpdated(
                        sessionID: threadId,
                        summary: "Turn failed.",
                        phase: .completed,
                        timestamp: .now
                    )
                ))
            case .notLoaded:
                break
            }

        case .threadClosed(let threadId):
            onEvent?(.sessionCompleted(
                SessionCompleted(
                    sessionID: threadId,
                    summary: "Codex thread closed.",
                    timestamp: .now,
                    isSessionEnd: true
                )
            ))

        case .threadNameUpdated:
            // Title updates don't have a dedicated AgentEvent and we can't
            // safely overwrite phase/summary here (would clobber running or
            // waiting-for-approval state).  Skip for now — the title is
            // populated at sessionStarted time which is usually enough.
            break

        case .turnStarted(let threadId, _):
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: "Codex is working…",
                    phase: .running,
                    timestamp: .now
                )
            ))

        case .turnCompleted(let threadId, let turn):
            // A turn completing doesn't end the thread — the user can send
            // another message.  Use activityUpdated(phase: .completed) so the
            // session stays visible as "Completed" rather than being torn
            // down.  `thread/closed` is the authoritative end signal.
            let summary: String
            switch turn.status {
            case .completed: summary = "Turn completed."
            case .interrupted: summary = "Turn interrupted."
            case .failed: summary = "Turn failed."
            case .inProgress: summary = "Turn in progress."
            }
            onEvent?(.activityUpdated(
                SessionActivityUpdated(
                    sessionID: threadId,
                    summary: summary,
                    phase: .completed,
                    timestamp: .now
                )
            ))

        case .unknown:
            break
        }
    }

    // MARK: - Helpers

    private func emitSessionStarted(from thread: CodexThread) {
        let workspaceName = URL(fileURLWithPath: thread.cwd).lastPathComponent
        let title = thread.name ?? workspaceName
        let summary = thread.preview.isEmpty ? "Codex session." : String(thread.preview.prefix(120))

        let phase: SessionPhase
        switch thread.status.type {
        case .active: phase = .running
        case .idle: phase = .completed
        case .notLoaded, .systemError: phase = .completed
        }

        onEvent?(.sessionStarted(
            SessionStarted(
                sessionID: thread.id,
                title: title,
                tool: .codex,
                origin: .live,
                initialPhase: phase,
                summary: summary,
                timestamp: .now,
                jumpTarget: JumpTarget(
                    terminalApp: "Codex.app",
                    workspaceName: workspaceName,
                    paneTitle: title,
                    workingDirectory: thread.cwd,
                    codexThreadID: thread.id
                ),
                codexMetadata: CodexSessionMetadata(
                    transcriptPath: thread.path,
                    initialUserPrompt: thread.preview.isEmpty ? nil : thread.preview
                )
            )
        ))
    }
}
