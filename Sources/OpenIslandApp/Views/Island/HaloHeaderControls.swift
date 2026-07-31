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
/// light-filament arcs with percent + resets-in inline (`HaloUsageSummary`,
/// fitted per profile), and the mute / settings / quit controls become **26pt
/// circular buttons** filled `white@.06` (`HaloHeaderButton`) — the `.ctl` chip
/// from the mockup. Their behaviors are unchanged, still emitted through the same
/// closures.
struct HaloHeaderControls: View {
    /// 26pt circular control (mockup `.ctl` — `white@.06` fill).
    static let headerControlButtonSize: CGFloat = 26
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

    /// The filament grows on the notch profile (fits the ~38pt notch band) and
    /// stays small on the height-capped top-bar band (see `HaloUsageMetrics`).
    private var filamentDiameter: CGFloat {
        usesNotchAwareLayout ? HaloUsageMetrics.headerFilamentNotch : HaloUsageMetrics.headerFilamentTopBar
    }

    private var openedHeaderButtonsWidth: CGFloat {
        (Self.headerControlButtonSize * 3) + (Self.headerControlSpacing * 2)
    }

    private var openedHeaderHorizontalPadding: CGFloat {
        IslandHeaderLaneLayout.horizontalPadding(usesNotchAwareLayout: usesNotchAwareLayout)
    }

    var body: some View {
        if usesNotchAwareLayout {
            GeometryReader { geometry in
                let metrics = IslandHeaderLaneLayout.metrics(
                    totalWidth: geometry.size.width,
                    usesNotchAwareLayout: usesNotchAwareLayout,
                    targetScreen: targetScreen,
                    openedHeaderButtonsWidth: openedHeaderButtonsWidth,
                    headerControlSpacing: Self.headerControlSpacing
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

                    HStack(spacing: Self.headerControlSpacing) {
                        if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty {
                            usageLaneView(providerGroups.right, alignment: .trailing)
                                .frame(width: metrics.rightUsageWidth, alignment: .trailing)
                        }
                        openedHeaderButtons
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
            HaloHeaderButton(
                systemName: isSoundMuted ? "speaker.slash" : "speaker.wave.2",
                emphasised: isSoundMuted,
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound"),
                size: Self.headerControlButtonSize,
                action: onToggleMute
            )

            HaloHeaderButton(
                systemName: "gearshape",
                emphasised: false,
                accessibilityLabel: lang.t("window.settings"),
                size: Self.headerControlButtonSize,
                action: onShowSettings
            )

            HaloHeaderButton(
                systemName: "power",
                emphasised: false,
                accessibilityLabel: lang.t("settings.about.quitApp"),
                size: Self.headerControlButtonSize,
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
