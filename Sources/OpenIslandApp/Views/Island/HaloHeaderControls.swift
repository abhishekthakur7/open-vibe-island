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
    private static let headerHorizontalPadding: CGFloat = 18
    private static let headerTopPadding: CGFloat = 2
    private static let notchHeaderHorizontalPadding: CGFloat = 46
    private static let notchLaneSafetyInset: CGFloat = 12
    private static let minimumRightUsageLaneWidth: CGFloat = 58

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
        usesNotchAwareLayout ? Self.notchHeaderHorizontalPadding : Self.headerHorizontalPadding
    }

    var body: some View {
        if usesNotchAwareLayout {
            GeometryReader { geometry in
                let providerGroups = splitUsageProviders(providers)
                let metrics = openedHeaderMetrics(for: geometry.size.width)

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

    @ViewBuilder
    private var openedUsageSummary: some View {
        if providers.isEmpty == false {
            HaloUsageSummary(providers: providers, lang: lang, filamentDiameter: filamentDiameter)
        } else {
            Color.clear
        }
    }

    private func splitUsageProviders(
        _ providers: [UsageProviderPresentation]
    ) -> (left: [UsageProviderPresentation], right: [UsageProviderPresentation]) {
        switch providers.count {
        case 0:
            return ([], [])
        case 1:
            return ([providers[0]], [])
        case 2:
            return ([providers[0]], [providers[1]])
        default:
            let splitIndex = Int(ceil(Double(providers.count) / 2.0))
            return (
                Array(providers.prefix(splitIndex)),
                Array(providers.dropFirst(splitIndex))
            )
        }
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

    private func openedHeaderMetrics(for totalWidth: CGFloat) -> HaloOpenedHeaderMetrics {
        let horizontalPadding = openedHeaderHorizontalPadding
        let contentWidth = max(0, totalWidth - (horizontalPadding * 2))
        guard usesNotchAwareLayout,
              let screen = targetScreen else {
            let rightLaneWidth = min(contentWidth, openedHeaderButtonsWidth + (contentWidth / 2))
            let leftUsageWidth = max(0, contentWidth - rightLaneWidth)
            return HaloOpenedHeaderMetrics(
                leftUsageWidth: leftUsageWidth,
                centerGapWidth: 0,
                rightUsageWidth: max(0, rightLaneWidth - openedHeaderButtonsWidth - Self.headerControlSpacing),
                rightLaneWidth: rightLaneWidth
            )
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

        let leftUsageWidth = max(0, rawLeftWidth - Self.notchLaneSafetyInset)
        let rightAvailableWidth = max(0, rawRightWidth - Self.notchLaneSafetyInset)
        let proposedRightUsageWidth = max(
            0,
            rightAvailableWidth - openedHeaderButtonsWidth - Self.headerControlSpacing
        )
        let rightUsageWidth = proposedRightUsageWidth >= Self.minimumRightUsageLaneWidth
            ? proposedRightUsageWidth
            : 0
        let rightLaneWidth = min(
            contentWidth,
            openedHeaderButtonsWidth
                + (rightUsageWidth > 0 ? Self.headerControlSpacing + rightUsageWidth : 0)
        )
        let centerGapWidth = max(0, contentWidth - leftUsageWidth - rightLaneWidth)

        return HaloOpenedHeaderMetrics(
            leftUsageWidth: leftUsageWidth,
            centerGapWidth: centerGapWidth,
            rightUsageWidth: rightUsageWidth,
            rightLaneWidth: rightLaneWidth
        )
    }
}

private struct HaloOpenedHeaderMetrics {
    let leftUsageWidth: CGFloat
    let centerGapWidth: CGFloat
    let rightUsageWidth: CGFloat
    let rightLaneWidth: CGFloat
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
