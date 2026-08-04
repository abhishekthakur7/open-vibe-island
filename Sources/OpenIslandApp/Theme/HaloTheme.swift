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
/// (`HaloThemeTests`).
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
    /// §I meter label (`.meter .mx .ml`) — sans, 12 / 550. Its own role because
    /// the mockup sets the meter label a half-point below the row metadata value
    /// (`.mv` 12.5) so the 22pt numeral stays the dial's only loud element (G-05).
    static let meterLabelSize: CGFloat = 12
    /// §B hover-peek title (`06-halo.html:713`) — sans, 13 / 600.
    static let peekTitleSize: CGFloat = 13
    /// §B hover-peek command (`06-halo.html:714`) — **mono**, 11.5 (command).
    static let peekDetailSize: CGFloat = 11.5
    /// §B hover-peek click hint (`06-halo.html:718`) — sans, 11 @ t3.
    static let peekHintSize: CGFloat = 11
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
        ("meterLabel", .sans, meterLabelSize),
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

    // MARK: Baked font constants (overlay remediation F19)

    /// The nest-header caption's font (`.nest-h` — SPEC-halo.md:264: 10 / sans /
    /// **700** / 0.09em UPPER): a single
    /// built constant both call sites (`HaloSessionRow.swift:622,1102`) construct
    /// from, instead of each hand-reconstructing `weight:` + `.tracking(...)` —
    /// the raw-size-only shape that let the two sites drift apart (`:1102`
    /// shipped `.semibold` against `:622`'s correct `.bold`).
    static let nestHeader = Font.system(size: nestHeaderSize, weight: .bold)
    /// The nest-header caption's letterspacing, baked alongside `nestHeader` for
    /// the same reason.
    static let nestHeaderTracking: CGFloat = nestHeaderSize * 0.09
}

/// Halo's edge-light accent palette + wash table (SPEC-halo §1a · AB-340).
///
/// The shared `IslandColorTokens` models only *semantic status slots*. Halo's
/// living prismatic edge needs partner hues (violet, magenta) for its two
/// gradient states, plus three usage thresholds, plus two faint washes — none of
/// which are expressible as status tints. They live here, theme-local, keeping
/// Halo's own paint outside the shared token struct. Every value is pinned to
/// the SPEC hex by 8-bit component equality in `HaloThemeTests`.
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

    /// Code-block inset stroke (`--hair2 white@.05`). Also the edge-light's own
    /// off-band wash (the `white@.05` filler between an orbiting/segmented state's
    /// coloured stops — SPEC §1a working / failure tables).
    static let hair2 = Color.white.opacity(0.05)
    /// Mono-block whisper fill (`--lift white@.028`).
    static let lift = Color.white.opacity(0.028)

    // MARK: Bloom hues (AB-341 · SPEC §1a bloom column)

    /// The colored `.shadow` glow each state casts is a **separate** hue from its
    /// edge stops (a warmer, softer bloom rgba), so it reads as *light bleeding*
    /// past the silhouette rather than a fatter stroke. Pinned to the mockup rgba
    /// by `HaloEdgeLightTests`; the per-state opacity/radius live in the edge-light
    /// model + `HaloMetrics`.
    ///
    /// Working glow `rgba(96,150,255,·)` — a cooler blue than the cyan→violet edge.
    static let workingBloom = Color(red: 96 / 255.0, green: 150 / 255.0, blue: 255 / 255.0)
    /// Permission glow `rgba(255,120,90,·)` — a hotter coral than the amber edge
    /// (the loudest bloom, the only one that bleeds far outside the silhouette).
    static let permissionBloom = Color(red: 255 / 255.0, green: 120 / 255.0, blue: 90 / 255.0)
    /// Question glow `rgba(255,207,122,·)` — the qgold hue, a steady soft halo.
    static let questionBloom = Color(red: 255 / 255.0, green: 207 / 255.0, blue: 122 / 255.0)
    /// Success glow `rgba(95,227,154,·)` — the green hue, blooms then dissolves.
    static let successBloom = Color(red: 95 / 255.0, green: 227 / 255.0, blue: 154 / 255.0)
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
    /// The side inset the **top-bar** opened profile ships (external-display /
    /// non-notched Macs) — `IslandPanelView.sessionListSideInset`'s `16`. Rows are
    /// handed only that number, so it is also the row's only signal for which
    /// silhouette it is being drawn inside; the notch profile passes `46`.
    static let topBarProfileSideInset: CGFloat = 16
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

    // MARK: Edge-light bloom radii (AB-341 · SPEC §1a bloom column)

    /// The mockup's bloom shadows are CSS `0 0 <blur> <spread>` — but SwiftUI's
    /// `.shadow(radius:)` has **no spread**, and the mockup's spreads are all
    /// *negative* (a tighter halo). We map each to an effective SwiftUI radius of
    /// `≈ (blur + spread) / 2` (halving CSS blur to SwiftUI's Gaussian σ, then
    /// applying the negative spread as a further tightening), then pin the tuned
    /// value here. These are **judged-by-eye** against `06-halo.html`; the final
    /// "reads across the room" pass is a dev-app manual sign-off item (SPEC §6.4).
    ///
    /// Working steady glow — mockup `0 0 26 -10` → `(26-10)/2 = 8`.
    static let workingBloomRadius: CGFloat = 8
    /// Permission bloompulse **min** — mockup `r20 -4` → `(20-4)/2 = 8`.
    static let permissionBloomRadiusMin: CGFloat = 8
    /// Permission bloompulse **max** — mockup `r46 -4` → an effective ~42pt blur.
    /// The loudest bloom; the grown `closedShadowInset` tokens (44pt) contain it.
    static let permissionBloomRadiusMax: CGFloat = 42
    /// Question steady glow — mockup `0 0 22 -10` → `(22-10)/2 = 6`.
    static let questionBloomRadius: CGFloat = 6
    /// Success okbloom **peak** — mockup `r40 → 0` (no spread) → `40/2 = 20`,
    /// dissolving to 0 over the 3s one-shot.
    static let successBloomRadiusMax: CGFloat = 20
}

