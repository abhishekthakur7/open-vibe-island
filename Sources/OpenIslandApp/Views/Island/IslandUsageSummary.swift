import AppKit
import SwiftUI
import OpenIslandCore

/// One usage provider (Claude, Codex, …) and its rate-limit windows, in the
/// shape the header's usage chips render. Built at the `IslandPanelView` call
/// site from the model's usage snapshots and handed to `IslandUsageSummary` /
/// `IslandHeaderControls` by value.
struct UsageProviderPresentation: Identifiable {
    let id: String
    let title: String
    let windows: [UsageWindowPresentation]

    var peakWindow: UsageWindowPresentation? {
        windows.max { lhs, rhs in
            lhs.usedPercentage < rhs.usedPercentage
        }
    }

    var peakWindowLabel: String {
        peakWindow?.label ?? ""
    }

    var peakUsedPercentage: Double {
        peakWindow?.usedPercentage ?? 0
    }

    var peakUsagePercentage: Int {
        peakWindow?.roundedUsedPercentage ?? 0
    }

    /// Switches on `title`, not `id` (F7): flattened single-window providers
    /// built by `IslandHeaderLaneLayout.flatten` carry a composite `id`
    /// (`"<provider.id>#<window.id>"`, so two windows from the same source
    /// provider stay unique `Identifiable` elements when they land in the same
    /// lane) but keep the source provider's unmodified `title` — so the
    /// abbreviation still resolves correctly post-flatten.
    var shortTitle: String {
        switch title {
        case "Claude":
            "Cl"
        case "Codex":
            "Cx"
        default:
            String(title.prefix(2))
        }
    }
}

struct UsageWindowPresentation: Identifiable {
    let id: String
    let label: String
    let usedPercentage: Double
    let resetsAt: Date?

    var roundedUsedPercentage: Int {
        Int(usedPercentage.rounded())
    }
}

/// Builds the shared localized text used by usage-summary tooltips and their
/// single grouped VoiceOver stop. Keeping this pure formatter beside the usage
/// presentation models prevents visual themes from drifting in punctuation or
/// reset semantics.
enum UsageSummaryAccessibilityFormatter {
    static func detail(
        for window: UsageWindowPresentation,
        asOf now: Date,
        lang: LanguageManager
    ) -> String {
        var detail = "\(window.label) \(window.roundedUsedPercentage)%"
        if let remaining = window.remainingLabel(asOf: now) {
            detail += ", \(lang.t("a11y.usage.resetsIn", remaining))"
        }
        return detail
    }

    static func summary(
        for provider: UsageProviderPresentation,
        usesShortTitle: Bool,
        asOf now: Date,
        lang: LanguageManager
    ) -> String {
        let title = usesShortTitle ? provider.shortTitle : provider.title
        let details = provider.windows.map {
            detail(for: $0, asOf: now, lang: lang)
        }
        .joined(separator: " · ")

        return details.isEmpty ? title : "\(title) \(details)"
    }

    static func summary(
        for providers: [UsageProviderPresentation],
        usesShortTitles: Bool,
        asOf now: Date,
        lang: LanguageManager
    ) -> String {
        providers.map {
            summary(
                for: $0,
                usesShortTitle: usesShortTitles,
                asOf: now,
                lang: lang
            )
        }
        .joined(separator: " · ")
    }
}

// MARK: - Shared opened-header lane geometry (F7, overlay remediation)

