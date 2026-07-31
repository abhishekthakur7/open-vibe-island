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
struct HaloHoverPeek: View {
    let content: HaloHoverPeekContent
    let lang: LanguageManager
    /// Upper bound from the host — the peek never renders wider than the
    /// island's own surface, so a narrow display clamps it instead of
    /// overhanging the pill it belongs to.
    var availableWidth: CGFloat

    @Environment(\.islandTokens) private var tokens
    @Environment(\.colorSchemeContrast) private var contrast

    /// `.isle perm{width:408px}`.
    static let preferredWidth: CGFloat = 408
    /// `border-radius:18px`.
    private static let cornerRadius: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            headRow
            hintRow
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(width: min(Self.preferredWidth, availableWidth), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(tokens.colors.surfaceInk)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
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