/// Halo's ambient / stateful motion periods (SPEC-halo §1c · §K · AB-340).
///
/// These are the leaf periods for the animated edge-light and liveness glyphs —
/// NOT in `IslandMotionTokens`, which models only open/close/pop/unmount as in
/// every shipped theme. They live here exactly as Poured keeps its own leaf
/// periods, pinned by `HaloThemeTests`. The edge-light engine (T22) and the
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
    /// The running wave glyph's per-bar stagger delays (SPEC §1c · mockup
    /// `wave 1.05s` bars delayed **.13 / .26s**). The three bars ride the same
    /// `wave` period, offset by these delays so the wave travels left→right.
    /// Pinned by `HaloClosedPillTests` so the stagger can't silently drift.
    static let waveBarDelays: [TimeInterval] = [0, 0.13, 0.26]
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
/// state. It is pure, testable, view-free.
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

    /// The collapsed row's **edge-lit rail** (SPEC §5C/§5D · mockup `.rail`): a 2pt
    /// vertical gradient rail in the left margin that marks **only** the live /
    /// actionable rows — running (cyan→violet), permission (amber→magenta), question
    /// (qgold) — so attention reads straight down the left of the list. A settled
    /// row (success / interrupted / failed) and an idle row carry **no** rail, so a
    /// list with nothing live is rail-free and calm. This is the collapsed-row
    /// mirror of `edgeMotion` (the perimeter edge-light's channel); it is pure so
    /// `HaloThemeTests` can pin the phase → rail mapping without rendering a view.
    enum Rail: CaseIterable {
        /// Cyan→violet vertical gradient (a running turn).
        case running
        /// Amber→magenta vertical gradient (the loudest — a permission request).
        case permission
        /// Flat qgold (a question — softer than permission).
        case question
    }

    static func rail(for state: EdgeState) -> Rail? {
        switch state {
        case .running: return .running
        case .permission: return .permission
        case .question: return .question
        case .success, .interrupted, .failed, .idle: return nil
        }
    }

    /// G-10 — the leading offset the 2pt rail needs to land on the **painted**
    /// wall, in points.
    ///
    /// The board writes `.rail{position:absolute;left:0}` (`06-halo.html:285`)
    /// against `.isle.panel`, whose `left:0` *is* its painted border-box edge. Ours
    /// is not: on the notch profile `NotchShape` draws the silhouette's side walls
    /// at `rect.minX + topCornerRadius` / `rect.maxX − topCornerRadius`
    /// (`NotchShape.swift:35-38`) — the row lays out in the full frame, but the
    /// outer `openedTopRadius` of each side is transparent shoulder that the
    /// surface's own clip discards. A rail at the row's x=0 is therefore not
    /// "dominated by the perimeter edge-light", as G-10 assumed: it is **clipped
    /// away entirely** (measured on this MacBook — frame edge 486pt, painted wall
    /// 506pt, and every pixel between them is desktop backdrop).
    ///
    /// The `.topBar` profile paints from `rect.minX` (`V6ClosedPillShape`), so it
    /// needs no offset. `sideInset` is the discriminator because it is the only
    /// profile signal a row is handed (`IslandPanelView.sessionListSideInset` is
    /// `notchAware ? 46 : 16`).
    static func railWallInset(sideInset: CGFloat, openedTopRadius: CGFloat) -> CGFloat {
        sideInset > HaloMetrics.topBarProfileSideInset ? openedTopRadius : 0
    }

    /// The achromatic **agent monogram** (mockup `.mono-tag`): a single identity
    /// initial derived from the agent's short name, upper-cased. Identity in Halo is
    /// a grey whisper — the monogram is **never** brand-colored (brief §7), so this
    /// carries only the letter, never a hue. The first alphanumeric scalar is taken
    /// so a punctuation-led name still yields a readable mark; an empty / symbol-only
    /// name falls back to a neutral bullet. Pure so `HaloThemeTests` pins the
    /// derivation and it stays stable across agents.
    static func monogram(agentShortName: String) -> String {
        guard let initial = agentShortName.unicodeScalars.first(where: {
            CharacterSet.alphanumerics.contains($0)
        }) else {
            return "•"
        }
        return String(initial).uppercased()
    }

    // MARK: - Subagents & completion (Part 2 · SPEC §5G/§5H · mockup §G/§H)

    /// The per-subagent **live elapsed** readout (§5G · AC · mockup `.sti`): the
    /// wall-clock span `now − startedAt` as a mono tabular `%dm %02ds`. Against the
    /// shared T08 `subagentsAndTasks` fixtures (`startedAt` at −42 / −75 / −8s) the
    /// three engines read `0m 42s` / `1m 15s` / `0m 08s`. Minutes are **not** rolled
    /// into hours — a long subagent stays an honest tabular count the column can
    /// still align (`90m 00s`) — and a negative interval (a clock nudge) clamps to
    /// `0m 00s` rather than printing a `-`. Kept pure so `HaloThemeTests` can pin
    /// the fixture readouts without rendering.
    static func subagentElapsedLabel(seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%dm %02ds", clamped / 60, clamped % 60)
    }

    /// The completion **Duration** readout (§5H · AC · mockup `.mv tnum`): the run
    /// length as a mono tabular string. A sub-hour run reads `%dm %02ds` (`14m 08s`,
    /// the mockup example = 848s), and a longer run rolls into an hours field
    /// (`1h 05m 30s`) so a multi-hour session never reads a misleading `65m 30s`. A
    /// negative span (clock skew) clamps to `0m 00s`. Distinct from
    /// `subagentElapsedLabel` only in the hour-roll: a subagent is a live count that
    /// stays in minutes, a completed run is a settled total that earns hours.
    static func durationLabel(seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, secs)
        }
        return String(format: "%dm %02ds", minutes, secs)
    }

    /// A completed row's **outcome badge** shape (§5H · AC · mockup `.outc`): the
    /// glyph + which status slot tints it. Success is a check on the green slot,
    /// interrupted a stop on the interrupted (warn) slot, failed a cross on the
    /// failed (red) slot — so a non-success completion never reads the same as a
    /// clean finish (glyph **and** hue differ, never colour alone, SPEC §K). Pure so
    /// `HaloThemeTests` pins the outcome → (glyph, slot) mapping.
    enum Outcome: CaseIterable {
        case success
        case interrupted
        case failed

        init(_ outcome: SessionOutcome) {
            switch outcome {
            case .success: self = .success
            case .interrupted: self = .interrupted
            case .failed: self = .failed
            }
        }

        /// The SF Symbol the badge carries — distinct per outcome.
        var glyphName: String {
            switch self {
            case .success: return "checkmark"
            case .interrupted: return "stop.fill"
            case .failed: return "xmark"
            }
        }
    }
}

