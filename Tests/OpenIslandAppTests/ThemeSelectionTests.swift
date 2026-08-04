import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-299: the theme runtime — registry lookup + fallback, and `AppModel`
/// persistence via `appearance.island.v8.theme`, including retired-id
/// normalization to the default.
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
        // "classic" is retired (owner ruling): it now takes the unknown-id
        // path and resolves to the default, not to itself.
        #expect(ThemeRegistry.theme(id: "classic").id == ThemeRegistry.default.id)
        #expect(ThemeRegistry.theme(id: "poured").id == "poured")
        // Nil (never selected) and garbage (stale / hand-edited defaults) both
        // resolve to the default rather than crashing or rendering blank.
        #expect(ThemeRegistry.theme(id: nil).id == ThemeRegistry.default.id)
        #expect(ThemeRegistry.theme(id: "does-not-exist").id == ThemeRegistry.default.id)
    }

    /// Retirement migration (owner ruling 2026-08-01, "yes delete annual and
    /// instrument"; extended to Classic and Flight Deck): the four deleted ids
    /// are no longer registered, so a stored selection of any of them takes
    /// the same unknown-id path a garbage value does and resolves to the
    /// default. Pinned by id rather than by symbol, since the theme types are
    /// gone.
    @Test
    func retiredAnnualAndInstrumentIdsResolveToTheDefault() {
        let retired = ["annual", "instrument", "classic", "flightDeck"]
        let ids = ThemeRegistry.all.map(\.id)
        for id in retired {
            #expect(ids.contains(id) == false)
            #expect(ThemeRegistry.theme(id: id).id == ThemeRegistry.default.id)
        }
    }

    /// The same migration through persistence: an install that had Annual,
    /// Instrument, Classic, or Flight Deck selected reloads on Poured Island,
    /// and the stale id is normalized out of `UserDefaults` rather than
    /// lingering.
    @Test
    func persistedRetiredThemeSelectionMigratesToTheDefault() {
        for id in ["annual", "instrument", "classic", "flightDeck"] {
            UserDefaults.standard.set(id, forKey: Self.themeKey)
            let model = AppModel()
            #expect(model.islandThemeID == ThemeRegistry.default.id)
            #expect(model.islandTheme.id == "poured")
        }
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
