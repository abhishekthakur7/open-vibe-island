import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

struct AgentSessionPresentationTests {
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
    func displayModelNameRendersFableAndMythosWithoutTheVendorWord() {
        #expect(AgentSession.shortModelDisplayName(for: "claude-fable-5") == "Fable 5")
        #expect(AgentSession.shortModelDisplayName(for: "claude-fable-5-20260101") == "Fable 5")
        #expect(AgentSession.shortModelDisplayName(for: "claude-mythos-5") == "Mythos 5")
        #expect(AgentSession.shortModelDisplayName(for: "anthropic/claude-fable-5") == "Fable 5")
        // Bare alias, no version.
        #expect(AgentSession.shortModelDisplayName(for: "fable") == "Fable")

        let withFableModel = AgentSession(
            id: "session-4",
            title: "Claude · repo",
            tool: .claudeCode,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            claudeMetadata: ClaudeSessionMetadata(model: "claude-fable-5-20260101")
        )
        #expect(withFableModel.displayModelName == "Fable 5")

        // Cross-vendor sessions keep an identifiable family name.
        let withOpenCodeModel = AgentSession(
            id: "session-5",
            title: "OpenCode · repo",
            tool: .openCode,
            phase: .running,
            summary: "Working",
            updatedAt: .now,
            openCodeMetadata: OpenCodeSessionMetadata(model: "anthropic/claude-fable-5")
        )
        #expect(withOpenCodeModel.displayModelName == "Fable 5")
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
