import AppKit
import SwiftUI
import OpenIslandCore

/// A complete visual identity for the island overlay.
///
/// The theme-arch series (AB-293…298) moved styling into `IslandThemeTokens`,
/// routed every overlay surface through those tokens, formalized `RowActions`
/// and the hover container, and extracted the panel-shell surfaces into
/// standalone slot components. This protocol is the capstone (AB-299): it
/// gathers those tokens, the capability flags and grid strategy, and a factory
/// per slot into one type, so `IslandPanelView` composes the overlay purely
/// from `@Environment(\.islandTheme)` and never names a concrete component.
/// After this, a new theme is "implement the protocol + register it".
///
/// **Granularity.** The Scope for AB-299 lists the theme's slots more finely
/// than there are seams in the view tree — e.g. "sessions summary", "section
/// header" and "footer" are the three regions of the one `sessionList` slot,
/// and "approval / question / completion body" are the actionable bodies drawn
/// inside the one `sessionRow` slot. Each factory below therefore owns a group
/// of Scope slots, noted in its doc comment; a theme controls a bundled slot by
/// swapping the factory that renders it. The shared invariants that are *not*
/// theme-swappable (presentation/display rules, `RowActions` wiring, keyboard
/// shortcuts, hover container, accessibility gates, the attention-is-loudest
/// hierarchy) live in `SessionState` / `AgentSession+Presentation` / the slot
/// components and are documented in `docs/architecture.md`.
///
/// `@MainActor` because every factory builds SwiftUI views; the identity,
/// tokens and capability flags are read on the main actor too (overlay render,
/// panel sizing, Settings). Conformers are stateless value types, so they stay
/// `Sendable` and can be handed around freely.
@MainActor
protocol IslandTheme: Sendable {

    // MARK: Identity

    /// Stable identifier persisted to `UserDefaults` and used for registry
    /// lookup. Never localized — it's data, not display text.
    var id: String { get }

    /// Localized display name (e.g. "Poured Island"), resolved through `lang.t`.
    func name(_ lang: LanguageManager) -> String

    /// Localized one-line descriptor shown under the name in the picker.
    func descriptor(_ lang: LanguageManager) -> String

    // MARK: Styling

    /// The colour / metric / motion tokens injected into `\.islandTokens` for
    /// every descendant surface.
    var tokens: IslandThemeTokens { get }

    // MARK: Capability flags

    /// Whether this theme's rows are safe to rasterize with `.drawingGroup()`.
    /// A flat, opaque-surfaced theme returns `true`; blur/glow themes that would
    /// be flattened by the off-screen render return `false`, and
    /// `IslandSessionRow` drops the `ConditionalDrawingGroup` accordingly.
    var rowIsDrawingGroupSafe: Bool { get }

    /// Whether the opened surface draws a native vibrancy base. Most themes
    /// return `true`; a flat-ink theme returns `false` and the surface falls
    /// back to a solid fill (the same path Reduce Transparency already takes).
    var usesVibrancy: Bool { get }

    // MARK: Geometry strategy

    /// The closed-island agents-grid geometry. A theme typically delegates to
    /// the shared `V6RightSlotView` statics pinned by `AgentsGridLayoutTests`,
    /// which encode one particular grid shape rather than a universal
    /// invariant, so a theme can supply its own matrix instead.
    var agentsGridGeometry: IslandAgentsGridGeometry { get }

    // MARK: Slot factories

    /// Closed-pill content, including the agents-grid right slot.
    /// (Scope: closed-pill content, agents-grid style.)
    func closedPill(
        mode: UnifiedBars.Mode,
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat,
        physicalNotchWidth: CGFloat,
        minWidth: CGFloat,
        showsGlyph: Bool
    ) -> AnyView

    /// The opened panel's header row: usage chips plus the mute / settings /
    /// quit controls. (Scope: opened header, usage chip.)
    func openedHeader(
        providers: [UsageProviderPresentation],
        usesNotchAwareLayout: Bool,
        targetScreen: NSScreen?,
        isSoundMuted: Bool,
        lang: LanguageManager,
        onToggleMute: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> AnyView

    /// One session row, including the approval / question / completion
    /// actionable bodies drawn inside it. (Scope: session row, approval body,
    /// question body, completion body.)
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
    ) -> AnyView

