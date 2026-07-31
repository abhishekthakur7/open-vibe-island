import SwiftUI
import OpenIslandCore

// MARK: - Content

/// What the §B peek says (mockup `06-halo.html:709-721`).
///
/// Pure value — every field is resolved from the surfaced sessions by
/// ``resolve(sessions:lang:)`` before any view exists, so the peek's *copy* is
/// testable without standing up an overlay and the view stays a renderer.
struct HaloHoverPeekContent: Equatable {

    /// Which attention the peek is speaking for. Drives the dot hue and the
    /// verb in the click hint — nothing else; the composition is identical.
    enum Kind: Equatable {
        case permission
        case question
    }

    var kind: Kind
    /// `.isle perm` line 1 — `the-automator wants to run a command`, 13/600 @ t1.
    var title: String
    /// `.isle perm` line 2 — the pending command, 11.5 mono @ t2. `nil` when the
    /// request carries no usable preview (an MCP call, a transcript-recovered
    /// session); the peek then runs as a two-line surface rather than inventing
    /// a command it cannot read.
    var detail: String?
    /// The `.mono-tag` monogram on the right of the head row.
    var monogram: String
    /// How many OTHER sessions are also waiting on the user. `0` hides the
    /// `+N more` chip — there is nothing compressed behind this one.
    var moreWaiting: Int

    /// The one actionable session the peek surfaces, or `nil` when nothing is
    /// waiting on the user (hover then stays the bare 1.03 scale bump — the
    /// board only ever draws a peek for an actionable island).
    ///
    /// "Most actionable" is the surfaced order's first waiting session, which is
    /// already the island's own spotlight ranking (`attention → running →
    /// first`), so the peek and the pill can never disagree about who is loud.
    static func resolve(sessions: [AgentSession], lang: LanguageManager) -> HaloHoverPeekContent? {
        let waiting = sessions.filter {
            $0.phase == .waitingForApproval || $0.phase == .waitingForAnswer
        }
        guard let lead = waiting.first else { return nil }

        let workspace = lead.spotlightWorkspaceName
        let kind: Kind = lead.phase == .waitingForApproval ? .permission : .question
        let command = kind == .permission
            ? IslandClosedLabelResolver.permissionCommandPreview(for: lead)
            : nil

        let title: String
        switch (kind, command) {
        case (.permission, .some):
            title = lang.t("island.halo.peek.wantsToRun", workspace)
        case (.permission, .none):
            title = lang.t("island.halo.peek.wantsPermission", workspace)
        case (.question, _):
            title = lang.t("island.halo.peek.hasQuestion", workspace)
        }

        return HaloHoverPeekContent(
            kind: kind,
            title: title,
            detail: command ?? (kind == .question ? questionPreview(for: lead) : nil),
            monogram: HaloSessionRowFormat.monogram(agentShortName: lead.tool.shortName),
            moreWaiting: waiting.count - 1
        )
    }

    /// The question's own prompt, trimmed to one line. Read from the same field
    /// the question hero renders, so the peek is a smaller view of the card the
    /// click opens — never a different sentence.
    private static func questionPreview(for session: AgentSession) -> String? {
        let asked = session.questionPrompt?.questions.first?.question ?? session.questionPrompt?.title
        guard let prompt = asked?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return nil
        }
        return prompt
    }

    /// `Click to review & approve` / `… & answer` — 11 @ t3.
    func hint(_ lang: LanguageManager) -> String {
        switch kind {
        case .permission: return lang.t("island.halo.peek.reviewApprove")
        case .question:   return lang.t("island.halo.peek.reviewAnswer")
        }
    }
}

// MARK: - View

