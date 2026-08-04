import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

@MainActor
@Suite(.serialized)
struct AppModelSessionListTests {
    init() {
        [
            "appearance.island.v8.stateIndicator",
            "appearance.island.v8.sessionGroup",
            "appearance.island.v8.sessionSort",
            "appearance.island.v8.completedStaleThreshold",
            "appearance.island.v8.notch.rightSlot",
            "appearance.island.v8.notch.centerLabel",
            "appearance.island.v8.notch.centerLabel.explicit",
            "appearance.island.v8.topBar.centerLabel.explicit",
            "appearance.island.v8.notch.stateIndicator",
            "appearance.island.v8.notch.sessionGroup",
            "appearance.island.v8.notch.sessionSort",
            "appearance.island.v8.notch.completedStaleThreshold",
            "appearance.island.v8.topBar.rightSlot",
            "appearance.island.v8.topBar.centerLabel",
            "appearance.island.v8.topBar.stateIndicator",
            "appearance.island.v8.topBar.sessionGroup",
            "appearance.island.v8.topBar.sessionSort",
            "appearance.island.v8.topBar.completedStaleThreshold",
            "app.suppressFrontmostNotifications",
            "feature.completionReply.enabled",
            "overlay.sound.muted",
            "app.autoCollapseOnMouseLeave",
        ].forEach(UserDefaults.standard.removeObject(forKey:))
    }

