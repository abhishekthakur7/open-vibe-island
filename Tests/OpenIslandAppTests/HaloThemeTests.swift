import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-340 (T21 · Halo 1/N): the Halo theme's shell — the pure-black void token
/// identity, the edge-light accent + wash tables, the ambient motion periods, the
/// grown window insets, the mono/sans typography floor, the bloomed-circle
/// agents-grid geometry, and the "never color alone" edge-state resolver.
///
/// Halo is built **unregistered** across T21–T25 (T26 registers it), so these
/// tests instantiate `HaloTheme()` / read `IslandThemeTokens.halo` directly rather
/// than through the registry. One assertion documents the interim registry state.
///
/// `@MainActor` because `HaloTheme` is a main-actor value type.
@MainActor
struct HaloThemeTests {

    // MARK: - Registry position (AC: appended after Annual, non-default)

    /// T26 (AB-345) registers Halo: appended to `ThemeRegistry.all` **after**
    /// `AnnualTheme()`, **non-default**. Poured Island stays `all[0]` (the product's
    /// face), and `theme(id:)` now resolves the real theme instead of falling back.
    /// This pins the position so a reorder (or a change of default) is caught.
    @Test
    func haloIsRegisteredAfterAnnualAndIsNotTheDefault() {
        let ids = ThemeRegistry.all.map(\.id)
        // Present and resolvable by id.
        #expect(ids.contains("halo"))
        #expect(ThemeRegistry.theme(id: "halo").id == "halo")
        // Full registry order (spec §7): Halo appended last, after Annual.
        #expect(ids == ["poured", "classic", "instrument", "flightDeck", "annual", "halo"])
        let haloIndex = ids.firstIndex(of: "halo")
        let annualIndex = ids.firstIndex(of: AnnualTheme().id)
        #expect(haloIndex != nil && annualIndex != nil)
        #expect(haloIndex == ids.count - 1)          // last entry
        #expect(annualIndex! + 1 == haloIndex!)       // directly after Annual
        // Non-default: Poured stays the product's face at slot 0.
        #expect(ThemeRegistry.default.id == "poured")
        #expect(ThemeRegistry.default.id != "halo")
        #expect(ids.first == "poured")
    }

    // MARK: - Surface: the pure-black void (the defining value)

    /// `surfaceInk` is **#000000** — pure black — the theme's whole identity. It is
    /// darker than every shipped ink (`flightDeckInk #08090A` was the previous
    /// floor). Pinned so the OLED void never drifts to a near-black.
    @Test
    func surfaceInkIsPureBlackTheDefiningValue() {
        let colors = IslandThemeTokens.halo.colors
        #expect(colors.surfaceInk == Color(red: 0, green: 0, blue: 0))
        // Darker than the previous floor (Flight Deck's #08090A).
        #expect(colors.surfaceInk != Color(red: 0x08 / 255.0, green: 0x09 / 255.0, blue: 0x0a / 255.0))
        // The ramp is pure white — opacity is applied to it for the text tiers.
        #expect(colors.paper == .white)
        #expect(colors.surfaceText == .white)
    }

    // MARK: - Status tints (8-bit component equality per hex)

    @Test
    func statusTintsPinToTheSpecHex() {
        let colors = IslandThemeTokens.halo.colors
        // running cyan #33DCFF (orbit primary).
        #expect(colors.statusRunning == Color(red: 0x33 / 255.0, green: 0xDC / 255.0, blue: 0xFF / 255.0))
        // completed green #5FE39A (success bloom).
        #expect(colors.statusCompleted == Color(red: 0x5F / 255.0, green: 0xE3 / 255.0, blue: 0x9A / 255.0))
        // approval amber #FFB14D (hottest attention).
        #expect(colors.statusWaitingForApproval == Color(red: 0xFF / 255.0, green: 0xB1 / 255.0, blue: 0x4D / 255.0))
        // answer qgold #FFCF7A (softer question).
        #expect(colors.statusWaitingForAnswer == Color(red: 0xFF / 255.0, green: 0xCF / 255.0, blue: 0x7A / 255.0))
        // aggregate = attention amber (roll-up).
        #expect(colors.statusWaitingAggregate == Color(red: 0xFF / 255.0, green: 0xB1 / 255.0, blue: 0x4D / 255.0))
        #expect(colors.statusWaitingAggregate == colors.statusWaitingForApproval)
        // warning / interrupted amber #E6AA42 (= flightDeckCaution).
        #expect(colors.statusWarning == Color(red: 0xE6 / 255.0, green: 0xAA / 255.0, blue: 0x42 / 255.0))
        #expect(colors.statusInterrupted == Color(red: 0xE6 / 255.0, green: 0xAA / 255.0, blue: 0x42 / 255.0))
        #expect(colors.statusWarning == colors.statusInterrupted)
        // failed static dim red #E0596C.
        #expect(colors.statusFailed == Color(red: 0xE0 / 255.0, green: 0x59 / 255.0, blue: 0x6C / 255.0))
        // idle is a *dot* (white@.42 fine for a mark); inactive dims to white@.28.
        #expect(colors.statusIdle == Color.white.opacity(0.42))
        #expect(colors.statusInactive == Color.white.opacity(0.28))
    }

