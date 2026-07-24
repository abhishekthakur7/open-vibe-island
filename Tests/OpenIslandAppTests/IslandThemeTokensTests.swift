import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Drift pins for `IslandThemeTokens.classic`.
///
/// The token layer has no consumers yet, so its only guarantee is that
/// `.classic` reproduces today's look exactly. Every token is compared
/// against the live constant it was lifted from — `V6Palette`,
/// `IslandDesignPalette`, `NotchShape`, `IslandChromeMetrics` — so a change to
/// either side fails here.
///
/// The opened-surface shadow and the open/close/pop animations live as
/// file-private constants inside `IslandPanelView.swift` and are therefore not
/// reachable from tests. Those are pinned against literals, with the source
/// site named in a comment.
struct IslandThemeTokensTests {

    // MARK: - Colors

    @Test
    func classicSurfaceColorsMatchV6Palette() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.surfaceInk == V6Palette.ink)
        #expect(colors.paper == V6Palette.paper)
    }

    @Test
    func classicStatusColorsMatchIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.statusRunning == IslandDesignPalette.Status.running)
        #expect(colors.statusCompleted == IslandDesignPalette.Status.completed)
        #expect(colors.statusWaitingForApproval == IslandDesignPalette.Status.waitingForApproval)
        #expect(colors.statusWaitingForAnswer == IslandDesignPalette.Status.waitingForAnswer)
        #expect(colors.statusWaitingAggregate == IslandDesignPalette.Status.waitingAggregate)
        #expect(colors.statusWarning == IslandDesignPalette.Status.warning)
        #expect(colors.statusInterrupted == IslandDesignPalette.Status.interrupted)
        #expect(colors.statusFailed == IslandDesignPalette.Status.failed)
        #expect(colors.statusIdle == IslandDesignPalette.Status.idle)
        #expect(colors.statusInactive == IslandDesignPalette.Status.inactive)
    }

    @Test
    func interruptedReusesTheWarningTone() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.statusInterrupted == colors.statusWarning)
    }

    @Test
    func classicContrastValuesMatchIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.secondaryTextOpacity == IslandDesignPalette.Contrast.secondaryText)
        #expect(colors.tertiaryTextOpacity == IslandDesignPalette.Contrast.tertiaryText)
        #expect(colors.hairlineOpacity == IslandDesignPalette.Contrast.hairline(increaseContrast: false))
        #expect(
            colors.hairlineOpacityIncreasedContrast
                == IslandDesignPalette.Contrast.hairline(increaseContrast: true)
        )
    }

    @Test
    func contrastHelpersMatchIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors

        for base in [0.0, 0.25, 0.48, 0.55, 0.9, 1.0] {
            for increaseContrast in [false, true] {
                #expect(
                    colors.text(base, increaseContrast: increaseContrast)
                        == IslandDesignPalette.Contrast.text(base, increaseContrast: increaseContrast)
                )
            }
        }

        for increaseContrast in [false, true] {
            #expect(
                colors.hairline(increaseContrast: increaseContrast)
                    == IslandDesignPalette.Contrast.hairline(increaseContrast: increaseContrast)
            )
        }
    }

    @Test
    func increasedContrastTextVariantsApplyTheBoost() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.increasedContrastTextBoost == 0.24)
        #expect(colors.secondaryTextOpacityIncreasedContrast == 0.55 + 0.24)
        #expect(colors.tertiaryTextOpacityIncreasedContrast == 0.48 + 0.24)
        // The boost clamps rather than overshooting.
        #expect(colors.text(0.9, increaseContrast: true) == 1)
    }

    @Test
    func statusTintMatchesIslandDesignPaletteForEveryPhase() {
        let colors = IslandThemeTokens.classic.colors

        for phase in SessionPhase.allCases {
            for outcome in SessionOutcome.allCases {
                #expect(
                    colors.statusTint(for: phase, outcome: outcome)
                        == IslandDesignPalette.Status.tint(for: phase, outcome: outcome)
                )
            }
        }
    }

    @Test
    func presenceAwareStatusTintMatchesIslandDesignPalette() {
        let colors = IslandThemeTokens.classic.colors
        let presences: [IslandSessionPresence] = [.running, .active, .inactive]

        for phase in SessionPhase.allCases {
            for presence in presences {
                for outcome in SessionOutcome.allCases {
                    #expect(
                        colors.statusTint(for: phase, presence: presence, outcome: outcome)
                            == IslandDesignPalette.Status.tint(
                                for: phase,
                                presence: presence,
                                outcome: outcome
                            )
                    )
                }
            }
        }
    }

    // MARK: - Metrics

    @Test
    func classicRadiiMatchNotchShape() {
        let metrics = IslandThemeTokens.classic.metrics

        #expect(metrics.openedTopRadius == NotchShape.openedTopRadius)
        #expect(metrics.openedBottomRadius == NotchShape.openedBottomRadius)
        #expect(metrics.openedTopRadius == 22)
        #expect(metrics.openedBottomRadius == 22)
    }

    @Test
    func classicChromeInsetsMatchIslandChromeMetrics() {
        let metrics = IslandThemeTokens.classic.metrics

        #expect(metrics.openedShadowHorizontalInset == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset == IslandChromeMetrics.openedShadowBottomInset)
        #expect(metrics.closedShadowHorizontalInset == IslandChromeMetrics.closedShadowHorizontalInset)
        #expect(metrics.closedShadowBottomInset == IslandChromeMetrics.closedShadowBottomInset)
        #expect(metrics.closedHoverScale == IslandChromeMetrics.closedHoverScale)
    }

    /// Literal pin: the opened-surface shadow is applied inline in
    /// `IslandPanelView.swift` as `.shadow(color: .black.opacity(0.36), radius: 22, y: 12)`.
    /// It has no named constant to compare against, and this ticket may not
    /// modify existing files to introduce one.
    @Test
    func classicSurfaceShadowMatchesIslandPanelViewLiterals() {
        let shadow = IslandThemeTokens.classic.metrics.surfaceShadow

        #expect(shadow.color == Color.black)
        #expect(shadow.opacity == 0.36)
        #expect(shadow.radius == 22)
        #expect(shadow.yOffset == 12)
        #expect(shadow.resolvedColor == Color.black.opacity(0.36))
    }

    // MARK: - Motion

    /// Literal pin: `openAnimation` / `closeAnimation` / `popAnimation` /
    /// `openedSurfaceUnmountDelay` are file-private constants in
    /// `IslandPanelView.swift`, so they are not reachable from tests. The
    /// parameters are pinned here, plus the resolved `Animation` values, which
    /// SwiftUI compares structurally.
    @Test
    func classicMotionMatchesIslandPanelViewLiterals() {
        let motion = IslandThemeTokens.classic.motion

        #expect(motion.openAnimation == .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0))
        #expect(motion.closeAnimation == .smooth(duration: 0.3, extraBounce: 0))
        #expect(motion.popAnimation == .spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0))
        #expect(motion.openedSurfaceUnmountDelay == 0.36)
    }

    @Test
    func animationTokensResolveToTheExpectedSwiftUIAnimations() {
        let motion = IslandThemeTokens.classic.motion

        #expect(
            motion.openAnimation.animation
                == Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
        )
        #expect(motion.closeAnimation.animation == Animation.smooth(duration: 0.3))
        #expect(motion.popAnimation.animation == Animation.spring(response: 0.3, dampingFraction: 0.5))
        #expect(IslandAnimationToken.easeInOut(duration: 0.18).animation == Animation.easeInOut(duration: 0.18))
    }

    // MARK: - Environment

    @Test
    func islandTokensEnvironmentDefaultsToClassic() {
        #expect(EnvironmentValues().islandTokens == IslandThemeTokens.classic)
    }

    @Test
    func islandTokensEnvironmentCanBeOverridden() {
        var values = EnvironmentValues()
        var custom = IslandThemeTokens.classic
        custom.metrics.openedTopRadius = 4
        values.islandTokens = custom

        #expect(values.islandTokens.metrics.openedTopRadius == 4)
        #expect(values.islandTokens != IslandThemeTokens.classic)
    }

    /// Compile-time proof that a view can read the tokens with
    /// `@Environment(\.islandTokens)`.
    private struct TokenReadingProbe: View {
        @Environment(\.islandTokens) private var tokens

        var body: some View {
            tokens.colors.surfaceInk
        }
    }

    @Test
    func aViewCanDeclareAnIslandTokensEnvironmentRead() {
        _ = TokenReadingProbe()
    }
}