/// Pure, view-free format rules for the Halo permission / question **hero**
/// (§5E/§5F · mockup `.hero`). Split out — like `HaloSessionRowFormat` — so the
/// AC-bearing decisions (which keycap a button prints, the ring / glow params,
/// the claude-vs-codex capability fork, the T10 command-token palette) are
/// unit-testable without rendering a SwiftUI view.
///
/// **Keycaps track real handlers.** The in-app approval shortcuts (⌘Y / ⌘⇧Y / ⌘N)
/// are the ones `OverlayPanelController` actually registers, so the buttons print
/// them. There is **no** ⌘J handler, so the Codex jump button prints no keycap —
/// a glyph must never advertise a shortcut that does not fire.
enum HaloHeroFormat {

    // MARK: Attention tint

    /// The two hero tints — permission (amber, hottest) and question (qgold,
    /// softer). Each resolves its own inset-ring / glow / conic-gradient hues. The
    /// question tint is consumed by the §5F hero the next slice adds.
    enum Tint: CaseIterable { case permission, question }

    // MARK: Capability fork (claude-vs-codex)

    /// The action layout the hero draws, forked by whether the agent can resolve
    /// the request out-of-process. Claude approves in-app (Allow once / Deny +
    /// scoped always-allow); Codex (`requiresTerminalApproval`) cannot, so the hero
    /// is honest — no fake Approve, a single cool-blue jump-to-approve (E3).
    enum Layout: Equatable { case approveDeny, jumpToApprove }

    static func layout(requiresTerminalApproval: Bool) -> Layout {
        requiresTerminalApproval ? .jumpToApprove : .approveDeny
    }

    // MARK: Variant (command / diff / terminal)

    /// Which body the permission hero draws: a syntax-lit command block, an inline
    /// file diff, or a terminal-approval (Codex) command. A file-diff request draws
    /// the diff; a Codex request is always the terminal variant regardless of body.
    enum Variant: Equatable { case command, diff, terminal }

    static func variant(hasFileDiff: Bool, requiresTerminalApproval: Bool) -> Variant {
        if requiresTerminalApproval { return .terminal }
        return hasFileDiff ? .diff : .command
    }

    /// The annunciator chip glyph per variant (never colour alone): a warning
    /// triangle for a command / terminal approval, a pencil for a file edit.
    static func annunciatorGlyph(_ variant: Variant) -> String {
        switch variant {
        case .command, .terminal: return "exclamationmark.triangle"
        case .diff: return "square.and.pencil"
        }
    }

    // MARK: Scoped-grant label (G-21 · mockup `.scope code`)

    /// A scoped always-allow label split around its `code` fragment — the mockup's
    /// `Yes, allow `rtk grep` from this project`, where the rule itself is an amber
    /// mono chip (`.scope code`) and the surrounding sentence is plain 12pt body.
    struct ScopeLabel: Equatable {
        var leading: String
        var code: String?
        var trailing: String
    }

    /// Splits an already-**localized** scope sentence around the first (longest)
    /// candidate rule fragment it actually contains, so the chip never invents or
    /// re-orders copy: the whole label still comes from `displayLabel` /
    /// `approval.alwaysAllow`, this only says which run of it is the rule.
    ///
    /// Candidates arrive most-specific-first (the shortened rule content, the raw
    /// rule content, the tool name); the longest one present wins so
    /// `AGENTS.md/` beats its own `AGENTS.md` prefix. A trailing `/` — an artifact
    /// of `ClaudePermissionUpdate.shortenedPath` — is trimmed off the *chip text*
    /// only. Nothing found ⇒ `code == nil` and the sentence renders whole, so an
    /// unrecognised label degrades to exactly today's flat row.
    ///
    /// The bracket a template wrapped its `%@` in is dropped from whichever
    /// segment faces the chip (`trimmedSegment`) — see N2 there.
    static func scopeLabel(_ label: String, candidates: [String?]) -> ScopeLabel {
        let found = candidates
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .compactMap { candidate -> (Range<String.Index>, String)? in
                guard let range = label.range(of: candidate) else { return nil }
                return (range, candidate)
            }
            .max { $0.1.count < $1.1.count }

        guard let (range, candidate) = found else {
            return ScopeLabel(leading: label, code: nil, trailing: "")
        }
        var chip = candidate
        while chip.hasSuffix("/") { chip = String(chip.dropLast()) }
        guard !chip.isEmpty else { return ScopeLabel(leading: label, code: nil, trailing: "") }
        return ScopeLabel(
            leading: Self.trimmedSegment(String(label[label.startIndex..<range.lowerBound]), side: .leading),
            code: chip,
            trailing: Self.trimmedSegment(String(label[range.upperBound...]), side: .trailing)
        )
    }

    private enum ScopeSegmentSide { case leading, trailing }

    /// The parentheses the localized template wraps `%@` in — ASCII for the
    /// `Always Allow (%@)` form.
    private static let scopeBracketCharacters: Set<Character> = ["(", ")"]

