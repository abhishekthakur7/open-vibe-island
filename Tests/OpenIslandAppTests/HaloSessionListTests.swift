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
