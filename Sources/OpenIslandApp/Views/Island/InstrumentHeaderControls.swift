import AppKit
import SwiftUI
import OpenIslandCore

/// Instrument's opened-panel header (AB-308).
///
/// The layout — the notch-split lanes on notched displays, the single flush-left
/// lane on the top-bar / external profile, and the metrics that measure the
/// physical notch out of the way — is shared verbatim with `IslandHeaderControls`
/// so the header keeps its exact geometry across themes. Only the two rendered
/// regions change for the instrument idiom: the usage chips become segmented
/// tick-meters with numeric readouts and CRIT / HIGH / OK tags
/// (`InstrumentUsageSummary`), and the mute / settings / quit buttons become flat
/// squared instrument buttons with hover states (`InstrumentHeaderButton`) —
/// their behaviors are unchanged, still emitted through the same closures.
struct InstrumentHeaderControls: View {
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
                let providerGroups = IslandHeaderLaneLayout.laneGroups(
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
            InstrumentHeaderButton(
                systemName: isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: isSoundMuted ? tokensAmber : nil,
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound"),
                size: Self.headerControlButtonSize,
                action: onToggleMute
            )

            InstrumentHeaderButton(
                systemName: "gearshape.fill",
                tint: nil,
                accessibilityLabel: lang.t("window.settings"),
                size: Self.headerControlButtonSize,
                action: onShowSettings
            )

            InstrumentHeaderButton(
                systemName: "power",
                tint: nil,
                accessibilityLabel: lang.t("settings.about.quitApp"),
                size: Self.headerControlButtonSize,
                action: onQuit
            )
        }
    }

    /// The muted state's amber warns in the instrument palette — the same caution
    /// amber status colour, so the header never spends a colour outside the
    /// theme's status vocabulary.
    private var tokensAmber: Color {
        IslandThemeTokens.instrument.colors.statusWarning
    }

    @ViewBuilder
    private var openedUsageSummary: some View {
        if providers.isEmpty == false {
            InstrumentUsageSummary(providers: providers, lang: lang)
        } else {
            Color.clear
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
            InstrumentUsageSummary(providers: providers, lang: lang)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

}

// MARK: - Instrument header button

/// A flat squared control for the header's mute / settings / quit actions. The
/// behavior is identical to `IslandHeaderControls.headerIconButton` — same
/// closures, same accessibility labels — the only change is the instrument
/// styling: a squared `surfaceInk`-over-paper fill outlined by a hairline rule,
/// and a hover state that lifts the fill and stroke. Colour is spent only on
/// status (the muted amber `tint`); the neutral controls draw in paper. There is
/// no transparency to reduce on this flat panel; the hover lift settles without
/// easing under Reduce Motion.
struct InstrumentHeaderButton: View {
    let systemName: String
    /// A status tint (e.g. muted amber). `nil` draws the neutral paper glyph.
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
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
        // The hover lift settles instantly under Reduce Motion — the state (and
        // its opacity) still changes, it just doesn't ease (AB-304 / AB-308).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
