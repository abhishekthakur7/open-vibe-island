import SwiftUI
import Testing
@testable import OpenIslandApp

/// Stage-1 pins for Poured Island 2.0 (AB-329): the attention palette, the new
/// material gradient / hard-specular / inner-hairline tokens, the grown
/// closed-pill shadow insets, and Classic status-colour parity.
///
/// This is a **starter** suite — stage 2 (typography table + full conformance
/// suite) EXTENDS it. Keep new Poured pins in this struct rather than a parallel
/// file so the theme's contract lives in one place.
struct PouredThemeTests {

    // MARK: - Attention palette (SPEC §0 / §1a)

    /// The two new attention-glow colours, pinned by exact 8-bit components so a
    /// drift in either fails the build.
    @Test
    func attentionPaletteMatchesTheSpecHex() {
        #expect(
            PouredPalette.attention
                == Color(red: 0xFF / 255.0, green: 0xB1 / 255.0, blue: 0x4D / 255.0)
        )
        #expect(
            PouredPalette.attentionHot
                == Color(red: 0xFF / 255.0, green: 0x9D / 255.0, blue: 0x5C / 255.0)
        )
    }

    /// The attention amber is a *brighter* amber than the shipped warning tone
    /// (`statusWarning #d98c26`), which keeps its caution / interrupted role — the
    /// two must never collapse onto one another.
    @Test
    func attentionIsDistinctFromTheWarningTone() {
        let colors = IslandThemeTokens.poured.colors

        #expect(PouredPalette.attention != colors.statusWarning)
        #expect(PouredPalette.attention != colors.statusInterrupted)
        #expect(PouredPalette.attentionHot != colors.statusWarning)
        #expect(PouredPalette.attention != PouredPalette.attentionHot)
    }

    // MARK: - Material tokens (SPEC §1d)

    /// The 3-stop body gradient carries elevation by inner luminance (lighter
    /// top → darker bottom). Pinned stop-by-stop: colour, opacity, location.
    @Test
    func bodyGradientPinsTheThreeStops() throws {
        let stops = try #require(IslandMaterialTokens.poured.bodyGradient)
        #expect(stops.count == 3)

        #expect(
            stops[0] == IslandGradientStop(
                color: Color(red: 26 / 255.0, green: 31 / 255.0, blue: 44 / 255.0),
                opacity: 0.86,
                location: 0.0
            )
        )
        #expect(
            stops[1] == IslandGradientStop(
                color: Color(red: 13 / 255.0, green: 17 / 255.0, blue: 26 / 255.0),
                opacity: 0.94,
                location: 0.62
            )
        )
        #expect(
            stops[2] == IslandGradientStop(
                color: Color(red: 9 / 255.0, green: 12 / 255.0, blue: 20 / 255.0),
                opacity: 0.96,
                location: 1.0
            )
        )
    }

    /// The hard specular is a crisp 1pt white line at 14% — read as a top line
    /// via `IslandSpecularEdge.sheenHeight == 1`.
    @Test
    func hardSpecularEdgeIsAOnePointFourteenPercentWhiteLine() throws {
        let edge = try #require(IslandMaterialTokens.poured.specularHardEdge)

        #expect(edge.color == Color.white)
        #expect(edge.opacity == 0.14)
        #expect(edge.sheenHeight == 1)
    }

    /// The inner hairline is a faint 0.5pt white inset stroke at 5%.
    @Test
    func innerHairlineIsAHalfPointFivePercentStroke() throws {
        let hairline = try #require(IslandMaterialTokens.poured.innerHairline)

        #expect(hairline.opacity == 0.05)
        #expect(hairline.width == 0.5)
    }

    /// The soft 26pt sheen is unchanged — the two hard layers stack *on top* of
    /// it rather than replacing it.
    @Test
    func softSpecularSheenIsUnchanged() throws {
        let sheen = try #require(IslandMaterialTokens.poured.specularTopEdge)

        #expect(sheen.color == Color.white)
        #expect(sheen.opacity == 0.5)
        #expect(sheen.sheenHeight == 26)
    }

    /// The four flat themes opt into none of the three new liquid-glass layers —
    /// `nil` is what guarantees `OpenedSurfaceBackground` renders them exactly as
    /// it does today.
    @Test
    func otherThemesDeclareNoNewMaterialLayers() {
        for material in [
            IslandMaterialTokens.classic,
            IslandMaterialTokens.instrument,
            IslandMaterialTokens.flightDeck,
            IslandMaterialTokens.annual,
        ] {
            #expect(material.bodyGradient == nil)
            #expect(material.specularHardEdge == nil)
            #expect(material.innerHairline == nil)
        }
    }

    /// `IslandMaterialTokens` still declares / synthesises `Equatable` after the
    /// three new fields — a compile-time proof plus a runtime sanity check.
    @Test
    func materialTokensRemainEquatable() {
        #expect(IslandMaterialTokens.poured == IslandMaterialTokens.poured)
        #expect(IslandMaterialTokens.poured != IslandMaterialTokens.classic)
    }

    // MARK: - Closed-inset growth (SPEC §3.1 / AB-329)

    /// Poured's closed-pill shadow insets grew 16/18 → 40/44 so the A3 amber
    /// bloom (radius ≤ 34 + spread) is contained by the always-opened-size
    /// overlay window; the opened insets stay 28/34. Because the closed insets
    /// now exceed the opened ones, `IslandChromeLayout`'s per-axis max grows the
    /// window (asserted in `IslandChromeLayoutTests`).
    @Test
    func closedShadowInsetsGrewToFortyFortyFour() {
        let metrics = IslandMetricsTokens.poured

        #expect(metrics.closedShadowHorizontalInset == 40)
        #expect(metrics.closedShadowBottomInset == 44)
        #expect(metrics.openedShadowHorizontalInset == 28)
        #expect(metrics.openedShadowBottomInset == 34)

        #expect(metrics.closedShadowHorizontalInset > metrics.openedShadowHorizontalInset)
        #expect(metrics.closedShadowBottomInset > metrics.openedShadowBottomInset)
    }

    // MARK: - Classic status-colour parity (SPEC §1a)

    /// Every vivid status tint Poured carries is *byte-identical* to Classic's —
    /// the two themes share status semantics. (Idle / inactive are the honest
    /// exception, pinned separately below.)
    @Test
    func vividStatusColorsAreByteIdenticalToClassic() {
        let poured = IslandThemeTokens.poured.colors
        let classic = IslandThemeTokens.classic.colors

        #expect(poured.statusRunning == classic.statusRunning)
        #expect(poured.statusCompleted == classic.statusCompleted)
        #expect(poured.statusWaitingForApproval == classic.statusWaitingForApproval)
        #expect(poured.statusWaitingForAnswer == classic.statusWaitingForAnswer)
        #expect(poured.statusWaitingAggregate == classic.statusWaitingAggregate)
        #expect(poured.statusWarning == classic.statusWarning)
        #expect(poured.statusInterrupted == classic.statusInterrupted)
        #expect(poured.statusFailed == classic.statusFailed)
    }

    /// The documented divergence from full parity: idle / inactive derive from
    /// each theme's own *paper* tone, not a shared status literal, so Poured's
    /// cool paper (`#f2f5fb`) makes them legitimately differ from Classic's warm
    /// paper (`#f1ead9`). Pinned so the difference stays a decision, not drift.
    @Test
    func idleAndInactiveFollowPouredsOwnPaper() {
        let poured = IslandThemeTokens.poured.colors
        let classic = IslandThemeTokens.classic.colors

        #expect(poured.statusIdle == poured.paper.opacity(0.35))
        #expect(poured.statusInactive == poured.paper.opacity(0.38))
        #expect(poured.statusIdle != classic.statusIdle)
        #expect(poured.statusInactive != classic.statusInactive)
    }
}
