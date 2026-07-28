import AppKit
import SwiftUI
import OpenIslandCore

/// Flight Deck's opened-panel header (AB-312).
///
/// The single flush-left lane on the top-bar / external profile, and the
/// underlying `IslandHeaderLaneLayout.metrics`/`laneGroups` machinery, are
/// shared with `IslandHeaderControls` (and mirror `InstrumentHeaderControls`).
/// The **notch-split lane geometry is no longer byte-identical** to the other
/// five themes as of overlay remediation Phase 5: FD's board
/// (`02-flight-deck.html:282`) stacks the right lane's control row above its
/// gauge rather than beside it (`ControlsLaneArrangement.columnStacked`), and
/// FD alone claims a taller opened-header band (`IslandTheme
/// .openedHeaderHeight`, 96pt) than the closed pill's own height. The
/// rendered idiom differs too: the usage chips become tape gauges with
/// numeric readouts and CRIT / CAUT / NOM placards (`FlightDeckUsageSummary`),
/// and the mute / settings / quit buttons become flat squared *panel
/// switches* with hover states (`FlightDeckHeaderButton`) — their behaviors
/// are unchanged, still emitted through the same closures.
struct FlightDeckHeaderControls: View {
    static let headerControlButtonSize: CGFloat = 22
    static let headerControlSpacing: CGFloat = 8
    private static let headerTopPadding: CGFloat = 2

