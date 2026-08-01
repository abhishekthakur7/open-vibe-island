import SwiftUI
import OpenIslandCore

/// Poured Island's §B hover peek (PI-B-001) — the narrated surface a 0.15s
/// pointer dwell reveals on the *collapsed* island, before any click.
///
/// Reference `docs/design/overlay-redesign/01-poured-island.html:706-736`. The
/// prose invariant (`:706-709`) is "the single continuously-morphing shape
/// begins to grow and surfaces the one actionable item — before a full open",
/// and the rendered frame (`:712-736`) draws exactly one `.glass` body hanging
/// under the menu bar: `width:404px; border-radius:20px; padding:11px 15px 12px`,
/// the standard concave fillets at the notch junction, and **no wings** — the
/// peek *replaces* the pill's content rather than docking a second card under a
/// still-drawn pill. That is why `PouredIslandTheme` vends it with
/// `replacesClosedSurface: true`: the host hides the closed pill for as long as
/// this is up, so there is one body, one silhouette, one edge — never a step at
/// a joint (the exact "two shapes" tell Halo's dock shape had to be built to
/// avoid).
///
/// Row 1 (`gap:11`) is the 8pt approval dot with its 3pt warm ring, the
/// actionable session's title over its pending command, and the agent chip.
/// Row 2 (`margin-top:9`) is the click hint with the `+N more sessions`
/// overflow chip pushed right.
///
/// **Not interactive.** Like Halo's peek it renders `allowsHitTesting(false)`:
/// the click the hint promises is the collapsed island's own existing open
/// gesture, and the peek must never eat it. It draws no glow of its own either
/// — the closed pill's ambient bloom (`PouredClosedGlow`) keeps casting behind
/// the surface, so the light story is unchanged by the growth.
struct PouredHoverPeek: View {
    let content: HaloHoverPeekContent
    let lang: LanguageManager
    /// Upper bound from the host — the peek never renders wider than the
    /// island's own surface, so a narrow display clamps it instead of
    /// overhanging the window it lives in.
    var availableWidth: CGFloat
    /// The collapsed pill's outer width. The grown body is never *narrower*
    /// than the shape it grew out of, which is what keeps the growth reading as
    /// one continuous silhouette instead of a swap.
    var closedPillWidth: CGFloat
    /// Which top edge the collapsed island has here (notch fillets / top bar).
    var topProfile: OpenedIslandSurfaceShape.TopProfile

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// `width:404px` (`01-poured-island.html:717`) — the board's own peek width,
    /// between the collapsed pill (`.pill.big` 352) and the opened panel (520).
    static let preferredWidth: CGFloat = 404
    /// `border-radius:20px` (`:717`).
    static let cornerRadius: CGFloat = 20

    /// `padding:11px 15px 12px` (`:717`).
    private static let paddingTop: CGFloat = 11
    private static let paddingHorizontal: CGFloat = 15
    private static let paddingBottom: CGFloat = 12
    /// `gap:11` on the head row, `margin-top:2` under the title,
    /// `margin-top:9` before the hint row (`:719,721,726`).
    private static let headRowSpacing: CGFloat = 11
    private static let titleToCommandSpacing: CGFloat = 2
    private static let rowSpacing: CGFloat = 9

    /// The width the grown body actually takes: the board's 404, floored at the
    /// pill it grew from and clamped to the host's surface.
    var resolvedWidth: CGFloat {
        min(availableWidth, max(closedPillWidth, Self.preferredWidth))
    }

    /// The one silhouette this body draws — and the one the light traces. Flat
    /// top (`topCornerRadius: 0`, i.e. the collapsed pill's own top edge) with
    /// the theme's concave notch fillets, the board's 20pt bottom radius.
    private var surfaceShape: OpenedIslandSurfaceShape {
        OpenedIslandSurfaceShape(
            topProfile: topProfile,
            topCornerRadius: 0,
            bottomCornerRadius: Self.cornerRadius,
            filletRadius: tokens.metrics.filletRadius
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            headRow
            hintRow
        }
        .padding(.top, Self.paddingTop)
        .padding(.bottom, Self.paddingBottom)
        .padding(.horizontal, Self.paddingHorizontal)
        .frame(width: resolvedWidth, alignment: .leading)
        .background(glassBody)
        // R6 · N-10 (PI-B-003): the board's peek body carries the same two
        // `.fillet` spans every pill does (`01-poured-island.html:718`), so the
        // grown surface keeps the concave shoulders the pill grew out of instead
        // of snapping square. Overlay-drawn and offset outward, so `resolvedWidth`
        // — the number the host hit-tests and measures against — is unchanged.
        .islandCornerFilletFlares(tokens.material.cornerFillet)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(peekTitle). \(peekHint)")
    }

    // MARK: Glass body

