import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Poured parity Slice 3 · PI-B-001 — the §B hover peek
/// (`docs/design/overlay-redesign/01-poured-island.html:706-736`).
///
/// Three seams are pinned here, all view-free:
/// 1. the **decision** a completed dwell makes (peek vs. open) per theme and per
///    session state,
/// 2. the model's peek state transitions, and
/// 3. the **theme seam** that replaced `IslandPanelView`'s old
///    `theme.id == "halo"` gate, including the fact that Halo's peek came across
///    it unchanged.
@MainActor
struct PouredHoverPeekTests {

    private var lang: LanguageManager { LanguageManager() }

    private func model(theme: String, scenario: IslandDebugScenario) -> AppModel {
        let model = AppModel()
        model.islandThemeID = theme
        model.loadDebugSnapshot(scenario.snapshot(), presentOverlay: false)
        model.notchStatus = .closed
        return model
    }

    private func peekContext(_ content: HaloHoverPeekContent) -> IslandClosedHoverPeekContext {
        IslandClosedHoverPeekContext(
            content: content,
            lang: lang,
            availableWidth: 520,
            closedPillWidth: 352,
            closedPillHeight: 32,
            topProfile: .notch
        )
    }

    // MARK: - Decision

    /// Board §B: the dwell's endpoint under Poured is the peek — "the single
    /// continuously-morphing shape begins to grow and surfaces the one
    /// actionable item — *before* a full open" (`:706-709`).
    @Test
    func pouredDwellPeeksWhenSomethingIsWaiting() {
        let model = model(theme: "poured", scenario: .closedAttentionQueue)
        #expect(model.hoverBehaviorForClosedSurface() == .peek)
        #expect(model.closedSurfaceHoverPeekContent() != nil)
    }

    /// With nothing blocked on the user the board draws no peek frame at all, so
    /// the dwell must keep doing what it always did rather than swallowing the
    /// gesture into an empty surface.
    @Test
    func pouredDwellStillOpensWhenNothingIsWaiting() {
        let model = model(theme: "poured", scenario: .closed)
        #expect(model.closedSurfaceHoverPeekContent() == nil)
        #expect(model.hoverBehaviorForClosedSurface() == .openPanel)
    }

    // MARK: - State transitions

    @Test
    func peekRaisesOnlyFromTheCollapsedIslandAndRetiresOnOpen() {
        let model = model(theme: "poured", scenario: .closedAttentionQueue)
        #expect(model.hoverPeekActive == false)

        model.beginHoverPeek()
        #expect(model.hoverPeekActive)

        // The measured body is what the controller hit-tests against while the
        // peek is up; retiring must clear it so a stale rect can never keep a
        // vanished peek "hovered".
        model.hoverPeekSurfaceSize = CGSize(width: 404, height: 74)
        model.endHoverPeek()
        #expect(model.hoverPeekActive == false)
        #expect(model.hoverPeekSurfaceSize == .zero)

        // Opening retires the peek in the same transaction …
        model.beginHoverPeek()
        #expect(model.hoverPeekActive)
        model.notchStatus = .opened
        #expect(model.hoverPeekActive == false)

        // … and an opened island can never raise one.
        model.beginHoverPeek()
        #expect(model.hoverPeekActive == false)
    }

    // MARK: - Theme seam

    /// Poured's peek *replaces* the collapsed surface — the board's rendered
    /// frame draws the grown body with no wings — and carries the board's own
    /// 20pt bottom radius (`:717`).
    @Test
    func pouredVendsAReplacingPeekAtTheBoardsRadius() throws {
        let sessions = IslandDebugScenario.closedAttentionQueue.snapshot().sessions
        let content = try #require(HaloHoverPeekContent.resolve(sessions: sessions, lang: lang))
        let peek = try #require(PouredIslandTheme().closedSurfaceHoverPeek(peekContext(content)))

        #expect(peek.replacesClosedSurface)
        #expect(peek.bottomCornerRadius == PouredHoverPeek.cornerRadius)
        #expect(PouredHoverPeek.cornerRadius == 20)
        #expect(PouredHoverPeek.preferredWidth == 404)
        #expect(PouredIslandTheme().hoverPeekPreemptsHoverOpen)
    }

    /// R6 ruling on N-3 (PI-B-001): the **rendered** board is golden, and it
    /// draws the §B peek frame at `transform:scale(1.0)`
    /// (`01-poured-island.html:717`). The `scale 1.03` in the §B prose (`:707`)
    /// and the `.pill.hover-lift` rule (`:157`) are applied to no element in the
    /// document, so a model-driven peek no longer lifts the collapsed surface.
    ///
    /// The transient pointer-only hover keeps the `closedHoverScale` token —
    /// the board renders no bare-hover frame, so the prose invariant stands
    /// there uncontradicted.
    @Test
    func peekRendersAtTheBoardsScaleOfOneWhileBareHoverKeepsTheLift() {
        let lift = IslandThemeTokens.poured.metrics.closedHoverScale
        #expect(lift == 1.03)

        // Peek up, pointer not over the (event-transparent) closed window: 1.
        #expect(IslandPanelView.closedSurfaceScale(
            opened: false, isHovering: false, hoverPeekActive: true, hoverScale: lift
        ) == 1)
        // Bare hover, no peek: the shipped lift.
        #expect(IslandPanelView.closedSurfaceScale(
            opened: false, isHovering: true, hoverPeekActive: false, hoverScale: lift
        ) == lift)
        // Opened never scales, whatever the pointer is doing.
        #expect(IslandPanelView.closedSurfaceScale(
            opened: true, isHovering: true, hoverPeekActive: true, hoverScale: lift
        ) == 1)
    }

    // MARK: - Shared content model

    /// The peek's copy comes from the *shared* resolver, and now carries the two
    /// extra facts Poured's §B head row needs that Halo's never did: the raw
    /// workspace (so Poured can phrase the line from its own
    /// `island.poured.peek.*` table) and the lead session's agent (the brand-dot
    /// chip at `:723`).
    @Test
    func sharedContentCarriesWorkspaceAndAgentForThePouredChip() throws {
        let sessions = IslandDebugScenario.closedAttentionQueue.snapshot().sessions
        let content = try #require(HaloHoverPeekContent.resolve(sessions: sessions, lang: lang))

        #expect(content.kind == .permission)
        #expect(content.moreWaiting == 1)
        #expect(content.workspace.isEmpty == false)
        #expect(content.title.contains(content.workspace))
        #expect(content.agent != nil)
    }

}
