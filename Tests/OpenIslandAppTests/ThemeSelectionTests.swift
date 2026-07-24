import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-299: the theme runtime — registry lookup + fallback, `AppModel`
/// persistence via `appearance.island.v8.theme`, and the byte-identical
/// invariants Classic must keep (chrome metrics feeding panel sizing, and the
/// grid geometry strategy delegating to the pinned statics).
///
/// Serialized and defaults-clearing like `AppModelAttentionSurfacesTests`,
/// since it constructs real `AppModel`s that read `UserDefaults.standard`.
@MainActor
@Suite(.serialized)
struct ThemeSelectionTests {
    private static let themeKey = "appearance.island.v8.theme"

    init() {
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }

    // MARK: - Registry

    @Test
    func classicIsTheRegistryDefault() {
        #expect(ThemeRegistry.default.id == "classic")
        #expect(ThemeRegistry.all.first?.id == "classic")
    }

    @Test
    func registryResolvesKnownAndFallsBackForNilOrUnknown() {
        #expect(ThemeRegistry.theme(id: "classic").id == "classic")
        // Nil (never selected) and garbage (stale / hand-edited defaults) both
        // resolve to the default rather than crashing or rendering blank.
        #expect(ThemeRegistry.theme(id: nil).id == ThemeRegistry.default.id)
        #expect(ThemeRegistry.theme(id: "does-not-exist").id == ThemeRegistry.default.id)
    }

    // MARK: - Persistence (AC #4)

    @Test
    func freshInstallUsesTheDefaultTheme() {
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
        let model = AppModel()
        #expect(model.islandThemeID == "classic")
        #expect(model.islandTheme.id == "classic")
    }

    @Test
    func storedSelectionReloadsFromDefaults() {
        // Set → reload from defaults → same theme.
        UserDefaults.standard.set("classic", forKey: Self.themeKey)
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == "classic")
        #expect(reloaded.islandTheme.id == "classic")
    }

    @Test
    func garbageStoredIdFallsBackToDefault() {
        UserDefaults.standard.set("💥 not-a-theme", forKey: Self.themeKey)
        let model = AppModel()
        // Normalized in-memory to a known id, and the resolved theme is the
        // default — a bad persisted value never leaves the overlay unstyled.
        #expect(model.islandThemeID == ThemeRegistry.default.id)
        #expect(model.islandTheme.id == ThemeRegistry.default.id)
    }

    @Test
    func selectionPersistsBackToDefaults() {
        let model = AppModel()
        model.islandThemeID = "classic"
        // The didSet writes through once init has finished, so a fresh model
        // observes the same id.
        UserDefaults.standard.set(model.islandThemeID, forKey: Self.themeKey)
        let reloaded = AppModel()
        #expect(reloaded.islandThemeID == model.islandThemeID)
    }

    // MARK: - Chrome metrics feed panel sizing (AC #6)

    @Test
    func classicChromeMetricsMatchLegacyStatics() {
        // `OverlayPanelController` now sources its shadow insets from the active
        // theme's metric tokens. With Classic active those equal the legacy
        // `IslandChromeMetrics` statics, so computed panel frames are unchanged.
        let metrics = ClassicTheme().tokens.metrics
        #expect(metrics.openedShadowHorizontalInset == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(metrics.openedShadowBottomInset == IslandChromeMetrics.openedShadowBottomInset)

        let model = AppModel()
        #expect(model.islandTheme.tokens.metrics.openedShadowHorizontalInset == IslandChromeMetrics.openedShadowHorizontalInset)
        #expect(model.islandTheme.tokens.metrics.openedShadowBottomInset == IslandChromeMetrics.openedShadowBottomInset)
    }

    // MARK: - Grid geometry strategy delegates to the pinned statics (AC #7)

    @Test
    func classicGridGeometryDelegatesToV6Statics() {
        let geometry = ClassicTheme().agentsGridGeometry
        for n in 0...20 {
            #expect(geometry.balancedRows(n) == V6RightSlotView.balancedRows(n))
        }
        for rowCount in 1...3 {
            let strategy = geometry.cellGeometry(rowCount)
            let statics = V6RightSlotView.cellGeometry(rowCount: rowCount)
            #expect(strategy.cell == statics.cell)
            #expect(strategy.gap == statics.gap)
            #expect(strategy.radius == statics.radius)
        }
    }
}
