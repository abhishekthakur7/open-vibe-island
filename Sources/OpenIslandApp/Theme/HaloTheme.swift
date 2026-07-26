import AppKit
import SwiftUI
import OpenIslandCore

/// The two-font typography system for the Halo theme (SPEC-halo §2 · AB-340).
///
/// Halo carries **all** structure in typography + hairlines — there are no
/// fills, no cards — so this table is load-bearing. The shared `IslandThemeTokens`
/// layer deliberately carries no typography (themes swap whole slot views), so
/// this enum is Halo's own scale, kept in one place so every Halo view draws
/// from the same roles and the ≥10pt floor is enforceable in one spot
/// (`HaloThemeTests`). It mirrors `FlightDeckTypography` / `AnnualTypography`.
///
/// **The mono/sans split (SPEC §2 numeral rule).** Halo is a *sans* face —
/// `.system(design: .default)` — everywhere the reader *reads* prose. Mono
/// (`.system(design: .monospaced)`) is reserved for exactly five value roles the
/// reader *scans* as code: **command · diff · branch · inline-code · pill-value**.
/// Tabular numerals (age, timers, counts, percentages) ride `.monospacedDigit()`
/// on the sans face at the view layer — they do **not** switch the whole face to
/// mono. Each role declares its `Family`, and the font builders derive their
/// `design` from it, so the mono/sans contract is one table `HaloThemeTests` can
/// pin (a `Font` is opaque and can't be introspected at runtime).
///
/// **Floor discipline.** No *readable* role dips below `floor` (10pt): the
/// mockup's sub-10pt caps roles (`.fk` 9, `.mk` 9, `.thl` 9.5, `.mono-tag` 9.5)
/// are lifted to the 10pt floor here, matching the sibling themes. The one
/// exception — the fitted grid overflow `+N`, a micro-indicator sized to its
/// annunciator light rather than a readable role — is not listed here.
enum HaloTypography {
    /// The lowest size any *readable* Halo text may use. Density comes from the
    /// void, hairlines and the edge-light — never from sub-10pt micro-type.
    static let floor: CGFloat = 10

    /// The two typefaces the split draws in: `sans` narration prose, `mono`
    /// the five scanned code/value roles. A role's `Family` is the source of
    /// truth its font's `Font.Design` is derived from.
    enum Family: Equatable {
        case sans
        case mono

        var design: Font.Design { self == .mono ? .monospaced : .default }
    }

    // MARK: Sizes (SPEC §2 table — sub-10 roles lifted to the floor)