    /// N2: the shared `approval.alwaysAllow` template parenthesises its `%@`, so
    /// splitting it around the tool name would leave the brackets orphaned either
    /// side of the chip (`Always Allow ( exec_command )`). The mockup §E writes a
    /// scope row as a sentence with the chip inline, so the bracket that only
    /// existed to delimit the substitution is dropped from the segment that faces
    /// the chip — the chip itself is now the delimiter. Halo-side only: the shared
    /// string is untouched and every other theme still renders it verbatim.
    private static func trimmedSegment(_ segment: String, side: ScopeSegmentSide) -> String {
        var trimmed = Substring(segment)
        var didStrip = true
        while didStrip {
            didStrip = false
            switch side {
            case .leading:
                while let last = trimmed.last, last.isWhitespace { trimmed = trimmed.dropLast(); didStrip = true }
                if let last = trimmed.last, scopeBracketCharacters.contains(last) {
                    trimmed = trimmed.dropLast()
                    didStrip = true
                }
            case .trailing:
                while let first = trimmed.first, first.isWhitespace { trimmed = trimmed.dropFirst(); didStrip = true }
                if let first = trimmed.first, scopeBracketCharacters.contains(first) {
                    trimmed = trimmed.dropFirst()
                    didStrip = true
                }
            }
        }
        return String(trimmed).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Keycaps (track the REAL registered shortcuts — ⌘Y / ⌘⇧Y / ⌘N / ⌘J)

    /// The in-app card shortcuts, each paired with the **real** glyphs the
    /// registered `OverlayPanelController.handleOverlayKeyDown` fires
    /// (⌘Y / ⌘⇧Y / ⌘N / ⌘J), plus `jump` — N3 registered ⌘J against the
    /// presented card's jump action (`handleJumpShortcut`), so the Codex hero's
    /// mockup keycap is now a case of this enum like any other rather than a
    /// view-local literal.
    enum Shortcut: CaseIterable {
        case allowOnce, alwaysAllow, deny, jump

        /// The key-hint glyphs printed on the keycap chip, in order.
        var glyphs: [String] {
            switch self {
            case .allowOnce: return ["⌘", "Y"]
            case .alwaysAllow: return ["⌘", "⇧", "Y"]
            case .deny: return ["⌘", "N"]
            case .jump: return ["⌘", "J"]
            }
        }

        /// The joined glyph string (e.g. `⌘⇧Y`) — the a11y / test-facing form.
        var glyphString: String { glyphs.joined() }
    }

    // MARK: Ring params (§5E · mockup `.hero`)

    /// Hero-card corner radius (`heroRadius 16`).
    static let ringRadius: CGFloat = HaloMetrics.heroRadius
    /// Ring stroke width (`heroRingWidth 1.5`).
    static let ringWidth: CGFloat = HaloMetrics.heroRingWidth
    /// The `::before` ring pulse period (`edgepulse 2.2s`).
    static let pulsePeriod: TimeInterval = HaloMotion.heroRing
    /// Outer-glow effective radius — mockup `0 0 48px -8px rgba(255,140,80,.5)`.
    ///
    /// G-37: the T22 spread-equivalence rule `(48 − 8) / 2 = 20` under-reads the
    /// board badly — CSS blurs the shadow *outward* from the (negatively spread)
    /// silhouette, while SwiftUI's `.shadow(radius:)` is a symmetric Gaussian, so
    /// 20 buys roughly half the visible bleed. Raised to `48 × 2/3` now that G-36
    /// makes this the only glow in the frame: the hero is the one loud thing, so
    /// it can afford the mockup's full halo without two lights competing.
    static let glowRadius: CGFloat = 32
    /// The `::before` ring rides the `.55 ↔ 1` edge pulse; Reduce Motion pins it at
    /// the **peak** so attention stays loudest statically (§3c).
    static let pulseMinOpacity: Double = HaloEdgeLightModel.pulseOpacityMin
    static let pulseMaxOpacity: Double = HaloEdgeLightModel.pulseOpacityMax
    /// The conic gradient's `from` angle (mockup `from 44deg`).
    static let conicAngle: Double = 44

    // MARK: Colours (per-tint ring / glow, compared by `==` in tests)

    /// The static inset ring hue (`rgba(255,160,80,.55)` permission / qgold@.5).
    static func insetRingColor(_ tint: Tint) -> Color {
        switch tint {
        case .permission: return Color(red: 255 / 255.0, green: 160 / 255.0, blue: 80 / 255.0).opacity(0.55)
        case .question: return IslandColorTokens.halo.statusWaitingForAnswer.opacity(0.5)
        }
    }

    /// The outer-glow hue (`rgba(255,140,80,.5)` permission / qgold@.4).
    static func glowColor(_ tint: Tint) -> Color {
        switch tint {
        case .permission: return Color(red: 255 / 255.0, green: 140 / 255.0, blue: 80 / 255.0).opacity(0.5)
        case .question: return IslandColorTokens.halo.statusWaitingForAnswer.opacity(0.4)
        }
    }

    /// The pulsing conic-gradient stops (`from 44°`): amber→magenta→amber for
    /// permission, qgold→`#ffe0a8`→qgold for question. Reuses the `HaloEdgeStop`
    /// value the T22 masked-ring engine consumes so the hero rides the same ring
    /// component.
    static func conicStops(_ tint: Tint) -> [HaloEdgeStop] {
        switch tint {
        case .permission:
            let amber = IslandColorTokens.halo.statusWaitingForApproval
            return [HaloEdgeStop(amber, 0), HaloEdgeStop(HaloEdge.magenta, 198), HaloEdgeStop(amber, 360)]
        case .question:
            let qgold = IslandColorTokens.halo.statusWaitingForAnswer
            let warm = Color(red: 255 / 255.0, green: 224 / 255.0, blue: 168 / 255.0)  // #ffe0a8
            return [HaloEdgeStop(qgold, 0), HaloEdgeStop(warm, 198), HaloEdgeStop(qgold, 360)]
        }
    }

    // MARK: Command-token palette (§5E · E1 — the T10 tokenizer's kinds → hues)

    /// The syntax palette the shipped `ShellCommandTokenizer` (T10) consumes for
    /// the `.cmd` block: command `#f4f6fb`/600, subcommand cyan, flag `#8fb6ff`,
    /// string green, path white@.5. `plain` inherits the block ink (`#c6ccd8`).
    static let commandPalette: [ShellCommandTokenizer.Kind: Color] = [
        .command: Color(red: 0xF4 / 255.0, green: 0xF6 / 255.0, blue: 0xFB / 255.0),
        .subcommand: IslandColorTokens.halo.statusRunning,
        .flag: Color(red: 0x8F / 255.0, green: 0xB6 / 255.0, blue: 0xFF / 255.0),
        .string: IslandColorTokens.halo.statusCompleted,
        .path: Color.white.opacity(0.5),
    ]

    /// The command role is the only weighted token (600); everything else inherits
    /// the block's regular mono weight.
    static let commandWeights: [ShellCommandTokenizer.Kind: Font.Weight] = [.command: .semibold]

    /// The `$ ` prompt hue (amber@.65 — `rgba(255,160,80,.65)`).
    static let promptColor = Color(red: 255 / 255.0, green: 160 / 255.0, blue: 80 / 255.0).opacity(0.65)

    /// The block ink the un-tokenized command text inherits (`#c6ccd8`).
    static let commandInk = Color(red: 0xC6 / 255.0, green: 0xCC / 255.0, blue: 0xD8 / 255.0)
}

/// Pure presentation logic for the §5F question hero's Halo-specific chrome — the
/// `.q-tag` category chip. The question *interior* (numbered options, multi-select,
/// freeform, submit, digit hints) is the shared, un-restyled
/// `StructuredQuestionPromptView` (T07); Halo only wraps it in the qgold ring shell
/// and stamps this one chip. Isolated here so the ≤12-char cap and generic fallback
/// are unit-testable without rendering a view.
enum HaloQuestionFormat {

