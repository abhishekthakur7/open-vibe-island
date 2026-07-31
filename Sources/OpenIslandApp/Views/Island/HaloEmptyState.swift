import SwiftUI
import OpenIslandCore

/// Halo's empty state (AB-340 · SPEC-halo §7 Slot 6 / §J).
///
/// The void "earns its keep by disappearing until it has something true to say."
/// Rendered on the pure-black surface with **no box fills**: a static 34pt monitor
/// (clock) glyph at tertiary ink, an `All quiet` title (14/600), a confident
/// subtitle (12/400), and a single `● Monitoring · N workspaces` pill drawn as an
/// idle dot + a hairline ring (a `strokeBorder`, **not** a filled capsule — the
/// only chrome is the 8%-white hairline, mirroring the A1 idle pill with its edge
/// off). There is deliberately **no `.shadow`/glow** anywhere: Halo's rest state is
/// "edge off, calm", so the empty frame carries no light at all.
///
/// The glyph is **static** — no breathing. Unlike Poured's slow-glowing sensor,
/// Halo's calm is the absence of motion, so the glyph is a plain dim mark (SPEC:
/// "the only motion in an otherwise still frame — it must be static").
///
/// **Workspace count (the AB-326 seam).** `workspaceCount` is the number of
/// distinct workspace names across the current + recent sessions. When it is a
/// real positive count the pill reads `Monitoring · N workspaces`; when it is
/// unavailable (`0`) the pill falls back to a bare `Monitoring` — **never** a fake
/// number. `installedAgentNames` is accepted for signature parity with the other
/// themes but Halo's quiet frame does not surface a hooks-installed pill (the
/// monitoring pill already answers "is this working?").
struct HaloEmptyState: View {
    let lang: LanguageManager
    let hasRecentSessions: Bool
    /// Distinct workspace names across current + recent sessions; `0` ⇒ unavailable
    /// (render `Monitoring` alone, never a fabricated count).
    var workspaceCount: Int = 0

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        // §J vertical rhythm (G-26): the mockup is a *ramp*, not a uniform stack —
        // `.eg{margin-bottom:13}` → `.et` → `.es{margin-top:6}` → `.ec{margin-top:15}`.
        // The base spacing carries the 6pt title→subtitle step; the two wider gaps
        // are the deltas on top of it (6+7=13, 6+9=15).
        VStack(spacing: 6) {
            Spacer()

            // Static monitor glyph (34pt, tertiary) — the still centre of the void.
            Image(systemName: "clock")
                .font(.system(size: 34, weight: .thin))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
                .accessibilityHidden(true)
                .padding(.bottom, 7)

            Text(lang.t("island.halo.empty.allQuiet"))
                .font(.system(size: HaloTypography.emptyTitleSize, weight: .semibold))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(0.95, increaseContrast: increasesContrast)))

            Text(hasRecentSessions
                ? lang.t("island.recentSessions")
                : lang.t("island.halo.empty.watching"))
                .font(.system(size: HaloTypography.emptySubtitleSize, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            monitoringPill
                .padding(.top, 9)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
    }

    /// The `● Monitoring · N workspaces` pill: an idle dot + a hairline ring, no
    /// fill and no glow — the collapsed A1 idle language, edge off. Tertiary ink so
    /// it reads as reassurance, not an attention state (color = state discipline).
    private var monitoringPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tokens.colors.statusIdle)
                .frame(width: HaloMetrics.dot, height: HaloMetrics.dot)
                .accessibilityHidden(true)
            Text(monitoringText)
                .font(.system(size: 11, weight: .regular))
                .monospacedDigit()
        }
        .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Hairline ring only — a `strokeBorder`, never a filled capsule (no box fills).
        .overlay(
            Capsule()
                .strokeBorder(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// `Monitoring · N workspaces` when the count is a real positive value, else a
    /// bare `Monitoring` — the count is never fabricated when unavailable. English
    /// singular/plural is honoured via two keys (CJK collapses to one form).
    private var monitoringText: String {
        guard workspaceCount > 0 else { return lang.t("island.halo.empty.monitoring") }
        let key = workspaceCount == 1
            ? "island.halo.empty.workspaceOne"
            : "island.halo.empty.workspaceOther"
        return lang.t(key, workspaceCount)
    }
}
