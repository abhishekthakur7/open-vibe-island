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
/// **byte-identical** at its default arguments — the closed↔opened morph frame
/// (and every theme's pill silhouette) depends on it. Mirrors
/// `FlightDeckClosedPillWidthRegressionTests` (the T12/AB-330 precedent) so a
/// drift in the width math fails the build regardless of what the Halo pill draws.
///
/// R4 · item 1 amends exactly one clause of that contract: the §I′ usage pill's
/// content genuinely does NOT fit the slot the fluid layout reserved (a `×N`
/// badge's ~22pt for a ~145pt group), which is why it used to render under the
/// physical notch. `leadingAccessoryWidth` is the declared, opt-in growth that
/// fixes it — `0` for every other theme and every other Halo state, so every
/// golden below is unchanged.
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

    /// G-20/G-46/G-47: the notch lane is budgeted from the hardware, not from a
    /// fixed 84. It grows to whatever wing the machine's own notch leaves before
    /// the closed pill would outgrow the opened panel — and the pill at a
    /// full-width label lands EXACTLY on that panel width, never past it, so the
    /// morph only ever grows.
    @Test
    func notchLaneLabelWidthIsBudgetedFromTheHardware() {
        // This MacBook (measured live: 193.5pt cutout, Halo's 38pt pill).
        let lane = V6ClosedPill.notchLaneLabelWidth(physicalNotchWidth: 193.5, height: Self.height)
        #expect(abs(lane - 120.25) < Self.tolerance)
        #expect(lane > V6ClosedPill.notchLaneLabelMaxWidth)

        // A pill whose label fills the lane is exactly the opened panel's width.
        let filled = 2 * (Self.height / 2 + 24 + 4 + 6 + lane) + 193.5
        #expect(abs(filled - V6ClosedPill.macbookMaxOuterWidth) < Self.tolerance)

        // A narrower cutout frees more lane; an absurd one can never take the
        // lane below the original v6 floor.
        #expect(
            V6ClosedPill.notchLaneLabelWidth(physicalNotchWidth: 180, height: Self.height)
                > lane
        )
        #expect(
            V6ClosedPill.notchLaneLabelWidth(physicalNotchWidth: 460, height: Self.height)
                == V6ClosedPill.notchLaneLabelMaxWidth
        )
    }
}

// MARK: - §I′ wing split (R4 · item 1)

/// The board's §I′ pill (`06-halo.html:1301-1305`) splits the usage compression
/// across BOTH wings — filament arc + `Codex 94%` on the left, the reset
/// countdown alone on the right. Halo used to draw all three tokens as one
/// right-slot group; on a notched Mac that group right-aligned to the pill edge
/// and spilled backwards **under the physical cutout** (measured on this
/// hardware: bright content at x 776.5…847.5 against the 663.5…848.5 cutout —
/// 61pt of the pill's only critical signal, eaten by the notch).
///
/// These pin the pure halves of the fix: the wing plan, the lead's declared
/// width, the countdown's copy, and — the actual bug — that a §I′ pill's left
/// wing content now *ends before the cutout begins*, computed from the same
/// numbers the layout uses rather than eyeballed from a screenshot.
@MainActor
struct HaloClosedPillWingSplitTests {
    private static let height: CGFloat = 38
    private static let pad: CGFloat = 19          // height / 2
    private static let glyph: CGFloat = 24        // V6ClosedPill.glyphSize
    private static let gap: CGFloat = 6           // notchLaneLabelGap
    private static let trailingMargin: CGFloat = 4
    private static let tolerance: CGFloat = 0.001

    /// This machine's real cutout, from `NSScreen.auxiliaryTop*Area`: 663.5…848.5.
    private static let cutoutWidth: CGFloat = 848.5 - 663.5

    private static func criticalUsage(percent: Int = 92, provider: String = "Codex") -> IslandRightSlotContent {
        .usage(percent: percent, windowLabel: "7d", providerTitle: provider)
    }

    // MARK: The plan

