import SwiftUI
import OpenIslandCore

/// Shown in the opened panel when there are no sessions to list. The second
/// line nudges the user to start an agent, or points at recent sessions when
/// some exist off-list.
///
/// AB-298: extracted from `IslandPanelView.emptyState` into a standalone slot
/// component. The `model.recentSessions.isEmpty` read is lifted to the call
/// site and passed in as `hasRecentSessions` — no `AppModel` reference.
struct IslandEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(lang.t("island.noTerminals"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
            Text(hasRecentSessions
                ? lang.t("island.recentSessions")
                : lang.t("island.startAgent"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
