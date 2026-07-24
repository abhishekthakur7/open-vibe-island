import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct AgentSessionPresentationTests {
    @Test
    func attachedCompletedSessionStaysActiveWhileRecent() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_199),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .active)
    }

    @Test
    func attachedCompletedSessionCollapsesWhenOld() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_201),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Initial prompt",
                lastUserPrompt: "Follow-up prompt",
                lastAssistantMessage: "Last assistant message"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .inactive)
        #expect(session.spotlightShowsDetailLines(at: referenceDate) == false)
    }

    @Test
    func detachedCompletedSessionCanStillCollapseToInactive() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_801)
        )

        #expect(session.islandPresence(at: referenceDate) == .inactive)
        #expect(session.spotlightShowsDetailLines(at: referenceDate) == false)
    }

    @Test
    func detachedCompletedSessionStaysActiveWithinTwentyMinutes() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-1_199),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Follow-up prompt",
                lastAssistantMessage: "Last assistant message"
            )
        )

        #expect(session.islandPresence(at: referenceDate) == .active)
        #expect(session.spotlightShowsDetailLines(at: referenceDate))
    }

    @Test
    func completionReplyRecipientCoversEveryAgentTool() {
        let expectedNames: [(AgentTool, String)] = [
            (.claudeCode, "Claude"),
            (.codex, "Codex"),
            (.geminiCLI, "Gemini"),
            (.openCode, "OpenCode"),
            (.qoder, "Qoder"),
            (.qwenCode, "Qwen Code"),
            (.factory, "Factory"),
            (.codebuddy, "CodeBuddy"),
            (.cursor, "Cursor"),
            (.kimiCLI, "Kimi"),
        ]
        #expect(expectedNames.map { $0.0.rawValue }.sorted() == AgentTool.allCases.map(\.rawValue).sorted())

        for (tool, expectedName) in expectedNames {
            let session = AgentSession(
                id: "\(tool.rawValue)-session",
                title: "\(expectedName) · worktree",
                tool: tool,
                phase: .completed,
                summary: "Ready",
                updatedAt: .now
            )

            #expect(session.completionReplyRecipientName == expectedName)
        }
    }

    @Test
    func completedSessionBecomesV8StaleAfterFiveMinutes() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-301)
        )

        #expect(session.isStaleCompletedForIsland(at: referenceDate))
        #expect(session.islandPresence(at: referenceDate) == .active)
    }

    @Test
    func completedSessionDoesNotBecomeV8StaleWhenThresholdIsNever() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: referenceDate.addingTimeInterval(-86_400)
        )

        #expect(!session.isStaleCompletedForIsland(
            at: referenceDate,
            threshold: IslandCompletedStaleThreshold.never.seconds
        ))
    }

    @Test
    func nonCompletedSessionsDoNotBecomeV8Stale() {
        let referenceDate = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: referenceDate.addingTimeInterval(-3_600)
        )

        #expect(!session.isStaleCompletedForIsland(at: referenceDate))
    }

    @Test
    func liveHeadlineUsesLatestPromptForAttachedSession() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Start by fixing the island hover behavior.",
                lastUserPrompt: "Now make the overlay height fit the content.",
                lastAssistantMessage: "Updating the layout logic."
            )
        )

        // Headline uses initial prompt (session topic), prompt line uses latest
        #expect(session.spotlightHeadlineText == "worktree · Start by fixing the island hover behavior.")
        #expect(session.spotlightPromptLineText == "You: Now make the overlay height fit the content.")
    }

    @Test
    func detachedSessionHeadlineShowsInitialPrompt() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .detached,
            phase: .completed,
            summary: "Done",
            updatedAt: Date.now.addingTimeInterval(-30),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Start by fixing the island hover behavior.",
                lastUserPrompt: "Now make the overlay height fit the content.",
                lastAssistantMessage: "Updating the layout logic."
            )
        )

        #expect(session.spotlightHeadlineText == "worktree · Start by fixing the island hover behavior.")
        #expect(session.spotlightPromptLineText == "You: Now make the overlay height fit the content.")
    }

    @Test
    func completedSessionShowsDifferentHeadlineAndPrompt() {
        let now = Date.now
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Done",
            updatedAt: now.addingTimeInterval(-30),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: "worktree",
                paneTitle: "codex ~/tmp/worktree",
                workingDirectory: "/tmp/worktree",
                terminalSessionID: "ghostty-1"
            ),
            codexMetadata: CodexSessionMetadata(
                initialUserPrompt: "Commit the README change.",
                lastUserPrompt: "Also confirm the worktree status.",
                lastAssistantMessage: "Committed and verified."
            )
        )

        #expect(session.spotlightHeadlineText == "worktree · Commit the README change.")
        #expect(session.spotlightPromptLineText == "You: Also confirm the worktree status.")
        #expect(session.notificationHeaderPromptLineText == nil)
    }

    @Test
    func runningCodexSessionWithoutToolShowsThinkingBesidePrompt() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Thinking.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Align the Codex statuses."
            )
        )

        #expect(session.spotlightPromptLineText == "You: Align the Codex statuses.")
        #expect(session.spotlightActivityLineText == "Thinking")
        #expect(session.displayCurrentToolName == nil)
    }

    @Test
    func runningCodexSessionKeepsWriteStdinAsInput() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running input.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Continue the command.",
                currentTool: "write_stdin",
                currentCommandPreview: "y"
            )
        )

        #expect(session.spotlightActivityLineText == "Input y")
        #expect(session.spotlightStatusLabel == "Live · Input")
        #expect(session.displayCurrentToolName == "Input")
    }

    @Test
    func runningCodexSessionDisplaysWebSearchAction() {
        let session = AgentSession(
            id: "session-1",
            title: "Codex · worktree",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: .running,
            summary: "Running web search.",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            codexMetadata: CodexSessionMetadata(
                lastUserPrompt: "Check the Codex repo.",
                currentTool: "web_search",
                currentCommandPreview: "Codex rollout ResponseItem"
            )
        )

        #expect(session.spotlightActivityLineText == "Search Codex rollout ResponseItem")
        #expect(session.spotlightStatusLabel == "Live · Search")
        #expect(session.spotlightSecondaryText == "Running Search")
        #expect(session.displayCurrentToolName == "Search")
    }

    // MARK: - AB-230: model badge

    @Test
    func displayModelNameShortensRealClaudeAndCursorModelIDs() {
        #expect(AgentSession.shortModelDisplayName(for: "claude-sonnet-4-5") == "Sonnet 4.5")
        // Cursor's raw model string puts the family keyword after the version.
        #expect(AgentSession.shortModelDisplayName(for: "claude-4.6-opus") == "Opus 4.6")
        #expect(AgentSession.shortModelDisplayName(for: "claude-opus-4-6-20260101") == "Opus 4.6")
        #expect(AgentSession.shortModelDisplayName(for: "gpt-5-codex") == "GPT-5")
        #expect(AgentSession.shortModelDisplayName(for: "gpt-5.3-codex-replay") == "GPT-5.3")
        // Bare alias, no version.
        #expect(AgentSession.shortModelDisplayName(for: "opus") == "Opus")
        // Unrecognized family falls back to a humanized form instead of crashing.
        #expect(AgentSession.shortModelDisplayName(for: "custom-router-model") == "Custom Router Model")
    }

    @Test
    func displayModelNameIsNilWithoutMetadataAndPicksFirstAvailableSource() {
        let withoutMetadata = AgentSession(
            id: "session-1",
            title: "Claude · repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
        #expect(withoutMetadata.displayModelName == nil)

        let withClaudeModel = AgentSession(
            id: "session-2",
            title: "Claude · repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            claudeMetadata: ClaudeSessionMetadata(model: "claude-opus-4-6-20260101")
        )
        #expect(withClaudeModel.displayModelName == "Opus 4.6")

        let withCursorModel = AgentSession(
            id: "session-3",
            title: "Cursor · repo",
            tool: .cursor,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            cursorMetadata: CursorSessionMetadata(model: "gpt-5-codex")
        )
        #expect(withCursorModel.displayModelName == "GPT-5")
    }

    // MARK: - AB-230: elapsed running time

    @Test
    func elapsedRunningLabelUsesFirstSeenAtNotLastUpdate() {
        let firstSeenAt = Date(timeIntervalSince1970: 10_000)
        let session = AgentSession(
            id: "session-1",
            title: "Claude · repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            // updatedAt is recent — spotlightAgeBadge would read "<1m" here —
            // but the session has actually been running much longer.
            updatedAt: firstSeenAt.addingTimeInterval(370),
            firstSeenAt: firstSeenAt
        )

        #expect(session.elapsedRunningLabel(at: firstSeenAt.addingTimeInterval(30)) == "<1m")
        #expect(session.elapsedRunningLabel(at: firstSeenAt.addingTimeInterval(370)) == "6m")
        #expect(session.elapsedRunningLabel(at: firstSeenAt.addingTimeInterval(3_900)) == "1h 5m")
        #expect(session.elapsedRunningLabel(at: firstSeenAt.addingTimeInterval(90_000)) == "1d 1h")
    }

    // MARK: - AB-283: terminal badge hides the unclassified sentinel

    @Test
    func spotlightTerminalBadgeHidesUnknownSentinel() {
        let session = sessionWithTerminalApp(JumpTarget.unknownTerminalApp)

        #expect(session.spotlightTerminalBadge == nil)
    }

    @Test
    func spotlightTerminalBadgePassesThroughRealHost() {
        #expect(sessionWithTerminalApp("Ghostty").spotlightTerminalBadge == "Ghostty")
        #expect(sessionWithTerminalApp("Warp").spotlightTerminalBadge == "Warp")
        #expect(sessionWithTerminalApp("Codex.app").spotlightTerminalBadge == "Codex.app")
    }

    @Test
    func spotlightTerminalBadgeIsNilWithoutJumpTarget() {
        let session = AgentSession(
            id: "session-1",
            title: "Claude · repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000)
        )

        #expect(session.spotlightTerminalBadge == nil)
    }

    private func sessionWithTerminalApp(_ terminalApp: String) -> AgentSession {
        AgentSession(
            id: "session-1",
            title: "Claude · repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: Date(timeIntervalSince1970: 10_000),
            jumpTarget: JumpTarget(
                terminalApp: terminalApp,
                workspaceName: "repo",
                paneTitle: "claude ~/repo",
                workingDirectory: "/tmp/repo"
            )
        )
    }
}