/// The opened-header usage-lane split + notch-cutout geometry, shared by every
/// themed opened-header controls view (`IslandHeaderControls`,
/// `AnnualHeaderControls`, `InstrumentHeaderControls`, `PouredHeaderControls`,
/// `FlightDeckHeaderControls`, `HaloHeaderControls`).
///
/// **Before F7** this was six byte-identical private copies —
/// `splitUsageProviders` / `openedHeaderMetrics` / `minimumRightUsageLaneWidth`,
/// one per theme, only the returned metrics-struct name differing. Splitting at
/// whole-**provider** granularity meant a provider's windows could never
/// balance across the physical notch cutout; and when the geometry starved the
/// right lane below `minimumRightUsageLaneWidth`, `rightUsageWidth` snapped to
/// exactly `0` while the provider group already assigned to that lane still
/// held an entire provider's windows — the render-tree guard
/// (`rightUsageWidth > 0 && !providerGroups.right.isEmpty`) then skipped the
/// group outright, silently deleting it from the render tree instead of
/// shrinking it.
///
/// **The fix**: `metrics(...)` computes the pure header-band geometry first
/// (unchanged math, content-independent), then `laneGroups(for:hasRightLane:)`
/// decides lane membership **from that result** at flattened `(provider,
/// window)` granularity (`flatten`). When the right lane is geometrically
/// starved, every flattened window routes to `left` instead of being handed to
/// a lane about to render at zero width — so the right lane renders nothing
/// only because it holds nothing, never because content was dropped.
///
/// **Phase 5 correction (Defect 1/2/3, overlay remediation adversarial
/// review).** The fix above shipped with two problems, both corrected here:
///
/// 1. **Defect 3 — the "a lone provider always stays whole" rule was wrong.**
///    It reintroduced, for the single-provider case, exactly the restriction
///    this file's own root-cause note blames: "a provider's windows could
///    never balance across the physical notch cutout." Both approved
///    mockups (`02-flight-deck.html:888-909`, `06-halo.html:767-780`) show a
///    single two-window provider (Claude 5h / Claude 7d) split **one window
///    per lane** — the opposite of "stays whole." Adjudicated: the mockups
///    are the target. `laneGroups` no longer special-cases provider count at
///    all — every flattened window splits by the same rule regardless of how
///    many source providers it came from. (This also fixes the "ghost
///    provider" hazard: the old guard read raw `providers.count`, so an
///    empty-window provider mixed with a real one could flip the exemption
///    despite contributing zero flattened items; the new guard reads
///    `flattened.count`, which a zero-window provider cannot inflate.)
/// 2. **Defect 1/2 — count-based splitting can't bound a lane's rendered
///    width, and had no defensive cap.** With 3 windows and 2 lanes, some
///    lane holds 2 items no matter how the split point is chosen — and for
///    Flight Deck specifically, 2 chips' worth of chrome (2×168pt + 12pt gap
///    = 348pt) is *wider* than the single 2-window chip (327pt) F8 was meant
///    to fix, because `flatten` turns one 2-window provider into two
///    separately-boxed array elements. `laneGroups` now optionally takes
///    `leftCapacity`/`rightCapacity` — the max item count each lane can
///    render without exceeding its real width, a plain `Int` the *caller*
///    derives from its own per-item width (a theme-specific **measurement**,
///    passed as a parameter — see `capacity(laneWidth:itemWidth:itemSpacing:)`
///    below). When both lanes' combined capacity covers every window, the
///    split favours the plain balanced (ceil/floor) point but shifts weight
///    into whichever lane still has room, so neither lane is handed more
///    than it can actually render. When capacity is insufficient even
///    combined, it falls back to the plain balanced split — sharing the
///    overflow roughly in half instead of concentrating every window in one
///    lane (bounds the previously-uncapped single-lane case). Windows are
///    never dropped either way — the default (`.max`) capacities reduce to
///    the unmodified plain balanced split, so the five themes that don't pass
///    real capacities are unaffected beyond the Defect 3 fix.
///
/// **Phase 5 correction (column-stack, adversarial review round 2).** Even
/// with Defect 1/2/3 fixed, real notch hardware still measured
/// `rightUsageWidth == 0` for Flight Deck specifically, because `metrics(...)`
/// charged the gauge for the buttons' width as if they shared one row —
/// `rightAvailableWidth - openedHeaderButtonsWidth - headerControlSpacing`.
/// That row-packed shape matches five themes' own header markup, but **not**
/// Flight Deck's own board (`02-flight-deck.html:282`,
/// `.phead .lane{flex-direction:column}`), which stacks the button row above
/// the gauge instead of beside it. `metrics(...)` now takes
/// `controlsLaneArrangement` (default `.rowPacked`, unchanged behaviour) so a
/// caller can opt into `.columnStacked`: the gauge gets the lane's full
/// available width (nothing shared out to the buttons), and the lane's total
/// width is `max(buttons, gauge)` instead of their sum. This is a
/// **measurement flag**, not a per-theme override of the algorithm — the
/// function stays the one shared, pure-geometry implementation for all six
/// themes.
///
/// **`.columnStacked` is now wired into `FlightDeckHeaderControls`'s render**
/// (overlay remediation Phase 5, "opened-header band growth" correction).
/// It was proven correct and unit-tested
/// (`IslandHeaderLaneLayoutTests
/// .flightDeckColumnStackedRightLaneIsNonZeroAtRealNotchHardwareGeometry`)
/// before this, but deliberately held back: the width fix was only half the
/// story while the opened header's reserved band
/// (`IslandPanelView.openedHeaderContent.frame(height: closedNotchHeight)`,
/// a fixed, non-clipping frame) was only ~34-38pt tall on real notch hardware
/// — stacking the button row (22pt) + spacing above FD's own gauge chip
/// (≈57pt with a reset row, the production-normal case) would have
/// reintroduced F8's vertical overflow from a different source. That blocker
/// is now resolved by `IslandTheme.openedHeaderHeight` (`IslandTheme.swift`):
/// Flight Deck claims its own taller band (96pt) independently of the closed
/// pill's height, so `.columnStacked`'s width fix can render safely. See
/// `FlightDeckHeaderControls.swift`'s `body` and this ticket's report for the
/// full numeric trace.
enum IslandHeaderLaneLayout {
    static let headerHorizontalPadding: CGFloat = 18
    static let notchHeaderHorizontalPadding: CGFloat = 46
    static let notchLaneSafetyInset: CGFloat = 12
    /// The floor a right-of-notch usage lane must clear before it is allowed to
    /// render at all (below it, `rightUsageWidth` snaps to `0` and every
    /// flattened window routes to the left lane instead).
    ///
    /// **Do not "just lower this" to make a starved lane render** (halo parity
    /// Q2, final-gate finding #1 — measured on 14" notch hardware, panel surface
    /// 540pt, `HaloHeaderControls`' own instrumentation): `rawRightWidth` is
    /// 131.5pt, of which `notchLaneSafetyInset` takes 12 and the three 26pt
    /// controls + their 8pt gap take 94 + 8 — leaving the gauge **17.5pt**, not
    /// the ~52 the parity notes assumed. No value of this constant admits a
    /// legible gauge into 17.5pt, and the themes' own header gauges need *more*
    /// than 58, not less: Halo's §C filament is a 30pt arc + 9pt gap + an 11pt
    /// percent readout ≈ 64pt (≈56pt even at the 22pt top-bar arc with the
    /// kicker dropped). Freeing the missing ~35–45pt means changing the header
    /// itself — `notchHeaderHorizontalPadding` (46 here; the Halo board's
    /// `.p-head` says 16, which alone recovers 30pt), the control size, or
    /// column-stacking the lane — never this floor.
    static let minimumRightUsageLaneWidth: CGFloat = 58

