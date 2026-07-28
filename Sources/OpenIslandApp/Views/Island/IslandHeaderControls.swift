import AppKit
import SwiftUI
import OpenIslandCore

/// The opened panel's top header row: the usage chips (laid out around the
/// physical notch on notch-aware displays, or flush-left on the top-bar
/// layout) plus the mute / settings / quit buttons.
///
/// AB-298: extracted from `IslandPanelView`'s `openedHeaderContent` /
/// `openedHeaderButtons` / `headerIconButton` / `openedHeaderMetrics` /
/// `splitUsageProviders` / `usageLaneView` / `openedUsageSummary` into a
/// standalone slot component. The usage providers and the layout inputs
/// (`usesNotchAwareLayout`, `targetScreen`, `isSoundMuted`) are lifted to the
/// call site and passed in by value; the three buttons emit through closures —
/// no `AppModel` reference.
struct IslandHeaderControls: View {
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
            headerIconButton(
                systemName: isSoundMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                tint: isSoundMuted ? .orange.opacity(0.92) : .white.opacity(0.62),
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound")
            ) {
                onToggleMute()
            }

            headerIconButton(
                systemName: "gearshape.fill",
                tint: .white.opacity(0.62),
                accessibilityLabel: lang.t("window.settings")
            ) {
                onShowSettings()
            }

            headerIconButton(
                systemName: "power",
                tint: .white.opacity(0.62),
                accessibilityLabel: lang.t("settings.about.quitApp")
            ) {
                onQuit()
            }
        }
    }

    /// Every call site passes an explicit, `lang.t`-routed
    /// `accessibilityLabel` (AB-244) — previously this fell back to the raw
    /// `systemName` (e.g. "gearshape.fill"), which is exactly the kind of
    /// label VoiceOver users shouldn't hear.
    private func headerIconButton(
        systemName: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Self.headerControlButtonSize, height: Self.headerControlButtonSize)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var openedUsageSummary: some View {
        if providers.isEmpty == false {
            IslandUsageSummary(providers: providers, lang: lang)
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
            IslandUsageSummary(providers: providers, lang: lang)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}
