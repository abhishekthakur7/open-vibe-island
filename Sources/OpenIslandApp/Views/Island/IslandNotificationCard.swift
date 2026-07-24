import SwiftUI
import OpenIslandCore

private struct NotificationContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Single actionable session shown when the panel was opened by a
/// notification — plus the "show all N" affordance when other sessions exist.
///
/// AB-298: extracted from `IslandPanelView.notificationCardContent` (and the
/// hover / height-measurement wrapper that used to live in `sessionList`) into
/// a standalone slot component. The model reads — the card session, the
/// interactive state, the row actions, the "show all" and pointer handlers,
/// and the measured-height write-back — are all lifted to the call site and
/// passed in by value or via closures; no `AppModel` reference.
struct IslandNotificationCard: View {
    let session: AgentSession?
    let isInteractive: Bool
    let stateIndicator: IslandSessionStateIndicator
    let completedStaleThreshold: TimeInterval
    let sideInset: CGFloat
    let totalSessionCount: Int
    let lang: LanguageManager
    let keyboardCoordinator: OverlayUICoordinator?
    let pulseClock: PulseClock?
    let makeActions: (AgentSession) -> RowActions
    let onShowAll: (AgentSession) -> Void
    let onPointerInside: () -> Void
    let onPointerExited: () -> Void
    let onMeasuredHeight: (CGFloat) -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    /// AB-299: the card's single row is built through the active theme's
    /// `sessionRow` factory. Classic returns the same `IslandSessionRow`.
    @Environment(\.islandTheme) private var theme

    var body: some View {
        cardContent
            .padding(.vertical, 2)
            .onHover { hovering in
                if hovering {
                    onPointerInside()
                } else {
                    onPointerExited()
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: NotificationContentHeightKey.self,
                        value: geo.size.height
                    )
                }
            )
            .onPreferenceChange(NotificationContentHeightKey.self) { height in
                if height > 0 {
                    onMeasuredHeight(height)
                }
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 0) {
            if let session {
                SessionRowContainer(
                    presentation: .notification,
                    isInteractive: isInteractive
                ) { isHighlighted in
                    theme.sessionRow(
                        session: session,
                        stateIndicator: stateIndicator,
                        completedStaleThreshold: completedStaleThreshold,
                        isActionable: true,
                        useDrawingGroup: isInteractive,
                        isInteractive: isInteractive,
                        isHighlighted: isHighlighted,
                        presentation: .notification,
                        sideInset: sideInset,
                        lang: lang,
                        actions: makeActions(session),
                        keyboardCoordinator: keyboardCoordinator,
                        pulseClock: pulseClock
                    )
                }
                .id(notificationCardIdentity(for: session))

                if totalSessionCount > 1 {
                    Button {
                        onShowAll(session)
                    } label: {
                        Text(lang.t("island.showAll", totalSessionCount))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, sideInset)
                            .padding(.top, 6)
                            .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func notificationCardIdentity(for session: AgentSession) -> String {
        switch session.phase {
        case .waitingForApproval:
            return "\(session.id)|approval|\(session.permissionRequest?.id.uuidString ?? "none")"
        case .waitingForAnswer:
            return "\(session.id)|question|\(session.questionPrompt?.id.uuidString ?? "none")"
        case .completed:
            return "\(session.id)|completed|\(session.updatedAt.timeIntervalSinceReferenceDate)"
        case .running:
            return "\(session.id)|running"
        }
    }
}
