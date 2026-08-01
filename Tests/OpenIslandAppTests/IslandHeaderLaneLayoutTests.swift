import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// F7 (overlay remediation): `IslandHeaderLaneLayout` is the single shared
/// implementation the opened header's notch-lane split now routes through —
/// previously six byte-identical private copies (`splitUsageProviders` /
/// `openedHeaderMetrics` / `minimumRightUsageLaneWidth`) duplicated across
/// `IslandHeaderControls`, `AnnualHeaderControls`, `InstrumentHeaderControls`,
/// `PouredHeaderControls`, `FlightDeckHeaderControls`, `HaloHeaderControls`.
///
/// The bug: splitting at whole-**provider** granularity meant a width-starved
/// right lane (`rightUsageWidth == 0`) still had an entire provider's windows
/// assigned to it by `splitUsageProviders`, and the render-tree guard
/// (`rightUsageWidth > 0 && !providerGroups.right.isEmpty`) then skipped that
/// group outright — deleting it from the render tree, not shrinking it.
/// Coverage before this file: zero (a `grep` of `Tests/` for
/// `splitUsageProviders` / `minimumRightUsageLaneWidth` / `rightUsageWidth`
/// returned nothing).
struct IslandHeaderLaneLayoutTests {
    private static func window(_ id: String, _ label: String, _ pct: Double) -> UsageWindowPresentation {
        UsageWindowPresentation(id: id, label: label, usedPercentage: pct, resetsAt: nil)
    }

    /// The exact overlay-remediation fixture: Claude carries two windows (5h
    /// 34%, 7d 78%), Codex carries one (7d 92%) — `AppearancePreviewFixtures
    /// .usageProviders` / `AppModel.islandUsageProviders`'s `usageMeters`
    /// scenario.
    private static let claudeAndCodex: [UsageProviderPresentation] = [
        UsageProviderPresentation(id: "claude", title: "Claude", windows: [
            window("claude-5h", "5h", 34),
            window("claude-7d", "7d", 78),
        ]),
        UsageProviderPresentation(id: "codex", title: "Codex", windows: [
            window("codex-7d", "7d", 92),
        ]),
    ]

    // MARK: - The core F7 regression: starvation must reflow, never drop

    /// The exact bug: a width-starved right lane (`rightUsageWidth == 0`) must
    /// never be handed a non-empty provider group by `laneGroups` — that
    /// combination is precisely what the render-tree guard
    /// (`rightUsageWidth > 0 && !providerGroups.right.isEmpty`) turns into a
    /// silent deletion of Codex's window from the header.
    @Test
    func starvedRightLaneNeverReceivesContent() {
        let groups = IslandHeaderLaneLayout.laneGroups(for: Self.claudeAndCodex, hasRightLane: false)
        #expect(groups.right.isEmpty)
    }

    /// End-to-end repro of the exact reported bug at the `metrics` level: a
    /// header band too narrow for the right lane (previously produced
    /// `rightUsageWidth == 0` while `splitUsageProviders` still handed the
    /// whole Codex provider to `right`, and the render guard then dropped it).
    /// Feeding the real starvation result into `laneGroups` must hold the same
    /// invariant the acceptance criterion names directly.
    @Test
    func metricsStarvationNeverPairsWithANonEmptyRightGroup() {
        // A total width far too narrow for both usage lanes + the button
        // cluster to coexist — forces `rightUsageWidth` to clamp to 0 via the
        // shared (unchanged) geometry math's `max(0, …)` floor.
        let metrics = IslandHeaderLaneLayout.metrics(
            totalWidth: 40,
            usesNotchAwareLayout: true,
            targetScreen: nil,
            openedHeaderButtonsWidth: 70,
            headerControlSpacing: 8
        )
        #expect(metrics.rightUsageWidth == 0)

        let groups = IslandHeaderLaneLayout.laneGroups(
            for: Self.claudeAndCodex,
            hasRightLane: metrics.rightUsageWidth > 0
        )
        #expect(!(metrics.rightUsageWidth == 0 && !groups.right.isEmpty))
        #expect(groups.right.isEmpty)
        #expect(groups.left.count == 3)
    }