    /// The full grouped session list: overview header, sections, rows, footer.
    /// (Scope: sessions summary, section header, footer.)
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
    ) -> AnyView

    /// The single-session card shown when a notification opened the notch.
    /// (Scope: notification-card chrome.)
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
    ) -> AnyView

    /// Shown in the opened panel when there are no sessions to list.
    /// (Scope: empty state.)
    ///
    /// `workspaceCount` is the number of distinct workspaces across the current
    /// and recent sessions — supplied so a theme can tailor its empty copy
    /// ("no live sessions across N workspaces" vs. a cold "start an agent").
    /// The shipped themes ignore it (zero visual change); it exists as a seam
    /// for the redesign themes (AB-326).
    ///
    /// `installedAgentNames` are the human display names of the agents whose
    /// managed hooks are installed (from `AppModel.installedAgentDisplayNames`),
    /// so a theme can reassure the user that silence means "nothing to do", not
    /// "broken" — Poured 2.0 draws them as a "Hooks installed for …" pill and
    /// hides it when the list is empty (AB-331 · SPEC §3.6/§4J). The shipped
    /// themes ignore it.
    func emptyState(
        lang: LanguageManager,
        hasRecentSessions: Bool,
        workspaceCount: Int,
        installedAgentNames: [String]
    ) -> AnyView

    /// Shown while the app is still probing terminals on a cold launch.
    /// (Scope: bootstrap placeholder.)
    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView

    /// The "install hooks" hint shown while no agent hooks are installed.
    /// (Scope: install hint.)
    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView

    /// The theme's **full** usage-meter surface — the §I "expanded usage view"
    /// (Poured 2.0's 52pt conic dials with reset countdowns and threshold pills).
    /// Distinct from the compact header ring drawn in `openedHeader`.
    ///
    /// Returns `nil` — the default every theme but Poured takes — when the theme
    /// has no dedicated full-meter surface. Hosted by the Settings → Appearance
    /// `meters` preview scenario (and its snapshot) as the standalone usage frame
    /// the mockup §I shows; the live overlay has no usage-expanded opened sub-
    /// state yet (that shared surface change is deferred to the conformance pass).
    /// A protocol requirement (not extension-only) for the same dynamic-dispatch
    /// reason as the AB-330 closed-pill seams.
    func usageMeterCard(providers: [UsageProviderPresentation], lang: LanguageManager) -> AnyView?

    /// The same full-meter surface, but mounted **inside the opened panel body**
    /// (below the session list) rather than in the Settings preview. Returns `nil`
    /// — the default every theme but Halo takes — so no other theme's opened
    /// surface changes. Halo mounts it because its header lane deliberately shows
    /// only one filament per notch lane (G-29), so the meter card is where the
    /// remaining windows, the `resets in …` countdowns and the 22pt threshold
    /// numerals actually reach the product (G-28 / G-34).
    func panelUsageMeterCard(
        providers: [UsageProviderPresentation],
        sideInset: CGFloat,
        lang: LanguageManager
    ) -> AnyView?

    // MARK: Closed-pill ambient seams (AB-330)

    /// An ambient glow the theme casts around the **closed** pill that must
    /// render OUTSIDE the notch morph's shared content `.clipShape` so it can
    /// bleed past the pill silhouette (Poured's attention / working / settle
    /// states). `IslandPanelView` places the returned view *behind* the
    /// closed surface, outside every clip, sized to the closed pill.
    ///
    /// Returns `nil` — the default every theme but Poured takes — for no
    /// external glow, so the closed-surface render tree stays byte-identical.
    /// The spotlight's phase/outcome arrives as `activity` (the same value on
    /// `\.islandClosedPillActivity`) so a theme can fold it into whatever ambient
    /// vocabulary it draws.
    ///
    /// **Declared here (not only in the extension)** so a call through
    /// `any IslandTheme` dynamically dispatches to the conformer's override
    /// rather than statically binding to the extension default — the extension
    /// below supplies the `nil` default so no shipped theme must implement it.
    func closedSurfaceGlow(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?,
        width: CGFloat,
        height: CGFloat
    ) -> AnyView?

    /// R6 · N-1 (PI-M-002): whether the **closed** surface's ambient state
    /// suppresses the body's inner contour hairline for as long as it glows.
    ///
    /// The reference's quiet `.glass` rule (`01-poured-island.html:134`) and its
    /// `lumen` working keyframes (`:187-188`) both carry `--hairline-inset`,
    /// while `attnpulse` (`:193-194`), `settle` (`:198-200`) and A4's inline
    /// glow (`:640`) all OMIT it — the loud states trade the contour edge for
    /// the bloom. Returns `false` — the default every theme but Poured takes —
    /// so their closed surface keeps whatever edge it always drew.
    ///
    /// **Declared here (not only in the extension)** for the same dynamic
    /// dispatch reason as `closedSurfaceGlow`.
    func closedSurfaceSuppressesInnerHairline(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?
    ) -> Bool

    /// The theme's **hover peek**: the narrated surface a 0.15s pointer dwell
    /// reveals on the *collapsed* island, before any click (PI-B-001, mockup
    /// `01-poured-island.html:706-736` for Poured / `06-halo.html:709-721` for
    /// Halo).
    ///
    /// Returns `nil` — the default every theme but Poured and Halo takes — so
    /// their closed-surface render tree stays byte-identical. The content model
    /// (`HaloHoverPeekContent`) is theme-agnostic and resolved once by the host;
    /// this seam only decides how it is *drawn*.
    ///
    /// **Declared here (not only in the extension)** for the same dynamic
    /// dispatch reason as `closedSurfaceGlow`.
    func closedSurfaceHoverPeek(_ context: IslandClosedHoverPeekContext) -> IslandClosedHoverPeek?

    /// Whether a dwell over the *collapsed* island should raise this theme's
    /// peek **instead of** opening the panel (PI-B-001).
    ///
    /// Separate from `closedSurfaceHoverPeek` on purpose. Halo vends a peek view
    /// (so its render path lives in the seam like everyone else's) but keeps
    /// `false` here: its dwell has always run straight to a full open, and
    /// flipping that is a Halo behaviour change no Poured ledger item covers.
    /// Poured's board specifies the peek *as* the dwell endpoint, so it returns
    /// `true`.
    var hoverPeekPreemptsHoverOpen: Bool { get }

    /// Whether this theme draws a hover peek at all (PI-B-001 review
    /// correction · latent S3).
    ///
    /// A cheap, allocation-free capability answer to the question the host used
    /// to answer by asking `closedSurfaceHoverPeek(_:)` — which builds an
    /// `AnyView` and must never be called per-frame just to test a flag. Both
    /// closed-edge gates (`suppressesClosedEdgeForPeek`, `syncHoverPeek`) now
    /// require it, so a theme that draws *no* peek can never zero its own
    /// closed edge with nothing drawn in its place: content availability alone
    /// (`hoverPeekContent != nil`) is theme-agnostic and was not a sufficient
    /// gate. `true` for exactly the two themes that vend a peek view (Halo,
    /// Poured), so their behaviour is unchanged.
    var themeDrawsHoverPeek: Bool { get }

    /// How this theme splits the closed pill's two wings for the current right
    /// slot — the label the lane actually renders, plus any extra left-wing
    /// content width the pill draws beside the glyph (R4 · item 1).
    ///
    /// The shared `V6ClosedPill.*OuterWidth` math reserves the right slot a
    /// width derived from `V6RightSlotView.intrinsicWidth`, which is the `×N`
    /// badge's — fine for the five themes that draw a badge there, wrong for
    /// Halo's §I′ usage compression, which draws a ~145pt filament + `Codex 92%`
    /// + countdown group. Right-aligned into a ~50pt wing on a notched Mac that
    /// group spills *backwards under the physical cutout*, where the hardware
    /// eats it (reproduced and measured on this MacBook: bright content at x
    /// 776.5…847.5 against the 663.5…848.5 cutout — 61.0pt lost). Board §I′ (`06-halo.html:1301-1305`) never asked for that: it
    /// puts the arc + `Codex 94%` on the **left** wing and the countdown alone
    /// on the right. This seam lets Halo declare that split once, so the pill
    /// and the panel's morph-frame width math read the same numbers.
    ///
    /// **Declared here (not only in the extension)** for the same dynamic
    /// dispatch reason as `closedSurfaceGlow`.
    func closedPillWingPlan(
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat
    ) -> IslandClosedPillWingPlan

    /// The ink the closed pill's **traveling** status glyph (`islandGlyphOverlay`,
    /// which the morph mounts once so it can slide into the header) takes for the
    /// current spotlight state — running blue / question gold / permission amber /
    /// outcome tint. Returns `nil` — the default — to leave `UnifiedBars` on its
    /// own paper tone, so every theme but Poured renders the glyph unchanged.
    /// A protocol requirement for the same dynamic-dispatch reason as
    /// `closedSurfaceGlow`.
    func closedGlyphTint(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?
    ) -> Color?

    /// The theme's **traveling** closed-pill glyph itself — not just its tint.
    /// `islandGlyphOverlay` mounts this once and continuously so it can slide
    /// from the closed pill into the opened header instead of fading in place
    /// (AB-243). `closedGlyphTint` above only covers themes whose correct
    /// indicator *is* the theme-agnostic `UnifiedBars` bars; a theme whose
    /// correct shape is something else (Halo's ringed A3 permission dot / A5-A6
    /// outcome marks) has nothing to tint — it needs to vend the whole view.
    ///
    /// Returns the theme-agnostic `UnifiedBars` bar glyph, tinted by
    /// `closedGlyphTint` — the default every theme but Halo takes, exactly
    /// reproducing what `islandGlyphOverlay` built inline before this seam
    /// existed, so the traveling glyph stays byte-identical for every other
    /// theme. **Declared here (not only in the extension)** for the same
    /// dynamic-dispatch reason as `closedGlyphTint`/`closedSurfaceGlow`: a call
    /// through `any IslandTheme` must dispatch to the conformer's override, not
    /// statically bind to the extension's default.
    ///
    /// (Overlay remediation Phase 3B · F3 / Decision D3: additive and isolated,
    /// rather than adding a permission case to `UnifiedBars.Mode` itself —
    /// `Mode` is not `CaseIterable` but is switched over exhaustively with no
    /// `default:` at 7 call sites, so a new case is a compile error at all
    /// seven, three of which would need genuinely new `CAShapeLayer` geometry
    /// in the shared animation engine, for a Halo-only need.)
    func closedTravelingGlyph(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?,
        size: CGFloat
    ) -> AnyView

    // MARK: Surface edge-light seam (AB-341)

    /// A living chrome overlay a theme traces around the **morphing surface
    /// silhouette** — the perimeter edge-light Halo uses as its whole state
    /// channel (SPEC-halo §3a). Composed ONLY at the `IslandPanelView` surface
    /// level and ALWAYS handed the single morphing `OpenedIslandSurfaceShape`
    /// (the exact instance the open/close transition animates), so the returned
    /// overlay can mask an `AngularGradient` with `shape.stroke(...)` and the
    /// ring interpolates in lockstep with the silhouette — never a crossfade.
    /// That shape renders the CLOSED pill silhouette too (`topCornerRadius: 0`,
    /// `bottomCornerRadius: closedNotchHeight/2`), which is why `V6ClosedPillShape`
    /// is deliberately **not** a parameter and the pill's own slot view never
    /// double-renders the ring. `context` carries the resolved ambient state,
    /// closed-vs-opened, and the surface geometry.
    ///
    /// The overlay is placed **unclipped** on top of the surface frame, so a
    /// theme's blooms (colored `.shadow`) bleed past the silhouette — the point
    /// of the grown shadow-inset window tokens (SPEC-halo §1b).
    ///
    /// Returns `nil` — the default every shipped theme takes — for no edge
    /// chrome, so the surface render tree stays byte-identical. **Declared here
    /// (not only in the extension)** for the same dynamic-dispatch reason as the
    /// AB-330 closed-pill seams: a call through `any IslandTheme` must dispatch
    /// to the conformer's override, not statically bind to the extension default.
    func surfaceEdgeOverlay(
        shape: OpenedIslandSurfaceShape,
        context: IslandSurfaceEdgeContext
    ) -> AnyView?

    // MARK: - Question-prompt submit CTA seam (overlay remediation Phase 2A · F1)

    /// A theme-supplied primary CTA for the shared `StructuredQuestionPromptView`
    /// Submit button (`IslandPanelView.swift`), used verbatim by all six themes'
    /// `questionActionBody`.
    ///
    /// `IslandActionButtonStyle` — the button style every theme falls back to —
    /// fills with a flat `Color` and can't express a gradient, is always
    /// `RoundedRectangle`, and always spans the card's full width. Poured/Halo
    /// want an intrinsic-width amber-gradient pill instead. Each theme already
    /// owns the right chrome for this (Poured's
    /// `PouredJumpButtonStyle`/`PouredApprovalButtonLabel`, Halo's
    /// `HaloHeroButton`) — this seam is where a conformer exposes it, rather
    /// than the shared view rebuilding it.
    ///
    /// Returns `nil` — the default every theme takes today — so the card falls
    /// back to `IslandActionButtonStyle`, exactly the rendering every theme
    /// ships now. **Declared here (not only in the extension)** for the same
    /// dynamic-dispatch reason as `closedGlyphTint`/`closedSurfaceGlow`: a call
    /// through `any IslandTheme` must dispatch to the conformer's override, not
    /// statically bind to the extension's default.
    ///
    /// `title` is the fully-resolved button label (submit / send reply / running
    /// multi-select count — `StructuredQuestionPromptView.submitButtonTitle`);
    /// `isEnabled` mirrors `canSubmit` so a conformer can render its own
    /// dimmed/disabled treatment (none of the three source components had one,
    /// since none were previously used behind a togglable `.disabled()`); the
    /// conformer is responsible for invoking `action` on tap and should ignore
    /// taps while `isEnabled` is `false`.
    func questionSubmitButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> AnyView?

    // MARK: - Question-prompt card container seam (overlay remediation Phase 2A-follow-up · F1)

    /// A theme-supplied container for the shared `StructuredQuestionPromptView`'s
    /// content (`IslandPanelView.swift`). The view always drew its own literal
    /// `RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.03))` card with a
    /// matching hairline `strokeBorder` — correct for Poured's layered-glass
    /// identity, but wrong for Halo (remediation plan §2 F1 DO-NOT-FIX
    /// table): Halo is a pure-black void whose only chrome is the 1.5pt
    /// edge-light, so a nested translucent box reads as a second, unwanted card
    /// layered inside `HaloHeroShell`'s own black-fill/ring/glow hero.
    ///
    /// `content` arrives pre-built — the shared view's own padding/frame already
    /// applied — so a conformer only supplies the fill/border/clip-shape around
    /// it, exactly mirroring `questionSubmitButton`'s seam shape.
    ///
    /// Returns `nil` — the default every theme takes today — so the card falls
    /// back to the literal translucent rounded panel every theme has always
    /// drawn. **Declared here (not only in the extension)** for the same
    /// dynamic-dispatch reason as `questionSubmitButton` / `closedGlyphTint` /
    /// `closedSurfaceGlow`: a call through `any IslandTheme` must dispatch to the
    /// conformer's override, not statically bind to the extension's default.
    func questionCardContainer(content: AnyView) -> AnyView?

    // MARK: - Question-prompt pagination seam (overlay remediation Phase 2B · F1a/D1)

    /// The number of `structuredQuestions` `StructuredQuestionPromptView` renders
    /// together on one page.
    ///
    /// `nil` means "no pagination": every question renders in one unbounded
    /// stack, and the keyboard 1-9/Enter wiring stays disabled whenever there
    /// is more than one question
    /// (`StructuredQuestionPromptView.registerKeyboardHandlersIfNeeded`'s pre-D1
    /// guard). This remains the protocol's fallback default; no
    /// currently-registered theme relies on it, since both take a concrete
    /// value below.
    ///
    /// A concrete value opts a theme into the D1 pagination mechanism — **one**
    /// mechanism, not two parallel code paths, because the approved boards
    /// (REMEDIATION-PLAN.md §5 D1) only disagree on *how big* a page is, never
    /// on the underlying machinery:
    /// - `1` (Poured `01-poured-island.html:1154-1205`, Halo
    ///   `06-halo.html:1067-1156`): one question per page — "Question 1 of 2" /
    ///   "1 of 2" with a "Submit & next" / "Next" advance button, then "…2 of
    ///   2" with "Submit". Digits are unambiguous on a one-question page, so
    ///   both themes *gain* keyboard selection they don't have today.
    /// - A size at or past the question count collapses every question onto one
    ///   page, visually identical to the `nil` default's "show everything". But
    ///   unlike `nil` it is a *distinct*, theme-opted-in configuration: the
    ///   keyboard stays active, with digits running **continuously** across the
    ///   stacked questions (1-3 then 4-7, never restarting at 1) — useful for a
    ///   theme whose identity favors showing every active item at once rather
    ///   than paging one at a time.
    ///
    /// The keyboard model is never special-cased per theme — it falls out of
    /// whichever questions land on the *current* page (`StructuredQuestionPromptView
    /// .currentPageFlatOptions`); a one-question page and an every-question page
    /// both feed the same flattening, they just start from a different `currentPage`.
    ///
    /// A plain `Int?` (not a dedicated enum) to match this file's established
    /// "narrow optional protocol member" shape (`closedGlyphTint`,
    /// `questionSubmitButton`) rather than introduce a new type for two concrete
    /// values. **Declared here (not only in the extension)** for the same
    /// dynamic-dispatch reason as `questionSubmitButton` / `closedGlyphTint`: a
    /// call through `any IslandTheme` must dispatch to the conformer's override,
    /// not statically bind to the extension's default.
    var questionPageSize: Int? { get }

    // MARK: - Opened-header band height (overlay remediation Phase 5 · F8)

    /// The opened panel's header-band height — what `IslandPanelView` gives
    /// `openedHeaderContent` (`.frame(height:)`) and what
    /// `OverlayPanelController.panelSize` budgets into the window's total
    /// content height alongside the measured body.
    ///
    /// `nil` — the default every currently-registered theme takes — means "use
    /// the closed pill's own height" (`closedNotchHeight` /
    /// `NSScreen.islandClosedHeight`), exactly the fixed, shared band every
    /// theme has always rendered into. Poured/Halo take this default and are
    /// therefore byte-identical.
    ///
    /// The seam exists for a theme whose opened chrome needs more room: e.g. a
    /// gauge-style summary chip that runs taller than the shared band, once its
    /// controls stack *above* the gauge in the notch lane
    /// (`ControlsLaneArrangement.columnStacked`, `IslandUsageSummary.swift`) and
    /// the band must clear controls (22pt) + spacing (8pt) + the chip + the
    /// header's own top padding (2pt) — well past the closed pill's ~24-38pt
    /// band (`F8`, overlay remediation). Growing this per-theme value, rather
    /// than `closedNotchHeight` itself, keeps the **closed pill** — shared
    /// geometry every theme's morph animates from — completely unaffected.
    ///
    /// **Declared here (not only in the extension)** for the same
    /// dynamic-dispatch reason as `questionPageSize` / `closedGlyphTint`: a
    /// call through `any IslandTheme` must dispatch to the conformer's
    /// override, not statically bind to the extension's default.
    var openedHeaderHeight: CGFloat? { get }
}