    // MARK: - Text ramp + hairline (the corrected tertiary opacity)

    @Test
    func textRampAndHairlineOpacitiesPin() {
        let colors = IslandThemeTokens.halo.colors
        // t2 white@.63 — 7.4:1 on black (repo peers use 0.60; adopt the mockup).
        #expect(colors.secondaryTextOpacity == 0.63)
        // The idle-edge hairline / dividers are 8%-white.
        #expect(colors.hairlineOpacity == 0.08)
        #expect(colors.hairlineOpacityIncreasedContrast == 0.24)
        #expect(colors.increasedContrastTextBoost == 0.24)
    }

    /// The mockup's `--t3` — white @ 0.42. Increase-Contrast lifts it by
    /// `increasedContrastTextBoost` for the accessibility path.
    @Test
    func tertiaryTextOpacityMatchesTheMockupsT3() {
        let colors = IslandThemeTokens.halo.colors
        #expect(colors.tertiaryTextOpacity == 0.42)
    }

    // MARK: - Metrics (radii, fillet, hover, shadow, the grown insets)

    @Test
    func metricsPinRadiiFilletHoverAndSurfaceShadow() {
        let metrics = IslandThemeTokens.halo.metrics
        // Morph targets (top 0→20, bottom height/2→20).
        #expect(metrics.openedTopRadius == 20)
        #expect(metrics.openedBottomRadius == 20)
        // Plain concave top corner (the non-vibrancy path) — no poured fillet.
        #expect(metrics.filletRadius == 0)
        // Same closed-hover lift as Poured.
        #expect(metrics.closedHoverScale == 1.03)
        // Deep black drop shadow so the OLED cutout reads seated on the desk.
        #expect(metrics.surfaceShadow == IslandShadowToken(color: .black, opacity: 0.6, radius: 30, yOffset: 12))
    }

    /// The grown shadow insets are load-bearing: `OverlayPanelController` sizes the
    /// overlay window from these tokens (via `IslandChromeLayout`'s per-axis
    /// `max(opened, closed)`, live since AB-320), and Halo's attention bloom
    /// (~46pt) and permission card outer glow (48pt) both bleed **outside** their
    /// silhouettes. If these regress to Poured/Flight-Deck values the loudest light
    /// is clipped at the window edge and the "visible across the room" claim fails —
    /// so they are pinned to the SPEC's grown values (40/48 opened, 40/44 closed).
    @Test
    func grownShadowInsetsArePinnedBecauseWindowSizingDependsOnThem() {
        let metrics = IslandThemeTokens.halo.metrics
        #expect(metrics.openedShadowHorizontalInset == 40)
        #expect(metrics.openedShadowBottomInset == 48)
        #expect(metrics.closedShadowHorizontalInset == 40)
        #expect(metrics.closedShadowBottomInset == 44)
        // Larger than every shipped flat theme (Flight Deck / Annual / Instrument
        // all reserve Classic's 18/22 · 12/14).
        #expect(metrics.openedShadowHorizontalInset > IslandThemeTokens.flightDeck.metrics.openedShadowHorizontalInset)
        #expect(metrics.closedShadowBottomInset > IslandThemeTokens.flightDeck.metrics.closedShadowBottomInset)
    }

