import Foundation
import Testing
@testable import OpenIslandApp

@Suite(.serialized)
struct NestedWorkAccessibilityTests {
    private let rollup = PouredTaskRollup(
        statuses: [.completed, .completed, .inProgress, .pending, .pending]
    )

    @Test
    func formatterUsesManualEnglishSingularAndPluralForms() {
        let originalLanguage = savedLanguagePreference()
        defer { restoreLanguagePreference(originalLanguage) }
        let lang = LanguageManager()
        lang.language = .en

        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 1,
            completedTaskCount: 1,
            totalTaskCount: 1,
            isExpanded: false,
            lang: lang
        ) == "1 subagent, 1 of 1 task completed")

        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 3,
            completedTaskCount: rollup.done,
            totalTaskCount: rollup.total,
            isExpanded: false,
            lang: lang
        ) == "3 subagents, 2 of 5 tasks completed")
    }

    @Test
    func formatterOmitsExpandedAndEmptyNestedWork() {
        let originalLanguage = savedLanguagePreference()
        defer { restoreLanguagePreference(originalLanguage) }
        let lang = LanguageManager()
        lang.language = .en

        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 3,
            completedTaskCount: 0,
            totalTaskCount: 0,
            isExpanded: false,
            lang: lang
        ) == "3 subagents")
        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 0,
            completedTaskCount: rollup.done,
            totalTaskCount: rollup.total,
            isExpanded: false,
            lang: lang
        ) == "2 of 5 tasks completed")
        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 3,
            completedTaskCount: rollup.done,
            totalTaskCount: rollup.total,
            isExpanded: true,
            lang: lang
        ) == nil)
        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 0,
            completedTaskCount: 0,
            totalTaskCount: 0,
            isExpanded: false,
            lang: lang
        ) == nil)
    }

    @Test
    func formatterLocalizesComponentsAndCombinedSeparator() {
        let originalLanguage = savedLanguagePreference()
        defer { restoreLanguagePreference(originalLanguage) }
        let expectations: [LanguageManager.AppLanguage: String] = [
            .en: "3 subagents, 2 of 5 tasks completed",
            .zhHans: "3 个子代理，5 个任务中已完成 2 个",
            .zhHant: "3 個子代理，5 個任務中已完成 2 個",
        ]

        for (language, expected) in expectations {
            let lang = LanguageManager()
            lang.language = language
            #expect(NestedWorkAccessibility.value(
                activeSubagentCount: 3,
                completedTaskCount: rollup.done,
                totalTaskCount: rollup.total,
                isExpanded: false,
                lang: lang
            ) == expected)
        }
    }

    @Test
    func pouredScenariosExposeNestedWorkOnlyWhileCollapsed() {
        let collapsed = IslandDebugScenario.subagentsCard.snapshot()
        let expanded = IslandDebugScenario.subagentsExpanded.snapshot()

        assertScenarioSemantics(
            collapsedIsExpanded: PouredRowExpansion.resolved(
                isInteractive: true,
                expandedByDefault: collapsed.forcesRowExpansion,
                isActionable: false,
                detailOverride: nil
            ),
            expandedIsExpanded: PouredRowExpansion.resolved(
                isInteractive: true,
                expandedByDefault: expanded.forcesRowExpansion,
                isActionable: false,
                detailOverride: nil
            )
        )
    }

    @Test
    func flightDeckScenariosExposeNestedWorkOnlyWhileCollapsed() {
        let collapsed = IslandDebugScenario.subagentsCard.snapshot()
        let expanded = IslandDebugScenario.subagentsExpanded.snapshot()

        // Flight Deck's ordinary interactive row resolves directly from the
        // debug seam when there is no local override and it is not actionable.
        assertScenarioSemantics(
            collapsedIsExpanded: collapsed.forcesRowExpansion,
            expandedIsExpanded: expanded.forcesRowExpansion
        )
    }

    @Test
    func haloScenariosExposeNestedWorkOnlyWhileCollapsed() {
        let collapsed = IslandDebugScenario.subagentsCard.snapshot()
        let expanded = IslandDebugScenario.subagentsExpanded.snapshot()

        // Halo uses the same ordinary-row defaults as Flight Deck.
        assertScenarioSemantics(
            collapsedIsExpanded: collapsed.forcesRowExpansion,
            expandedIsExpanded: expanded.forcesRowExpansion
        )
    }

    private func assertScenarioSemantics(
        collapsedIsExpanded: Bool,
        expandedIsExpanded: Bool
    ) {
        let originalLanguage = savedLanguagePreference()
        defer { restoreLanguagePreference(originalLanguage) }
        let lang = LanguageManager()
        lang.language = .en

        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 3,
            completedTaskCount: rollup.done,
            totalTaskCount: rollup.total,
            isExpanded: collapsedIsExpanded,
            lang: lang
        ) == "3 subagents, 2 of 5 tasks completed")
        #expect(NestedWorkAccessibility.value(
            activeSubagentCount: 3,
            completedTaskCount: rollup.done,
            totalTaskCount: rollup.total,
            isExpanded: expandedIsExpanded,
            lang: lang
        ) == nil)
    }

    private func savedLanguagePreference() -> String? {
        UserDefaults.standard.string(forKey: "appLanguage")
    }

    private func restoreLanguagePreference(_ language: String?) {
        if let language {
            UserDefaults.standard.set(language, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }
    }
}