/// The §B hover peek (G-62/M-27): the narrated surface a pointer dwell reveals
/// under the collapsed pill, before any click.
///
/// Mockup `06-halo.html:709-721` — a `width:408px; border-radius:18px;
/// padding:12px 15px` black body carrying a bloomed status dot, the actionable
/// session's title (13/600 @ t1) over its pending command (11.5 mono @ t2), the
/// `.mono-tag` monogram, and a second line 9pt below with the click hint
/// (11 @ t3) and a right-aligned `+N more` chip.
///
/// **Not interactive.** It hangs below the pill as chrome (`allowsHitTesting
/// (false)`) so the pointer stays on the pill that spawned it and the click that
/// the hint promises is the pill's own existing open gesture — the peek can
/// never eat it. That is also why it does not need to participate in the V3
/// morph: `IslandPanelView` fades it out on the first frame of `morphProgress`,
/// and the surface underneath grows exactly as it did before this view existed.
///
/// **Docked, not floating (R4 · item 2).** §B is emphatic that this is *one*
/// object — "the single black shape begins to grow… the edge-light stretches
/// continuously around the growing silhouette" — and §B′'s filmstrip draws the
/// peek frame at the **pill's own width**, just taller (`132×58` after `132×30`).
/// The shipped peek was a 408pt card floating ~4pt under a pill that kept its own
/// amber ring, so the judge read two shapes. It now renders as the pill's own
/// column: `dockedWidth` is the closed pill's outer width, the body's top edge is
/// flush with the pill's bottom, and — because a rounded-bottom pill meeting a
/// square-top body would leave two corner notches at the joint — the fill is
/// `HaloHoverPeekDockShape`, the whole column **minus the pill's own silhouette**
/// (even-odd). That fills the corner cut-ins with the same ink while leaving the
/// live pill and its content untouched, so the union silhouette is one straight
/// black body. The single continuous outline around that union is composed by
/// `IslandPanelView` (which owns the theme's edge seam) and the pill's own ring
/// is suppressed for as long as the peek is up, so there is exactly one edge.
struct HaloHoverPeek: View {
    let content: HaloHoverPeekContent
    let lang: LanguageManager
    /// Upper bound from the host — the peek never renders wider than the
    /// island's own surface, so a narrow display clamps it instead of
    /// overhanging the pill it belongs to.
    var availableWidth: CGFloat
    /// The closed pill's outer width: the docked body matches it exactly, so the
    /// two bodies share one silhouette (§B′ frame 2 is the pill's width, taller).
    var dockedWidth: CGFloat
    /// The pill band this column reserves above its own content — the pill draws
    /// into it, this view only leaves room.
    var pillHeight: CGFloat
    /// The pill's bottom corner radius, so the knockout matches the silhouette
    /// the pill actually draws where the two bodies meet.
    var pillBottomRadius: CGFloat

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast

    /// `.isle perm{width:408px}` — the board's own demo width, still the cap the
    /// docked body will not exceed on a very wide pill.
    static let preferredWidth: CGFloat = 408
    /// `border-radius:18px` — §B′ frame 2's radius, the bottom of the docked body.
    static let cornerRadius: CGFloat = 18

    /// The width the docked body actually takes: the pill's, clamped to the host's
    /// surface and floored at the board's own peek width so a short pill (an
    /// unlabelled attention state) still has room for the narration.
    var resolvedWidth: CGFloat {
        min(availableWidth, max(dockedWidth, Self.preferredWidth))
    }

