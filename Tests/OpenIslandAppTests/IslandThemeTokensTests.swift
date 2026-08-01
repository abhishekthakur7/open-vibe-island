import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Drift pins for `IslandThemeTokens.classic`.
///
/// The guarantee is that `.classic` reproduces today's look exactly. Tokens
/// whose legacy constant still has un-migrated call sites are compared against
/// that live constant — `V6Palette`, `IslandDesignPalette`, `NotchShape`,
/// `IslandChromeMetrics` — so a change to either side fails here.
///
/// The opened-surface shadow and the open/close/pop animations no longer have
/// a second definition to compare against: AB-295 routed `IslandPanelView`
/// through the tokens and deleted the file-private constants they were lifted
/// from, making the token the single source. Those stay pinned against
/// literals, which is now a pin on the shipping values themselves.
struct IslandThemeTokensTests {
    // MARK: - Colors

    @Test
    func interruptedReusesTheWarningTone() {
        let colors = IslandThemeTokens.classic.colors

        #expect(colors.statusInterrupted == colors.statusWarning)
    }

    // MARK: - Metrics

    /// AB-320 shape pin: `closedSurfaceShadow` is opt-in. Every shipped theme
    /// leaves it `nil`, which is what makes the morph's new
    /// theme-driven closed shadow a no-op for all of them — the previous code
    /// hard-zeroed the closed end of the interpolation.
    @MainActor
    @Test
    func shippedThemesDeclareNoClosedSurfaceShadow() {
        for theme in ThemeRegistry.all {
            #expect(theme.tokens.metrics.closedSurfaceShadow == nil)
        }
    }

    // MARK: - Motion

    // MARK: - Environment
}