    /// Literally the same code path the pill and the panel paint their body
    /// with: `OpenedSurfaceBackground`, which applies the theme material's
    /// `bodyGradient` (the reference's 3-stop `--glass`,
    /// `01-poured-island.html:49,132-134,147` — the peek body carries class
    /// `glass` like every other Poured surface), then `specularHardEdge` and
    /// `innerHairline` over it, all in one recipe.
    ///
    /// PI-B-001 review correction: this used to hand-roll a *different* body
    /// (flat `surfaceInk` + a local specular + a local hairline), so the pill →
    /// peek growth swapped materials mid-flight — a one-body silhouette
    /// painted with two recipes. Delegating removes the discontinuity by
    /// construction: a vertical sample through the peek interior now shows the
    /// same top-to-bottom ramp the pill shows, because it is the same view.
    /// The silhouette is unchanged — the same `surfaceShape` is both the fill's
    /// hairline contour and the clip.
    private var glassBody: some View {
        OpenedSurfaceBackground(
            reduceTransparency: reduceTransparency,
            surfaceShape: surfaceShape
        )
        .clipShape(surfaceShape)
        .allowsHitTesting(false)
    }

    // MARK: Rows

    private var headRow: some View {
        HStack(alignment: .center, spacing: Self.headRowSpacing) {
            PouredPillRingedDot(
                fill: dotTint,
                ring: ringTint.opacity(PouredPillMotion.Permission.ringOpacity),
                ringWidth: PouredPillMotion.Permission.ringWidth
            )

            VStack(alignment: .leading, spacing: Self.titleToCommandSpacing) {
                Text(peekTitle)
                    .font(PouredType.Role.peekTitle.font)
                    .foregroundStyle(tokens.colors.paper.opacity(text(0.96)))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail = content.detail {
                    Text(detail)
                        .font(PouredType.Role.peekCommand.font)
                        .foregroundStyle(tokens.colors.paper.opacity(text(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let agent = content.agent {
                agentChip(agent)
            }
        }
    }

    private var hintRow: some View {
        HStack(spacing: 10) {
            Text(peekHint)
                .font(PouredType.Role.peekHint.font)
                .foregroundStyle(tokens.colors.paper.opacity(text(tokens.colors.tertiaryTextOpacity)))
                .lineLimit(1)

            Spacer(minLength: 6)

            if content.moreWaiting > 0 {
                chip {
                    Text(lang.t("island.poured.peek.moreSessions", content.moreWaiting))
                        .font(PouredType.Role.metaChip.font)
                        .foregroundStyle(tokens.colors.paper.opacity(text(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                }
            }
        }
    }

    /// `<span class="chip"><span class="cd"></span>Sonnet 5</span>` (`:723`) —
    /// the agent's brand dot plus its display name, the same identity pairing
    /// the opened row's `agentIdentityChip` draws.
    private func agentChip(_ agent: AgentTool) -> some View {
        chip {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: agent.brandColorHex) ?? tokens.colors.paper)
                    .frame(width: 6, height: 6)
                Text(agent.displayName)
                    .font(PouredType.Role.agentChipLabel.font)
                    .foregroundStyle(tokens.colors.paper.opacity(text(tokens.colors.secondaryTextOpacity)))
                    .lineLimit(1)
            }
        }
    }

    /// `.chip { background: rgba(242,245,251,.06) }` — the paper tone at 6%, not
    /// a new surface colour.
    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tokens.colors.paper.opacity(0.06), in: Capsule())
    }

    // MARK: Copy

    /// `<name> wants to run a command` (`01-poured-island.html:718`), phrased
    /// from Poured's own `island.poured.peek.*` table rather than inheriting
    /// Halo's, so the two boards' copy can diverge without either theme moving.
    /// The permission/question fork is the shared content model's — a peek must
    /// never promise "approve" for a question.
    private var peekTitle: String {
        switch (content.kind, content.detail) {
        case (.permission, .some): lang.t("island.poured.peek.wantsToRun", content.workspace)
        case (.permission, .none): lang.t("island.poured.peek.wantsPermission", content.workspace)
        case (.question, _):       lang.t("island.poured.peek.hasQuestion", content.workspace)
        }
    }

    /// `Click to review & approve` (`:727`).
    private var peekHint: String {
        switch content.kind {
        case .permission: lang.t("island.poured.peek.reviewApprove")
        case .question:   lang.t("island.poured.peek.reviewAnswer")
        }
    }

    // MARK: Tokens

    /// The status hue: amber for a permission, gold for a question — the same
    /// tokens the A3/A4 pill and the §C rows read, so the peek's light and the
    /// island's light are one hue.
    private var dotTint: Color {
        switch content.kind {
        case .permission: tokens.colors.statusWaitingForApproval
        case .question:   tokens.colors.statusWaitingForAnswer
        }
    }

    /// `.ring { box-shadow:0 0 0 3px rgba(255,177,77,.22) }` — the warm
    /// attention halo, matched to the dot's own hue for the question variant so
    /// the two states differ in hue *and* copy, never colour alone.
    private var ringTint: Color {
        switch content.kind {
        case .permission: PouredPalette.attention
        case .question:   tokens.colors.statusWaitingForAnswer
        }
    }

    private func text(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: contrast == .increased)
    }
}