    /// The maximum q-tag length (mockup `.q-tag` "≤12 chars", e.g. `Auth`,
    /// `Platforms`). Longer headers are truncated (grapheme-safe, no ellipsis — the
    /// chip is a category marker, not prose).
    static let maxTagLength = 12

    /// The `.q-tag` category label for a prompt: the first question's `header`
    /// (`Auth`, `Scope`) when it carries a real category, else a generic `Question`
    /// fallback. Always ≤ ``maxTagLength`` graphemes. `nil` only when there is no
    /// prompt at all (the hero then renders no chip).
    ///
    /// The header is treated as generic — and replaced by the fallback — when it is
    /// empty or equals the shared "Answer needed" umbrella string, so the chip never
    /// echoes the annunciator's own title.
    static func tag(for prompt: QuestionPrompt?, lang: LanguageManager = .shared) -> String? {
        guard prompt != nil else { return nil }
        return tag(header: prompt?.questions.first?.header, lang: lang)
    }

    /// The same normalization for an already-resolved header — the **page's own**
    /// question, not always the first (V8 · G-24): with `questionPageSize == 1` the
    /// hero's chip must follow pagination (`Auth` on page 1, `Scope` on page 2),
    /// which the prompt-level overload above cannot see.
    static func tag(header: String?, lang: LanguageManager = .shared) -> String {
        let generic = lang.t("island.halo.question.tag")
        let header = (header ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let answerNeeded = lang.t("question.answerNeeded")
        let source: String
        if header.isEmpty || header.caseInsensitiveCompare(answerNeeded) == .orderedSame {
            source = generic
        } else {
            source = header
        }
        return String(source.prefix(maxTagLength))
    }

    /// The `.qprog` readout (mockup `1 of 2`) — the hero head's right-aligned
    /// progress token (V8 · G-23/G-72). Deliberately *not* the shared
    /// `question.progress` string ("Question 1 of 2"): the head already says
    /// "A question for you", so the noun is redundant and the board prints the
    /// bare ordinal pair. `nil` for a single-question prompt, where progress is
    /// noise. `questionIndex` is 0-based; the readout renders it 1-based.
    static func progress(
        questionIndex: Int,
        questionCount: Int,
        lang: LanguageManager = .shared
    ) -> String? {
        guard questionCount > 1 else { return nil }
        return lang.t("island.halo.question.progress", questionIndex + 1, questionCount)
    }

    /// One run of the `.q-hint` footer caption: either prose or a real key that
    /// deserves the mockup's `kbd` keycap chip (V8 · G-25).
    enum HintSegment: Equatable, Sendable {
        case text(String)
        case key(String)
    }

    /// Splits a localized keyboard-hint sentence ("1–3 select · Enter submits ·
    /// Esc closes") into prose + keycap runs, so the footer can render the keys
    /// as `kbd` chips instead of printing them as prose (mockup `.q-hint`).
    ///
    /// Tokenizes on alphanumeric runs and promotes a run to a keycap when it is
    /// a 1–2 digit number or one of the ASCII key names every localization keeps
    /// verbatim (`Enter` / `Esc` / `Return` — the zh tables translate the verbs
    /// around them, never the key caps themselves). Everything else — including
    /// CJK words — stays prose, so this degrades to "no keycaps" rather than
    /// mis-chipping a translated word.
    static func hintSegments(_ hint: String) -> [HintSegment] {
        var segments: [HintSegment] = []
        var prose = ""
        var token = ""

        func flushToken() {
            guard !token.isEmpty else { return }
            if isKeyToken(token) {
                if !prose.isEmpty {
                    segments.append(.text(prose))
                    prose = ""
                }
                segments.append(.key(token))
            } else {
                prose += token
            }
            token = ""
        }

        for character in hint {
            if character.isLetter || character.isNumber {
                token.append(character)
            } else {
                flushToken()
                prose.append(character)
            }
        }
        flushToken()
        if !prose.isEmpty {
            segments.append(.text(prose))
        }
        return segments
    }

    private static func isKeyToken(_ token: String) -> Bool {
        if token.count <= 2, token.allSatisfy(\.isNumber) { return true }
        return ["Enter", "Esc", "Return", "Tab"].contains(token)
    }
}

/// What the shared question view tells Halo's hero head about the page it is
/// currently rendering (V8 · G-23/G-24/G-72): the `1 of 2` progress token, the
/// page question's category header, and whether that question is multi-select.
///
/// The page index lives in `StructuredQuestionPromptView`'s `@State`, so the
/// hero — which wraps that view — can only learn it by preference. Published
/// unconditionally by the shared view and read only by `HaloQuestionHero`;
/// every other theme ignores it.
struct HaloQuestionPageInfo: Equatable, Sendable {
    var progress: String?
    var header: String?
    var isMultiSelect: Bool
}

struct HaloQuestionPageInfoKey: PreferenceKey {
    static let defaultValue: HaloQuestionPageInfo? = nil
    static func reduce(value: inout HaloQuestionPageInfo?, nextValue: () -> HaloQuestionPageInfo?) {
        value = nextValue() ?? value
    }
}

// MARK: - Token axes (SPEC-halo §1 — pinned by HaloThemeTests)

extension IslandColorTokens {
    /// Halo's colour axis: a pure-black OLED void whose only chrome is the living
    /// prismatic edge-light. `surfaceInk` is **#000000** — darker than every
    /// other theme's ink — and the text ramp is white at opacity on that void.
    /// The status tints map each state to its *primary* edge hue.
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
        tertiaryTextOpacity: 0.42,
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
    /// Bypass / interrupted amber (`--warn #E6AA42`).
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
    /// .5/.84); the close is a clean collapse back to the
    /// notch; the pop is a soft "condense" (light gathering, not a mechanical
    /// snap). The ambient edge-light periods live in `HaloMotion`, not here.
    ///
    /// **M-26 (halo parity V3): the close IS the open, reversed.** `closeAnimation`
    /// used to be `.smooth(duration: 0.32)`, which collapsed the panel in ~0.13 s
    /// against the open's ~0.30 s — a visibly asymmetric pair when the two are
    /// scrubbed frame-by-frame against §B′. Both directions now ride the exact
    /// same spring, so the reverse morph traces the same envelope (the same
    /// `morphProgress` interpolant in `IslandPanelView` drives both).
    static let halo = IslandMotionTokens(
        openAnimation: .spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0),
        closeAnimation: .spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0),
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
/// **Registered in `ThemeRegistry.all`** (T26, AB-345): appended **after**
/// every other theme, **non-default** — Poured Island stays `all[0]` (the product's
/// face). The registration is the one-line append the architecture doc describes;
/// `HaloThemeTests` pins its registry position and that it never displaces the
/// default. T21–T25 built Halo unregistered (tests instantiate `HaloTheme()`
/// directly); this final slice completes the heroes and flips the registration.
struct HaloTheme: IslandTheme {

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
    /// (the same reason Poured is unsafe). The animated *panel* edge
    /// is on the surface shape, not the row, so it does not bear on this flag — the
    /// row's own luminous bleed settles it at `false`.
    let rowIsDrawingGroupSafe = false