/// The uniform "still reads as this theme's own chrome, not a foreign grey"
/// disabled recipe every `questionSubmitButton` override applies (overlay
/// remediation Phase 2A-follow-up · F1): keep the button's own hue, just mute
/// it, rather than falling back to `IslandActionButtonStyle`'s shared grey
/// disabled literal (`IslandPanelView.swift`, `guard isEnabled else { … }`).
/// Neither Poured's `PouredApprovalButtonLabel` nor Halo's `HaloHeroButton` had
/// a disabled state before this — each was only ever mounted while
/// unconditionally actionable — so this is one shared pair (not independently
/// tuned per theme) applied as `.saturation(_:).opacity(_:)` over the
/// conformer's own enabled paint, so a disabled Submit dims consistently
/// across themes instead of drifting per conformer.
enum IslandQuestionSubmitDisabledStyle {
    /// `.saturation()` floor for a disabled themed Submit button.
    static let saturation: Double = 0.35
    /// `.opacity()` floor for a disabled themed Submit button.
    static let opacity: Double = 0.5
}

// MARK: - Closed-pill wing plan (R4 · item 1)

/// How a theme splits the closed pill's two wings around the physical notch.
///
/// Pure value, resolved once per frame by `IslandPanelView` and fed to BOTH the
/// `V6ClosedPill.*OuterWidth` math (which sizes the morph's closed frame) and
/// `theme.closedPill(...)` (which renders it), so the reserved geometry and the
/// drawn content can never disagree — the exact drift that let Halo's §I′ usage
/// group render under the hardware cutout.
struct IslandClosedPillWingPlan: Equatable {
    /// What the notch lane / centre label actually renders. A theme returns
    /// `nil` to drop a label its wing composition has made redundant — Halo's
    /// §I′ pill, whose left wing already reads `Codex 92%`, so a lane label of
    /// `Codex` beside it is a literal duplicate.
    var label: String?

