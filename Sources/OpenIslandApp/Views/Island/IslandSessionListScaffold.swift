import SwiftUI
import OpenIslandCore

/// The opened panel's full session-list chrome: the overview header (with its
/// aggregate counts), the scrollable, optionally grouped list of session rows
/// with their section headers, and the footer hairline.
///
/// AB-298: extracted from `IslandPanelView`'s `sessionList` scaffolding plus
/// `sessionPanelHeader` / `sessionSectionHeader` / `sessionPanelFooter` /
/// `sessionOverviewView` (and their pure helpers) into a standalone slot
/// component. Every model read — the listed sessions, the grouped sections,
/// the grouping mode, the actionable session id, and the per-row actions — is
/// lifted to the call site and passed in by value or via `makeActions`; no
/// `AppModel` reference.
struct IslandSessionListScaffold: View {
    /// Cap for the scrollable session-row region — the one intentional height
    /// cap left in the opened surface (long lists scroll instead of growing
    /// the window indefinitely). This used to also live, duplicated, as
    /// `OverlayPanelController.maxSessionListHeight`, with a comment admitting
    /// the two had to be hand-kept in sync; now the controller only reads the
    /// real measured height, so this is the single source of truth (AB-228).
    private static let maxSessionListHeight: CGFloat = 560

    let sessions: [AgentSession]
    let sections: [IslandSessionSection]
    let group: IslandSessionGroup
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let sideInset: CGFloat
    let isInteractive: Bool
    let actionableSessionID: String?
    let lang: LanguageManager
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?
    let makeActions: (AgentSession) -> RowActions

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    /// AB-299: rows are built through the active theme's `sessionRow` factory
    /// so a theme can supply its own row without re-implementing the list
    /// scaffold. Classic returns the same `IslandSessionRow` this used to
    /// instantiate directly.
    @Environment(\.islandTheme) private var theme

    var body: some View {
        // AB-228: the header and the row list each own their own small
        // periodic tick instead of sharing one `TimelineView` that wrapped
        // (and rebuilt) header + rows + footer together every 30s. The
        // header's tick keeps its aggregate counts and the "just done → idle"
        // section regrouping fresh; each row (see `IslandSessionRow`)
        // separately owns the much smaller job of refreshing its own age badge
        // / presence, so a row updating doesn't ripple into the header or its
        // siblings, and vice versa.
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                sessionPanelHeader(referenceDate: context.date)
            }