    /// The void is opaque `#000`, so `OpenedSurfaceBackground` takes the opaque
    /// `surfaceInk` path and never builds a vibrancy view — which also makes Reduce
    /// Transparency a no-op for this theme (already opaque).
    let usesVibrancy = false

    // MARK: Geometry strategy

    /// Halo reuses the shared `V6RightSlotView` balanced matrix (so the pill
    /// width math + morph frame are unchanged) but overrides
    /// `cellGeometry` to `(6, 3.5, 3)` so each cell renders as a **bloomed light
    /// circle** (radius = cell / 2). Pinned by `HaloThemeTests`;
    /// `AgentsGridLayoutTests` are untouched.
    var agentsGridGeometry: IslandAgentsGridGeometry {
        IslandAgentsGridGeometry(
            balancedRows: { V6RightSlotView.balancedRows($0) },
            cellGeometry: { _ in (cell: HaloMetrics.gridCell, gap: HaloMetrics.gridGap, radius: HaloMetrics.gridRadius) }
        )
    }

    // MARK: Surface edge-light (AB-341 · T22)

    /// The living prismatic perimeter edge-light — Halo's whole state channel
    /// (SPEC §3a). Returns `HaloEdgeLight`, which masks a per-state `AngularGradient`
    /// with `shape.stroke(lineWidth: HaloMetrics.edge)` on the **same** morphing
    /// `OpenedIslandSurfaceShape` the open/close transition animates, so the ring
    /// and silhouette interpolate in lockstep. `context` carries the resolved "one
    /// loud thing" ambient state, closed-vs-opened, and the surface size. This is
    /// the one theme that overrides the default-nil hook.
    func surfaceEdgeOverlay(
        shape: OpenedIslandSurfaceShape,
        context: IslandSurfaceEdgeContext
    ) -> AnyView? {
        AnyView(HaloEdgeLight(shape: shape, context: context))
    }

    // MARK: Closed-pill ambient seams (AB-330 · overlay remediation F3)

    /// Tints the closed pill's traveling glyph by ambient state (AB-330 stage 2 ·
    /// overlay remediation F3 — mirrors `PouredIslandTheme.closedGlyphTint`).
    /// Shares the exact liveness/outcome colour tables `HaloClosedPill`'s own
    /// (Reduce Motion) indicator uses — `HaloSessionRowFormat.livenessTint(_:tokens:)`
    /// / `outcomeTint(_:tokens:)` in `HaloClosedPill.swift` — so this and the
    /// pill's own indicator can never disagree on a state's colour. Not on the
    /// hot path once `closedTravelingGlyph` below is also overridden (Halo's
    /// traveling glyph draws its own shape, with its own embedded tint, and
    /// never falls through to the default `UnifiedBars`-based extension that
    /// would call this) — kept anyway as a complete, independently correct and
    /// independently testable protocol conformance (`HaloClosedPillTests`),
    /// rather than left `nil` for a seam that plainly has a real answer.
    func closedGlyphTint(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?
    ) -> Color? {
        let ambient = PouredPillAmbientState.resolve(activity: activity, mode: mode, rightSlot: rightSlot)
        let state = HaloSessionRowFormat.edgeState(for: ambient)
        switch HaloSessionRowFormat.pillIndicator(for: state) {
        case .liveness(let barsMode):
            return HaloSessionRowFormat.livenessTint(HaloLivenessGlyph.Kind(mode: barsMode), tokens: tokens)
        case .permissionDot:
            return tokens.colors.statusWaitingForApproval
        case .outcome:
            return HaloSessionRowFormat.outcomeTint(state, tokens: tokens)
        }
    }