    /// Pill label (`.lab`) — sans, 12.5.
    static let pillLabelSize: CGFloat = 12.5
    /// Pill mono value (`.lab .mn`) — **mono**, 11 (pill-value).
    static let pillValueSize: CGFloat = 11
    /// Workspace title (`.ws`) — sans, 14, weight 600.
    static let workspaceTitleSize: CGFloat = 14
    /// Branch disambiguation (`.disamb`) — **mono**, 10.5 @ t3 (branch).
    static let branchDisambSize: CGFloat = 10.5
    /// Activity line (`.act`) / verb (`.act .live`) — sans, 12.5.
    static let activitySize: CGFloat = 12.5
    /// Meta chip (`.chip`) — sans, 10.5.
    static let metaChipSize: CGFloat = 10.5
    /// Tabular meta-chip value (`.chip.mn`) — sans + `.monospacedDigit()`, 10.
    /// A scanned *value* chip; kept on the sans face (mono is reserved for the
    /// five code roles) with tabular figures applied at the view layer.
    static let metaChipValueSize: CGFloat = 10
    /// Age (`.age`) — sans + `.monospacedDigit()`, 11 @ t3.
    static let ageSize: CGFloat = 11
    /// Section header (`.grp`) — sans, 10 / 0.10em UPPER (at floor).
    static let sectionHeaderSize: CGFloat = 10
    /// Summary strip label (`.summary`) — sans, 11.
    static let summaryLabelSize: CGFloat = 11
    /// Summary number (`.b .n`) — sans + `.monospacedDigit()`, 12 / 700.
    static let summaryNumberSize: CGFloat = 12
    /// Outcome badge (`.outc`) — sans, 10.5 / 700.
    static let outcomeBadgeSize: CGFloat = 10.5
    /// Jump chip (`.jump`) — sans, 11.5 / 600.
    static let jumpChipSize: CGFloat = 11.5
    /// Hero title (`.ht`) — sans, 14 / 650.
    static let heroTitleSize: CGFloat = 14
    /// Hero subtitle (`.hs`) — sans, 11.
    static let heroSubtitleSize: CGFloat = 11
    /// Command block (`.cmd`) — **mono**, 12 (command).
    static let commandSize: CGFloat = 12
    /// Inline diff (`.diff`) — **mono**, 11.5 (diff).
    static let diffSize: CGFloat = 11.5
    /// Keycap (`.kc kbd`) — sans, 10 / 600 (at floor).
    static let keycapSize: CGFloat = 10
    /// Question text (`.qtext`) — sans, 14.5 / 560.
    static let questionTextSize: CGFloat = 14.5
    /// Option label (`.opt .ol`) — sans, 13 / 600.
    static let optionLabelSize: CGFloat = 13
    /// Option desc (`.opt .od`) — sans, 11.5.
    static let optionDescSize: CGFloat = 11.5
    /// Option number (`.opt .num`) — sans + `.monospacedDigit()`, 11 / 700.
    /// A scanned counter, kept on the sans face with tabular figures.
    static let optionNumberSize: CGFloat = 11
    /// Q chip (`.q-tag`) — sans, 10 / 700 / 0.05em UPPER (at floor).
    static let qChipSize: CGFloat = 10
    /// Subagent type (`.sty`) — sans, 12 / 600.
    static let subagentTypeSize: CGFloat = 12
    /// Subagent task (`.stk`) — sans, 11.
    static let subagentTaskSize: CGFloat = 11
    /// Subagent elapsed (`.sti`) — sans + `.monospacedDigit()`, 11.
    static let subagentElapsedSize: CGFloat = 11
    /// Nest header (`.nest-h`) — sans, 10 / 700 / 0.09em UPPER (at floor).
    static let nestHeaderSize: CGFloat = 10
    /// Todo (`.todo`) — sans, 12.
    static let todoSize: CGFloat = 12
    /// Assistant body (`.assistant`) — sans, 12.5.
    static let assistantSize: CGFloat = 12.5
    /// Assistant inline `code` — **mono**, 11 (inline-code).
    static let assistantInlineCodeSize: CGFloat = 11
    /// Metadata value (`.mv`) — sans, 12.5 / 560.
    static let metadataValueSize: CGFloat = 12.5
    /// Meter value (`.mp`) — sans + `.monospacedDigit()`, 22 / 660.
    static let meterValueSize: CGFloat = 22
    /// Empty title (`.et`) — sans, 14 / 600.
    static let emptyTitleSize: CGFloat = 14
    /// Empty subtitle (`.es`) — sans, 12.
    static let emptySubtitleSize: CGFloat = 12

    // MARK: Lifted roles (mockup sub-10 → 10pt floor — pinned by tests)

    /// Usage kicker (`.fk`) — **lifted 9 → 10**, sans.
    static let usageKickerSize: CGFloat = 10
    /// Usage value (`.fv`) — sans, 11 (already ≥ floor).
    static let usageValueSize: CGFloat = 11
    /// Metadata key (`.mk`) / grid key (`.mcell .mk`) — **lifted 9 → 10**, sans.
    static let metadataKeySize: CGFloat = 10
    /// Threshold pill (`.thl`) — **lifted 9.5 → 10**, sans.
    static let thresholdPillSize: CGFloat = 10
    /// Agent monogram (`.mono-tag`) — **lifted 9.5 → 10**, sans. Carries readable
    /// characters ("S5" / "OC"), so it is a *readable* role that lifts, unlike the
    /// fitted grid `+N` which stays exempt.
    static let monogramSize: CGFloat = 10

    // MARK: Role table (the mono/sans split contract)

