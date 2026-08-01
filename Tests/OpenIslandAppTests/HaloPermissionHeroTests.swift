import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-345 (T26 · Halo permission hero, §5E) + glow-travel (§3b). Pins the pure,
/// view-free format rules the hero renders from — the keycap glyphs (which must
/// track the **real** registered `OverlayPanelController` shortcuts), the
/// claude-vs-codex capability fork, the ring / glow / conic-gradient params, the
/// T10 command-token palette — and the perimeter-edge opacity handoff the
/// glow-travel condense drives. Everything is a pure function of its arguments, so
/// these pin the AC without rendering a SwiftUI view (the `HaloEdgeLightTests` /
/// `FlightDeckApprovalFormat` proof pattern). Colours are compared with `==`
/// against the same token / literal expressions the format builds them from.
@MainActor
struct HaloPermissionHeroTests {

    // MARK: - Keycaps (track the REAL ⌘Y / ⌘⇧Y / ⌘N / ⌘J handlers)

    // MARK: - Capability fork (claude vs codex — §5E · E3)

    // MARK: - Hero ring params (§5E · mockup `.hero`)

    // MARK: - Ring / glow / conic colours (§5E — compared by `==`)

    // MARK: - Command-token palette (§5E · E1 — the T10 tokenizer's kinds → hues)

    // MARK: - Glow-travel handoff (§3b step 4 — perimeter edge condenses)

    /// G-10 — every opened frame in the mockup is a class-less `<div class="isle
    /// panel">` (§C's list, §E's heroes, §F, §H), so `.isle::before` falls through
    /// to `background:var(--hair)`: "idle: bare 8% hairline, edge OFF"
    /// (`06-halo.html:130`). The loud perimeters (`.isle.work` / `.perm` / …) are a
    /// **closed-pill** signal. Opened working therefore drops its orbiting
    /// cyan→violet segment onto that hairline — otherwise it sweeps the very 2pt of
    /// left gutter §C's `.rail.run` occupies, in the very same hue, and the rail
    /// stops reading once per orbit.
    @Test
    func openedWorkingPerimeterSettlesToTheBoardsBareHairline() {
        #expect(HaloEdgeLightModel.perimeterSettlesToHairline(for: .working, isOpened: true))

        // Closed keeps the orbit — that is where it means something.
        for state in IslandSurfaceEdgeState.allCases {
            #expect(!HaloEdgeLightModel.perimeterSettlesToHairline(for: state, isOpened: false))
        }
        // The attention states already hand their light over through
        // `perimeterOpenHandoffOpacity` + `perimeterSuppressesBloom` (a *dimmed
        // amber* hairline, deliberately still amber — G-36/M-20), and
        // `.success` / `.failure` draw no rail to collide with. Both are untouched.
        for state in [IslandSurfaceEdgeState.idle, .permission, .question, .success, .failure] {
            #expect(!HaloEdgeLightModel.perimeterSettlesToHairline(for: state, isOpened: true))
        }
    }

    /// G-10 — the rail's own placement. `.rail{left:0}` (`06-halo.html:285`) sits on
    /// the panel's painted border-box edge; ours has to be pushed `openedTopRadius`
    /// in to reach it, because `NotchShape` draws the silhouette's walls that far
    /// inside the layout frame. Without the offset the rail lands in the
    /// transparent shoulder and is clipped away — which is why G-10 read as "the
    /// rail is unreadable" when it was in fact not on screen at all.
    @Test
    func railStartsAtThePaintedWallOnTheNotchProfileOnly() {
        // Notch profile (`IslandPanelView.sessionListSideInset` = 46).
        #expect(HaloSessionRowFormat.railWallInset(sideInset: 46, openedTopRadius: 20) == 20)
        // Top-bar profile (= 16): `V6ClosedPillShape` paints from `rect.minX`, so
        // the row's own leading edge already *is* the wall.
        #expect(HaloSessionRowFormat.railWallInset(sideInset: 16, openedTopRadius: 20) == 0)
        #expect(HaloMetrics.topBarProfileSideInset == 16)
        // The offset tracks the theme's radius, not a copied literal.
        #expect(HaloSessionRowFormat.railWallInset(sideInset: 46, openedTopRadius: 26) == 26)
        #expect(IslandThemeTokens.halo.metrics.openedTopRadius == 20)
    }

    // MARK: - Scoped-grant label (G-21 · mockup `.scope code`)

}
