import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// AB-326 stage 1: conformance preview fixtures + debug scenarios.
struct AppearancePreviewFixturesTests {
    private static let now = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - Determinism

    @Test
    func fixturesAreDeterministicForTheSameNow() {
        let lang = LanguageManager()

        #expect(AppearancePreviewFixtures.sessions(now: Self.now, lang: lang)
            == AppearancePreviewFixtures.sessions(now: Self.now, lang: lang))
        #expect(AppearancePreviewFixtures.completedInterrupted(now: Self.now)
            == AppearancePreviewFixtures.completedInterrupted(now: Self.now))
        #expect(AppearancePreviewFixtures.completedFailed(now: Self.now)
            == AppearancePreviewFixtures.completedFailed(now: Self.now))
        #expect(AppearancePreviewFixtures.duplicateWorkspaceTrio(now: Self.now)
            == AppearancePreviewFixtures.duplicateWorkspaceTrio(now: Self.now))
        #expect(AppearancePreviewFixtures.permissionCommand(now: Self.now)
            == AppearancePreviewFixtures.permissionCommand(now: Self.now))
        #expect(AppearancePreviewFixtures.permissionDiff(now: Self.now)
            == AppearancePreviewFixtures.permissionDiff(now: Self.now))
        #expect(AppearancePreviewFixtures.codexTerminalApproval(now: Self.now)
            == AppearancePreviewFixtures.codexTerminalApproval(now: Self.now))
        #expect(AppearancePreviewFixtures.questionMulti(now: Self.now)
            == AppearancePreviewFixtures.questionMulti(now: Self.now))
        #expect(AppearancePreviewFixtures.subagentsAndTasks(now: Self.now)
            == AppearancePreviewFixtures.subagentsAndTasks(now: Self.now))
        #expect(AppearancePreviewFixtures.pouredSessionDetail(now: Self.now)
            == AppearancePreviewFixtures.pouredSessionDetail(now: Self.now))
        #expect(AppearancePreviewFixtures.pouredMultiSelectQuestion(now: Self.now)
            == AppearancePreviewFixtures.pouredMultiSelectQuestion(now: Self.now))
        #expect(AppearancePreviewFixtures.pouredCompactQuestion(now: Self.now)
            == AppearancePreviewFixtures.pouredCompactQuestion(now: Self.now))
    }

    // MARK: - Poured §D detail (Slice 5 · D1-detail)

    /// The three detail blocks §D draws that no earlier Poured fixture could
    /// reach — `PouredSessionRow` reads each through a different accessor, and
    /// each renders *nothing* when its field is absent, so a missing one is a
    /// silently empty board frame rather than a test failure. Pinned here at the
    /// data layer, where it is cheap and unambiguous.
    @Test
    func pouredDetailFixtureCarriesEveryFieldTheDetailBodyRenders() throws {
        let session = AppearancePreviewFixtures.pouredSessionDetail(now: Self.now)

        // `.mcell` Directory ← `jumpTarget.workingDirectory`. Written absolute so
        // `directoryDisplayText`'s own home-abbreviation produces the board's
        // `~/…/open-vibe-island`; a literal `~` would survive it unabbreviated.
        let directory = try #require(session.jumpTarget?.workingDirectory)
        #expect(directory.hasPrefix("/"))
        #expect(directory.hasSuffix("/open-vibe-island"))

        // `.assistant` prose ← `lastAssistantMessageText`, carrying the board's
        // emphasis, inline code and two-item list as Markdown.
        let message = try #require(session.lastAssistantMessageText)
        #expect(message.contains("**AppModel.start()**"))
        #expect(message.contains("`BridgeServer`"))
        #expect(message.contains("- Socket bind → registry restore → reconcile"))
        #expect(message.contains("- Added a guard for the detached-pane case"))

        // `Transcript` ghost ← `trackingTranscriptPath`.
        #expect(session.trackingTranscriptPath?.hasSuffix(".jsonl") == true)

        // The board's own §D identity: running Claude, `feat/theme-poured`,
        // `acceptEdits`, and the two-clock split behind `live 1m 42s`.
        #expect(session.phase == .running)
        #expect(session.claudeMetadata?.worktreeBranch == "feat/theme-poured")
        #expect(session.claudeMetadata?.permissionMode == .acceptEdits)
        #expect(session.firstSeenAt == Self.now.addingTimeInterval(-102))
    }

    // MARK: - Poured §F′ / §F″ questions (Slice 5 · F3 / F4)

    /// `01-poured-island.html:1210-1240` (F′) and `:1245-1260` (F″), verbatim.
    /// Copy is the parity contract here — a paraphrase is a silent reference
    /// divergence — so the strings are asserted literally.
    @Test
    func pouredQuestionFixturesCarryTheBoardsCopyVerbatim() throws {
        let multiSelect = AppearancePreviewFixtures.pouredMultiSelectQuestion(now: Self.now)
        let f3 = try #require(multiSelect.questionPrompt?.questions.first)
        #expect(multiSelect.questionPrompt?.questions.count == 1)
        #expect(f3.header == "Targets")
        #expect(f3.question == "Which agents should ship in v0.6?")
        #expect(f3.multiSelect)
        #expect(f3.options.map(\.label) == ["OpenCode", "Kimi CLI", "Qwen Code"])
        // F′ has no `.od` and no freeform `Other` anywhere.
        #expect(f3.options.allSatisfy { $0.description.isEmpty })
        #expect(f3.options.allSatisfy { !$0.allowsFreeform })
        #expect(Set(f3.options.map(\.id)).count == 3)

        let compact = AppearancePreviewFixtures.pouredCompactQuestion(now: Self.now)
        let f4 = try #require(compact.questionPrompt?.questions.first)
        #expect(compact.questionPrompt?.questions.count == 1)
        #expect(f4.header == "Deploy")
        #expect(f4.question == "Proceed to production?")
        #expect(!f4.multiSelect)
        #expect(f4.options.map(\.label) == ["Yes, deploy", "Hold"])
        #expect(f4.options.allSatisfy { $0.description.isEmpty })
        #expect(Set(f4.options.map(\.id)).count == 2)

        // Both are question surfaces, so the §F hero is what renders them.
        #expect(multiSelect.phase == .waitingForAnswer)
        #expect(compact.phase == .waitingForAnswer)
    }

    // MARK: - Duplicate-workspace trio

    @Test
    func trioCollidesOnWorkspaceAndDisambiguatesByBranchThenRecency() {
        let trio = AppearancePreviewFixtures.duplicateWorkspaceTrio(now: Self.now)
        #expect(trio.count == 3)

        // They all collide on the exact string a row headline leads with.
        #expect(Set(trio.map(\.spotlightDisplayName)) == ["the-automator"])

        let disambiguators = SessionDisambiguation.disambiguators(for: trio, now: Self.now)
        #expect(disambiguators.count == 3)
        #expect(disambiguators[trio[0].id] == "feat/bridge-auth")
        #expect(disambiguators[trio[1].id] == "main")
        // Codex carries no branch (branch is Claude-only ground truth) → recency.
        #expect(disambiguators[trio[2].id]?.contains("ago") == true)

        // The middle member fans out across three subagents.
        #expect(trio[1].claudeMetadata?.activeSubagents.count == 3)
    }

    // MARK: - Question: multi-question conformance set

    @Test
    func conformanceQuestionOptionsHaveDistinctIDs() {
        // Phase 1 remediation item 1.4: `stableID` used to truncate every seed
        // to its first 16 UTF-8 bytes with no hashing, so every
        // "conformance-auth-…" seed (and every "conformance-scope-…" seed)
        // collided on that shared 16-character prefix — every option in both
        // groups rendered as option[0]. `options.count` alone (asserted
        // above) can't catch this, since a list of duplicate ids still has
        // the right *length*; this pins distinctness directly.
        //
        // Slice 5 · F3: the Auth question grew a fourth option — the board's
        // `.opt-other` freeform escape hatch — so both groups now carry four.
        let questions = AppearancePreviewFixtures.conformanceQuestions()
        #expect(Set(questions[0].options.map(\.id)).count == 4)
        #expect(Set(questions[1].options.map(\.id)).count == 4)
        // And no id collides *across* the two groups either.
        #expect(Set(questions.flatMap { $0.options.map(\.id) }).count == 8)
    }

    // MARK: - Preview scenario mapping (stage 2)

    @Test
    func scenarioContentMapsEachScenarioToItsFixtureSet() {
        let now = Self.now
        let lang = LanguageManager()

        func content(_ scenario: AppearancePreviewScenario) -> AppearancePreviewScenarioContent {
            AppearancePreviewFixtures.scenarioContent(scenario, now: now, lang: lang)
        }

        // list: the baseline five, no hero, no meters.
        let list = content(.list)
        #expect(list.sessions == AppearancePreviewFixtures.sessions(now: now, lang: lang))
        #expect(list.actionableSessionID == nil)
        #expect(list.usageProviders == nil)

        // Each single-card scenario surfaces its fixture as the actionable hero.
        let cardCases: [(AppearancePreviewScenario, AgentSession)] = [
            (.permissionCommand, AppearancePreviewFixtures.permissionCommand(now: now)),
            (.permissionDiff, AppearancePreviewFixtures.permissionDiff(now: now)),
            (.codexApproval, AppearancePreviewFixtures.codexTerminalApproval(now: now)),
            (.questionMulti, AppearancePreviewFixtures.questionMulti(now: now)),
            (.subagents, AppearancePreviewFixtures.subagentsAndTasks(now: now)),
        ]
        for (scenario, fixture) in cardCases {
            let resolved = content(scenario)
            #expect(resolved.sessions == [fixture], "\(scenario.rawValue) fixture mismatch")
            #expect(resolved.actionableSessionID == fixture.id, "\(scenario.rawValue) missing hero id")
            #expect(resolved.usageProviders == nil)
        }

        // completed variants: both outcomes, interrupted is the expanded hero.
        let completed = content(.completedVariants)
        #expect(completed.sessions.map(\.id) == [
            AppearancePreviewFixtures.completedInterrupted(now: now).id,
            AppearancePreviewFixtures.completedFailed(now: now).id,
        ])
        #expect(completed.actionableSessionID == AppearancePreviewFixtures.completedInterrupted(now: now).id)
        #expect(completed.usageProviders == nil)

        // duplicates: the whole trio, no single hero.
        let duplicates = content(.duplicates)
        #expect(duplicates.sessions == AppearancePreviewFixtures.duplicateWorkspaceTrio(now: now))
        #expect(duplicates.actionableSessionID == nil)
        #expect(duplicates.usageProviders == nil)

        // meters: baseline sessions + the fixture usage providers (34/78/92).
        let meters = content(.meters)
        #expect(meters.sessions == AppearancePreviewFixtures.sessions(now: now, lang: lang))
        #expect(meters.actionableSessionID == nil)
        #expect(meters.usageProviders?.map(\.id) == ["claude", "codex"])
        #expect(meters.usageProviders?[0].peakUsagePercentage == 78)
        #expect(meters.usageProviders?[1].peakUsagePercentage == 92)

        // empty: no sessions, no hero, no meters.
        let empty = content(.empty)
        #expect(empty.sessions.isEmpty)
        #expect(empty.actionableSessionID == nil)
        #expect(empty.usageProviders == nil)
    }
}

/// AB-326: the new debug scenarios must stay demo-only and self-consistent
/// while leaving the pre-existing scenarios untouched.
struct IslandDebugScenarioConformanceTests {
    @Test
    func onlyUsageScenariosCarryUsageProviders() {
        // `closedCritical` needs the ≥90% providers so the I′ filament wins the
        // right-slot resolver ladder — see its fixture comment. PI-I-001:
        // `pouredGroupedSix` joins them because the board's §C header renders
        // two usage rings, one per wing (`01-poured-island.html:784-790`).
        for scenario in IslandDebugScenario.allCases {
            let snapshot = scenario.snapshot()
            if scenario == .usageMeters || scenario == .closedCritical || scenario == .pouredGroupedSix {
                #expect(snapshot.usageProviders?.isEmpty == false)
            } else {
                #expect(snapshot.usageProviders == nil, "\(scenario.rawValue) unexpectedly set usage providers")
            }
        }
    }
}