    // MARK: - Motion (open/close/pop/unmount)

    @Test
    func motionTokensPinTheFluidLightTravelsSprings() {
        let motion = IslandThemeTokens.halo.motion
        #expect(motion.openAnimation == .spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0))
        // M-26: the close is the open reversed — same spring, both directions.
        #expect(motion.closeAnimation == .spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0))
        #expect(motion.popAnimation == .spring(response: 0.34, dampingFraction: 0.66, blendDuration: 0))
        #expect(motion.openedSurfaceUnmountDelay == 0.36)
    }

    // MARK: - Material + capability flags (opaque void, no specular)

    @Test
    func haloIsAnOpaqueVoidWithNoVibrancyOrSpecular() {
        let theme = HaloTheme()
        // Opaque OLED void — no vibrancy, so the opened surface takes the opaque
        // `surfaceInk` path and Reduce Transparency is a no-op.
        #expect(theme.usesVibrancy == false)
        // The animated 1.5pt perimeter edge *replaces* the specular concept, so
        // the material carries none; the ink fallback is fully opaque.
        #expect(theme.tokens.material.specularTopEdge == nil)
        #expect(theme.tokens.material.tintOpacity == 1.0)
        #expect(theme.tokens.material.material == .hudWindow)
        #expect(theme.tokens.material.blendingMode == .behindWindow)
        #expect(theme.tokens.material.appearanceName == .vibrantDark)
    }

    /// The row's own rail glow + dot bloom bleed outside the row silhouette, so a
    /// `.drawingGroup()` flatten would clip them — the row opts out of that
    /// rasterization (the panel edge is on the surface, not the row).
    @Test
    func rowsAreDrawingGroupUnsafeForRailGlowAndDotBloom() {
        #expect(HaloTheme().rowIsDrawingGroupSafe == false)
    }

    // MARK: - Question-prompt pagination (overlay remediation Phase 2B · F1a/D1)

    /// Halo's board (`06-halo.html:1067-1156`) shows one question per page — two
    /// separate frames, "1 of 2" / "Next" then "2 of 2" / "Submit" — pinned here
    /// at the type level, alongside the visual proof in
    /// `HaloConformanceSnapshotTests.testQuestionHero` / `testQuestionHeroSubmitEnabled`.
    @Test
    func questionPageSizeIsOnePerPage() {
        #expect(HaloTheme().questionPageSize == 1)
    }

    // MARK: - Halo-local edge accents + washes

    @Test
    func edgeAccentsAndWashesPinToTheSpecHex() {
        // Gradient partner stops.
        #expect(HaloEdge.violet == Color(red: 0x7C / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0))
        #expect(HaloEdge.magenta == Color(red: 0xFF / 255.0, green: 0x5E / 255.0, blue: 0xA8 / 255.0))
        // Usage thresholds (fine = green, warn = qgold, crit distinct).
        #expect(HaloEdge.usageFine == Color(red: 0x5F / 255.0, green: 0xE3 / 255.0, blue: 0x9A / 255.0))
        #expect(HaloEdge.usageWarn == Color(red: 0xFF / 255.0, green: 0xCF / 255.0, blue: 0x7A / 255.0))
        #expect(HaloEdge.usageCrit == Color(red: 0xFF / 255.0, green: 0x6B / 255.0, blue: 0x6B / 255.0))
        // fine/warn intentionally equal the green/qgold status tints.
        #expect(HaloEdge.usageFine == IslandThemeTokens.halo.colors.statusCompleted)
        #expect(HaloEdge.usageWarn == IslandThemeTokens.halo.colors.statusWaitingForAnswer)
        // Washes.
        #expect(HaloEdge.hair2 == Color.white.opacity(0.05))
        #expect(HaloEdge.lift == Color.white.opacity(0.028))
    }

    // MARK: - Halo-local metrics

    @Test
    func haloMetricConstantsPin() {
        #expect(HaloMetrics.edge == 1.5)  // the theme's signature
        #expect(HaloMetrics.railWidth == 2)
        #expect(HaloMetrics.railInsetY == 8)
        #expect(HaloMetrics.dot == 8)
        #expect(HaloMetrics.heroRadius == 16)
        #expect(HaloMetrics.heroRingWidth == 1.5)
        #expect(HaloMetrics.gridCell == 6)
        #expect(HaloMetrics.gridGap == 3.5)
        #expect(HaloMetrics.gridRadius == 3)
    }

