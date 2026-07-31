import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-343 (T24 · Halo Part 2): pure-format pins for `HaloSessionListModel` — the
/// counting / grouping rules behind `HaloSessionListScaffold` (§5 Slot 4 · mockup
/// §C). These lock the non-zero-bucket filter, the `total`-always ordering, the
/// "need you" tally, the grouping-caption keys, and the idle rule so the summary
/// strip / footer can't drift from the mockup without a failing test.
///
/// `@MainActor` because the idle helpers hang off the main-actor
/// `AgentSession+Presentation` extension.
@MainActor
struct HaloSessionListTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(
        id: String,
        phase: SessionPhase,
        outcome: SessionOutcome = .success,
        updatedAt: Date
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
            updatedAt: updatedAt
        )
    }

    // MARK: - Summary buckets (non-zero filter + total-always ordering)

    /// The mockup strip (`6 total · 2 waiting · 2 running · 2 done`): `total`
    /// always leads, then only the non-zero state buckets in
    /// `waiting → running → done → idle` order. With no idle sessions the idle
    /// bucket drops out entirely.
    @Test
    func summaryStripKeepsTotalThenOnlyNonZeroBuckets() {
        let sessions = [
            session(id: "a", phase: .waitingForApproval, updatedAt: now),
            session(id: "b", phase: .waitingForAnswer, updatedAt: now),
            session(id: "c", phase: .running, updatedAt: now),
            session(id: "d", phase: .running, updatedAt: now),
            session(id: "e", phase: .completed, updatedAt: now),
            session(id: "f", phase: .completed, updatedAt: now),
        ]

        let buckets = HaloSessionListModel.summaryBuckets(
            sessions: sessions,
            referenceDate: now,
            threshold: 3600
        )

        #expect(buckets == [
            .init(kind: .total, count: 6),
            .init(kind: .waiting, count: 2),
            .init(kind: .running, count: 2),
            .init(kind: .done, count: 2),
        ])
    }

    /// An empty list yields no strip at all (nothing to bound with a hairline).
    @Test
    func summaryStripIsEmptyForNoSessions() {
        #expect(HaloSessionListModel.summaryBuckets(sessions: [], referenceDate: now, threshold: 3600).isEmpty)
    }

    /// A stale completed session folds into the idle bucket (not done), and the
    /// idle bucket then surfaces at the tail of the strip.
    @Test
    func staleCompletedFoldsIntoIdleBucket() {
        let stale = session(id: "old", phase: .completed, updatedAt: now.addingTimeInterval(-86_400))
        let fresh = session(id: "new", phase: .completed, updatedAt: now)

        let buckets = HaloSessionListModel.summaryBuckets(
            sessions: [stale, fresh],
            referenceDate: now,
            threshold: 60
        )

        #expect(buckets == [
            .init(kind: .total, count: 2),
            .init(kind: .done, count: 1),
            .init(kind: .idle, count: 1),
        ])
    }

    // MARK: - Footer "need you" tally

    /// The footer's `M need you` counts exactly the attention sessions
    /// (approval + answer), never running or completed.
    @Test
    func needCountTalliesOnlyAttentionSessions() {
        let sessions = [
            session(id: "a", phase: .waitingForApproval, updatedAt: now),
            session(id: "b", phase: .waitingForAnswer, updatedAt: now),
            session(id: "c", phase: .running, updatedAt: now),
            session(id: "d", phase: .completed, updatedAt: now),
        ]
        #expect(HaloSessionListModel.needCount(sessions: sessions) == 2)
        #expect(HaloSessionListModel.needCount(sessions: []) == 0)
    }

    // MARK: - Grouping caption keys

    /// Every grouping mode maps to its Halo footer caption key; `.none` is silent.
    @Test
    func groupingCaptionKeysCoverEveryMode() {
        #expect(HaloSessionListModel.groupedByLocalizationKey(.none) == nil)
        #expect(HaloSessionListModel.groupedByLocalizationKey(.state) == "island.halo.footer.groupedByState")
        #expect(HaloSessionListModel.groupedByLocalizationKey(.agent) == "island.halo.footer.groupedByAgent")
        #expect(HaloSessionListModel.groupedByLocalizationKey(.project) == "island.halo.footer.groupedByProject")
    }

    // MARK: - Bucket label keys

    /// Each bucket word routes through the shared `sessionOverview` catalog so the
    /// Halo strip reuses the app-wide localizations.
    @Test
    func bucketLabelKeysMapToSharedOverviewCatalog() {
        #expect(HaloSessionListModel.BucketKind.total.labelKey == "island.sessionOverview.total")
        #expect(HaloSessionListModel.BucketKind.waiting.labelKey == "island.sessionOverview.waiting")
        #expect(HaloSessionListModel.BucketKind.running.labelKey == "island.sessionOverview.running")
        #expect(HaloSessionListModel.BucketKind.done.labelKey == "island.sessionOverview.done")
        #expect(HaloSessionListModel.BucketKind.idle.labelKey == "island.sessionOverview.idle")
    }

    // MARK: - §C section-header taxonomy (Q2 follow-up)

    /// Halo skins the shared `island.section.*` product copy with the board's own
    /// three words (`NEEDS YOU` / `RUNNING` / `DONE`); `state-idle` keeps `IDLE`
    /// (the board never names an idle group) and non-state groupings fall
    /// through to their shared title.
    @Test
    func sectionTaxonomyMapsStateSectionsToBoardWords() {
        #expect(HaloSectionTaxonomy.localizationKey(forSectionID: "state-approval") == "island.halo.section.needsYou")
        #expect(HaloSectionTaxonomy.localizationKey(forSectionID: "state-answer") == "island.halo.section.needsYou")
        #expect(HaloSectionTaxonomy.localizationKey(forSectionID: HaloSectionTaxonomy.needsYouSectionID) == "island.halo.section.needsYou")
        #expect(HaloSectionTaxonomy.localizationKey(forSectionID: "state-running") == "island.halo.section.running")
        #expect(HaloSectionTaxonomy.localizationKey(forSectionID: "state-done") == "island.halo.section.done")
        #expect(HaloSectionTaxonomy.localizationKey(forSectionID: "state-idle") == "island.halo.section.idle")
        #expect(HaloSectionTaxonomy.localizationKey(forSectionID: "agent-codex") == nil)
    }

    /// The board files a permission row and a question row under **one** `Needs
    /// you` header (`06-halo.html` §C), so the two adjacent attention sections
    /// merge — order preserved, approval rows first. Every other section passes
    /// through untouched, and a list with only one attention section is left
    /// exactly as the shared sectioning built it.
    @Test
    func attentionSectionsMergeIntoOneNeedsYouGroup() {
        let approval = session(id: "a", phase: .waitingForApproval, updatedAt: now)
        let answer = session(id: "b", phase: .waitingForAnswer, updatedAt: now)
        let running = session(id: "c", phase: .running, updatedAt: now)
        let sections = [
            IslandSessionSection(id: "state-approval", title: "island.section.needsApproval", sessions: [approval]),
            IslandSessionSection(id: "state-answer", title: "island.section.needsAnswer", sessions: [answer]),
            IslandSessionSection(id: "state-running", title: "island.section.inProgress", sessions: [running]),
        ]

        let merged = HaloSectionTaxonomy.merged(sections)
        #expect(merged.map(\.id) == [HaloSectionTaxonomy.needsYouSectionID, "state-running"])
        #expect(merged[0].sessions.map(\.id) == ["a", "b"])

        let single = Array(sections.dropFirst())
        #expect(HaloSectionTaxonomy.merged(single).map(\.id) == ["state-answer", "state-running"])
    }

    /// Every Halo header word resolves in all three app languages (never falls
    /// back to the raw key).
    @Test
    func sectionStringsResolveInEveryLanguage() {
        let lang = LanguageManager()
        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            lang.language = language
            for key in ["needsYou", "running", "done", "idle"].map({ "island.halo.section.\($0)" }) {
                #expect(lang.t(key) != key)
            }
        }
    }

    /// The footer summary + grouping strings resolve in all three app languages
    /// (the two-`%lld` readout must never fall back to the raw key).
    @Test
    func footerStringsResolveInEveryLanguage() {
        let lang = LanguageManager()
        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            lang.language = language
            let summary = lang.t("island.halo.footer.summary", 6, 2)
            #expect(summary != "island.halo.footer.summary")
            #expect(summary.contains("6"))
            #expect(summary.contains("2"))
            #expect(lang.t("island.halo.footer.groupedByProject") != "island.halo.footer.groupedByProject")
        }
    }
}
