import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-343 (T24 · Halo Part 1): pure-format pins for the Halo usage surfaces —
/// the opened-header light-filament summary (§5C) and the §I full meter card
/// (§5I). These lock the threshold cut-offs (shared with every theme), the
/// filament colours (Halo's own `HaloEdge` usage table), the band words, and the
/// filament geometry constants so the header / meter can't drift from the mockup.
///
/// `@MainActor` because the SwiftUI-touching helpers are main-actor.
@MainActor
struct HaloUsageTests {

    // MARK: - Threshold bands (the single shared usage rule)

    /// The band a usage percentage falls into rides the **exact** app-wide
    /// `usageColor` cut-offs (`IslandUsageSummary`: `>= 90` critical, `70..<90`
    /// warn, else fine) — the same shipped cutoffs `AnnualUsageVerdict` /
    /// `PouredUsageThreshold` pin. Pinned at both boundaries plus the 34 / 78 / 94
    /// §I fixture points.
    @Test
    func usageThresholdBandsMatchTheSharedUsageCutoffs() {
        #expect(HaloUsageThreshold.threshold(for: 99) == .critical)
        #expect(HaloUsageThreshold.threshold(for: 94) == .critical)     // §I fixture
        #expect(HaloUsageThreshold.threshold(for: 90) == .critical)
        #expect(HaloUsageThreshold.threshold(for: 89.9) == .warn)
        #expect(HaloUsageThreshold.threshold(for: 78) == .warn)         // §I fixture
        #expect(HaloUsageThreshold.threshold(for: 70) == .warn)
        #expect(HaloUsageThreshold.threshold(for: 69.9) == .fine)
        #expect(HaloUsageThreshold.threshold(for: 34) == .fine)         // §I fixture
        #expect(HaloUsageThreshold.threshold(for: 0) == .fine)
    }

    /// Only the `>= 90` critical band pulses / is loud — the single filament
    /// allowed motion.
    @Test
    func onlyCriticalBandIsCritical() {
        #expect(HaloUsageThreshold.critical.isCritical)
        #expect(!HaloUsageThreshold.warn.isCritical)
        #expect(!HaloUsageThreshold.fine.isCritical)
        #expect(HaloUsageThreshold.threshold(for: 90).isCritical)
        #expect(!HaloUsageThreshold.threshold(for: 89.9).isCritical)
    }

    // MARK: - Filament colours (Halo's own usage table, pinned to SPEC hex)

