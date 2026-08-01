import Testing
@testable import OpenIslandApp

struct IslandDebugScenarioTests {
    /// Overlay remediation Phase 1 item 1.7 (P1.a): `subagentsExpanded` is the
    /// only scenario reachable from `IslandDebugScenario` that forces the row
    /// expansion seam (`\.islandRowExpandedByDefault`) open; `subagentsCard`
    /// must keep documenting the collapsed row it always has.
    @Test
    func subagentsExpandedForcesRowExpansionWhileSubagentsCardStaysCollapsed() {
        #expect(IslandDebugScenario.subagentsExpanded.snapshot().forcesRowExpansion)
        #expect(!IslandDebugScenario.subagentsCard.snapshot().forcesRowExpansion)

        for scenario in IslandDebugScenario.allCases where scenario != .subagentsExpanded {
            #expect(
                !scenario.snapshot().forcesRowExpansion,
                "\(scenario.rawValue) unexpectedly forces row expansion"
            )
        }
    }
}