    /// Extra left-wing content width the pill draws between the glyph and the
    /// label lane, in points. `0` for every theme but Halo's §I′ usage lead.
    var leadingAccessoryWidth: CGFloat
}

// MARK: - Closed-surface hover peek seam (PI-B-001)

/// Everything a theme needs to draw its collapsed-island hover peek. Resolved
/// once by `IslandPanelView` (which owns the geometry and the language) and
/// handed across the seam by value, so a theme's peek view never reaches back
/// into the host for layout.
struct IslandClosedHoverPeekContext {
    /// The one actionable session the peek narrates, already resolved from the
    /// surfaced sessions. Theme-agnostic despite the `Halo…` name — see the
    /// naming-debt note on `HaloHoverPeekContent`.
    var content: HaloHoverPeekContent
    var lang: LanguageManager
    /// Upper bound from the host: the peek never renders wider than the
    /// island's own surface, so a narrow display clamps it.
    var availableWidth: CGFloat
    /// The closed pill's outer width for this placement.
    var closedPillWidth: CGFloat
    /// The closed pill's band height (its own silhouette height).
    var closedPillHeight: CGFloat
    /// Which top edge the collapsed island has here — a notched Mac's concave
    /// fillet junction, or a plain top-bar pill.
    var topProfile: OpenedIslandSurfaceShape.TopProfile
}

