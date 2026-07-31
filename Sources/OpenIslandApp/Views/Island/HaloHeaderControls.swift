import AppKit
import SwiftUI
import OpenIslandCore

/// Halo's opened-panel header (AB-343 · `SPEC-halo` §5C · mockup §C).
///
/// The layout — the notch-split lanes on notched displays, the single flush-left
/// lane on the top-bar / external profile, and the metrics that measure the
/// physical notch out of the way — is shared **verbatim** with
/// `AnnualHeaderControls` / `IslandHeaderControls` so the header keeps its exact
/// geometry across themes (mockup `.ngap 96pt` reserved under the notch). Only the
/// two rendered regions change for the Halo idiom: the usage becomes thin
/// light-filament arcs with a percent readout (`HaloUsageSummary`, fitted per
/// profile), and the mute / settings / quit controls become **26pt circular
/// buttons** filled `white@.06` (`HaloHeaderButton`) — the `.ctl` chip from the
/// mockup. Their behaviors are unchanged, still emitted through the same closures.
///
/// **Parity V9 — the notch profile's own geometry.** The board budgets a 96pt
/// `.ngap` for the notch; real 14"/16" hardware cuts out ~185pt, and the shared
/// lane math left the right-of-notch lane 17.5pt — no gauge ever rendered there
/// (parked through V1…V8). Owner-sanctioned fix, entirely theme-scoped: this view
/// hands `IslandHeaderLaneLayout.metrics(...)` its own `trailingPadding`,
/// `notchLaneSafetyInset` and `minimumRightLaneWidth`, and fits its controls per
/// profile the way the filament already was. The other five themes call the same
/// shared function with the same shared defaults and are unaffected.
struct HaloHeaderControls: View {
    /// 26pt circular control (mockup `.ctl` — `white@.06` fill).
    static let headerControlButtonSize: CGFloat = 26
    /// The notch profile's control (parity V9, owner-sanctioned). The board
    /// reserves a 96pt `.ngap` for its notch; this MacBook's cutout is **185pt**,
    /// eating ~89pt the board never budgeted, and the three controls stand in
    /// exactly the strip that survives right of it. Shrinking them 26 → 22 buys
    /// the filament 12pt of that strip — the difference between a lane that draws
    /// a gauge and one that draws nothing. 22pt is still a comfortable hit target
    /// (Instrument ships 22pt controls) and the 4pt delta is invisible next to a
    /// missing gauge. The top-bar / external profile has no notch to pay for and
    /// keeps the board's 26.
    static let notchHeaderControlButtonSize: CGFloat = 22
    /// The board's `.p-head .lane.r{gap:8px}`.
    static let headerControlSpacing: CGFloat = 8
    /// …tightened to 6 on the notch profile only (parity V9): 3 gaps × 2pt is
    /// another 6pt for the filament, at a spacing the 22pt controls still read as
    /// separate chips.
    static let notchHeaderControlSpacing: CGFloat = 6
    /// G-14 — the mockup's `.p-head{padding:11px 16px 10px}` breathes below the
    /// notch; the shared 2pt default made the lane cling to the notch edge.
    private static let headerTopPadding: CGFloat = 10
    /// The notch profile's trailing gutter (parity V9), and the one number here
    /// that is **not** what it looks like on screen.
    ///
    /// `NotchShape` draws the opened silhouette's side walls at `rect.minX +
    /// topCornerRadius` / `rect.maxX − topCornerRadius` (`NotchShape.swift`) —
    /// the header lays out in the full 540pt frame, but only the middle
    /// `540 − 2 × openedTopRadius` of it is ever painted. Measured on this
    /// MacBook: frame 486…1026pt, drawn silhouette 506…1006pt. So the shared 46pt
    /// notch padding renders as a **26pt** visible gutter, and this 36 renders as
    /// the board's own `.p-head{padding:11px 16px 10px}` — 16pt. Anything below
    /// ~30 here starts clipping the quit control against the wall.
    ///
    /// The leading gutter keeps the shared 46: it is where
    /// `IslandPanelView.openedGlyphLeadingInset`'s traveling glyph lands (26 +
    /// its 24pt box = 50), and shrinking it would drop the glyph onto the left
    /// filament. Nothing lands on the trailing side, so its 10pt of slack is free
    /// and all of it goes to the starved right-of-notch lane.
    static let notchHeaderTrailingPadding: CGFloat = 36
    /// Halo's own notch clearance, replacing the shared 12 for this theme only.
    /// The right lane's filament sits this far from the physical cutout's edge —
    /// 6pt still reads as clearance (the arc carries its own ~1.4pt ring inset on
    /// top), and the 6pt saved is what lifts the lane over its floor.
    static let notchLaneSafetyInset: CGFloat = 6
    /// Halo's own right-lane floor, replacing the shared 58 for this theme only
    /// (`IslandHeaderLaneLayout.minimumRightUsageLaneWidth` — see its doc comment
    /// for why the shared constant itself must not move). 45 is the width of the
    /// narrowest rung `HaloUsageLaneRung` still draws a *readout* in (a 15pt arc +
    /// 6pt gap + a two-digit percent ≈ 46.6, less a rounding hair); below it the
    /// window is better served by the §I meter card than by a squeezed arc.
    static let minimumRightFilamentLaneWidth: CGFloat = 45

