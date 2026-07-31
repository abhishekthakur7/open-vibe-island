import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-342 (T23 · Halo 3/N): the Halo closed pill — the wings shell, the A1–A6
/// ambient-state pairings, the `wave` liveness glyph, and the mono-object narrated
/// label. These are the **pure** contracts the pill draws from, pinned view-free:
///
/// - the state → left-wing indicator (glyph / dot / outcome mark) table
///   (`HaloSessionRowFormat.pillIndicator`, extending the AB-340 "never color
///   alone" resolver rather than duplicating it),
/// - the ambient → edge-state bridge the pill/label share,
/// - the two-tone label split (`HaloPillLabelTone`), including the A3 mono command,
/// - the wave stagger constants (`HaloMotion.wave` / `waveBarDelays`), and
/// - the closed-pill width-regression matrix — the shipped `V6ClosedPill.*OuterWidth`
///   math the pill delegates to **verbatim** must stay byte-identical (the
///   closed↔opened morph frame depends on it), mirroring
///   `FlightDeckClosedPillWidthRegressionTests`.
@MainActor
struct HaloClosedPillTests {

    // MARK: - State → left-wing indicator (SPEC §4 / §5A · "never color alone")

    /// Every edge state resolves to a distinct-in-shape left-wing indicator: a
    /// liveness glyph for the live states (still/wave/breathe), a ringed dot for a
    /// held permission, and an outcome mark for each completion. So the pill never
    /// carries state by hue alone (and stays legible under Reduce Motion, where the
    /// light freezes).
    @Test
    func pillIndicatorPairsEveryStateWithANonColorShape() {
        #expect(HaloSessionRowFormat.pillIndicator(for: .idle) == .liveness(.idle))
        #expect(HaloSessionRowFormat.pillIndicator(for: .running) == .liveness(.running))
        #expect(HaloSessionRowFormat.pillIndicator(for: .question) == .liveness(.waiting))
        #expect(HaloSessionRowFormat.pillIndicator(for: .permission) == .permissionDot)
        #expect(HaloSessionRowFormat.pillIndicator(for: .success) == .outcome(.success))
        #expect(HaloSessionRowFormat.pillIndicator(for: .interrupted) == .outcome(.interrupted))
        #expect(HaloSessionRowFormat.pillIndicator(for: .failed) == .outcome(.failed))
    }

    /// The three completions carry **distinct** outcome symbols — a completion is
    /// never confused with a clean finish. The symbols come from the shared
    /// `statusGlyphName` channel (no duplicate table), so a check / stop / cross.
    @Test
    func outcomeMarksAreDistinctAndSharedWithTheRowGlyphChannel() {
        let success = HaloSessionRowFormat.statusGlyphName(.success)
        let interrupted = HaloSessionRowFormat.statusGlyphName(.interrupted)
        let failed = HaloSessionRowFormat.statusGlyphName(.failed)
        #expect(success == "checkmark")
        #expect(interrupted == "stop.fill")
        #expect(failed == "xmark")
        #expect(Set([success, interrupted, failed]).count == 3)
    }

    /// The pill indicator resolves the same distinct shape for all seven states —
    /// no two states share an indicator (permission's dot ≠ any liveness/outcome).
    @Test
    func pillIndicatorIsUniquePerState() {
        let indicators = HaloSessionRowFormat.EdgeState.allCases
            .map { HaloSessionRowFormat.pillIndicator(for: $0) }
        #expect(Set(indicators.map { "\($0)" }).count == indicators.count)
    }

    // MARK: - Ambient → edge-state bridge (pill + label share one resolution)