/// A theme's rendered hover peek plus the two facts the host needs to compose
/// the frame around it.
struct IslandClosedHoverPeek {
    /// The peek body itself.
    var body: AnyView

    /// The bottom radius of the silhouette the peek presents, so the host's
    /// perimeter edge overlay (Halo's edge-light) traces the same outline the
    /// body draws.
    var bottomCornerRadius: CGFloat

    /// `true` → the peek IS the collapsed island for as long as it is up (the
    /// board's §B frame draws the grown body with **no** wings), so the host
    /// hides the closed pill underneath it and the peek carries the whole glass
    /// treatment. `false` → the peek docks *under* a still-visible pill and
    /// leaves the pill's own body alone (Halo).
    var replacesClosedSurface: Bool
}

// MARK: - Closed-pill ambient seam defaults (AB-330)

extension IslandTheme {
    /// Default: the theme draws no hover peek at all.
    func closedSurfaceHoverPeek(_ context: IslandClosedHoverPeekContext) -> IslandClosedHoverPeek? { nil }

    /// Default: a dwell opens the panel, exactly as it always has.
    var hoverPeekPreemptsHoverOpen: Bool { false }

    /// Default: the theme draws no hover peek, so no peek-driven closed-edge
    /// suppression can ever apply to it.
    var themeDrawsHoverPeek: Bool { false }