    let providers: [UsageProviderPresentation]
    let usesNotchAwareLayout: Bool
    let targetScreen: NSScreen?
    let isSoundMuted: Bool
    let lang: LanguageManager
    let onToggleMute: () -> Void
    let onShowSettings: () -> Void
    let onQuit: () -> Void

    @Environment(\.islandTokens) private var tokens

    /// The filament grows on the notch profile (fits the ~38pt notch band) and
    /// stays small on the height-capped top-bar band (see `HaloUsageMetrics`).
    private var filamentDiameter: CGFloat {
        usesNotchAwareLayout ? HaloUsageMetrics.headerFilamentNotch : HaloUsageMetrics.headerFilamentTopBar
    }

    /// The control size fitted per profile, exactly as the filament is (26 on the
    /// top bar, 22 where the physical notch takes the lane).
    private var controlButtonSize: CGFloat {
        usesNotchAwareLayout ? Self.notchHeaderControlButtonSize : Self.headerControlButtonSize
    }

    /// Fitted per profile with the control size (see `notchHeaderControlSpacing`).
    private var controlSpacing: CGFloat {
        usesNotchAwareLayout ? Self.notchHeaderControlSpacing : Self.headerControlSpacing
    }

    private var openedHeaderButtonsWidth: CGFloat {
        (controlButtonSize * 3) + (controlSpacing * 2)
    }

    private var openedHeaderHorizontalPadding: CGFloat {
        IslandHeaderLaneLayout.horizontalPadding(usesNotchAwareLayout: usesNotchAwareLayout)
    }

    /// Notch profile only: the board's 16pt trailing gutter (the top-bar profile
    /// keeps the shared symmetric padding).
    private var openedHeaderTrailingPadding: CGFloat {
        usesNotchAwareLayout ? Self.notchHeaderTrailingPadding : openedHeaderHorizontalPadding
    }