    /// Every readable role, paired with the `Family` the split assigns it and its
    /// point size. The font builders read their `design` from these entries, so a
    /// role that flips family here flips its rendered font too — the contract
    /// `HaloThemeTests.monoSansSplitHoldsTheFiveCodeRoles` pins. **Exactly five**
    /// roles are `.mono` (command · diff · branch · inline-code · pill-value);
    /// every other readable role is `.sans`.
    static let roleFamilies: [(name: String, family: Family, size: CGFloat)] = [
        // The five reserved mono code/value roles.
        ("pillValue", .mono, pillValueSize),
        ("branchDisamb", .mono, branchDisambSize),
        ("command", .mono, commandSize),
        ("diff", .mono, diffSize),
        ("assistantInlineCode", .mono, assistantInlineCodeSize),
        // Sans narration / label / value roles (tabular figures where numeric are
        // applied via `.monospacedDigit()` at the view layer, not a mono face).
        ("pillLabel", .sans, pillLabelSize),
        ("workspaceTitle", .sans, workspaceTitleSize),
        ("activity", .sans, activitySize),
        ("metaChip", .sans, metaChipSize),
        ("metaChipValue", .sans, metaChipValueSize),
        ("age", .sans, ageSize),
        ("sectionHeader", .sans, sectionHeaderSize),
        ("summaryLabel", .sans, summaryLabelSize),
        ("summaryNumber", .sans, summaryNumberSize),
        ("outcomeBadge", .sans, outcomeBadgeSize),
        ("jumpChip", .sans, jumpChipSize),
        ("heroTitle", .sans, heroTitleSize),
        ("heroSubtitle", .sans, heroSubtitleSize),
        ("keycap", .sans, keycapSize),
        ("questionText", .sans, questionTextSize),
        ("optionLabel", .sans, optionLabelSize),
        ("optionDesc", .sans, optionDescSize),
        ("optionNumber", .sans, optionNumberSize),
        ("qChip", .sans, qChipSize),
        ("subagentType", .sans, subagentTypeSize),
        ("subagentTask", .sans, subagentTaskSize),
        ("subagentElapsed", .sans, subagentElapsedSize),
        ("nestHeader", .sans, nestHeaderSize),
        ("todo", .sans, todoSize),
        ("assistant", .sans, assistantSize),
        ("metadataValue", .sans, metadataValueSize),
        ("meterValue", .sans, meterValueSize),
        ("emptyTitle", .sans, emptyTitleSize),
        ("emptySubtitle", .sans, emptySubtitleSize),
        // The lifted-to-floor roles the SPEC pins explicitly.
        ("usageKicker", .sans, usageKickerSize),
        ("usageValue", .sans, usageValueSize),
        ("metadataKey", .sans, metadataKeySize),
        ("thresholdPill", .sans, thresholdPillSize),
        ("monogram", .sans, monogramSize),
    ]

    /// The `Family` a named role draws in, or `nil` for an unknown name.
    static func family(of role: String) -> Family? {
        roleFamilies.first { $0.name == role }?.family
    }

    /// Every readable role's point size — the vector `HaloThemeTests` asserts
    /// stays at or above `floor`.
    static var readableRoleSizes: [CGFloat] {
        roleFamilies.map(\.size)
    }

    /// The names of the roles that draw in the mono face — exactly the five
    /// reserved code/value roles. `HaloThemeTests` pins this set so no future
    /// role silently joins the mono face.
    static var monoRoleNames: Set<String> {
        Set(roleFamilies.filter { $0.family == .mono }.map(\.name))
    }
}

/// Halo's edge-light accent palette + wash table (SPEC-halo §1a · AB-340).
///
/// The shared `IslandColorTokens` models only *semantic status slots*. Halo's
/// living prismatic edge needs partner hues (violet, magenta) for its two
/// gradient states, plus three usage thresholds, plus two faint washes — none of
/// which are expressible as status tints. They live here, theme-local, mirroring
/// how `FlightDeckSurfaces` / `AnnualHairline` keep their theme paint outside the
/// token struct. Every value is pinned to the SPEC hex by 8-bit component
/// equality in `HaloThemeTests`.
///
/// **Discipline note (brief §7):** the edge-light is **never** brand-colored —
/// agent identity in Halo is an achromatic monogram. These accents partner the
/// *state* gradients only; `AgentSession.brandColorHex` is deliberately unused on
/// the edge.
enum HaloEdge {
    /// Working gradient stop 2 (`--violet #7C5CFF`).
    static let violet = Color(red: 0x7C / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0)
    /// Permission gradient stop 2 (`--magenta #FF5EA8`).
    static let magenta = Color(red: 0xFF / 255.0, green: 0x5E / 255.0, blue: 0xA8 / 255.0)
    /// Usage filament — fine (`--fine #5FE39A`, `< 70`). Equal to the green status.
    static let usageFine = Color(red: 0x5F / 255.0, green: 0xE3 / 255.0, blue: 0x9A / 255.0)
    /// Usage filament — warn (`--wrn #FFCF7A`, `70…90`). Equal to the qgold answer.
    static let usageWarn = Color(red: 0xFF / 255.0, green: 0xCF / 255.0, blue: 0x7A / 255.0)
    /// Usage filament — critical (`--crit #FF6B6B`, `≥ 90`).
    static let usageCrit = Color(red: 0xFF / 255.0, green: 0x6B / 255.0, blue: 0x6B / 255.0)