    /// How the right lane's control buttons share their lane with the usage
    /// gauge(s) (Phase 5, "Flight Deck column-stack" correction).
    ///
    /// Five themes (Classic, Annual, Instrument, Poured, Halo) pack the
    /// buttons and the gauge **side by side** in one row — the buttons'
    /// fixed-width chrome must be subtracted from the lane's available width
    /// before any of it can go to the gauge, and the lane's total width is
    /// their **sum**. Flight Deck's own board (`02-flight-deck.html:282`,
    /// `.phead .lane{flex-direction:column}`) instead **stacks** the button
    /// row above the gauge — the two never compete for the same horizontal
    /// space, so the lane's available gauge width is the lane's full width,
    /// and the lane's total width is the **max** of the two, not their sum.
    ///
    /// This is a plain geometry **measurement flag**, not a per-theme
    /// override of the algorithm below — `metrics(...)` stays the one shared,
    /// theme-agnostic function for all six themes (see the enum's top-level
    /// doc comment on why this deliberately isn't hoisted onto the
    /// `IslandTheme` protocol instead).
    enum ControlsLaneArrangement {
        /// Buttons and gauge share the lane horizontally (the five
        /// non-Flight-Deck themes; also this function's default, so every
        /// existing call site is unaffected unless it opts in).
        case rowPacked
        /// Buttons sit in their own row, stacked above the gauge (Flight
        /// Deck only).
        case columnStacked
    }