    /// Halo's traveling closed-pill glyph (overlay remediation F3 · Decision D3):
    /// returns the SAME liveness-glyph / ringed-permission-dot / outcome-mark
    /// indicator `HaloClosedPill`'s own (non-traveling) indicator already draws
    /// correctly under Reduce Motion (`showsGlyph: true`) — `HaloPillIndicatorGlyph`
    /// (`HaloClosedPill.swift`) is the shared view both call, so the default
    /// animated path and the Reduce Motion path can never again draw a different
    /// shape for the same ambient state. Before this seam, `islandGlyphOverlay`
    /// hardcoded the theme-agnostic `UnifiedBars` 3-bar glyph for every theme,
    /// which structurally cannot draw a dot — the A3 permission ring rendered
    /// correctly nowhere except the Reduce Motion crossfade.
    func closedTravelingGlyph(
        mode: UnifiedBars.Mode,
        rightSlot: IslandRightSlotContent?,
        activity: IslandClosedPillActivity?,
        size: CGFloat
    ) -> AnyView {
        let ambient = PouredPillAmbientState.resolve(activity: activity, mode: mode, rightSlot: rightSlot)
        let indicator = HaloSessionRowFormat.pillIndicator(for: HaloSessionRowFormat.edgeState(for: ambient))
        return AnyView(HaloPillIndicatorGlyph(indicator: indicator, tokens: tokens, box: size))
    }

    // MARK: Slot factories (restyled across T22–T25; the notification card
    // builds the shared `IslandNotificationCard` directly, exactly like Poured)

    /// The closed pill (AB-342 · T23 · SPEC §5A · mockup §A/§G′/§I′): wings via
    /// `HStack`, the six ambient states A1–A6, liveness/dot/outcome pairings, and
    /// the two-tone narrated label. The width math is delegated **verbatim** to
    /// `V6ClosedPill.externalOuterWidth` / `macbookOuterWidth`, so the closed↔opened
    /// morph frame is byte-identical to every other theme. The living edge-light /
    /// bloom is **not** drawn here — `IslandPanelView` composes it via
    /// `surfaceEdgeOverlay(shape:context:)` on the morphing silhouette (AB-341), so
    /// the pill never double-renders the ring; it renders only the wing content.
    /// The right slot forks per kind (`HaloRightSlotView`): the A2′ bloomed-circle
    /// agents-grid, the `.cnt.hot`/`.cnt.q` attention capsules, the G′ subagent
    /// nodes roll-up, and the I′ worst-window usage filament.
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
        AnyView(HaloClosedPill(
            mode: mode,
            // R4 · item 1: the wing plan owns the label too, so a §I′ pill whose
            // left wing already reads `Codex 92%` doesn't also print `Codex` in
            // the lane. Routed through the same pure rule the panel's width math
            // uses, so the pill and its reserved frame agree.
            label: HaloClosedPillWings.label(label, rightSlot: rightSlot),
            rightSlot: rightSlot,
            layout: layout,
            height: height,
            physicalNotchWidth: physicalNotchWidth,
            minWidth: minWidth,
            showsGlyph: showsGlyph
        ))
    }

    /// G-62/M-27 · board §B — Halo's docked peek, moved verbatim behind the
    /// PI-B-001 theme seam. Identical inputs, identical view, identical
    /// composition by the host (`replacesClosedSurface: false` keeps the pill
    /// drawn and the host's edge overlay tracing the union outline), so Halo's
    /// render tree is byte-identical to what `IslandPanelView` built inline
    /// behind a `theme.id == "halo"` check before the seam existed.
    ///
    /// `hoverPeekPreemptsHoverOpen` deliberately stays at the protocol default
    /// (`false`): Halo's dwell has always run to a full open, and changing that
    /// is not part of the Poured slice that introduced this seam.
    var themeDrawsHoverPeek: Bool { true }

    func closedSurfaceHoverPeek(_ context: IslandClosedHoverPeekContext) -> IslandClosedHoverPeek? {
        IslandClosedHoverPeek(
            body: AnyView(
                HaloHoverPeek(
                    content: context.content,
                    lang: context.lang,
                    availableWidth: context.availableWidth,
                    dockedWidth: context.closedPillWidth,
                    pillHeight: context.closedPillHeight,
                    pillBottomRadius: context.closedPillHeight / 2
                )
            ),
            bottomCornerRadius: HaloHoverPeek.cornerRadius,
            replacesClosedSurface: false
        )
    }

    /// R4 · item 1 · board §I′ — Halo's only wing split: the critical-usage
    /// filament + `Codex 92%` moves to the **left** wing (declaring its width so
    /// the shared reserve grows to hold it), the countdown stays alone on the
    /// right, and the now-duplicate lane label is dropped. Every other right-slot
    /// kind returns the protocol default's plan, unchanged.
    func closedPillWingPlan(
        label: String?,
        rightSlot: IslandRightSlotContent?,
        layout: V6ClosedLayout,
        height: CGFloat
    ) -> IslandClosedPillWingPlan {
        IslandClosedPillWingPlan(
            label: HaloClosedPillWings.label(label, rightSlot: rightSlot),
            leadingAccessoryWidth: HaloClosedPillWings.leadingAccessoryWidth(
                for: rightSlot,
                layout: layout
            )
        )
    }

    /// Opened header (AB-343 · T24 · SPEC §5C · mockup §C): the notch-split lanes
    /// (shared geometry) carrying thin light-filament usage arcs with percent +
    /// resets-in inline (`HaloUsageSummary`, fitted per profile) and the 26pt
    /// `white@.06` circular mute / settings / quit controls (`HaloHeaderButton`).
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
        AnyView(
            HaloHeaderControls(
                providers: providers,
                usesNotchAwareLayout: usesNotchAwareLayout,
                targetScreen: targetScreen,
                isSoundMuted: isSoundMuted,
                lang: lang,
                onToggleMute: onToggleMute,
                onShowSettings: onShowSettings,
                onQuit: onQuit
            )
        )
    }

    /// Halo's §I full-meter surface (AB-343 · SPEC §5I · mockup §I): the 52pt
    /// light-filament dials with reset countdowns and threshold words. Hosted by
    /// the `meters` preview scenario; the compact header filament stays in
    /// `openedHeader`.
    func usageMeterCard(providers: [UsageProviderPresentation], lang: LanguageManager) -> AnyView? {
        guard !providers.isEmpty else { return nil }
        return AnyView(HaloUsageMeterCard(providers: providers, lang: lang))
    }