    /// The shared closed-pill ambient frame folds onto the Halo edge state the
    /// indicator/label read: idle→idle, working (either arity)→running,
    /// permission→permission, question→question, and a completion forks by outcome.
    @Test
    func ambientBridgesToTheExpectedEdgeState() {
        #expect(HaloSessionRowFormat.edgeState(for: .idle) == .idle)
        #expect(HaloSessionRowFormat.edgeState(for: .working(manyWorking: false)) == .running)
        #expect(HaloSessionRowFormat.edgeState(for: .working(manyWorking: true)) == .running)
        #expect(HaloSessionRowFormat.edgeState(for: .permission) == .permission)
        #expect(HaloSessionRowFormat.edgeState(for: .question) == .question)
        #expect(HaloSessionRowFormat.edgeState(for: .completed(.success)) == .success)
        #expect(HaloSessionRowFormat.edgeState(for: .completed(.interrupted)) == .interrupted)
        #expect(HaloSessionRowFormat.edgeState(for: .completed(.failed)) == .failed)
    }

    // MARK: - Wave glyph stagger (SPEC §1c · mockup `wave 1.05s` .13/.26s)

    /// The running wave rides the 1.05s `wave` period with the mockup's per-bar
    /// stagger (.13 / .26s), so the light travels left→right. Pinned so neither
    /// the period nor the stagger silently drifts.
    @Test
    func waveTimingMatchesTheSpec() {
        #expect(HaloMotion.wave == 1.05)
        #expect(HaloMotion.waveBarDelays == [0, 0.13, 0.26])
        // Three bars, one delay each — the glyph geometry consumes them verbatim.
        #expect(HaloLivenessGlyph.bars.count == 3)
        #expect(HaloLivenessGlyph.bars.map(\.delay) == HaloMotion.waveBarDelays)
    }

    /// The waiting/breathe glyph keeps all three bars (mockup §K `breathe`:
    /// "all three bars", M-09) — the state reads by opacity pulse, not by a
    /// dropped bar.
    @Test
    func waitingGlyphKeepsAllThreeBars() {
        #expect(HaloLivenessGlyph.bars[0].waitH > 0)
        #expect(HaloLivenessGlyph.bars[1].waitH > 0)
        #expect(HaloLivenessGlyph.bars[2].waitH > 0)
    }

    /// `UnifiedBars.Mode` maps onto the glyph mode 1:1 (the pill indicator carries
    /// a `Mode`; the glyph draws a `Kind`).
    @Test
    func livenessKindMapsFromMode() {
        #expect(HaloLivenessGlyph.Kind(mode: .idle) == .idle)
        #expect(HaloLivenessGlyph.Kind(mode: .running) == .running)
        #expect(HaloLivenessGlyph.Kind(mode: .waiting) == .waiting)
    }

    // MARK: - Two-tone label (SPEC §5A · mono-object split)

