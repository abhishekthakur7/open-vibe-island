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

    private let colors = IslandColorTokens.halo

    // MARK: - Keycaps (track the REAL ⌘Y / ⌘⇧Y / ⌘N handlers; no ⌘J)

    @Test
    func keycapGlyphsMatchTheRegisteredShortcuts() {
        #expect(HaloHeroFormat.Shortcut.allowOnce.glyphs == ["⌘", "Y"])
        #expect(HaloHeroFormat.Shortcut.alwaysAllow.glyphs == ["⌘", "⇧", "Y"])
        #expect(HaloHeroFormat.Shortcut.deny.glyphs == ["⌘", "N"])
    }

    @Test
    func keycapGlyphStringsJoinInOrder() {
        #expect(HaloHeroFormat.Shortcut.allowOnce.glyphString == "⌘Y")
        #expect(HaloHeroFormat.Shortcut.alwaysAllow.glyphString == "⌘⇧Y")
        #expect(HaloHeroFormat.Shortcut.deny.glyphString == "⌘N")
    }

    /// There is deliberately **no** jump shortcut: `OverlayPanelController`
    /// registers ⌘Y / ⌘⇧Y / ⌘N only. The Codex jump button prints no keycap, so no
    /// `Shortcut` case may spell a ⌘J — a glyph must track a real handler.
    @Test
    func noShortcutAdvertisesAJumpKey() {
        for shortcut in HaloHeroFormat.Shortcut.allCases {
            #expect(!shortcut.glyphs.contains("J"))
        }
        #expect(HaloHeroFormat.Shortcut.allCases.count == 3)
    }

    // MARK: - Capability fork (claude vs codex — §5E · E3)

    @Test
    func claudeApprovesInApp_codexJumpsToApprove() {
        #expect(HaloHeroFormat.layout(requiresTerminalApproval: false) == .approveDeny)
        #expect(HaloHeroFormat.layout(requiresTerminalApproval: true) == .jumpToApprove)
    }

    @Test
    func variantForksCommandDiffTerminal() {
        // A Codex request is always the terminal variant, diff or not.
        #expect(HaloHeroFormat.variant(hasFileDiff: false, requiresTerminalApproval: true) == .terminal)
        #expect(HaloHeroFormat.variant(hasFileDiff: true, requiresTerminalApproval: true) == .terminal)
        // In-app: a file diff draws the diff, else the command block.
        #expect(HaloHeroFormat.variant(hasFileDiff: true, requiresTerminalApproval: false) == .diff)
        #expect(HaloHeroFormat.variant(hasFileDiff: false, requiresTerminalApproval: false) == .command)
    }

    /// The annunciator glyph is a non-colour channel: a pencil for a file edit, a
    /// warning triangle for a command / terminal approval — never colour alone.
    @Test
    func annunciatorGlyphDistinguishesEditFromCommand() {
        #expect(HaloHeroFormat.annunciatorGlyph(.diff) == "square.and.pencil")
        #expect(HaloHeroFormat.annunciatorGlyph(.command) == "exclamationmark.triangle")
        #expect(HaloHeroFormat.annunciatorGlyph(.terminal) == "exclamationmark.triangle")
    }

    // MARK: - Hero ring params (§5E · mockup `.hero`)

    @Test
    func ringParamsMatchTheSpec() {
        #expect(HaloHeroFormat.ringRadius == 16)        // heroRadius
        #expect(HaloHeroFormat.ringWidth == 1.5)        // heroRingWidth
        #expect(HaloHeroFormat.pulsePeriod == 2.2)      // edgepulse 2.2s
        // Outer glow `0 0 48 -8` under the T22 spread-equivalence rule (48-8)/2.
        #expect(HaloHeroFormat.glowRadius == 20)
        // The `::before` ring rides the shared `.55 ↔ 1` edge pulse.
        #expect(HaloHeroFormat.pulseMinOpacity == 0.55)
        #expect(HaloHeroFormat.pulseMaxOpacity == 1.0)
        #expect(HaloHeroFormat.conicAngle == 44)
    }

    @Test
    func ringParamsAreWiredToTheSharedMetricsAndMotion() {
        // The ring reuses the theme's own tokens, never a fresh literal.
        #expect(HaloHeroFormat.ringRadius == HaloMetrics.heroRadius)
        #expect(HaloHeroFormat.ringWidth == HaloMetrics.heroRingWidth)
        #expect(HaloHeroFormat.pulsePeriod == HaloMotion.heroRing)
        #expect(HaloHeroFormat.pulseMinOpacity == HaloEdgeLightModel.pulseOpacityMin)
        #expect(HaloHeroFormat.pulseMaxOpacity == HaloEdgeLightModel.pulseOpacityMax)
    }

    // MARK: - Ring / glow / conic colours (§5E — compared by `==`)

    @Test
    func permissionRingIsAmber_questionIsQGold() {
        // Inset ring — amber@.55 / qgold@.5.
        #expect(HaloHeroFormat.insetRingColor(.permission)
            == Color(red: 255 / 255.0, green: 160 / 255.0, blue: 80 / 255.0).opacity(0.55))
        #expect(HaloHeroFormat.insetRingColor(.question)
            == colors.statusWaitingForAnswer.opacity(0.5))
        // Outer glow — rgba(255,140,80,.5) / qgold@.4.
        #expect(HaloHeroFormat.glowColor(.permission)
            == Color(red: 255 / 255.0, green: 140 / 255.0, blue: 80 / 255.0).opacity(0.5))
        #expect(HaloHeroFormat.glowColor(.question)
            == colors.statusWaitingForAnswer.opacity(0.4))
    }

    @Test
    func permissionConicIsAmberMagentaAmberFrom44Degrees() {
        let amber = colors.statusWaitingForApproval
        #expect(HaloHeroFormat.conicStops(.permission) == [
            HaloEdgeStop(amber, 0),
            HaloEdgeStop(HaloEdge.magenta, 198),   // mockup 55% of 360
            HaloEdgeStop(amber, 360),
        ])
    }

    @Test
    func questionConicIsQGoldWarmQGold() {
        let qgold = colors.statusWaitingForAnswer
        #expect(HaloHeroFormat.conicStops(.question) == [
            HaloEdgeStop(qgold, 0),
            HaloEdgeStop(Color(red: 255 / 255.0, green: 224 / 255.0, blue: 168 / 255.0), 198),
            HaloEdgeStop(qgold, 360),
        ])
    }

    // MARK: - Command-token palette (§5E · E1 — the T10 tokenizer's kinds → hues)

    @Test
    func commandPaletteColoursEachTokenKind() {
        let palette = HaloHeroFormat.commandPalette
        #expect(palette[.command] == Color(red: 0xF4 / 255.0, green: 0xF6 / 255.0, blue: 0xFB / 255.0))
        #expect(palette[.subcommand] == colors.statusRunning)          // cyan
        #expect(palette[.flag] == Color(red: 0x8F / 255.0, green: 0xB6 / 255.0, blue: 0xFF / 255.0))
        #expect(palette[.string] == colors.statusCompleted)            // green
        #expect(palette[.path] == Color.white.opacity(0.5))
        // The command is the one weighted (600) token; the prompt is amber@.65.
        #expect(HaloHeroFormat.commandWeights[.command] == .semibold)
        #expect(HaloHeroFormat.promptColor
            == Color(red: 255 / 255.0, green: 160 / 255.0, blue: 80 / 255.0).opacity(0.65))
    }

    /// A real command tokenizes into the palette's kinds edge-to-edge — the E1
    /// path the hero renders (the T10 tokenizer shipped, so `.cmd` spans are live).
    @Test
    func shippedTokenizerClassifiesTheE1Command() {
        let tokens = ShellCommandTokenizer.labeledTokens(#"rtk grep -rn "fetch(" packages/ui/src"#)
        let kinds = tokens.map(\.kind)
        #expect(kinds.contains(.command))
        #expect(kinds.contains(.subcommand))
        #expect(kinds.contains(.flag))
        #expect(kinds.contains(.string))
        #expect(kinds.contains(.path))
    }

    // MARK: - Glow-travel handoff (§3b step 4 — perimeter edge condenses)

    /// While **closed** the perimeter edge is fully opaque in every state (the loud
    /// pill bloom is uncut).
    @Test
    func closedPerimeterHoldsFullOpacity() {
        for state in IslandSurfaceEdgeState.allCases {
            #expect(HaloEdgeLightModel.perimeterOpenHandoffOpacity(for: state, isOpened: false) == 1.0)
        }
    }

    /// Opening on an **attention** state dims the perimeter edge to the luminous
    /// handoff floor (light condensing into the card ring); non-attention states
    /// stay fully opaque even when open.
    @Test
    func openedAttentionPerimeterDimsToTheHandoffFloor() {
        #expect(HaloEdgeLightModel.perimeterOpenHandoffOpacity(for: .permission, isOpened: true)
            == HaloEdgeLightModel.perimeterOpenHandoffFloor)
        #expect(HaloEdgeLightModel.perimeterOpenHandoffOpacity(for: .question, isOpened: true)
            == HaloEdgeLightModel.perimeterOpenHandoffFloor)
        // The floor is a luminous mid-value — the edge never goes dark (both ends
        // stay amber through the handoff).
        #expect(HaloEdgeLightModel.perimeterOpenHandoffFloor == 0.55)
        #expect(HaloEdgeLightModel.perimeterOpenHandoffFloor > 0)

        for state in [IslandSurfaceEdgeState.idle, .working, .success, .failure] {
            #expect(HaloEdgeLightModel.perimeterOpenHandoffOpacity(for: state, isOpened: true) == 1.0)
        }
    }
}
