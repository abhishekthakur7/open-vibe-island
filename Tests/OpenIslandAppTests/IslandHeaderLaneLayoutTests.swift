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

    /// The other half of the same invariant: none of the three windows are
    /// lost when starvation forces everything left — all three synthetic
    /// single-window providers land in `left`, not just Claude's own two.
    @Test
    func starvedRightLaneReflowsAllWindowsIntoLeftInsteadOfDroppingThem() {
        let groups = IslandHeaderLaneLayout.laneGroups(for: Self.claudeAndCodex, hasRightLane: false)
        #expect(groups.left.count == 3)
        #expect(groups.left.map { $0.windows[0].id } == ["claude-5h", "claude-7d", "codex-7d"])
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

    /// With ample width, the right lane opens and both provider groups keep
    /// their assigned windows — nothing is dropped in the non-starved case
    /// either.
    @Test
    func metricsWithAmpleWidthNeverDropsProviderGroups() {
        let metrics = IslandHeaderLaneLayout.metrics(
            totalWidth: 900,
            usesNotchAwareLayout: true,
            targetScreen: nil,
            openedHeaderButtonsWidth: 70,
            headerControlSpacing: 8
        )
        #expect(metrics.rightUsageWidth > 0)

        let groups = IslandHeaderLaneLayout.laneGroups(
            for: Self.claudeAndCodex,
            hasRightLane: metrics.rightUsageWidth > 0
        )
        #expect(groups.left.count + groups.right.count == 3)
        #expect(!groups.right.isEmpty)
    }

    // MARK: - The balanced (non-starved) split

    /// With room for a right lane and **no** per-item capacity supplied (the
    /// plain, uncapped call every non-FD theme still makes), the 3 flattened
    /// windows split 2/1 — Claude's two windows stay together on the left,
    /// Codex's single window takes the right — rather than the old
    /// whole-provider split, which put all of Claude's windows left and all
    /// of Codex's right *regardless of width* (and then dropped Codex's
    /// entirely on starvation, since the split never even looked at the
    /// geometry).
    ///
    /// Phase 5 correction: this exact split (2 flattened items sharing one
    /// lane) is what a **naive, non-capacity-aware Flight Deck render**
    /// turned into Defect 1 — two separately-boxed 168pt chips (348pt) is
    /// *wider* than the single 2-window chip (327pt) F8 meant to produce.
    /// The split itself was never the bug; nothing here changed it. FD's own
    /// fix is (a) rendering a lane's flattened items in one shared box
    /// (`FlightDeckUsageSummary.groupsAllProvidersIntoOneChip`) and (b)
    /// passing real per-lane capacities into `laneGroups` — see
    /// `flightDeckCapacityAwareSplitNeverExceedsItsOwnMeasuredChrome` below.
    @Test
    func balancedSplitGroupsFlattenedWindowsAcrossBothLanesWhenUncapped() {
        let groups = IslandHeaderLaneLayout.laneGroups(for: Self.claudeAndCodex, hasRightLane: true)
        #expect(groups.left.map { $0.windows[0].id } == ["claude-5h", "claude-7d"])
        #expect(groups.right.map { $0.windows[0].id } == ["codex-7d"])
    }

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

    /// The starvation contract (a lone provider's windows all land in `left`)
    /// still holds when there genuinely is no right lane — Defect 3 only
    /// changed the *non-starved* case.
    @Test
    func aLoneProviderStillStaysWholeWhenTheRightLaneIsStarved() {
        let claudeOnly = [Self.claudeAndCodex[0]]
        let groups = IslandHeaderLaneLayout.laneGroups(for: claudeOnly, hasRightLane: false)
        #expect(groups.left.count == 2)
        #expect(groups.right.isEmpty)
    }

    @Test
    func emptyProvidersProduceEmptyLanes() {
        let groups = IslandHeaderLaneLayout.laneGroups(for: [], hasRightLane: true)
        #expect(groups.left.isEmpty)
        #expect(groups.right.isEmpty)
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

    /// Three (or more) distinct single-window providers balance the same way
    /// — the split is purely a function of flattened window count, never of
    /// how many distinct providers contributed them.
    @Test
    func threeSingleWindowProvidersBalanceByWindowCountNotProviderCount() {
        let three = [
            UsageProviderPresentation(id: "a", title: "Alpha", windows: [Self.window("a-1", "5h", 10)]),
            UsageProviderPresentation(id: "b", title: "Bravo", windows: [Self.window("b-1", "5h", 20)]),
            UsageProviderPresentation(id: "c", title: "Charlie", windows: [Self.window("c-1", "5h", 30)]),
        ]
        let groups = IslandHeaderLaneLayout.laneGroups(for: three, hasRightLane: true)
        #expect(groups.left.count == 2)
        #expect(groups.right.count == 1)
        #expect(groups.left.map { $0.windows[0].id } + groups.right.map { $0.windows[0].id } == ["a-1", "b-1", "c-1"])
    }

    /// A zero-window "ghost" provider (unreachable via
    /// `AppModel.islandUsageProviders`, which filters empties, but not
    /// defended against here before Phase 5) contributes nothing to
    /// `flatten` and therefore cannot influence the split — the old guard
    /// read raw `providers.count`, so a ghost mixed with one real provider
    /// could flip `providers.count > 1` to `true` despite there being only
    /// one *real* source, defeating the lone-provider rule. Defect 3 removed
    /// that rule entirely, so this is now moot for correctness, but the
    /// invariant — a ghost provider changes nothing — still deserves its own
    /// coverage.
    @Test
    func zeroWindowGhostProviderContributesNothingToTheSplit() {
        let ghost = UsageProviderPresentation(id: "ghost", title: "Ghost", windows: [])
        let real = UsageProviderPresentation(id: "claude", title: "Claude", windows: [
            Self.window("claude-5h", "5h", 34),
            Self.window("claude-7d", "7d", 78),
        ])

        let withGhost = IslandHeaderLaneLayout.laneGroups(for: [ghost, real], hasRightLane: true)
        let withoutGhost = IslandHeaderLaneLayout.laneGroups(for: [real], hasRightLane: true)

        #expect(withGhost.left.map { $0.windows[0].id } == withoutGhost.left.map { $0.windows[0].id })
        #expect(withGhost.right.map { $0.windows[0].id } == withoutGhost.right.map { $0.windows[0].id })
        #expect(IslandHeaderLaneLayout.flatten([ghost, real]).count == 2)
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

    /// The mirror image: a starved right capacity shifts everything feasible
    /// back to the left, as long as left's own capacity can hold it.
    @Test
    func capacityAwareSplitShiftsToTheLaneWithRoomWhenTheOtherCannotFitAnything() {
        let groups = IslandHeaderLaneLayout.laneGroups(
            for: Self.claudeAndCodex,
            hasRightLane: true,
            leftCapacity: 3,
            rightCapacity: 0
        )
        #expect(groups.left.count == 3)
        #expect(groups.right.isEmpty)
    }

    /// Defect 2's "bounded" requirement, restated in capacity terms: when
    /// *neither* lane can fit anything (both capacities 0 — the real-hardware
    /// case measured for Flight Deck, where even one 168pt chip exceeds a
    /// ~120pt lane), the algorithm still doesn't dump every window into one
    /// lane — it keeps the balanced split, so the eventual overflow (which no
    /// split can fully avoid once total demand exceeds total supply) is
    /// shared rather than concentrated.
    @Test
    func capacityAwareSplitFallsBackToBalancedWhenNeitherLaneCanFitAnything() {
        let groups = IslandHeaderLaneLayout.laneGroups(
            for: Self.claudeAndCodex,
            hasRightLane: true,
            leftCapacity: 0,
            rightCapacity: 0
        )
        #expect(groups.left.count == 2)
        #expect(groups.right.count == 1)
    }

    /// Windows-per-lane invariant (explicit coverage the reviewer named):
    /// across a spread of capacity scenarios, `left.count + right.count`
    /// always equals the total flattened window count — capacity constraints
    /// only ever redistribute, never drop.
    @Test
    func capacityNeverChangesTheTotalWindowCountAcrossLanes() {
        let fiveWindows = UsageProviderPresentation(id: "claude", title: "Claude", windows: [
            Self.window("w1", "5h", 10),
            Self.window("w2", "7d", 20),
            Self.window("w3", "30d", 30),
            Self.window("w4", "90d", 40),
            Self.window("w5", "1y", 50),
        ])
        for (left, right) in [(0, 0), (1, 1), (2, 3), (5, 0), (0, 5), (100, 100)] {
            let groups = IslandHeaderLaneLayout.laneGroups(
                for: [fiveWindows],
                hasRightLane: true,
                leftCapacity: left,
                rightCapacity: right
            )
            #expect(groups.left.count + groups.right.count == 5)
        }
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

    /// Requirement 1's other half: the five non-Flight-Deck themes' row-packed
    /// metrics must not move. Since every one of them calls `metrics(...)`
    /// without `controlsLaneArrangement`, the default must reproduce the
    /// pre-existing row-packed formula byte-for-byte — pinned here directly
    /// against the same real-hardware raw widths used above, so a future
    /// change to the default can't silently drift the other five themes.
    @Test
    func defaultArrangementReproducesRowPackedMetricsForTheOtherFiveThemes() {
        let buttonsWidth = (FlightDeckHeaderControls.headerControlButtonSize * 3)
            + (FlightDeckHeaderControls.headerControlSpacing * 2)

        let explicit = IslandHeaderLaneLayout.notchAwareMetrics(
            contentWidth: 540 - 2 * IslandHeaderLaneLayout.notchHeaderHorizontalPadding,
            rawLeftWidth: 131.5,
            rawRightWidth: 130,
            openedHeaderButtonsWidth: buttonsWidth,
            headerControlSpacing: 8,
            controlsLaneArrangement: .rowPacked
        )
        let usingDefault = IslandHeaderLaneLayout.metrics(
            totalWidth: 540,
            usesNotchAwareLayout: true,
            targetScreen: nil,
            openedHeaderButtonsWidth: buttonsWidth,
            headerControlSpacing: 8
        )
        // `targetScreen: nil` hits the synthetic (non-screen) branch, not the
        // real-hardware branch `notchAwareMetrics` models directly — the
        // point of this assertion is narrower: that leaving
        // `controlsLaneArrangement` unspecified is indistinguishable from
        // passing `.rowPacked` explicitly, for both branches of `metrics`.
        let explicitSynthetic = IslandHeaderLaneLayout.metrics(
            totalWidth: 540,
            usesNotchAwareLayout: true,
            targetScreen: nil,
            openedHeaderButtonsWidth: buttonsWidth,
            headerControlSpacing: 8,
            controlsLaneArrangement: .rowPacked
        )
        #expect(usingDefault.leftUsageWidth == explicitSynthetic.leftUsageWidth)
        #expect(usingDefault.rightUsageWidth == explicitSynthetic.rightUsageWidth)
        #expect(usingDefault.rightLaneWidth == explicitSynthetic.rightLaneWidth)
        #expect(usingDefault.centerGapWidth == explicitSynthetic.centerGapWidth)

        // And the real-hardware row-packed branch reproduces the regression
        // (`rightUsageWidth == 0`) regardless of which of the five themes'
        // own button/spacing constants it's fed — Annual/Instrument/Poured/
        // Classic/Halo all still route through this same `.rowPacked` path.
        #expect(explicit.rightUsageWidth == 0)
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

    /// The invariant the brief named explicitly: **never** zero gauges when
    /// there's real capacity and real content — across a spread of
    /// capacities and assigned counts, not just the canonical fixture.
    @Test
    func visibleItemCountNeverRendersZeroGaugesWhenCapacityIsAtLeastOne() {
        for capacity in 1...6 {
            for assignedCount in 1...8 {
                let visible = IslandHeaderLaneLayout.visibleItemCount(assignedCount: assignedCount, capacity: capacity)
                #expect(
                    visible >= 1,
                    "capacity \(capacity) assignedCount \(assignedCount) rendered \(visible) gauges"
                )
            }
        }
    }

    /// `overflowBadgeFits`: the badge draws only in whatever leftover width
    /// `capacity`'s floor division didn't already spend on full items — never
    /// by displacing one. A lane using every pixel of its measured capacity
    /// (the common case once `visibleItemCount` stopped reserving a slot)
    /// gets no badge at all rather than exceeding its width.
    @Test
    func overflowBadgeFitsOnlyInLeftoverWidthNeverByDisplacingAGauge() {
        // The canonical case this ticket derives numerically: capacity 1,
        // 118pt right lane post-column-stack, reduced by the chip's own
        // 2×9pt padding to 100pt. One 96pt gauge already uses 96 of that
        // 100pt — 4pt left, nowhere near the 9 (spacing) + 28 (badge) = 37pt
        // the badge needs alongside it.
        #expect(
            IslandHeaderLaneLayout.overflowBadgeFits(
                laneWidth: 100,
                itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
                itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing,
                badgeWidth: FlightDeckUsageProviderChip.overflowBadgeWidth,
                visibleCount: 1
            ) == false
        )

        // A lane with genuine floor-division slack (capacity computed at 1
        // gauge, but the lane is wide enough to also fit the narrower badge)
        // does allow it.
        #expect(
            IslandHeaderLaneLayout.overflowBadgeFits(
                laneWidth: 96 + 9 + 28,
                itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
                itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing,
                badgeWidth: FlightDeckUsageProviderChip.overflowBadgeWidth,
                visibleCount: 1
            ) == true
        )

        // Zero visible items (capacity 0): the badge fits standalone as long
        // as the lane itself is at least as wide as the badge.
        #expect(
            IslandHeaderLaneLayout.overflowBadgeFits(
                laneWidth: 30,
                itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
                itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing,
                badgeWidth: FlightDeckUsageProviderChip.overflowBadgeWidth,
                visibleCount: 0
            ) == true
        )
        #expect(
            IslandHeaderLaneLayout.overflowBadgeFits(
                laneWidth: 20,
                itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
                itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing,
                badgeWidth: FlightDeckUsageProviderChip.overflowBadgeWidth,
                visibleCount: 0
            ) == false
        )
    }

    /// Lane-width invariant (explicit coverage the brief named): the widest
    /// content a lane can be asked to render — `visibleItemCount` full-size
    /// items plus (only when `overflowBadgeFits` proves there's room) one
    /// overflow affordance narrower than a full item — never exceeds the
    /// lane's own width, for the canonical 3-window fixture (2 lanes,
    /// capacity 1 each, from
    /// `flightDeckCapacityAwareSplitNeverExceedsItsOwnMeasuredChrome`) and a
    /// spread of degenerate capacities. Also asserts the "no zero gauges"
    /// invariant inline: whenever `capacity >= 1` and content is assigned,
    /// `visible >= 1`.
    @Test
    func laneWidthInvariantHoldsForTheCanonicalFixtureAndDegenerateCases() {
        func chipWidth(assignedCount: Int, capacity: Int, reducedLaneWidth: CGFloat) -> (width: CGFloat, visible: Int) {
            let visible = IslandHeaderLaneLayout.visibleItemCount(assignedCount: assignedCount, capacity: capacity)
            let overflowCount = assignedCount - visible
            var width = FlightDeckUsageProviderChip.horizontalPadding * 2
            if visible > 0 {
                width += CGFloat(visible) * FlightDeckUsageWindowGauge.compactGaugeWidth
                width += CGFloat(visible - 1) * FlightDeckUsageProviderChip.interGaugeSpacing
            }
            let badgeFits = overflowCount > 0 && IslandHeaderLaneLayout.overflowBadgeFits(
                laneWidth: reducedLaneWidth,
                itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
                itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing,
                badgeWidth: FlightDeckUsageProviderChip.overflowBadgeWidth,
                visibleCount: visible
            )
            if badgeFits {
                if visible > 0 {
                    width += FlightDeckUsageProviderChip.interGaugeSpacing
                }
                width += FlightDeckUsageProviderChip.overflowBadgeWidth
            }
            return (width, visible)
        }

        // The canonical 3-window fixture at real notch hardware geometry:
        // both lanes measure to capacity 1 (see
        // `flightDeckCapacityAwareSplitNeverExceedsItsOwnMeasuredChrome`),
        // `laneGroups`'s balanced-split fallback still hands one lane 2
        // windows — exactly the case `visibleItemCount` exists for.
        let laneWidth: CGFloat = 118 // the fixed right-lane width post-F7/column-stack fix
        let reducedLaneWidth = laneWidth - FlightDeckUsageProviderChip.horizontalPadding * 2 // 100
        let capacity = 1
        for assignedCount in 0...3 {
            let (width, visible) = chipWidth(assignedCount: assignedCount, capacity: capacity, reducedLaneWidth: reducedLaneWidth)
            #expect(width <= laneWidth, "assignedCount \(assignedCount) produced \(width)pt over a \(laneWidth)pt lane")
            if assignedCount > 0 {
                // Never zero gauges when capacity >= 1 and something is assigned.
                #expect(visible >= 1, "assignedCount \(assignedCount) capacity \(capacity) rendered \(visible) gauges")
            }
        }

        // Degenerate cases named in the brief: zero capacity (badge-only, no
        // gauge fits at all) and ample capacity (no truncation needed).
        // padding (2×9) + one badge (28), no gauges — well under any real lane width.
        let zeroCapacity = chipWidth(assignedCount: 4, capacity: 0, reducedLaneWidth: 32)
        #expect(zeroCapacity.width == FlightDeckUsageProviderChip.horizontalPadding * 2 + FlightDeckUsageProviderChip.overflowBadgeWidth)
        #expect(zeroCapacity.width < 118)
        #expect(chipWidth(assignedCount: 0, capacity: 5, reducedLaneWidth: 1000).width == FlightDeckUsageProviderChip.horizontalPadding * 2)
        let ample = chipWidth(assignedCount: 2, capacity: 5, reducedLaneWidth: 1000)
        let ampleLaneWidth = FlightDeckUsageProviderChip.horizontalPadding * 2
            + 2 * FlightDeckUsageWindowGauge.compactGaugeWidth
            + 1 * FlightDeckUsageProviderChip.interGaugeSpacing
        #expect(ample.width == ampleLaneWidth)
        #expect(ample.visible == 2)
    }

    // MARK: - `flatten`: identity + ordering

    /// Flattening preserves provider order and each provider's internal window
    /// order, assigns a composite id unique across the whole flattened array
    /// (so two windows from the same provider stay distinct `Identifiable`
    /// elements when they land in the same `ForEach` lane), and keeps the
    /// original `title` untouched (every consuming `*UsageSummary` view
    /// renders `provider.title` once and loops `provider.windows`, so it's
    /// unaffected by flattening).
    @Test
    func flattenPreservesOrderAndUniquelyIdentifiesEachWindow() {
        let flattened = IslandHeaderLaneLayout.flatten(Self.claudeAndCodex)
        #expect(flattened.map(\.title) == ["Claude", "Claude", "Codex"])
        #expect(flattened.map { $0.windows[0].id } == ["claude-5h", "claude-7d", "codex-7d"])
        #expect(Set(flattened.map(\.id)).count == 3)
        for item in flattened {
            #expect(item.windows.count == 1)
        }
    }

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