    // MARK: Washes (below the token model)

    /// Code-block inset stroke (`--hair2 white@.05`).
    static let hair2 = Color.white.opacity(0.05)
    /// Mono-block whisper fill (`--lift white@.028`).
    static let lift = Color.white.opacity(0.028)
}

/// Halo's view-level geometry constants (SPEC-halo §1b · AB-340).
///
/// The shared `IslandMetricsTokens` models only the overlay's chrome geometry
/// (opened radii, shadow insets, hover scale, fillet). Halo's signature — the
/// 1.5pt prismatic edge, the edge-lit rail, the hero ring, the bloomed grid
/// circles — needs its own leaf metrics, kept here exactly as the sibling themes
/// keep their view constants. Pinned by `HaloThemeTests`.
enum HaloMetrics {
    /// Prismatic edge thickness — **1.5pt** is the theme's signature.
    static let edge: CGFloat = 1.5
    /// Actionable-row edge-lit rail width.
    static let railWidth: CGFloat = 2
    /// Vertical inset of the rail from the row's top/bottom.
    static let railInsetY: CGFloat = 8
    /// Status dot diameter.
    static let dot: CGFloat = 8
    /// Permission / question hero-card corner radius.
    static let heroRadius: CGFloat = 16
    /// Hero-card ring stroke width.
    static let heroRingWidth: CGFloat = 1.5
    /// Agents-grid cell diameter (circle = `gridCell / 2`).
    static let gridCell: CGFloat = 6
    /// Agents-grid inter-cell gap.
    static let gridGap: CGFloat = 3.5
    /// Agents-grid cell corner radius (`gridCell / 2` → bloomed circle).
    static let gridRadius: CGFloat = 3
}

/// Halo's ambient / stateful motion periods (SPEC-halo §1c · §K · AB-340).
///
/// These are the leaf periods for the animated edge-light and liveness glyphs —
/// NOT in `IslandMotionTokens`, which models only open/close/pop/unmount as in
/// every shipped theme. They live here exactly as Poured / Flight Deck keep their
/// leaf periods, pinned by `HaloThemeTests`. The edge-light engine (T22) and the
/// closed pill / rows (T23–T25) consume them; each maps to a §K motion.
enum HaloMotion {
    /// Working edge orbit — `from` 0→360° / 6s linear (monotonic, not a sine).
    static let orbit: TimeInterval = 6
    /// Permission edge pulse + outer bloom — 1.9s ease-in-out.
    static let permissionPulse: TimeInterval = 1.9
    /// Question edge pulse — 2.6s ease-in-out (gentler than permission).
    static let question: TimeInterval = 2.6
    /// Success bloom → dissolve to hairline — 3s ease-out, one shot.
    static let success: TimeInterval = 3
    /// Row entrance light sweep — a single ~0.7s pass (never looped).
    static let sweep: TimeInterval = 0.7
    /// Hero-card ring pulse — 2.2s ease-in-out.
    static let heroRing: TimeInterval = 2.2
    /// Running liveness-glyph wave — 1.05s.
    static let wave: TimeInterval = 1.05
    /// Waiting liveness-glyph breathe — 2.4s.
    static let breathe: TimeInterval = 2.4
    /// Agents-grid waiting-dot breathe — 2s.
    static let gridDot: TimeInterval = 2
}

/// "Never color alone" — the pure state → (glyph / shape / motion) resolver for
/// the Halo edge-light (SPEC-halo §4 · AB-340).
///
/// Halo conveys state through *moving light*, so every state must also carry a
/// non-color channel: a distinct glyph and a distinct edge-motion, so the state
/// stays legible for color-blind users and (critically) under Reduce Motion,
/// where the light freezes. This is the pure logic T23/T25 will consume when they
/// draw the pill / rows; `HaloThemeTests` asserts a non-color channel exists per
/// state. It mirrors `AnnualSessionRowFormat` — pure, testable, view-free.
enum HaloSessionRowFormat {
    /// The seven edge states the light resolves to. Distinct from the raw
    /// `SessionPhase` because a completed session forks by outcome (success /
    /// interrupted / failed) and an inactive session recedes to `idle`.
    enum EdgeState: CaseIterable {
        case running
        case permission
        case question
        case success
        case interrupted
        case failed
        case idle
    }

