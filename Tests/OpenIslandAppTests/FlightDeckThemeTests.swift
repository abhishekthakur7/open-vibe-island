import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-311 (flightdeck 1/4): the Flight Deck theme's shell — registration, the
/// phosphor annunciator token identity, the flat-panel material, the mono
/// typography floor, and the theme's own square-annunciator-light grid geometry.
///
/// Serialized and defaults-clearing like `ThemeSelectionTests` /
/// `InstrumentThemeTests`, since the registry / persistence checks construct real
/// `AppModel`s that read `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct FlightDeckThemeTests {
    private static let themeKey = "appearance.island.v8.theme"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }

    // MARK: - Registration (AC #1)

    // MARK: - Phosphor palette (AC #2)

    // MARK: - Flat panel material (AC #3 · #6)

    // MARK: - Mono typography floor (AC #2)

    // MARK: - Two-font split contract (AB-337 · SPEC §2)

    /// The 2.0 board's mono/sans split: narration prose the reader *reads* — the
    /// session name, live narration, assistant rich text, gauge legends — draws
    /// **sans**, and every *value* the reader *scans* — status codes, counts,
    /// the mono body/label/micro-label — draws **mono tabular**. No test pinned
    /// font design before this; a `Font` is opaque, so the contract is pinned on
    /// the `roleFamilies` table the font builders derive their design from.
    @Test
    func monoSansSplitHoldsTheTwoFontContract() {
        // Narration roles are sans — the headline is explicitly NOT monospaced.
        #expect(FlightDeckTypography.family(of: "sessionName") == .sans)
        #expect(FlightDeckTypography.family(of: "narration") == .sans)
        #expect(FlightDeckTypography.family(of: "assistant") == .sans)
        #expect(FlightDeckTypography.family(of: "gaugeLabel") == .sans)
        #expect(FlightDeckTypography.family(of: "countGlyph") == .sans)
        #expect(FlightDeckTypography.family(of: "countLabel") == .sans)

        // Value roles are mono — the status code and every counter/body ARE
        // monospaced (tabular numerals ride the mono design for free).
        #expect(FlightDeckTypography.family(of: "statusCode") == .mono)
        #expect(FlightDeckTypography.family(of: "resetCountdown") == .mono)
        #expect(FlightDeckTypography.family(of: "annunciatorContext") == .mono)
        #expect(FlightDeckTypography.family(of: "heldLabel") == .mono)
        #expect(FlightDeckTypography.family(of: "completionJumpLabel") == .mono)
        #expect(FlightDeckTypography.family(of: "count") == .mono)
        #expect(FlightDeckTypography.family(of: "microLabel") == .mono)
        #expect(FlightDeckTypography.family(of: "label") == .mono)
        #expect(FlightDeckTypography.family(of: "body") == .mono)
        #expect(FlightDeckTypography.family(of: "gaugeValue") == .mono)
        #expect(FlightDeckTypography.family(of: "gaugeUnit") == .mono)

        // F17's three same-sized count roles intentionally differ by both
        // semantic family and weight; do not fold them back into one font.
        #expect(FlightDeckTypography.weight(of: "countGlyph") == .bold)
        #expect(FlightDeckTypography.weight(of: "countLabel") == .medium)
        #expect(FlightDeckTypography.weight(of: "count") == .semibold)
        #expect(FlightDeckTypography.weight(of: "gaugeValue") == .bold)
        #expect(FlightDeckTypography.weight(of: "resetCountdown") == .medium)
        #expect(FlightDeckTypography.weight(of: "annunciatorContext") == .medium)
        #expect(FlightDeckTypography.weight(of: "heldLabel") == .medium)
        #expect(FlightDeckTypography.weight(of: "completionJumpLabel") == .semibold)

        // The two families map onto the two `Font.Design`s the split intends.
        #expect(FlightDeckTypography.Family.sans.design == .default)
        #expect(FlightDeckTypography.Family.mono.design == .monospaced)

        // Every role in the table declares a family, and an unknown role is nil.
        #expect(FlightDeckTypography.family(of: "does-not-exist") == nil)
        #expect(FlightDeckTypography.weight(of: "does-not-exist") == nil)
        #expect(FlightDeckTypography.roleFamilies.allSatisfy { !$0.name.isEmpty })
    }

    // MARK: - Annunciator summary tile geometry / typography (overlay remediation F9)

    // MARK: - Own square-annunciator-light grid geometry (AC #6)

    // MARK: - Capability flags

    // MARK: - Question-prompt pagination (overlay remediation Phase 2B · F1a/D1)

    // MARK: - Opened-header band height (overlay remediation Phase 5 · F8)

    // MARK: - Uppercase micro-labels neutralize for CJK

    // MARK: - Tape gauge colour + placard bands + threshold geometry (AB-338 AC #1)

    // MARK: - Hidden-window indicator (overlay remediation E3)

    /// End-to-end trace of the exact E3 regression at the pure-arithmetic
    /// seam, reusing the real geometry from
    /// `IslandHeaderLaneLayoutTests.overflowBadgeFitsOnlyInLeftoverWidthNeverByDisplacingAGauge`:
    /// a lane assigned 2 flattened windows at capacity 1 (FD's real
    /// notch-hardware capacity, the canonical 3-window fixture) renders 1
    /// visible gauge and hides 1 — and the inline badge's 37pt requirement
    /// doesn't fit the ~4pt of leftover width a 100pt reduced lane has after
    /// that one gauge. This confirms the corner indicator, not silence, is
    /// what actually reaches the screen for that exact case.
    @Test
    func e3RegressionCanonicalFixtureLaneGetsACornerIndicatorNotSilence() {
        let capacity = 1
        let assignedCount = 2
        let visible = IslandHeaderLaneLayout.visibleItemCount(assignedCount: assignedCount, capacity: capacity)
        let overflowCount = assignedCount - visible
        #expect(overflowCount == 1)

        let reducedLaneWidth: CGFloat = 100 // 119.5pt real left lane − 2×9pt chip padding
        let badgeFits = IslandHeaderLaneLayout.overflowBadgeFits(
            laneWidth: reducedLaneWidth,
            itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
            itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing,
            badgeWidth: FlightDeckUsageProviderChip.overflowBadgeWidth,
            visibleCount: visible
        )
        #expect(badgeFits == false)

        #expect(
            FlightDeckUsageProviderChip.OverflowAffordance.decide(overflowCount: overflowCount, allowsOverflowBadge: badgeFits)
                == .corner(count: 1)
        )
    }

    // MARK: - Theme name / descriptor localize (AC #1)

    // MARK: - Actionable surface strings localize (AB-314 AC #6 · #8)

    // MARK: - Layered surface hierarchy (AB-335)

    // MARK: - Closed-pill attention segment (AB-338 AC #2 · SPEC §4A A3/A4)

    // MARK: - Closed-pill wing label tone (AB-338 AC #3 · SPEC §4A A2/A5)

    /// The wing label tone-splits the resolver's own output: a working narration
    /// into a green verb + bright object, the `N working` aggregate into a strong
    /// count + dim qualifier, and a completion into an advisory `Done ·` prefix +
    /// bright workspace. Non-splittable frames render as one run.
    @Test
    func wingLabelToneSplitsWorkingAndCompletion() {
        typealias Seg = FlightDeckPillLabelTone.Segment

        // A2 working — "Editing AppModel.swift" → verb green, object bright.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Editing AppModel.swift", ambient: .working(manyWorking: false))
                == [Seg(text: "Editing", role: .verb), Seg(text: " AppModel.swift", role: .object)]
        )
        // A2′ aggregate — "3 working" → count strong, qualifier dim.
        #expect(
            FlightDeckPillLabelTone.segments(for: "3 working", ambient: .working(manyWorking: true))
                == [Seg(text: "3", role: .count), Seg(text: " working", role: .plain)]
        )
        // A5 completion — "Done · the-automator" → advisory prefix, bright workspace.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Done · the-automator", ambient: .completed(.success))
                == [Seg(text: "Done ·", role: .donePrefix), Seg(text: " the-automator", role: .object)]
        )
        // Idle / permission / question carry no split — one plain run.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Approve swift build?", ambient: .permission)
                == [Seg(text: "Approve swift build?", role: .plain)]
        )
        // A single-word working label with no object is still one object run.
        #expect(
            FlightDeckPillLabelTone.segments(for: "Working", ambient: .working(manyWorking: false))
                == [Seg(text: "Working", role: .object)]
        )
        // Empty text yields no segments (the pill draws nothing).
        #expect(FlightDeckPillLabelTone.segments(for: "   ", ambient: .idle).isEmpty)
    }
}

