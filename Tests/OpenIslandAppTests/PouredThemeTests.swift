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
            IslandMaterialTokens.flightDeck,
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
            IslandMaterialTokens.flightDeck,
            IslandMaterialTokens.halo,
        ] {
            #expect(material.morphsAsOneBody == false)
        }
    }

    /// R6 · N-1 (PI-M-002): the rendered board splits the ambient states on the
    /// contour hairline. Quiet `.glass` (`01-poured-island.html:134`) and the
    /// working `lumen` keyframes (`:187-188`) write `--hairline-inset` into
    /// their `box-shadow` stack; `attnpulse` (`:193-194`), `settle`
    /// (`:198-200`) and A4's inline question glow (`:640`) all omit it. So the
    /// attention and settle blooms drop the inner hairline and everything else
    /// keeps it — deliberately NOT the same set as `castsGlow`, which working
    /// is also in.
    @Test @MainActor
    func attentionAndSettleDropTheContourHairlineWhileQuietAndWorkingKeepIt() {
        #expect(PouredPillAmbientState.idle.suppressesInnerHairline == false)
        #expect(PouredPillAmbientState.working(manyWorking: false).suppressesInnerHairline == false)
        #expect(PouredPillAmbientState.working(manyWorking: true).suppressesInnerHairline == false)
        #expect(PouredPillAmbientState.permission.suppressesInnerHairline)
        #expect(PouredPillAmbientState.question.suppressesInnerHairline)
        #expect(PouredPillAmbientState.completed(.success).suppressesInnerHairline)
        // A6 rests with no glow at all, so there is nothing to trade the edge for.
        #expect(PouredPillAmbientState.completed(.interrupted).suppressesInnerHairline == false)
        #expect(PouredPillAmbientState.completed(.failed).suppressesInnerHairline == false)
        // `working` glows but keeps the hairline — the one place the two differ.
        #expect(PouredPillAmbientState.working(manyWorking: false).castsGlow)

        // Theme seam: Poured folds the spotlight's phase into the decision …
        let poured = PouredIslandTheme()
        #expect(poured.closedSurfaceSuppressesInnerHairline(mode: .waiting, rightSlot: nil, activity: nil))
        #expect(poured.closedSurfaceSuppressesInnerHairline(mode: .running, rightSlot: nil, activity: nil) == false)
        #expect(poured.closedSurfaceSuppressesInnerHairline(mode: .idle, rightSlot: nil, activity: nil) == false)
        // … while every other theme takes the protocol default and never drops
        // an edge it drew.
        for theme in [ClassicTheme(), HaloTheme()] as [any IslandTheme] {
            #expect(theme.closedSurfaceSuppressesInnerHairline(mode: .waiting, rightSlot: nil, activity: nil) == false)
        }
    }

    /// R6 · N-10 (PI-B-003): every rendered `.pill` and the §B peek body carry
    /// two concave `.fillet` spans at their top OUTER corners — a `--fillet`
    /// (12px) square filled with `--glass-fillet` `rgba(20,25,36,.92)`, masked
    /// by a radial gradient centred on the square's own outer corner
    /// (`01-poured-island.html:50,56,136-143,718`).
    ///
    /// Pins the token and the mask's *concavity*: the outer corner is carved
    /// away, the inner corner (the one hugging the body wall) survives.
    @Test
    func pouredDrawsConcaveTopCornerFilletFlaresAndOtherThemesDrawNone() throws {
        let fillet = try #require(IslandMaterialTokens.poured.cornerFillet)
        #expect(fillet.size == 12)
        #expect(fillet.opacity == 0.92)
        #expect(fillet.color == Color(red: 20 / 255.0, green: 25 / 255.0, blue: 36 / 255.0))
        #expect(fillet.resolvedColor == fillet.color.opacity(0.92))

        for material in [
            IslandMaterialTokens.classic,
            IslandMaterialTokens.flightDeck,
            IslandMaterialTokens.halo,
        ] {
            #expect(material.cornerFillet == nil)
        }

        // Geometry: a 12×12 piece whose filled region is the square minus the
        // quarter disc centred on the outer top corner.
        let box = CGRect(x: 0, y: 0, width: fillet.size, height: fillet.size)
        let leading = IslandCornerFilletShape(side: .leading).path(in: box)
        let trailing = IslandCornerFilletShape(side: .trailing).path(in: box)

        #expect(leading.boundingRect.width <= fillet.size)
        #expect(leading.boundingRect.height <= fillet.size)
        // Outer top corner carved away; the inner bottom corner (against the
        // body wall) filled — that is what makes the curve concave.
        #expect(leading.contains(CGPoint(x: 1, y: 1)) == false)
        #expect(leading.contains(CGPoint(x: 11, y: 11)))
        #expect(trailing.contains(CGPoint(x: 11, y: 1)) == false)
        #expect(trailing.contains(CGPoint(x: 1, y: 11)))
        // The arc itself: the point one fillet away from the outer corner along
        // the bottom edge sits ON the boundary, so just inside it is still cut.
        #expect(leading.contains(CGPoint(x: 0.5, y: 11.5)) == false)
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
            // PI-C-006: the §C in-list Approve / Deny override of the same
            // button — 12/600 sans (`01-poured-island.html:820`).
            (.compactButtonLabel, 12, 600, false, false),
            // PI-I-001: the header wing's `.ut b` countdown — 11/600 tabular.
            (.usageResetLabel, 11, 600, false, true),
            (.heroTitle, 14, 640, false, false),
            (.metadataKey, 10, 600, false, false),
            // Slice 5 §F″: the compact single's inline sentence — 13/560
            // (`01-poured-island.html:1253`), deliberately NOT `.optionLabel`'s
            // 13/600 (which resolves one weight step heavier).
            (.compactQuestionText, 13, 560, false, false),
            // Slice 5 mapper gap 13: `.opt-other{font-size:12px}` at body
            // weight (`:400-402`); the italic rides at the call site.
            (.optionOther, 12, 400, false, false),
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

    // MARK: - §F submit keycap (Slice 5)

    /// The board prints `↵` (`&#8629;`) on both question submit CTAs
    /// (`01-poured-island.html:1194`, `:1234`) and Return really submits, so the
    /// cap is an honest affordance. Pinned so it can never drift to `⏎`/`Enter`
    /// — and, per Y4, it is deliberately drawn with the amber `.btn.primary .kc
    /// kbd` tint the board never overrides for the gold face.
    @Test
    func questionSubmitKeycapIsTheBoardsReturnGlyph() {
        #expect(PouredQuestionKeycaps.submit == ["\u{21B5}"])
    }

    /// Slice 5 added the R10 intent sentences and the R11 per-surface verbs as
    /// Poured-only keys (so `approval.allowOnce` — "Yes" — keeps every other
    /// theme byte-identical). A key present only in `en` reads as raw dot-case on
    /// a Chinese install, which is exactly what this sweep catches.
    @Test @MainActor
    func pouredHeroCopyLocalizesInEveryLanguage() {
        let keys = [
            "poured.approval.allowOnce",
            "poured.approval.approve",
            "poured.approval.deny",
            "poured.approval.intent.runCommand",
            "poured.approval.intent.editFile",
            "poured.approval.intent.terminalApproval",
            "poured.question.selectAllThatApply",
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

        // R11, board-verbatim and PER SURFACE: the §E hero says "Allow once",
        // the §C in-list row says "Approve" (`01-poured-island.html:819`), and
        // neither is the shared `approval.allowOnce` ("Yes") the other themes
        // still use.
        let english = LanguageManager()
        english.language = .en
        #expect(english.t("poured.approval.allowOnce") == "Allow once")
        #expect(english.t("poured.approval.approve") == "Approve")
        #expect(english.t("poured.approval.deny") == "Deny")
        #expect(english.t("approval.allowOnce") == "Yes")
    }

    // MARK: - §D primary button (Slice 5)

    /// The board draws TWO different blues on Poured's full-size buttons: §D's
    /// `Jump to terminal` (`linear-gradient(180deg,#8fbcff,#6ea7ff)`, ink
    /// `#0a1a35`, glow `rgba(110,167,255,.6)` — `01-poured-island.html:963-964`)
    /// and E3's Codex CTA (`#8fccf0→#4aa3df`, ink `#062133`). Native collapsed
    /// both onto `.wayfinding`, so §D rendered in E3's colour.
    ///
    /// The palette itself is file-private, so the hexes are pinned by scanning
    /// the source — the same idiom `QuestionPromptAccessibilityTests` uses for
    /// contracts SwiftUI won't hand back without a host. What it buys is the
    /// guard that matters: the split can't quietly collapse back onto one kind,
    /// and §H's completion jump (whose board blue this round never extracted)
    /// stays on `.wayfinding` where it was.
    @Test
    func detailPrimaryIsTheBoardsOwnBlueNotE3sCodexCTA() throws {
        #expect(PouredFullSizeButtonKind.detailPrimary.usesGradient)
        #expect(PouredFullSizeButtonKind.detailPrimary.showsButtonGlow)
        #expect(PouredFullSizeButtonKind.allCases.count == 5)

        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OpenIslandApp/Views/Island/PouredSessionRow.swift"),
            encoding: .utf8
        )

        for hex in ["0x8F/255, green: 0xBC/255, blue: 0xFF/255",
                    "0x6E/255, green: 0xA7/255, blue: 0xFF/255",
                    "0x0A/255, green: 0x1A/255, blue: 0x35/255"] {
            #expect(source.contains(hex), "§D blue \(hex) missing")
        }

        // Exactly one surface takes the new kind — §D's `detailActionRail`.
        #expect(source.components(separatedBy: "kind: .detailPrimary").count - 1 == 1)
        // E3's terminal CTA and §H's completion jump keep the Codex blue.
        #expect(source.components(separatedBy: "kind: .wayfinding").count - 1 == 2)
    }

    /// The board carries the `.q-head` workspace span on §F only: F′ renders
    /// "no workspace tag, no 'Question x of y'" (`01-poured-island.html:1218-1219`)
    /// and F″'s head is the chip plus the sentence. Native injected it
    /// unconditionally, so F′ drew a span the board does not have. Pinned as a
    /// source scan because the accessor is a private computed property on a
    /// SwiftUI view — the same idiom `QuestionPromptAccessibilityTests` uses for
    /// the shared interior's seams.
    @Test
    func questionHeroInjectsTheWorkspaceSpanOnlyWhereTheBoardDrawsIt() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OpenIslandApp/Views/Island/PouredSessionRow.swift"),
            encoding: .utf8
        )

        // One injection site, and it is the gated accessor rather than a
        // literal `QuestionPromptHeadContext(` in the call.
        #expect(source.components(separatedBy: "headContext: pouredQuestionHeadContext").count - 1 == 1)
        #expect(source.components(separatedBy: "private var pouredQuestionHeadContext: QuestionPromptHeadContext?").count - 1 == 1)
        // The gate itself: a paginated prompt (more than one question) is the
        // only shape the span rides on.
        #expect(source.contains("prompt.questions.count > 1"))

        // And the fixtures behind the three board frames really do split that
        // way — F2 paginates, F′ and F″ do not.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect((AppearancePreviewFixtures.questionMulti(now: now).questionPrompt?.questions.count ?? 0) > 1)
        #expect(AppearancePreviewFixtures.pouredMultiSelectQuestion(now: now).questionPrompt?.questions.count == 1)
        #expect(AppearancePreviewFixtures.pouredCompactQuestion(now: now).questionPrompt?.questions.count == 1)
    }
}