    /// Halo moves the lead to the left wing and drops the now-duplicate lane
    /// label — the §I′ pill's left wing already says `Codex`, so the resolver's
    /// own `Codex` label beside it printed the vendor twice.
    @Test
    func haloPlansTheUsageSplitAndDropsTheDuplicateLabel() {
        let plan = HaloTheme().closedPillWingPlan(
            label: "Codex",
            rightSlot: Self.criticalUsage(),
            layout: .macbook,
            height: Self.height
        )
        #expect(plan.label == nil)
        #expect(plan.leadingAccessoryWidth > 0)
        #expect(
            abs(plan.leadingAccessoryWidth
                - HaloUsageFilamentLead.estimatedWidth(percent: 92, providerTitle: "Codex")) < Self.tolerance
        )
    }

    /// Every other Halo state keeps the composition it shipped with: no accessory,
    /// label untouched.
    @Test
    func haloLeavesEveryOtherRightSlotAlone() {
        let theme = HaloTheme()
        let slots: [IslandRightSlotContent?] = [
            nil,
            .count(3),
            .attentionCount(count: 2, kind: .permission),
            .attentionCount(count: 1, kind: .question),
            .taskCounter(completed: 2, total: 5, subagents: 0),
            .agents([]),
        ]
        for slot in slots {
            let plan = theme.closedPillWingPlan(
                label: "Editing AppModel.swift",
                rightSlot: slot,
                layout: .macbook,
                height: Self.height
            )
            #expect(plan.label == "Editing AppModel.swift")
            #expect(plan.leadingAccessoryWidth == 0)
        }
    }

    /// The seam is Halo-side: the other five themes take the protocol default, so
    /// their pills cannot move — including for a `.usage` slot, which they all
    /// still render as the shared badge.
    @Test
    func siblingThemesTakeTheIdentityPlan() {
        let siblings: [any IslandTheme] = [
            ClassicTheme(), PouredIslandTheme(), FlightDeckTheme(),
            AnnualTheme(), InstrumentTheme(),
        ]
        for theme in siblings {
            let plan = theme.closedPillWingPlan(
                label: "Codex",
                rightSlot: Self.criticalUsage(),
                layout: .macbook,
                height: Self.height
            )
            #expect(plan.label == "Codex", "\(theme.id) must keep its label")
            #expect(plan.leadingAccessoryWidth == 0, "\(theme.id) must reserve no accessory")
        }
    }

    // MARK: The width math

    /// `leadingAccessoryWidth` defaults to 0, so every existing caller — and
    /// therefore every other theme's pill and the morph frame it animates — gets
    /// the identical number it always did.
    @Test
    func accessoryWidthDefaultsToTheShippedGeometry() {
        for label in [nil, "Editing AppModel.swift", "Approve swift build?"] as [String?] {
            #expect(
                V6ClosedPill.macbookOuterWidth(label: label, physicalNotchWidth: 185, height: Self.height)
                    == V6ClosedPill.macbookOuterWidth(
                        label: label,
                        physicalNotchWidth: 185,
                        height: Self.height,
                        leadingAccessoryWidth: 0
                    )
            )
            #expect(
                V6ClosedPill.externalOuterWidth(
                    label: label, rightSlot: .count(3), minWidth: 70, height: Self.height
                ) == V6ClosedPill.externalOuterWidth(
                    label: label, rightSlot: .count(3), minWidth: 70, height: Self.height,
                    leadingAccessoryWidth: 0
                )
            )
        }
    }

    /// **The bug, as a number.** On this machine's 185pt cutout, a §I′ pill's
    /// left-wing content (pad + glyph + gap + lead) must end *before* the cutout
    /// starts — with exactly the shared layout's own `notchLaneLabelTrailingMargin`
    /// of clearance, since the accessory is what sets the reserve.
    @Test
    func usageLeadEndsBeforeThePhysicalCutout() {
        let lead = HaloUsageFilamentLead.estimatedWidth(percent: 92, providerTitle: "Codex")
        let outer = V6ClosedPill.macbookOuterWidth(
            label: nil,
            physicalNotchWidth: Self.cutoutWidth,
            height: Self.height,
            leadingAccessoryWidth: lead
        )

        // The pill is centred on the cutout, so each wing is half the surplus.
        let wing = (outer - Self.cutoutWidth) / 2
        let contentEnd = Self.pad + Self.glyph + Self.gap + lead

        #expect(contentEnd < wing, "the §I′ lead must not reach the cutout")
        #expect(abs(wing - contentEnd - Self.trailingMargin) < Self.tolerance)

        // And it only ever grows the pill — never past the panel it morphs into.
        #expect(outer > V6ClosedPill.macbookOuterWidth(
            label: nil, physicalNotchWidth: Self.cutoutWidth, height: Self.height
        ))
        #expect(outer <= V6ClosedPill.macbookMaxOuterWidth)
    }

    /// The fluid `.external` layout has no cutout to collide with, but it also has
    /// no slack: its width is the literal sum of its parts, and the part it
    /// reserves for the right slot is the `×N` badge's (~22pt) against a
    /// `18h 59m` countdown's ~45. So the external plan tops the accessory up by
    /// the shortfall — otherwise the countdown overhangs the pill's own edge.
    /// `.macbook` needs no top-up: its reserve is symmetric, so the wing the lead
    /// bought on the left is handed to the right as well.
    @Test
    func externalPlanCoversTheCountdownsOwnShortfall() {
        let theme = HaloTheme()
        let slot = Self.criticalUsage()
        let external = theme.closedPillWingPlan(
            label: nil, rightSlot: slot, layout: .external, height: Self.height
        ).leadingAccessoryWidth
        let macbook = theme.closedPillWingPlan(
            label: nil, rightSlot: slot, layout: .macbook, height: Self.height
        ).leadingAccessoryWidth

        #expect(macbook == HaloUsageFilamentLead.estimatedWidth(percent: 92, providerTitle: "Codex"))
        #expect(external > macbook)
        #expect(
            abs(external - macbook
                - (HaloUsageCountdown.reservedWidth - V6RightSlotView.intrinsicWidth(of: slot))) < Self.tolerance
        )

        // The pill that results genuinely holds every part it draws.
        let outer = V6ClosedPill.externalOuterWidth(
            label: nil, rightSlot: slot, minWidth: 70, height: Self.height,
            leadingAccessoryWidth: external
        )
        let needed = Self.pad * 2 + Self.glyph
            + Self.gap + HaloUsageFilamentLead.estimatedWidth(percent: 92, providerTitle: "Codex")
            + Self.gap + HaloUsageCountdown.reservedWidth
        #expect(outer >= needed - Self.tolerance)
    }

    /// The right wing is left holding only the countdown, which is far narrower
    /// than the wing the symmetric reserve gives it — so it can never reach back
    /// under the cutout either.
    @Test
    func countdownFitsTheRightWingWithRoomToSpare() {
        let lead = HaloUsageFilamentLead.estimatedWidth(percent: 92, providerTitle: "Codex")
        let outer = V6ClosedPill.macbookOuterWidth(
            label: nil,
            physicalNotchWidth: Self.cutoutWidth,
            height: Self.height,
            leadingAccessoryWidth: lead
        )
        let wing = (outer - Self.cutoutWidth) / 2
        // `18h 59m` at 11pt tabular ≈ 45pt measured; the wing must beat it even
        // with the trailing pad.
        #expect(wing - Self.pad > 60)
    }

    // MARK: The leaves' copy

    /// The lead's width tracks the text it will draw, so a longer provider name
    /// reserves more wing rather than silently overflowing into the cutout.
    @Test
    func leadWidthGrowsWithTheLabelItDraws() {
        let codex = HaloUsageFilamentLead.estimatedWidth(percent: 92, providerTitle: "Codex")
        let claude = HaloUsageFilamentLead.estimatedWidth(percent: 92, providerTitle: "Claude")
        #expect(claude > codex)
        #expect(HaloUsageFilamentLead.estimatedWidth(percent: 100, providerTitle: "Codex") > codex)
    }

    /// Threshold tint is unchanged by the split — the percent still lights crit
    /// at ≥90, warn at 70…90, fine below.
    @Test
    func leadKeepsTheThresholdTint() {
        #expect(HaloUsageFilamentLead.tint(percent: 92) == HaloEdge.usageCrit)
        #expect(HaloUsageFilamentLead.tint(percent: 78) == HaloEdge.usageWarn)
        #expect(HaloUsageFilamentLead.tint(percent: 34) == HaloEdge.usageFine)
    }

    /// The right wing's token: the countdown when the provider reports a reset,
    /// the window label when it doesn't (never a hole) — the G-32 rule, now owned
    /// by the countdown leaf alone.
    @Test
    func countdownFallsBackToTheWindowLabel() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(HaloUsageCountdown.token(windowLabel: "7d", resetsAt: nil, now: now) == "7d")
        #expect(
            HaloUsageCountdown.token(windowLabel: "7d", resetsAt: now.addingTimeInterval(-60), now: now) == "7d"
        )
        let ahead = HaloUsageCountdown.token(
            windowLabel: "7d",
            resetsAt: now.addingTimeInterval(19 * 3600),
            now: now
        )
        #expect(ahead != "7d")
    }
}