    /// How the edge-light behaves for a state — the **motion** channel of "never
    /// color alone". `bloom` (permission) is the loudest; `staticColor` (failure)
    /// deliberately does **not** animate, so failure is visibly distinct from the
    /// pulsing attention states even at a glance; `off` (idle) is the bare
    /// hairline. Under Reduce Motion every animated case freezes to its state
    /// color, so this channel degrades without losing information.
    enum EdgeMotion: CaseIterable {
        /// Cyan→violet segment orbiting the perimeter (working).
        case orbit
        /// Amber (question qgold) edge pulsing, no bloom.
        case pulse
        /// Amber→magenta edge pulsing **and** blooming outside the silhouette
        /// (permission — the loudest ambient state).
        case bloom
        /// Green bloom that dissolves back to hairline (success — one shot).
        case settle
        /// A static state-colored segment that never animates (failure).
        case staticColor
        /// The bare 8%-white idle hairline (idle / interrupted quiet).
        case off
    }

    /// Maps a row's phase / presence / outcome onto its edge state. An inactive
    /// process recedes to `idle` regardless of stored phase, so a dead session
    /// never keeps a loud edge.
    static func edgeState(
        phase: SessionPhase,
        presence: IslandSessionPresence,
        outcome: SessionOutcome
    ) -> EdgeState {
        if presence == .inactive { return .idle }
        switch phase {
        case .waitingForApproval:
            return .permission
        case .waitingForAnswer:
            return .question
        case .running:
            return .running
        case .completed:
            switch outcome {
            case .success: return .success
            case .interrupted: return .interrupted
            case .failed: return .failed
            }
        }
    }

    /// The non-color **glyph** channel: a distinct SF Symbol per state so state
    /// is never carried by hue alone. Success is a quiet check; interrupted and
    /// failed swap to a stop / cross so a non-success completion never reads the
    /// same as a clean finish; permission / question carry their alert marks.
    static func statusGlyphName(_ state: EdgeState) -> String {
        switch state {
        case .running: return "circle.fill"
        case .permission: return "exclamationmark.triangle.fill"
        case .question: return "questionmark.circle.fill"
        case .success: return "checkmark"
        case .interrupted: return "stop.fill"
        case .failed: return "xmark"
        case .idle: return "circle"
        }
    }

    /// The non-color **motion** channel: how the edge behaves for the state.
    /// Permission blooms (loudest), question only pulses, failure is static, idle
    /// is off — so permission and question are distinct by shape/motion as well as
    /// hue, and failure never masquerades as a live attention state.
    static func edgeMotion(_ state: EdgeState) -> EdgeMotion {
        switch state {
        case .running: return .orbit
        case .permission: return .bloom
        case .question: return .pulse
        case .success: return .settle
        case .interrupted: return .off
        case .failed: return .staticColor
        case .idle: return .off
        }
    }
}

// MARK: - Token axes (SPEC-halo §1 — pinned by HaloThemeTests)

extension IslandColorTokens {
    /// Halo's colour axis: a pure-black OLED void whose only chrome is the living
    /// prismatic edge-light. `surfaceInk` is **#000000** — darker than every
    /// shipped ink (`flightDeckInk #08090A` was the previous floor) — and the text
    /// ramp is white at opacity on that void. The status tints map each state to
    /// its *primary* edge hue.
    ///
    /// **Contrast correction (SPEC §1a / §0.4):** the mockup's tertiary text was
    /// white @ 0.42, which is only 3.9:1 on pure black (< 4.5:1). It is corrected
    /// to **0.50** (5.3:1) here and pinned so no one restores the failing value.
    static let halo = IslandColorTokens(
        surfaceInk: haloVoid,
        paper: .white,
        surfaceText: .white,
        statusRunning: haloCyan,
        statusCompleted: haloGreen,
        statusWaitingForApproval: haloAmber,
        statusWaitingForAnswer: haloQGold,
        statusWaitingAggregate: haloAmber,
        statusWarning: haloWarn,
        statusInterrupted: haloWarn,
        statusFailed: haloRed,
        statusIdle: Color.white.opacity(0.42),
        statusInactive: Color.white.opacity(0.28),
        secondaryTextOpacity: 0.63,
        tertiaryTextOpacity: 0.50,
        increasedContrastTextBoost: 0.24,
        hairlineOpacity: 0.08,
        hairlineOpacityIncreasedContrast: 0.24
    )

