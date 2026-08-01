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

    // MARK: The width math

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

}

