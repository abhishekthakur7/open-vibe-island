import SwiftUI
import OpenIslandCore

/// Halo's install-hooks hint (AB-340 · SPEC-halo §7 Slot 8).
///
/// The persistent "install hooks" prompt shown while no agent hooks are installed —
/// the positive inverse of §J's monitoring pill. A quiet hairline **card**: a muted
/// caution glyph, the hint copy, and a `SETUP` tag + chevron, all inside the panel's
/// `hair2` chip chrome. The tap routes to Settings → Setup through `onTap`.
///
/// **V9 / G-64 — the calmest state must stay calm.** The hint is not in mockup §J at
/// all, yet in real (non-harness) mode it sits between the header and the empty
/// state and was reading as the loudest element on the panel: full-bleed secondary
/// ink over two lines, seated on a full-width rule that made it a *banner*. It now
/// wears the same chrome as the §D/§H `.mcell` chips (radius 9, `hair2` inset
/// stroke, a 2% wash, `8/11` padding) and drops to the tertiary ink tier, so it
/// reads as one more quiet fact on the surface rather than an attention state.
/// Position, copy and tap behaviour are unchanged — this is a restyle only.
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
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .regular))
                    // Muted tertiary ink — never the amber attention accent, and
                    // never a glow (a hint is not a session attention state).
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                    .accessibilityHidden(true)
                Text(lang.t("island.hint.installHooks"))
                    .font(.system(size: HaloTypography.emptySubtitleSize, weight: .regular))
                    // G-64: tertiary tier at rest (was secondary) — the hint sits a
                    // step *below* the empty state's own subtitle, never above it.
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(hovering ? tokens.colors.secondaryTextOpacity : tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // The chip's 11pt side padding costs the line the width it used
                    // to have: without this the copy tail-truncates ("Tap to…")
                    // instead of wrapping to its second line. Copy is unchanged.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Text(lang.t("island.halo.hint.setup"))
                    .font(.system(size: HaloTypography.keycapSize, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(hovering ? tokens.colors.secondaryTextOpacity : tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                    .accessibilityHidden(true)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(hovering ? tokens.colors.secondaryTextOpacity : tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                    .accessibilityHidden(true)
            }
            // `.mcell` chrome (G-55 / G-64): 8/11 padding inside a radius-9 chip.
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tokens.colors.paper.opacity(hovering ? 0.04 : 0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                tokens.colors.paper.opacity(increasesContrast ? 0.14 : 0.05),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Hover lift settles without easing under Reduce Motion.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
