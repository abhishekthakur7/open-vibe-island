import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// PI-V-001 deterministic evidence for the Poured §C list projection
/// (`PouredSectionTaxonomy`), covering the three ledger claims the board makes
/// about the opened list:
///
/// - **PI-C-001** — the two attention sections merge into one `Needs you`, and
///   the two terminal outcomes stay together under `Done`.
/// - **PI-C-002 / PI-C-007** — idle never renders as a group, so an arbitrarily
///   long idle tail cannot grow into a table below the rows that need the reader
///   (the `C4-stress-40` shape, exercised here as a unit rather than a capture).
/// - **PI-C-003** — a row's headline is a name a human can act on, never a bare
///   filesystem separator. The root-workspace case below asserts the fixed
///   behavior (the guard chain in `spotlightWorkspaceName`); residual secondary
///   surfaces are recorded in the ledger.
///
/// Everything here is a pure projection over hand-built sessions and a fixed
/// `now`; nothing reads the wall clock, the defaults store, or the view layer.
struct PouredProjectionStressTests {
    private static let now = Date(timeIntervalSince1970: 1_770_000_000)
    private static let defaultStaleThreshold = IslandCompletedStaleThreshold.fiveMinutes.seconds

    // MARK: - Builders

    private static func session(
        id: String,
        phase: SessionPhase,
        outcome: SessionOutcome = .success,
        workspace: String,
        tool: AgentTool = .claudeCode,
        secondsAgo: TimeInterval
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "\(tool.displayName) · \(workspace)",
            tool: tool,
            origin: .demo,
            attachmentState: .attached,
            phase: phase,
            outcome: outcome,
            summary: "\(id) summary",
            updatedAt: now.addingTimeInterval(-secondsAgo),
            jumpTarget: JumpTarget(
                terminalApp: "Ghostty",
                workspaceName: workspace,
                paneTitle: "\(tool.rawValue) ~/\(workspace)",
                terminalSessionID: id
            )
        )
    }

    /// The projection the opened Poured list actually renders: shared state
    /// sectioning first (that is what `PouredSessionListScaffold` feeds it),
    /// then the Poured taxonomy on top.
    private static func projection(
        _ sessions: [AgentSession],
        staleThreshold: TimeInterval = defaultStaleThreshold
    ) -> PouredSectionTaxonomy.Projection {
        PouredSectionTaxonomy.project(
            IslandSessionSectioning.sections(
                for: sessions,
                group: .state,
                sort: .attention,
                completedStaleThreshold: staleThreshold,
                now: now
            )
        )
    }

    private static func shape(_ projection: PouredSectionTaxonomy.Projection) -> [(String, [String])] {
        projection.sections.map { ($0.id, $0.sessions.map(\.id)) }
    }

    // MARK: - C1: the board's six

    /// The `C1-grouped-six` fixture projects to exactly the board's three groups
    /// with exactly two rows each, and no idle group at all.
    ///
    /// The threshold is `.never` on purpose: the board's Done rows are 12 and 22
    /// minutes old *and* its footer reads `0 idle` in the same frame, which is
    /// only self-consistent above a 22-minute stale window. Under the shipping
    /// 5-minute default those two rows are stale-completed — asserted separately
    /// below, so the divergence is recorded rather than hidden.
    @Test
    func c1GroupedSixProjectsToTheBoardsThreeGroupsWithNoIdleGroup() {
        let sessions = AppearancePreviewFixtures.pouredGroupedSix(now: Self.now)
        #expect(sessions.count == 6)

        let projected = Self.projection(sessions, staleThreshold: IslandCompletedStaleThreshold.never.seconds)

        #expect(projected.sections.map(\.id) == [
            PouredSectionTaxonomy.Group.needsYou.sectionID,
            PouredSectionTaxonomy.Group.working.sectionID,
            PouredSectionTaxonomy.Group.done.sectionID,
        ])
        #expect(projected.sections.map(\.title) == [
            "island.poured.section.needsYou",
            "island.poured.section.working",
            "island.poured.section.done",
        ])
        #expect(projected.sections.map(\.sessions.count) == [2, 2, 2])
        #expect(projected.idleCount == 0)
        #expect(projected.idleSessions.isEmpty)

        // Needs you: the permission ahead of the question (1m vs 3m — recency
        // already agrees with the approval-first concatenation here).
        #expect(projected.sections[0].sessions.map(\.phase) == [.waitingForApproval, .waitingForAnswer])
        #expect(projected.sections[0].sessions.map(\.id)
            == ["fixture-poured-c1-permission", "fixture-poured-c1-question"])

        // Working: both running, newest first.
        #expect(projected.sections[1].sessions.allSatisfy { $0.phase == .running })
        #expect(projected.sections[1].sessions.map(\.id)
            == ["fixture-poured-c1-running", "fixture-trio-claude-main"])

        // Done: success and interrupted together under one terminal group.
        #expect(projected.sections[2].sessions.allSatisfy { $0.phase == .completed })
        #expect(projected.sections[2].sessions.map(\.outcome) == [.success, .interrupted])
        #expect(projected.sections[2].sessions.map(\.id)
            == ["fixture-completed-success", "fixture-poured-c1-interrupted"])
    }

    /// The reference/default divergence the fixture's doc comment records: under
    /// the shipping 5-minute stale window the board's own Done rows age out of
    /// `Done` and into the footer roll-up. Pinned so a later slice that changes
    /// the threshold semantics has to come back through this test.
    @Test
    func c1GroupedSixDoneRowsFallToTheIdleRollUpUnderTheShippingStaleWindow() {
        let projected = Self.projection(AppearancePreviewFixtures.pouredGroupedSix(now: Self.now))

        #expect(projected.sections.map(\.id) == [
            PouredSectionTaxonomy.Group.needsYou.sectionID,
            PouredSectionTaxonomy.Group.working.sectionID,
        ])
        #expect(projected.idleCount == 2)
        #expect(projected.idleSessions.map(\.id).sorted()
            == ["fixture-completed-success", "fixture-poured-c1-interrupted"])
    }

    /// Same input twice → identical output. The projection sorts by recency with
    /// an explicit index tiebreak precisely because Swift's `sort` is not stable,
    /// so an unstable implementation would surface here as a shuffled group.
    @Test
    func c1GroupedSixProjectionIsStableAcrossRepeatedRuns() {
        let sessions = AppearancePreviewFixtures.pouredGroupedSix(now: Self.now)
        let threshold = IslandCompletedStaleThreshold.never.seconds

        let first = Self.shape(Self.projection(sessions, staleThreshold: threshold))
        for _ in 0..<8 {
            let repeated = Self.shape(Self.projection(sessions, staleThreshold: threshold))
            #expect(repeated.map(\.0) == first.map(\.0))
            #expect(repeated.map(\.1) == first.map(\.1))
        }

        // And the fixture builder itself is `now`-deterministic.
        #expect(AppearancePreviewFixtures.pouredGroupedSix(now: Self.now) == sessions)
    }

    // MARK: - C4: the 40-session stress shape

    /// One live runner behind thirty-nine stale sessions renders **one** row.
    /// This is the whole point of PI-C-002/PI-C-007: the idle tail is a count in
    /// the footer, not thirty-nine rows of table.
    @Test
    func fortySessionsWithOneRunnerRenderExactlyOneRowAndCountThirtyNineIdle() {
        var sessions = [Self.session(id: "stress-running", phase: .running, workspace: "open-vibe-island", secondsAgo: 5)]
        for index in 0..<39 {
            sessions.append(
                Self.session(
                    id: "stress-idle-\(index)",
                    phase: .completed,
                    outcome: .success,
                    // One row's workspace is the filesystem root — the PI-C-003
                    // shape. It must still never render as a bare separator.
                    workspace: index == 7 ? "/" : "workspace-\(index)",
                    secondsAgo: TimeInterval(30 * 60 + index * 60)
                )
            )
        }
        #expect(sessions.count == 40)

        let projected = Self.projection(sessions)

        #expect(projected.sections.count == 1)
        #expect(projected.sections[0].id == PouredSectionTaxonomy.Group.working.sectionID)
        #expect(projected.sections.flatMap(\.sessions).map(\.id) == ["stress-running"])
        #expect(projected.idleCount == 39)

        // Every row in the set headlines with something, rendered or rolled up.
        for session in sessions {
            #expect(!session.spotlightDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// PI-C-003, **fixed**: a session whose workspace is the filesystem root
    /// never headlines as a bare `/`.
    ///
    /// This test originally pinned the defect (`spotlightDisplayName == "/"`) as
    /// an executable fact while the fix lived on its own branch. That branch
    /// landed — `spotlightWorkspaceName` now rejects path-punctuation-only
    /// candidates at every fallback stage — so the expectation is inverted, as
    /// the original pin demanded. The root case falls through to the raw-title
    /// fallback (`"Claude Code · /"`): not a bare separator, though it still
    /// carries the slash in its tail — recorded in the ledger as a residual,
    /// alongside the secondary surfaces that can still store `/`.
    @Test
    func rootWorkspaceNeverHeadlinesAsABareSeparator_PI_C_003() {
        let root = Self.session(id: "stress-root-workspace", phase: .running, workspace: "/", secondsAgo: 5)
        #expect(root.spotlightDisplayName != "/")
        #expect(root.spotlightDisplayName == "\(AgentTool.claudeCode.displayName) · /")

        // The honest fallback the accessor already owns for an *empty* workspace
        // — the agent's display name — is what a repaired `/` case should reach.
        let blank = Self.session(id: "stress-blank-workspace", phase: .running, workspace: "  ", secondsAgo: 5)
        #expect(blank.spotlightDisplayName != "/")
        #expect(!blank.spotlightDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    /// Attention is never curated away. Twelve of forty sessions are blocked on
    /// the user; all twelve must reach `Needs you`, whatever the idle tail does.
    @Test
    func everyAttentionSessionSurvivesTheProjectionAtStressScale() {
        var sessions: [AgentSession] = []
        for index in 0..<6 {
            sessions.append(
                Self.session(
                    id: "attn-approval-\(index)",
                    phase: .waitingForApproval,
                    workspace: "approval-\(index)",
                    secondsAgo: TimeInterval(10 + index)
                )
            )
        }
        for index in 0..<6 {
            sessions.append(
                Self.session(
                    id: "attn-answer-\(index)",
                    phase: .waitingForAnswer,
                    workspace: "answer-\(index)",
                    tool: .codex,
                    secondsAgo: TimeInterval(100 + index)
                )
            )
        }
        for index in 0..<28 {
            sessions.append(
                Self.session(
                    id: "tail-\(index)",
                    phase: .completed,
                    outcome: .success,
                    workspace: "tail-\(index)",
                    secondsAgo: TimeInterval(45 * 60 + index * 60)
                )
            )
        }
        #expect(sessions.count == 40)

        let projected = Self.projection(sessions)
        let needsYou = try? #require(projected.sections.first { $0.id == PouredSectionTaxonomy.Group.needsYou.sectionID })

        #expect(needsYou?.sessions.count == 12)
        let surfaced = Set(needsYou?.sessions.map(\.id) ?? [])
        let expected = Set(sessions.filter { $0.phase == .waitingForApproval || $0.phase == .waitingForAnswer }.map(\.id))
        #expect(surfaced == expected)
        #expect(projected.idleCount == 28)
        // The idle roll-up may never swallow a session that needs the user.
        #expect(projected.idleSessions.allSatisfy { $0.phase == .completed })
    }
}