    /// A2 working narration → verb sans/dim + object **mono**/primary (the mockup's
    /// `<span class="dim">Editing</span> <span class="mn">AppModel.swift</span>`).
    @Test
    func workingLabelSplitsVerbDimObjectMono() {
        let segments = HaloPillLabelTone.segments(for: "Editing AppModel.swift", ambient: .working(manyWorking: false))
        #expect(segments == [
            .init(text: "Editing", role: .dim),
            .init(text: " AppModel.swift", role: .mono),
        ])
    }

    /// A2′ aggregate → the count reads primary/strong, the qualifier dim
    /// (`3 working`).
    @Test
    func aggregateWorkingLabelReadsCountStrongQualifierDim() {
        let segments = HaloPillLabelTone.segments(for: "3 working", ambient: .working(manyWorking: true))
        #expect(segments == [
            .init(text: "3", role: .count),
            .init(text: " working", role: .dim),
        ])
    }

    /// A3 permission → the command is lifted into a **mono** run, the rest primary
    /// (`Approve ` + `swift build` + `?`), so the scanned code role reads as code.
    @Test
    func permissionLabelLiftsTheCommandIntoMono() {
        let segments = HaloPillLabelTone.segments(
            for: "Approve swift build?",
            ambient: .permission,
            commandAffixes: (prefix: "Approve ", suffix: "?")
        )
        #expect(segments == [
            .init(text: "Approve ", role: .primary),
            .init(text: "swift build", role: .mono),
            .init(text: "?", role: .primary),
        ])
    }

    /// When the permission label is the `Approval needed` fallback (no command),
    /// the affixes don't match and the whole label renders as one primary run —
    /// never a broken mono slice.
    @Test
    func permissionFallbackRendersOnePlainRun() {
        let segments = HaloPillLabelTone.segments(
            for: "Approval needed",
            ambient: .permission,
            commandAffixes: (prefix: "Approve ", suffix: "?")
        )
        #expect(segments == [.init(text: "Approval needed", role: .primary)])
    }

    /// A4 question → the lead word dim, the rest primary (`Answer needed`).
    @Test
    func questionLabelDimsTheLeadWord() {
        let segments = HaloPillLabelTone.segments(for: "Answer needed", ambient: .question)
        #expect(segments == [
            .init(text: "Answer", role: .dim),
            .init(text: " needed", role: .primary),
        ])
    }

    /// A5/A6 completion → the `Done ·` / `Interrupted ·` / `Failed ·` prefix reads
    /// dim, the workspace primary (sans — a workspace name is data, not code, so it
    /// is **not** mono).
    @Test
    func completionLabelDimsThePrefixWorkspacePrimary() {
        for label in ["Done · the-automator", "Interrupted · niche-radar", "Failed · open-vibe-island"] {
            let segments = HaloPillLabelTone.segments(for: label, ambient: .completed(.success))
            #expect(segments.count == 2)
            #expect(segments.first?.role == .dim)
            #expect(segments.last?.role == .primary)
            // No mono run — the workspace is never rendered as code.
            #expect(!segments.contains { $0.role == .mono })
        }
    }

    /// An empty / whitespace label yields no segments (the pill shows no label).
    @Test
    func blankLabelYieldsNoSegments() {
        #expect(HaloPillLabelTone.segments(for: "   ", ambient: .idle).isEmpty)
        #expect(HaloPillLabelTone.segments(for: "", ambient: .working(manyWorking: false)).isEmpty)
    }

    // MARK: - Right-slot task roll-up (SPEC §G′)

    /// A running subagent fan-out rolls up to the **nodes** form carrying the
    /// subagent count (the G′ `3` + nodes glyph) — never the nested list, never a
    /// frozen fraction.
    @Test
    func taskCounterWithSubagentsRollsUpToNodesCount() {
        #expect(HaloRightSlotForm.task(completed: 2, total: 5, subagents: 3) == .nodes(3))
        // The subagent count wins even when there is also a todo list in flight.
        #expect(HaloRightSlotForm.task(completed: 0, total: 0, subagents: 1) == .nodes(1))
    }

    /// With no fan-out the counter falls back to the todo **fraction** (`2/5`), so
    /// a plain todo run reads as progress rather than an empty nodes glyph.
    @Test
    func taskCounterWithoutSubagentsFallsBackToFraction() {
        #expect(HaloRightSlotForm.task(completed: 2, total: 5, subagents: 0) == .fraction(completed: 2, total: 5))
        #expect(HaloRightSlotForm.task(completed: 0, total: 0, subagents: 0) == .fraction(completed: 0, total: 0))
    }

    // MARK: - Traveling-glyph tint (overlay remediation F3)

    /// `HaloTheme.closedGlyphTint` resolves through the exact same ambient →
    /// edge-state → indicator pipeline as the pill's own left-wing indicator
    /// (`pillIndicatorPairsEveryStateWithANonColorShape` above), landing on the
    /// shared colour table in `HaloSessionRowFormat.livenessTint`/`outcomeTint`
    /// plus the permission dot's `statusWaitingForApproval` — pinned directly so
    /// "nil tint / paper-toned bars for every state" (the achromatic-glyph
    /// regression this remediation fixes) cannot silently return.
    @Test
    func closedGlyphTintMatchesTheSharedStateColourTable() {
        let theme = HaloTheme()
        let tokens = theme.tokens

        #expect(
            theme.closedGlyphTint(mode: .idle, rightSlot: nil, activity: nil)
                == tokens.colors.paper.opacity(tokens.colors.tertiaryTextOpacity)
        )
        #expect(theme.closedGlyphTint(mode: .running, rightSlot: nil, activity: nil) == tokens.colors.statusRunning)
        #expect(
            theme.closedGlyphTint(mode: .waiting, rightSlot: nil, activity: nil)
                == tokens.colors.statusWaitingForAnswer
        )

        // A3 permission — the state this remediation fixes: the traveling
        // glyph must land on the same amber as the pill's own ringed dot, not
        // fall through the `.waiting` bars branch above.
        let permission = IslandClosedPillActivity(phase: .waitingForApproval, outcome: .success, isOutcomeFresh: false)
        #expect(
            theme.closedGlyphTint(mode: .waiting, rightSlot: nil, activity: permission)
                == tokens.colors.statusWaitingForApproval
        )

        let freshSuccess = IslandClosedPillActivity(phase: .completed, outcome: .success, isOutcomeFresh: true)
        #expect(theme.closedGlyphTint(mode: .idle, rightSlot: nil, activity: freshSuccess) == tokens.colors.statusCompleted)

        let freshFailure = IslandClosedPillActivity(phase: .completed, outcome: .failed, isOutcomeFresh: true)
        #expect(theme.closedGlyphTint(mode: .idle, rightSlot: nil, activity: freshFailure) == tokens.colors.statusFailed)
    }
}

