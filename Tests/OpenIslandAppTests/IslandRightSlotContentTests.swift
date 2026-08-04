import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-322 Part B — the closed pill's right-slot priority ladder.
///
/// The ladder is the whole point of the ticket: attention → task counter →
/// critical usage → the user's resting preference. Every case here is
/// given/when/then against the pure `IslandRightSlotResolver`, so nothing
/// depends on an overlay, a usage cache or the wall clock.
struct IslandRightSlotResolverTests {

    // MARK: - Priority ladder

    /// Permission outranks question: an approval blocks the agent's next tool
    /// call, an unanswered question only blocks the conversation.
    @Test
    func permissionBeatsQuestionWhenBothAreWaiting() {
        let content = IslandRightSlotResolver.content(
            attention: .init(count: 2, hasPermission: true),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: .count(5)
        )
        #expect(content == .attentionCount(count: 2, kind: .permission))
    }

    /// Any attention outranks a busy task list — the pill's job while blocked
    /// is to say "you are the blocker", not to narrate progress.
    @Test
    func anyAttentionBeatsTaskCounter() {
        let content = IslandRightSlotResolver.content(
            attention: .init(count: 1, hasPermission: false),
            spotlightTasks: .init(isRunning: true, completed: 2, total: 5, subagents: 3),
            worstUsage: .init(percent: 99, windowLabel: "5h", providerTitle: "Claude"),
            preferred: .count(4)
        )
        #expect(content == .attentionCount(count: 1, kind: .question))
    }

    /// Tasks outrank usage: what the agent is doing right now beats a rate
    /// limit that will still be there in a minute.
    @Test
    func taskCounterBeatsUsage() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(isRunning: true, completed: 2, total: 5, subagents: 0),
            worstUsage: .init(percent: 97, windowLabel: "7d", providerTitle: "Claude"),
            preferred: .count(1)
        )
        #expect(content == .taskCounter(completed: 2, total: 5, subagents: 0))
    }

    /// A finished / waiting spotlight would leave a frozen counter on the pill,
    /// so only a running session narrates progress.
    @Test
    func taskCounterRequiresARunningSpotlight() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(isRunning: false, completed: 2, total: 5, subagents: 3),
            worstUsage: nil,
            preferred: .count(2)
        )
        #expect(content == .count(2))
    }

    /// Exactly at the threshold the badge appears — the comparison is `>=`.
    @Test
    func usageAtThresholdIsReported() {
        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 90.0, windowLabel: "5h", providerTitle: "Claude"),
            preferred: .count(3)
        )
        #expect(content == .usage(percent: 90, windowLabel: "5h", providerTitle: "Claude"))
    }

    /// Quiet state: the user's preference is what's left.
    @Test
    func fallsThroughToTheUserPreference() {
        let quiet = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 12, windowLabel: "5h", providerTitle: "Claude"),
            preferred: .count(4)
        )
        #expect(quiet == .count(4))

        let grid = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: .agents([.session(color: .red, state: .running)])
        )
        #expect(grid == .agents([.session(color: .red, state: .running)]))

        let off = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: nil
        )
        #expect(off == nil)
    }

    /// A `.none` preference silences the *resting* content, not a blocked
    /// agent — the pill must still be able to report that it needs the user.
    @Test
    func attentionOverridesANonePreference() {
        let content = IslandRightSlotResolver.content(
            attention: .init(count: 3, hasPermission: true),
            spotlightTasks: .init(),
            worstUsage: nil,
            preferred: nil
        )
        #expect(content == .attentionCount(count: 3, kind: .permission))
    }

    /// The worst window wins across *all* providers, carrying its own labels.
    @Test
    func worstUsagePicksTheHighestWindowAcrossProviders() {
        let providers = [
            UsageProviderPresentation(id: "claude", title: "Claude", windows: [
                UsageWindowPresentation(id: "claude-5h", label: "5h", usedPercentage: 41, resetsAt: nil),
                UsageWindowPresentation(id: "claude-7d", label: "7d", usedPercentage: 88, resetsAt: nil),
            ]),
            UsageProviderPresentation(id: "codex", title: "Codex", windows: [
                UsageWindowPresentation(id: "codex-weekly", label: "weekly", usedPercentage: 93, resetsAt: nil),
            ]),
        ]

        let worst = IslandRightSlotResolver.worstUsage(in: providers)
        #expect(worst == .init(percent: 93, windowLabel: "weekly", providerTitle: "Codex"))
        #expect(IslandRightSlotResolver.worstUsage(in: []) == nil)
    }

    /// G-32 (halo parity V9): the winning window's `resetsAt` rides along, all
    /// the way into the `.usage` payload, so a pill can render the board's third
    /// token (the `19h` countdown) instead of the window label. Additive — a
    /// window without a reset time still produces the three-token payload every
    /// other theme reads, byte-identical to before.
    @Test
    func worstUsageCarriesTheWindowResetTimeIntoTheUsagePayload() {
        let resetsAt = Date(timeIntervalSince1970: 1_800_000_000)
        let providers = [
            UsageProviderPresentation(id: "codex", title: "Codex", windows: [
                UsageWindowPresentation(id: "codex-7d", label: "7d", usedPercentage: 92, resetsAt: resetsAt),
            ]),
        ]

        let worst = IslandRightSlotResolver.worstUsage(in: providers)
        #expect(worst?.resetsAt == resetsAt)

        let content = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: worst,
            preferred: nil
        )
        #expect(
            content == .usage(
                percent: 92,
                windowLabel: "7d",
                providerTitle: "Codex",
                resetsAt: resetsAt
            )
        )

        // No reset time reported ⇒ the pre-G-32 payload, unchanged.
        let withoutReset = IslandRightSlotResolver.content(
            attention: .init(),
            spotlightTasks: .init(),
            worstUsage: .init(percent: 92, windowLabel: "7d", providerTitle: "Codex"),
            preferred: nil
        )
        #expect(withoutReset == .usage(percent: 92, windowLabel: "7d", providerTitle: "Codex"))
    }

}