    /// Default: no external closed-pill glow. Every theme but Poured takes this.
    func closedSurfaceGlow(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?,
        width: CGFloat,
        height: CGFloat
    ) -> AnyView? { nil }

    /// Default: the closed surface's inner edge never changes with the ambient
    /// state. Every theme but Poured takes this.
    func closedSurfaceSuppressesInnerHairline(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?
    ) -> Bool { false }

    /// Default: leave the traveling glyph on its own paper tone.
    func closedGlyphTint(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?
    ) -> Color? { nil }

    /// Default: the theme-agnostic `UnifiedBars` bar glyph, tinted by
    /// `closedGlyphTint` — exactly what `islandGlyphOverlay` built inline
    /// before this seam existed. Every theme but Halo takes this, so their
    /// traveling glyph's render tree (and therefore its pixels) is unchanged.
    func closedTravelingGlyph(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?,
        size: CGFloat
    ) -> AnyView {
        AnyView(
            UnifiedBars(
                mode: mode,
                size: size,
                tint: closedGlyphTint(mode: mode, rightSlot: rightSlot, activity: activity)
            )
        )
    }

    /// Default: the wings the shared `V6ClosedPill` math has always assumed —
    /// the resolved label in the lane and nothing extra beside the glyph. Every
    /// theme but Halo takes this, so their closed-pill widths and contents are
    /// byte-identical (R4 · item 1).
    func closedPillWingPlan(
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat
    ) -> IslandClosedPillWingPlan {
        IslandClosedPillWingPlan(label: label, leadingAccessoryWidth: 0)
    }