    /// The pure-black OLED void — the theme's defining value.
    private static let haloVoid = Color(red: 0, green: 0, blue: 0)
    /// Working orbit primary (`--cyan #33DCFF`).
    private static let haloCyan = Color(red: 0x33 / 255.0, green: 0xDC / 255.0, blue: 0xFF / 255.0)
    /// Success bloom (`--green #5FE39A`).
    private static let haloGreen = Color(red: 0x5F / 255.0, green: 0xE3 / 255.0, blue: 0x9A / 255.0)
    /// Permission — the hottest attention (`--amber #FFB14D`).
    private static let haloAmber = Color(red: 0xFF / 255.0, green: 0xB1 / 255.0, blue: 0x4D / 255.0)
    /// Question — softer (`--qgold #FFCF7A`).
    private static let haloQGold = Color(red: 0xFF / 255.0, green: 0xCF / 255.0, blue: 0x7A / 255.0)
    /// Bypass / interrupted amber (`--warn #E6AA42`, = `flightDeckCaution`).
    private static let haloWarn = Color(red: 0xE6 / 255.0, green: 0xAA / 255.0, blue: 0x42 / 255.0)
    /// Static dim red for a failure (`--red #E0596C`).
    private static let haloRed = Color(red: 0xE0 / 255.0, green: 0x59 / 255.0, blue: 0x6C / 255.0)
}

extension IslandMetricsTokens {
    /// Halo's chrome: modest 20pt opened radii (the morph target), the plain
    /// concave top corner (`filletRadius 0`, the non-vibrancy path), and a deep
    /// black drop shadow so the OLED cutout reads seated on the desk.
    ///
    /// **The grown insets (40/48 opened, 40/44 closed) are load-bearing.** Halo's
    /// attention bloom (`bloompulse` ~46pt) and the permission card outer glow
    /// (48pt) both bleed **outside** their silhouettes — the theme's whole point.
    /// `OverlayPanelController` sizes the overlay window from these shadow-inset
    /// tokens (via `IslandChromeLayout`'s per-axis `max(opened, closed)`), so they
    /// must be sized to the *worst-case* bloom, not the idle pill — otherwise the
    /// loudest light is clipped at the window edge. AB-320 made these real. Pinned
    /// with that dependency noted so no one regresses them to Poured/FD values.
    static let halo = IslandMetricsTokens(
        openedTopRadius: 20,
        openedBottomRadius: 20,
        surfaceShadow: IslandShadowToken(
            color: .black,
            opacity: 0.6,
            radius: 30,
            yOffset: 12
        ),
        openedShadowHorizontalInset: 40,
        openedShadowBottomInset: 48,
        closedShadowHorizontalInset: 40,
        closedShadowBottomInset: 44,
        closedHoverScale: 1.03,
        filletRadius: 0
    )
}

extension IslandMotionTokens {
    /// Halo's motion: a fluid "light travels" morph — smooth, no bounce, the notch
    /// *growing*. The open spring settles without overshoot (between Poured's
    /// .5/.84 and Annual's .44/.86); the close is a clean collapse back to the
    /// notch; the pop is a soft "condense" (light gathering, not a mechanical
    /// snap). The ambient edge-light periods live in `HaloMotion`, not here.
    static let halo = IslandMotionTokens(
        openAnimation: .spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0),
        closeAnimation: .smooth(duration: 0.32, extraBounce: 0),
        popAnimation: .spring(response: 0.34, dampingFraction: 0.66, blendDuration: 0),
        openedSurfaceUnmountDelay: 0.36
    )
}

extension IslandMaterialTokens {
    /// Halo is an opaque OLED void, not glass: `HaloTheme.usesVibrancy` is `false`,
    /// so `OpenedSurfaceBackground` takes the opaque `surfaceInk` path and never
    /// instantiates a vibrancy view. These are the fallback values if vibrancy
    /// were ever forced on — a fully opaque ink tint (`1.0`) and **no specular
    /// edge**: the animated 1.5pt perimeter edge-light *replaces* the specular
    /// concept entirely (an `IslandSpecularEdge` can't express an orbiting/masked
    /// ring), so the material token carries none. Reduce Transparency is therefore
    /// a no-op for this theme — the void is already opaque `#000`.
    static let halo = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 1.0,
        specularTopEdge: nil
    )
}

extension IslandThemeTokens {
    /// Halo (prismatic edge-light on a true-black void): a pure-black OLED void
    /// whose only chrome is a living 1.5pt prismatic edge-light. `usesVibrancy`
    /// off, `tintOpacity` 1.0, no specular — the animated edge is the light
    /// channel — grown shadow insets so the attention bloom is never clipped.
    static let halo = IslandThemeTokens(
        colors: .halo,
        metrics: .halo,
        motion: .halo,
        material: .halo
    )
}

