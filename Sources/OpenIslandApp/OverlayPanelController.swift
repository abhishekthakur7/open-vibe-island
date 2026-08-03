import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import OpenIslandCore

@MainActor
final class OverlayPanelController {
    /// Single source of truth with `V6ClosedPill.macbookMaxOuterWidth`, which
    /// budgets the closed pill's notch-lane label against exactly this number
    /// (G-20) — the closed silhouette must never be wider than the panel it
    /// grows into.
    private static let preferredNotchOpenedPanelWidth: CGFloat = V6ClosedPill.macbookMaxOuterWidth
    private static let preferredTopBarOpenedPanelWidth: CGFloat = 520
    private static let openedContentWidthPadding: CGFloat = 0
    private static let openedContentBottomPadding: CGFloat = 0
    /// Small cushion added on top of the SwiftUI-measured content height
    /// (AB-228). The measured value can land a couple of points short of
    /// what's actually needed depending on which padding/inset layer the
    /// measuring `GeometryReader` sits under; a few points of headroom here
    /// is far cheaper to reason about than chasing that discrepancy, and
    /// erring tall avoids reintroducing clipping.
    private static let measuredContentSafetyPadding: CGFloat = 8
    /// Floor / pre-measurement fallback height for the opened content area:
    /// the `panelSize` minimum so the window never shrinks below it, and the
    /// value `openedContentHeight` returns before SwiftUI has reported a real
    /// `GeometryReader` measurement for the current frame (any content case,
    /// not just the empty state — see overlay remediation Phase 5's fix to
    /// `openedContentHeight`, which stopped force-applying this constant
    /// whenever `islandListSessions.isEmpty` regardless of the real measured
    /// height). Themes' empty-state bodies are no longer guaranteed to fit
    /// this constant — Flight Deck's and Halo's 2.0 bodies exceed it — so it
    /// must never be treated as their final height, only as the value shown
    /// for the one frame before measurement lands.
    private static let openedEmptyStateHeight: CGFloat = 108

    private var panel: NotchPanel?
    private var eventMonitors = NotchEventMonitors()
    private var keyCommandMonitor: Any?
    private var hoverTimer: DispatchWorkItem?
    private var hoverCancelGrace: DispatchWorkItem?
    weak var model: AppModel?
    private(set) var notchRect: NSRect = .zero

    var isVisible: Bool {
        panel?.isVisible == true
    }

    nonisolated static func shouldActivatePanel(for reason: NotchOpenReason?) -> Bool {
        reason == .click
    }

    func availableDisplayOptions() -> [OverlayDisplayOption] {
        OverlayDisplayResolver.availableDisplayOptions()
    }

    func ensurePanel(model: AppModel, preferredScreenID: String?) {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        positionPanel(panel, preferredScreenID: preferredScreenID, animated: false)
        panel.orderFrontRegardless()
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        startEventMonitoring()
    }

