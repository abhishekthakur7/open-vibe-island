import SwiftUI

/// Typography roles for the Poured Island 2.0 theme (AB-329,
/// `SPEC-poured-island` §2).
///
/// The shared `IslandThemeTokens` layer deliberately carries no typography —
/// themes swap whole slot views, so per-view fonts belong to each theme. This
/// enum is Poured's own type table, kept in one place so every Poured slot view
/// (T12–T15) draws from the same roles and the scale is checkable in one spot
/// (`PouredThemeTests`), exactly like `FlightDeckTypography`.
///
/// Poured 2.0 is the largest visual change in the redesign: the shipped theme
/// used `design: .monospaced` for section headers, the summary strip, badges,
/// age and usage labels; the mockup uses **proportional SF Pro** with
/// `tabular-nums`, reserving mono strictly for **code / branch / command /
/// diff / inline-code**. This table encodes that split. Numerals are tabular
/// (`.monospacedDigit()`) wherever the mockup sets `font-variant-numeric:
/// tabular-nums` (ages, timers, counts, percentages) — the whole face never
/// switches to mono just to line the digits up.
///
/// This ticket only **defines** the table; no view adopts it yet (that is
/// T12–T15). Defining it now, complete and pinned, keeps the scale from
/// drifting slot-by-slot as the views are ported.
///
/// **Weight note.** The mockup uses CSS numeric weights (500 / 550 / 560 / 640 /
/// 650 …) finer-grained than SwiftUI's named `Font.Weight` cases. Each role's
/// *spec* weight is stored verbatim as the pinnable number (`Spec.weight`), and
/// `Spec.fontWeight` rounds it to the nearest system weight for the actual
/// `Font` — so the contract test pins the design intent (650) while the render
/// uses the closest face SF Pro exposes (`.semibold`).
enum PouredType {
    /// The lowest size any *readable* Poured role may use. Density comes from
    /// weight, case, tracking and the glass itself — never from sub-10pt
    /// micro-type. Every role in `roleTable` sits at or above this floor
    /// (`PouredThemeTests.everyReadableRoleHoldsTheFloor`).
    static let floor: CGFloat = 10

    /// One typographic role, described by its parameters rather than by a built
    /// `Font`, so the table is inspectable and pinnable. `Font` is *computed*
    /// from these fields (`font`), which keeps `Spec` `Equatable` / `Sendable`.
    struct Spec: Equatable, Sendable {
        /// Point size (mockup px at 1× == SwiftUI pt).
        var size: CGFloat

        /// The mockup's CSS-style numeric weight (400 / 500 / 550 / 600 / 640 /
        /// 650 / 700). Stored as the design intent; `fontWeight` rounds it for
        /// rendering.
        var weight: CGFloat

        /// Letter-spacing in **em** (relative to `size`), as the mockup expresses
        /// it. Negative on tight display headlines, positive on the uppercase
        /// micro-labels, `0` for body/prose. `trackingPoints` converts it for a
        /// `.tracking()` modifier.
        var trackingEm: CGFloat

        /// `true` → `design: .monospaced`. Reserved for code-shaped text only:
        /// command / diff / branch / directory / inline `code`.
        var isMono: Bool

        /// `true` → `.monospacedDigit()`. Lines up numerals (ages, timers,
        /// counts, percentages) without switching the whole face to mono.
        var isTabular: Bool

        /// `true` → the role is uppercased by its consuming view (section
        /// headers, kickers, metadata keys). Carried here so the case treatment
        /// travels with the role rather than being re-decided per view.
        var isUppercase: Bool

        /// The nearest system `Font.Weight` to the spec `weight`. SF Pro exposes
        /// named weights only, so the 600–650 "display semibold" band collapses
        /// to `.semibold` and 550 / 560 to `.medium`.
        var fontWeight: Font.Weight {
            switch weight {
            case ..<450: .regular
            case ..<575: .medium
            case ..<675: .semibold
            default: .bold
            }
        }

        /// `trackingEm` resolved to points for a `.tracking()` modifier.
        var trackingPoints: CGFloat { trackingEm * size }

        /// The SwiftUI `Font` this role renders in — the value T12–T15 apply.
        /// Mono roles take `design: .monospaced`; tabular roles fold in
        /// `.monospacedDigit()`. Tracking and casing are applied by the
        /// consuming view (a `Font` cannot carry tracking).
        var font: Font {
            let base = Font.system(
                size: size,
                weight: fontWeight,
                design: isMono ? .monospaced : .default
            )
            return isTabular ? base.monospacedDigit() : base
        }
    }