            AutoHeightScrollView(maxHeight: Self.maxSessionListHeight) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    sessionRowsContent()
                }
            }

            sessionPanelFooter
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sessionRowsContent() -> some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 0) {
                if group != .none {
                    sessionSectionHeader(section)
                }

                ForEach(section.sessions) { session in
                    SessionRowContainer(isInteractive: isInteractive) { isHighlighted in
                        theme.sessionRow(
                            session: session,
                            stateIndicator: stateIndicator,
                            completedStaleThreshold: completedStaleThreshold,
                            isActionable: session.phase.requiresAttention || session.id == actionableSessionID,
                            useDrawingGroup: isInteractive,
                            isInteractive: isInteractive,
                            isHighlighted: isHighlighted,
                            presentation: .list,
                            sideInset: sideInset,
                            lang: lang,
                            actions: makeActions(session),
                            keyboardCoordinator: keyboardCoordinator,
                            pulseClock: pulseClock
                        )
                    }
                }
            }
        }
    }

    private func sessionPanelHeader(referenceDate: Date) -> some View {
        let overview = sessionOverviewItems(referenceDate: referenceDate)

        return HStack(spacing: 8) {
            Text(lang.t("island.sessionList.title").uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(tokens.colors.paper.opacity(0.55))

            ViewThatFits(in: .horizontal) {
                sessionOverviewView(overview, compact: false)
                sessionOverviewView(overview, compact: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 36)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private var sessionPanelFooter: some View {
        Color.clear
            .frame(height: 10)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func sessionOverviewItems(referenceDate: Date) -> [SessionOverviewItem] {
        guard !sessions.isEmpty else { return [] }

        let threshold = completedStaleThreshold
        let waiting = sessions.filter(\.phase.requiresAttention).count
        let running = sessions.filter { $0.phase == .running }.count
        let done = sessions.filter {
            $0.phase == .completed
                && !isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count
        let idle = sessions.filter {
            isIdleSessionOverviewItem($0, referenceDate: referenceDate, threshold: threshold)
        }.count

        return [
            SessionOverviewItem(id: "total", title: lang.t("island.sessionOverview.total"), compactTitle: "", count: sessions.count, tint: nil),
            SessionOverviewItem(id: "waiting", title: lang.t("island.sessionOverview.waiting"), compactTitle: lang.t("island.sessionOverview.waitingCompact"), count: waiting, tint: tokens.colors.statusWaitingAggregate),
            SessionOverviewItem(id: "running", title: lang.t("island.sessionOverview.running"), compactTitle: lang.t("island.sessionOverview.runningCompact"), count: running, tint: tokens.colors.statusRunning),
            SessionOverviewItem(id: "done", title: lang.t("island.sessionOverview.done"), compactTitle: lang.t("island.sessionOverview.done"), count: done, tint: tokens.colors.statusCompleted),
            SessionOverviewItem(id: "idle", title: lang.t("island.sessionOverview.idle"), compactTitle: lang.t("island.sessionOverview.idle"), count: idle, tint: tokens.colors.statusIdle),
        ].filter { $0.id == "total" || $0.count > 0 }
    }

    private func isIdleSessionOverviewItem(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }

    private func sessionOverviewView(_ items: [SessionOverviewItem], compact: Bool) -> some View {
        HStack(spacing: compact ? 7 : 9) {
            ForEach(items) { item in
                sessionOverviewMetric(item, compact: compact)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        // AB-244: no interactive content here — the per-metric tint dots
        // are purely decorative (`.accessibilityHidden` below), so VoiceOver
        // reads this whole strip as one sentence ("5 total, 2 waiting, 1
        // running…") instead of stopping on every dot/count pair.
        .accessibilityElement(children: .combine)
    }

    private func sessionOverviewMetric(_ item: SessionOverviewItem, compact: Bool) -> some View {
        HStack(spacing: 4) {
            if let tint = item.tint {
                Circle()
                    .fill(tint)
                    .frame(width: 5.5, height: 5.5)
                    .accessibilityHidden(true)
            }

            Text(sessionOverviewMetricTitle(item, compact: compact))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    item.tint == nil
                        ? tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast))
                        : tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast))
                )
        }
    }

    private func sessionOverviewMetricTitle(_ item: SessionOverviewItem, compact: Bool) -> String {
        if item.id == "total" {
            return compact ? "\(item.count)" : "\(item.count) \(item.title)"
        }

        return "\(item.count) \(compact ? item.compactTitle : item.title)"
    }

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(sectionTint(for: section))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(sessionSectionTitle(for: section).uppercased())
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(Color.white.opacity(0.008))
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func sectionTint(for section: IslandSessionSection) -> Color {
        guard let first = section.sessions.first else { return tokens.colors.statusIdle }
        if section.id == "state-idle" { return tokens.colors.statusIdle }
        return tokens.colors.statusTint(for: first.phase, outcome: first.outcome)
    }

    private func sessionSectionTitle(for section: IslandSessionSection) -> String {
        if section.title.hasPrefix("island.") {
            return lang.t(section.title)
        }
        return section.title
    }

    private func sectionLabelColor(for section: IslandSessionSection) -> Color {
        switch section.id {
        case "state-approval":
            return tokens.colors.statusWaitingForApproval.opacity(0.86)
        case "state-answer":
            return tokens.colors.statusWaitingForAnswer.opacity(0.86)
        default:
            return tokens.colors.paper.opacity(0.7)
        }
    }
}

private struct SessionOverviewItem: Identifiable {
    let id: String
    let title: String
    let compactTitle: String
    let count: Int
    let tint: Color?
}
