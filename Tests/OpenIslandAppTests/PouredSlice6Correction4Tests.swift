import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Poured parity Slice 6 · correction round 4 — the four items both independent
/// reviewers converged on (PI-X-001 H1 / I1-I2 / G1).
///
/// One pin per corrected behaviour. The header lane's overflow rule is real
/// arithmetic (`PouredHeaderMeterLane`); the rest are source pins, in keeping
/// with the other Poured suites — no assertion mounts a view.
struct PouredSlice6Correction4Tests {

    private static func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static let rowSource = "Sources/OpenIslandApp/Views/Island/PouredSessionRow.swift"
    private static let usageSource = "Sources/OpenIslandApp/Views/Island/PouredUsageSummary.swift"
    private static let headerSource = "Sources/OpenIslandApp/Views/Island/PouredHeaderControls.swift"

    /// An English-pinned lookup instance — `LanguageManager.language` persists to
    /// the shared `appLanguage` default on every set and other suites cycle
    /// zh-Hans/zh-Hant in parallel, so a bare instance can resolve a Chinese
    /// bundle mid-run. Restoring the persisted key leaves the default as found.
    private static func englishLanguage() -> LanguageManager {
        let key = "appLanguage"
        let saved = UserDefaults.standard.string(forKey: key)
        let lang = LanguageManager()
        lang.language = .en
        if let saved {
            UserDefaults.standard.set(saved, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        return lang
    }

    // MARK: - C4-2 · the header meter lane's overflow rule (I1-I2)

    /// The three-window header fixture, at the widths the 620pt notch capture
    /// measured: `CLAUDE 5H` (fine), `CLAUDE 7D` (warn), `CODEX 7D · PRO`
    /// (critical, and the widest of the three).
    private static let fixture = [
        PouredHeaderMeterLane.Candidate(id: "claude#5h", width: 100, usedPercentage: 34),
        PouredHeaderMeterLane.Candidate(id: "claude#7d", width: 100, usedPercentage: 78),
        PouredHeaderMeterLane.Candidate(id: "codex#7d", width: 130, usedPercentage: 92),
    ]

    @Test
    func laneRendersEveryMeterWhenTheyAllFit() {
        // 100 + 12 + 100 + 12 + 130 = 354.
        #expect(PouredHeaderMeterLane.fitted(Self.fixture, availableWidth: 354) == ["claude#5h", "claude#7d", "codex#7d"])
        #expect(PouredHeaderMeterLane.fitted(Self.fixture, availableWidth: 900) == ["claude#5h", "claude#7d", "codex#7d"])
    }

    /// Severity-first: the calmest band is the first thing elided, and the
    /// survivors keep **board order**, never the ranking's order.
    @Test
    func laneDropsTheLowestBandFirstAndKeepsBoardOrder() {
        // One point short of the full row: the 34% `fine` meter goes.
        #expect(PouredHeaderMeterLane.fitted(Self.fixture, availableWidth: 353) == ["claude#7d", "codex#7d"])
        // 100 + 12 + 130 = 242; one point short of that drops the 78% `warn`.
        #expect(PouredHeaderMeterLane.fitted(Self.fixture, availableWidth: 241) == ["codex#7d"])
    }

    /// The worst band is the last meter standing — and it stands even when it
    /// does not fit, because the lane's `.clipped()` bound makes a truncated
    /// critical number strictly better than an empty header.
    @Test
    func laneNeverElidesItsWayToEmptyWhileItHasWidth() {
        #expect(PouredHeaderMeterLane.fitted(Self.fixture, availableWidth: 40) == ["codex#7d"])
        #expect(PouredHeaderMeterLane.fitted(Self.fixture, availableWidth: 1) == ["codex#7d"])
        // A lane with no width at all renders nothing (and no meter is measured
        // against a phantom proposal — the R3/C8 mistake).
        #expect(PouredHeaderMeterLane.fitted(Self.fixture, availableWidth: 0).isEmpty)
        #expect(PouredHeaderMeterLane.fitted([], availableWidth: 400).isEmpty)
    }

    /// Ties inside one band fall to the higher percentage, then to board order —
    /// so the rule is a total order and two runs can't disagree.
    @Test
    func laneTieBreaksOnPercentageThenBoardOrder() {
        let sameBand = [
            PouredHeaderMeterLane.Candidate(id: "a", width: 100, usedPercentage: 10),
            PouredHeaderMeterLane.Candidate(id: "b", width: 100, usedPercentage: 30),
            PouredHeaderMeterLane.Candidate(id: "c", width: 100, usedPercentage: 30),
        ]
        // Room for two: the 10% goes first.
        #expect(PouredHeaderMeterLane.fitted(sameBand, availableWidth: 212) == ["b", "c"])
        // Room for one: `b` and `c` tie on percentage, board order breaks it.
        #expect(PouredHeaderMeterLane.fitted(sameBand, availableWidth: 100) == ["b"])
    }

    /// The band cut-offs are the app-wide usage rule's, not a second opinion.
    @Test
    func laneSeverityRanksFollowTheSharedThresholdBands() {
        #expect(PouredHeaderMeterLane.severityRank(0) == 0)
        #expect(PouredHeaderMeterLane.severityRank(69.9) == 0)
        #expect(PouredHeaderMeterLane.severityRank(70) == 1)
        #expect(PouredHeaderMeterLane.severityRank(89.9) == 1)
        #expect(PouredHeaderMeterLane.severityRank(90) == 2)
        #expect(PouredHeaderMeterLane.severityRank(100) == 2)
    }

    /// The spacing the rule pays for is the spacing the lane actually draws.
    @Test
    func laneFitsAccountsForTheRenderedGaps() {
        let two = Array(Self.fixture.prefix(2))
        #expect(PouredHeaderMeterLane.fits(two, availableWidth: 212))
        #expect(!PouredHeaderMeterLane.fits(two, availableWidth: 211))
        #expect(PouredHeaderMeterLane.meterSpacing == 12)
        #expect(PouredHeaderMeterLane.ringLabelSpacing == 8)
    }

    /// A wider window title measures wider — the fitter is reading real font
    /// metrics for the strings the lane renders, not a fixed per-meter guess.
    @Test
    func meterWidthTracksItsWidestLabelLine() {
        let lang = Self.englishLanguage()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let window = UsageWindowPresentation(
            id: "5h",
            label: "5h",
            usedPercentage: 34,
            resetsAt: now.addingTimeInterval(2 * 3600 + 10 * 60)
        )

        let short = PouredUsageWindowRing.measuredWidth(
            providerTitle: "Claude",
            window: window,
            ringDiameter: 30,
            now: now,
            lang: lang
        )
        let long = PouredUsageWindowRing.measuredWidth(
            providerTitle: "Codex Enterprise Plus",
            window: window,
            ringDiameter: 30,
            now: now,
            lang: lang
        )

        #expect(short > 30 + PouredHeaderMeterLane.ringLabelSpacing)
        #expect(long > short)
        // The ring is part of the footprint the lane pays for.
        let wider = PouredUsageWindowRing.measuredWidth(
            providerTitle: "Claude",
            window: window,
            ringDiameter: 40,
            now: now,
            lang: lang
        )
        #expect(wider == short + 10)
    }

    /// The lane is bounded on **both** header profiles, and the bound is a hard
    /// clip — the fitter's estimate is the first line of defence, never the only
    /// one.
    @Test
    func headerLanesAreBoundedAndClipped() throws {
        let header = try Self.source(Self.headerSource)
        #expect(header.contains("laneWidth: metrics.leftUsageWidth"))
        #expect(header.contains("laneWidth: metrics.rightUsageWidth"))
        #expect(header.contains(".clipped()"))
        // The top-bar profile computes its lane from the band it is given.
        #expect(header.contains("- openedHeaderButtonsWidth"))
        #expect(header.contains("- Self.topBarLaneGap"))
        // R15 is untouched: distribution is still `laneGroups`' call.
        #expect(header.contains("IslandHeaderLaneLayout.laneGroups("))
    }

    /// Elision is visual only — a meter the lane cannot draw keeps its VoiceOver
    /// stop. The mirror is hidden by **clipping a real layout**, never by
    /// `.hidden()`, `.opacity(0)` or a 0×0 proposal: all three were measured to
    /// drop the meter out of `overlay.ax.json` entirely.
    @Test
    func elidedMetersStayInTheAccessibilityTree() throws {
        let usage = try Self.source(Self.usageSource)
        #expect(usage.contains("elidedMeterAccessibilityMirror"))
        #expect(usage.contains(".fixedSize()"))
        #expect(usage.contains(".frame(width: 0, height: 0, alignment: .leading)"))
        #expect(usage.contains(".allowsHitTesting(false)"))
        #expect(!usage.contains(".opacity(0)"))
    }

    // MARK: - C4-1 · §H result prose (H1)

    /// The §H `Result` slab renders the board's one `.assistant` rule, the same
    /// one §D's slab already passed — 12.5/400 at `paper@.66`, strong lifted to
    /// `.96`/640, inline `code` on the `white@.06` chip. It used to fall back to
    /// `.completionCard`.
    @Test
    func completionResultUsesTheBoardsAssistantProse() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("LocalMarkdownText(completionMessageText, style: .pouredAssistant, colors: assistantInkColors)"))
        #expect(!row.contains("LocalMarkdownText(completionMessageText, colors: tokens.colors)"))
        // §D's slab is unchanged and still the other half of the pair.
        #expect(row.contains("LocalMarkdownText(message, style: .pouredAssistant, colors: assistantInkColors)"))
    }