    @Test
    func islandListSessionsOnlyIncludeLiveAttachedSessions() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        var liveSession = AgentSession(
            id: "live-session",
            title: "Claude · active",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "active",
                paneTitle: "claude ~/active",
                workingDirectory: "/tmp/active",
                terminalSessionID: "ghostty-1"
            ),
            claudeMetadata: ClaudeSessionMetadata(
                transcriptPath: "/tmp/live.jsonl",
                currentTool: "Task"
            )
        )
        liveSession.isProcessAlive = true

        model.state = SessionState(
            sessions: [
                liveSession,
                AgentSession(
                    id: "recent-session",
                    title: "Claude · recent",
                    tool: .claudeCode,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Finished",
                    updatedAt: now.addingTimeInterval(-300),
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "recent",
                        paneTitle: "claude ~/recent",
                        workingDirectory: "/tmp/recent",
                        terminalSessionID: "ghostty-2"
                    ),
                    claudeMetadata: ClaudeSessionMetadata(
                        transcriptPath: "/tmp/recent.jsonl",
                        lastAssistantMessage: "Finished"
                    )
                ),
            ]
        )

        #expect(model.surfacedSessions.map(\.id) == ["live-session"])
        #expect(model.recentSessions.map(\.id) == ["recent-session"])
        #expect(model.islandListSessions.map(\.id) == ["live-session"])
    }

    /// AB-237: dismiss must work on any session (not just remote — the row's
    /// dismiss button used to be gated to `session.isRemote` even though
    /// `AppModel.dismissSession` always worked on any id), and it must be
    /// undo-safe: a dismissed session reappears the next time a genuine live
    /// bridge event arrives for the same session id, rather than staying
    /// hidden until process-death polling eventually catches up.
    @Test
    func dismissedLocalSessionReappearsOnNextLiveBridgeEvent() {
        let now = Date(timeIntervalSince1970: 5_000)
        let model = AppModel()

        model.applyTrackedEvent(
            .sessionStarted(
                SessionStarted(
                    sessionID: "local-session",
                    title: "Claude · local",
                    tool: .claudeCode,
                    origin: .live,
                    initialPhase: .running,
                    summary: "Working",
                    timestamp: now
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.surfacedSessions.map(\.id) == ["local-session"])

        model.dismissSession("local-session")

        #expect(model.surfacedSessions.isEmpty)
        #expect(model.state.session(id: "local-session")?.phase == .completed)
        #expect(model.state.session(id: "local-session")?.outcome == .interrupted)

        // A later live hook event for the same session id — the session
        // should reappear rather than staying suppressed.
        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "local-session",
                    summary: "Back to work",
                    phase: .running,
                    timestamp: now.addingTimeInterval(30)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        #expect(model.surfacedSessions.map(\.id) == ["local-session"])
        #expect(model.state.session(id: "local-session")?.phase == .running)
    }

    @Test
    func islandListDeduplicatesSessionsSharingTheSameLiveGhosttyTerminal() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        var runningLive = AgentSession(
            id: "running-live",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Current live turn",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-1"
            )
        )
        runningLive.isProcessAlive = true

        var oldTurnSameSplit = AgentSession(
            id: "old-turn-same-split",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Historical turn on the same split",
            updatedAt: now.addingTimeInterval(-90),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-1"
            )
        )
        oldTurnSameSplit.isProcessAlive = true

        var otherLive = AgentSession(
            id: "other-live",
            title: "Codex · open-island",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Another live split",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-split-2"
            )
        )
        otherLive.isProcessAlive = true

        model.state = SessionState(
            sessions: [runningLive, oldTurnSameSplit, otherLive]
        )

        #expect(model.surfacedSessions.map(\.id) == ["running-live", "other-live"])
        #expect(model.recentSessions.map(\.id).contains("old-turn-same-split"))
        #expect(model.liveSessionCount == 2)
        #expect(model.liveRunningCount == 1)
        #expect(model.liveAttentionCount == 0)
    }

    @Test
    func closedIslandTextLaneDefaultsOffOnNotchButAgentActionOnTopBar() {
        // AB-241: the notch-lane label reuses `islandCenterLabel`, but must
        // default to `.off` on the notch profile specifically — before this
        // ticket the closed pill hard-suppressed the label on MacBook, so an
        // untouched install has to keep looking exactly as it did. The
        // topBar (external) profile keeps its pre-existing `.agentAction`
        // default untouched.
        //
        // PI-A-001 (Poured parity, owner rulings R4/R5) narrows the notch
        // `.off` default to *non-Poured* themes: every §A frame of the Poured
        // board narrates in the collapsed pill, so Poured's effective notch
        // default is `.agentAction`.
        //
        // PI-A-001 review correction: the "user chose" sentinel is the dedicated
        // `centerLabel.explicit` marker, NOT absence of the persisted
        // `centerLabel` value — `persistAppearancePreferences` writes all seven
        // notch keys on any notch change, so key-absence was destroyed by
        // unrelated writes. Arm (a) below is the regression that pins it.
        let notchLabelKey = "appearance.island.v8.notch.centerLabel"
        let notchLabelMarkerKey = "appearance.island.v8.notch.centerLabel.explicit"
        let themeKey = "appearance.island.v8.theme"
        let previous = [notchLabelKey, notchLabelMarkerKey, themeKey]
            .map { ($0, UserDefaults.standard.object(forKey: $0)) }
        defer {
            for (key, value) in previous {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        UserDefaults.standard.removeObject(forKey: notchLabelKey)
        UserDefaults.standard.removeObject(forKey: notchLabelMarkerKey)

        let now = Date(timeIntervalSince1970: 5_000)
        let model = AppModel()
        UserDefaults.standard.removeObject(forKey: notchLabelKey)
        UserDefaults.standard.removeObject(forKey: notchLabelMarkerKey)
        model.islandThemeID = "halo"

        var running = listSession(id: "running", phase: .running, updatedAt: now)
        running.isProcessAlive = true
        model.state = SessionState(sessions: [running])

        // (c1) a non-Poured theme on the notch still defaults `.off`, and the
        // topBar (external) profile keeps its pre-existing `.agentAction`.
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        #expect(model.islandCenterLabel == .off)
        #expect(model.islandClosedLabel() == nil)

        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .topBar)
        #expect(model.islandCenterLabel == .agentAction)
        #expect(model.islandClosedLabel() != nil)

        // (c2) PI-A-001: Poured on the notch defaults `.agentAction` — the
        // collapsed narrative the board's §A frames all show.
        model.islandThemeID = "poured"
        model.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        #expect(model.islandCenterLabel == .agentAction)
        #expect(model.islandClosedLabel() != nil)

        // (a) REGRESSION: an unrelated notch preference write (right slot) makes
        // `persistAppearancePreferences` materialise `centerLabel=off` on disk.
        // That is not a user choice, so the Poured override must survive it.
        model.updateAppearancePreferences(for: .notch) { $0.rightSlot = .agents }
        #expect(UserDefaults.standard.string(forKey: notchLabelKey) == IslandCenterLabel.off.rawValue)
        #expect(UserDefaults.standard.object(forKey: notchLabelMarkerKey) == nil)
        #expect(model.islandCenterLabel == .agentAction)
        #expect(model.islandClosedLabel() != nil)

        // (a2) PI-A-001 round-2: stored and effective disagree by design on a
        // fresh Poured notch install, and `effectiveCenterLabel(for:)` — what
        // the settings pane's centre-label card now reads — reports the value
        // the pill actually renders, not the raw stored `.off`.
        #expect(model.appearancePreferences(for: .notch).centerLabel == .off)
        #expect(model.effectiveCenterLabel(for: .notch) == .agentAction)

        // (a3) PI-A-001 round-2 REGRESSION: the settings-card "Off" pick is
        // explicit intent with NO stored change (stored already is `.off`).
        // Before this fix that click planted no marker and was a silent no-op —
        // the user could not turn the label off at all. It must now record the
        // choice, flip the effective value, and survive a fresh `AppModel`.
        model.updateAppearancePreferences(
            for: .notch,
            explicitCenterLabelChoice: true
        ) { $0.centerLabel = .off }
        #expect(UserDefaults.standard.bool(forKey: notchLabelMarkerKey))
        #expect(model.effectiveCenterLabel(for: .notch) == .off)
        #expect(model.islandCenterLabel == .off)
        #expect(model.islandClosedLabel() == nil)

        let afterExplicitOff = AppModel()
        afterExplicitOff.islandThemeID = "poured"
        afterExplicitOff.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        afterExplicitOff.state = SessionState(sessions: [running])
        #expect(afterExplicitOff.effectiveCenterLabel(for: .notch) == .off)
        #expect(afterExplicitOff.islandClosedLabel() == nil)

        // (b) an explicit `.off` — a real change through the user path — wins
        // under Poured and survives a fresh `AppModel`. The round-trip through
        // `.agentAction` is deliberate: it also pins that an actual stored
        // change still records the choice on its own, with no intent flag.
        model.updateAppearancePreferences(for: .notch) { $0.centerLabel = .agentAction }
        model.updateAppearancePreferences(for: .notch) { $0.centerLabel = .off }
        #expect(UserDefaults.standard.string(forKey: notchLabelKey) == IslandCenterLabel.off.rawValue)
        #expect(UserDefaults.standard.bool(forKey: notchLabelMarkerKey))
        #expect(model.islandCenterLabel == .off)
        #expect(model.islandClosedLabel() == nil)

        let reloaded = AppModel()
        reloaded.islandThemeID = "poured"
        reloaded.overlayPlacementDiagnostics = placementDiagnostics(mode: .notch)
        reloaded.state = SessionState(sessions: [running])
        #expect(reloaded.islandCenterLabel == .off)
        #expect(reloaded.islandClosedLabel() == nil)

        // (c3) explicitly opting in on the notch profile surfaces the label
        // under a non-Poured theme too, independent of the topBar profile.
        model.islandThemeID = "halo"
        model.updateAppearancePreferences(for: .notch) { $0.centerLabel = .agentAction }
        #expect(model.islandClosedLabel() != nil)
    }

    @Test
    func rolloutEventsDoNotPromoteRecoveredSessionsToAttachedDuringColdStart() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.isResolvingInitialLiveSessions = true
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "recovered-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .running,
                    summary: "Recovered from cache",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .activityUpdated(
                SessionActivityUpdated(
                    sessionID: "recovered-session",
                    summary: "Reading recent rollout lines.",
                    phase: .running,
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .rollout
        )

        #expect(model.liveSessionCount == 0)
        #expect(model.state.session(id: "recovered-session")?.attachmentState == .stale)
        #expect(model.shouldShowSessionBootstrapPlaceholder)
    }

    /// AB-243: reviving `notchPop()`. A completion that would otherwise be
    /// suppressed by the frontmost-session gate (the session's own terminal
    /// was already focused, so no notification card should steal attention)
    /// still earns a brief pill "pop" bump — but only while the overlay is
    /// closed, and only for completions (not permission/question events,
    /// which stay covered by `bridgeNotificationIsSuppressedWhenSessionIsAlreadyFrontmost`
    /// above showing no state change at all).
    @Test
    func completionSuppressedByFrontmostSessionStillPopsTheClosedPill() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel(
            isNotificationSessionAlreadyFrontmost: { session in
                session.id == "frontmost-session"
            }
        )
        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "frontmost-session",
                    title: "Codex · open-island",
                    tool: .codex,
                    origin: .live,
                    attachmentState: .attached,
                    phase: .running,
                    summary: "Already focused in the front terminal.",
                    updatedAt: now
                ),
            ]
        )

        model.applyTrackedEvent(
            .sessionCompleted(
                SessionCompleted(
                    sessionID: "frontmost-session",
                    summary: "Done while frontmost.",
                    timestamp: now.addingTimeInterval(1)
                )
            ),
            updateLastActionMessage: false,
            ingress: .bridge
        )

        var observedPopping = false
        for _ in 0..<20 {
            if model.notchStatus == .popping {
                observedPopping = true
                break
            }
            await Task.yield()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(observedPopping)
        // No notification card — the overlay never opened.
        #expect(model.islandSurface == .sessionList())
        #expect(model.notchOpenReason == nil)

        // `notchPop()` reverts to `.closed` on its own after ~0.3s.
        try await Task.sleep(for: .milliseconds(500))
        #expect(model.notchStatus == .closed)
    }

    @Test
    func mergeDiscoveredClaudeSessionsPreservesRegistryJumpTargetAndAddsTranscriptMetadata() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        model.state = SessionState(
            sessions: [
                AgentSession(
                    id: "claude-session",
                    title: "Claude · open-island",
                    tool: .claudeCode,
                    origin: .live,
                    attachmentState: .stale,
                    phase: .completed,
                    summary: "Recovered from registry",
                    updatedAt: now.addingTimeInterval(-60),
                    jumpTarget: JumpTarget(
                        terminalApp: "Ghostty",
                        workspaceName: "open-island",
                        paneTitle: "claude ~/open-island",
                        workingDirectory: "/tmp/open-island",
                        terminalSessionID: "ghostty-claude",
                        terminalTTY: "/dev/ttys002"
                    )
                ),
            ]
        )

        let merged = model.discovery.mergeDiscoveredSessions([
            AgentSession(
                id: "claude-session",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .running,
                summary: "Recovered from transcript",
                updatedAt: now,
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude deadbeef",
                    workingDirectory: "/tmp/open-island"
                ),
                claudeMetadata: ClaudeSessionMetadata(
                    transcriptPath: "/tmp/claude.jsonl",
                    lastUserPrompt: "Check the Claude session registry.",
                    currentTool: "Task"
                )
            ),
        ])

        #expect(merged.count == 1)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalSessionID == "ghostty-claude")
        #expect(merged.first?.claudeMetadata?.transcriptPath == "/tmp/claude.jsonl")
        #expect(merged.first?.claudeMetadata?.lastUserPrompt == "Check the Claude session registry.")
        #expect(merged.first?.phase == .running)
    }

    @Test
    func mergedWithSyntheticClaudeSessionsAddsGhosttyClaudeProcessWhenNoTrackedSessionExists() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: [],
            activeProcesses: [
                .init(
                    tool: .claudeCode,
                    sessionID: nil,
                    workingDirectory: "/tmp/open-island",
                    terminalTTY: "/dev/ttys002",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.count == 1)
        #expect(merged.first?.id.hasPrefix("claude-process:") == true)
        #expect(merged.first?.attachmentState == .attached)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalTTY == "/dev/ttys002")
    }

    @Test
    func sanitizeCrossToolGhosttyJumpTargetsClearsClaudeMisbinding() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let misboundClaudeSession = AgentSession(
            id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .running,
            summary: "Running",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "open-island",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/tmp/open-island",
                terminalSessionID: "ghostty-codex"
            )
        )

        let sanitized = model.monitoring.sanitizeCrossToolGhosttyJumpTargets(in: [misboundClaudeSession])

        #expect(sanitized.first?.jumpTarget?.terminalSessionID == nil)
        #expect(sanitized.first?.jumpTarget?.paneTitle == "Claude e45d5e87")
    }

    @Test
    func mergedWithSyntheticCursorSessionsAddsCursorAgentWhenNoTrackedSessionExists() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()

        let merged = model.monitoring.mergedWithSyntheticCursorSessions(
            existingSessions: [],
            activeProcesses: [
                .init(
                    tool: .cursor,
                    sessionID: "6f7b9f8a-2bd0-48b4-a497-9801dd191d03",
                    workingDirectory: "/tmp/simple-agent-lab",
                    terminalTTY: "/dev/ttys003",
                    terminalApp: "Ghostty"
                ),
            ],
            now: now
        )

        #expect(merged.count == 1)
        #expect(merged.first?.id == "6f7b9f8a-2bd0-48b4-a497-9801dd191d03")
        #expect(merged.first?.tool == .cursor)
        #expect(merged.first?.attachmentState == .attached)
        #expect(merged.first?.jumpTarget?.terminalApp == "Ghostty")
        #expect(merged.first?.jumpTarget?.terminalTTY == "/dev/ttys003")
        #expect(merged.first?.cursorMetadata?.conversationId == "6f7b9f8a-2bd0-48b4-a497-9801dd191d03")
    }

    /// Regression test: `measuredNotificationContentHeight` MUST be cleared when the
    /// surface changes to a different session, to avoid sizing the new card with stale
    /// measurements from the previous one.
    @Test
    @MainActor
    func approvalCardMeasuredHeightClearedWhenSurfaceSessionChanges() {
        let model = AppModel()

        var sessionA = AgentSession(
            id: "approval-session-A",
            title: "Claude · proj-A",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit A",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file_a.swift",
                affectedPath: "/tmp/file_a.swift"
            )
        )
        sessionA.isProcessAlive = true

        var sessionB = AgentSession(
            id: "approval-session-B",
            title: "Claude · proj-B",
            tool: .claudeCode,
            attachmentState: .attached,
            phase: .waitingForApproval,
            summary: "Approve edit B",
            updatedAt: .now,
            permissionRequest: PermissionRequest(
                title: "Edit",
                summary: "file_b.swift",
                affectedPath: "/tmp/file_b.swift"
            )
        )
        sessionB.isProcessAlive = true

        model.state = SessionState(sessions: [sessionA, sessionB])

        let surfaceA = IslandSurface.sessionList(actionableSessionID: "approval-session-A")
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = surfaceA
        model.measuredNotificationContentHeight = 320

        model.notchClose()

        let surfaceB = IslandSurface.sessionList(actionableSessionID: "approval-session-B")
        model.notchOpen(reason: .notification, surface: surfaceB)

        #expect(
            model.measuredNotificationContentHeight == 0,
            "Switching to a different session's card must clear the stale measurement from the previous session to prevent wrong initial panel sizing."
        )
    }

    @Test
    func recoveredSessionMatchesLiveGhosttyProcessByCWDWhenMultipleCandidatesExist() {
        let now = Date(timeIntervalSince1970: 2_000)
        let model = AppModel()
        let recoveredSessions = [
            AgentSession(
                id: "e45d5e87-66d0-4f67-8399-6ebc02f3d453",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .completed,
                summary: "Recovered transcript",
                updatedAt: now.addingTimeInterval(-10_800),
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude e45d5e87",
                    workingDirectory: "/tmp/open-island"
                )
            ),
            AgentSession(
                id: "c9a48d05-c1f9-4e39-ab66-19edef0c2bc9",
                title: "Claude · open-island",
                tool: .claudeCode,
                origin: .live,
                attachmentState: .stale,
                phase: .completed,
                summary: "Recovered transcript",
                updatedAt: now.addingTimeInterval(-64_800),
                jumpTarget: JumpTarget(
                    terminalApp: "Unknown",
                    workspaceName: "open-island",
                    paneTitle: "Claude c9a48d05",
                    workingDirectory: "/tmp/open-island"
                )
            ),
        ]
        let activeProcesses: [ActiveProcessSnapshot] = [
            .init(
                tool: .claudeCode,
                sessionID: nil,
                workingDirectory: "/tmp/open-island",
                terminalTTY: "/dev/ttys002",
                terminalApp: "Ghostty"
            ),
        ]

        let merged = model.monitoring.mergedWithSyntheticClaudeSessions(
            existingSessions: recoveredSessions,
            activeProcesses: activeProcesses,
            now: now
        )

        // With relaxed CWD matching, recovered session matches the process
        // so no synthetic session is created.
        #expect(merged.count == 2)
        #expect(merged.allSatisfy { !$0.id.hasPrefix("claude-process:") })

        let probe = TerminalSessionAttachmentProbe()
        let resolutions = probe.sessionResolutions(
            for: merged,
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: activeProcesses,
            now: now
        )

        model.state = SessionState(sessions: merged)
        _ = model.state.reconcileAttachmentStates(resolutions.mapValues(\.attachmentState))
        _ = model.state.reconcileJumpTargets(
            resolutions.reduce(into: [String: JumpTarget]()) { partialResult, entry in
                if let correctedJumpTarget = entry.value.correctedJumpTarget {
                    partialResult[entry.key] = correctedJumpTarget
                }
            }
        )

        let claudeSessions = model.state.sessions.filter { $0.tool == .claudeCode }
        #expect(claudeSessions.count == 2)
    }

    private func listSession(id: String, phase: SessionPhase, updatedAt: Date) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(id)",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: phase.displayName,
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "codex ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            )
        )
    }

    private func placementDiagnostics(mode: OverlayPlacementMode) -> OverlayPlacementDiagnostics {
        OverlayPlacementDiagnostics(
            targetScreenID: mode == .notch ? "display-notch" : "display-topbar",
            targetScreenName: mode == .notch ? "Built-in Display" : "External Display",
            selectionSummary: "test",
            mode: mode,
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: mode == .notch ? 37 : 0, left: 0, bottom: 0, right: 0),
            overlayFrame: NSRect(x: 400, y: 820, width: 700, height: 160)
        )
    }
}