// MARK: - Theme

/// "Halo" — the darkest and most motion-defined theme in the set: a pure-black
/// (#000000) OLED void whose **only** chrome is a 1.5pt living prismatic
/// edge-light traced around the morphing silhouette (SPEC-halo · AB-340).
///
/// **This is Part 1 (T21) — the theme shell.** It ships the full token identity
/// (the pure-black void, the edge-light accent + wash tables, the ambient motion
/// periods, the grown window insets, the mono/sans typography scale), the theme's
/// own bloomed-circle agents-grid geometry, and the "never color alone" edge-state
/// resolver (`HaloSessionRowFormat`) the later slices consume. The edge-light
/// engine (T22), the closed pill (T23), the rows / heroes (T24), and the opened
/// chrome (T25) restyle the slots; **until then the slot factories delegate to the
/// Classic implementations** so the overlay renders (Classic's flat views) rather
/// than blank. The quiet slots (empty / bootstrap / install) are likewise interim
/// Classic delegations, finished in Part 2.
///
/// **Not registered in `ThemeRegistry.all`.** T21–T25 build Halo unregistered
/// (tests instantiate `HaloTheme()` directly); T26 performs the one-line
/// registration once the theme is complete. So `ThemeRegistry.theme(id: "halo")`
/// falls back to the default in the interim — an existing-behavior assertion in
/// `HaloThemeTests` documents it.
struct HaloTheme: IslandTheme {

    /// Interim delegate for the slots Part 1 does not restyle yet. Replaced
    /// slot-by-slot by T22–T25 (rows / pill / header / heroes) and Part 2 (the
    /// quiet slots). Every `// PART 2 · T2x` comment below marks a delegation the
    /// later slice removes.
    private let interim = ClassicTheme()

    // MARK: Identity

    let id = "halo"

    func name(_ lang: LanguageManager) -> String {
        lang.t("theme.halo.name")
    }

    func descriptor(_ lang: LanguageManager) -> String {
        lang.t("theme.halo.descriptor")
    }

    // MARK: Styling

    var tokens: IslandThemeTokens { .halo }

    // MARK: Capability flags

    /// Rows are near-chromeless, but the actionable-row **rail carries a glow** and
    /// the **status dot a bloom** (blur) that bleed outside the row silhouette; a
    /// `.drawingGroup()` off-screen render would flatten/clip both to row bounds
    /// (the same reason Poured / Flight Deck are unsafe). The animated *panel* edge
    /// is on the surface shape, not the row, so it does not bear on this flag — the
    /// row's own luminous bleed settles it at `false`.
    let rowIsDrawingGroupSafe = false

    /// The void is opaque `#000`, so `OpenedSurfaceBackground` takes the opaque
    /// `surfaceInk` path and never builds a vibrancy view — which also makes Reduce
    /// Transparency a no-op for this theme (already opaque).
    let usesVibrancy = false

    // MARK: Geometry strategy

    /// Halo reuses Classic's balanced matrix (so the pill width math + morph frame
    /// are unchanged — the same move Annual / Flight Deck made) but overrides
    /// `cellGeometry` to `(6, 3.5, 3)` so each cell renders as a **bloomed light
    /// circle** (radius = cell / 2). Pinned by `HaloThemeTests`; Classic's
    /// `AgentsGridLayoutTests` are untouched.
    var agentsGridGeometry: IslandAgentsGridGeometry {
        IslandAgentsGridGeometry(
            balancedRows: { V6RightSlotView.balancedRows($0) },
            cellGeometry: { _ in (cell: HaloMetrics.gridCell, gap: HaloMetrics.gridGap, radius: HaloMetrics.gridRadius) }
        )
    }

    // MARK: Slot factories (interim — delegated to Classic until T22–T25)

    // PART 2 · T23: the closed pill (wings, ambient states A1–A6, edge-light,
    // agents-grid of bloomed circles) replaces this delegation.
    func closedPill(
        mode: UnifiedBars.Mode,
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat,
        physicalNotchWidth: CGFloat,
        minWidth: CGFloat,
        showsGlyph: Bool
    ) -> AnyView {
        interim.closedPill(
            mode: mode,
            label: label,
            rightSlot: rightSlot,
            layout: layout,
            height: height,
            physicalNotchWidth: physicalNotchWidth,
            minWidth: minWidth,
            showsGlyph: showsGlyph
        )
    }

