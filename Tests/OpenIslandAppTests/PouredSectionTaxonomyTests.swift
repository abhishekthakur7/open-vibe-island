import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// PI-C-001 / PI-C-002 / PI-C-007: pure pins for `PouredSectionTaxonomy` — the
/// projection from the shared five state sections onto the Poured board's three
/// groups (`01-poured-island.html` §C: `Needs you` 809, `Working` 844, `Done`
/// 878) plus the idle roll-up the footer carries (913).
///
/// These lock the merge, the extraction, the fixed group order, the fixed
/// swatch hues, and the within-group recency ordering so the list can't drift
/// back into a flat, unbounded table without a failing test.
///
/// `@MainActor` because `islandActivityDate` hangs off the main-actor
/// `AgentSession+Presentation` extension.
@MainActor
struct PouredSectionTaxonomyTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        id: String,
        phase: SessionPhase,
        outcome: SessionOutcome = .success,
        minutesAgo: Double = 0
    ) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · \(id)",
            tool: .codex,
            origin: .live,
            attachmentState: .attached,
            phase: phase,
            outcome: outcome,
            summary: phase.displayName,
            updatedAt: now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    private func section(_ id: String, _ sessions: [AgentSession]) -> IslandSessionSection {
        IslandSessionSection(id: id, title: "island.section.\(id)", sessions: sessions)
    }

    private func ids(_ section: IslandSessionSection) -> [String] {
        section.sessions.map(\.id)
    }

    // MARK: - Merge (PI-C-001)

    /// The board files the permission row *and* the question row under one
    /// `Needs you` header. Approval rows are concatenated ahead of question rows
    /// before the recency sort, so with equal timestamps the stable sort leaves
    /// permissions on top — the loudest thing first.
    @Test
    func needsYouMergesApprovalAndAnswerWithApprovalRowsFirst() {
        let projection = PouredSectionTaxonomy.project([
            section("state-approval", [session(id: "p1", phase: .waitingForApproval),
                                       session(id: "p2", phase: .waitingForApproval)]),
            section("state-answer", [session(id: "q1", phase: .waitingForAnswer)]),
        ])

        #expect(projection.sections.count == 1)
        #expect(projection.sections[0].id == "state-poured-needsYou")
        #expect(projection.sections[0].title == "island.poured.section.needsYou")
        #expect(ids(projection.sections[0]) == ["p1", "p2", "q1"])
    }

    /// A single attention section still projects onto the merged identity — the
    /// header word must be `Needs you`, never the shared `Needs answer` copy.
    @Test
    func needsYouProjectsEvenWhenOnlyOneAttentionSectionExists() {
        let projection = PouredSectionTaxonomy.project([
            section("state-answer", [session(id: "q1", phase: .waitingForAnswer)]),
        ])

        #expect(projection.sections.map(\.id) == ["state-poured-needsYou"])
    }

    /// `Done` is the board's **terminal** bucket: success and interrupted rows sit
    /// side by side under one header (887 / 904), never split into two groups.
    @Test
    func doneKeepsSuccessAndInterruptedRowsTogether() {
        let projection = PouredSectionTaxonomy.project([
            section("state-done", [
                session(id: "ok", phase: .completed, outcome: .success, minutesAgo: 12),
                session(id: "int", phase: .completed, outcome: .interrupted, minutesAgo: 22),
            ]),
        ])

        #expect(projection.sections.count == 1)
        #expect(projection.sections[0].id == "state-done")
        #expect(ids(projection.sections[0]) == ["ok", "int"])
    }

    // MARK: - Idle extraction (PI-C-002 / PI-C-007)

    /// The board never renders an idle group; idle exists only as the footer
    /// roll-up. The projection lifts `state-idle` out of the rendered sections
    /// and hands back its rows for that readout.
    @Test
    func idleSectionIsExtractedFromTheRenderedListAndCounted() {
        let projection = PouredSectionTaxonomy.project([
            section("state-running", [session(id: "r", phase: .running)]),
            section("state-idle", [
                session(id: "i1", phase: .completed, minutesAgo: 90),
                session(id: "i2", phase: .completed, minutesAgo: 120),
                session(id: "i3", phase: .completed, minutesAgo: 150),
            ]),
        ])

        #expect(projection.sections.map(\.id) == ["state-running"])
        #expect(projection.idleCount == 3)
        #expect(projection.idleSessions.map(\.id).sorted() == ["i1", "i2", "i3"])
    }

    /// A list that is *entirely* idle renders no rows at all — the whole table
    /// collapses into the footer roll-up rather than becoming an unbounded
    /// scroll of things nobody is waiting on.
    @Test
    func anAllIdleListRendersNoSections() {
        let projection = PouredSectionTaxonomy.project([
            section("state-idle", (1...12).map { session(id: "i\($0)", phase: .completed, minutesAgo: Double($0) * 10) }),
        ])

        #expect(projection.sections.isEmpty)
        #expect(projection.idleCount == 12)
    }

    // MARK: - Fixed group order + empty-group omission

    /// `Needs you → Working → Done` is fixed by the taxonomy, not by the order
    /// the shared sectioning happened to emit — attention is always first.
    @Test
    func groupOrderIsFixedRegardlessOfInputSectionOrder() {
        let input = [
            section("state-done", [session(id: "d", phase: .completed)]),
            section("state-idle", [session(id: "i", phase: .completed, minutesAgo: 99)]),
            section("state-running", [session(id: "r", phase: .running)]),
            section("state-answer", [session(id: "q", phase: .waitingForAnswer)]),
            section("state-approval", [session(id: "p", phase: .waitingForApproval)]),
        ]

        let projection = PouredSectionTaxonomy.project(input)

        #expect(projection.sections.map(\.id) == [
            "state-poured-needsYou",
            "state-running",
            "state-done",
        ])
        #expect(projection.sections.map(\.title) == [
            "island.poured.section.needsYou",
            "island.poured.section.working",
            "island.poured.section.done",
        ])
    }

    /// The board never draws a zero-count header — an empty group is omitted
    /// entirely rather than rendered with a `0`.
    @Test
    func emptyGroupsAreOmittedEntirely() {
        let projection = PouredSectionTaxonomy.project([
            section("state-running", [session(id: "r", phase: .running)]),
        ])

        #expect(projection.sections.map(\.id) == ["state-running"])
        #expect(PouredSectionTaxonomy.project([]).sections.isEmpty)
        #expect(PouredSectionTaxonomy.project([]).idleCount == 0)
    }

    // MARK: - Within-group ordering

    /// Within every group rows read most-recent-first (board §C: `1m/3m`,
    /// `now/8m`, `12m/22m`).
    @Test
    func withinGroupOrderIsMostRecentFirst() {
        let projection = PouredSectionTaxonomy.project([
            section("state-running", [
                session(id: "old", phase: .running, minutesAgo: 8),
                session(id: "new", phase: .running, minutesAgo: 0),
            ]),
        ])

        #expect(ids(projection.sections[0]) == ["new", "old"])
    }

    /// Equal timestamps keep the order they arrived in — the recency sort is
    /// stable, so the deterministic attention order upstream produced survives.
    @Test
    func recencyTiesAreStableInIncomingOrder() {
        let tied = (1...5).map { session(id: "t\($0)", phase: .running, minutesAgo: 4) }
        #expect(PouredSectionTaxonomy.recencyDescending(tied).map(\.id) == ["t1", "t2", "t3", "t4", "t5"])

        // A newer row jumps the whole tied block; the block's internal order holds.
        var mixed = tied
        mixed.insert(session(id: "fresh", phase: .running, minutesAgo: 0), at: 3)
        #expect(
            PouredSectionTaxonomy.recencyDescending(mixed).map(\.id)
                == ["fresh", "t1", "t2", "t3", "t4", "t5"]
        )
    }

    // MARK: - Scaffold gating: `.none` ≡ `.state`, agent/project untouched

    /// PI-C-001's core claim: whichever sort the profile carries, the *projected*
    /// list is the same, because the taxonomy re-orders every group by recency
    /// (see `PouredSectionTaxonomy`'s recorded preference override). The two
    /// sides here take genuinely different paths into the projection —
    ///
    /// - the `.none` re-section path the scaffold runs (`group: .state`,
    ///   `sort: .attention`), which preserves the incoming attention order inside
    ///   each section, and
    /// - a `.state` grouping reached with the profile's other sort
    ///   (`sort: .lastUpdate`), which pre-sorts every section by recency
    ///
    /// — and the sessions are deliberately handed over in a non-recency order so
    /// the two disagree *before* the projection. They converge after it.
    ///
    /// The user override for `.agent` / `.project` is a different shape entirely
    /// and never reaches the taxonomy — it passes through the scaffold verbatim.
    @Test
    func attentionAndLastUpdateSortsConvergeAfterProjectionWhileAgentAndProjectPassThrough() {
        // Arrival order is *not* recency order: the older runner arrives first.
        let sessions = [
            session(id: "p", phase: .waitingForApproval, minutesAgo: 1),
            session(id: "q", phase: .waitingForAnswer, minutesAgo: 3),
            session(id: "r-old", phase: .running, minutesAgo: 8),
            session(id: "r-new", phase: .running, minutesAgo: 0),
            session(id: "d", phase: .completed, minutesAgo: 2),
        ]

        func sections(sort: IslandSessionSort) -> [IslandSessionSection] {
            IslandSessionSectioning.sections(
                for: sessions,
                group: .state,
                sort: sort,
                completedStaleThreshold: 3600,
                now: now
            )
        }

        // Guard against this test decaying back into a tautology: the two inputs
        // must genuinely differ before the taxonomy runs.
        let attentionInput = sections(sort: .attention)
        let lastUpdateInput = sections(sort: .lastUpdate)
        #expect(attentionInput.map(ids) != lastUpdateInput.map(ids))
        #expect(attentionInput.first { $0.id == "state-running" }.map(ids) == ["r-old", "r-new"])
        #expect(lastUpdateInput.first { $0.id == "state-running" }.map(ids) == ["r-new", "r-old"])

        let fromNone = PouredSectionTaxonomy.project(attentionInput)
        let fromLastUpdate = PouredSectionTaxonomy.project(lastUpdateInput)

        #expect(fromNone.sections.map(\.id) == fromLastUpdate.sections.map(\.id))
        #expect(fromNone.sections.map(ids) == fromLastUpdate.sections.map(ids))
        #expect(fromNone.sections.map(\.id) == [
            "state-poured-needsYou",
            "state-running",
            "state-done",
        ])
        // Recency-descending inside every group, from either side.
        #expect(fromNone.sections.map(ids) == [["p", "q"], ["r-new", "r-old"], ["d"]])

        // Agent / project identities are not taxonomy identities — the scaffold's
        // lookups return nil for them, so titles and tints stay as they are.
        for id in ["agent-codex", "project-open-island", "all"] {
            #expect(PouredSectionTaxonomy.group(forSectionID: id) == nil)
            #expect(PouredSectionTaxonomy.localizationKey(forSectionID: id) == nil)
        }
    }

    // MARK: - Footer count is the projection's count (PI-C-002)

    /// The footer roll-up must count exactly the rows the projection removed.
    ///
    /// The scaffold's local `idleSessionCount` is a **wider** bucket — completed
    /// *and* (stale **or** inactive) — than the state sectioning's `state-idle`,
    /// which is stale only. A completed session that is 25 minutes old under a
    /// `never` stale window satisfies the wide predicate (it is inactive: past
    /// the 20-minute activity horizon) but is not stale, so the projection keeps
    /// it in `Done`. Reading the wide count while the taxonomy is active would
    /// print `1 idle` in the footer under a list that renders that very row —
    /// which is why the footer reads `taxonomyProjection?.idleCount` first.
    @Test
    func footerCountMatchesTheRowsTheProjectionRemovedWhenTheTwoDefinitionsDisagree() throws {
        let inactiveButNotStale = session(id: "done-inactive", phase: .completed, minutesAgo: 25)
        let sessions = [
            session(id: "r", phase: .running, minutesAgo: 0),
            inactiveButNotStale,
        ]

        // The wide bucket the scaffold uses for agent / project groupings.
        let wideIdleCount = sessions.filter {
            $0.phase == .completed
                && ($0.isStaleCompletedForIsland(at: now, threshold: IslandCompletedStaleThreshold.never.seconds)
                    || $0.islandPresence(at: now) == .inactive)
        }.count
        #expect(wideIdleCount == 1)

        let projected = PouredSectionTaxonomy.project(
            IslandSessionSectioning.sections(
                for: sessions,
                group: .state,
                sort: .attention,
                completedStaleThreshold: IslandCompletedStaleThreshold.never.seconds,
                now: now
            )
        )

        // The row renders under `Done` …
        let done = try #require(projected.sections.first { $0.id == PouredSectionTaxonomy.Group.done.sectionID })
        #expect(ids(done) == ["done-inactive"])
        // … so the footer count the scaffold prints is the projection's `0`,
        // not the wide bucket's `1`.
        #expect(projected.idleCount == 0)
        #expect(projected.idleCount != wideIdleCount)
    }

    // MARK: - Fixed swatch hues

    /// Each group wears its fixed board hue (`--attn #ffb14d`, `--run #6ea7ff`,
    /// `--done #6fb982`), all three already existing tokens — no new hex is
    /// minted, and the tint no longer depends on whichever row sorts first.
    @Test
    func groupTintsAreFixedToTheBoardTokens() {
        let colors = IslandThemeTokens.poured.colors

        #expect(PouredSectionTaxonomy.tint(for: .needsYou, tokens: colors) == PouredPalette.attention)
        #expect(PouredSectionTaxonomy.tint(for: .working, tokens: colors) == colors.statusRunning)
        #expect(PouredSectionTaxonomy.tint(for: .done, tokens: colors) == colors.statusCompleted)

        // The board's literal hues, pinned so a token drift fails here too.
        #expect(PouredSectionTaxonomy.tint(for: .needsYou, tokens: colors)
                == Color(red: 0xFF / 255.0, green: 0xB1 / 255.0, blue: 0x4D / 255.0))
        #expect(PouredSectionTaxonomy.tint(for: .working, tokens: colors)
                == Color(red: 0x6E / 255.0, green: 0xA7 / 255.0, blue: 0xFF / 255.0))
        #expect(PouredSectionTaxonomy.tint(for: .done, tokens: colors)
                == Color(red: 0x6F / 255.0, green: 0xB9 / 255.0, blue: 0x82 / 255.0))
    }

    /// A `Done` group led by an interrupted row keeps the green `--done` swatch —
    /// the regression the fixed tint exists to prevent (the old first-row
    /// derivation would have painted it interrupted amber).
    @Test
    func doneKeepsItsGreenSwatchEvenWhenLedByAnInterruptedRow() throws {
        let colors = IslandThemeTokens.poured.colors
        let projection = PouredSectionTaxonomy.project([
            section("state-done", [session(id: "int", phase: .completed, outcome: .interrupted)]),
        ])

        let group = try #require(PouredSectionTaxonomy.group(forSectionID: projection.sections[0].id))
        #expect(group == .done)
        #expect(PouredSectionTaxonomy.tint(for: group, tokens: colors) == colors.statusCompleted)
        #expect(colors.statusCompleted != colors.statusInterrupted)
    }

    // MARK: - Header words localize

    /// The three new `island.poured.section.*` keys resolve to real translations
    /// in English and both Chinese scripts.
    @Test
    func sectionHeaderWordsLocalizeInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            for group in PouredSectionTaxonomy.Group.allCases {
                let resolved = manager.t(group.localizationKey)
                #expect(resolved != group.localizationKey, "\(group.localizationKey) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }

        let en = LanguageManager()
        en.language = .en
        #expect(en.t(PouredSectionTaxonomy.Group.needsYou.localizationKey) == "Needs you")
        #expect(en.t(PouredSectionTaxonomy.Group.working.localizationKey) == "Working")
        #expect(en.t(PouredSectionTaxonomy.Group.done.localizationKey) == "Done")
    }
}