    struct Metrics {
        let leftUsageWidth: CGFloat
        let centerGapWidth: CGFloat
        let rightUsageWidth: CGFloat
        let rightLaneWidth: CGFloat
    }

    struct LaneGroups {
        let left: [UsageProviderPresentation]
        let right: [UsageProviderPresentation]
    }

    static func horizontalPadding(usesNotchAwareLayout: Bool) -> CGFloat {
        usesNotchAwareLayout ? notchHeaderHorizontalPadding : headerHorizontalPadding
    }

    /// Flattens each provider's rate-limit windows into synthetic
    /// single-window providers. Keeps the source provider's `title` unchanged
    /// (so `shortTitle` and every consuming `*UsageSummary` view — which
    /// already renders `provider.title` once and loops `provider.windows` —
    /// are unaffected by flattening), but assigns a composite `id`
    /// (`"<provider.id>#<window.id>"`) so two windows from the same source
    /// provider stay unique `Identifiable` elements when they land in the same
    /// `ForEach` lane.
    static func flatten(_ providers: [UsageProviderPresentation]) -> [UsageProviderPresentation] {
        providers.flatMap { provider in
            provider.windows.map { window in
                UsageProviderPresentation(
                    id: "\(provider.id)#\(window.id)",
                    title: provider.title,
                    windows: [window]
                )
            }
        }
    }

    /// Splits `providers` into left/right usage lanes at flattened
    /// `(provider, window)` granularity, optionally capacity-aware.
    ///
    /// - `hasRightLane` must be `metrics.rightUsageWidth > 0`, computed
    ///   *before* this call — when the header band is geometrically starved,
    ///   every window routes to `left` instead of being handed to a lane about
    ///   to render at zero width (the F7 regression).
    /// - No provider-count special-casing (Phase 5 Defect 3 — see the enum's
    ///   doc comment): a single provider's windows split across lanes exactly
    ///   like any other flattened set, matching the approved mockups.
    /// - `leftCapacity` / `rightCapacity` (Phase 5 Defect 1/2, default `.max`
    ///   — uncapped, i.e. the plain balanced split): the max flattened-item
    ///   count each lane can hold without exceeding its real rendered width.
    ///   When the combined capacity covers every window, the split starts
    ///   from the balanced (ceil/floor) point and shifts weight from
    ///   whichever lane is over its own capacity into the other lane (which
    ///   the combined check guarantees has room). When capacity is
    ///   insufficient even combined, it falls back to the plain balanced
    ///   split rather than concentrating every window in one lane.
    static func laneGroups(
        for providers: [UsageProviderPresentation],
        hasRightLane: Bool,
        leftCapacity: Int = .max,
        rightCapacity: Int = .max
    ) -> LaneGroups {
        let flattened = flatten(providers)
        guard hasRightLane, flattened.count > 1 else {
            return LaneGroups(left: flattened, right: [])
        }

        let total = flattened.count
        let balancedLeftCount = Int(ceil(Double(total) / 2.0))
        let safeLeftCapacity = max(0, leftCapacity)
        let safeRightCapacity = max(0, rightCapacity)
        let (combinedCapacity, overflowed) = safeLeftCapacity.addingReportingOverflow(safeRightCapacity)
        let hasEnoughCombinedCapacity = overflowed || combinedCapacity >= total

        let leftCount: Int
        if hasEnoughCombinedCapacity {
            var candidate = min(balancedLeftCount, safeLeftCapacity)
            let rightNeeds = total - candidate
            if rightNeeds > safeRightCapacity {
                candidate = min(safeLeftCapacity, candidate + (rightNeeds - safeRightCapacity))
            }
            leftCount = candidate
        } else {
            leftCount = balancedLeftCount
        }

        return LaneGroups(
            left: Array(flattened.prefix(leftCount)),
            right: Array(flattened.dropFirst(leftCount))
        )
    }

