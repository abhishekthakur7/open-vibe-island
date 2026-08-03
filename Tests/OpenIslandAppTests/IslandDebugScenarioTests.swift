import Testing
@testable import OpenIslandApp

struct IslandDebugScenarioTests {
    /// The complete set of scenarios that force the row expansion seam
    /// (`\.islandRowExpandedByDefault`) open. Every other scenario must leave it
    /// alone — most of them exist to document a *collapsed* row.
    ///
    /// - `subagentsExpanded` (overlay remediation Phase 1 item 1.7 · P1.a):
    ///   Flight Deck's / Halo's §D/§G expanded body, paired with
    ///   `subagentsCard`, which keeps documenting the same row collapsed.
    /// - `pouredSessionDetail` (Poured parity Slice 5 · `D1-detail`): the board's
    ///   §D frame. Poured's expansion gate
    ///   (`PouredSessionRow.PouredRowExpansion.resolved`) opens a detail body
    ///   only for `expandedByDefault`, an explicit chevron / `Answer` tap, or an
    ///   actionable row in *notification* presentation — a quiet `.running` row
    ///   in the list is collapsed by construction (PI-C-006), which is exactly
    ///   the state §D expands *from*, so the seam is the only non-interactive
    ///   way to reach it.
    /// - `completedSuccess` (Poured parity Slice 6 · `H1-completed`): the board's
    ///   §H hero. A completed row in a click-opened list is collapsed by
    ///   construction (PI-C-006) exactly like §D's running row, so the seam —
    ///   paired with the surface's `actionableSessionID`, which
    ///   `shouldShowEmbeddedDetailBody` also requires — is the only
    ///   non-interactive way to reach the completion card.
    private static let expansionForcingScenarios: Set<IslandDebugScenario> = [
        .subagentsExpanded,
        .pouredSessionDetail,
        .completedSuccess,
    ]

    @Test
    func onlyTheDocumentedScenariosForceRowExpansion() {
        for scenario in IslandDebugScenario.allCases {
            let forces = scenario.snapshot().forcesRowExpansion
            if Self.expansionForcingScenarios.contains(scenario) {
                #expect(forces, "\(scenario.rawValue) should force row expansion")
            } else {
                #expect(!forces, "\(scenario.rawValue) unexpectedly forces row expansion")
            }
        }

        // The collapsed counterpart stays collapsed — the pairing is the point.
        #expect(!IslandDebugScenario.subagentsCard.snapshot().forcesRowExpansion)
    }

    /// Poured parity Slice 5: the board draws §D / §F′ / §F″ as a standalone
    /// panel holding exactly one row, so these three scenarios must not fan out
    /// into the shared multi-row list the notification scenarios use.
    @Test
    func pouredHeroScenariosRenderExactlyTheirOwnSession() {
        let cases: [(IslandDebugScenario, String)] = [
            (.pouredSessionDetail, "fixture-poured-d1-detail"),
            (.pouredMultiSelectQuestion, "fixture-poured-f3-multi-select"),
            (.pouredCompactQuestion, "fixture-poured-f4-compact"),
        ]

        for (scenario, expectedID) in cases {
            let snapshot = scenario.snapshot()
            #expect(snapshot.sessions.map(\.id) == [expectedID], "\(scenario.rawValue) session set")
            #expect(snapshot.selectedSessionID == expectedID, "\(scenario.rawValue) selection")
            #expect(snapshot.notchStatus == .opened)
        }
    }
}
