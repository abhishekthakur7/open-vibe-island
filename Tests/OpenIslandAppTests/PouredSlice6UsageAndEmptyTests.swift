import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Poured parity Slice 6 · part B — the §I usage card / §I′ pill chip and the §J
/// empty state, pinned against the board (PI-I-001 · PI-X-001 I/J, R14).
///
/// Same discipline as the other Poured suites: pure values and source pins, no
/// mounted views. The layout claim ("a board-width card renders 2 + 1 meters")
/// is asserted through `PouredMeterFlow`, which is the arithmetic the `Layout`
/// itself calls, so the composition is checkable without a render.
struct PouredSlice6UsageAndEmptyTests {

    private static func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private static let meterCardSource = "Sources/OpenIslandApp/Views/Island/PouredUsageMeterCard.swift"
    private static let usageSummarySource = "Sources/OpenIslandApp/Views/Island/PouredUsageSummary.swift"
    private static let emptyStateSource = "Sources/OpenIslandApp/Views/Island/PouredEmptyState.swift"

    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - §I threshold pill (`01-poured-island.html:481-483`)

    /// The board tints each band separately; the card painted one uniform `0.15`.
    @Test
    func thresholdPillFillIsPerBand() {
        #expect(PouredUsageThreshold.fine.pillFillOpacity == 0.14)
        #expect(PouredUsageThreshold.warn.pillFillOpacity == 0.14)
        #expect(PouredUsageThreshold.critical.pillFillOpacity == 0.16)
    }

    @Test
    func thresholdPillReadsTheBandFillRatherThanAUniformAlpha() throws {
        let card = try Self.source(Self.meterCardSource)
        #expect(card.contains("color.opacity(threshold.pillFillOpacity)"))
        #expect(!card.contains("color.opacity(0.15)"))
    }

    // MARK: - §I meter label (`:473`)

    /// The board's `.ml` is 550, not `.medium`(500) decided at the view.
    @Test
    func meterLabelTakesThe550RoleFromTheTypeTable() throws {
        let spec = PouredType.Role.usageMeterLabel.spec
        #expect(spec.size == 12)
        #expect(spec.weight == 550)
        #expect(spec.isMono == false)
        #expect(spec.isUppercase == false)

        let card = try Self.source(Self.meterCardSource)
        #expect(card.contains("PouredType.Role.usageMeterLabel.font"))
        #expect(!card.contains(".font(.system(size: 12, weight: .medium))"))
    }

    // MARK: - §I dial track (`:1456` card vs `:229` header)

    /// R4-8 pinned the *header* ring's neutral `.12` track; the §I card's is a
    /// touch fainter. The card must carry its own value without moving the ring.
    @Test
    func cardDialTrackIsFainterThanTheHeaderRingsPinnedTrack() throws {
        #expect(PouredUsageMetrics.meterDialTrackOpacity == 0.1)
        // The shared ring's default — what the §C header keeps getting.
        #expect(PouredUsageRing(fraction: 0.5, color: .red).trackOpacity == 0.12)

        let card = try Self.source(Self.meterCardSource)
        #expect(card.contains("trackOpacity: PouredUsageMetrics.meterDialTrackOpacity"))
        // The header ring never passes a track — it stays on the ruled default.
        let summary = try Self.source(Self.usageSummarySource)
        #expect(!summary.contains("trackOpacity: PouredUsageMetrics"))
    }

    // MARK: - §I motion (none — `:1455-1483`)

    /// §I renders no animation at all, and the §C header rings carry none either,
    /// so the 0.8s critical breathe is gone from the shared ring. A returning
    /// `repeatForever` here is the pulse coming back.
    @Test
    func usageRingCarriesNoDangerGlowAnimation() throws {
        let summary = try Self.source(Self.usageSummarySource)
        #expect(!summary.contains("glowPulse"))
        #expect(!summary.contains("repeatForever"))
        #expect(!summary.contains("isDanger"))
    }

    // MARK: - §I wrap composition (`:469-470`)

    /// `.meters{gap:22; flex-wrap:wrap}` over `.meter{flex:1 1 200px}` in the
    /// board's 484pt content box (520 − 18 − 18) fits two meters, not three.
    @Test
    func boardWidthCardWrapsItsThreeMetersTwoPlusOne() {
        let boardContentWidth: CGFloat = 520 - 18 - 18
        #expect(PouredMeterFlow.columns(forWidth: boardContentWidth) == 2)
        #expect(PouredMeterFlow.rowCounts(count: 3, width: boardContentWidth) == [2, 1])
        // Flex-grow: the row's two meters share the width, gap paid once.
        #expect(PouredMeterFlow.itemWidth(forWidth: boardContentWidth, columns: 2) == 231)
    }

