import Testing
@testable import OpenIslandApp

struct IslandDebugScenarioTests {
    @Test
    func allDebugScenarioSessionsAreDemoSessions() {
        for scenario in IslandDebugScenario.allCases {
            let snapshot = scenario.snapshot()
            #expect(snapshot.sessions.allSatisfy { $0.origin == .demo })
        }
    }

    /// Overlay remediation Phase 1 item 1.7 (P1.a): `subagentsExpanded` is the
    /// only scenario reachable from `IslandDebugScenario` that forces the row
    /// expansion seam (`\.islandRowExpandedByDefault`) open; `subagentsCard`
    /// must keep documenting the collapsed row it always has.
    @Test
    func subagentsExpandedForcesRowExpansionWhileSubagentsCardStaysCollapsed() {
        #expect(IslandDebugScenario.subagentsExpanded.snapshot().forcesRowExpansion)
        #expect(!IslandDebugScenario.subagentsCard.snapshot().forcesRowExpansion)

        for scenario in IslandDebugScenario.allCases where scenario != .subagentsExpanded {
            #expect(
                !scenario.snapshot().forcesRowExpansion,
                "\(scenario.rawValue) unexpectedly forces row expansion"
            )
        }
    }

    /// `subagentsExpanded` exists solely to add expansion on top of
    /// `subagentsCard` (mockup §D/§G becomes capturable) — everything else
    /// about the two snapshots, including the underlying fixture and the
    /// surface config, must match so the pair is a clean collapsed/expanded
    /// A-B comparison.
    @Test
    func subagentsExpandedReusesSubagentsCardFixtureAndSurface() {
        let collapsed = IslandDebugScenario.subagentsCard.snapshot()
        let expanded = IslandDebugScenario.subagentsExpanded.snapshot()

        #expect(expanded.notchStatus == collapsed.notchStatus)
        #expect(expanded.notchOpenReason == collapsed.notchOpenReason)
        #expect(expanded.islandSurface == collapsed.islandSurface)
        #expect(expanded.selectedSessionID == collapsed.selectedSessionID)
        #expect(expanded.sessions.map(\.id) == collapsed.sessions.map(\.id))
    }

    @Test
    func ordinaryActionableFixturesAreClaudeBackedWithTruthfulModelAndBranchMetadata() {
        let approval = IslandDebugScenario.approvalCard.snapshot().sessions.first
        let question = IslandDebugScenario.questionCard.snapshot().sessions.first

        #expect(approval?.tool == .claudeCode)
        #expect(approval?.claudeMetadata?.model == "claude-opus-4-8-20260101")
        #expect(approval?.claudeMetadata?.worktreeBranch == "feat/approval-flow")
        #expect(approval?.codexMetadata == nil)

        #expect(question?.tool == .claudeCode)
        #expect(question?.claudeMetadata?.model == "claude-sonnet-5-20260101")
        #expect(question?.claudeMetadata?.worktreeBranch == "feat/question-flow")
        #expect(question?.codexMetadata == nil)
    }

    @Test
    func codexApprovalFixtureRemainsCodexOnlyWithoutFabricatedBranch() {
        let session = IslandDebugScenario.codexApprovalCard.snapshot().sessions.first

        #expect(session?.tool == .codex)
        #expect(session?.claudeMetadata == nil)
    }

    @Test
    func completionFixturesExposeTranscriptAffordancePaths() {
        let completion = IslandDebugScenario.completionCard.snapshot().sessions.first
        let longCompletion = IslandDebugScenario.longCompletionCard.snapshot().sessions.first

        #expect(!(completion?.trackingTranscriptPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
        #expect(!(longCompletion?.trackingTranscriptPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
    }
}