    // MARK: - The balanced (non-starved) split

    /// Phase 5, Defect 3 (adjudicated): a single provider's windows are
    /// **not** exempt from splitting. Both approved mockups
    /// (`02-flight-deck.html:888-909`, `06-halo.html:767-780`) show a single
    /// two-window provider (Claude 5h / Claude 7d) split **one window per
    /// lane** when there's room — the opposite of the "a lone provider always
    /// stays whole" rule this file shipped with, which reintroduced the exact
    /// restriction `IslandUsageSummary`'s own root-cause note blames: "a
    /// provider's windows could never balance across the physical notch
    /// cutout." This replaces
    /// `aLoneProviderNeverSplitsAcrossTheNotchEvenWithRoomOnTheRight`, which
    /// pinned the now-rejected behaviour.
    @Test
    func aLoneProviderSplitsAcrossTheNotchWhenThereIsRoomOnTheRight() {
        let claudeOnly = [Self.claudeAndCodex[0]]
        let groups = IslandHeaderLaneLayout.laneGroups(for: claudeOnly, hasRightLane: true)
        #expect(groups.left.map { $0.windows[0].id } == ["claude-5h"])
        #expect(groups.right.map { $0.windows[0].id } == ["claude-7d"])
    }

    // MARK: - Defect 2: a single multi-window provider is now bounded

    /// The old code's guard (`providers.count > 1`) meant a *single* provider
    /// with many windows got zero balancing — every window landed in `left`
    /// uncapped, regardless of available room on the right. Not
    /// field-triggerable by real snapshots (which cap at ~2 windows/provider)
    /// but latent and undefended. Now that `laneGroups` no longer
    /// special-cases provider count (Defect 3), a 5-window single provider
    /// balances exactly like 5 windows from any mix of providers would.
    @Test
    func aSingleProviderWithManyWindowsBalancesInsteadOfPilingIntoOneLane() {
        let fiveWindows = UsageProviderPresentation(id: "claude", title: "Claude", windows: [
            Self.window("w1", "5h", 10),
            Self.window("w2", "7d", 20),
            Self.window("w3", "30d", 30),
            Self.window("w4", "90d", 40),
            Self.window("w5", "1y", 50),
        ])
        let groups = IslandHeaderLaneLayout.laneGroups(for: [fiveWindows], hasRightLane: true)
        #expect(groups.left.count == 3)
        #expect(groups.right.count == 2)
        #expect(groups.left.count + groups.right.count == 5)
    }

    // MARK: - Capacity-aware split (Defect 1)

    /// The core capacity contract: when both lanes' capacities combined cover
    /// every window, neither lane is ever handed more than its own capacity
    /// — the split shifts weight to whichever lane still has room instead of
    /// blindly halving.
    @Test
    func capacityAwareSplitRespectsEachLanesOwnFitBudget() {
        let groups = IslandHeaderLaneLayout.laneGroups(
            for: Self.claudeAndCodex,
            hasRightLane: true,
            leftCapacity: 1,
            rightCapacity: 2
        )
        #expect(groups.left.count == 1)
        #expect(groups.right.count == 2)
        #expect(groups.left.count + groups.right.count == 3)
    }

    // MARK: - Flight Deck-specific width-fit assertion (Defect 1)