    // MARK: - C4-3 · §H rail weights (H1)

    /// `.btn.ghost` is a **filled** chip at `--t1`; only an explicit opt-in
    /// drops a ghost's label to `--t3`. Native had the two inverted.
    @Test
    func ghostButtonsAreBrightUnlessDimmed() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("var isDimmed: Bool = false"))
        #expect(row.contains("let alpha = isDimmed ? tokens.colors.tertiaryTextOpacity : 0.96"))
        #expect(row.contains("PouredFullSizeButtonStyle(kind: .ghost, isDimmed: true)"))
    }

    /// §H's Transcript is the same ghost chip as Reply, with no document glyph —
    /// and §D's rail keeps `TranscriptAffordance(pouredGhost: true)` with its
    /// glyph, unchanged (Slice 5 · D4).
    @Test
    func completionRailTranscriptIsABareGhostChip() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("private func completionTranscriptButton(path: String) -> some View"))
        #expect(row.contains("completionTranscriptButton(path: transcriptPath)"))
        // The affordance survives only at §D's rail and the footnote.
        #expect(row.components(separatedBy: "TranscriptAffordance(").count - 1 == 2)
        #expect(row.components(separatedBy: "pouredGhost: true").count - 1 == 1)
        // The context menu / tooltip / workspace-qualified label are reused.
        #expect(row.contains("lang.t(\"a11y.transcript\", session.spotlightWorkspaceName)"))
        #expect(row.contains("revealTranscriptFileInFinder(at: path)"))
    }

    // MARK: - C4-4 · expanded disambiguator (G1)

    /// Expanded, the title line's disambiguator is the branch **alone** — the
    /// fan-out is already stated by the `.act` line and the nest header. The
    /// collapsed composition (owner escalation E2) is untouched.
    @Test
    func expandedDisambiguatorDropsTheFanOutSegment() throws {
        let row = try Self.source(Self.rowSource)
        #expect(row.contains("guard !showsDetail, let subagentCount = collapsedSubagentCount else { return base }"))
        // The collapsed join itself is unchanged.
        #expect(row.contains("return base + \" \\u{00B7} \" + fanOut"))
    }
}