    /// Default: no dedicated full-meter surface. Every theme but Poured takes
    /// this, so the `meters` preview keeps drawing only the compact header ring.
    func usageMeterCard(providers: [UsageProviderPresentation], lang: LanguageManager) -> AnyView? { nil }

    /// Default: nothing extra in the opened panel body. Every theme but Halo takes
    /// this, so their opened surfaces are unchanged.
    func panelUsageMeterCard(
        providers: [UsageProviderPresentation],
        sideInset: CGFloat,
        lang: LanguageManager
    ) -> AnyView? { nil }

    /// Default: no surface edge-light. Every shipped theme takes this, so the
    /// morph / Reduce-Motion surfaces stay byte-identical (AB-341). Halo (Part 2)
    /// overrides it with the `HaloEdgeLight` masked-gradient ring.
    func surfaceEdgeOverlay(
        shape: OpenedIslandSurfaceShape,
        context: IslandSurfaceEdgeContext
    ) -> AnyView? { nil }

    /// Default: no themed CTA — `StructuredQuestionPromptView` falls back to
    /// `IslandActionButtonStyle`, the protocol's fallback for a theme that
    /// doesn't override it. Poured/Halo override it (overlay remediation Phase
    /// 2A-follow-up · F1).
    func questionSubmitButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> AnyView? { nil }

