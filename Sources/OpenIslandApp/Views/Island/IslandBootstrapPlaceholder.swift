import SwiftUI
import OpenIslandCore

/// Shown while the app is still probing terminals for session ownership on a
/// cold launch, before it knows whether there are any live sessions to list.
///
/// AB-298: extracted from `IslandPanelView.sessionBootstrapPlaceholder` into a
/// standalone slot component. Reads its colours from `islandTokens` like the
/// other panel surfaces; takes its strings by value via `lang` — no `AppModel`
/// reference.
struct IslandBootstrapPlaceholder: View {
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.7))
                .scaleEffect(0.8)
            Text(lang.t("island.checkingTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.58))
            Text(lang.t("island.terminalOwnership"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