    // MARK: - Halo-local ambient motion periods

    @Test
    func haloMotionPeriodsPin() {
        #expect(HaloMotion.orbit == 6)
        #expect(HaloMotion.permissionPulse == 1.9)
        #expect(HaloMotion.question == 2.6)
        #expect(HaloMotion.success == 3)
        #expect(HaloMotion.sweep == 0.7)
        #expect(HaloMotion.heroRing == 2.2)
        #expect(HaloMotion.wave == 1.05)
        #expect(HaloMotion.breathe == 2.4)
        #expect(HaloMotion.gridDot == 2)
        // Permission pulses faster than question — attention outranks by cadence.
        #expect(HaloMotion.permissionPulse < HaloMotion.question)
    }

    // MARK: - Typography floor (every readable role ≥ 10pt)

    @Test
    func everyReadableTypographyRoleHoldsTheTenPointFloor() {
        #expect(HaloTypography.floor == 10)
        #expect(!HaloTypography.readableRoleSizes.isEmpty)
        for size in HaloTypography.readableRoleSizes {
            #expect(size >= HaloTypography.floor)
        }
        // The four lifted roles the SPEC pins explicitly all sit at the floor.
        #expect(HaloTypography.usageKickerSize == 10)   // .fk  9  → 10
        #expect(HaloTypography.metadataKeySize == 10)   // .mk  9  → 10
        #expect(HaloTypography.thresholdPillSize == 10) // .thl 9.5 → 10
        #expect(HaloTypography.monogramSize == 10)      // .mono-tag 9.5 → 10
    }

    /// F19: both nest-header captions build from one named 10pt bold-sans role
    /// and its shared 0.09em tracking value. `Font` itself is opaque, so the
    /// family and size contracts remain pinned through `roleFamilies`; the
    /// declaration of `nestHeader` is the single source for its bold weight.
    @Test
    func nestHeaderCaptionRolePinsSansSizeAndTracking() {
        #expect(HaloTypography.nestHeaderSize == 10)
        #expect(HaloTypography.family(of: "nestHeader") == .sans)
        #expect(abs(HaloTypography.nestHeaderTracking - 0.9) < 0.000_001)
        #expect(HaloTypography.nestHeaderTracking == HaloTypography.nestHeaderSize * 0.09)
    }

    // MARK: - Mono/sans split (mono limited to the five code roles)

    /// Halo is a sans face; mono (`.system(design: .monospaced)`) is reserved for
    /// exactly five *scanned* code/value roles — command · diff · branch ·
    /// inline-code · pill-value. Tabular numerals ride `.monospacedDigit()` on the
    /// sans face, not a mono switch. A `Font` is opaque, so this is pinned on the
    /// `roleFamilies` table the font builders derive their design from (T18's move).
    @Test
    func monoSansSplitHoldsTheFiveCodeRoles() {
        // Exactly the five reserved roles are mono.
        #expect(HaloTypography.monoRoleNames == ["command", "diff", "branchDisamb", "assistantInlineCode", "pillValue"])
        #expect(HaloTypography.family(of: "command") == .mono)
        #expect(HaloTypography.family(of: "diff") == .mono)
        #expect(HaloTypography.family(of: "branchDisamb") == .mono)
        #expect(HaloTypography.family(of: "assistantInlineCode") == .mono)
        #expect(HaloTypography.family(of: "pillValue") == .mono)

        // Narration / label / value roles are sans — the reader *reads* these.
        #expect(HaloTypography.family(of: "workspaceTitle") == .sans)
        #expect(HaloTypography.family(of: "activity") == .sans)
        #expect(HaloTypography.family(of: "questionText") == .sans)
        #expect(HaloTypography.family(of: "assistant") == .sans)
        #expect(HaloTypography.family(of: "monogram") == .sans)
        // Tabular counters stay on the sans face (mono is not the whole face).
        #expect(HaloTypography.family(of: "optionNumber") == .sans)
        #expect(HaloTypography.family(of: "age") == .sans)
        #expect(HaloTypography.family(of: "summaryNumber") == .sans)

        // The two families map onto the two `Font.Design`s the split intends.
        #expect(HaloTypography.Family.sans.design == .default)
        #expect(HaloTypography.Family.mono.design == .monospaced)

        // Every role declares a family; an unknown role is nil; the table has no
        // more than five mono roles.
        #expect(HaloTypography.family(of: "does-not-exist") == nil)
        #expect(HaloTypography.roleFamilies.allSatisfy { !$0.name.isEmpty })
        #expect(HaloTypography.monoRoleNames.count == 5)
    }

