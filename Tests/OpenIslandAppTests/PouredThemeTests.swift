import Foundation
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

    // MARK: - Material tokens (SPEC §1d)

    /// PI-M-001: there is NO broad soft sheen. The reference glass body
    /// (`docs/design/overlay-redesign/01-poured-island.html:48-53`) declares only
    /// `--specular` (1px white@14% top catch), `--hairline-inset` (0.5px
    /// white@5%) and `--shadow` — the native 26pt white@50% wash had no
    /// counterpart in it and is removed.
    @Test
    func pouredHasNoBroadSoftSheen() {
        #expect(IslandMaterialTokens.poured.specularTopEdge == nil)
    }

    /// PI-M-002: the glass body carries exactly ONE inner edge — the 0.5pt
    /// `--hairline-inset` — so Poured drops the all-theme 0.07/1pt content-layer
    /// stroke, while the defaulted value keeps every other theme byte-identical.
    @Test
    func pouredDropsTheContentEdgeStrokeOthersKeepTheDefault() {
        #expect(IslandMaterialTokens.poured.contentEdgeStroke == nil)

        let preserved = IslandHairlineToken(opacity: 0.07, width: 1)
        for material in [
            IslandMaterialTokens.classic,
            IslandMaterialTokens.instrument,
            IslandMaterialTokens.flightDeck,
            IslandMaterialTokens.annual,
            IslandMaterialTokens.halo,
        ] {
            #expect(material.contentEdgeStroke == preserved)
        }
    }

    /// PI-B-002: pill, peek and panel are ONE continuous glass body, so Poured's
    /// morph paints one material for the whole interpolant. Every other theme
    /// keeps the two-layer crossfade it shipped with — Classic explicitly, since
    /// it is a vibrancy theme too and must stay byte-identical.
    @Test
    func onlyPouredMorphsAsOneBody() {
        #expect(IslandMaterialTokens.poured.morphsAsOneBody)

        for material in [
            IslandMaterialTokens.classic,
            IslandMaterialTokens.instrument,
            IslandMaterialTokens.flightDeck,
            IslandMaterialTokens.annual,
            IslandMaterialTokens.halo,
        ] {
            #expect(material.morphsAsOneBody == false)
        }
    }

    // MARK: - Closed-inset growth (SPEC §3.1 / AB-329)

    // MARK: - Classic status-colour parity (SPEC §1a)

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

    // MARK: - Text-ramp & hairline opacities (SPEC §1a)

    /// The text ramp and hairline opacities. The mockup's own drift values
    /// (`--t2 .66`, `--hair .09`) are **explicitly NOT adopted**: the mockup's
    /// own comment says `.6`, so the spec's drift-resolution keeps the shipped
    /// `secondaryTextOpacity 0.6` / `hairlineOpacity 0.08`. Pinned so a later
    /// "sync to mockup" pass can't silently reintroduce the drift.
    @Test
    func textAndHairlineOpacitiesKeepShippedValuesNotMockupDrift() {
        let colors = IslandThemeTokens.poured.colors

        #expect(colors.secondaryTextOpacity == 0.6)  // NOT the mockup's 0.66
        #expect(colors.tertiaryTextOpacity == 0.5)
        #expect(colors.hairlineOpacity == 0.08)       // NOT the mockup's 0.09
        // Increase-Contrast hairline lifts to 0.24 (the mockup implies .24 is fine).
        #expect(colors.hairlineOpacityIncreasedContrast == 0.24)
    }

    // MARK: - Chrome metrics (SPEC §1b)

    // MARK: - Motion (SPEC §1c)

    // MARK: - Material tint (SPEC §1d)

    // MARK: - Capability flags (SPEC §5.2)

    // MARK: - Question-prompt pagination (overlay remediation Phase 2B · F1a/D1)

    // MARK: - Agents-grid geometry (SPEC §5.2)

    // MARK: - Typography table (SPEC §2)

    /// The load-bearing roles, pinned `(size, weight, mono, tabular)` so a drift
    /// in the §2 table fails the build. Covers the grown headline sizes
    /// (workspace 13.2→14, activity 11→12.5, hero 12.5→14), the mono/sans split
    /// (branch / command / diff stay mono; the rest go SF Pro), the tabular-digit
    /// roles (age / summary number), and the lifted metadata key. Activity is
    /// spec'd 500–550 and set at 550 (matching the live verb).
    @Test
    func loadBearingTypographyRolesMatchTheSpecTable() {
        // (role, size, weight, isMono, isTabular)
        let expected: [(role: PouredType.Role, size: CGFloat, weight: CGFloat, mono: Bool, tabular: Bool)] = [
            (.workspaceTitle, 14, 600, false, false),
            (.activityLine, 12.5, 550, false, false),
            (.branchDisambiguator, 11, 400, true, false),
            (.age, 11, 500, false, true),
            (.sectionHeader, 10.5, 650, false, false),
            (.summaryNumber, 12, 700, false, true),
            (.commandBlock, 12, 600, true, false),
            (.diff, 11.5, 400, true, false),
            (.heroButtonLabel, 13, 600, false, false),
            (.heroTitle, 14, 640, false, false),
            (.metadataKey, 10, 600, false, false),
        ]

        for entry in expected {
            let spec = entry.role.spec
            #expect(spec.size == entry.size, "\(entry.role) size")
            #expect(spec.weight == entry.weight, "\(entry.role) weight")
            #expect(spec.isMono == entry.mono, "\(entry.role) mono")
            #expect(spec.isTabular == entry.tabular, "\(entry.role) tabular")
        }
        // Activity's spec weight is within the 500–550 band the table allows.
        #expect([500, 550].contains(PouredType.Role.activityLine.spec.weight))
    }

    /// Mono is reserved for code-shaped text only — command / diff / branch /
    /// inline `code` / mono metadata value. The roles the shipped
    /// theme drew in mono (section header, summary strip, agent chip, age) are
    /// now proportional SF Pro — Poured 2.0's largest visual change.
    @Test
    func monoIsReservedForCodeShapedRoles() {
        let monoRoles = Set(PouredType.Role.allCases.filter { $0.spec.isMono })
        #expect(monoRoles == Set<PouredType.Role>([
            .branchDisambiguator,
            .commandBlock,
            .diff,
            .assistantInlineCode,
            .metadataValueMono,
            // PI-B-001: the §B peek's second line is the pending *command*
            // (`font-family:var(--mono)`, `01-poured-island.html:721`) — code
            // shaped, so it belongs in this set rather than breaking the rule.
            .peekCommand,
        ]))

        for role in [PouredType.Role.sectionHeader, .summaryLabel, .summaryNumber, .age, .agentChipLabel, .metaChip] {
            #expect(role.spec.isMono == false, "\(role) must be sans in 2.0")
        }
    }

    // MARK: - Full-size button contract (F16)

    // MARK: - Usage threshold rule (SPEC §3.2 · §4I · AB-331)

    /// The one usage rule: the band cut-offs are the app-wide `usageColor`
    /// cut-offs (`>= 90` / `70..<90` / else), pinned at both boundaries plus the
    /// exact 34 / 78 / 92 fixture points so the §I meters render fine / warn /
    /// critical. Cut-offs are UNCHANGED from the shipped ring — only the colours
    /// moved onto tokens (asserted below).
    @Test
    func usageThresholdBandsMatchTheUsageColorCutoffs() {
        #expect(PouredUsageThreshold.threshold(for: 99) == .critical)
        #expect(PouredUsageThreshold.threshold(for: 92) == .critical)   // fixture
        #expect(PouredUsageThreshold.threshold(for: 90) == .critical)
        #expect(PouredUsageThreshold.threshold(for: 89.9) == .warn)
        #expect(PouredUsageThreshold.threshold(for: 78) == .warn)       // fixture
        #expect(PouredUsageThreshold.threshold(for: 70) == .warn)
        #expect(PouredUsageThreshold.threshold(for: 69.9) == .fine)
        #expect(PouredUsageThreshold.threshold(for: 34) == .fine)       // fixture
        #expect(PouredUsageThreshold.threshold(for: 0) == .fine)
    }

    /// Percent → **token** colour, the single rule the ring arc, the ring value
    /// and the §I dial all share: `fine → statusCompleted`,
    /// `warn → statusWaitingForAnswer`, `critical → statusFailed`. The retired
    /// raw `.red/.orange/.green` the shipped `usageColor` returned are gone.
    @Test
    func usageThresholdColorsResolveToStatusTokens() {
        let colors = IslandThemeTokens.poured.colors

        #expect(PouredUsageThreshold.fine.color(colors) == colors.statusCompleted)
        #expect(PouredUsageThreshold.warn.color(colors) == colors.statusWaitingForAnswer)
        #expect(PouredUsageThreshold.critical.color(colors) == colors.statusFailed)

        // Resolved from a percentage at each boundary — the arc/value colour the
        // header ring and §I dial both paint.
        #expect(PouredUsageThreshold.threshold(for: 89.9).color(colors) == colors.statusWaitingForAnswer)
        #expect(PouredUsageThreshold.threshold(for: 90).color(colors) == colors.statusFailed)
        #expect(PouredUsageThreshold.threshold(for: 69.9).color(colors) == colors.statusCompleted)
        #expect(PouredUsageThreshold.threshold(for: 70).color(colors) == colors.statusWaitingForAnswer)

        // The retired raw palette must not leak back in.
        #expect(PouredUsageThreshold.critical.color(colors) != Color.red.opacity(0.95))
        #expect(PouredUsageThreshold.warn.color(colors) != Color.orange.opacity(0.95))
        #expect(PouredUsageThreshold.fine.color(colors) != Color.green.opacity(0.95))
    }

    // MARK: - Usage meter strings localize (AB-331)

    // MARK: - Scaffold footer + empty-state strings localize (AB-331)

    // MARK: - §I meter-card hosting seam (AB-331)

    /// The full §I meter card is hosted only by Poured, and only when there are
    /// usage windows to show: `usageMeterCard` returns the card for Poured with
    /// providers, `nil` for Poured with none, and `nil` for every other theme
    /// (they carry no full-meter surface, so the `meters` preview keeps drawing
    /// only their compact header ring).
    @Test @MainActor
    func usageMeterCardHostsOnlyForPouredWithProviders() {
        let lang = LanguageManager()
        let providers = AppearancePreviewFixtures.usageProviders(now: Date())
        #expect(!providers.isEmpty)

        #expect(PouredIslandTheme().usageMeterCard(providers: providers, lang: lang) != nil)
        #expect(PouredIslandTheme().usageMeterCard(providers: [], lang: lang) == nil)
        #expect(ClassicTheme().usageMeterCard(providers: providers, lang: lang) == nil)
    }
}

