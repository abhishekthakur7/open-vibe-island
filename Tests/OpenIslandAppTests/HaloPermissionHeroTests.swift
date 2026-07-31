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

    // MARK: - Keycaps (track the REAL ⌘Y / ⌘⇧Y / ⌘N / ⌘J handlers)

    @Test
    func keycapGlyphsMatchTheRegisteredShortcuts() {
        #expect(HaloHeroFormat.Shortcut.allowOnce.glyphs == ["⌘", "Y"])
        #expect(HaloHeroFormat.Shortcut.alwaysAllow.glyphs == ["⌘", "⇧", "Y"])
        #expect(HaloHeroFormat.Shortcut.deny.glyphs == ["⌘", "N"])
        #expect(HaloHeroFormat.Shortcut.jump.glyphs == ["⌘", "J"])
    }

    @Test
    func keycapGlyphStringsJoinInOrder() {
        #expect(HaloHeroFormat.Shortcut.allowOnce.glyphString == "⌘Y")
        #expect(HaloHeroFormat.Shortcut.alwaysAllow.glyphString == "⌘⇧Y")
        #expect(HaloHeroFormat.Shortcut.deny.glyphString == "⌘N")
        #expect(HaloHeroFormat.Shortcut.jump.glyphString == "⌘J")
    }

    /// N3: the Codex hero's ⌘J is a **registered** binding now
    /// (`OverlayPanelController.handleJumpShortcut` fires the presented card's
    /// jump), so it earned a `Shortcut` case. The enum's contract is unchanged —
    /// every glyph it vends tracks a real handler — so the case list is exactly
    /// the four keys the controller handles, and no case may invent a fifth.
    @Test
    func everyShortcutTracksARegisteredHandler() {
        #expect(HaloHeroFormat.Shortcut.allCases.count == 4)
        let registered: Set<String> = ["⌘Y", "⌘⇧Y", "⌘N", "⌘J"]
        for shortcut in HaloHeroFormat.Shortcut.allCases {
            #expect(registered.contains(shortcut.glyphString))
        }
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
        // Outer glow `0 0 48px -8px` — G-37 raised the effective radius to 48×2/3
        // once G-36 made the hero the only glow in the frame.
        #expect(HaloHeroFormat.glowRadius == 32)
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
        // G-36/M-20: the floor is near-dark — the §E filmstrip's third frame has
        // the perimeter give up its light entirely to the card ring — but still
        // non-zero, so the silhouette keeps an amber hairline through the handoff.
        #expect(HaloEdgeLightModel.perimeterOpenHandoffFloor == 0.15)
        #expect(HaloEdgeLightModel.perimeterOpenHandoffFloor > 0)

        for state in [IslandSurfaceEdgeState.idle, .working, .success, .failure] {
            #expect(HaloEdgeLightModel.perimeterOpenHandoffOpacity(for: state, isOpened: true) == 1.0)
        }
    }

    /// G-36/M-20: dimming the ring is only half the handoff — the perimeter also
    /// drops its own bloom while a hero is presented, so the card's glow is the
    /// one loud thing. Closed, and every non-attention state, keeps its bloom.
    @Test
    func openedAttentionPerimeterSuppressesItsOwnBloom() {
        #expect(HaloEdgeLightModel.perimeterSuppressesBloom(for: .permission, isOpened: true))
        #expect(HaloEdgeLightModel.perimeterSuppressesBloom(for: .question, isOpened: true))

        for state in [IslandSurfaceEdgeState.idle, .working, .success, .failure] {
            #expect(!HaloEdgeLightModel.perimeterSuppressesBloom(for: state, isOpened: true))
        }
        for state in IslandSurfaceEdgeState.allCases {
            #expect(!HaloEdgeLightModel.perimeterSuppressesBloom(for: state, isOpened: false))
        }
    }

    // MARK: - Scoped-grant label (G-21 · mockup `.scope code`)

    /// The rule fragment becomes the amber `code` chip; the sentence around it is
    /// preserved verbatim, and the longest present candidate wins so the
    /// `shortenedPath` form beats its own prefix.
    @Test
    func scopeLabelSplitsAroundTheRuleFragment() {
        let split = HaloHeroFormat.scopeLabel(
            "Yes, allow writing to AGENTS.md/ in this project",
            candidates: ["AGENTS.md/", "AGENTS.md", "Edit"]
        )
        #expect(split.leading == "Yes, allow writing to")
        #expect(split.code == "AGENTS.md")      // the display `/` is trimmed off the chip
        #expect(split.trailing == "in this project")
    }

    /// N2: `approval.alwaysAllow` is the shared `Always Allow (%@)` template, so
    /// splitting it around the tool name would strand its brackets either side of
    /// the chip (`Always Allow ( exec_command )`). The mockup §E writes a scope row
    /// as a sentence with the chip inline, so the bracket facing the chip is
    /// dropped — Halo-side, with the shared string untouched.
    @Test
    func scopeLabelDropsTheBracketsTheTemplateWrappedTheSubstitutionIn() {
        let split = HaloHeroFormat.scopeLabel("Always Allow (exec_command)", candidates: ["exec_command"])
        #expect(split.leading == "Always Allow")
        #expect(split.code == "exec_command")
        #expect(split.trailing.isEmpty)
    }

    /// The zh templates wrap `%@` in **fullwidth** brackets (`始终允许（%@）`), so the
    /// strip has to know both forms or the localized row keeps the orphans.
    @Test
    func scopeLabelDropsFullwidthBracketsForTheChineseTemplates() {
        for label in ["始终允许（exec_command）", "始終允許（exec_command）"] {
            let split = HaloHeroFormat.scopeLabel(label, candidates: ["exec_command"])
            #expect(split.code == "exec_command")
            #expect(!split.leading.contains("（"))
            #expect(split.trailing.isEmpty)
        }
    }

    /// A sentence with no recognisable rule fragment degrades to a flat row.
    @Test
    func scopeLabelWithoutAMatchRendersWhole() {
        let split = HaloHeroFormat.scopeLabel("Yes, and bypass permissions", candidates: ["Bash", nil])
        #expect(split.leading == "Yes, and bypass permissions")
        #expect(split.code == nil)
        #expect(split.trailing.isEmpty)
    }
}