    let providers: [UsageProviderPresentation]
    let usesNotchAwareLayout: Bool
    let targetScreen: NSScreen?
    let isSoundMuted: Bool
    let lang: LanguageManager
    let onToggleMute: () -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.islandTokens) private var tokens

    private var openedHeaderButtonsWidth: CGFloat {
        (Self.headerControlButtonSize * 3) + (Self.headerControlSpacing * 2)
    }

    private var openedHeaderHorizontalPadding: CGFloat {
        IslandHeaderLaneLayout.horizontalPadding(usesNotchAwareLayout: usesNotchAwareLayout)
    }

    /// Overlay remediation Phase 5, Defect 1: how many flattened windows a
    /// lane of `laneWidth` can actually render — FD's own per-item
    /// **measurement** (the compact gauge tier, since capacity feeds
    /// `laneGroups` *before* `ViewThatFits` picks a tier, and the compact
    /// tier is the more permissive one to plan against) minus its chip's own
    /// fixed chrome, passed to the shared, theme-agnostic
    /// `IslandHeaderLaneLayout.capacity`.
    private func laneCapacity(for laneWidth: CGFloat) -> Int {
        IslandHeaderLaneLayout.capacity(
            laneWidth: reducedLaneWidth(for: laneWidth),
            itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
            itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing
        )
    }

    /// `laneWidth` minus the chip's own fixed horizontal chrome
    /// (`FlightDeckUsageProviderChip.horizontalPadding`, both sides) — the
    /// width actually available to gauges/badge inside the chip. Shared by
    /// `laneCapacity(for:)` and the overflow-badge fit check so the two can't
    /// drift onto different reduced widths for the same lane.
    private func reducedLaneWidth(for laneWidth: CGFloat) -> CGFloat {
        max(0, laneWidth - FlightDeckUsageProviderChip.horizontalPadding * 2)
    }

    var body: some View {
        if usesNotchAwareLayout {
            GeometryReader { geometry in
                // Overlay remediation Phase 5 ("opened-header band growth"
                // correction): `.columnStacked` mirrors FD's own board
                // (`02-flight-deck.html:282`, `.phead .lane{flex-direction:
                // column}`), which stacks the button row above the gauge
                // rather than beside it — see the right-lane `VStack` below.
                // This was previously left at the `.rowPacked` default
                // because the fixed opened-header band (~34-38pt on real
                // notch hardware) couldn't fit a stacked 22pt button row +
                // spacing above FD's own gauge chip without reintroducing
                // F8's vertical overflow. `IslandTheme.openedHeaderHeight`
                // (`IslandTheme.swift`) resolves that budget — Flight Deck
                // now claims a 96pt band independently of the closed pill's
                // height — so `.columnStacked` is safe to wire in here.
                let metrics = IslandHeaderLaneLayout.metrics(
                    totalWidth: geometry.size.width,
                    usesNotchAwareLayout: usesNotchAwareLayout,
                    targetScreen: targetScreen,
                    openedHeaderButtonsWidth: openedHeaderButtonsWidth,
                    headerControlSpacing: Self.headerControlSpacing,
                    controlsLaneArrangement: .columnStacked
                )
                let leftCapacity = laneCapacity(for: metrics.leftUsageWidth)
                let rightCapacity = laneCapacity(for: metrics.rightUsageWidth)
                let providerGroups = IslandHeaderLaneLayout.laneGroups(
                    for: providers,
                    hasRightLane: metrics.rightUsageWidth > 0,
                    leftCapacity: leftCapacity,
                    rightCapacity: rightCapacity
                )

                HStack(spacing: 0) {
                    usageLaneView(providerGroups.left, alignment: .leading, capacity: leftCapacity, laneWidth: metrics.leftUsageWidth)
                        .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    // Column-stacked (mockup `.phead .lane.r`): the button
                    // row sits above the gauge, not beside it — the two never
                    // share the lane's width, only its full-width budget.
                    VStack(alignment: .trailing, spacing: Self.headerControlSpacing) {
                        openedHeaderButtons
                        if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty {
                            usageLaneView(providerGroups.right, alignment: .trailing, capacity: rightCapacity, laneWidth: metrics.rightUsageWidth)
                        }
                    }
                    .frame(width: metrics.rightLaneWidth, alignment: .trailing)
                }
                .padding(.horizontal, openedHeaderHorizontalPadding)
                .padding(.top, Self.headerTopPadding)
            }
        } else {
            HStack(spacing: 12) {
                openedUsageSummary
                    .frame(maxWidth: .infinity, alignment: .leading)

                openedHeaderButtons
            }
            .padding(.leading, openedHeaderHorizontalPadding)
            .padding(.trailing, openedHeaderHorizontalPadding)
            .padding(.top, Self.headerTopPadding)
        }
    }

    private var openedHeaderButtons: some View {
        HStack(spacing: Self.headerControlSpacing) {
            FlightDeckHeaderButton(
                systemName: isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: isSoundMuted ? tokens.colors.statusWarning : nil,
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound"),
                size: Self.headerControlButtonSize,
                action: onToggleMute
            )

            FlightDeckHeaderButton(
                systemName: "gearshape.fill",
                tint: nil,
                accessibilityLabel: lang.t("window.settings"),
                size: Self.headerControlButtonSize,
                action: onShowSettings
            )

            FlightDeckHeaderButton(
                systemName: "power",
                tint: nil,
                accessibilityLabel: lang.t("settings.about.quitApp"),
                size: Self.headerControlButtonSize,
                action: onQuit
            )
        }
    }

    @ViewBuilder
    private var openedUsageSummary: some View {
        if providers.isEmpty == false {
            FlightDeckUsageSummary(providers: providers, lang: lang)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func usageLaneView(
        _ providers: [UsageProviderPresentation],
        alignment: Alignment,
        capacity: Int,
        laneWidth: CGFloat
    ) -> some View {
        if providers.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
        } else {
            // Phase 5, Defect 1: one bezeled box per lane, not one per
            // flattened window — see `FlightDeckUsageSummary
            // .groupsAllProvidersIntoOneChip`. `capacity` is the same
            // measurement `laneGroups` used to split `providers` between
            // lanes above — passed straight through so the chip can render
            // an explicit "+N" affordance instead of overflowing when
            // `laneGroups`'s balanced-split fallback still hands this lane
            // more windows than `capacity` (the residual: 3 windows, 2 lanes,
            // 1 real gauge of capacity each — see `FlightDeckUsageProviderChip
            // .maxVisibleWindows`).
            //
            // `providers` here is already flattened to one window each
            // (`IslandHeaderLaneLayout.laneGroups`'s output), so its count
            // *is* the assigned window count — no re-flattening needed.
            let visibleCount = IslandHeaderLaneLayout.visibleItemCount(
                assignedCount: providers.count,
                capacity: capacity
            )
            // "No zero gauges" correction (Phase 5, adversarial review round
            // 3): the badge only draws when it fits *alongside*
            // `visibleCount` full gauges — never by displacing one of them.
            // See `IslandHeaderLaneLayout.overflowBadgeFits`'s doc comment.
            let allowsOverflowBadge = IslandHeaderLaneLayout.overflowBadgeFits(
                laneWidth: reducedLaneWidth(for: laneWidth),
                itemWidth: FlightDeckUsageWindowGauge.compactGaugeWidth,
                itemSpacing: FlightDeckUsageProviderChip.interGaugeSpacing,
                badgeWidth: FlightDeckUsageProviderChip.overflowBadgeWidth,
                visibleCount: visibleCount
            )
            FlightDeckUsageSummary(
                providers: providers,
                lang: lang,
                groupsAllProvidersIntoOneChip: true,
                maxVisibleWindows: capacity,
                allowsOverflowBadge: allowsOverflowBadge
            )
            .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

}

// MARK: - Flight Deck header button (panel switch)

/// A flat squared *panel switch* for the header's mute / settings / quit actions.
/// The behavior is identical to `IslandHeaderControls.headerIconButton` — same
/// closures, same accessibility labels — the only change is the avionics styling:
/// a squared `surfaceInk`-over-paper fill outlined by a hairline bezel with a
/// thin lit top-edge highlight so the control reads as a seated cockpit switch,
/// and a hover state that lifts the fill, stroke and highlight. Colour is spent
/// only on status (the muted caution `tint`); the neutral controls draw in paper.
/// There is no transparency to reduce on this flat panel; the hover lift settles
/// without easing under Reduce Motion.
struct FlightDeckHeaderButton: View {
    let systemName: String
    /// A status tint (e.g. muted caution amber). `nil` draws the neutral paper
    /// glyph.
    let tint: Color?
    let accessibilityLabel: String
    var size: CGFloat = 22
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var glyphColor: Color {
        tint ?? tokens.colors.paper.opacity(hovering ? 0.92 : 0.66)
    }

    private var fillOpacity: Double {
        hovering ? 0.1 : 0.04
    }

    private var strokeOpacity: Double {
        let base = tokens.colors.hairline(increaseContrast: increasesContrast)
        return hovering ? min(1, base + 0.14) : base
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tokens.colors.paper.opacity(fillOpacity))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(tokens.colors.paper.opacity(strokeOpacity), lineWidth: 1)
                        )
                        // The seated-switch top-edge highlight — a thin lit rule
                        // that reads as a bevelled cockpit toggle. Lifts on hover.
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(tokens.colors.paper.opacity(hovering ? 0.22 : 0.1))
                                .frame(height: 1)
                                .padding(.horizontal, 3)
                        }
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
        // The hover lift settles instantly under Reduce Motion — the state (and
        // its opacity) still changes, it just doesn't ease (AB-311 / AB-312).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