    func show(model: AppModel, preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        self.model = model
        let panel = self.panel ?? makePanel(model: model)
        self.panel = panel
        let diagnostics = positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)
        presentPanel(panel, activates: Self.shouldActivatePanel(for: model.notchOpenReason))
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        startEventMonitoring()
        return diagnostics
    }

    func hide() {
        panel?.ignoresMouseEvents = true
        panel?.acceptsMouseMovedEvents = false
    }

    func setInteractive(_ interactive: Bool) {
        guard let panel else {
            return
        }

        panel.ignoresMouseEvents = !interactive
        panel.acceptsMouseMovedEvents = interactive

        if interactive {
            presentPanel(panel, activates: Self.shouldActivatePanel(for: model?.notchOpenReason))
        }
    }

    func reposition(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        guard let panel else {
            return placementDiagnostics(preferredScreenID: preferredScreenID)
        }

        return positionPanel(panel, preferredScreenID: preferredScreenID, animated: true)
    }

    func placementDiagnostics(preferredScreenID: String?) -> OverlayPlacementDiagnostics? {
        let panelSize = panel?.frame.size ?? OverlayDisplayResolver.defaultPanelSize
        return OverlayDisplayResolver.diagnostics(preferredScreenID: preferredScreenID, panelSize: panelSize)
    }

    // MARK: - Panel creation

    private func makePanel(model: AppModel) -> NotchPanel {
        let screen = resolveTargetScreen() ?? NSScreen.main
        let windowFrame = screen.map { panelFrame(for: model, on: $0) } ?? .zero

        let panel = NotchPanel(
            contentRect: windowFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .statusBar
        panel.sharingType = .readOnly
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = false
        // `.stationary` keeps the overlay pinned during the macOS Sonoma+
        // "click wallpaper to reveal desktop" gesture (and Mission Control
        // / Show Desktop). Without it the panel slides off-screen with the
        // user's other windows — on built-in notch displays it disappears
        // below the menu bar, and on external displays it falls out of the
        // top bar entirely.
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.ignoresMouseEvents = true

        let hostingView = NotchHostingView(rootView: IslandPanelView(model: model))
        hostingView.notchController = self
        panel.contentView = hostingView

        computeNotchRect(screen: resolveTargetScreen())
        return panel
    }

    // MARK: - Positioning

    @discardableResult
    private func positionPanel(
        _ panel: NSPanel,
        preferredScreenID: String?,
        animated: Bool
    ) -> OverlayPlacementDiagnostics? {
        guard let screen = resolveTargetScreen(preferredScreenID: preferredScreenID) else {
            return nil
        }

        let windowFrame = panelFrame(for: model, on: screen)

        // Always set the panel frame instantly — no AppKit animation.
        // All visual transitions (shape, size, opacity, corner radius) are
        // driven by SwiftUI's .animation() modifier on the content view.
        // Mixing NSAnimationContext with SwiftUI spring animations caused
        // visible jank because the two systems have different timing curves,
        // durations, and start times (AppKit was deferred by one runloop).
        if panel.frame != windowFrame {
            panel.setFrame(windowFrame, display: true)
        }
        computeNotchRect(screen: screen)

        return OverlayDisplayResolver.diagnostics(
            preferredScreenID: preferredScreenID,
            panelSize: panel.frame.size
        )
    }

    private func presentPanel(_ panel: NSPanel, activates: Bool) {
        if activates {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    private func computeNotchRect(screen: NSScreen?) {
        guard let screen else {
            notchRect = .zero
            return
        }

        let notchSize = screen.notchSize
        let screenFrame = screen.frame
        let notchX = screenFrame.midX - notchSize.width / 2
        let notchY = screenFrame.maxY - notchSize.height
        notchRect = NSRect(x: notchX, y: notchY, width: notchSize.width, height: notchSize.height)
    }

    /// Picks the screen to anchor the overlay to.
    ///
    /// Priority: persisted manual preference (matched via the stable
    /// `OverlayDisplayResolver.screenID` so a hotplug-reassigned
    /// `CGDirectDisplayID` can't silently re-target the wrong monitor) →
    /// first notched screen → `NSScreen.main` → first available screen.
    /// Returns `nil` only when no displays are connected.
    private func resolveTargetScreen(preferredScreenID: String? = nil) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }

        if let preferredScreenID,
           let screen = screens.first(where: { OverlayDisplayResolver.screenID(for: $0) == preferredScreenID }) {
            return screen
        }

        if let notchScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }

        return NSScreen.main ?? screens[0]
    }

    // MARK: - Mouse event monitoring

    private func startEventMonitoring() {
        let disablesForHarness = model?.disablesOverlayEventMonitoringDuringHarness == true

        // The key monitor installs whenever the harness isn't disabling
        // event monitoring at all, OR it is but verification has explicitly
        // opted back in (`AppModel.enablesOverlayKeyMonitorDuringHarness`,
        // overlay remediation Phase 3 Task 1 — doc comment there has the
        // full history). Before that override existed this whole function
        // returned early for *any* harness scenario launch, so a
        // harness-launched panel never installed `keyCommandMonitor` at
        // all — pressing `1`/Enter had zero effect, and the verification
        // protocol's interactive mode could not exercise keyboard handling
        // for any theme.
        if keyCommandMonitor == nil,
           !disablesForHarness || model?.enablesOverlayKeyMonitorDuringHarness == true {
            keyCommandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.handleOverlayKeyDown(event) else { return event }
                return nil
            }
        }

        // Mouse monitoring stays governed solely by
        // `disablesOverlayEventMonitoringDuringHarness`, opt-in or not — an
        // automated capture run shouldn't have the host's real cursor
        // driving hover-open/auto-collapse, and nothing about keyboard
        // verification needs it.
        if disablesForHarness {
            return
        }

        guard !eventMonitors.isActive else { return }

        eventMonitors.start { [weak self] location in
            self?.handleMouseMoved(location)
        } mouseDownHandler: { [weak self] location in
            self?.handleMouseDown(location)
        }
    }

    // MARK: - Keyboard shortcuts (AB-227)

    /// Handles keyboard shortcuts on the visible approval/question card.
    /// Returns `true` when the event was fully handled (the caller swallows
    /// it); `false` lets it continue through normal AppKit dispatch.
    ///
    /// Focus guard: while a text field on the card is being edited (Reply /
    /// "Other" freeform fields), everything except Esc passes through
    /// untouched so typing digits or pressing Enter behaves like normal
    /// text entry — see `ReplyTextField`'s own IME-safe Enter handling.
    private func handleOverlayKeyDown(_ event: NSEvent) -> Bool {
        guard let model, model.isOverlayVisible,
              let panel, panel.isKeyWindow else {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Plain Esc only — leave modified combos (e.g. ⌘⌥Esc Force Quit)
        // alone rather than reinterpreting them as "close the overlay".
        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty {
            // R8 (owner ruling, 2026-08-02) — two-stage Esc. With a hero
            // (permission / question / detail) open **inside** the expanded
            // Poured list, the first Esc collapses it back to its compact row
            // and keeps the list context; only the second Esc closes the panel.
            //
            // `requestCollapse()` returns false when no in-list hero is open —
            // which is every other surface, every other theme, and the
            // notification card's auto-expanded single row — so Esc keeps its
            // shipped close-the-panel meaning everywhere the ruling does not
            // reach. The theme check is redundant with that (only
            // `PouredSessionRow` ever registers a hero) and is spelled out
            // anyway so the Poured gate is legible at the call site.
            switch Self.escapeStage(
                themeID: model.islandTheme.id,
                hasOpenInListHero: PouredHeroExpansion.shared.openHeroSessionID != nil
            ) {
            case .collapseHero:
                PouredHeroExpansion.shared.requestCollapse()
            case .closePanel:
                model.notchClose()
            }
            return true
        }

        guard !(panel.firstResponder is NSText) else {
            return false
        }

        let characters = event.charactersIgnoringModifiers?.lowercased()

        if flags.contains(.command), characters == "y" {
            return flags.contains(.shift)
                ? handleAlwaysAllowShortcut(model)
                : handleApprovalShortcut(model, action: .allowOnce)
        }

        if flags.contains(.command), characters == "n" {
            return handleApprovalShortcut(model, action: .deny)
        }

        if flags.contains(.command), characters == "j" {
            return handleJumpShortcut(model)
        }

        // Slice 5 gap 6, §F half. Unlike the ⌘-shortcuts above, Enter / 1–9 do
        // not select a session here at all: they call whichever
        // `StructuredQuestionPromptView` is mounted, through the single
        // `QuestionCardKeyboardHandlers` slot it registers on appear and clears
        // on disappear (`IslandPanelView.registerKeyboardHandlersIfNeeded`).
        // Inside the expanded Poured list only the **open** §F hero mounts that
        // interior — a compact question row draws an `Answer` chip and no
        // prompt (PI-C-006) — so the registered slot already *is* the open
        // hero's, and R8 stage 1 clears it on the way out. That is why these
        // two branches need no `PouredHeroExpansion` lookup while ⌘Y / ⌘N do:
        // the question keys follow the mounted view, the approval keys followed
        // the selected card.
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            return model.overlay.handleQuestionSubmitKey()
        }

        if let characters, characters.count == 1,
           let digit = Int(characters), (1...9).contains(digit) {
            return model.overlay.handleQuestionOptionKey(digit - 1)
        }

        return false
    }

    /// R8 stage selection, as a pure decision so the two-stage contract can be
    /// pinned without standing up an `NSPanel` (the idiom every other decision
    /// in this controller already uses).
    enum EscapeStage: Equatable {
        /// Collapse the open in-list hero back to its compact row; the list, and
        /// the panel, stay.
        case collapseHero
        /// The shipped meaning: close the overlay.
        case closePanel
    }

    nonisolated static func escapeStage(themeID: String, hasOpenInListHero: Bool) -> EscapeStage {
        // Poured-only by ruling, and by construction: `PouredSessionRow` is the
        // only view that ever registers an in-list hero, so the second term is
        // already false everywhere else. Spelled out so the gate is legible.
        (themeID == "poured" && hasOpenInListHero) ? .collapseHero : .closePanel
    }

    /// The session ⌘Y / ⌘⇧Y / ⌘N actually act on, as a pure choice between the
    /// open in-list hero and the selected card.
    nonisolated static func approvalShortcutSessionID(
        openHeroSessionID: String?,
        activeCardSessionID: String?
    ) -> String? {
        openHeroSessionID ?? activeCardSessionID
    }

    /// The session ⌘Y / ⌘⇧Y / ⌘N actually act on.
    ///
    /// Slice 5 gap 6: `activeIslandCardSession` is the *notification/selected*
    /// session (`islandSurface.sessionID`). A §E hero opened in place inside the
    /// expanded Poured list is usually not that session, so before this the hero
    /// drew ⌘Y / ⌘N keycaps that fired on a different row — or on nothing at
    /// all. `PouredHeroExpansion.openHeroSessionID` is precisely "the hero the
    /// user opened in the list" (R9's in-place expansion), so it takes
    /// precedence; with no hero open, or when the recorded id no longer resolves
    /// to a live session, the shipped selected-card behaviour is unchanged.
    private func approvalShortcutSession(_ model: AppModel) -> AgentSession? {
        let id = Self.approvalShortcutSessionID(
            openHeroSessionID: PouredHeroExpansion.shared.openHeroSessionID,
            activeCardSessionID: model.activeIslandCardSession?.id
        )
        guard let id else { return nil }
        return model.state.session(id: id) ?? model.activeIslandCardSession
    }

    /// What ⌘Y / ⌘N do once a session has been resolved — a pure decision so the
    /// E5 contract can be pinned without an `NSPanel`, the idiom `escapeStage`
    /// and `approvalShortcutSessionID` already use.
    enum ApprovalShortcutOutcome: Equatable {
        /// The shipped path: resolve the request in-app.
        case approve
        /// E5: a `requiresTerminalApproval` request cannot be resolved in-app at
        /// all, so the honest act behind the advertised cap is the jump.
        case jump
        /// Nothing to do — the key falls through to normal AppKit dispatch
        /// rather than being swallowed.
        case ignore
    }

    /// E5 (Poured Slice 5): the board prints `⌘Y` on E3's blue
    /// "Jump to Codex to approve" primary (`01-poured-island.html:1106-1108`),
    /// and a printed keycap must fire — the keycap-truth rule this slice
    /// enforced everywhere else. E3 is the `requiresTerminalApproval` shape:
    /// nothing in this app can approve it, and the card's own CTA (and ⌘J)
    /// already perform exactly one thing — jump. So ⌘Y performs that same jump
    /// instead of bailing.
    ///
    /// Deliberately narrow. `⌘N` (deny) keeps bailing: E3 prints no deny cap and
    /// jumping on a deny key would be a lie in the other direction. `⌘⇧Y` never
    /// reaches here (`handleAlwaysAllowShortcut` is its own path, untouched).
    /// And the theme term keeps every other theme byte-identical — Poured's E3
    /// is the only surface that prints `⌘Y` on a terminal-approval card, so
    /// nowhere else gains a binding it does not advertise.
    nonisolated static func approvalShortcutOutcome(
        themeID: String,
        action: ApprovalAction,
        requiresTerminalApproval: Bool
    ) -> ApprovalShortcutOutcome {
        guard requiresTerminalApproval else { return .approve }
        guard themeID == "poured", case .allowOnce = action else { return .ignore }
        return .jump
    }

    private func handleApprovalShortcut(_ model: AppModel, action: ApprovalAction) -> Bool {
        guard let session = approvalShortcutSession(model), session.phase == .waitingForApproval else {
            return false
        }
        switch Self.approvalShortcutOutcome(
            themeID: model.islandTheme.id,
            action: action,
            requiresTerminalApproval: session.permissionRequest?.requiresTerminalApproval == true
        ) {
        case .approve:
            model.approvePermission(for: session.id, action: action)
            return true
        case .jump:
            // The session ⌘Y resolved — the open in-list hero when there is one
            // — not `activeIslandCardSession`, because the cap is printed on
            // that hero and must act on the row the user is looking at.
            return jumpIfReachable(model, session: session)
        case .ignore:
            return false
        }
    }

    /// N3: the presented card's Jump action, fired by ⌘J — the *same*
    /// `jumpToSession` round-trip the Jump CTA button calls, so the keycap the
    /// Halo Codex hero prints (`06-halo.html:1056`) names a real binding rather
    /// than decorating one. Deliberately inert (returns `false`, the event
    /// continues through normal AppKit dispatch) whenever the card has no
    /// reachable jump target, which is also `jumpToSession`'s own precondition —
    /// so a swallowed key never leaves a "Cannot jump" message behind. Themes
    /// that print no ⌘J simply gain a shortcut they do not advertise.
    private func handleJumpShortcut(_ model: AppModel) -> Bool {
        guard let session = model.activeIslandCardSession else { return false }
        return jumpIfReachable(model, session: session)
    }

    /// The jump itself, split out of `handleJumpShortcut` unchanged so E5's ⌘Y
    /// route performs the identical round-trip (same reachability precondition,
    /// same inert-on-unreachable return) on a session it picked itself.
    private func jumpIfReachable(_ model: AppModel, session: AgentSession) -> Bool {
        guard let jumpTarget = session.jumpTarget,
              jumpTarget.terminalApp.lowercased() != "unknown" else {
            return false
        }
        model.jumpToSession(session)
        return true
    }

    /// AB-235: prefers the first of Claude's actual `suggestedUpdates` (the
    /// scoped always-allow options rendered as stacked buttons on the card)
    /// so the shortcut applies the same real, correctly-scoped rule a click
    /// would. Falls back to synthesizing the original generic session-scoped
    /// rule when the request carried no suggestions (e.g. non-Claude agents),
    /// so the shortcut keeps working exactly as it did before AB-235.
    private func handleAlwaysAllowShortcut(_ model: AppModel) -> Bool {
        guard let session = approvalShortcutSession(model),
              session.phase == .waitingForApproval,
              let permissionRequest = session.permissionRequest,
              !permissionRequest.requiresTerminalApproval else {
            return false
        }

        if let firstSuggestedUpdate = permissionRequest.suggestedUpdates.first {
            model.approvePermission(for: session.id, action: .allowWithUpdates([firstSuggestedUpdate]))
            return true
        }

        guard let toolName = permissionRequest.toolName else {
            return false
        }

        let rule = ClaudePermissionRuleValue(toolName: toolName)
        let update = ClaudePermissionUpdate.addRules(destination: .session, rules: [rule], behavior: .allow)
        model.approvePermission(for: session.id, action: .allowWithUpdates([update]))
        return true
    }

    private func handleMouseMoved(_ screenLocation: NSPoint) {
        guard let model else { return }

        // PI-B-001: while the peek is up the *grown* body is the island, so the
        // dwell area grows with it — otherwise a pointer moving a few points
        // down onto the surface the dwell just revealed would read as "left the
        // island" and retire it a tenth of a second after it appeared.
        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)
            || isPointInHoverPeekArea(screenLocation, model: model)

        if model.notchStatus == .closed && inClosedSurfaceArea {
            scheduleHoverOpen()
        } else if model.notchStatus == .closed && !inClosedSurfaceArea {
            cancelHoverIntent()
        }

        let shouldTrackNotificationPointer = model.notchStatus == .opened
            && model.notchOpenReason == .notification
            && model.showsNotificationCard

        if shouldTrackNotificationPointer || model.shouldAutoCollapseOnMouseLeave {
            if isPointInExpandedArea(screenLocation) {
                model.notePointerInsideIslandSurface()
            } else {
                model.handlePointerExitedIslandSurface()
            }
        }
    }

    private func handleMouseDown(_ screenLocation: NSPoint) {
        guard let model else { return }

        // PI-B-001: the peek's own body is part of the collapsed island's click
        // target — its hint literally reads "Click to review & approve", so a
        // click that lands on the narration must open, not fall through.
        let inClosedSurfaceArea = isPointInClosedSurfaceArea(screenLocation)
            || isPointInHoverPeekArea(screenLocation, model: model)

        if model.notchStatus == .closed && inClosedSurfaceArea {
            cancelHoverOpenImmediately()
            // PI-B-001: the click the peek's hint promises is this very gesture.
            // Retire the peek first, without grace, so the open starts from the
            // collapsed silhouette and the two surfaces never overlap.
            model.endHoverPeek()
            model.notchOpen(reason: .click)
        } else if model.notchStatus == .opened {
            if !isPointInExpandedArea(screenLocation), !isPointInsidePanelWindow(screenLocation) {
                model.notchClose()
                repostMouseDown(at: screenLocation)
            }
        }
    }

    /// G-61 (second half): a click anywhere over the overlay's own window is
    /// never an "outside click".
    ///
    /// `isPointInExpandedArea` deliberately answers a narrower question — the
    /// *interactive* rect, i.e. the window minus the transparent ring reserved
    /// for the surface's drop shadow and the theme's blooms (40 × 48pt for
    /// Halo). Treating that ring as outside meant a click that visually landed
    /// on the panel's own halo dismissed the overlay *and* got reposted into
    /// whatever app sits behind it — "I clicked the island and it closed",
    /// exactly the first-click complaint. The ring carries no controls, so
    /// swallowing the click there costs nothing.
    private func isPointInsidePanelWindow(_ screenPoint: NSPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return Self.rectContainsIncludingEdges(panel.frame, point: screenPoint)
    }

    /// Grace period before a hover-open timer is cancelled.  Prevents
    /// mouse jitter at the notch edge from resetting the delay.
    private static let hoverCancelGracePeriod: TimeInterval = 0.1

    private func scheduleHoverOpen() {
        // Mouse re-entered during grace period — just revoke the cancel.
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil

        guard let model else { return }

        // PI-B-001: the dwell has already been served — the peek is up. Nothing
        // further to schedule until the pointer leaves and comes back.
        guard !model.hoverPeekActive else { return }

        guard hoverTimer == nil else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self, let model = self.model else { return }
            self.performHoverOpen(model)
            self.hoverTimer = nil
        }

        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + AppModel.hoverOpenDelay, execute: item)
    }

    private func performHoverOpen(_ model: AppModel) {
        guard model.notchStatus == .closed else { return }

        // PI-B-001 · board §B: for a theme whose reference specifies the peek as
        // the dwell endpoint, the same 0.15s dwell grows the collapsed shape and
        // surfaces the one actionable item *instead of* opening. Every other
        // theme — and this one with nothing waiting on the user — opens exactly
        // as before.
        if model.hoverBehaviorForClosedSurface() == .peek {
            model.beginHoverPeek()
            return
        }

        if model.hapticFeedbackEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                NSHapticFeedbackManager.FeedbackPattern.alignment,
                performanceTime: .now
            )
        }

        model.notchOpen(reason: .hover)
    }

    /// The peek's live outer rect: the measured body, top-aligned with the
    /// collapsed island and centred on the same axis (`IslandPanelView` mounts
    /// it as a top-anchored overlay on a window centred on the notch).
    /// `.zero`-sized — i.e. no peek up — always answers `false`.
    ///
    /// PI-B-001 round-2 correction: the anchor is the *same* geometry the pill
    /// hit-test uses — `closedSurfaceRect(for:)` when a target screen resolves,
    /// falling back to `notchRect` exactly like `isPointInClosedSurfaceArea`.
    /// Anchoring straight to `notchRect` made the peek's hit-rect depend on a
    /// physical notch, so on top-bar placements the dwell could die over the
    /// grown body while the pointer was still inside the visible peek.
    private func isPointInHoverPeekArea(_ screenPoint: NSPoint, model: AppModel) -> Bool {
        guard model.hoverPeekActive else { return false }
        let size = model.hoverPeekSurfaceSize
        guard size.width > 0, size.height > 0 else { return false }

        let anchor = closedSurfaceRect(for: model) ?? notchRect
        let rect = NSRect(
            x: anchor.midX - size.width / 2,
            y: anchor.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return Self.rectContainsIncludingEdges(rect, point: screenPoint)
    }

    /// Cancels a pending hover dwell **and** retires a raised peek, both after
    /// the same jitter grace period.
    ///
    /// PI-B-001 folded the peek into what used to be `cancelHoverOpen`: the two
    /// are the same intent ("the pointer has left the island"), and they must
    /// share the grace window or a pointer skimming the notch edge would flicker
    /// the peek off and on.
    private func cancelHoverIntent() {
        guard hoverTimer != nil || model?.hoverPeekActive == true else { return }

        // Don't cancel immediately — allow a short grace period so that
        // mouse jitter at the notch edge doesn't restart the timer.
        guard hoverCancelGrace == nil else { return }

        let grace = DispatchWorkItem { [weak self] in
            self?.hoverTimer?.cancel()
            self?.hoverTimer = nil
            self?.hoverCancelGrace = nil
            self?.model?.endHoverPeek()
        }

        hoverCancelGrace = grace
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hoverCancelGracePeriod,
            execute: grace
        )
    }

    /// Cancel without grace period — used for click-to-open where the
    /// hover timer must not fire after the click already opened the panel.
    private func cancelHoverOpenImmediately() {
        hoverCancelGrace?.cancel()
        hoverCancelGrace = nil
        hoverTimer?.cancel()
        hoverTimer = nil
    }

    // MARK: - Hit testing geometry

    func isPointInClosedSurfaceArea(_ screenPoint: NSPoint) -> Bool {
        guard let model else { return false }

        if let closedSurfaceRect = closedSurfaceRect(for: model) {
            return Self.rectContainsIncludingEdges(closedSurfaceRect, point: screenPoint)
        }

        let expandedNotch = notchRect.insetBy(dx: -20, dy: -10)
        return Self.rectContainsIncludingEdges(expandedNotch, point: screenPoint)
    }

    func isPointInExpandedArea(_ screenPoint: NSPoint) -> Bool {
        guard let model, model.notchStatus == .opened else {
            return isPointInClosedSurfaceArea(screenPoint)
        }

        guard let panel else {
            return false
        }

        // The window is always at opened size, but the visible content area
        // is the inner content rect (excluding shadow insets).
        guard let contentRect = contentRect(for: model, in: panel.frame) else {
            return false
        }

        return Self.rectContainsIncludingEdges(contentRect, point: screenPoint)
    }

    func openedPanelWidth(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return Self.preferredTopBarOpenedPanelWidth }
        let preferredWidth = screen.safeAreaInsets.top > 0
            ? Self.preferredNotchOpenedPanelWidth
            : Self.preferredTopBarOpenedPanelWidth
        return max(IslandChromeLayout.minimumContentWidth, min(preferredWidth, screen.visibleFrame.width - 32))
    }

    func contentRect(for model: AppModel, in bounds: NSRect) -> NSRect? {
        IslandChromeLayout.contentRect(in: bounds, metrics: chromeMetrics(for: model))
    }

    nonisolated static func closedSurfaceRect(
        notchRect: NSRect,
        closedWidth: CGFloat
    ) -> NSRect {
        let cx = notchRect.midX
        return NSRect(
            x: cx - closedWidth / 2,
            y: notchRect.minY,
            width: closedWidth,
            height: notchRect.height
        )
    }

    nonisolated static func rectContainsIncludingEdges(_ rect: NSRect, point: NSPoint) -> Bool {
        point.x >= rect.minX
            && point.x <= rect.maxX
            && point.y >= rect.minY
            && point.y <= rect.maxY
    }

    /// Extra hit-area width reserved on a notched display when the
    /// notch-lane label (AB-241) is showing. Sized generously (rather than
    /// tracking the live label's exact rendered width) — the same "fixed,
    /// generous hit-area" approach already used for the external layout's
    /// fluid pill below — so hover/click keeps working over the label
    /// without this controller needing to duplicate `V6ClosedPill`'s text
    /// measurement.
    nonisolated static let notchLaneLabelHitAreaBonus: CGFloat = 200

    /// Hit-area width of the v6 closed pill.
    ///
    /// - On a MacBook (physical notch present) the pill is locked to
    ///   `44 + notchWidth + 44`, per the v6 design spec, plus
    ///   `notchLaneLabelHitAreaBonus` when the notch-lane label is showing.
    /// - On an external display the width is content-driven; we return a
    ///   generous fixed hit-area so hover / click detection works without
    ///   the controller having to introspect live session state.
    nonisolated static func closedPanelWidth(
        notchWidth: CGFloat,
        isNotchedDisplay: Bool,
        notchStatus: NotchStatus,
        includesNotchLaneLabel: Bool = false
    ) -> CGFloat {
        let popBonus: CGFloat = notchStatus == .popping ? 18 : 0
        if isNotchedDisplay {
            let labelBonus: CGFloat = includesNotchLaneLabel ? notchLaneLabelHitAreaBonus : 0
            return notchWidth + 88 + labelBonus + popBonus
        }
        return 360 + popBonus
    }

    private func closedSurfaceRect(for model: AppModel) -> NSRect? {
        guard let screen = resolveTargetScreen() else {
            return nil
        }

        let closedWidth = closedPanelWidth(for: model, on: screen)
        return Self.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )
    }

    private func panelFrame(for model: AppModel?, on screen: NSScreen) -> NSRect {
        let size = panelSize(for: model, on: screen)
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Always returns the maximum (opened) panel size so the window never
    /// needs to resize.  All visual transitions are driven purely by SwiftUI
    /// inside this fixed-size window.
    private func panelSize(for model: AppModel?, on screen: NSScreen) -> CGSize {
        // Use at least the empty-state height so the window doesn't shrink
        // when sessions come and go while opened.
        let contentHeight = model.map { max(openedContentHeight(for: $0), Self.openedEmptyStateHeight) }
            ?? Self.openedEmptyStateHeight

        // Overlay remediation Phase 5 (F8): the window's reserved header-band
        // budget must match what `IslandPanelView` actually gives
        // `openedHeaderContent` (`theme.openedHeaderHeight ?? closedNotchHeight`
        // there; mirrored here since this controller has no `theme` access at
        // the view layer). `screen.notchSize.height` and `closedNotchHeight`
        // are numerically identical on a real notch screen (both resolve to
        // `safeAreaInsets.top`), so this is a no-op for the five themes that
        // don't override `openedHeaderHeight` — but Flight Deck's taller
        // override must inflate the *window*, or its own measured body
        // content gets squeezed by a fixed-size window still sized for the
        // old, shorter band (its bottom would be clipped by the surface's
        // `.clipShape`).
        let headerBandHeight = model?.islandTheme.openedHeaderHeight ?? screen.notchSize.height

        return IslandChromeLayout.windowSize(
            preferredContentWidth: openedPanelWidth(for: screen) + Self.openedContentWidthPadding,
            contentHeight: headerBandHeight + contentHeight + Self.openedContentBottomPadding,
            metrics: chromeMetrics(for: model),
            availableWidth: screen.visibleFrame.width
        )
    }

    /// Chrome metrics of the active theme (AB-299). With Classic active these
    /// equal the legacy `IslandChromeMetrics` statics (pinned by
    /// `IslandThemeTokensTests`), so the computed panel frames are identical to
    /// before the token layer existed. Falls back to Classic when there's no
    /// model yet (early sizing during panel creation).
    private func chromeMetrics(for model: AppModel?) -> IslandMetricsTokens {
        (model?.islandTheme.tokens ?? .classic).metrics
    }

    private func closedPanelWidth(for model: AppModel, on screen: NSScreen) -> CGFloat {
        let notchWidth = screen.notchSize.width
        let isNotched = screen.safeAreaInsets.top > 0
        return Self.closedPanelWidth(
            notchWidth: notchWidth,
            isNotchedDisplay: isNotched,
            notchStatus: model.notchStatus,
            includesNotchLaneLabel: isNotched && model.islandClosedLabel() != nil
        )
    }

    /// Opened-surface content height, driven entirely by SwiftUI measurement
    /// (AB-228). This used to hand-estimate a height per session phase
    /// (~15 constants covering row height, approval/question/completion body
    /// height, markdown text measured via `NSString.boundingRect`, ...) that
    /// had to be kept in lockstep with `IslandPanelView`'s actual layout by
    /// hand, and diverged whenever real content (long commands, wrapped
    /// markdown, many todos, long question lists) didn't match the estimate
    /// — causing clipped content or dead space below it.
    ///
    /// `IslandPanelView.openedContent` now measures its own real, rendered
    /// height via a `GeometryReader`/`PreferenceKey` (the same mechanism
    /// already used for notification cards) and publishes it to
    /// `AppModel.measuredOpenedContentHeight` /
    /// `measuredNotificationContentHeight`. This method just reads that
    /// measured value back.
    ///
    /// Overlay remediation Phase 5 (`emptyState` clipping, F9-adjacent): this
    /// used to short-circuit to the fixed `openedEmptyStateHeight` constant
    /// whenever `model.islandListSessions.isEmpty`, *before* ever consulting
    /// the measured height — even though `IslandPanelView.openedContent`
    /// measures the empty state exactly like every other content case (its
    /// doc comment already says "hint banner + list/placeholder/empty state,
    /// all included"). That early return was calibrated to Classic/Poured's
    /// compact empty body and silently clipped taller bodies added later
    /// (Flight Deck's lamp grid + sysline row, Halo's 34pt glyph + monitoring
    /// pill) at the surface's `.clipShape` — the panel was sized to 108pt
    /// while those themes' empty states needed more. The empty-state case now
    /// goes through the same "measured, else floor" path as every other
    /// content case; `openedEmptyStateHeight` remains the pre-measurement /
    /// unmeasured-frame fallback (and the `panelSize` floor below), it is
    /// simply no longer force-applied once a real measurement exists.
    private func openedContentHeight(for model: AppModel) -> CGFloat {
        let isNotificationMode = model.notchOpenReason == .notification && model.islandSurface.sessionID != nil
        let measured = isNotificationMode
            ? model.measuredNotificationContentHeight
            : model.measuredOpenedContentHeight

        guard measured > 0 else {
            // Not measured yet (first frame after the surface/content
            // changed, before SwiftUI has laid out and reported a height) —
            // including the very first empty-state frame. Fall back to the
            // empty-state floor; the measured-height `didSet` debounce
            // corrects this with a follow-up reposition as soon as layout
            // completes, matching how notification cards already behaved
            // before this change.
            return Self.openedEmptyStateHeight
        }

        return measured + Self.measuredContentSafetyPadding
    }

    // MARK: - Event reposting

    private func repostMouseDown(at screenPoint: NSPoint) {
        let flippedY = NSScreen.main.map { $0.frame.height - screenPoint.y } ?? screenPoint.y

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
            mouseButton: .left
        ) else { return }

        event.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard let upEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: screenPoint.x, y: flippedY),
                mouseButton: .left
            ) else { return }
            upEvent.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - NotchPanel

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - NotchHostingView