    /// The wrap has to keep behaving at the widths the card actually renders at
    /// (the Settings preview stage: 540/520pt panels less a 46/16pt side inset
    /// and the card's own 18 + 18 padding) and at a hypothetical three-up card.
    @Test
    func wrapDegradesToOneColumnWhenTheCardIsTooNarrowForTwoMeters() {
        // Notch profile: 540 − 46 − 46 − 36 = 412 ⇒ one meter per row.
        #expect(PouredMeterFlow.rowCounts(count: 3, width: 412) == [1, 1, 1])
        // Top-bar profile: 520 − 16 − 16 − 36 = 452 ⇒ the board's 2 + 1.
        #expect(PouredMeterFlow.rowCounts(count: 3, width: 452) == [2, 1])
        // Three 200pt meters plus two 22pt gaps.
        #expect(PouredMeterFlow.columns(forWidth: 644) == 3)
        #expect(PouredMeterFlow.rowCounts(count: 3, width: 644) == [3])
        // Degenerate proposals still render every meter.
        #expect(PouredMeterFlow.columns(forWidth: 0) == 1)
        #expect(PouredMeterFlow.rowCounts(count: 0, width: 484).isEmpty)
    }

    // MARK: - §I fixture exactness (`:1477-1478`)

    @Test
    func codexWindowRendersTheBoardsTierLabelAndCountdown() throws {
        let providers = AppearancePreviewFixtures.usageProviders(now: Self.fixedNow)
        let codex = try #require(providers.first { $0.id == "codex" })
        let window = try #require(codex.windows.first)

        #expect("\(codex.title) · \(window.label)" == "Codex · 7d · Pro")
        #expect(window.roundedUsedPercentage == 92)
        #expect(window.remainingLabel(asOf: Self.fixedNow) == "18h 40m")
    }

    /// The two Claude windows are untouched by the I2 fixture correction.
    @Test
    func claudeWindowsKeepTheirBoardReadouts() throws {
        let providers = AppearancePreviewFixtures.usageProviders(now: Self.fixedNow)
        let claude = try #require(providers.first { $0.id == "claude" })
        #expect(claude.windows.map(\.label) == ["5h", "7d"])
        #expect(claude.windows.map(\.roundedUsedPercentage) == [34, 78])
        #expect(claude.windows.compactMap { $0.remainingLabel(asOf: Self.fixedNow) } == ["2h 10m", "3d 4h"])
    }

    // MARK: - §I′ pill chip (`:1502-1505`)

    /// The readout is a `.chip` box carrying the band's own `.16` fill, and the
    /// dial's track is the tint at `.3` — not neutral paper.
    @Test
    func usageChipTakesTheBoardsTintedCapsuleAndTrack() {
        #expect(PouredPillMotion.RightSlot.usageChipFillOpacity == 0.16)
        #expect(PouredPillMotion.RightSlot.usageChipCornerRadius == 6)
        #expect(PouredPillMotion.RightSlot.usageChipHPadding == 7)
        #expect(PouredPillMotion.RightSlot.usageChipVPadding == 2)
        #expect(PouredPillMotion.RightSlot.usageDialTrackOpacity == 0.3)
    }

    /// `r15 / stroke-width 6` on a `viewBox 42` rendered at 12px: the stroke is
    /// a fifth of the path diameter, and path + stroke is the full 12pt of ink.
    @Test
    func chipDialKeepsTheBoardsStrokeToDiameterRatio() {
        let diameter = PouredPillMotion.RightSlot.usageDialDiameter
        let lineWidth = PouredPillMotion.RightSlot.usageDialLineWidth
        #expect(diameter + lineWidth == 12)
        #expect(abs(lineWidth / diameter - 6.0 / 30.0) < 0.000_1)
    }

    /// The `>= 90` gate and the warn/fine tint path are untouched — only the
    /// critical readout takes the board's lifted `#f0a8a8` ink.
    @Test
    func onlyTheCriticalBandTakesTheLiftedChipInk() {
        #expect(PouredPillMotion.RightSlot.usageCriticalThreshold == 90)
        #expect(PouredPillMotion.RightSlot.usageWarnThreshold == 70)
        #expect(IslandRightSlotResolver.usageAlertThreshold == 90)
        #expect(PouredPalette.usageCriticalChipInk != PouredPalette.attention)
    }

    // MARK: - §J copy fork (`:1531-1533`)

    /// Poured reads its own keys; the shared `island.noTerminals` / `island.startAgent`
    /// pair stays exactly where the other themes read it.
    @Test
    func pouredEmptyStateReadsTheForkedKeysAndTheOtherThemesDoNot() throws {
        let poured = try Self.source(Self.emptyStateSource)
        #expect(poured.contains("lang.t(\"island.poured.empty.title\")"))
        #expect(poured.contains("lang.t(\"island.poured.empty.subtitle\")"))
        #expect(!poured.contains("lang.t(\"island.noTerminals\")"))
        #expect(!poured.contains("lang.t(\"island.startAgent\")"))

        // Classic still reads the shared pair; Halo keeps its own §J copy. Neither
        // may pick up Poured's fork.
        let classic = try Self.source("Sources/OpenIslandApp/Views/Island/IslandEmptyState.swift")
        #expect(classic.contains("lang.t(\"island.noTerminals\")"))
        #expect(classic.contains("lang.t(\"island.startAgent\")"))
        for shared in [
            "Sources/OpenIslandApp/Views/Island/IslandEmptyState.swift",
            "Sources/OpenIslandApp/Views/Island/HaloEmptyState.swift",
            "Sources/OpenIslandApp/Views/Island/FlightDeckEmptyState.swift",
        ] {
            let text = try Self.source(shared)
            #expect(!text.contains("island.poured.empty."), "\(shared) picked up Poured's fork")
        }
    }

