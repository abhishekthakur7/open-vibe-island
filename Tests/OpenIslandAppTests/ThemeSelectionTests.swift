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
    func pouredIsTheRegistryDefault() {
        // AB-304 (poured 5/5) flipped the default: Poured Island is now the
        // product's face, so it's first in the picker and the fresh-install
        // fallback.
        #expect(ThemeRegistry.default.id == "poured")
        #expect(ThemeRegistry.all.first?.id == "poured")
    }

    @Test
    func registryResolvesKnownAndFallsBackForNilOrUnknown() {
        #expect(ThemeRegistry.theme(id: "classic").id == "classic")
        #expect(ThemeRegistry.theme(id: "poured").id == "poured")
        // Nil (never selected) and garbage (stale / hand-edited defaults) both
        // resolve to the default rather than crashing or rendering blank.
        #expect(ThemeRegistry.theme(id: nil).id == ThemeRegistry.default.id)
        #expect(ThemeRegistry.theme(id: "does-not-exist").id == ThemeRegistry.default.id)
    }

    // MARK: - Persistence (AC #4)

    @Test
    func freshInstallUsesTheDefaultTheme() {
        // No stored value (fresh install) → the flipped default, Poured Island.
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
        let model = AppModel()
        #expect(model.islandThemeID == "poured")
        #expect(model.islandTheme.id == "poured")
        #expect(model.islandThemeID == ThemeRegistry.default.id)
    }

    @Test
    func explicitClassicSelectionIsPreservedOverTheNewDefault() {
        // A user who explicitly chose Classic before the flip keeps Classic —
        // the new default only applies when nothing is stored.
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

    // MARK: - Picker selection round-trip (AB-306)

    @Test
    func pickingEachThemeRoundTripsThroughDefaults() {
        // Mirrors the Appearance picker card action: `model.islandThemeID = id`
        // for every registered theme, then a fresh AppModel reloaded from
        // defaults must resolve the same theme active.
        for theme in ThemeRegistry.all {
            let model = AppModel()
            model.islandThemeID = theme.id
            let reloaded = AppModel()
            #expect(reloaded.islandThemeID == theme.id)
            #expect(reloaded.islandTheme.id == theme.id)
        }
    }
}
