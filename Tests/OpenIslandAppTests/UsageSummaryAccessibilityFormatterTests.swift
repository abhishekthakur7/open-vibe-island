import Foundation
import Testing
@testable import OpenIslandApp

struct UsageSummaryAccessibilityFormatterTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test
    func englishFixtureDetailsIncludeLocalizedResetSemantics() {
        let lang = language(.en)

        #expect(
            summary(
                provider: "Claude",
                windowID: "claude-5h",
                label: "5h",
                percentage: 34,
                remaining: 7_740,
                lang: lang
            ) == "Claude 5h 34%, resets in 2h 9m"
        )
        #expect(
            summary(
                provider: "Claude",
                windowID: "claude-7d",
                label: "7d",
                percentage: 78,
                remaining: 270_000,
                lang: lang
            ) == "Claude 7d 78%, resets in 3d 3h"
        )
        #expect(
            summary(
                provider: "Codex",
                windowID: "codex-7d",
                label: "7d",
                percentage: 92,
                remaining: 68_340,
                lang: lang
            ) == "Codex 7d 92%, resets in 18h 59m"
        )
    }

    @Test
    func resetPhraseLocalizesInEverySupportedLanguage() {
        let expected: [LanguageManager.AppLanguage: String] = [
            .en: "Claude 5h 34%, resets in 2h 9m",
            .zhHans: "Claude 5h 34%, 2h 9m 后重置",
            .zhHant: "Claude 5h 34%, 2h 9m 後重置",
        ]

        for (appLanguage, expectedSummary) in expected {
            #expect(
                summary(
                    provider: "Claude",
                    windowID: "claude-5h",
                    label: "5h",
                    percentage: 34,
                    remaining: 7_740,
                    lang: language(appLanguage)
                ) == expectedSummary
            )
        }
    }

    @Test
    func everyUsageThemeRoutesHelpAndGroupedLabelThroughSharedFormatter() throws {
        let islandDirectory = repositoryRoot()
            .appendingPathComponent("Sources/OpenIslandApp/Views/Island")
        let files = [
            "IslandUsageSummary.swift",
            "PouredUsageSummary.swift",
            "HaloUsageSummary.swift",
            "FlightDeckUsageSummary.swift",
        ]

        for file in files {
            let source = try String(
                contentsOf: islandDirectory.appendingPathComponent(file),
                encoding: .utf8
            )
            #expect(
                source.contains("UsageSummaryAccessibilityFormatter.summary("),
                "\(file) must use the shared usage accessibility formatter"
            )
            #expect(
                source.contains(".help(summaryText)"),
                "\(file) must reuse the shared summary for help"
            )
            #expect(
                source.contains(".accessibilityLabel(summaryText)"),
                "\(file) must reuse the shared summary for its grouped VoiceOver stop"
            )
        }
    }

    private func summary(
        provider title: String,
        windowID: String,
        label: String,
        percentage: Double,
        remaining: TimeInterval?,
        lang: LanguageManager
    ) -> String {
        UsageSummaryAccessibilityFormatter.summary(
            for: provider(
                title: title,
                windows: [
                    window(
                        id: windowID,
                        label: label,
                        percentage: percentage,
                        remaining: remaining
                    ),
                ]
            ),
            usesShortTitle: false,
            asOf: now,
            lang: lang
        )
    }

    private func provider(
        title: String,
        windows: [UsageWindowPresentation]
    ) -> UsageProviderPresentation {
        UsageProviderPresentation(
            id: title.lowercased(),
            title: title,
            windows: windows
        )
    }

    private func window(
        id: String,
        label: String,
        percentage: Double,
        remaining: TimeInterval?
    ) -> UsageWindowPresentation {
        UsageWindowPresentation(
            id: id,
            label: label,
            usedPercentage: percentage,
            resetsAt: remaining.map(now.addingTimeInterval)
        )
    }

    private func language(_ appLanguage: LanguageManager.AppLanguage) -> LanguageManager {
        let manager = LanguageManager()
        manager.language = appLanguage
        return manager
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
