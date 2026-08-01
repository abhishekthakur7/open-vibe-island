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
/// - **PI-C-002 / PI-C-007** — a long tail can never grow into a table below the
///   rows that need the reader (the `C4-stress-40` shape, exercised here as a
///   unit rather than a capture). Under **owner ruling R1** that bound is the
///   **6-row display cap** rather than idle extraction: Done stays visible, and
///   `PouredSectionTaxonomy.cappedSections` is what keeps the list finite.
/// - **PI-C-003** — a row's headline is a name a human can act on, never a bare
///   filesystem separator. The root-workspace case below asserts the fixed
///   behavior (the guard chain in `spotlightWorkspaceName`); residual secondary
///   surfaces are recorded in the ledger.
///
/// Everything here is a pure projection over hand-built sessions and a fixed
/// `now`; nothing reads the wall clock, the defaults store, or the view layer.
struct PouredProjectionStressTests {
    private static let now = Date(timeIntervalSince1970: 1_770_000_000)
    /// Owner ruling R1 (`docs/design/overlay-redesign/poured-owner-rulings.md`):
    /// *"done stays visible"* — the Poured list re-sections with `never`
    /// whatever the profile's `completedStaleThreshold` is, so this is the
    /// window the rendered projection actually runs under
    /// (`PouredSessionListScaffold.taxonomyStaleThreshold`).
    private static let listStaleThreshold = IslandCompletedStaleThreshold.never.seconds
    /// The shipping profile default, kept only to prove R1 makes the projection
    /// independent of it.
    private static let profileDefaultStaleThreshold = IslandCompletedStaleThreshold.fiveMinutes.seconds

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
        staleThreshold: TimeInterval = listStaleThreshold
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
    /// The board's Done rows are 12 and 22 minutes old *and* its footer reads
    /// `0 idle` in the same frame. Owner ruling R1 rules the board correct —
    /// Done does not stale out — so the Poured list runs at `never` and this is
    /// simply what §C shows.
    @Test
    func c1GroupedSixProjectsToTheBoardsThreeGroupsWithNoIdleGroup() {
        let sessions = AppearancePreviewFixtures.pouredGroupedSix(now: Self.now)
        #expect(sessions.count == 6)

        let projected = Self.projection(sessions)

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

    /// **Owner ruling R1** (replaces the recorded reference/default divergence):
    /// *"done stays visible"*. An old completed row projects to `Done`, not to
    /// the idle roll-up, and the result no longer depends on which
    /// `completedStaleThreshold` the profile carries — because the Poured list
    /// re-sections at `never` regardless
    /// (`PouredSessionListScaffold.taxonomyStaleThreshold`).
    ///
    /// The 22-minute `fixture-poured-c1-interrupted` row is the exact case the
    /// old test pinned as a divergence; under the shipping 5-minute default the
    /// shared sectioning still calls it stale, which is the input this asserts
    /// against, so the test cannot decay into a tautology.
    @Test
    func oldCompletedRowsProjectToDoneWhateverTheProfileThresholdIs_R1() throws {
        let sessions = AppearancePreviewFixtures.pouredGroupedSix(now: Self.now)

        // The shared sectioning genuinely disagrees with itself across the two
        // windows — the divergence R1 resolves is real, not asserted away.
        func sectioned(_ threshold: TimeInterval) -> [IslandSessionSection] {
            IslandSessionSectioning.sections(
                for: sessions, group: .state, sort: .attention,
                completedStaleThreshold: threshold, now: Self.now
            )
        }
        #expect(sectioned(Self.profileDefaultStaleThreshold).contains { $0.id == "state-idle" })
        #expect(!sectioned(Self.listStaleThreshold).contains { $0.id == "state-idle" })

        // What the Poured list renders is the `never` projection either way.
        let rendered = Self.projection(sessions)
        let done = try #require(rendered.sections.first { $0.id == PouredSectionTaxonomy.Group.done.sectionID })
        #expect(done.sessions.map(\.id)
            == ["fixture-completed-success", "fixture-poured-c1-interrupted"])
        #expect(rendered.idleCount == 0)
        #expect(rendered.idleSessions.isEmpty)

        // The window the scaffold actually runs at reproduces the rendered
        // projection, and the profile default does *not* — which is the whole
        // content of R1. (Comparing the `never` projection to itself would have
        // been a tautology; these two inputs genuinely differ.)
        let atScaffoldWindow = PouredSectionTaxonomy.project(
            sectioned(PouredSessionListScaffold.taxonomyStaleThreshold)
        )
        #expect(Self.shape(atScaffoldWindow).map(\.0) == Self.shape(rendered).map(\.0))
        #expect(Self.shape(atScaffoldWindow).map(\.1) == Self.shape(rendered).map(\.1))

        let atProfileDefault = PouredSectionTaxonomy.project(sectioned(Self.profileDefaultStaleThreshold))
        #expect(Self.shape(atProfileDefault).map(\.1) != Self.shape(rendered).map(\.1))
        #expect(atProfileDefault.idleCount > 0)
    }

