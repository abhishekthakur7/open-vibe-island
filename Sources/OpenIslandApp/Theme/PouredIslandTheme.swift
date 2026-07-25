import AppKit
import SwiftUI
import OpenIslandCore

/// "Poured Island" — the liquid-glass theme (AB-300), first of five slices.
///
/// This slice ships the theme's skeleton: the token identity (cool ink/paper,
/// filleted opened shape, deep soft shadow, lighter vibrancy + specular top
/// edge, softer "poured" motion), the themed `NSVisualEffectView` configuration
/// carried by `IslandMaterialTokens`, the fillet-stem silhouette driven by
/// `metrics.filletRadius`, and the glass closed pill (`PouredClosedPill`).
///
/// Everything else — the opened header, session rows, list, notification card
/// and the empty/bootstrap/install states — deliberately returns Classic's slot
/// views for now; those regions get their glass treatment in the later Poured
/// slices (AB-301…). Mixed rendering behind the Lab switch is expected until
/// then. Registered but **not** the default: the default flips in Poured 5/5.
struct PouredIslandTheme: IslandTheme {

    // MARK: Identity

    let id = "poured"

    func name(_ lang: LanguageManager) -> String {
        lang.t("theme.poured.name")
    }

    func descriptor(_ lang: LanguageManager) -> String {
        lang.t("theme.poured.descriptor")
    }

    // MARK: Styling

    var tokens: IslandThemeTokens { .poured }

    // MARK: Capability flags

    /// Rows still render Classic's flat views this slice, which are safe to
    /// rasterize; the glass row treatment (and any flag flip) lands in AB-301.
    let rowIsDrawingGroupSafe = true

    /// The opened slab is a frosted `NSVisualEffectView` surface, so vibrancy
    /// is on — it falls back to a flat `surfaceInk` fill under Reduce
    /// Transparency, the same path Classic takes.
    let usesVibrancy = true

    // MARK: Geometry strategy

    /// Poured's closed grid does not deviate from Classic's, so it reuses the
    /// same `V6RightSlotView` statics (pinned by `AgentsGridLayoutTests`) — no
    /// new geometry, no new layout vectors. Only the per-tile glass styling
    /// differs, which lives in `PouredClosedPill`, not in the geometry.
    var agentsGridGeometry: IslandAgentsGridGeometry {
        IslandAgentsGridGeometry(
            balancedRows: { V6RightSlotView.balancedRows($0) },
            cellGeometry: { V6RightSlotView.cellGeometry(rowCount: $0) }
        )
    }

    // MARK: Slot factories

    /// The one slot this slice restyles: the glass closed pill.
    func closedPill(
        mode: UnifiedBars.Mode,
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat,
        physicalNotchWidth: CGFloat,
        minWidth: CGFloat,
        showsGlyph: Bool
    ) -> AnyView {
        AnyView(
            PouredClosedPill(
                mode: mode,
                label: label,
                rightSlot: rightSlot,
                layout: layout,
                height: height,
                physicalNotchWidth: physicalNotchWidth,
                minWidth: minWidth,
                showsGlyph: showsGlyph
            )
        )
    }

    // MARK: Slots deferred to later Poured slices (Classic views for now)

    func openedHeader(
        providers: [UsageProviderPresentation],
        usesNotchAwareLayout: Bool,
        targetScreen: NSScreen?,
        isSoundMuted: Bool,
        lang: LanguageManager,
        onToggleMute: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            IslandHeaderControls(
                providers: providers,
                usesNotchAwareLayout: usesNotchAwareLayout,
                targetScreen: targetScreen,
                isSoundMuted: isSoundMuted,
                lang: lang,
                onToggleMute: onToggleMute,
                onShowSettings: onShowSettings,
                onQuit: onQuit
            )
        )
    }

    func sessionRow(
        session: AgentSession,
        stateIndicator: IslandSessionStateIndicator,
        completedStaleThreshold: TimeInterval,
        isActionable: Bool,
        useDrawingGroup: Bool,
        isInteractive: Bool,
        isHighlighted: Bool,
        presentation: IslandSessionRowPresentation,
        sideInset: CGFloat,
        lang: LanguageManager,
        actions: RowActions,
        keyboardCoordinator: OverlayUICoordinator?,
        pulseClock: PulseClock?
    ) -> AnyView {
        AnyView(
            IslandSessionRow(
                session: session,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                isActionable: isActionable,
                useDrawingGroup: useDrawingGroup,
                isInteractive: isInteractive,
                isHighlighted: isHighlighted,
                presentation: presentation,
                sideInset: sideInset,
                lang: lang,
                actions: actions,
                keyboardCoordinator: keyboardCoordinator,
                pulseClock: pulseClock
            )
        )
    }

    func sessionList(
        sessions: [AgentSession],
        sections: [IslandSessionSection],
        group: IslandSessionGroup,
        stateIndicator: IslandSessionStateIndicator,
        completedStaleThreshold: TimeInterval,
        sideInset: CGFloat,
        isInteractive: Bool,
        actionableSessionID: String?,
        lang: LanguageManager,
        keyboardCoordinator: OverlayUICoordinator?,
        pulseClock: PulseClock?,
        makeActions: @escaping (AgentSession) -> RowActions
    ) -> AnyView {
        AnyView(
            IslandSessionListScaffold(
                sessions: sessions,
                sections: sections,
                group: group,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                sideInset: sideInset,
                isInteractive: isInteractive,
                actionableSessionID: actionableSessionID,
                lang: lang,
                keyboardCoordinator: keyboardCoordinator,
                pulseClock: pulseClock,
                makeActions: makeActions
            )
        )
    }

    func notificationCard(
        session: AgentSession?,
        isInteractive: Bool,
        stateIndicator: IslandSessionStateIndicator,
        completedStaleThreshold: TimeInterval,
        sideInset: CGFloat,
        totalSessionCount: Int,
        lang: LanguageManager,
        keyboardCoordinator: OverlayUICoordinator?,
        pulseClock: PulseClock?,
        makeActions: @escaping (AgentSession) -> RowActions,
        onShowAll: @escaping (AgentSession) -> Void,
        onPointerInside: @escaping () -> Void,
        onPointerExited: @escaping () -> Void,
        onMeasuredHeight: @escaping (CGFloat) -> Void
    ) -> AnyView {
        AnyView(
            IslandNotificationCard(
                session: session,
                isInteractive: isInteractive,
                stateIndicator: stateIndicator,
                completedStaleThreshold: completedStaleThreshold,
                sideInset: sideInset,
                totalSessionCount: totalSessionCount,
                lang: lang,
                keyboardCoordinator: keyboardCoordinator,
                pulseClock: pulseClock,
                makeActions: makeActions,
                onShowAll: onShowAll,
                onPointerInside: onPointerInside,
                onPointerExited: onPointerExited,
                onMeasuredHeight: onMeasuredHeight
            )
        )
    }

    func emptyState(lang: LanguageManager, hasRecentSessions: Bool) -> AnyView {
        AnyView(IslandEmptyState(lang: lang, hasRecentSessions: hasRecentSessions))
    }

    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        AnyView(IslandBootstrapPlaceholder(lang: lang))
    }

    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        AnyView(IslandInstallHooksHint(lang: lang, onTap: onTap))
    }
}