    /// Ties `IslandHeaderLaneLayout.capacity` + FD's own real chrome
    /// constants (`FlightDeckUsageProviderChip.horizontalPadding` /
    /// `.interGaugeSpacing`, `FlightDeckUsageWindowGauge.compactGaugeWidth`)
    /// to the geometry `IslandHeaderLaneLayout.metrics` reports for FD's real
    /// button constants, at the canonical 3-window overlay-remediation
    /// fixture — so a future regression that widens any of FD's chrome or
    /// shrinks the header band shows up as a failing number, not a silent
    /// overflow only visible in a capture.
    @Test
    func flightDeckCapacityAwareSplitNeverExceedsItsOwnMeasuredChrome() {
        let buttonsWidth = (FlightDeckHeaderControls.headerControlButtonSize * 3)
            + (FlightDeckHeaderControls.headerControlSpacing * 2)
        // Deliberately the default `.rowPacked` arrangement: FD's `body`
        // still calls `metrics(...)` without `controlsLaneArrangement` — see
        // `flightDeckColumnStackedRightLaneIsNonZeroAtRealNotchHardwareGeometry`
        // below for why `.columnStacked` (which *would* fix the F7 right-lane
        // regression on real hardware) isn't wired into production yet.
        let metrics = IslandHeaderLaneLayout.metrics(
            totalWidth: 540,
            usesNotchAwareLayout: true,
            targetScreen: nil,
            openedHeaderButtonsWidth: buttonsWidth,
            headerControlSpacing: FlightDeckHeaderControls.headerControlSpacing
        )

        func capacity(_ laneWidth: CGFloat) -> Int {
            IslandHeaderLaneLayout.capacity(
                laneWidth: max(0, laneWidth - FlightDeckUsageProviderChip.horizontalPadding * 2),
                itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
                itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing
            )
        }

        let leftCapacity = capacity(metrics.leftUsageWidth)
        let rightCapacity = capacity(metrics.rightUsageWidth)

        // Whatever capacity comes out to, the *content* that capacity implies
        // must not exceed the lane's real width — the arithmetic the fix
        // relies on, pinned directly rather than just trusted.
        if leftCapacity > 0 {
            let content = FlightDeckUsageProviderChip.horizontalPadding * 2
                + CGFloat(leftCapacity) * FlightDeckUsageWindowGauge.compactGaugeWidth
                + CGFloat(leftCapacity - 1) * FlightDeckUsageProviderChip.interGaugeSpacing
            #expect(content <= metrics.leftUsageWidth)
        }
        if rightCapacity > 0 {
            let content = FlightDeckUsageProviderChip.horizontalPadding * 2
                + CGFloat(rightCapacity) * FlightDeckUsageWindowGauge.compactGaugeWidth
                + CGFloat(rightCapacity - 1) * FlightDeckUsageProviderChip.interGaugeSpacing
            #expect(content <= metrics.rightUsageWidth)
        }

        let groups = IslandHeaderLaneLayout.laneGroups(
            for: Self.claudeAndCodex,
            hasRightLane: metrics.rightUsageWidth > 0,
            leftCapacity: leftCapacity,
            rightCapacity: rightCapacity
        )
        #expect(groups.left.count + groups.right.count == 3)
    }

    // MARK: - Column-stack correction (Phase 5, "Flight Deck column-stack")

