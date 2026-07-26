import SwiftUI
import OpenIslandCore

/// Halo's install-hooks hint (AB-340 · SPEC-halo §7 Slot 8).
///
/// The persistent "install hooks" prompt shown while no agent hooks are installed —
/// the positive inverse of §J's monitoring pill. A quiet hairline-bounded line: a
/// muted caution glyph, the hint copy, a `SETUP` tag + chevron, and a single
/// hairline rule beneath. The tap routes to Settings → Setup through `onTap`.
///
/// **Deliberately quiet — a hint is not an attention state.** There is **NO
/// edge-light and NO glow**: nowhere in this view is a `.shadow` modifier, and
/// nowhere does it draw a state hue. Color = state discipline (brief §7) means the
/// prismatic edge and its bloom belong only to live session states; surfacing an
/// install hint with light would falsely read as "something needs you". The caution
/// glyph draws in a muted tertiary ink (not the amber attention accent) for the same
/// reason. A code-review confirmation of "no shadow modifier" is called out in the
/// PR per the acceptance criteria.
struct HaloInstallHooksHint: View {
    let lang: LanguageManager
    let onTap: () -> Void

    @State private var hovering = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandTokens) private var tokens

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .regular))
                        // Muted tertiary ink — never the amber attention accent, and
                        // never a glow (a hint is not a session attention state).
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                        .accessibilityHidden(true)
                    Text(lang.t("island.hint.installHooks"))
                        .font(.system(size: HaloTypography.emptySubtitleSize, weight: .regular))
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(hovering ? 0.9 : tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Text(lang.t("island.halo.hint.setup"))
                        .font(.system(size: HaloTypography.keycapSize, weight: .semibold))
                        .tracking(lang.usesCJKScript ? 0 : 1.0)
                        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(hovering ? 0.7 : tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(tokens.colors.paper.opacity(hovering ? 0.6 : 0.4))
                        .accessibilityHidden(true)
                }
                // A single hairline rule seats the line — no box, no pill, no fill.
                Rectangle()
                    .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Hover lift settles without easing under Reduce Motion.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