// MARK: - §B docked hover peek (R4 · item 2)

/// §B: "the single black shape begins to grow… the edge-light stretches
/// continuously around the growing silhouette", and §B′'s filmstrip draws the
/// peek frame at the **pill's own width**, just taller. The shipped peek was a
/// fixed 408pt card floating ~4pt under a pill that kept its own ring — two
/// shapes, two outlines. These pin the docking geometry that makes it one.
@MainActor
struct HaloHoverPeekDockTests {
    private static let pillHeight: CGFloat = 44
    private static let pillRadius: CGFloat = 22

    private static func peek(dockedWidth: CGFloat, availableWidth: CGFloat) -> HaloHoverPeek {
        HaloHoverPeek(
            content: HaloHoverPeekContent(
                kind: .permission,
                title: "open-island wants to run a command",
                detail: "swift build",
                monogram: "C",
                moreWaiting: 0
            ),
            lang: .shared,
            availableWidth: availableWidth,
            dockedWidth: dockedWidth,
            pillHeight: pillHeight,
            pillBottomRadius: pillRadius
        )
    }

    /// The docked body takes the pill's width, so the two share one silhouette.
    @Test
    func docksToThePillsOwnWidth() {
        #expect(Self.peek(dockedWidth: 467, availableWidth: 600).resolvedWidth == 467)
    }