    /// The scaffold's window *is* `never` — pinned so a future edit to
    /// `taxonomyStaleThreshold` cannot silently reintroduce staling under R1.
    @Test
    func theScaffoldsTaxonomyWindowIsNever_R1() {
        #expect(PouredSessionListScaffold.taxonomyStaleThreshold == IslandCompletedStaleThreshold.never.seconds)
        #expect(Self.listStaleThreshold == PouredSessionListScaffold.taxonomyStaleThreshold)
    }

    /// R1's cross-surface consequence: the summary strip must read the same
    /// window the list re-sections at, or one frame says `Done` in the table and
    /// `idle` in the strip. The C1 fixture's Done rows are 12m / 22m old — stale
    /// under the profile default — and the board prints `6 total / 2 waiting /
    /// 2 running / 2 done` with no idle bucket at all.
    @Test
    func c1SummaryStripReadsTwoDoneAndNoIdleUnderTheEffectiveThreshold_R1() {
        let sessions = AppearancePreviewFixtures.pouredGroupedSix(now: Self.now)

        let effective = PouredSessionListScaffold.overviewBuckets(
            sessions: sessions,
            referenceDate: Self.now,
            threshold: PouredSessionListScaffold.taxonomyStaleThreshold
        )
        #expect(effective == PouredSessionListScaffold.OverviewBuckets(
            total: 6, waiting: 2, running: 2, done: 2, idle: 0
        ))

        // The profile window is what the strip used to read, and it disagrees —
        // so the assertion above is a real fix, not a restatement.
        let atProfileDefault = PouredSessionListScaffold.overviewBuckets(
            sessions: sessions,
            referenceDate: Self.now,
            threshold: Self.profileDefaultStaleThreshold
        )
        #expect(atProfileDefault.idle > 0)
        #expect(atProfileDefault.done < effective.done)
    }

    /// R3's idle disclosure is **unreachable** under R1: at the scaffold's window
    /// the extracted bucket is empty even for rows hours past any profile
    /// threshold, so the footer toggle can never appear. Pinned so a future
    /// threshold ruling has to come through this test.
    @Test
    func idleDisclosureIsUnreachableUnderR1() {
        let ancient = (0..<5).map {
            Self.session(
                id: "ancient-\($0)",
                phase: .completed,
                workspace: "workspace-\($0)",
                secondsAgo: TimeInterval(6 * 60 * 60 + $0 * 60)
            )
        }

        let rendered = Self.projection(ancient, staleThreshold: PouredSessionListScaffold.taxonomyStaleThreshold)
        #expect(rendered.idleCount == 0)
        #expect(rendered.idleSessions.isEmpty)
        #expect(rendered.sections.map(\.id) == [PouredSectionTaxonomy.Group.done.sectionID])

        // Same rows at the profile window do fall into the idle bucket.
        #expect(Self.projection(ancient, staleThreshold: Self.profileDefaultStaleThreshold).idleCount == 5)
    }

    /// The cap may never hide the row the surface was opened for. Ten sessions,
    /// actionable = the last `Done` row (well past the six-row cut) → still
    /// rendered while collapsed.
    @Test
    func theActionableSessionIsAlwaysAmongRenderedRows() throws {
        var sessions = [Self.session(id: "pin-running", phase: .running, workspace: "runner", secondsAgo: 5)]
        for index in 0..<9 {
            sessions.append(
                Self.session(
                    id: "pin-done-\(index)",
                    phase: .completed,
                    workspace: "done-\(index)",
                    secondsAgo: TimeInterval(60 * 60 + index * 60)
                )
            )
        }

        let projected = Self.projection(sessions)
        let actionable = try #require(projected.sections.last?.sessions.last?.id)
        #expect(actionable == "pin-done-8")

        let capped = PouredSectionTaxonomy.cappedSections(projected.sections)
        #expect(capped.isCapped)
        #expect(!capped.visible.contains { $0.sessions.contains { $0.id == actionable } })

        let pinned = PouredSessionListScaffold.pinningActionableSession(
            capped.visible,
            projected: projected.sections,
            actionableSessionID: actionable
        )
        #expect(pinned.contains { $0.sessions.contains { $0.id == actionable } })
        // Its group header is still there, and the frame grew by exactly one row.
        #expect(pinned.map(\.id) == capped.visible.map(\.id))
        #expect(pinned.flatMap(\.sessions).count == capped.visible.flatMap(\.sessions).count + 1)
        // No pinning happens when the actionable row is already on screen.
        #expect(
            PouredSessionListScaffold.pinningActionableSession(
                capped.visible, projected: projected.sections, actionableSessionID: "pin-running"
            ).flatMap(\.sessions).map(\.id) == capped.visible.flatMap(\.sessions).map(\.id)
        )
    }

    /// The other pinning shape: the actionable row's whole group was cut away, so
    /// the group comes back — header and all — holding just that row, in
    /// projection order.
    @Test
    func pinningReinstatesAGroupThatTheCutRemovedEntirely() throws {
        var sessions: [AgentSession] = []
        for index in 0..<7 {
            sessions.append(
                Self.session(
                    id: "pin-attn-\(index)",
                    phase: .waitingForApproval,
                    workspace: "attn-\(index)",
                    secondsAgo: TimeInterval(10 + index)
                )
            )
        }
        sessions.append(Self.session(id: "pin-tail-done", phase: .completed, workspace: "tail", secondsAgo: 3 * 60 * 60))

        let projected = Self.projection(sessions)
        let capped = PouredSectionTaxonomy.cappedSections(projected.sections)
        #expect(capped.visible.map(\.id) == [PouredSectionTaxonomy.Group.needsYou.sectionID])

        let pinned = PouredSessionListScaffold.pinningActionableSession(
            capped.visible,
            projected: projected.sections,
            actionableSessionID: "pin-tail-done"
        )
        #expect(pinned.map(\.id) == [
            PouredSectionTaxonomy.Group.needsYou.sectionID,
            PouredSectionTaxonomy.Group.done.sectionID,
        ])
        #expect(pinned.last?.sessions.map(\.id) == ["pin-tail-done"])
        #expect(pinned.last?.title == PouredSectionTaxonomy.Group.done.localizationKey)
    }

    /// Same input twice → identical output. The projection sorts by recency with
    /// an explicit index tiebreak precisely because Swift's `sort` is not stable,
    /// so an unstable implementation would surface here as a shuffled group.
    @Test
    func c1GroupedSixProjectionIsStableAcrossRepeatedRuns() {
        let sessions = AppearancePreviewFixtures.pouredGroupedSix(now: Self.now)

        let first = Self.shape(Self.projection(sessions))
        for _ in 0..<8 {
            let repeated = Self.shape(Self.projection(sessions))
            #expect(repeated.map(\.0) == first.map(\.0))
            #expect(repeated.map(\.1) == first.map(\.1))
        }

        // And the fixture builder itself is `now`-deterministic.
        #expect(AppearancePreviewFixtures.pouredGroupedSix(now: Self.now) == sessions)
    }

    // MARK: - C4: the 40-session stress shape

    /// One live runner behind thirty-nine old completed sessions.
    ///
    /// **Rewritten under owner ruling R1.** This test used to assert the tail
    /// was extracted as `39 idle` and one row rendered. R1 rules the opposite
    /// half of that: Done never stales, so all thirty-nine stay in `Done` and
    /// the idle bucket is empty. The bound PI-C-002 / PI-C-007 promise — that a
    /// long tail can never grow into an unbounded table — is now kept by the
    /// **6-row display cap** instead: `Working 1 + Done 5` on screen, thirty-four
    /// behind "Show all 40 sessions".
    @Test
    func fortySessionsWithOneRunnerKeepDoneVisibleAndRenderOnlySixRows() throws {
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

        // R1: two groups, nothing extracted.
        #expect(projected.sections.map(\.id) == [
            PouredSectionTaxonomy.Group.working.sectionID,
            PouredSectionTaxonomy.Group.done.sectionID,
        ])
        #expect(projected.sections.map(\.sessions.count) == [1, 39])
        #expect(projected.idleCount == 0)
        #expect(projected.idleSessions.isEmpty)

        // R1's cap: six rows on screen, thirty-four behind "Show all".
        let capped = PouredSectionTaxonomy.cappedSections(projected.sections)
        #expect(capped.total == 40)
        #expect(capped.hiddenCount == 34)
        #expect(capped.isCapped)
        #expect(capped.visible.flatMap(\.sessions).count == 6)
        #expect(capped.visible.map(\.id) == [
            PouredSectionTaxonomy.Group.working.sectionID,
            PouredSectionTaxonomy.Group.done.sectionID,
        ])
        #expect(capped.visible[0].sessions.map(\.id) == ["stress-running"])
        #expect(capped.visible[1].sessions.count == 5)
        // The header still prints the group's real size, not the five it drew.
        #expect(capped.groupTotals[PouredSectionTaxonomy.Group.done.sectionID] == 39)
        #expect(capped.groupTotals[PouredSectionTaxonomy.Group.working.sectionID] == 1)

        // Expanding is the way back to every row — no session is unreachable.
        #expect(projected.sections.flatMap(\.sessions).count == 40)

        // Every row in the set headlines with something, on screen or behind the cap.
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
    /// the user; all twelve must reach `Needs you`, whatever the tail does.
    ///
    /// Under owner ruling R1 the twenty-eight completed rows stay in `Done`
    /// rather than becoming `28 idle`, and the display cap decides what is on
    /// screen: the six visible rows are **all** attention rows, and the other
    /// six attention rows are reachable by expanding — never dropped.
    @Test
    func everyAttentionSessionSurvivesTheProjectionAtStressScale() throws {
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
        let needsYou = try #require(projected.sections.first { $0.id == PouredSectionTaxonomy.Group.needsYou.sectionID })

        #expect(needsYou.sessions.count == 12)
        let surfaced = Set(needsYou.sessions.map(\.id))
        let attentionIDs = Set(sessions.filter { $0.phase == .waitingForApproval || $0.phase == .waitingForAnswer }.map(\.id))
        #expect(surfaced == attentionIDs)
        // R1: the completed tail stays in `Done`; nothing is extracted at all.
        #expect(projected.idleCount == 0)
        #expect(projected.sections.map(\.id) == [
            PouredSectionTaxonomy.Group.needsYou.sectionID,
            PouredSectionTaxonomy.Group.done.sectionID,
        ])
        #expect(projected.sections.map(\.sessions.count) == [12, 28])

        // The cap can only ever cut into the *tail*: attention is group-first,
        // so all six visible rows are attention rows.
        let capped = PouredSectionTaxonomy.cappedSections(projected.sections)
        #expect(capped.total == 40)
        #expect(capped.hiddenCount == 34)
        #expect(capped.visible.map(\.id) == [PouredSectionTaxonomy.Group.needsYou.sectionID])
        #expect(capped.visible[0].sessions.count == 6)
        #expect(capped.visible[0].sessions.allSatisfy { attentionIDs.contains($0.id) })
        // `Done` is cut away entirely while collapsed, yet `Needs you` still
        // prints twelve — the reader is told six more are waiting on them.
        #expect(capped.groupTotals[PouredSectionTaxonomy.Group.needsYou.sectionID] == 12)
        #expect(capped.groupTotals[PouredSectionTaxonomy.Group.done.sectionID] == 28)

        // Expanding reaches the other six attention rows.
        let expandedAttention = Set(projected.sections.flatMap(\.sessions).map(\.id)).intersection(attentionIDs)
        #expect(expandedAttention == attentionIDs)
        #expect(Set(capped.visible.flatMap(\.sessions).map(\.id)).count == 6)
    }
}
