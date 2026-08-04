import AppKit
import Testing
@testable import OpenIslandApp

struct OverlayPanelControllerTests {
    @Test
    func closedSurfaceRectCentersOnNotch() {
        let notchRect = NSRect(x: 200, y: 900, width: 200, height: 38)
        let closedWidth: CGFloat = 320

        let rect = OverlayPanelController.closedSurfaceRect(
            notchRect: notchRect,
            closedWidth: closedWidth
        )

        // Centered on notch midX (300), width 320
        #expect(rect.minX == 140)
        #expect(rect.minY == 900)
        #expect(rect.width == 320)
        #expect(rect.height == 38)
    }

    @Test
    func edgeInclusiveHitTestingTreatsMaxBoundaryAsInside() {
        let rect = NSRect(x: 100, y: 200, width: 224, height: 8)
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 208)))
        #expect(OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 324, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 325, y: 205)))
        #expect(!OverlayPanelController.rectContainsIncludingEdges(rect, point: NSPoint(x: 150, y: 209)))
    }

    @Test
    func notchedDisplayClosedWidthWrapsPhysicalNotchWithFixedReserve() {
        // v6 MacBook layout: outer width = 44 + physical notch + 44.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 224,
            isNotchedDisplay: true,
            notchStatus: .closed
        )
        #expect(width == CGFloat(224 + 88))
    }

    @Test
    func externalDisplayClosedWidthUsesFixedHitArea() {
        // v6 external layout: fluid in SwiftUI, but the controller uses a
        // generous fixed hit-area so hover/click works without knowing the
        // live content width.
        let width = OverlayPanelController.closedPanelWidth(
            notchWidth: 0,
            isNotchedDisplay: false,
            notchStatus: .closed
        )
        #expect(width == CGFloat(360))
    }

    // MARK: - islandClosedHeight

    @Test
    func islandClosedHeightClampsToNotchHeightWhenSmallerThanMenuBar() {
        // Simulates MacBook Air M2: physical notch ≈ 34 pt, menu bar reserved ≈ 37 pt.
        // Must return 34 (the smaller value) so the island sits flush with the notch.
        let height = NSScreen.computeIslandClosedHeight(safeAreaInsetsTop: 34, topStatusBarHeight: 37)
        #expect(height == 34)
    }

    // MARK: - R8 two-stage Esc

    @Test
    func escapeCollapsesAnOpenPouredHeroBeforeItEverClosesThePanel() {
        // Owner ruling R8 (2026-08-02): with a hero open inside the expanded
        // Poured list, the FIRST Esc collapses it back to its compact row and
        // keeps the list; only the SECOND Esc closes the panel.
        #expect(
            OverlayPanelController.escapeStage(themeID: "poured", hasOpenInListHero: true)
                == .collapseHero
        )
        // Stage 2 — the hero has just collapsed, so nothing is registered.
        #expect(
            OverlayPanelController.escapeStage(themeID: "poured", hasOpenInListHero: false)
                == .closePanel
        )
    }

    @Test
    func escapeKeepsItsShippedMeaningInEveryOtherTheme() {
        // The ruling is Poured-scoped, and the other registered theme must
        // stay byte-identical. `hasOpenInListHero` can only ever be true under
        // Poured (`PouredSessionRow` is the sole registrar), but the theme term
        // is asserted anyway so a future registrar cannot silently widen it.
        for themeID in ["halo"] {
            #expect(
                OverlayPanelController.escapeStage(themeID: themeID, hasOpenInListHero: true)
                    == .closePanel
            )
            #expect(
                OverlayPanelController.escapeStage(themeID: themeID, hasOpenInListHero: false)
                    == .closePanel
            )
        }
    }

    // MARK: - Keycap truth (Slice 5 gap 6)

    @Test
    func approvalShortcutsActuateTheOpenInListHeroRatherThanTheSelectedCard() {
        // Before this, ⌘Y / ⌘⇧Y / ⌘N keyed off `activeIslandCardSession` — the
        // notification/selected session — so a §E hero opened in place in the
        // list advertised keycaps that fired on a different row, or on nothing.
        #expect(
            OverlayPanelController.approvalShortcutSessionID(
                openHeroSessionID: "hero",
                activeCardSessionID: "selected"
            ) == "hero"
        )
        // With no hero open the shipped behaviour is untouched…
        #expect(
            OverlayPanelController.approvalShortcutSessionID(
                openHeroSessionID: nil,
                activeCardSessionID: "selected"
            ) == "selected"
        )
        // …including the "nothing to act on" case, which must stay nil so the
        // key falls through to normal AppKit dispatch instead of being eaten.
        #expect(
            OverlayPanelController.approvalShortcutSessionID(
                openHeroSessionID: nil,
                activeCardSessionID: nil
            ) == nil
        )
    }

    // MARK: - E5 (Poured Slice 5): ⌘Y on a terminal-approval hero jumps

    @Test
    func commandYJumpsInsteadOfNoOppingOnPouredsTerminalApprovalHero() {
        // The board prints ⌘Y on E3's "Jump to Codex to approve" primary, and a
        // printed cap must fire. Nothing in-app can approve a
        // `requiresTerminalApproval` request, so ⌘Y performs the same jump E3's
        // own CTA and ⌘J already perform.
        #expect(
            OverlayPanelController.approvalShortcutOutcome(
                themeID: "poured",
                action: .allowOnce,
                requiresTerminalApproval: true
            ) == .jump
        )
        // ⌘N is not printed on E3 and must not become a jump.
        #expect(
            OverlayPanelController.approvalShortcutOutcome(
                themeID: "poured",
                action: .deny,
                requiresTerminalApproval: true
            ) == .ignore
        )
    }

    @Test
    func ordinaryApprovalsAndEveryOtherThemeKeepTheirShippedApprovalShortcut() {
        // Non-terminal requests are untouched in every theme, for every action
        // that reaches this path.
        for themeID in ["poured", "halo"] {
            #expect(
                OverlayPanelController.approvalShortcutOutcome(
                    themeID: themeID,
                    action: .allowOnce,
                    requiresTerminalApproval: false
                ) == .approve
            )
            #expect(
                OverlayPanelController.approvalShortcutOutcome(
                    themeID: themeID,
                    action: .deny,
                    requiresTerminalApproval: false
                ) == .approve
            )
        }
        // Only Poured's E3 prints ⌘Y on a terminal-approval card, so no other
        // theme gains a binding it does not advertise — they keep bailing.
        for themeID in ["halo"] {
            #expect(
                OverlayPanelController.approvalShortcutOutcome(
                    themeID: themeID,
                    action: .allowOnce,
                    requiresTerminalApproval: true
                ) == .ignore
            )
        }
    }
}