    /// The exact regression this correction targets, reproduced without a
    /// live notched `NSScreen` (its `auxiliaryTopLeftArea`/
    /// `auxiliaryTopRightArea` aren't mockable, and depending on whichever
    /// physical Mac runs the suite would make this environment-dependent —
    /// see `notchAwareMetrics`'s doc comment). `rawLeftWidth`/`rawRightWidth`
    /// below are the literal measured real-hardware numbers (540pt panel)
    /// the brief reports: `rawRightWidth: 130` decomposes as
    /// `130 − 12 (notchLaneSafetyInset) − 82 (buttons) − 8 (spacing) = 28pt`,
    /// under `minimumRightUsageLaneWidth (58)` ⇒ snaps to 0 when row-packed —
    /// the bug. `rawLeftWidth: 131.5` is back-derived from the reported
    /// `leftUsageWidth == 119.5` (`131.5 − 12 == 119.5`).
    @Test
    func flightDeckColumnStackedRightLaneIsNonZeroAtRealNotchHardwareGeometry() {
        let buttonsWidth = (FlightDeckHeaderControls.headerControlButtonSize * 3)
            + (FlightDeckHeaderControls.headerControlSpacing * 2)
        #expect(buttonsWidth == 82)

        let rowPacked = IslandHeaderLaneLayout.notchAwareMetrics(
            contentWidth: 540 - 2 * IslandHeaderLaneLayout.notchHeaderHorizontalPadding,
            rawLeftWidth: 131.5,
            rawRightWidth: 130,
            openedHeaderButtonsWidth: buttonsWidth,
            headerControlSpacing: FlightDeckHeaderControls.headerControlSpacing,
            controlsLaneArrangement: .rowPacked
        )
        // Reproduces the measured regression exactly: 28pt proposed, below
        // the 58pt floor, snaps to 0.
        #expect(rowPacked.leftUsageWidth == 119.5)
        #expect(rowPacked.rightUsageWidth == 0)

        let columnStacked = IslandHeaderLaneLayout.notchAwareMetrics(
            contentWidth: 540 - 2 * IslandHeaderLaneLayout.notchHeaderHorizontalPadding,
            rawLeftWidth: 131.5,
            rawRightWidth: 130,
            openedHeaderButtonsWidth: buttonsWidth,
            headerControlSpacing: FlightDeckHeaderControls.headerControlSpacing,
            controlsLaneArrangement: .columnStacked
        )
        // The fix: the gauge is no longer charged for the buttons' width, so
        // the same 118pt of post-inset available width (130 − 12) clears the
        // 58pt floor outright.
        #expect(columnStacked.rightUsageWidth == 118)
        #expect(columnStacked.rightUsageWidth > 0)
        // The left lane has no buttons to share space with in either
        // arrangement — confirming the fix is scoped to the right lane only.
        #expect(columnStacked.leftUsageWidth == rowPacked.leftUsageWidth)
    }

    /// The "no zero gauges" correction (Phase 5, adversarial review round 3):
    /// `visibleItemCount` renders `min(assignedCount, capacity)` — it no
    /// longer reserves a slot for an overflow affordance regardless of
    /// whether `assignedCount` exceeds `capacity`. The retired reserved-slot
    /// rule (`capacity - 1` whenever `assignedCount > capacity`) is exactly
    /// what produced **zero** gauges at `capacity == 1` — FD's real
    /// notch-hardware capacity — rendering a bare "+N" and none of the
    /// user's actual numbers.
    @Test
    func visibleItemCountRendersEveryItemCapacityCanHoldWithoutReservingASlot() {
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: 0, capacity: 1) == 0)
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: 1, capacity: 1) == 1)
        // The exact regression: 2 assigned at capacity 1 used to render 0
        // gauges (`capacity - 1`); it now renders the 1 gauge that fits.
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: 2, capacity: 1) == 1)
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: 3, capacity: 2) == 2)
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: 5, capacity: 0) == 0)
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: 5, capacity: .max) == 5)
        // Negative inputs clamp rather than underflow.
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: -1, capacity: 3) == 0)
        #expect(IslandHeaderLaneLayout.visibleItemCount(assignedCount: 3, capacity: -1) == 0)
    }

    // MARK: - `flatten`: identity + ordering

    /// `shortTitle` switches on `title`, not the (now composite, post-flatten)
    /// `id` — so the abbreviation survives flattening. Regression guard for
    /// the F7 refactor: before, `shortTitle` switched on `id` (`"claude"` /
    /// `"codex"`), which a composite flattened id (`"claude#claude-5h"`)
    /// would no longer match, silently falling through to
    /// `String(title.prefix(2))` and turning "Codex" into "Co" instead of the
    /// shipped "Cx".
    @Test
    func shortTitleSurvivesFlatteningBecauseItSwitchesOnTitle() {
        let flattened = IslandHeaderLaneLayout.flatten(Self.claudeAndCodex)
        #expect(flattened[0].shortTitle == "Cl")   // Claude · 5h
        #expect(flattened[1].shortTitle == "Cl")   // Claude · 7d
        #expect(flattened[2].shortTitle == "Cx")   // Codex · 7d
    }
}