    /// Every Poured typographic role. The names are the API surface T12–T15
    /// consume: `PouredType.Role.workspaceTitle.font`, etc.
    enum Role: String, CaseIterable, Sendable {
        // Row / list chrome
        case workspaceTitle          // .ws   — headline / workspace name
        case completionHeaderTitle   // completion header
        case activityLine            // .act  — narrated activity line
        case activityVerb            // .act .live — the live verb span
        case branchDisambiguator     // .disamb — duplicate-workspace branch (mono)
        case metaChip                // .chip — meta chip label
        case age                     // .age  — right-aligned age (tabular)
        case sectionHeader           // .grp  — grouped section header
        case listOverviewTitle       // list overview / summary title
        case summaryLabel            // summary strip bucket label
        case summaryNumber           // .n    — summary strip count (tabular)
        case agentChipLabel          // agent identity chip label
        case outcomeBadge            // .outcome — Success / Interrupted / Failed
        case outcomeBadgeHero        // .outcome — §H hero override (11px)
        case jumpChip                // .jump — jump-to-terminal chip

        // Meters
        case usageMeterLabel         // .ml   — §I meter `provider · window` label
        case displayNumeral          // .mpct — big meter percentage (tabular)
        case usageRingValue          // .uv   — ring value readout (tabular)
        case usageResetLabel         // .ut b — header wing reset countdown

        // Code surfaces (mono)
        case commandBlock            // .cmd  — permission command (mono)
        case diff                    // .diff — inline diff (mono)

        // Permission / question hero
        case keycap                  // .kc kbd — keycap hint
        case heroButtonLabel         // hero-frame approval / submit CTA label
        case compactButtonLabel      // §C in-list Approve / Deny CTA label
        case heroTitle               // .ht   — permission hero title
        case heroSubtitle            // .hs   — permission hero subtitle
        case questionText            // .q-text — the question prompt
        case compactQuestionText     // §F″ inline question sentence
        case optionLabel             // .opt .ol — option label
        case optionDesc              // .opt .od — option description
        case optionNumber            // .opt .num — option number (tabular)
        case optionOther             // .opt-other — freeform escape hatch (italic)
        case questionChip            // .q-chip — question kicker chip

        // §B hover peek (PI-B-001)
        case peekTitle               // §B head row — "<name> wants to run a command"
        case peekCommand             // §B head row — the pending command (mono)
        case peekHint                // §B hint row — "Click to review & approve"

        // Subagents / tasks
        case subagentType            // .sa-type — subagent type
        case subagentTask            // .sa-task — subagent task
        case subagentElapsed         // .sa-time — live elapsed (tabular)
        case nestHeader              // .nest-h — nested-list header
        case todo                    // .todo — task list item
        case pillCountBadge          // .count — closed-pill right-slot capsule
        case pillLabel               // .pill .lab — closed-pill narrated label

        // Assistant prose / metadata
        case assistantBody           // .assistant — last-message rich prose
        case assistantLabel          // assistant-message-header kicker
        case assistantInlineCode     // inline `code` in prose (mono)
        case metadataKey             // .mk   — metadata grid key (lifted to floor)
        case metadataValue           // .mv   — metadata grid value
        case metadataValueMono       // .mv .mono — mono metadata value (branch/dir)

        // Empty / bootstrap / install
        case emptyTitle              // .et   — empty-state title
        case emptySubtitle           // .es   — empty-state subtitle
        case bootstrapHint           // bootstrap placeholder line
        case installHint             // install-hooks hint line

        /// This role's parameters.
        var spec: Spec { PouredType.roleTable[self]! }

        /// This role's rendered `Font` — the value T12–T15 apply.
        var font: Font { spec.font }
    }