// MARK: - Closed-pill width regression (the AB-338 / T12 contract)

/// AB-342 renders the six ambient states with new pill-local content (liveness
/// glyph, ringed dot, outcome marks, two-tone label) and a Part-1 count-badge
/// right slot, but the shipped `V6ClosedPill.*OuterWidth` math must stay
/// **byte-identical** — the closed↔opened morph frame (and every theme's pill
/// silhouette) depends on it, and the Halo wing content must render *inside* the
/// slot the fluid layout already reserved, never widen it. Mirrors
/// `FlightDeckClosedPillWidthRegressionTests` (the T12/AB-330 precedent) so a
/// drift in the width math fails the build regardless of what the Halo pill draws.
@MainActor
struct HaloClosedPillWidthRegressionTests {
    private static let height: CGFloat = 38
    private static let tolerance: CGFloat = 0.001

    private func external(_ label: String?, _ rightSlot: IslandRightSlotContent?) -> CGFloat {
        V6ClosedPill.externalOuterWidth(label: label, rightSlot: rightSlot, minWidth: 70, height: Self.height)
    }

    private func macbook(_ label: String?, notch: CGFloat) -> CGFloat {
        V6ClosedPill.macbookOuterWidth(label: label, physicalNotchWidth: notch, height: Self.height)
    }

    /// The A1–A6 fixture matrix reserves exactly the shipped widths — the bare idle
    /// pill, a narrated A2 label, the count-shaped right slots (`.count` /
    /// `.attentionCount` / `.usage`), and an outcome label — all unchanged.
    @Test
    func externalOuterWidthGoldensAreUnchanged() {
        #expect(abs(external(nil, nil) - 70) < Self.tolerance)
        #expect(abs(external("Editing AppModel.swift", nil) - 238.6) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 1, kind: .permission)) - 82.4) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 12, kind: .question)) - 89.6) < Self.tolerance)
        #expect(abs(external(nil, .usage(percent: 92, windowLabel: "7d", providerTitle: "Codex")) - 89.6) < Self.tolerance)
        #expect(abs(external("Done · the-automator", nil) - 224) < Self.tolerance)
    }

    /// A permission and a question right slot with the same count reserve the same
    /// width — the Part-2 capsule variants will differ only in glyph / hue, not
    /// geometry, so the frame is stable now and after the restyle.
    @Test
    func rightSlotKindDoesNotChangeReservedWidth() {
        #expect(
            external("x", .attentionCount(count: 3, kind: .permission))
                == external("x", .attentionCount(count: 3, kind: .question))
        )
    }

    /// The MacBook (notch-lane) layout reserves symmetric width around the physical
    /// notch, and a label never shrinks the reserve below the bare-pill baseline.
    @Test
    func macbookOuterWidthIsStableAndSymmetric() {
        #expect(macbook("Editing AppModel.swift", notch: 180) >= macbook(nil, notch: 180))
        #expect(abs(macbook(nil, notch: 200) - macbook(nil, notch: 200)) < Self.tolerance)
    }
}