final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var notchController: OverlayPanelController?

    override var isOpaque: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure the panel is key before SwiftUI processes the click.
        // With nonactivatingPanel, hover-opened panels aren't key, so
        // SwiftUI Button may consume the first click for key acquisition
        // instead of firing its action.
        window?.makeKey()
        super.mouseDown(with: event)
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller = notchController,
              let model = controller.model else {
            return nil
        }

        guard let contentRect = controller.contentRect(for: model, in: bounds),
              contentRect.contains(point) else {
            return nil
        }

        return super.hitTest(point) ?? self
    }

    private func convertToScreen(_ viewPoint: NSPoint) -> NSPoint {
        guard let window else { return viewPoint }
        let windowPoint = convert(viewPoint, to: nil)
        return window.convertPoint(toScreen: windowPoint)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    private func configureTransparency() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        // NSHostingView wraps content in internal NSScrollViews.
        // SwiftUI may recreate them when the view tree changes (e.g.
        // AutoHeightScrollView toggling between scroll/non-scroll mode),
        // so we must re-disable on every layout pass.
        // Guard: only modify properties when they differ to avoid
        // triggering additional layout passes that could loop.
        disableInternalScrollers(in: self)
    }

    private func disableInternalScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            if scrollView.hasVerticalScroller { scrollView.hasVerticalScroller = false }
            if scrollView.hasHorizontalScroller { scrollView.hasHorizontalScroller = false }
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            return
        }
        for child in view.subviews {
            disableInternalScrollers(in: child)
        }
    }
}