    /// Each band lights its `HaloEdge` filament — the exact SPEC hex
    /// (`usageFine #5FE39A` `< 70`, `usageWarn #FFCF7A` `70…90`,
    /// `usageCrit #FF6B6B` `>= 90`). Pinned so the header filament and §I dial
    /// can't drift onto a different accent.
    @Test
    func usageThresholdColorsResolveToHaloEdgeFilaments() {
        #expect(HaloUsageThreshold.fine.filamentColor == HaloEdge.usageFine)
        #expect(HaloUsageThreshold.warn.filamentColor == HaloEdge.usageWarn)
        #expect(HaloUsageThreshold.critical.filamentColor == HaloEdge.usageCrit)

        // The exact SPEC hex, by 8-bit components (guards against a silent retint).
        #expect(HaloUsageThreshold.fine.filamentColor
            == Color(red: 0x5F / 255.0, green: 0xE3 / 255.0, blue: 0x9A / 255.0))
        #expect(HaloUsageThreshold.warn.filamentColor
            == Color(red: 0xFF / 255.0, green: 0xCF / 255.0, blue: 0x7A / 255.0))
        #expect(HaloUsageThreshold.critical.filamentColor
            == Color(red: 0xFF / 255.0, green: 0x6B / 255.0, blue: 0x6B / 255.0))

        // Resolved from a percentage at each boundary — the colour the header
        // filament and §I dial both paint.
        #expect(HaloUsageThreshold.threshold(for: 69.9).filamentColor == HaloEdge.usageFine)
        #expect(HaloUsageThreshold.threshold(for: 70).filamentColor == HaloEdge.usageWarn)
        #expect(HaloUsageThreshold.threshold(for: 89.9).filamentColor == HaloEdge.usageWarn)
        #expect(HaloUsageThreshold.threshold(for: 90).filamentColor == HaloEdge.usageCrit)
    }

    // MARK: - Band words (never colour-alone, §5I)

    /// Every band carries a distinct localization key so the §I meter states its
    /// band as a **word** (FINE / WARN / CRITICAL), never colour-alone.
    @Test
    func bandWordsMapToDistinctLocalizationKeys() {
        #expect(HaloUsageThreshold.fine.localizationKey == "island.halo.usage.fine")
        #expect(HaloUsageThreshold.warn.localizationKey == "island.halo.usage.warn")
        #expect(HaloUsageThreshold.critical.localizationKey == "island.halo.usage.critical")

        let keys = Set(HaloUsageThreshold.allCases.map(\.localizationKey))
        #expect(keys.count == HaloUsageThreshold.allCases.count)
    }

    /// The band-word keys resolve to non-empty English strings — the §I meter's
    /// word is never blank (would defeat the "never colour-alone" guarantee).
    @Test
    func bandWordsResolveToNonEmptyStrings() {
        let lang = LanguageManager(); lang.language = .en
        for band in HaloUsageThreshold.allCases {
            #expect(!lang.t(band.localizationKey).isEmpty)
        }
        #expect(!lang.t("island.halo.usage.metersTitle").isEmpty)
        // The resets-in template carries its placeholder through.
        #expect(lang.t("island.halo.usage.resetsIn", "2h 10m").contains("2h 10m"))
    }

    // MARK: - Filament geometry (pinned to the mockup arc)

    /// The filament geometry constants pin to the mockup: 30/22pt header (fitted
    /// per profile like Poured's ring), 52pt §I dial, and a 270° arc (`arcSpan
    /// 0.75`) rotated so its gap sits at the top (`rotate(135)`). The header
    /// filament grows on the notch profile and shrinks on the height-capped
    /// top-bar band.
    @Test
    func filamentMetricsPinToTheMockupArc() {
        #expect(HaloUsageMetrics.headerFilamentNotch == 30)
        #expect(HaloUsageMetrics.headerFilamentTopBar == 22)
        #expect(HaloUsageMetrics.headerFilamentTopBar < HaloUsageMetrics.headerFilamentNotch)
        #expect(HaloUsageMetrics.headerFilamentLineWidth == 2.2)
        #expect(HaloUsageMetrics.meterFilament == 52)
        #expect(HaloUsageMetrics.meterFilamentLineWidth == 3)
        #expect(HaloUsageMetrics.arcSpan == 0.75)
        #expect(HaloUsageMetrics.arcRotationDegrees == 135)
    }

    // MARK: - Header control geometry (§5C)

    /// The mute / settings / quit controls are 26pt circular buttons (mockup
    /// `.ctl`), pinned so they can't drift back to Annual's 24pt quiet glyphs.
    @Test
    func headerControlsAreTwentySixPointCircles() {
        #expect(HaloHeaderControls.headerControlButtonSize == 26)
    }

    // MARK: - Theme wiring (slots return Halo surfaces, not the interim delegate)

    /// The §I meter card slot returns a Halo surface when providers exist and nil
    /// when empty (matching every theme's `usageMeterCard` contract).
    @Test
    func usageMeterCardSlotIsNilOnlyWhenEmpty() {
        let theme = HaloTheme()
        let lang = LanguageManager(); lang.language = .en
        #expect(theme.usageMeterCard(providers: [], lang: lang) == nil)

        let provider = UsageProviderPresentation(
            id: "claude",
            title: "Claude",
            windows: [UsageWindowPresentation(id: "5h", label: "5h", usedPercentage: 34, resetsAt: nil)]
        )
        #expect(theme.usageMeterCard(providers: [provider], lang: lang) != nil)
    }
}
