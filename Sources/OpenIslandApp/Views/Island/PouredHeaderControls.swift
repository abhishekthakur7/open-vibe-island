import AppKit
import SwiftUI
import OpenIslandCore

/// Poured Island's opened-panel header (AB-301).
///
/// The layout — the notch-split lanes on notched displays, the single flush-left
/// lane on the top-bar / external profile, and the metrics that measure the
/// physical notch out of the way — is shared verbatim with `IslandHeaderControls`
/// so the header keeps its exact geometry across themes. Only the two rendered
/// regions change for glass: the usage chips become conic-gradient rings with a
/// numeric readout per provider window (`PouredUsageSummary`), and the mute /
/// settings / quit buttons become frosted glass buttons with hover states
/// (`PouredHeaderButton`) — their behaviors are unchanged, still emitted through
/// the same closures.
struct PouredHeaderControls: View {
    static let headerControlButtonSize: CGFloat = 22
    static let headerControlSpacing: CGFloat = 8
    private static let headerTopPadding: CGFloat = 2
    /// The gap between the single flush-left lane and the control cluster on the
    /// top-bar / external profile (unchanged from the `HStack(spacing: 12)` this
    /// profile always used — named so C4-2's lane bound can subtract it).
    private static let topBarLaneGap: CGFloat = 12

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

    /// The usage ring is fitted to whichever header band this profile draws into:
    /// the ~38pt notch band takes the mockup's 30pt ring, the ~24pt top-bar band
    /// a smaller ring so it can't bleed past the height-capped header (AB-331).
    private var headerRingDiameter: CGFloat {
        usesNotchAwareLayout ? PouredUsageMetrics.headerRingNotch : PouredUsageMetrics.headerRingTopBar
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
                    usageLaneView(providerGroups.left, alignment: .leading, laneWidth: metrics.leftUsageWidth)
                        .frame(width: metrics.leftUsageWidth, alignment: .leading)

                    Color.clear
                        .frame(width: metrics.centerGapWidth)

                    HStack(spacing: Self.headerControlSpacing) {
                        if metrics.rightUsageWidth > 0, !providerGroups.right.isEmpty {
                            usageLaneView(providerGroups.right, alignment: .trailing, laneWidth: metrics.rightUsageWidth)
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
            // C4-2: the single flush-left lane needs the same hard bound. Its
            // width is everything the band has left once both gutters, the
            // control cluster and the gap before it are paid for — computed,
            // not inferred from a `maxWidth: .infinity` the meters were free to
            // ignore.
            GeometryReader { geometry in
                let laneWidth = max(
                    0,
                    geometry.size.width
                        - (openedHeaderHorizontalPadding * 2)
                        - openedHeaderButtonsWidth
                        - Self.topBarLaneGap
                )

                HStack(spacing: Self.topBarLaneGap) {
                    usageLaneView(providers, alignment: .leading, laneWidth: laneWidth)
                        .frame(width: laneWidth, alignment: .leading)

                    openedHeaderButtons
                }
                .padding(.leading, openedHeaderHorizontalPadding)
                .padding(.trailing, openedHeaderHorizontalPadding)
                .padding(.top, Self.headerTopPadding)
            }
        }
    }

    private var openedHeaderButtons: some View {
        HStack(spacing: Self.headerControlSpacing) {
            PouredHeaderButton(
                systemName: isSoundMuted ? "speaker.slash" : "speaker.wave.2",
                tint: isSoundMuted ? .orange.opacity(0.92) : .white.opacity(0.7),
                accessibilityLabel: lang.t(isSoundMuted ? "a11y.header.unmuteSound" : "a11y.header.muteSound"),
                size: Self.headerControlButtonSize,
                action: onToggleMute
            )

            PouredHeaderButton(
                systemName: "gearshape",
                tint: .white.opacity(0.7),
                accessibilityLabel: lang.t("window.settings"),
                size: Self.headerControlButtonSize,
                action: onShowSettings
            )

            PouredHeaderButton(
                systemName: "xmark",
                tint: .white.opacity(0.7),
                accessibilityLabel: lang.t("settings.about.quitApp"),
                size: Self.headerControlButtonSize,
                action: onQuit
            )
        }
    }

    /// C4-2 (PI-X-001/I1-I2 · review round 1): the lane is **bounded**.
    ///
    /// Two things happen here that didn't before. `PouredUsageSummary` is told
    /// the lane's real width, so `PouredHeaderMeterLane` can elide the
    /// lowest-severity meter rather than let it overrun (the worst band always
    /// survives — see that type for the full rule). And the lane `.clipped()`s
    /// at its own frame, so even a meter the fitter chose to keep can only ever
    /// truncate *inside* the lane instead of drawing under the mute / settings /
    /// close cluster, which is what the 620pt notch capture showed. Elision is
    /// visual only: every meter keeps its VoiceOver stop.
    ///
    /// Distribution across the wings is untouched (R15) — that is
    /// `IslandHeaderLaneLayout.laneGroups`', not this function's, call.
    @ViewBuilder
    private func usageLaneView(
        _ providers: [UsageProviderPresentation],
        alignment: Alignment,
        laneWidth: CGFloat
    ) -> some View {
        if providers.isEmpty {
            Color.clear
                .frame(maxWidth: .infinity)
        } else {
            PouredUsageSummary(
                providers: providers,
                lang: lang,
                ringDiameter: headerRingDiameter,
                laneWidth: laneWidth
            )
            .frame(maxWidth: .infinity, alignment: alignment)
            .clipped()
        }
    }

}

// MARK: - Glass header button

/// A frosted circular control for the header's mute / settings / quit actions.
/// The behavior is identical to `IslandHeaderControls.headerIconButton`; the
/// only additions are the glass fill (a touch brighter with a specular ring),
/// and a hover state that lifts the fill and stroke so the control reads as
/// interactive glass. Under Reduce Transparency the fill goes flatter/opaquer so
/// the glyph stays legible.
struct PouredHeaderButton: View {
    let systemName: String
    let tint: Color
    let accessibilityLabel: String
    var size: CGFloat = 22
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fillOpacity: Double {
        if reduceTransparency {
            return hovering ? 0.22 : 0.14
        }
        return hovering ? 0.17 : 0.09
    }

    private var strokeOpacity: Double {
        hovering ? 0.28 : 0.12
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(.white.opacity(fillOpacity), in: Circle())
                .overlay(
                    Circle().strokeBorder(.white.opacity(strokeOpacity), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onHover { hovering = $0 }
        // The hover lift settles instantly under Reduce Motion — the state
        // (and its opacity) still changes, it just doesn't ease (AB-304).
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
    }
}