    /// The full §2 typography table. One entry per `Role`; the single source of
    /// truth the contract test iterates.
    ///
    /// Two deliberate deviations from the mockup, both documented at the token:
    /// - **Metadata key** is 9.5 in the mockup, but a metadata *key* is readable
    ///   chrome, not a fitted micro-indicator, so it is **lifted to the 10pt
    ///   floor** (see `metadataKey` below).
    /// - **Usage ring value** is a 9.5–11.5 range in the mockup; the readable
    ///   end (11.5, which the shipped ring already uses) is taken so no readable
    ///   role dips below the floor.
    static let roleTable: [Role: Spec] = [
        // size, weight, trackingEm, mono, tabular, uppercase
        .workspaceTitle:        Spec(size: 14,   weight: 600, trackingEm: -0.01, isMono: false, isTabular: false, isUppercase: false),
        .completionHeaderTitle: Spec(size: 15,   weight: 640, trackingEm: -0.01, isMono: false, isTabular: false, isUppercase: false),
        .activityLine:          Spec(size: 12.5, weight: 550, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .activityVerb:          Spec(size: 12.5, weight: 550, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .branchDisambiguator:   Spec(size: 11,   weight: 400, trackingEm: 0,     isMono: true,  isTabular: false, isUppercase: false),
        .metaChip:              Spec(size: 10.5, weight: 500, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .age:                   Spec(size: 11,   weight: 500, trackingEm: 0,     isMono: false, isTabular: true,  isUppercase: false),
        .sectionHeader:         Spec(size: 10.5, weight: 650, trackingEm: 0.09,  isMono: false, isTabular: false, isUppercase: true),
        .listOverviewTitle:     Spec(size: 10.5, weight: 650, trackingEm: 0.16,  isMono: false, isTabular: false, isUppercase: true),
        .summaryLabel:          Spec(size: 11,   weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .summaryNumber:         Spec(size: 12,   weight: 700, trackingEm: 0,     isMono: false, isTabular: true,  isUppercase: false),
        .agentChipLabel:        Spec(size: 10.5, weight: 500, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .outcomeBadge:          Spec(size: 10.5, weight: 650, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        // PI-X-001/H1: inside the §H completion hero the board inline-bumps the
        // same pill to `font-size:11px;padding:3px 10px`
        // (`01-poured-island.html:1400`) — size only, the 650 weight of
        // `.outcome` (`:292`) is untouched. The §C row keeps `outcomeBadge`.
        .outcomeBadgeHero:      Spec(size: 11,   weight: 650, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .jumpChip:              Spec(size: 11.5, weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),

        // PI-I-001/I1: the board's `.mtx .ml` — `12px`, `font-weight:550`
        // (`01-poured-island.html:473`). The card drew it at `.medium` (500);
        // 550 is the same rendered face here, but the design intent is now
        // pinned in the table instead of being re-decided at the view.
        .usageMeterLabel:       Spec(size: 12,   weight: 550, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .displayNumeral:        Spec(size: 20,   weight: 640, trackingEm: -0.02, isMono: false, isTabular: true,  isUppercase: false),
        // Mockup range 9.5–11.5; readable end taken so the role holds the floor.
        .usageRingValue:        Spec(size: 11.5, weight: 700, trackingEm: 0,     isMono: false, isTabular: true,  isUppercase: false),
        // PI-I-001: the board's `.umeter .ut b` — 11px/600, block, not
        // uppercase, `letter-spacing:0` (`01-poured-island.html:234`).
        .usageResetLabel:       Spec(size: 11,   weight: 600, trackingEm: 0,     isMono: false, isTabular: true,  isUppercase: false),

        .commandBlock:          Spec(size: 12,   weight: 600, trackingEm: 0,     isMono: true,  isTabular: false, isUppercase: false),
        .diff:                  Spec(size: 11.5, weight: 400, trackingEm: 0,     isMono: true,  isTabular: false, isUppercase: false),

        .keycap:                Spec(size: 10,   weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .heroButtonLabel:       Spec(size: 13,   weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        // PI-C-006: the §C row override of the same `.btn` — `font-size:12px`
        // (`01-poured-island.html:820`), weight unchanged.
        .compactButtonLabel:    Spec(size: 12,   weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .heroTitle:             Spec(size: 14,   weight: 640, trackingEm: -0.01, isMono: false, isTabular: false, isUppercase: false),
        .heroSubtitle:          Spec(size: 11,   weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .questionText:          Spec(size: 14.5, weight: 560, trackingEm: -0.01, isMono: false, isTabular: false, isUppercase: false),
        // Slice 5 §F″: the compact single states its sentence *inline* beside the
        // chip at `font-size:13px;font-weight:560` (`01-poured-island.html:1253`)
        // — the same 560 voice as `.q-text`, one step down in size and without
        // its optical tracking, because it is set as a label, not a block.
        .compactQuestionText:   Spec(size: 13,   weight: 560, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .optionLabel:           Spec(size: 13,   weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .optionDesc:            Spec(size: 11.5, weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .optionNumber:          Spec(size: 11,   weight: 700, trackingEm: 0,     isMono: false, isTabular: true,  isUppercase: false),
        // Slice 5 (mapper gap 13): `.opt-other{font-size:12px}` at the body
        // weight (`01-poured-island.html:400-402`). The italic is applied at the
        // call site — `Spec` carries no slant field, and no other Poured role
        // needs one.
        .optionOther:           Spec(size: 12,   weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .questionChip:          Spec(size: 10,   weight: 700, trackingEm: 0.05,  isMono: false, isTabular: false, isUppercase: true),

        // §B peek, read verbatim off the board's own inline styles
        // (`01-poured-island.html:718,721,727`): 13/600, 11.5 mono, 11.
        .peekTitle:             Spec(size: 13,   weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .peekCommand:           Spec(size: 11.5, weight: 400, trackingEm: 0,     isMono: true,  isTabular: false, isUppercase: false),
        .peekHint:              Spec(size: 11,   weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),

        .subagentType:          Spec(size: 12,   weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .subagentTask:          Spec(size: 11,   weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .subagentElapsed:       Spec(size: 11,   weight: 400, trackingEm: 0,     isMono: false, isTabular: true,  isUppercase: false),
        .nestHeader:            Spec(size: 10,   weight: 650, trackingEm: 0.08,  isMono: false, isTabular: false, isUppercase: true),
        .todo:                  Spec(size: 12,   weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        // PI-X-001/G3 (correction 2): the board's right-slot `.count` capsule —
        // `font-size:12px; font-weight:650` (`01-poured-island.html:174-176`).
        // Tabular so a ticking `2/5 → 3/5` cannot jitter the capsule's width.
        .pillCountBadge:        Spec(size: 12,   weight: 650, trackingEm: 0,     isMono: false, isTabular: true,  isUppercase: false),
        // PI-X-001/G3 (correction 2): the closed pill's label is the board's
        // `.pill .lab` — `font-size:12.5px; letter-spacing:-.01em` and **no**
        // `font-weight`, i.e. the inherited body 400 (`01-poured-island.html:154`).
        // Native rendered it in `activityLine`, which is the *row*'s `.act` rule
        // (12.5/550, tracking 0, `:266`) — a different board rule that happens to
        // share the size. The extra weight and the missing negative tracking cost
        // ~6.4pt on the board's own §G″ sentence, which is exactly what pushed
        // `Refactoring · 3 agents` past the notch lane and truncated it to
        // `Refactoring · 3 a…`. No width math moves: `V6ClosedPill`'s statics
        // measure the label by character count, not by face.
        .pillLabel:             Spec(size: 12.5, weight: 400, trackingEm: -0.01, isMono: false, isTabular: false, isUppercase: false),

        .assistantBody:         Spec(size: 12.5, weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .assistantLabel:        Spec(size: 10,   weight: 650, trackingEm: 0.08,  isMono: false, isTabular: false, isUppercase: true),
        .assistantInlineCode:   Spec(size: 11,   weight: 400, trackingEm: 0,     isMono: true,  isTabular: false, isUppercase: false),
        // Mockup 9.5, but a metadata key is readable chrome → lifted to the floor.
        .metadataKey:           Spec(size: 10,   weight: 600, trackingEm: 0.06,  isMono: false, isTabular: false, isUppercase: true),
        .metadataValue:         Spec(size: 12.5, weight: 550, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .metadataValueMono:     Spec(size: 11.5, weight: 550, trackingEm: 0,     isMono: true,  isTabular: false, isUppercase: false),

        .emptyTitle:            Spec(size: 14,   weight: 600, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .emptySubtitle:         Spec(size: 12,   weight: 400, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .bootstrapHint:         Spec(size: 14,   weight: 500, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
        .installHint:           Spec(size: 12,   weight: 500, trackingEm: 0,     isMono: false, isTabular: false, isUppercase: false),
    ]

    /// The point size of every readable role — the vector `PouredThemeTests`
    /// asserts stays at or above `floor`. (Every Poured role is readable; there
    /// is no fitted micro-indicator role like the closed-grid "+N".)
    static var readableRoleSizes: [CGFloat] {
        Role.allCases.map { $0.spec.size }
    }

    /// Convenience `Font` accessor: `PouredType.font(for: .workspaceTitle)`.
    static func font(for role: Role) -> Font { role.font }
}