    /// Board-verbatim in English, present (and translated) in both Chinese
    /// catalogs — a key missing from one catalog renders as the raw key there.
    @Test
    func emptyCopyIsBoardVerbatimInEveryCatalog() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/OpenIslandApp/Resources")

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let catalog = try String(
                contentsOf: root.appending(path: "\(locale).lproj/Localizable.strings"),
                encoding: .utf8
            )
            for key in ["island.poured.empty.title", "island.poured.empty.subtitle"] {
                #expect(catalog.contains("\"\(key)\" ="), "\(locale) is missing \(key)")
            }
            // The shared keys survive for every other theme.
            #expect(catalog.contains("\"island.noTerminals\" ="))
            #expect(catalog.contains("\"island.startAgent\" ="))
        }

        let english = try String(
            contentsOf: root.appending(path: "en.lproj/Localizable.strings"),
            encoding: .utf8
        )
        #expect(english.contains("\"island.poured.empty.title\" = \"All quiet\";"))
        #expect(english.contains(
            "\"island.poured.empty.subtitle\" = \"No active agents. Open Island is watching your terminals \u{2014} the next permission, question, or finished run will surface here.\";"
        ))
    }

    // MARK: - §J glyph proportions (`:1529-1530`)

    /// An 18px render of a `viewBox 24` mark: `circle r3`, `stroke-width 1.8`,
    /// four 3-unit ticks whose centres sit 7.5 units out.
    @Test
    func monitorGlyphMatchesTheBoardSVGProportions() {
        #expect(PouredEmptyGlyphMetrics.discDiameter == 34)
        #expect(PouredEmptyGlyphMetrics.glyphBounds == 18)
        #expect(PouredEmptyGlyphMetrics.scale == 0.75)
        #expect(PouredEmptyGlyphMetrics.hubDiameter == 4.5)
        #expect(PouredEmptyGlyphMetrics.strokeWidth == 1.35)
        #expect(PouredEmptyGlyphMetrics.tickLength == 2.25)
        #expect(PouredEmptyGlyphMetrics.tickCenterOffset == 5.625)
        // The whole mark stays inside its 18pt SVG box.
        #expect(PouredEmptyGlyphMetrics.tickCenterOffset + PouredEmptyGlyphMetrics.tickLength / 2
            <= PouredEmptyGlyphMetrics.glyphBounds / 2)
        // …and the ticks never touch the hub.
        #expect(PouredEmptyGlyphMetrics.tickCenterOffset - PouredEmptyGlyphMetrics.tickLength / 2
            > PouredEmptyGlyphMetrics.hubDiameter / 2)
    }

    /// The breathing hold under Reduce Motion is unchanged by the re-proportioning.
    @Test
    func monitorGlyphKeepsItsReduceMotionHold() throws {
        let poured = try Self.source(Self.emptyStateSource)
        #expect(poured.contains("guard !reduceMotion else { return }"))
        #expect(poured.contains("let active = reduceMotion ? true : breathe"))
    }

    // MARK: - §J determinism seam (J1 capture)

    /// The live list depends on what the capturing machine has installed, so the
    /// board's exact three are pinned by the scenario — and only by that one.
    @Test
    func emptyStateScenarioPinsTheBoardsInstalledAgents() {
        #expect(IslandDebugScenario.emptyState.snapshot().installedAgentNames == ["Claude", "Codex", "Gemini"])
        for scenario in IslandDebugScenario.allCases where scenario != .emptyState {
            #expect(
                scenario.snapshot().installedAgentNames == nil,
                "\(scenario.rawValue) unexpectedly pins installed agents"
            )
        }
    }
}

/// The `AppModel` half of the J1 seam: the snapshot's pin has to reach the value
/// `IslandPanelView` hands the empty state.
@MainActor
struct PouredSlice6EmptyStateInjectionTests {

    @Test
    func loadingTheEmptyStateScenarioPinsTheInstalledAgentNames() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.emptyState.snapshot())
        #expect(model.installedAgentDisplayNames == ["Claude", "Codex", "Gemini"])
    }

    /// A scenario that pins nothing leaves the live derivation in place — the
    /// `debugUsageProvidersOverride` precedent, so production is untouched.
    @Test
    func aScenarioWithoutThePinClearsTheOverride() {
        let model = AppModel()
        model.loadDebugSnapshot(IslandDebugScenario.emptyState.snapshot())
        model.loadDebugSnapshot(IslandDebugScenario.sessionList.snapshot())
        #expect(model.debugInstalledAgentNamesOverride == nil)
    }
}