    /// Default: no themed card container — the shared view keeps drawing its
    /// own literal translucent rounded card. Poured takes this default (its
    /// layered glass already reads correctly with the literal card nested
    /// inside its own gold wash); Halo overrides it (overlay remediation Phase
    /// 2A-follow-up · F1).
    func questionCardContainer(content: AnyView) -> AnyView? { nil }

    /// Default: no pagination — every question renders on one page and
    /// `registerKeyboardHandlersIfNeeded` keeps multi-question keyboard
    /// selection disabled (its pre-D1 behaviour); this remains the protocol's
    /// fallback for a theme that doesn't opt in. Poured/Halo override it
    /// (overlay remediation Phase 2B · F1a/D1).
    var questionPageSize: Int? { nil }

    /// Default: use the closed pill's own height — the shared, unchanged
    /// band every theme has always rendered its opened header into.
    /// Poured/Halo take this default and are therefore byte-identical
    /// (overlay remediation Phase 5 · F8).
    var openedHeaderHeight: CGFloat? { nil }
}

/// The closed-island agents-grid geometry a theme supplies. Expressed as plain
/// functions (rather than a subclass) so a theme can delegate straight to the
/// `V6RightSlotView` statics, which stay the single implementation the layout
/// math and `AgentsGridLayoutTests` share.
struct IslandAgentsGridGeometry {
    /// Per-row cell counts for `n` sessions (the hand-tuned balanced matrix).
    var balancedRows: (Int) -> [Int]

    /// Cell size / gap / corner radius for a matrix with `rowCount` rows.
    var cellGeometry: (Int) -> (cell: CGFloat, gap: CGFloat, radius: CGFloat)
}

// MARK: - Environment

private struct IslandThemeKey: EnvironmentKey {
    static let defaultValue: any IslandTheme = PouredIslandTheme()
}

extension EnvironmentValues {
    /// The active island theme.
    ///
    /// Defaults to `PouredIslandTheme` — the look Open Island ships today — so a
    /// view that reads this without an explicit injection renders unchanged,
    /// mirroring `\.islandTokens`. `IslandPanelView` injects the model's active
    /// theme (and its `tokens`) at the overlay root.
    var islandTheme: any IslandTheme {
        get { self[IslandThemeKey.self] }
        set { self[IslandThemeKey.self] = newValue }
    }
}