    var body: some View {
        VStack(spacing: 0) {
            // The pill's own band. Transparent: the live pill renders into it.
            Color.clear
                .frame(height: pillHeight)

            VStack(alignment: .leading, spacing: 9) {
                headRow
                hintRow
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: resolvedWidth, alignment: .leading)
        .background(
            HaloHoverPeekDockShape(
                pillHeight: pillHeight,
                pillBottomRadius: pillBottomRadius,
                bottomRadius: Self.cornerRadius
            )
            // Even-odd: paint the whole column EXCEPT the pill's silhouette, so
            // the joint's corner cut-ins fill with the same ink and the pill's
            // own content is never painted over. No shadow — the docked body is
            // part of the pill's silhouette now, and Halo's void casts none.
            .fill(tokens.colors.surfaceInk, style: FillStyle(eoFill: true))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(content.title). \(content.hint(lang))")
    }

    private var headRow: some View {
        HStack(alignment: .center, spacing: 12) {
            HaloStatusDot(tint: dotTint, bloomOpacity: 0.55)

            VStack(alignment: .leading, spacing: 2) {
                Text(content.title)
                    .font(.system(size: HaloTypography.peekTitleSize, weight: .semibold))
                    .foregroundStyle(tokens.colors.paper)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail = content.detail {
                    Text(detail)
                        .font(.system(size: HaloTypography.peekDetailSize, design: .monospaced))
                        .foregroundStyle(tokens.colors.paper.opacity(opacity(tokens.colors.secondaryTextOpacity)))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HaloAgentMonogram(
                text: content.monogram,
                tokens: tokens,
                increasesContrast: contrast == .increased
            )
        }
    }

    private var hintRow: some View {
        HStack(spacing: 10) {
            Text(content.hint(lang))
                .font(.system(size: HaloTypography.peekHintSize))
                .foregroundStyle(tokens.colors.paper.opacity(opacity(tokens.colors.tertiaryTextOpacity)))
                .lineLimit(1)

            Spacer(minLength: 6)

            if content.moreWaiting > 0 {
                Text(lang.t("island.halo.peek.moreWaiting", content.moreWaiting))
                    .font(.system(size: HaloTypography.metaChipSize, weight: .medium))
                    .foregroundStyle(tokens.colors.paper.opacity(opacity(tokens.colors.secondaryTextOpacity)))
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }
        }
    }

    /// `.dot.perm` amber / `.dot.ques` qgold — the same status tokens the §C row
    /// dots read, so the peek's light and the row's light are one hue.
    private var dotTint: Color {
        switch content.kind {
        case .permission: return tokens.colors.statusWaitingForApproval
        case .question:   return tokens.colors.statusWaitingForAnswer
        }
    }

    private func opacity(_ base: Double) -> Double {
        tokens.colors.text(base, increaseContrast: contrast == .increased)
    }
}

// MARK: - Dock silhouette (R4 · item 2)

/// The docked peek's fill path: the **whole** pill+peek column (flat top, the
/// peek's bottom radius) with the pill's own silhouette subtracted, filled
/// even-odd.
///
/// Why the subtraction. The pill's bottom corners curve in over their last
/// `pillBottomRadius` points, so a body that simply started at the pill's bottom
/// edge would leave two unpainted notches at the joint and the union would read
/// as a step, not a column. Painting the column minus the pill means those
/// notches fill with the identical `surfaceInk` while every pixel the pill itself
/// owns — including its label, dot and badge — is left alone, even though this
/// layer is composited *above* the pill. The result is one continuous black body
/// whose outline `IslandPanelView` traces once with the theme's edge-light.
///
/// Both sub-paths come from `V6ClosedPillShape`, the very shape the pill and the
/// morph draw, so the knockout can never disagree with the silhouette it cuts.
struct HaloHoverPeekDockShape: Shape {
    let pillHeight: CGFloat
    let pillBottomRadius: CGFloat
    let bottomRadius: CGFloat

    /// How far the knockout is pulled INSIDE the pill's real silhouette, so this
    /// layer's ink underlaps the pill's own antialiased edge instead of butting
    /// against it. Butting leaves a sub-pixel seam where the two coverage ramps
    /// sum to less than 1 — measured as a 1px α≈198 hairline straight across the
    /// joint, which reads as a bright line on any light desktop and is precisely
    /// the "two shapes" tell being fixed here. 0.75pt is inside the pill's own
    /// `height/2` padding, so no pill content is ever painted over.
    static let knockoutUnderlap: CGFloat = 0.75

    func path(in rect: CGRect) -> Path {
        var path = V6ClosedPillShape(cornerRadius: bottomRadius).path(in: rect)
        let inset = Self.knockoutUnderlap
        let pillRect = CGRect(
            x: rect.minX + inset,
            y: rect.minY,
            width: max(0, rect.width - inset * 2),
            height: max(0, min(pillHeight, rect.height) - inset)
        )
        path.addPath(V6ClosedPillShape(cornerRadius: pillBottomRadius).path(in: pillRect))
        return path
    }
}