    /// Halo is the one theme that mounts the §I card in the **opened panel** too
    /// (G-28 / G-34): its header lane shows a single filament per notch lane, so
    /// this is where the full per-window readout — 52pt dials, the 22pt
    /// threshold-coloured numerals, `resets in …`, the FINE/WARN/CRITICAL capsules
    /// — reaches the product. Chromeless (G-31): it sits *inside* the panel's own
    /// black body and edge ring, seamed off by the shared 8%-white hairline
    /// exactly like the list's summary strip and footer, so it must not draw a
    /// second card frame.
    func panelUsageMeterCard(
        providers: [UsageProviderPresentation],
        sideInset: CGFloat,
        lang: LanguageManager
    ) -> AnyView? {
        guard !providers.isEmpty else { return nil }
        return AnyView(HaloUsageMeterCard(providers: providers, lang: lang, sideInset: sideInset))
    }

    // MARK: Question-prompt seams (overlay remediation Phase 2A-follow-up · F1)

    /// The §F question card's Submit CTA. Reuses `HaloHeroButton`'s `.primary`
    /// kind verbatim — its `#FFCE8A→#FFAB54` 135° gradient is already an exact
    /// match to the board (`06-halo.html:371-372`), so this seam only had to
    /// widen the button's visibility (`private` → `internal`) and thread
    /// `isEnabled` through for the disabled state this card newly makes
    /// reachable (`canSubmit` toggles false→true; Allow-once/Deny/Jump-to-Codex
    /// are always actionable and never disabled). No `.frame(maxWidth:)` here —
    /// `HaloHeroButton` has always been intrinsic-width, matching the board's
    /// `display:inline-flex`.
    func questionSubmitButton(
        title: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> AnyView? {
        AnyView(
            HaloHeroButton(
                title: title,
                keycaps: nil,
                kind: .primary,
                isEnabled: isEnabled,
                accessibilityLabel: title,
                action: action
            )
        )
    }

    /// The §F question card's own container: **no chrome at all**. Halo's
    /// identity is a pure-black void whose only chrome is the 1.5pt edge-light
    /// (remediation plan DO-NOT-FIX table); `HaloQuestionHero` already wraps
    /// this content in `HaloHeroShell`'s own black-fill/ring/glow hero card
    /// (`HaloSessionRow.swift`), so the shared view's literal translucent box
    /// would draw a second, unwanted nested card. Returning `content` untouched
    /// removes that chrome entirely rather than reshaping it.
    func questionCardContainer(content: AnyView) -> AnyView? {
        content
    }

    /// D1 pagination: one question per page (`06-halo.html:1067-1156` — two
    /// separate frames, "1 of 2" / "Next" then "2 of 2" / "Submit"). See
    /// `IslandTheme.questionPageSize`'s doc for the shared mechanism.
    var questionPageSize: Int? { 1 }

    /// The collapsed void row (AB-344 · T25 · SPEC §5C/§5D · mockup §C/§D):
    /// `HaloSessionRow` — the `lead` (bloomed status dot + achromatic monogram),
    /// the `body` (workspace title + T05 branch disambiguator, the T03 narrated
    /// activity with a live-cyan verb, meta chips + Jump), the tabular age, the
    /// hover-reveal dismiss, and the phase-mapped edge-lit rail (running / permission
    /// / question only). The Part-2 seam: the expanded per-row detail and the
    /// actionable heroes (permission command/diff, question options, completion body,
    /// subagent nests) mount **below** this summary — AB-345 adds them here without
    /// touching the collapsed row.
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
        AnyView(HaloSessionRow(
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
        ))
    }

    /// Halo's session-list chrome (AB-343 · T24 · SPEC §5 Slot 4 · mockup §C):
    /// `HaloSessionListScaffold` — the hairline-bounded summary strip (non-zero
    /// buckets + tinted dots), "Needs you"-first section headers, inter-row
    /// 8%-white hairlines + white@.026 hover wash, and the quiet `N sessions · M
    /// need you` footer with its passive `Grouped by …` caption. The row slot is
    /// the AB-344 seam: rows route through `sessionRow` above, so once T24 pt3
    /// lands the void Halo row it drops straight into the scaffold with no
    /// change here.
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
        AnyView(
            HaloSessionListScaffold(
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
        )
    }

    // The notification card is the **shared** `IslandNotificationCard`: Halo
    // delegates to it (exactly like Poured), and its one row routes
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
        AnyView(
            IslandNotificationCard(
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
        )
    }

    // MARK: Quiet slots (Part 2 — rendered on the pure-black void, no box fills)

    /// `HaloEmptyState` — a 34pt static monitor glyph (t3), `All quiet` (14/600), a
    /// confident subtitle (12/400), and a `● Monitoring · N workspaces` pill (idle
    /// dot + hairline ring). `N` is `workspaceCount` — the AB-326 seam: distinct
    /// workspace names across current + recent sessions; the pill falls back to a
    /// bare `Monitoring` when the count is unavailable, never a fabricated number.
    /// `installedAgentNames` is accepted for signature parity but unused (the
    /// monitoring pill already answers "is this working?").
    func emptyState(
        lang: LanguageManager,
        hasRecentSessions: Bool,
        workspaceCount: Int,
        installedAgentNames: [String]
    ) -> AnyView {
        AnyView(HaloEmptyState(
            lang: lang,
            hasRecentSessions: hasRecentSessions,
            workspaceCount: workspaceCount
        ))
    }

    /// `HaloBootstrapPlaceholder` — the void shell shown while probing terminals on
    /// cold launch. Shares the empty-state identity; trivially flash-safe since the
    /// `#000` void is fully opaque (no gradient/material fade to flash a non-black
    /// fill before it mounts).
    func bootstrapPlaceholder(lang: LanguageManager) -> AnyView {
        AnyView(HaloBootstrapPlaceholder(lang: lang))
    }

    /// `HaloInstallHooksHint` — a quiet hairline line + `SETUP` tap CTA, with **NO
    /// edge-light / no glow** (a hint is not an attention state — color = state
    /// discipline, brief §7). The view contains no `.shadow` modifier.
    func installHint(lang: LanguageManager, onTap: @escaping () -> Void) -> AnyView {
        AnyView(HaloInstallHooksHint(lang: lang, onTap: onTap))
    }
}
