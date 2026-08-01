import Dispatch
import Foundation
import Testing
@testable import OpenIslandCore

/// Regression coverage for core session lifecycle and visibility behavior.
struct SessionStateTests {
    /// Completed Codex CLI sessions outside Codex.app should age out even while Codex.app is running.
    @Test
    func completedCodexCLISessionEndsEvenWhenCodexAppIsRunning() {
        let startedAt = Date(timeIntervalSince1970: 7_000)
        var state = SessionState()

        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "codex-vscode-review",
                    title: "Codex · jobfeed",
                    tool: .codex,
                    origin: .live,
                    summary: "Reviewing code",
                    timestamp: startedAt,
                    jumpTarget: JumpTarget(
                        terminalApp: "VS Code",
                        workspaceName: "jobfeed",
                        paneTitle: "Codex 019e9716",
                        workingDirectory: "/Users/example/jobfeed"
                    )
                )
            )
        )
        state.apply(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "codex-vscode-review",
                    summary: "no issues found",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        _ = state.markProcessLiveness(aliveSessionIDs: [], isCodexAppRunning: true)
        _ = state.markProcessLiveness(aliveSessionIDs: [], isCodexAppRunning: true)

        #expect(state.session(id: "codex-vscode-review")?.isSessionEnded == true)
        #expect(state.liveSessionCount == 0)
    }

    /// Contract that the Claude Desktop fix (#510) relies on: a hook-managed
    /// Claude session stays visible for as long as its ID is reported in
    /// `aliveSessionIDs`, and is only evicted after two consecutive polls
    /// where it is absent. ProcessMonitoringCoordinator keeps Claude Desktop
    /// session IDs in that set while Claude.app is running (the desktop
    /// subprocess is TTY-less and invisible to ps/lsof discovery), so they no
    /// longer vanish ~6s after appearing.
    @Test
    func hookManagedClaudeSessionLivenessFollowsReportedAliveSet() {
        var session = AgentSession(
            id: "desktop-1",
            title: "Claude · demo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        session.isHookManaged = true
        session.isProcessAlive = true
        var state = SessionState(sessions: [session])

        // Reported alive (Claude.app running): stays visible across polls.
        state.markProcessLiveness(aliveSessionIDs: ["desktop-1"])
        state.markProcessLiveness(aliveSessionIDs: ["desktop-1"])
        #expect(state.session(id: "desktop-1")?.isSessionEnded == false)
        #expect(state.session(id: "desktop-1")?.isVisibleInIsland == true)

        // First miss (e.g. Claude.app just quit): debounced, not yet evicted.
        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "desktop-1")?.isSessionEnded == false)
        #expect(state.session(id: "desktop-1")?.isVisibleInIsland == true)

        // Second consecutive miss: session ends and leaves the island.
        state.markProcessLiveness(aliveSessionIDs: [])
        #expect(state.session(id: "desktop-1")?.isSessionEnded == true)
        #expect(state.session(id: "desktop-1")?.isVisibleInIsland == false)
    }

    @Test
    func resolvesUserActionsAndKeepsSessionsSortedByRecency() {
        let startedAt = Date(timeIntervalSince1970: 2_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "older",
                    title: "Older session",
                    tool: .claudeCode,
                    phase: .running,
                    summary: "Working",
                    updatedAt: startedAt
                ),
                AgentSession(
                    id: "newer",
                    title: "Newer session",
                    tool: .codex,
                    phase: .waitingForApproval,
                    summary: "Needs approval",
                    updatedAt: startedAt.addingTimeInterval(5),
                    permissionRequest: PermissionRequest(
                        title: "Edit users.ts",
                        summary: "Needs access",
                        affectedPath: "src/routes/users.ts"
                    )
                ),
            ]
        )

        state.resolvePermission(
            sessionID: "newer",
            resolution: .allowOnce(),
            at: startedAt.addingTimeInterval(20)
        )

        #expect(state.sessions.first?.id == "newer")
        #expect(state.sessions.first?.phase == .running)
        #expect(state.sessions.first?.permissionRequest == nil)

        state.answerQuestion(
            sessionID: "older",
            response: QuestionPromptResponse(answer: "Production"),
            at: startedAt.addingTimeInterval(25)
        )

        #expect(state.sessions.first?.id == "older")
        #expect(state.sessions.first?.summary == "Answered: Production")
    }

    @Test
    func keepsQuestionStateWhileIncidentalRunningUpdatesArrive() {
        let startedAt = Date(timeIntervalSince1970: 2_500)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-question",
                    title: "Claude · repo",
                    tool: .claudeCode,
                    attachmentState: .attached,
                    phase: .waitingForAnswer,
                    summary: "Which environment?",
                    updatedAt: startedAt,
                    questionPrompt: QuestionPrompt(
                        title: "Which environment?",
                        questions: [
                            QuestionPromptItem(
                                question: "Which environment?",
                                header: "Env",
                                options: [
                                    QuestionOption(label: "Production"),
                                    QuestionOption(label: "Staging"),
                                ]
                            )
                        ]
                    )
                )
            ]
        )

        state.apply(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "claude-question",
                    summary: "Claude is still waiting for your answer.",
                    phase: .running,
                    timestamp: startedAt.addingTimeInterval(5)
                )
            )
        )

        #expect(state.session(id: "claude-question")?.phase == .waitingForAnswer)
        #expect(state.session(id: "claude-question")?.summary == "Which environment?")
        #expect(state.session(id: "claude-question")?.questionPrompt?.title == "Which environment?")
    }

    @Test
    func bridgeEnvelopeRoundTripsThroughLineCodec() throws {
        let envelope = BridgeEnvelope.event(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "session-42",
                    request: PermissionRequest(
                        title: "Edit middleware",
                        summary: "Needs to edit auth middleware.",
                        affectedPath: "src/auth/middleware.ts"
                    ),
                    timestamp: Date(timeIntervalSince1970: 3_000)
                )
            )
        )

        var buffer = try BridgeCodec.encodeLine(envelope)
        let decoded = try BridgeCodec.decodeLines(from: &buffer)

        #expect(decoded == [envelope])
        #expect(buffer.isEmpty)
    }

    @Test
    func codexHookInstallerMergesManagedGroupsWithoutDroppingUnrelatedHooks() throws {
        let existing = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "/usr/bin/true",
                    "statusMessage": "Other hook"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)

        let mutation = try CodexHookInstaller.installHooksJSON(
            existingData: existing,
            hookCommand: "'/tmp/OpenIslandHooks'"
        )

        #expect(mutation.changed)
        let root = try jsonObject(from: mutation.contents)
        let hooks = root["hooks"] as? [String: Any]
        let stopGroups = hooks?["Stop"] as? [[String: Any]]
        let stopCommands = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []
        let managedStopHook = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .first(where: { $0["command"] as? String == "'/tmp/OpenIslandHooks'" })

        #expect(stopCommands.contains("/usr/bin/true"))
        #expect(stopCommands.contains("'/tmp/OpenIslandHooks'"))
        #expect(managedStopHook?["statusMessage"] == nil)

        let sessionStartGroups = hooks?["SessionStart"] as? [[String: Any]]
        let permissionGroups = hooks?["PermissionRequest"] as? [[String: Any]]
        let managedPermissionHook = permissionGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .first(where: { $0["command"] as? String == "'/tmp/OpenIslandHooks'" })
        #expect(sessionStartGroups?.contains(where: { $0["matcher"] as? String == "startup|resume" }) == true)
        #expect(managedPermissionHook?["timeout"] as? Int == CodexHookInstaller.managedInteractiveTimeout)
        #expect(hooks?["PreToolUse"] == nil)
        #expect(hooks?["PostToolUse"] == nil)
    }

    @Test
    func codexHookInstallerUninstallRemovesOnlyManagedHooks() throws {
        let existing = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/tmp/OpenIslandHooks'",
                    "statusMessage": "Managed by Open Island"
                  },
                  {
                    "type": "command",
                    "command": "/usr/bin/true",
                    "statusMessage": "Other hook"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)

        let mutation = try CodexHookInstaller.uninstallHooksJSON(
            existingData: existing,
            managedCommand: "'/tmp/OpenIslandHooks'"
        )

        #expect(mutation.changed)
        #expect(mutation.hasRemainingHooks)

        let root = try jsonObject(from: mutation.contents)
        let hooks = root["hooks"] as? [String: Any]
        let stopGroups = hooks?["Stop"] as? [[String: Any]]
        let stopCommands = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []

        #expect(stopCommands == ["/usr/bin/true"])
    }

    @Test
    func firstSeenAtIsWrittenOnceAndPreservedAcrossSubsequentEvents() {
        let t0 = Date(timeIntervalSince1970: 10_000)
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "s-1",
            title: "First boot",
            tool: .claudeCode,
            summary: "Starting",
            timestamp: t0
        )))

        #expect(state.session(id: "s-1")?.firstSeenAt == t0)

        // A repeated sessionStarted (e.g. hook reconnect) must preserve the
        // original firstSeenAt even though the payload timestamp is later.
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "s-1",
            title: "Re-attached",
            tool: .claudeCode,
            summary: "Reattached",
            timestamp: t0.addingTimeInterval(120)
        )))
        #expect(state.session(id: "s-1")?.firstSeenAt == t0)
        #expect(state.session(id: "s-1")?.updatedAt == t0.addingTimeInterval(120))

        // Activity updates leave firstSeenAt untouched.
        state.apply(.activityUpdated(SessionActivityUpdated(
            sessionID: "s-1",
            summary: "Working",
            phase: .running,
            timestamp: t0.addingTimeInterval(240)
        )))
        #expect(state.session(id: "s-1")?.firstSeenAt == t0)
    }

    @Test
    func firstSeenAtPersistsThroughRegistryRoundTrip() throws {
        let t0 = Date(timeIntervalSince1970: 20_000)
        let session = AgentSession(
            id: "claude-1",
            title: "Repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: t0.addingTimeInterval(60),
            firstSeenAt: t0
        )
        let record = ClaudeTrackedSessionRecord(session: session)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClaudeTrackedSessionRecord.self, from: data)

        #expect(decoded.firstSeenAt == t0)
        #expect(decoded.session.firstSeenAt == t0)

        // Legacy records without firstSeenAt decode cleanly and fall back to
        // updatedAt on the restored AgentSession.
        let legacyJSON = """
        {
          "attachmentState": "stale",
          "phase": "running",
          "sessionID": "claude-legacy",
          "summary": "Legacy",
          "title": "Legacy",
          "updatedAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let legacy = try decoder.decode(ClaudeTrackedSessionRecord.self, from: legacyJSON)
        #expect(legacy.firstSeenAt == nil)
        let legacyUpdated = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")
        #expect(legacy.session.firstSeenAt == legacyUpdated)
        // Legacy records predate `outcome` entirely — should fall back to `.success`.
        #expect(legacy.outcome == nil)
        #expect(legacy.session.outcome == .success)
    }

    // MARK: - AB-230: session outcome (success / interrupted / failed)

    @Test
    func sessionEndTeardownPreservesThePreviouslyRecordedOutcome() {
        let startedAt = Date(timeIntervalSince1970: 30_300)
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "s-1",
            title: "Session",
            tool: .claudeCode,
            summary: "Working",
            timestamp: startedAt
        )))

        state.apply(.sessionCompleted(SessionCompleted(
            sessionID: "s-1",
            summary: "Claude Code failed to finish the turn.",
            timestamp: startedAt.addingTimeInterval(10),
            outcome: .failed
        )))
        #expect(state.session(id: "s-1")?.outcome == .failed)

        // SessionEnd unconditionally sets `isInterrupt: true` purely to
        // suppress a duplicate notification card — it must NOT stomp the
        // `.failed` outcome the prior StopFailure already recorded.
        state.apply(.sessionCompleted(SessionCompleted(
            sessionID: "s-1",
            summary: "Claude Code session ended.",
            timestamp: startedAt.addingTimeInterval(20),
            isInterrupt: true,
            isSessionEnd: true
        )))

        #expect(state.session(id: "s-1")?.isSessionEnded == true)
        #expect(state.session(id: "s-1")?.outcome == .failed)
    }

    /// AB-237: dismiss used to only be wired up in the UI for remote
    /// sessions, but `dismissSession` itself has always worked on any
    /// session id. This locks in that a *local*, hook-managed, still
    /// process-alive session also disappears immediately once dismissed —
    /// `isDismissedByUser` is checked first in `isVisibleInIsland`,
    /// overriding the hook-managed / process-alive visibility rules.
    @Test
    func dismissSessionHidesLocalHookManagedSessionImmediately() {
        var session = AgentSession(
            id: "local-1",
            title: "Claude · local",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        session.isHookManaged = true
        session.isProcessAlive = true
        var state = SessionState(sessions: [session])

        #expect(state.session(id: "local-1")?.isVisibleInIsland == true)

        state.dismissSession(id: "local-1")

        #expect(state.session(id: "local-1")?.isDismissedByUser == true)
        #expect(state.session(id: "local-1")?.isVisibleInIsland == false)
    }

    /// AB-237: passive process-liveness polling (`markProcessLiveness`, the
    /// periodic `ps`/`lsof` reconciliation) must NOT resurrect a dismissed
    /// session by itself — only `markSingleSessionAlive`, invoked
    /// exclusively for genuine live hook events, does. This is what keeps a
    /// dismissed-but-still-running agent hidden until it actually does
    /// something, rather than reappearing the instant background polling
    /// next confirms the PID is alive.
    @Test
    func dismissedSessionStaysHiddenThroughBackgroundProcessPolling() {
        var session = AgentSession(
            id: "local-1",
            title: "Claude · local",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        session.isHookManaged = true
        session.isProcessAlive = true
        var state = SessionState(sessions: [session])

        state.dismissSession(id: "local-1")
        #expect(state.session(id: "local-1")?.isVisibleInIsland == false)

        state.markProcessLiveness(aliveSessionIDs: ["local-1"])

        #expect(state.session(id: "local-1")?.isDismissedByUser == true)
        #expect(state.session(id: "local-1")?.isVisibleInIsland == false)
    }

    @Test
    func agentSessionOutcomeRoundTripsThroughCodableWithSuccessDefaultForLegacyData() throws {
        let session = AgentSession(
            id: "s-1",
            title: "Session",
            tool: .claudeCode,
            phase: .completed,
            outcome: .failed,
            summary: "Failed",
            updatedAt: .now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentSession.self, from: data)
        #expect(decoded.outcome == .failed)

        // Pre-AB-230 persisted JSON has no "outcome" key at all.
        let legacyJSON = """
        {
          "id": "legacy-1",
          "title": "Legacy",
          "tool": "claudeCode",
          "attachmentState": "stale",
          "phase": "completed",
          "summary": "Done",
          "updatedAt": "2026-01-01T00:00:00Z",
          "firstSeenAt": "2026-01-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let legacy = try decoder.decode(AgentSession.self, from: legacyJSON)
        #expect(legacy.outcome == .success)
    }
}

private func jsonObject(from data: Data?) throws -> [String: Any] {
    guard let data else {
        return [:]
    }

    let object = try JSONSerialization.jsonObject(with: data)
    return object as? [String: Any] ?? [:]
}
