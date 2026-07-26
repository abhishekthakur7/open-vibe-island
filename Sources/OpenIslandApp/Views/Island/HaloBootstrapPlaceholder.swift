import SwiftUI
import OpenIslandCore

/// Halo's cold-launch bootstrap placeholder (AB-340 · SPEC-halo §7 Slot 7).
///
/// The void shell shown while probing terminal ownership on cold launch. It shares
/// the empty state's still, box-free identity — a static monitor glyph, a spinner,
/// and the `checking terminals` copy — so the two pre-list states read as one calm
/// surface (SPEC: "reuse the empty-state void shell").
///
/// **No flash — trivially safe.** The Halo surface is a fully opaque `#000` void
/// (`HaloTheme.usesVibrancy == false`, `tintOpacity 1.0`), so `OpenedSurfaceBackground`
/// paints opaque black immediately; there is **no gradient/material fade-in** that
/// could flash a non-black fill before the content mounts (the risk Poured's spec
/// flagged for its poured-glass gradient does not exist here). Nothing in this view
/// draws a box fill or a glow.
struct HaloBootstrapPlaceholder: View {
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: "clock")
                .font(.system(size: 30, weight: .thin))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                .accessibilityHidden(true)

            ProgressView()
                .progressViewStyle(.circular)
                .tint(tokens.colors.paper.opacity(0.7))
                .scaleEffect(0.8)

            Text(lang.t("island.checkingTerminals"))
                .font(.system(size: HaloTypography.emptyTitleSize, weight: .semibold))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            Text(lang.t("island.terminalOwnership"))
                .font(.system(size: HaloTypography.emptySubtitleSize, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
    }
}
