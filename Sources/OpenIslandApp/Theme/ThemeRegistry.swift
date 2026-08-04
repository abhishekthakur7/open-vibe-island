import Foundation

/// The ordered set of island themes the app knows about, and lookup by id.
///
/// The order here is the order the Settings picker offers them; the first entry
/// is the default a fresh install (or an unknown / missing stored id) falls back
/// to. Registering a new theme is a one-line append here plus its `IslandTheme`
/// conformance — nothing else in the overlay needs to change (AB-299).
@MainActor
enum ThemeRegistry {

    /// Every theme, in picker order. Poured Island is first, so it's the
    /// default — the final Poured slice (AB-304, poured 5/5) flipped the default
    /// to it, making it the product's face. Halo is the only other theme,
    /// second in the picker, for anyone who prefers its look.
    static let all: [any IslandTheme] = [
        PouredIslandTheme(),
        HaloTheme(),
    ]

    /// The default theme a fresh install and every unrecoverable lookup use.
    static var `default`: any IslandTheme { all[0] }

    /// The theme with `id`, or the default when `id` is nil / unknown. This is
    /// the single fallback point: a missing or garbage persisted id resolves to
    /// `default` rather than crashing or rendering blank.
    ///
    /// This is also the whole migration story for **retired** themes. The
    /// 2026-08-01 owner ruling deleted Annual and Instrument; anyone whose
    /// `appearance.island.v8.theme` still holds `"annual"` or `"instrument"`
    /// takes exactly the unknown-id path here and lands on Poured Island, and
    /// `AppModel` normalizes the stored value back on load. No versioned
    /// migration step is needed — `ThemeSelectionTests` pins both ids. Classic
    /// and Flight Deck were retired the same way: `"classic"` and
    /// `"flightDeck"` now also resolve to `default` via this same unknown-id
    /// path.
    static func theme(id: String?) -> any IslandTheme {
        guard let id, let match = all.first(where: { $0.id == id }) else {
            return `default`
        }
        return match
    }
}
