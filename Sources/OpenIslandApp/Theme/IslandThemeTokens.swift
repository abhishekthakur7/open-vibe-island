import SwiftUI

/// The full set of styling tokens an island theme provides.
///
/// This is the foundation of the theme system: overlay styling that is today
/// hardcoded across `V6Palette`, `IslandDesignPalette`, `NotchShape`,
/// `IslandChromeMetrics` and `IslandPanelView` gets expressed once here, and
/// views read it from the environment via `@Environment(\.islandTokens)`.
///
/// Deliberately split three ways so a theme can override one axis without
/// restating the others. Typography is intentionally absent: themes swap
/// entire slot views, so per-view fonts belong to each theme's own views
/// rather than to a shared token table.
///
/// Not `Codable` — `Color` has no stable `Codable` conformance and
/// `IslandAnimationToken` is a rendering concern, not persisted state. Themes
/// are selected by identifier; the tokens themselves are code, not data.
struct IslandThemeTokens: Equatable, Sendable {
    var colors: IslandColorTokens
    var metrics: IslandMetricsTokens
    var motion: IslandMotionTokens
    var material: IslandMaterialTokens
}

// MARK: - Poured Island

extension IslandThemeTokens {
    /// Poured Island (liquid glass): cool frosted identity, filleted opened
    /// shape, deep soft shadow, lighter vibrancy tint with a specular top edge,
    /// and a softer "poured" open/close spring.
    static let poured = IslandThemeTokens(
        colors: .poured,
        metrics: .poured,
        motion: .poured,
        material: .poured
    )
}