/// The `AppModel` side of AB-322 Part B: the adapter feeds live state into the
/// resolver, so what the agents are doing outranks the resting preference.
@MainActor
struct IslandRightSlotAdapterTests {

    @Test
    func waitingSessionOverridesTheAgentsGridPreference() {
        let model = AppModel()
        // Pin the preference on *both* display profiles: which one is active
        // resolves from the attached screens asynchronously, so setting only
        // `islandRightSlot` would land in whichever bucket happened to be
        // active at that instant.
        setRightSlotPreference(.agents, on: model)

        let now = Date.now
        model.state = SessionState(sessions: [
            makeSession(id: "run", phase: .running, at: now),
            makeSession(
                id: "approve",
                phase: .waitingForApproval,
                at: now,
                permissionRequest: PermissionRequest(title: "edit", summary: "edit", affectedPath: "/tmp/x")
            ),
        ])

        #expect(model.islandClosedRightSlotContent() == .attentionCount(count: 1, kind: .permission))

        // The preference itself is untouched — it still resolves to the grid.
        guard case .agents(let cells)? = model.islandPreferredRightSlotContent() else {
            Issue.record("Expected the preference to still resolve to .agents")
            return
        }
        #expect(cells.count == 2)
    }

    @Test
    func runningSpotlightWithTasksReportsProgress() {
        let model = AppModel()
        setRightSlotPreference(.count, on: model)

        let now = Date.now
        var session = makeSession(id: "run", phase: .running, at: now)
        session.claudeMetadata = ClaudeSessionMetadata(
            transcriptPath: "/tmp/run.jsonl",
            activeSubagents: [ClaudeSubagentInfo(agentID: "a")],
            activeTasks: [
                ClaudeTaskInfo(id: "1", title: "one", status: .completed),
                ClaudeTaskInfo(id: "2", title: "two", status: .pending),
            ]
        )
        model.state = SessionState(sessions: [session])

        #expect(model.islandClosedRightSlotContent() == .taskCounter(completed: 1, total: 2, subagents: 1))
    }

    private func setRightSlotPreference(_ slot: IslandRightSlot, on model: AppModel) {
        model.updateAppearancePreferences(for: .notch) { $0.rightSlot = slot }
        model.updateAppearancePreferences(for: .topBar) { $0.rightSlot = slot }
    }

    private func makeSession(
        id: String,
        phase: SessionPhase,
        at date: Date,
        permissionRequest: PermissionRequest? = nil
    ) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · \(id)",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            summary: "",
            updatedAt: date,
            firstSeenAt: date,
            permissionRequest: permissionRequest,
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: id,
                paneTitle: "claude ~/\(id)",
                workingDirectory: "/tmp/\(id)",
                terminalSessionID: "ghostty-\(id)"
            ),
            claudeMetadata: ClaudeSessionMetadata(transcriptPath: "/tmp/\(id).jsonl")
        )
        session.isProcessAlive = true
        session.isHookManaged = true
        return session
    }
}
