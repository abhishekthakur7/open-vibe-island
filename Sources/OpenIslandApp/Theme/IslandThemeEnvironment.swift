import SwiftUI

private struct IslandThemeTokensKey: EnvironmentKey {
    static let defaultValue: IslandThemeTokens = .classic
}

extension EnvironmentValues {
    /// Styling tokens for the island overlay.
    ///
    /// Defaults to `.classic` — the look Open Island ships today — so a view
    /// that reads this without an explicit injection renders unchanged.
    var islandTokens: IslandThemeTokens {
        get { self[IslandThemeTokensKey.self] }
        set { self[IslandThemeTokensKey.self] = newValue }
    }
}