    var body: some View {
        if usesNotchAwareLayout {
            GeometryReader { geometry in
                let metrics = IslandHeaderLaneLayout.metrics(
                    totalWidth: geometry.size.width,
                    usesNotchAwareLayout: usesNotchAwareLayout,
                    targetScreen: targetScreen,
                    openedHeaderButtonsWidth: openedHeaderButtonsWidth,
                    headerControlSpacing: controlSpacing,
                    // V9 — the Halo-scoped knobs that finally admit a
                    // right-of-notch filament on real notch hardware. Measured
                    // here: rawRight 141.5 − 6 (inset) − 78 (3×22 + 2×6) − 6
                    // (lane gap) = 51.5pt, cleared against the 45 floor and spent
                    // on the richest `HaloUsageLaneRung` that fits.
                    trailingPadding: Self.notchHeaderTrailingPadding,
                    notchLaneSafetyInset: Self.notchLaneSafetyInset,
                    minimumRightLaneWidth: Self.minimumRightFilamentLaneWidth
                )
                // G-29 — the mockup's `.p-head` carries **one** filament per lane
                // (`Claude 5h` left of the notch gap, `Claude 7d` right of it).
                // Overflow windows (3rd+) are not crowded into the left lane; they
                // live in the §I meter card below the list.
                let providerGroups = Self.laneFilaments(
                    for: providers,
                    hasRightLane: metrics.rightUsageWidth > 0
                )

                HStack(spacing: 0) {
                    usageLaneView(providerGroups.left, alignment: .leading)
                        .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    HStack(spacing: controlSpacing) {
                        if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty {
                            usageLaneView(providerGroups.right, alignment: .trailing)
                                .frame(width: metrics.rightUsageWidth, alignment: .trailing)
                        }
                        openedHeaderButtons
                    }
                    .frame(width: metrics.rightLaneWidth, alignment: .trailing)
                }
                .padding(.leading, openedHeaderHorizontalPadding)
                .padding(.trailing, openedHeaderTrailingPadding)
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
        HStack(spacing: controlSpacing) {
            HaloHeaderButton(
                systemName: isSoundMuted ? "speaker.slash" : "speaker.wave.2",
                emphasised: isSoundMuted,
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound"),
                size: controlButtonSize,
                action: onToggleMute
            )

            HaloHeaderButton(
                systemName: "gearshape",
                emphasised: false,
                accessibilityLabel: lang.t("window.settings"),
                size: controlButtonSize,
                action: onShowSettings
            )

            HaloHeaderButton(
                systemName: "power",
                emphasised: false,
                accessibilityLabel: lang.t("settings.about.quitApp"),
                size: controlButtonSize,
                action: onQuit
            )
        }
    }

    /// The single-lane (top-bar / external) header carries the same **two**
    /// filaments the notch profile splits across its lanes (G-29); the rest go to
    /// the §I meter card.
    @ViewBuilder
    private var openedUsageSummary: some View {
        let lanes = Self.laneFilaments(for: providers, hasRightLane: true)
        let headerProviders = lanes.left + lanes.right
        if headerProviders.isEmpty == false {
            HaloUsageSummary(providers: headerProviders, lang: lang, filamentDiameter: filamentDiameter)
        } else {
            Color.clear
        }
    }

    /// Halo's **one-filament-per-lane** header split (mockup §C `.p-head`): the
    /// first flattened `(provider, window)` sits in the left lane, the second in
    /// the right lane when the notch geometry leaves one, and every further window
    /// is dropped from the header entirely — it is carried by the §I meter card
    /// (`HaloUsageMeterCard`) in the panel body instead. Unlike the shared
    /// balanced `IslandHeaderLaneLayout.laneGroups`, nothing overflows back into a
    /// lane: the header is a two-token glance, not a full readout.
    static func laneFilaments(
        for providers: [UsageProviderPresentation],
        hasRightLane: Bool
    ) -> IslandHeaderLaneLayout.LaneGroups {
        let flattened = IslandHeaderLaneLayout.flatten(providers)
        guard hasRightLane else {
            return IslandHeaderLaneLayout.LaneGroups(left: Array(flattened.prefix(1)), right: [])
        }
        return IslandHeaderLaneLayout.LaneGroups(
            left: Array(flattened.prefix(1)),
            right: Array(flattened.dropFirst(1).prefix(1))
        )
    }

    @ViewBuilder
    private func usageLaneView(
        _ providers: [UsageProviderPresentation],
        alignment: Alignment
    ) -> some View {
        if providers.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
        } else {
            HaloUsageSummary(providers: providers, lang: lang, filamentDiameter: filamentDiameter)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

}

// MARK: - Halo header button (26pt circular control)

/// A 26pt circular control for the header's mute / settings / quit actions
/// (mockup `.ctl`). The behavior is identical to `AnnualHeaderButton` /
/// `IslandHeaderControls.headerIconButton` — same closures, same accessibility
/// labels — the only change is the Halo styling: a `white@.06` fill circle that
/// lifts to `white@.14` on hover, with the SF glyph in the secondary text ramp
/// rising to primary on hover. The muted state carries by the slashed glyph plus a
/// touch more fill, without spending an edge-light accent (agent identity stays
/// achromatic in Halo). The hover lift settles instantly under Reduce Motion.
struct HaloHeaderButton: View {
    let systemName: String
    /// The muted state — a touch brighter fill so the slashed glyph reads as an
    /// active toggle, without spending colour.
    let emphasised: Bool
    let accessibilityLabel: String
    var size: CGFloat = 26
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    private var fillOpacity: Double {
        let base = emphasised ? 0.10 : 0.06
        return hovering ? 0.14 : base
    }

    private var glyphOpacity: Double {
        let base = emphasised ? 0.85 : tokens.colors.secondaryTextOpacity
        let resolved = hovering ? min(1, base + 0.2) : base
        return tokens.colors.text(resolved, increaseContrast: increasesContrast)
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(tokens.colors.paper.opacity(glyphOpacity))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(fillOpacity)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
        // The hover lift settles instantly under Reduce Motion — the state (and
        // its opacity) still changes, it just doesn't ease (AB-343).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
}