    /// The max number of fixed-width items (`itemWidth`, with `itemSpacing`
    /// between adjacent items) that fit within `laneWidth` without exceeding
    /// it. Pure arithmetic, no theme-specific chrome baked in — a caller
    /// whose lane imposes its own fixed padding (e.g. a bezel box) should
    /// subtract that from `laneWidth` before calling this. Shared so every
    /// theme can opt into capacity-aware `laneGroups` with its own per-item
    /// **measurement**, without putting the algorithm on the `IslandTheme`
    /// protocol (see the enum's doc comment on why that's out of bounds).
    static func capacity(laneWidth: CGFloat, itemWidth: CGFloat, itemSpacing: CGFloat) -> Int {
        guard laneWidth > 0, itemWidth > 0 else { return 0 }
        let count = (laneWidth + itemSpacing) / (itemWidth + itemSpacing)
        return max(0, Int(count.rounded(.down)))
    }

    /// The residual overflow fix (Phase 5, column-stack correction; **revised**
    /// Phase 5 "no zero gauges" correction — overlay remediation adversarial
    /// review round 3): given `assignedCount` flattened items handed to a lane
    /// whose own full-size `capacity` (from
    /// `capacity(laneWidth:itemWidth:itemSpacing:)`) is too small to hold them
    /// all, how many should render as full items.
    ///
    /// **Renders `min(assignedCount, capacity)` — never fewer.** The retired
    /// implementation always reserved one slot for an overflow "+N" badge
    /// whenever `assignedCount > capacity`, even when `capacity == 1` — at
    /// FD's real notch-hardware capacity (one gauge per lane, the canonical
    /// 3-window fixture) that reservation left **zero** slots for a real
    /// gauge, rendering a bare "+3" and none of the user's actual numbers
    /// (F7's original deletion bug, re-badged one layer up). **Never render
    /// zero gauges when `capacity >= 1` and at least one window is assigned**
    /// is the invariant this function now guarantees
    /// (`visibleItemCountNeverRendersZeroGaugesWhenCapacityIsAtLeastOne`).
    ///
    /// The overflow badge is no longer this function's concern: a caller that
    /// still has windows left over (`assignedCount - visibleItemCount(...) >
    /// 0`) decides separately, via `overflowBadgeFits(...)` below, whether
    /// there is enough *leftover* width (after `capacity`'s floor-division
    /// already proved `capacity` full items fit) to also draw the badge
    /// without exceeding the lane — rather than this function pre-emptively
    /// sacrificing a real gauge's slot for it.
    ///
    /// Pure arithmetic, reused by every lane that needs overflow-safe
    /// truncation.
    static func visibleItemCount(assignedCount: Int, capacity: Int) -> Int {
        min(max(0, assignedCount), max(0, capacity))
    }

    /// Whether the reserved-slot "+N" badge can be drawn **alongside**
    /// `visibleCount` full-size items without exceeding `laneWidth` (the same
    /// reduced, chrome-subtracted width `capacity(laneWidth:itemWidth:
    /// itemSpacing:)` was computed against). Pure geometry: `capacity`'s floor
    /// division (`(laneWidth + itemSpacing) / (itemWidth + itemSpacing)`)
    /// generally leaves `< itemWidth + itemSpacing` of unused width once
    /// `visibleCount` (== `capacity`, whenever there is real overflow) items
    /// are drawn — this checks whether that leftover sliver is still wide
    /// enough for the badge (deliberately much narrower than a full item, see
    /// `FlightDeckUsageProviderChip.overflowBadgeWidth`'s doc comment) plus
    /// one more `itemSpacing` to separate it from the last item.
    ///
    /// A lane already using every pixel of its measured capacity on full
    /// items (the common case — `capacity`'s floor division happened to land
    /// exactly, or `visibleCount == 0` with no room even for the badge alone)
    /// renders no badge at all rather than exceeding its width — unlike the
    /// retired `visibleItemCount` behaviour, this never sacrifices a real
    /// gauge to guarantee the badge a slot.
    static func overflowBadgeFits(
        laneWidth: CGFloat,
        itemWidth: CGFloat,
        itemSpacing: CGFloat,
        badgeWidth: CGFloat,
        visibleCount: Int
    ) -> Bool {
        guard visibleCount > 0 else { return badgeWidth <= laneWidth }
        let usedWidth = CGFloat(visibleCount) * itemWidth + CGFloat(visibleCount - 1) * itemSpacing
        let remaining = laneWidth - usedWidth
        return remaining >= itemSpacing + badgeWidth
    }

