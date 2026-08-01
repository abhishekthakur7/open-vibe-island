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

    /// Verifies permission and question events update an already-tracked session.
    @Test
    func appliesPermissionAndQuestionEventsToExistingSessions() {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        var state = SessionState()

        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "session-1",
                    title: "Fix auth bug",
                    tool: .codex,
                    summary: "Booting up",
                    timestamp: startedAt
                )
            )
        )

        state.apply(
            .permissionRequested(
                PermissionRequested(
                    sessionID: "session-1",
                    request: PermissionRequest(
                        title: "Edit file",
                        summary: "Wants to edit middleware",
                        affectedPath: "src/auth/middleware.ts"
                    ),
                    timestamp: startedAt.addingTimeInterval(5)
                )
            )
        )

        #expect(state.attentionCount == 1)
        #expect(state.activeActionableSession?.phase == .waitingForApproval)
        #expect(state.activeActionableSession?.permissionRequest?.affectedPath == "src/auth/middleware.ts")

        state.apply(
            .questionAsked(
                QuestionAsked(
                    sessionID: "session-1",
                    prompt: QuestionPrompt(
                        title: "Which environment?",
                        options: ["Production", "Staging"]
                    ),
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.activeActionableSession?.phase == .waitingForAnswer)
        #expect(state.activeActionableSession?.questionPrompt?.options == ["Production", "Staging"])
        #expect(state.activeActionableSession?.permissionRequest == nil)
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
    func actionableStateResolvedClearsWaitingForApproval() {
        let startedAt = Date(timeIntervalSince1970: 5_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-approval",
                    title: "Claude · repo",
                    tool: .claudeCode,
                    attachmentState: .attached,
                    phase: .waitingForApproval,
                    summary: "Wants to edit file",
                    updatedAt: startedAt,
                    permissionRequest: PermissionRequest(
                        title: "Edit file",
                        summary: "Wants to edit file",
                        affectedPath: "src/main.ts"
                    )
                )
            ]
        )

        state.apply(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: "claude-approval",
                    summary: "Approval was handled outside Open Island.",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.session(id: "claude-approval")?.phase == .running)
        #expect(state.session(id: "claude-approval")?.permissionRequest == nil)
        #expect(state.session(id: "claude-approval")?.summary == "Approval was handled outside Open Island.")
    }

    @Test
    func actionableStateResolvedClearsWaitingForAnswer() {
        let startedAt = Date(timeIntervalSince1970: 5_500)
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
                        options: ["Production", "Staging"]
                    )
                )
            ]
        )

        state.apply(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: "claude-question",
                    summary: "Approval was handled outside Open Island.",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.session(id: "claude-question")?.phase == .running)
        #expect(state.session(id: "claude-question")?.questionPrompt == nil)
    }

    @Test
    func actionableStateResolvedIsNoOpWhenAlreadyRunning() {
        let startedAt = Date(timeIntervalSince1970: 6_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-running",
                    title: "Claude · repo",
                    tool: .claudeCode,
                    phase: .running,
                    summary: "Working on it",
                    updatedAt: startedAt
                )
            ]
        )

        state.apply(
            .actionableStateResolved(
                ActionableStateResolved(
                    sessionID: "claude-running",
                    summary: "Should not change anything.",
                    timestamp: startedAt.addingTimeInterval(10)
                )
            )
        )

        #expect(state.session(id: "claude-running")?.phase == .running)
        #expect(state.session(id: "claude-running")?.summary == "Working on it")
    }

    @Test
    func preservesLiveSessionOriginFromStartEvent() {
        var state = SessionState()

        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "live-session-1",
                    title: "Live session",
                    tool: .codex,
                    origin: .live,
                    summary: "Live data",
                    timestamp: .now
                )
            )
        )

        #expect(state.session(id: "live-session-1")?.origin == .live)
        #expect(state.session(id: "live-session-1")?.isDemoSession == false)
        #expect(state.session(id: "live-session-1")?.attachmentState == .attached)
    }

    @Test
    func reconcileAttachmentStatesUpdatesExistingSessionsOnly() {
        let startedAt = Date(timeIntervalSince1970: 4_000)
        var state = SessionState(
            sessions: [
                AgentSession(
                    id: "attached-session",
                    title: "Attached session",
                    tool: .codex,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Turn completed",
                    updatedAt: startedAt
                ),
                AgentSession(
                    id: "untouched-session",
                    title: "Untouched session",
                    tool: .codex,
                    attachmentState: .attached,
                    phase: .running,
                    summary: "Still running",
                    updatedAt: startedAt.addingTimeInterval(5)
                ),
            ]
        )

        let changed = state.reconcileAttachmentStates([
            "attached-session": .attached,
            "missing-session": .detached,
        ])

        #expect(changed)
        #expect(state.session(id: "attached-session")?.attachmentState == .attached)
        #expect(state.session(id: "attached-session")?.summary == "Turn completed")
        #expect(state.session(id: "untouched-session")?.attachmentState == .attached)
    }

    @Test
    func liveCountsOnlyIncludeVisibleSessions() {
        var liveRunning = AgentSession(
            id: "live-running",
            title: "Live running",
            tool: .codex,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
        liveRunning.isProcessAlive = true

        var liveAttention = AgentSession(
            id: "live-attention",
            title: "Live attention",
            tool: .codex,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Needs approval",
            updatedAt: .now
        )
        liveAttention.isProcessAlive = true

        let state = SessionState(
            sessions: [
                liveRunning,
                liveAttention,
                AgentSession(
                    id: "detached-running",
                    title: "Detached running",
                    tool: .codex,
                    attachmentState: .detached,
                    phase: .running,
                    summary: "Old run",
                    updatedAt: .now
                ),
            ]
        )

        #expect(state.liveSessionCount == 2)
        #expect(state.liveRunningCount == 1)
        #expect(state.liveAttentionCount == 1)
        #expect(state.runningCount == 2)
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
    func codexHookInstallerInstallLeavesLegacyLookingCommandsUntouched() throws {
        let existing = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/Users/test/.open-island/bin/open-island-bridge' --source codex"
                  },
                  {
                    "type": "command",
                    "command": "/usr/bin/printf"
                  }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "'/Users/test/.open-island/bin/open-island-bridge' --source codex"
                  },
                  {
                    "type": "command",
                    "command": "'/tmp/old-debug/OpenIslandHooks'"
                  },
                  {
                    "type": "command",
                    "command": "/usr/bin/true"
                  }
                ]
              }
            ]
          }
        }
        """.data(using: .utf8)

        let mutation = try CodexHookInstaller.installHooksJSON(
            existingData: existing,
            hookCommand: "'/tmp/new-release/OpenIslandHooks'"
        )

        #expect(mutation.changed)

        let root = try jsonObject(from: mutation.contents)
        let hooks = root["hooks"] as? [String: Any]
        let preToolGroups = hooks?["PreToolUse"] as? [[String: Any]]
        let preToolCommands = preToolGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []
        let stopGroups = hooks?["Stop"] as? [[String: Any]]
        let stopCommands = stopGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []
        let permissionGroups = hooks?["PermissionRequest"] as? [[String: Any]]
        let permissionCommands = permissionGroups?
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String } ?? []

        #expect(preToolCommands == [
            "'/Users/test/.open-island/bin/open-island-bridge' --source codex",
            "/usr/bin/printf",
        ])
        #expect(permissionCommands == ["'/tmp/new-release/OpenIslandHooks'"])
        #expect(hooks?["PostToolUse"] == nil)
        #expect(stopCommands.contains("/usr/bin/true"))
        #expect(stopCommands.contains("'/tmp/new-release/OpenIslandHooks'"))
        #expect(stopCommands.contains("'/Users/test/.open-island/bin/open-island-bridge' --source codex"))
        #expect(stopCommands.contains("'/tmp/old-debug/OpenIslandHooks'"))
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
    func codexHookInstallerEnablesAndRemovesFeatureFlag() {
        let initialConfig = """
        personality = "pragmatic"

        [projects."/tmp"]
        trust_level = "trusted"
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: initialConfig)
        #expect(enabled.changed)
        #expect(enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("[features]"))
        #expect(enabled.contents.contains("hooks = true"))
        #expect(!enabled.contents.contains("codex_hooks = true"))

        let removed = CodexHookInstaller.disableCodexHooksFeatureIfManaged(in: enabled.contents)
        #expect(removed.changed)
        #expect(!removed.contents.contains("hooks = true"))
    }

    @Test
    func codexHookInstallerMigratesLegacyFeatureFlag() {
        let legacyConfig = """
        [features]
        codex_hooks = true
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: legacyConfig)
        #expect(enabled.changed)
        #expect(!enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("hooks = true"))
        #expect(!enabled.contents.contains("codex_hooks = true"))
    }

    @Test
    func codexHookInstallerCanUseLegacyFeatureFlagForOlderCodex() {
        let initialConfig = """
        model = "gpt-5-codex"
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: initialConfig, preferredKey: .legacy)
        #expect(enabled.changed)
        #expect(enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("[features]"))
        let enabledLines = enabled.contents.components(separatedBy: "\n")
        #expect(enabledLines.contains("codex_hooks = true"))
        #expect(!enabledLines.contains("hooks = true"))
    }

    @Test
    func codexHookInstallerRemovesLegacyFlagWhenCurrentFlagExists() {
        let mixedConfig = """
        [features]
        hooks = true
        codex_hooks = true
        """

        let enabled = CodexHookInstaller.enableCodexHooksFeature(in: mixedConfig)
        #expect(enabled.changed)
        #expect(!enabled.featureEnabledByInstaller)
        #expect(enabled.contents.contains("hooks = true"))
        #expect(!enabled.contents.contains("codex_hooks = true"))
    }

    @Test
    func codexHookInstallerRecognizesCurrentAndLegacyFeatureFlags() {
        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        hooks = true
        """))

        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        hooks=true # enabled by user
        """))

        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        codex_hooks = true
        """))

        #expect(CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        codex_hooks=true # legacy enabled by user
        """))

        #expect(!CodexHookInstaller.isCodexHooksFeatureEnabled(in: """
        [features]
        hooks=false # disabled by user
        """))
    }

    /// Verifies Codex hook feature detection across current, legacy, and invalid CLI output.
    @Test
    func codexHookInstallerDetectsPreferredFeatureFlagFromCodexOutput() {
        let currentFeatures = """
        plugin_hooks  under development  false
        hooks         stable             true
        """
        let legacyFeatures = """
        codex_hooks   stable             true
        shell_tool    stable             true
        """

        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromFeatureList: currentFeatures) == .current)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromFeatureList: legacyFeatures) == .legacy)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromVersionOutput: "codex-cli 0.130.0") == .current)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromVersionOutput: "codex-cli 0.129.0") == .legacy)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromFeatureList: "shell_tool stable true") == nil)
        #expect(CodexHookInstaller.preferredCodexHooksFeatureKey(fromVersionOutput: "not a version") == nil)
    }

    @Test
    func codexHookPayloadInfersTerminalAppFromRuntimeEnvironment() throws {
        let payload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "session-1",
            terminalSessionID: "ghostty-frontmost",
            terminalTitle: "codex ~/tmp/other-worktree",
            transcriptPath: nil
        )

        let inferredITerm = payload.withRuntimeContext(environment: [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w0t0p0",
        ])
        #expect(inferredITerm.terminalApp == "iTerm")

        let inferredGhostty = payload.withRuntimeContext(environment: [
            "TERM_PROGRAM": "ghostty",
        ])
        #expect(inferredGhostty.terminalApp == "Ghostty")
        #expect(inferredGhostty.defaultJumpTarget.workingDirectory == "/tmp/worktree")
    }

    @Test
    func codexGhosttyLocatorUsedForSessionStartAndPromptButNotToolUse() {
        let locator: (String) -> (sessionID: String?, tty: String?, title: String?) = { _ in
            (sessionID: "ghostty-frontmost", tty: nil, title: "codex ~/tmp/worktree")
        }
        let env = ["TERM_PROGRAM": "ghostty"]
        let ttyProvider: () -> String? = { "/dev/ttys022" }

        let atStart = CodexHookPayload(
            cwd: "/tmp/worktree", hookEventName: .sessionStart,
            model: "gpt-5-codex", permissionMode: .default, sessionID: "s1", transcriptPath: nil
        ).withRuntimeContext(environment: env, currentTTYProvider: ttyProvider, terminalLocatorProvider: locator)

        #expect(atStart.terminalSessionID == "ghostty-frontmost")
        #expect(atStart.terminalTitle == "codex ~/tmp/worktree")

        let atPrompt = CodexHookPayload(
            cwd: "/tmp/worktree", hookEventName: .userPromptSubmit,
            model: "gpt-5-codex", permissionMode: .default, sessionID: "s1", transcriptPath: nil
        ).withRuntimeContext(environment: env, currentTTYProvider: ttyProvider, terminalLocatorProvider: locator)

        #expect(atPrompt.terminalSessionID == "ghostty-frontmost")
        #expect(atPrompt.terminalTitle == "codex ~/tmp/worktree")

        let atTool = CodexHookPayload(
            cwd: "/tmp/worktree", hookEventName: .preToolUse,
            model: "gpt-5-codex", permissionMode: .default, sessionID: "s1", transcriptPath: nil
        ).withRuntimeContext(
            environment: env, currentTTYProvider: ttyProvider,
            terminalLocatorProvider: { _ in (sessionID: "ghostty-wrong", tty: nil, title: "wrong") }
        )

        #expect(atTool.terminalSessionID == nil)
        #expect(atTool.terminalTitle == nil)
    }

    @Test
    func codexHookPayloadCarriesSessionLocatorIntoJumpTarget() {
        let payload = CodexHookPayload(
            cwd: "/tmp/worktree",
            hookEventName: .sessionStart,
            model: "gpt-5-codex",
            permissionMode: .default,
            sessionID: "session-1",
            terminalApp: "iTerm",
            terminalSessionID: "A6C5F356-DEED-40F7-A787-AB9DADF27AD6",
            terminalTTY: "/dev/ttys022",
            terminalTitle: "codex ~/P/open-island",
            transcriptPath: nil
        )

        let jumpTarget = payload.defaultJumpTarget
        #expect(jumpTarget.terminalApp == "iTerm")
        #expect(jumpTarget.terminalSessionID == "A6C5F356-DEED-40F7-A787-AB9DADF27AD6")
        #expect(jumpTarget.terminalTTY == "/dev/ttys022")
        #expect(jumpTarget.paneTitle == "codex ~/P/open-island")
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
    func sessionCompletedWithoutSignalsDefaultsToSuccessOutcome() {
        let startedAt = Date(timeIntervalSince1970: 30_000)
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
            summary: "Claude Code completed the turn.",
            timestamp: startedAt.addingTimeInterval(10)
        )))

        #expect(state.session(id: "s-1")?.phase == .completed)
        #expect(state.session(id: "s-1")?.outcome == .success)
    }

    @Test
    func sessionCompletedWithInterruptFlagMapsToInterruptedOutcome() {
        let startedAt = Date(timeIntervalSince1970: 30_100)
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "s-1",
            title: "Session",
            tool: .claudeCode,
            summary: "Working",
            timestamp: startedAt
        )))

        // Mirrors BridgeServer's `.stop` handling when Claude reports a
        // Ctrl+C mid-turn (`payload.isInterrupt == true`).
        state.apply(.sessionCompleted(SessionCompleted(
            sessionID: "s-1",
            summary: "Claude Code completed the turn.",
            timestamp: startedAt.addingTimeInterval(10),
            isInterrupt: true
        )))

        #expect(state.session(id: "s-1")?.phase == .completed)
        #expect(state.session(id: "s-1")?.outcome == .interrupted)
    }

    @Test
    func sessionCompletedWithExplicitOutcomeMapsStopFailureToFailed() {
        let startedAt = Date(timeIntervalSince1970: 30_200)
        var state = SessionState()
        state.apply(.sessionStarted(SessionStarted(
            sessionID: "s-1",
            title: "Session",
            tool: .claudeCode,
            summary: "Working",
            timestamp: startedAt
        )))

        // Mirrors BridgeServer's `.stopFailure` handling — always `.failed`
        // regardless of `isInterrupt`.
        state.apply(.sessionCompleted(SessionCompleted(
            sessionID: "s-1",
            summary: "Claude Code failed to finish the turn.",
            timestamp: startedAt.addingTimeInterval(10),
            outcome: .failed
        )))

        #expect(state.session(id: "s-1")?.phase == .completed)
        #expect(state.session(id: "s-1")?.outcome == .failed)
    }

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

    @Test
    func denyingPermissionThroughOpenIslandRecordsFailedOutcome() {
        let startedAt = Date(timeIntervalSince1970: 30_400)
        var state = SessionState(sessions: [
            AgentSession(
                id: "s-1",
                title: "Session",
                tool: .claudeCode,
                phase: .waitingForApproval,
                summary: "Wants to edit a file",
                updatedAt: startedAt,
                permissionRequest: PermissionRequest(
                    title: "Edit file",
                    summary: "Wants to edit a file",
                    affectedPath: "src/main.ts"
                )
            ),
        ])

        state.resolvePermission(
            sessionID: "s-1",
            resolution: .deny(),
            at: startedAt.addingTimeInterval(5)
        )

        #expect(state.session(id: "s-1")?.phase == .completed)
        #expect(state.session(id: "s-1")?.outcome == .failed)
    }

    @Test
    func approvingPermissionResetsOutcomeToSuccess() {
        let startedAt = Date(timeIntervalSince1970: 30_500)
        var state = SessionState(sessions: [
            AgentSession(
                id: "s-1",
                title: "Session",
                tool: .claudeCode,
                phase: .waitingForApproval,
                summary: "Wants to edit a file",
                updatedAt: startedAt,
                permissionRequest: PermissionRequest(
                    title: "Edit file",
                    summary: "Wants to edit a file",
                    affectedPath: "src/main.ts"
                )
            ),
        ])

        state.resolvePermission(
            sessionID: "s-1",
            resolution: .allowOnce(),
            at: startedAt.addingTimeInterval(5)
        )

        #expect(state.session(id: "s-1")?.phase == .running)
        #expect(state.session(id: "s-1")?.outcome == .success)
    }

    @Test
    func processVanishingWithoutACleanStopRecordsInterruptedOutcome() {
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

        state.markProcessLiveness(aliveSessionIDs: [])
        state.markProcessLiveness(aliveSessionIDs: [])

        #expect(state.session(id: "desktop-1")?.isSessionEnded == true)
        #expect(state.session(id: "desktop-1")?.phase == .completed)
        #expect(state.session(id: "desktop-1")?.outcome == .interrupted)
    }

    @Test
    func dismissSessionRecordsInterruptedOutcome() {
        var state = SessionState(sessions: [
            AgentSession(
                id: "remote-1",
                title: "Remote session",
                tool: .claudeCode,
                phase: .running,
                summary: "Working",
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ),
        ])

        state.dismissSession(id: "remote-1")

        #expect(state.session(id: "remote-1")?.phase == .completed)
        #expect(state.session(id: "remote-1")?.outcome == .interrupted)
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

    /// AB-237: dismiss is undo-safe — it suppresses the row, it doesn't
    /// tombstone the session. This mirrors exactly what
    /// `AppModel.applyTrackedEvent` does for a genuine live bridge event
    /// (`state.apply` followed by `markSingleSessionAlive`, see
    /// `ProcessMonitoringCoordinator.markSessionProcessAlive`) and verifies
    /// the dismissed session reappears once the agent is heard from again.
    @Test
    func dismissedSessionReappearsWhenLiveEventArrivesForSameID() {
        var state = SessionState()
        state.apply(
            .sessionStarted(
                SessionStarted(
                    sessionID: "local-1",
                    title: "Claude · local",
                    tool: .claudeCode,
                    origin: .live,
                    initialPhase: .running,
                    summary: "Working",
                    timestamp: Date(timeIntervalSince1970: 1_000)
                )
            )
        )
        #expect(state.session(id: "local-1")?.isVisibleInIsland == true)

        state.dismissSession(id: "local-1")
        #expect(state.session(id: "local-1")?.isVisibleInIsland == false)

        // A genuine live hook event arrives for the same session id.
        state.apply(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "local-1",
                    summary: "Still working",
                    phase: .running,
                    timestamp: Date(timeIntervalSince1970: 1_010)
                )
            )
        )
        // `apply` alone updates phase/summary but does not undo the
        // suppression — only `markSingleSessionAlive` does, matching how
        // `AppModel` wires the two together for bridge-ingress events.
        #expect(state.session(id: "local-1")?.phase == .running)
        #expect(state.session(id: "local-1")?.isVisibleInIsland == false)

        state.markSingleSessionAlive(sessionID: "local-1")

        #expect(state.session(id: "local-1")?.isDismissedByUser == false)
        #expect(state.session(id: "local-1")?.isVisibleInIsland == true)
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