    /// A short pill (an unlabelled attention state) still gets the board's own
    /// peek width to narrate in, and the host's surface is always the ceiling.
    @Test
    func clampsToTheHostAndFloorsAtTheBoardWidth() {
        #expect(Self.peek(dockedWidth: 200, availableWidth: 600).resolvedWidth == HaloHoverPeek.preferredWidth)
        #expect(Self.peek(dockedWidth: 900, availableWidth: 520).resolvedWidth == 520)
    }

    /// The knockout is pulled inside the pill's silhouette so this layer's ink
    /// underlaps the pill's antialiased edge. Butting them left a measured 1px
    /// α≈198 hairline straight across the joint — a bright line on any light
    /// desktop, and exactly the seam that read as "two shapes".
    @Test
    func knockoutUnderlapsThePillEdge() {
        #expect(HaloHoverPeekDockShape.knockoutUnderlap > 0)
        // Well inside the pill's own horizontal padding (height / 2), so no pill
        // content can ever be painted over by the dock's fill.
        #expect(HaloHoverPeekDockShape.knockoutUnderlap < Self.pillHeight / 2)
    }

    /// The dock path leaves the pill's interior unpainted (even-odd) while
    /// covering the column below it: a point in the middle of the pill band is
    /// inside BOTH sub-paths, a point in the peek body is inside only the outer
    /// one, and a point in the joint's corner cut-in is inside only the outer one
    /// too — which is what fills the notches the pill's radius would leave.
    @Test
    func dockPathKnocksOutThePillAndFillsTheCornerCutIns() {
        let shape = HaloHoverPeekDockShape(
            pillHeight: Self.pillHeight,
            pillBottomRadius: Self.pillRadius,
            bottomRadius: HaloHoverPeek.cornerRadius
        )
        let rect = CGRect(x: 0, y: 0, width: 467, height: 140)
        let path = shape.path(in: rect)

        // Peek body: painted.
        #expect(path.contains(CGPoint(x: 233, y: 100), eoFill: true))
        // Pill interior: NOT painted — the live pill and its label own it.
        #expect(!path.contains(CGPoint(x: 233, y: 20), eoFill: true))
        // The joint's left corner cut-in — outside the pill's rounded corner but
        // inside the column. Painted, so the union has straight sides.
        #expect(path.contains(CGPoint(x: 1.5, y: Self.pillHeight - 1), eoFill: true))
        // Outside the column entirely.
        #expect(!path.contains(CGPoint(x: -5, y: 100), eoFill: true))
    }
}