// MARK: - NotchEventMonitors

@MainActor
final class NotchEventMonitors {
    private var globalMoveMonitor: Any?
    private var localMoveMonitor: Any?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var lastMoveTime: TimeInterval = 0

    var isActive: Bool { globalMoveMonitor != nil }

    func start(
        mouseMoveHandler: @MainActor @escaping @Sendable (NSPoint) -> Void,
        mouseDownHandler: @MainActor @escaping @Sendable (NSPoint) -> Void
    ) {
        let throttleInterval: TimeInterval = 0.05

        nonisolated(unsafe) var sharedLastMove: TimeInterval = 0

        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Self.deliverOnMain(location, to: mouseMoveHandler)
        }

        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - sharedLastMove >= throttleInterval else { return event }
            sharedLastMove = now
            let location = NSEvent.mouseLocation
            Self.deliverOnMain(location, to: mouseMoveHandler)
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Self.deliverOnMain(location, to: mouseDownHandler)
        }

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            let location = NSEvent.mouseLocation
            Self.deliverOnMain(location, to: mouseDownHandler)
            return event
        }
    }

    /// G-61: runs the handler **synchronously**, on the same main-thread turn
    /// the event arrived on, instead of hopping through `Task { @MainActor in }`.
    ///
    /// `NSEvent` monitors already fire on the main thread, so the hop bought
    /// nothing but latency — and that latency was the bug: a deferred
    /// `mouseDownHandler` decided "was this click inside the panel?" against the
    /// panel's geometry *after* SwiftUI had already handled the same click and
    /// relaid out (a row expanding/collapsing resizes the overlay window, and
    /// `OverlayPanelController.isPointInExpandedArea` reads the live
    /// `panel.frame`). A first click that landed near the bottom of the panel
    /// could therefore be judged outside a window that had since shrunk under
    /// it — dismissing the whole overlay on the user's first click. Evaluating
    /// on the event's own turn pins the decision to the geometry the user
    /// actually clicked on.
    private nonisolated static func deliverOnMain(
        _ location: NSPoint,
        to handler: @MainActor @escaping @Sendable (NSPoint) -> Void
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { handler(location) }
        } else {
            Task { @MainActor in handler(location) }
        }
    }

    func stop() {
        if let m = globalMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = localMoveMonitor { NSEvent.removeMonitor(m) }
        if let m = globalClickMonitor { NSEvent.removeMonitor(m) }
        if let m = localClickMonitor { NSEvent.removeMonitor(m) }
        globalMoveMonitor = nil
        localMoveMonitor = nil
        globalClickMonitor = nil
        localClickMonitor = nil
    }
}

