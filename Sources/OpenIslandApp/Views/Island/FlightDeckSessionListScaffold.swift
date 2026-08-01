import SwiftUI
import OpenIslandCore

/// Flight Deck's session-list chrome (AB-312): the sessions summary as a strip of
/// **annunciator tiles** (ATTN / RUN / DONE / IDLE, each lit when its count is
/// non-zero and dark at zero), a column-caption strip (STATUS / SESSION / MODEL
/// / TIME — AB-337) over the list, the section headers for all four grouping modes, the
/// scrollable list of rows, and a **BRIDGE LINK** footer wired to the real
/// bridge-socket state.
///
/// The counting and grouping logic is identical to `IslandSessionListScaffold` —
/// the summary's total / waiting / running / done / idle tallies and the
/// per-section tint / title / count are computed the same way — so only the
/// surface treatment differs: hierarchy is carried by lit annunciator tiles,
/// uppercase letterspaced mono captions, square status lamps and load-bearing
/// hairline rules rather than by glass or wash. Every uppercase caption routes
/// its casing and tracking through `FlightDeckText`, which neutralizes both for
/// CJK so 中文 never letterspaces into illegibility.
///
/// Rows are built through the active theme's `sessionRow` factory (the shared
/// scaffold's exact path), so the Flight Deck list inherits the theme's
/// `FlightDeckSessionRow` (AB-313): every non-actionable row carries a status
/// lane on the STATUS / SESSION / MODEL / TIME column grid (AB-337), registered
/// directly under this strip's captions.
struct FlightDeckSessionListScaffold: View {
    /// Cap for the scrollable region — kept in sync with the shared scaffold so
    /// the opened surface's height math is identical across themes.
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.islandTokens) private var tokens
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                annunciatorStrip(referenceDate: context.date)
            }

            columnCaptionStrip

            AutoHeightScrollView(maxHeight: Self.maxSessionListHeight) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    sessionRowsContent()
                }
            }

            sessionPanelFooter
        }
        .padding(.vertical, 2)
        // AB-335: the opened panel body renders the FD `panel` tone (#0E1113),
        // a distinct step *lighter* than the `surfaceInk` cockpit ground the
        // shared `OpenedSurfaceBackground` fills beneath it — so the list reads
        // as a lit panel seated over the darker ground. The closed pill / ground
        // keep `surfaceInk`.
        .frame(maxWidth: .infinity)
        .background(FlightDeckSurfaces.panel)
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
                    // AB-337 · §4K: relay-snap settle when a row is inserted into
                    // the already-mounted list. The transition never plays on the
                    // list's initial appearance (that arrives under the panel's own
                    // open morph), only on a genuine insert; the drive animation is
                    // nil under Reduce Motion, so a reduced-motion insert snaps —
                    // no clock is touched.
                    .transition(FlightDeckRowEntrance.transition)
                }
            }
            // Keyed to the section's row-id set so an insert/remove animates the
            // matching row's transition (and the neighbours settling around it).
            .animation(
                reduceMotion ? nil : FlightDeckRowEntrance.animation,
                value: section.sessions.map(\.id)
            )
        }
    }

    // MARK: - Annunciator summary tiles

    /// The summary strip — the mockup's `.summary` (`02-flight-deck.html:321-326,
    /// 913-919`): its **own full-width band**, entirely separate from the
    /// brand/usage `.phead` header above it. There is no mockup equivalent of a
    /// "SESSION LIST" title sharing this row — the shipped `Text(...title)`
    /// fused into one `HStack` alongside the tiles is dropped (overlay
    /// remediation F9); the column-caption strip immediately below already
    /// labels the list ("Session" et al.), so the redundant title cost fidelity
    /// without adding information. Tiles are `flex:1` and always fill the
    /// available width edge-to-edge, so unlike the retired fixed-intrinsic
    /// `annunciatorRow` this never needs a `ViewThatFits` compact fallback.
    private func annunciatorStrip(referenceDate: Date) -> some View {
        let tiles = annunciatorTiles(referenceDate: referenceDate)

        return HStack(spacing: 1) {
            ForEach(tiles) { tile in
                FlightDeckAnnunciatorTileView(tile: tile, lang: lang)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // The 1pt inter-tile gaps show this hairline through, matching the
        // mockup's `.summary{gap:1px;background:var(--hair)}` container.
        .background(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(annunciatorAccessibilityLabel(tiles))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    /// The four fixed annunciator tiles. Unlike the shared summary,
    /// which filters out zero-count states, the Flight Deck panel always renders
    /// all four — an unlit annunciator is as much a readout as a lit one — so ATTN
    /// / RUN / DONE / IDLE stay in fixed positions and simply light or go dark
    /// with their count.
    private func annunciatorTiles(referenceDate: Date) -> [FlightDeckAnnunciatorTile] {
        let threshold = completedStaleThreshold
        let waiting = sessions.filter(\.phase.requiresAttention).count
        let running = sessions.filter { $0.phase == .running }.count
        let done = sessions.filter {
            $0.phase == .completed
                && !isIdleSession($0, referenceDate: referenceDate, threshold: threshold)
        }.count
        let idle = sessions.filter {
            isIdleSession($0, referenceDate: referenceDate, threshold: threshold)
        }.count

        return [
            FlightDeckAnnunciatorTile(id: "attn", label: lang.t("island.flightDeck.annunciator.attn"), count: waiting, tint: tokens.colors.statusWaitingAggregate),
            FlightDeckAnnunciatorTile(id: "run", label: lang.t("island.flightDeck.annunciator.run"), count: running, tint: tokens.colors.statusRunning),
            FlightDeckAnnunciatorTile(id: "done", label: lang.t("island.flightDeck.annunciator.done"), count: done, tint: tokens.colors.statusCompleted),
            FlightDeckAnnunciatorTile(id: "idle", label: lang.t("island.flightDeck.annunciator.idle"), count: idle, tint: tokens.colors.statusIdle),
        ]
    }

    private func annunciatorAccessibilityLabel(_ tiles: [FlightDeckAnnunciatorTile]) -> String {
        let parts = tiles.map { "\($0.count) \($0.label)" }
        return "\(lang.t("island.sessionList.title")) \(parts.joined(separator: ", "))"
    }

    private func isIdleSession(
        _ session: AgentSession,
        referenceDate: Date,
        threshold: TimeInterval
    ) -> Bool {
        guard session.phase == .completed else { return false }
        return session.isStaleCompletedForIsland(at: referenceDate, threshold: threshold)
            || session.islandPresence(at: referenceDate) == .inactive
    }

    // MARK: - Column-caption strip

    /// The STATUS / SESSION / MODEL / TIME column captions over the list. As of
    /// AB-337 the strip leads with a **STATUS** caption over the new status-code
    /// column and the shipped **APP** caption is gone (APP folded into the row's
    /// `SSH` chip). The captions and the rows share one geometry: the leading
    /// STATUS caption sits at the fixed `statusColumnWidth`, the SESSION caption
    /// flexes over the flexing headline, and the MODEL / TIME captions sit at the
    /// exact `FlightDeckSessionRowGrid` lane widths (with the chevron and dismiss
    /// control lanes reserved as clear trailing space) so each caption lands
    /// directly over its cell across every row — one source, captions and rows
    /// cannot drift.
    private var columnCaptionStrip: some View {
        HStack(spacing: FlightDeckSessionRowGrid.leadingColumnGap) {
            columnCaption(lang.t("island.flightDeck.column.status"))
                .frame(width: FlightDeckSessionRowGrid.statusColumnWidth, alignment: .leading)

            columnCaption(lang.t("island.flightDeck.column.session"))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: FlightDeckSessionRowGrid.columnGap) {
                columnCaption(lang.t("island.flightDeck.column.model"))
                    .frame(width: FlightDeckSessionRowGrid.modelColumnWidth, alignment: .leading)
                columnCaption(lang.t("island.flightDeck.column.time"))
                    .frame(width: FlightDeckSessionRowGrid.timeColumnWidth, alignment: .trailing)
                // Reserve the chevron + dismiss control lanes so the TIME caption
                // registers over the row's TIME cell, which sits left of them.
                Color.clear.frame(width: FlightDeckSessionRowGrid.detailToggleColumnWidth, height: 1)
                Color.clear.frame(width: FlightDeckSessionRowGrid.dismissColumnWidth, height: 1)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }

    private func columnCaption(_ text: String) -> some View {
        Text(FlightDeckText.caps(text, lang: lang))
            .font(FlightDeckTypography.microLabel)
            .tracking(FlightDeckText.tracking(1.0, lang: lang))
            .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            .lineLimit(1)
    }

    // MARK: - Section header

    private func sessionSectionHeader(_ section: IslandSessionSection) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(sectionTint(for: section))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(FlightDeckText.caps(sessionSectionTitle(for: section), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(0.9, lang: lang))
                .foregroundStyle(sectionLabelColor(for: section))
            Text("\(section.sessions.count)")
                .font(.system(size: FlightDeckTypography.microLabelSize, weight: .medium, design: .monospaced))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
            Spacer(minLength: 0)
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(tokens.colors.paper.opacity(increasesContrast ? 0.03 : 0.012))
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
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
            return tokens.colors.statusWaitingForApproval.opacity(0.9)
        case "state-answer":
            return tokens.colors.statusWaitingForAnswer.opacity(0.9)
        default:
            return tokens.colors.paper.opacity(tokens.colors.text(0.72, increaseContrast: increasesContrast))
        }
    }

    // MARK: - BRIDGE LINK footer

    /// The bridge-link readout, wired to the real socket state: a live square lamp
    /// and a BRIDGE LINK · LINK / NO LINK caption on the left (green nominal and
    /// blinking when the socket is up, warning red and static when it is down),
    /// the live session count on the right. The panel displays the truth of the
    /// connection, not a decorative string.
    private var sessionPanelFooter: some View {
        FlightDeckBridgeFooter(sessionCount: sessions.count, sideInset: sideInset, lang: lang)
    }
}

// MARK: - Annunciator tile geometry

/// One annunciator tile's geometry (`02-flight-deck.html:322-326`): the
/// `9px 12px` padding, the `gap:3px` between the stacked count and caption,
/// and the lit marker's `2px`-wide full-height accent bar. Named constants —
/// rather than literals inline in `FlightDeckAnnunciatorTileView.body` — so
/// `FlightDeckThemeTests` can pin the geometry the plan's acceptance criteria
/// (tile height 49–55pt @1x, a ≥2pt accent mark) actually depend on, the same
/// pattern `FlightDeckSessionRowGrid` / `FlightDeckTapeGauge` already follow
/// for their own pinned geometry (overlay remediation F9).
enum FlightDeckAnnunciatorGeometry {
    static let verticalPadding: CGFloat = 9
    static let horizontalPadding: CGFloat = 12
    static let stackSpacing: CGFloat = 3
    static let accentBarWidth: CGFloat = 2
}

// MARK: - Annunciator tile

private struct FlightDeckAnnunciatorTile: Identifiable {
    let id: String
    let label: String
    let count: Int
    let tint: Color
    var isLit: Bool { count > 0 }
}

/// One annunciator tile: a large count stacked **above** an uppercase caption
/// (mockup `.sumtile{flex-direction:column}`, `02-flight-deck.html:322-334`),
/// marked lit by a leading **full-height 2pt accent bar** — not a small square
/// lamp — when its count is non-zero; dark tiles carry no accent mark at all.
/// An unlit annunciator is still a readout: its count and caption drop to
/// dimmer text rather than disappearing. A lit accent bar is self-lit
/// phosphor (AB-336, generalized by overlay remediation F9 from the retired
/// square lamp): it bleeds a static halo outside its own silhouette via the
/// shared `phosphorGlow` primitive. The glow is static (a count readout, not
/// a live lamp), so there is nothing to animate and Reduce Motion is a no-op
/// here. Tiles carry no per-tile radius or border — separation comes from the
/// 1pt hairline gaps the parent `annunciatorStrip` draws between them
/// (mockup `.summary{gap:1px}`), and each tile fills with the `--surface`
/// panel tone (`FlightDeckSurfaces.panel`), not the `--surface-2` tile tone.
private struct FlightDeckAnnunciatorTileView: View {
    let tile: FlightDeckAnnunciatorTile
    let lang: LanguageManager

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }

    @Environment(\.islandTokens) private var tokens

    private var countColor: Color {
        tile.isLit
            ? tokens.colors.paper.opacity(tokens.colors.text(0.85, increaseContrast: increasesContrast))
            : tokens.colors.paper.opacity(tokens.colors.text(tile.count == 0 ? tokens.colors.tertiaryTextOpacity : tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast))
    }

    private var labelColor: Color {
        tokens.colors.paper.opacity(
            tokens.colors.text(
                tile.isLit ? tokens.colors.secondaryTextOpacity : tokens.colors.tertiaryTextOpacity,
                increaseContrast: increasesContrast
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FlightDeckAnnunciatorGeometry.stackSpacing) {
            Text("\(tile.count)")
                .font(FlightDeckTypography.annunciatorCount)
                .foregroundStyle(countColor)
                .lineLimit(1)

            Text(FlightDeckText.caps(tile.label, lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(0.8, lang: lang))
                .foregroundStyle(labelColor)
                .lineLimit(1)
        }
        .padding(.vertical, FlightDeckAnnunciatorGeometry.verticalPadding)
        .padding(.horizontal, FlightDeckAnnunciatorGeometry.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlightDeckSurfaces.panel)
        .overlay(alignment: .leading) {
            if tile.isLit {
                Rectangle()
                    .fill(tile.tint)
                    .frame(width: FlightDeckAnnunciatorGeometry.accentBarWidth)
                    // The lit marker bleeds a phosphor halo outside its own
                    // silhouette, the same primitive every other lit lamp uses.
                    .phosphorGlow(
                        shape: Rectangle(),
                        tint: tile.tint,
                        radius: FlightDeckMotion.Breathe.glowRadiusMin,
                        intensity: 0.55
                    )
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.count) \(tile.label)")
    }
}

// MARK: - Bridge-link footer

/// The footer that reads the live bridge-socket state from the environment and
/// draws it as an avionics link light: a blinking green lamp and a LINK caption
/// when the socket is up, a static red lamp and NO LINK when it is down. The
/// blink is disabled under Reduce Motion (the lamp holds steady lit), and the
/// caption's casing / tracking neutralize for CJK.
private struct FlightDeckBridgeFooter: View {
    let sessionCount: Int
    let sideInset: CGFloat
    let lang: LanguageManager

    @Environment(\.islandBridgeIsLive) private var bridgeIsLive
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    private var increasesContrast: Bool { colorSchemeContrast == .increased }
    @Environment(\.islandTokens) private var tokens

    private var linkColor: Color {
        bridgeIsLive ? tokens.colors.statusRunning : tokens.colors.statusFailed
    }

    var body: some View {
        HStack(spacing: 7) {
            FlightDeckLinkLamp(color: linkColor, isLive: bridgeIsLive)

            Text(FlightDeckText.caps(lang.t("island.flightDeck.footer.bridgeLink"), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(1.2, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.secondaryTextOpacity, increaseContrast: increasesContrast)))

            Text(FlightDeckText.caps(
                lang.t(bridgeIsLive ? "island.flightDeck.footer.link" : "island.flightDeck.footer.noLink"),
                lang: lang
            ))
            .font(FlightDeckTypography.microLabel)
            .tracking(FlightDeckText.tracking(1.0, lang: lang))
            .foregroundStyle(linkColor)

            Spacer(minLength: 0)

            Text(FlightDeckText.caps(lang.t("island.flightDeck.footer.sessions", sessionCount), lang: lang))
                .font(FlightDeckTypography.microLabel)
                .tracking(FlightDeckText.tracking(0.8, lang: lang))
                .foregroundStyle(tokens.colors.paper.opacity(tokens.colors.text(tokens.colors.tertiaryTextOpacity, increaseContrast: increasesContrast)))
        }
        .padding(.leading, sideInset)
        .padding(.trailing, sideInset)
        .frame(height: 26)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tokens.colors.paper.opacity(tokens.colors.hairline(increaseContrast: increasesContrast)))
                .frame(height: 1)
        }
    }
}

/// The footer's live link lamp: a self-lit status square that blinks while the
/// bridge is up, and holds a steady square when the link is down or under Reduce
/// Motion. A phosphor halo (AB-336, the shared primitive) bleeds outside the
/// square and tracks the blink so the link lamp reads as a lit annunciator, not a
/// flat swatch; a down link holds a steady dim halo.
private struct FlightDeckLinkLamp: View {
    let color: Color
    let isLive: Bool

    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lampOpacity: Double {
        isLive && !reduceMotion ? (blink ? 1 : 0.4) : (isLive ? 1 : 0.85)
    }

    /// The halo tracks the blink (bright at the lit peak, dim at the trough); a
    /// down link keeps a steady low halo.
    private var glowIntensity: Double {
        isLive && !reduceMotion ? (blink ? 0.6 : 0.25) : (isLive ? 0.55 : 0.35)
    }

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(lampOpacity)
            .phosphorGlow(
                shape: Rectangle(),
                tint: color,
                radius: FlightDeckMotion.Breathe.glowRadiusMin,
                intensity: glowIntensity
            )
            .onAppear {
                guard isLive, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    blink = true
                }
            }
            .accessibilityHidden(true)
    }
}