    // MARK: - Agents-grid geometry (bloomed circles; balancedRows delegates)

    /// Halo reuses Classic's balanced matrix verbatim (so the pill width math and
    /// morph frame are unchanged), but overrides `cellGeometry` to `(6, 3.5, 3)` so
    /// each cell renders as a bloomed light circle (radius = cell / 2). Classic's
    /// `AgentsGridLayoutTests` are untouched — the deviation lives only here.
    @Test
    func gridGeometryReusesClassicMatrixButBloomsTheCellsIntoCircles() {
        let geometry = HaloTheme().agentsGridGeometry

        // `balancedRows` delegates to the shared V6RightSlotView implementation —
        // call both and compare across n = 1…9 (and beyond).
        for n in 1...9 {
            #expect(geometry.balancedRows(n) == V6RightSlotView.balancedRows(n))
        }
        for n in [0, 10, 20] {
            #expect(geometry.balancedRows(n) == V6RightSlotView.balancedRows(n))
        }

        // `cellGeometry` is the constant bloomed-circle geometry for every matrix.
        for rowCount in 1...3 {
            let g = geometry.cellGeometry(rowCount)
            #expect(g.cell == 6)
            #expect(g.gap == 3.5)
            #expect(g.radius == 3)
            // Bloomed circle: radius is exactly half the cell.
            #expect(g.radius == g.cell / 2)
        }
        // It is a deliberate deviation from Classic's row-count-dependent geometry.
        #expect(geometry.cellGeometry(3).cell != V6RightSlotView.cellGeometry(rowCount: 1).cell
            || geometry.cellGeometry(3).radius != V6RightSlotView.cellGeometry(rowCount: 1).radius)
    }

    // MARK: - "Never color alone" (non-color channel per state)

    /// Halo conveys state through moving light, so every state must also carry a
    /// non-color channel. `HaloSessionRowFormat` resolves a distinct **glyph** and
    /// a distinct **edge-motion** per state — the pure logic T23/T25 consume — so
    /// the state stays legible for color-blind users and under Reduce Motion (where
    /// the light freezes). This mirrors `AnnualSessionRowFormat`'s discipline test.
    @Test
    func everyEdgeStateCarriesANonColorGlyphAndMotionChannel() {
        let states = HaloSessionRowFormat.EdgeState.allCases
        #expect(states.count == 7)

        // A non-empty glyph exists for every state, and all seven are distinct —
        // so no state is carried by hue alone.
        let glyphs = states.map { HaloSessionRowFormat.statusGlyphName($0) }
        #expect(glyphs.allSatisfy { !$0.isEmpty })
        #expect(Set(glyphs).count == states.count)

        // The outcome forks read differently from a clean finish (SPEC §4).
        #expect(HaloSessionRowFormat.statusGlyphName(.success) == "checkmark")
        #expect(HaloSessionRowFormat.statusGlyphName(.interrupted) == "stop.fill")
        #expect(HaloSessionRowFormat.statusGlyphName(.failed) == "xmark")
        #expect(HaloSessionRowFormat.statusGlyphName(.success)
            != HaloSessionRowFormat.statusGlyphName(.failed))

        // The motion channel: permission blooms (loudest), question only pulses,
        // failure is STATIC (never pulses — visibly distinct from attention), idle
        // is off. Permission vs question are distinct by motion as well as hue.
        #expect(HaloSessionRowFormat.edgeMotion(.running) == .orbit)
        #expect(HaloSessionRowFormat.edgeMotion(.permission) == .bloom)
        #expect(HaloSessionRowFormat.edgeMotion(.question) == .pulse)
        #expect(HaloSessionRowFormat.edgeMotion(.success) == .settle)
        #expect(HaloSessionRowFormat.edgeMotion(.failed) == .staticColor)
        #expect(HaloSessionRowFormat.edgeMotion(.idle) == .off)
        #expect(HaloSessionRowFormat.edgeMotion(.permission)
            != HaloSessionRowFormat.edgeMotion(.question))
    }

    /// The edge-state resolver maps phase / presence / outcome exactly, and an
    /// inactive process always recedes to `idle` so a dead session never keeps a
    /// loud edge (mirrors `AnnualSessionRowFormat.statusMark`).
    @Test
    func edgeStateResolverMapsPhasePresenceAndOutcome() {
        typealias F = HaloSessionRowFormat
        #expect(F.edgeState(phase: .running, presence: .running, outcome: .success) == .running)
        #expect(F.edgeState(phase: .waitingForApproval, presence: .running, outcome: .success) == .permission)
        #expect(F.edgeState(phase: .waitingForAnswer, presence: .running, outcome: .success) == .question)
        #expect(F.edgeState(phase: .completed, presence: .active, outcome: .success) == .success)
        #expect(F.edgeState(phase: .completed, presence: .active, outcome: .interrupted) == .interrupted)
        #expect(F.edgeState(phase: .completed, presence: .active, outcome: .failed) == .failed)
        // An inactive process recedes to idle regardless of stored phase.
        #expect(F.edgeState(phase: .running, presence: .inactive, outcome: .success) == .idle)
        #expect(F.edgeState(phase: .waitingForApproval, presence: .inactive, outcome: .success) == .idle)
    }

    // MARK: - Collapsed-row rail mapping (AB-344 · SPEC §5C/§5D)

    /// The collapsed row's edge-lit rail marks **only** the live / actionable rows —
    /// running, permission, question — and is absent on every settled or idle row
    /// (success / interrupted / failed / idle), so a list with nothing live is
    /// rail-free and calm. Pure logic pinned here so the phase → rail mapping can't
    /// drift without a rendered row (AB-344 acceptance).
    @Test
    func railAppearsOnlyOnLiveAndActionableRows() {
        typealias F = HaloSessionRowFormat
        // The three states that draw a rail, each with its distinct style.
        #expect(F.rail(for: .running) == .running)
        #expect(F.rail(for: .permission) == .permission)
        #expect(F.rail(for: .question) == .question)
        // Every settled / idle state is rail-free.
        #expect(F.rail(for: .success) == nil)
        #expect(F.rail(for: .interrupted) == nil)
        #expect(F.rail(for: .failed) == nil)
        #expect(F.rail(for: .idle) == nil)

        // Exactly the live/actionable states carry a rail — no more, no fewer.
        let railed = F.EdgeState.allCases.filter { F.rail(for: $0) != nil }
        #expect(Set(railed) == [.running, .permission, .question])

        // The three rail styles are distinct (each state reads a different rail).
        let styles = railed.map { F.rail(for: $0) }
        #expect(Set(styles).count == 3)
    }

    // MARK: - Agent monogram derivation (achromatic identity mark)

    /// The achromatic monogram is a single upper-cased identity initial taken from
    /// the agent's short name — never a hue (identity stays a grey whisper, brief
    /// §7). The first *alphanumeric* scalar is used so a punctuation-led name still
    /// yields a readable mark, and an empty / symbol-only name falls back to a
    /// neutral bullet rather than an empty chip.
    @Test
    func monogramIsASingleUppercasedAlphanumericInitial() {
        typealias F = HaloSessionRowFormat
        #expect(F.monogram(agentShortName: "CLAUDE") == "C")
        #expect(F.monogram(agentShortName: "codex") == "C")
        #expect(F.monogram(agentShortName: "GEMINI") == "G")
        // Leading punctuation is skipped to the first readable character.
        #expect(F.monogram(agentShortName: "· kimi") == "K")
        // Every shipped agent yields a non-empty, single-character mark.
        for tool in AgentTool.allCases {
            let mark = F.monogram(agentShortName: tool.shortName)
            #expect(mark.count == 1)
            #expect(!mark.isEmpty)
        }
        // Degenerate names fall back to the neutral bullet, never an empty string.
        #expect(F.monogram(agentShortName: "") == "•")
        #expect(F.monogram(agentShortName: "—") == "•")
    }

    // MARK: - Subagents & completion formats (Part 2 · §5G/§5H)

    /// AC (§5G): against the shared T08 `subagentsAndTasks` fixtures (`startedAt` at
    /// −42 / −75 / −8s) the three subagents read `0m 42s` / `1m 15s` / `0m 08s` —
    /// the exact tabular readouts the ticket pins, matching Flight Deck's own
    /// `engineElapsedLabel` so the two themes read one span the same way. Minutes
    /// never roll into hours (a live count stays a minute column) and a negative
    /// interval clamps to `0m 00s`, never a `-` glyph.
    @Test
    func subagentElapsedLabelMatchesTheT08FixtureReadouts() {
        typealias F = HaloSessionRowFormat
        #expect(F.subagentElapsedLabel(seconds: 42) == "0m 42s")
        #expect(F.subagentElapsedLabel(seconds: 75) == "1m 15s")
        #expect(F.subagentElapsedLabel(seconds: 8) == "0m 08s")
        #expect(F.subagentElapsedLabel(seconds: 90 * 60) == "90m 00s")
        #expect(F.subagentElapsedLabel(seconds: -5) == "0m 00s")
    }

    /// The expanded subagent stop is a combined VoiceOver node. Its status is
    /// deliberately labelled on the dot child (as in Poured), rather than on the
    /// parent: a parent label replaces the combined type, task, and elapsed text.
    /// This source-level regression covers the SwiftUI declaration; native AX
    /// hierarchy capture remains a manual/harness concern.
    @Test
    func expandedSubagentAccessibilityCombinesStatusTypeTaskAndElapsed() throws {
        let row = try haloSessionRowSource()
        let start = try #require(row.range(of: "private func subagentRow("))
        let end = try #require(row.range(of: "private func subagentTypeText", range: start.upperBound..<row.endIndex))
        let subagentRow = String(row[start.lowerBound..<end.lowerBound])

        #expect(subagentRow.contains(".accessibilityElement(children: .combine)"))
        #expect(subagentRow.contains(".accessibilityLabel(lang.t(isRunning ? \"a11y.subagent.running\" : \"subagents.completed\"))"))
        #expect(subagentRow.contains("Text(subagentTypeText(sub))"))
        #expect(subagentRow.contains("Text(task)"))
        #expect(subagentRow.contains("subagentElapsed(sub, isRunning: isRunning)"))
        #expect(!subagentRow.contains(".accessibilityHidden(true)"))
        #expect(subagentRow.components(separatedBy: ".accessibilityLabel(").count - 1 == 1)
    }

    /// AC (§5H): the completion Duration reads `14m 08s` (the mockup example,
    /// 848s) as a mono tabular span, rolls into an hours field for a multi-hour run
    /// (`1h 05m 30s`) so it never reads a misleading `65m 30s`, and clamps a
    /// negative span (clock skew) to `0m 00s`.
    @Test
    func durationLabelFormatsTheCompletionRunLength() {
        typealias F = HaloSessionRowFormat
        #expect(F.durationLabel(seconds: 14 * 60 + 8) == "14m 08s")
        #expect(F.durationLabel(seconds: 43 * 60) == "43m 00s")
        #expect(F.durationLabel(seconds: 3600 + 5 * 60 + 30) == "1h 05m 30s")
        #expect(F.durationLabel(seconds: -1) == "0m 00s")
    }

    /// AC (§5H): the outcome badge maps each `SessionOutcome` to a **distinct**
    /// glyph — a check for success, a stop for interrupted, a cross for failed — so
    /// a non-success completion is never carried by hue alone (SPEC §K). The three
    /// glyphs are pairwise distinct.
    @Test
    func outcomeBadgeGlyphsAreDistinctPerOutcome() {
        typealias O = HaloSessionRowFormat.Outcome
        #expect(O.success.glyphName == "checkmark")
        #expect(O.interrupted.glyphName == "stop.fill")
        #expect(O.failed.glyphName == "xmark")
        #expect(O(.success) == .success)
        #expect(O(.interrupted) == .interrupted)
        #expect(O(.failed) == .failed)
        let glyphs = O.allCases.map(\.glyphName)
        #expect(Set(glyphs).count == O.allCases.count)
    }

    private func haloSessionRowSource() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repository = testsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repository.appendingPathComponent("Sources/OpenIslandApp/Views/Island/HaloSessionRow.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    // MARK: - Identity strings localize (AC: name/descriptor per language ≠ key)

    /// The theme's `name` / `descriptor` resolve to real translations — not the bare
    /// key — in English and both Chinese scripts (mirrors `AnnualThemeTests`). The
    /// drafted values (`Halo` / `Prismatic edge-light on a true-black void.`) are
    /// implemented as specced; naming is flagged as pending user confirmation.
    @Test
    func themeNameAndDescriptorLocalizeInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let theme = HaloTheme()
        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            let name = theme.name(manager)
            let descriptor = theme.descriptor(manager)
            #expect(!name.isEmpty)
            #expect(name != "theme.halo.name", "name is unlocalized in \(language)")
            #expect(!descriptor.isEmpty)
            #expect(descriptor != "theme.halo.descriptor", "descriptor is unlocalized in \(language)")
        }
    }

    /// Every Halo quiet-slot copy key (empty-state title / confident subtitle /
    /// monitoring pill singular+plural / SETUP CTA) resolves to a real translation
    /// in English and both Chinese scripts, so the void frame never renders a bare
    /// key. The `%lld` workspace pill keys carry a real localized template.
    @Test
    func haloQuietSlotStringsLocalizeInEveryLanguage() {
        let originalLanguage = UserDefaults.standard.string(forKey: "appLanguage")
        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: "appLanguage")
            } else {
                UserDefaults.standard.removeObject(forKey: "appLanguage")
            }
        }

        let keys = [
            "island.halo.empty.allQuiet",
            "island.halo.empty.watching",
            "island.halo.empty.monitoring",
            "island.halo.empty.workspaceOne",
            "island.halo.empty.workspaceOther",
            "island.halo.hint.setup",
        ]

        for language in [LanguageManager.AppLanguage.en, .zhHans, .zhHant] {
            let manager = LanguageManager()
            manager.language = language
            for key in keys {
                let resolved = manager.t(key)
                #expect(resolved != key, "\(key) is unlocalized in \(language)")
                #expect(!resolved.isEmpty)
            }
        }
    }

    // MARK: - §5F question q-tag format (pure)

    /// The `.q-tag` chip label (§5F) is the first question's `header` when it names a
    /// real category, capped at ≤12 graphemes. A long header truncates; a `nil`
    /// prompt yields no chip; the generic "Answer needed" umbrella is replaced by the
    /// localized `Question` fallback so the chip never echoes the annunciator title.
    @Test
    func questionTagResolvesHeaderCappedWithFallback() {
        let lang = LanguageManager()
        lang.language = .en

        // No prompt → no chip.
        #expect(HaloQuestionFormat.tag(for: nil, lang: lang) == nil)

        // A real category header passes through verbatim (≤12 chars).
        let auth = QuestionPrompt(
            title: "Bridge design",
            questions: [QuestionPromptItem(question: "Which auth?", header: "Auth", options: [QuestionOption(label: "A")])]
        )
        #expect(HaloQuestionFormat.tag(for: auth, lang: lang) == "Auth")

        // A long header is truncated to the 12-char cap.
        let long = QuestionPrompt(
            title: "T",
            questions: [QuestionPromptItem(question: "Q", header: "Authentication strategy", options: [QuestionOption(label: "A")])]
        )
        let longTag = HaloQuestionFormat.tag(for: long, lang: lang)
        #expect(longTag != nil)
        #expect((longTag?.count ?? 0) <= HaloQuestionFormat.maxTagLength)
        #expect(longTag == "Authenticati")

        // An empty / generic header falls back to the localized "Question" tag.
        let generic = QuestionPrompt(
            title: "T",
            questions: [QuestionPromptItem(question: "Q", header: "", options: [QuestionOption(label: "A")])]
        )
        #expect(HaloQuestionFormat.tag(for: generic, lang: lang) == lang.t("island.halo.question.tag"))
        #expect(HaloQuestionFormat.tag(for: generic, lang: lang) == "Question")
    }
}