    /// The pure header-band geometry: unchanged math from the original
    /// per-theme `openedHeaderMetrics`, computed once and shared. Entirely
    /// independent of usage-provider content — `laneGroups` consumes this
    /// result's `rightUsageWidth`, not the other way around.
    static func metrics(
        totalWidth: CGFloat,
        usesNotchAwareLayout: Bool,
        targetScreen: NSScreen?,
        openedHeaderButtonsWidth: CGFloat,
        headerControlSpacing: CGFloat,
        controlsLaneArrangement: ControlsLaneArrangement = .rowPacked
    ) -> Metrics {
        let horizontalPadding = horizontalPadding(usesNotchAwareLayout: usesNotchAwareLayout)
        let contentWidth = max(0, totalWidth - (horizontalPadding * 2))
        guard usesNotchAwareLayout, let screen = targetScreen else {
            switch controlsLaneArrangement {
            case .rowPacked:
                let rightLaneWidth = min(contentWidth, openedHeaderButtonsWidth + (contentWidth / 2))
                let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
                return Metrics(
                    leftUsageWidth: leftUsageWidth,
                    centerGapWidth: 0,
                    rightUsageWidth: max(0, rightLaneWidth - openedHeaderButtonsWidth - headerControlSpacing),
                    rightLaneWidth: rightLaneWidth
                )
            case .columnStacked:
                // Stacked: the gauge isn't squeezed by the buttons' width, so
                // it can claim up to half the content width same as the
                // row-packed lane's overall budget; the lane itself is
                // whichever of the two (buttons row, gauge) is wider, not
                // their sum.
                let rightLaneWidth = min(contentWidth, max(openedHeaderButtonsWidth, contentWidth / 2))
                let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
                return Metrics(
                    leftUsageWidth: leftUsageWidth,
                    centerGapWidth: 0,
                    rightUsageWidth: rightLaneWidth,
                    rightLaneWidth: rightLaneWidth
                )
            }
        }

        let panelMinX = screen.frame.midX - (totalWidth / 2)
        let panelMaxX = panelMinX + totalWidth
        let contentMinX = panelMinX + horizontalPadding
        let contentMaxX = panelMaxX - horizontalPadding

        let fallbackNotchHalfWidth = screen.notchSize.width / 2
        let notchLeftEdge = screen.frame.midX - fallbackNotchHalfWidth
        let notchRightEdge = screen.frame.midX + fallbackNotchHalfWidth
        let leftVisibleMaxX = screen.auxiliaryTopLeftArea?.maxX ?? notchLeftEdge
        let rightVisibleMinX = screen.auxiliaryTopRightArea?.minX ?? notchRightEdge

        let rawLeftWidth = max(0, min(contentMaxX, leftVisibleMaxX) - contentMinX)
        let rawRightWidth = max(0, contentMaxX - max(contentMinX, rightVisibleMinX))

        return notchAwareMetrics(
            contentWidth: contentWidth,
            rawLeftWidth: rawLeftWidth,
            rawRightWidth: rawRightWidth,
            openedHeaderButtonsWidth: openedHeaderButtonsWidth,
            headerControlSpacing: headerControlSpacing,
            controlsLaneArrangement: controlsLaneArrangement
        )
    }