// MARK: - NSScreen notch size helper

extension NSScreen {
    /// Simulated notch width used on non-notch (external) displays.
    /// Sized close to a real MacBook notch (~200pt) so the closed island
    /// doesn't feel disproportionately wide when the black rectangle is
    /// fully visible (not hidden behind a physical notch).
    static let externalDisplayNotchWidth: CGFloat = 190
    static let externalDisplayNotchHeight: CGFloat = 38

    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(
                width: Self.externalDisplayNotchWidth,
                height: Self.externalDisplayNotchHeight
            )
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4

        return CGSize(width: notchWidth, height: notchHeight)
    }

    var topStatusBarHeight: CGFloat {
        let reservedTopInset = max(0, frame.maxY - visibleFrame.maxY)
        if reservedTopInset > 0 {
            return reservedTopInset
        }

        if safeAreaInsets.top > 0 {
            return safeAreaInsets.top
        }

        return 24
    }

    var islandClosedHeight: CGFloat {
        NSScreen.computeIslandClosedHeight(
            safeAreaInsetsTop: safeAreaInsets.top,
            topStatusBarHeight: topStatusBarHeight
        )
    }

    /// Pure helper so the height selection logic can be unit-tested without real screen hardware.
    ///
    /// On notch screens, use `safeAreaInsetsTop` directly — the island must match the
    /// physical notch height exactly so it sits flush with the notch bottom edge.
    /// Previously this used `min(safeAreaInsetsTop, topStatusBarHeight)`, but when the
    /// menu bar reserved area is smaller than the notch (e.g. auto-hide menu bar, or
    /// certain display configurations), the island ended up shorter than the physical
    /// notch, leaving a visible gap.
    /// On non-notch screens (`safeAreaInsetsTop == 0`), use `topStatusBarHeight` directly.
    static func computeIslandClosedHeight(
        safeAreaInsetsTop: CGFloat,
        topStatusBarHeight: CGFloat
    ) -> CGFloat {
        if safeAreaInsetsTop > 0 {
            return safeAreaInsetsTop
        }
        return topStatusBarHeight
    }
}