// MARK: - Closed-pill width regression (AB-338 · the T12/AB-330 contract)

/// AB-338 renders two *new* right-slot kinds in the Flight Deck idiom (the
/// attention segment and the usage mini-tape) and adds the two-tone wing labels,
/// but the shipped `V6ClosedPill.*OuterWidth` math must stay **byte-identical** —
/// the closed↔opened morph frame (and every theme's pill silhouette) depends on
/// it, and the FD variants must render *inside* the slot the fluid layout already
/// reserved, never widen it. Mirrors `PouredClosedPillWidthRegressionTests` (the
/// T12/AB-330 precedent) so a drift in the width math fails the build regardless
/// of what the FD right-slot / wing views draw.
@MainActor
struct FlightDeckClosedPillWidthRegressionTests {
    private static let height: CGFloat = 38
    private static let tolerance: CGFloat = 0.001

    private func external(_ label: String?, _ rightSlot: IslandRightSlotContent?) -> CGFloat {
        V6ClosedPill.externalOuterWidth(label: label, rightSlot: rightSlot, minWidth: 70, height: Self.height)
    }

    /// The four count-shaped kinds (`.count`, `.attentionCount`, `.taskCounter`,
    /// `.usage`) share the badge width math, so the FD attention-segment and
    /// usage-mini-tape renderings never move the external frame.
    @Test
    func externalOuterWidthGoldensAreUnchanged() {
        #expect(abs(external(nil, nil) - 70) < Self.tolerance)
        #expect(abs(external("Editing AppModel.swift", nil) - 238.6) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 1, kind: .permission)) - 82.4) < Self.tolerance)
        #expect(abs(external(nil, .attentionCount(count: 12, kind: .question)) - 89.6) < Self.tolerance)
        #expect(abs(external(nil, .usage(percent: 92, windowLabel: "7d", providerTitle: "Claude")) - 89.6) < Self.tolerance)
        #expect(abs(external("Done · the-automator", nil) - 224) < Self.tolerance)
    }
}