    /// The notch-split half of `metrics(...)`'s arithmetic, decoupled from
    /// `NSScreen` lookup so it can be exercised directly with **literal,
    /// measured raw widths** — real notch hardware numbers reported by a
    /// physical capture — rather than requiring a live notched display in
    /// the test process (`NSScreen`'s `auxiliaryTopLeftArea` /
    /// `auxiliaryTopRightArea` aren't mockable, and depending on whichever
    /// physical Mac happens to run the suite would make the assertion
    /// environment-dependent). `metrics(...)` derives `rawLeftWidth` /
    /// `rawRightWidth` from the real screen and calls straight through; this
    /// function is pure arithmetic and owns the actual row-packed vs
    /// column-stacked branching.
    static func notchAwareMetrics(
        contentWidth: CGFloat,
        rawLeftWidth: CGFloat,
        rawRightWidth: CGFloat,
        openedHeaderButtonsWidth: CGFloat,
        headerControlSpacing: CGFloat,
        controlsLaneArrangement: ControlsLaneArrangement
    ) -> Metrics {
        let leftUsageWidth = max(0, rawLeftWidth - notchLaneSafetyInset)
        let rightAvailableWidth = max(0, rawRightWidth - notchLaneSafetyInset)

        // Row-packed: the buttons share the lane's width with the gauge, so
        // their fixed chrome (+ the gap between them) comes out of the
        // available width before any of it can go to the gauge. Column-
        // stacked: the buttons sit in their own row above the gauge, so the
        // gauge is never charged for them — it gets the lane's full
        // available width.
        let proposedRightUsageWidth: CGFloat
        switch controlsLaneArrangement {
        case .rowPacked:
            proposedRightUsageWidth = max(0, rightAvailableWidth - openedHeaderButtonsWidth - headerControlSpacing)
        case .columnStacked:
            proposedRightUsageWidth = rightAvailableWidth
        }
        let rightUsageWidth = proposedRightUsageWidth >= minimumRightUsageLaneWidth
            ? proposedRightUsageWidth
            : 0

        // Row-packed: the lane must hold both, side by side — buttons + gap +
        // gauge. Column-stacked: the lane holds whichever of the two rows is
        // wider — `max`, not the sum — since they stack vertically instead.
        let rightLaneWidth: CGFloat
        switch controlsLaneArrangement {
        case .rowPacked:
            rightLaneWidth = min(
                contentWidth,
                openedHeaderButtonsWidth
                    + (rightUsageWidth > 0 ? headerControlSpacing + rightUsageWidth : 0)
            )
        case .columnStacked:
            rightLaneWidth = min(contentWidth, max(openedHeaderButtonsWidth, rightUsageWidth))
        }
        let centerGapWidth = max(0, contentWidth - leftUsageWidth - rightLaneWidth)

        return Metrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightUsageWidth: rightUsageWidth,
            rightLaneWidth: rightLaneWidth
        )
    }
}

/// The compact usage chips shown in the opened header — one per provider,
/// each collapsing its title from full ("Claude") to short ("Cl") to fit.
///
/// AB-298: extracted from `IslandPanelView`'s `compactUsageSummaryView` /
/// `compactUsageChip` / `usageColor` / `usageHelpText` / `remainingDurationString`
/// (and the dead `headerPill`) into a standalone slot component. Takes its
/// providers by value and reads its colours from `islandTokens` — no `AppModel`
/// reference.
struct IslandUsageSummary: View {
    let providers: [UsageProviderPresentation]
    let lang: LanguageManager
    var now: Date = .now

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        ViewThatFits(in: .horizontal) {
            compactUsageSummaryView(usesShortTitles: false)
            compactUsageSummaryView(usesShortTitles: true)
        }
    }

    private func compactUsageSummaryView(usesShortTitles: Bool) -> some View {
        HStack(spacing: 7) {
            ForEach(providers) { provider in
                compactUsageChip(provider, usesShortTitle: usesShortTitles)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func compactUsageChip(_ provider: UsageProviderPresentation, usesShortTitle: Bool) -> some View {
        let summaryText = UsageSummaryAccessibilityFormatter.summary(
            for: provider,
            usesShortTitle: usesShortTitle,
            asOf: now,
            lang: lang
        )

        return HStack(spacing: 5) {
            Text(usesShortTitle ? provider.shortTitle : provider.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))

            Text(provider.peakWindowLabel)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            Text("\(provider.peakUsagePercentage)%")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(usageColor(for: provider.peakUsedPercentage))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .help(summaryText)
        // AB-244: three adjacent `Text`s (title / window / percentage) would
        // otherwise read as three separate VoiceOver stops — combine into
        // one chip-level label reusing the same summary already built for
        // the `.help()` tooltip.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryText)
    }

    private func headerPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private func usageColor(for percentage: Double) -> Color {
        switch percentage {
        case 90...:
            .red.opacity(0.95)
        case 70..<90:
            .orange.opacity(0.95)
        default:
            .green.opacity(0.95)
        }
    }
}
