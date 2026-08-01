import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct TerminalSessionAttachmentProbeTests {
    @Test
    func ghosttyKeepsOnlyNewestSessionAttachedPerSnapshot() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let older = ghosttySession(
            id: "older",
            updatedAt: now.addingTimeInterval(-60),
            phase: .completed,
            terminalSessionID: "ghostty-1"
        )
        let newer = ghosttySession(
            id: "newer",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-1"
        )

        let updates = probe.attachmentStates(
            for: [older, newer],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-1", workingDirectory: "/tmp/worktree", title: "codex ~/tmp/worktree")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["newer"] == .attached)
        #expect(updates["older"] == .stale)
    }

    @Test
    func ghosttyStableIdentifierPreventsWorkingDirectoryFallbackMatches() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = ghosttySession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            terminalSessionID: "ghostty-stale",
            paneTitle: "codex ~/tmp/worktree"
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .available(
                [.init(sessionID: "ghostty-active", workingDirectory: "/tmp/worktree", title: "codex ~/tmp/worktree")],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["session-1"] == .stale)
    }

    @Test
    func ghosttyRehomesMisbindingWhenRecordedTerminalIsAlreadyClaimed() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let primary = ghosttySession(
            id: "primary",
            updatedAt: now,
            phase: .running,
            terminalSessionID: "ghostty-1",
            workingDirectory: "/tmp/worktree"
        )
        let rehomed = ghosttySession(
            id: "rehomed",
            updatedAt: now.addingTimeInterval(-30),
            phase: .completed,
            terminalSessionID: "ghostty-1",
            paneTitle: "codex ~/tmp/worktree",
            workingDirectory: "/tmp/personal",
            workspaceName: "worktree"
        )

        let resolutions = probe.sessionResolutions(
            for: [primary, rehomed],
            ghosttyAvailability: .available(
                [
                    .init(sessionID: "ghostty-1", workingDirectory: "/tmp/worktree", title: "codex ~/tmp/worktree"),
                    .init(sessionID: "ghostty-2", workingDirectory: "/tmp/personal", title: "codex ~/tmp/personal"),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(resolutions["primary"]?.attachmentState == .attached)
        #expect(resolutions["rehomed"]?.attachmentState == .attached)
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.terminalSessionID == "ghostty-2")
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.paneTitle == "codex ~/tmp/personal")
        #expect(resolutions["rehomed"]?.correctedJumpTarget?.workspaceName == "personal")
    }

    @Test
    func explicitTerminalMissDropsRecentlyAttachedSessionOutOfLiveState() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = terminalSession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            tty: "/dev/ttys001",
            codexMetadata: CodexSessionMetadata(currentTool: "Bash")
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .available([] as [TerminalSessionAttachmentProbe.GhosttyTerminalSnapshot], appIsRunning: false),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: true),
            now: now
        )

        #expect(updates["session-1"] == .stale)
    }

    @Test
    func unavailableGhosttyProbeRetainsRecentGraceState() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let session = ghosttySession(
            id: "session-1",
            updatedAt: now.addingTimeInterval(-30),
            phase: .running,
            terminalSessionID: "ghostty-1"
        )

        let updates = probe.attachmentStates(
            for: [session],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["session-1"] == .attached)
    }

    @Test
    func activeClaudeProcessDoesNotAttachAmbiguousSameDirectorySessionsWithoutStrongerSignals() {
        let now = Date(timeIntervalSince1970: 1_000)
        let probe = TerminalSessionAttachmentProbe()
        let currentSession = AgentSession(
            id: "claude-current",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Current session",
            updatedAt: now,
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "open-island",
                paneTitle: "Claude current",
                workingDirectory: "/tmp/open-island"
            )
        )
        let olderSession = AgentSession(
            id: "claude-older",
            title: "Claude · open-island",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .stale,
            phase: .completed,
            summary: "Older session",
            updatedAt: now.addingTimeInterval(-18 * 3_600),
            jumpTarget: JumpTarget(
                terminalApp: "Unknown",
                workspaceName: "open-island",
                paneTitle: "Claude older",
                workingDirectory: "/tmp/open-island"
            )
        )

        let updates = probe.attachmentStates(
            for: [currentSession, olderSession],
            ghosttyAvailability: .unavailable(appIsRunning: true),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            activeProcesses: [
                .init(tool: .claudeCode, sessionID: nil, workingDirectory: "/tmp/open-island", terminalTTY: "/dev/ttys002"),
            ],
            now: now
        )

        #expect(updates["claude-current"] != .attached)
        #expect(updates["claude-older"] != .attached)
    }

    @Test
    func ghosttySessionListRegressionOnlyKeepsLiveLookingTabsAttached() {
        let now = Date(timeIntervalSince1970: 10_000)
        let probe = TerminalSessionAttachmentProbe()
        let sessions = [
            ghosttySession(
                id: "019d540b-0985-7913-9ad1-0e87f12c918f",
                updatedAt: now.addingTimeInterval(-30),
                phase: .running,
                terminalSessionID: "8B3E80D7-26C5-457E-A390-2F0B8B584EF2",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/Users/wangruobing/personal/open-island",
                workspaceName: "open-island"
            ),
            ghosttySession(
                id: "019d52de-0a11-7053-adf2-76f106393e42",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "448D7E28-24FB-46F1-9504-C252F97926C1",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/Users/wangruobing/personal/open-island",
                workspaceName: "open-island"
            ),
            ghosttySession(
                id: "019d52dd-8e5a-7602-b618-3f4ec447ac72",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "1FF8D5F5-7C34-4CC7-BF93-4F67DA197E5D",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/Users/wangruobing/personal/open-island",
                workspaceName: "open-island"
            ),
            ghosttySession(
                id: "019d52ee-55b3-7712-9c3b-b2d9c038e04d",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "BAA8EBC8-DC99-4720-9F14-A6BAF55DFC62",
                paneTitle: "codex ~/p/open-island",
                workingDirectory: "/Users/wangruobing/personal/open-island",
                workspaceName: "open-island"
            ),
            ghosttySession(
                id: "019d51f5-0234-7ec3-9494-8b0e4d1b670e",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                phase: .completed,
                terminalSessionID: "DD5A5488-E789-4326-BA5C-6A0BDFB0A51F",
                paneTitle: "codex ~/p/vibe-island",
                workingDirectory: "/Users/wangruobing/personal/vibe-island",
                workspaceName: "vibe-island"
            ),
            AgentSession(
                id: "session-approval",
                title: "Codex · open-island",
                tool: .codex,
                origin: .live,
                attachmentState: .attached,
                phase: .waitingForApproval,
                summary: "Approval needed",
                updatedAt: now.addingTimeInterval(-18 * 3_600),
                jumpTarget: JumpTarget(
                    terminalApp: "Ghostty",
                    workspaceName: "open-island",
                    paneTitle: "codex ~/p/open-island",
                    workingDirectory: "/Users/wangruobing/personal/open-island",
                    terminalSessionID: "ghostty-approval"
                ),
                codexMetadata: CodexSessionMetadata(
                    currentTool: "exec_command",
                    currentCommandPreview: "head -5000 SettingsView.swift"
                )
            ),
        ]

        let updates = probe.attachmentStates(
            for: sessions,
            ghosttyAvailability: .available(
                [
                    .init(
                        sessionID: "8B3E80D7-26C5-457E-A390-2F0B8B584EF2",
                        workingDirectory: "/Users/wangruobing/personal/open-island",
                        title: "codex ~/p/open-island"
                    ),
                    .init(
                        sessionID: "448D7E28-24FB-46F1-9504-C252F97926C1",
                        workingDirectory: "/Users/wangruobing/personal/open-island",
                        title: "codex ~/p/open-island"
                    ),
                    .init(
                        sessionID: "1FF8D5F5-7C34-4CC7-BF93-4F67DA197E5D",
                        workingDirectory: "/Users/wangruobing/personal/open-island",
                        title: "~/p/open-island"
                    ),
                    .init(
                        sessionID: "BAA8EBC8-DC99-4720-9F14-A6BAF55DFC62",
                        workingDirectory: "/Users/wangruobing/personal/open-island",
                        title: "~/p/open-island"
                    ),
                    .init(
                        sessionID: "DD5A5488-E789-4326-BA5C-6A0BDFB0A51F",
                        workingDirectory: "/Users/wangruobing/personal/vibe-island",
                        title: "~/p/vibe-island"
                    ),
                ],
                appIsRunning: true
            ),
            terminalAvailability: .available([] as [TerminalSessionAttachmentProbe.TerminalTabSnapshot], appIsRunning: false),
            now: now
        )

        #expect(updates["019d540b-0985-7913-9ad1-0e87f12c918f"] == .attached)
        #expect(updates["019d52de-0a11-7053-adf2-76f106393e42"] == .attached)
        #expect(updates["019d52dd-8e5a-7602-b618-3f4ec447ac72"] == .detached)
        #expect(updates["019d52ee-55b3-7712-9c3b-b2d9c038e04d"] == .detached)
        #expect(updates["019d51f5-0234-7ec3-9494-8b0e4d1b670e"] == .detached)
        #expect(updates["session-approval"] == .detached)
    }

    private func ghosttySession(
        id: String,
        updatedAt: Date,
        phase: SessionPhase,
        terminalSessionID: String,
        paneTitle: String = "codex ~/tmp/worktree",
        workingDirectory: String = "/tmp/worktree",
        workspaceName: String = "worktree",
        codexMetadata: CodexSessionMetadata? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(workspaceName)",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Summary",
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspaceName,
                paneTitle: paneTitle,
                workingDirectory: workingDirectory,
                terminalSessionID: terminalSessionID
            ),
            codexMetadata: codexMetadata
        )
    }

    private func terminalSession(
        id: String,
        updatedAt: Date,
        phase: SessionPhase,
        tty: String,
        codexMetadata: CodexSessionMetadata? = nil
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "Summary",
            updatedAt: updatedAt,
            jumpTarget: JumpTarget(
                terminalApp: "Terminal",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalTTY: tty
            ),
            codexMetadata: codexMetadata
        )
    }
}