    // PART 2 · T25: the notch-split header with light-filament usage arcs +
    // resets-in inline replaces this delegation.
    func openedHeader(
        providers: [UsageProviderPresentation],
        usesNotchAwareLayout: Bool,
        targetScreen: NSScreen?,
        isSoundMuted: Bool,
        lang: LanguageManager,
        onToggleMute: @escaping () -> Void,
        onShowSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> AnyView {
        interim.openedHeader(
            providers: providers,
            usesNotchAwareLayout: usesNotchAwareLayout,
            targetScreen: targetScreen,
            isSoundMuted: isSoundMuted,
            lang: lang,
            onToggleMute: onToggleMute,
            onShowSettings: onShowSettings,
            onQuit: onQuit
        )
    }

    // PART 2 · T24: the void row (dot + monogram, narrated activity, edge-lit
    // rail, permission/question heroes, completion body) replaces this delegation.
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
    ) -> AnyView {
        interim.sessionRow(
            session: session,
            stateIndicator: stateIndicator,
            completedStaleThreshold: completedStaleThreshold,
            isActionable: isActionable,
            useDrawingGroup: useDrawingGroup,
            isInteractive: isInteractive,
            isHighlighted: isHighlighted,
            presentation: presentation,
            sideInset: sideInset,
            lang: lang,
            actions: actions,
            keyboardCoordinator: keyboardCoordinator,
            pulseClock: pulseClock
        )
    }

    // PART 2 · T25: the hairline-bounded summary strip + "Needs you"-first
    // sections + quiet footer replace this delegation.
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
    ) -> AnyView {
        interim.sessionList(
            sessions: sessions,
            sections: sections,
            group: group,
            stateIndicator: stateIndicator,
            completedStaleThreshold: completedStaleThreshold,
            sideInset: sideInset,
            isInteractive: isInteractive,
            actionableSessionID: actionableSessionID,
            lang: lang,
            keyboardCoordinator: keyboardCoordinator,
            pulseClock: pulseClock,
            makeActions: makeActions
        )
    }

    // The notification card is the **shared** `IslandNotificationCard`: Halo
    // delegates to it (exactly like Annual / Poured), and its one row routes
    // through `sessionRow` above, so once T24 restyles the row the card inherits
    // the void + edge-ring hero with no parallel card. The delegation itself is
    // permanent — only the row body it draws changes.
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
    ) -> AnyView {
        interim.notificationCard(
            session: session,
            isInteractive: isInteractive,
            stateIndicator: stateIndicator,
            completedStaleThreshold: completedStaleThreshold,
            sideInset: sideInset,
            totalSessionCount: totalSessionCount,
            lang: lang,
            keyboardCoordinator: keyboardCoordinator,
            pulseClock: pulseClock,
            makeActions: makeActions,
            onShowAll: onShowAll,
            onPointerInside: onPointerInside,
            onPointerExited: onPointerExited,
            onMeasuredHeight: onMeasuredHeight
        )
    }

    // MARK: Quiet slots (MINIMAL stubs — finished in Part 2)

    // PART 2: `HaloEmptyState` — 34pt static monitor glyph (t3), "All quiet"
    // (14/600), subtitle (12/400), and a `● Monitoring · N workspaces` pill (idle
    // dot + hairline ring) where N is `workspaceCount` (the AB-326 seam: distinct
    // workspace names across current + recent sessions; render `Monitoring` alone
    // when the count is unavailable, never a fake number). Delegated to Classic in
    // the interim so the panel is never blank; `workspaceCount` /
    // `installedAgentNames` are ignored until Part 2 consumes them.
    func emptyState(
        lang: LanguageManager,
        hasRecentSessions: Bool,
        workspaceCount: Int,
        installedAgentNames: [String]
    ) -> AnyView {
        interim.emptyState(
            lang: lang,
            hasRecentSessions: hasRecentSessions,
            workspaceCount: workspaceCount,
            installedAgentNames: installedAgentNames
        )
    }

    // PART 2: `HaloBootstrapPlaceholder` — the void shell shown while probing
    // terminals on cold launch (trivially flash-safe since #000 is opaque).
    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        interim.bootstrapPlaceholder(lang: lang)
    }

    // PART 2: `HaloInstallHooksHint` — a quiet hairline line + `SETUP` tap CTA,
    // with **NO edge-light / no glow** (a hint is not an attention state —
    // color = state discipline, brief §7).
    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        interim.installHint(lang: lang, onTap: onTap)
    }
}
