import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// Poured parity Slice 6 · part A — §G glyph/copy conformance (PI-X-001/G1) and
/// the §H completion hero's board composition (PI-X-001/H1, R14).
///
/// Everything asserted here is a *pure* value the two surfaces read: the run
/// glyph's rendered sizes, the live-subagent rollup behind the expanded `.act`
/// suffix, the hero sub-line's composition, the hero badge's type override, and
/// the two new deterministic scenarios. Rendering itself stays the harness's job.
struct PouredSlice6Tests {

    /// One frozen clock for every fixture assertion below.
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - §G run glyph (G1 · `01-poured-island.html:1289`, `:1313`)

    /// The two §G sites the board draws the run glyph at, pinned to the board's
    /// own boxes. Both used to draw something else entirely — an SF
    /// `arrow.triangle.branch` in the nest header, a pulsing dot in the todo
    /// tick — so a regression here is a return to a different marker vocabulary.
    @Test
    func runGlyphAdoptsTheBoardsTwoNestedSizes() {
        #expect(PouredRunGlyphMetrics.nestHeaderHeight == 11)
        #expect(PouredRunGlyphMetrics.todoTickHeight == 9)
        // The todo tick has to fit inside the board's 14×14 `.tk` box.
        #expect(PouredRunGlyphMetrics.todoTickHeight < 14)
    }

    /// Unlike the board — which shrinks the box and leaves `.glyph i` at its
    /// literal metrics, overflowing every reduced instance (contradiction C-7) —
    /// native scales the bars with the box off one factor.
    @Test
    func runGlyphBarsScaleWithTheGlyphBox() {
        let full = PouredRunGlyphMetrics.barHeights(height: PouredRunGlyphMetrics.referenceHeight)
        #expect(full == [14, 14, 11])
        #expect(PouredRunGlyphMetrics.barWidth(height: PouredRunGlyphMetrics.referenceHeight) == 2.5)

        for height in [PouredRunGlyphMetrics.nestHeaderHeight, PouredRunGlyphMetrics.todoTickHeight] {
            let bars = PouredRunGlyphMetrics.barHeights(height: height)
            #expect(bars.count == 3)
            // No bar may exceed its own box — that is the whole point of scaling.
            #expect(bars.allSatisfy { $0 <= height + 0.001 }, "bars overflow the \(height)pt box")
            #expect(PouredRunGlyphMetrics.barWidth(height: height) < 2.5)
            // Proportions survive the scale: the third bar stays the short one.
            #expect(bars[0] == bars[1])
            #expect(bars[2] < bars[0])
        }
    }

    // MARK: - §G expanded activity suffix (G1 · `:1286`)

    private func subagent(id: String, summary: String? = nil) -> ClaudeSubagentInfo {
        ClaudeSubagentInfo(
            agentID: id,
            agentType: "Explore",
            summary: summary,
            taskDescription: "Map the theme token surface",
            startedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test
    func expandedRowCountsOnlyStillRunningSubagents() {
        let mixed = [
            subagent(id: "a"),
            subagent(id: "b", summary: "done"),
            subagent(id: "c"),
        ]
        #expect(PouredLiveSubagents.liveCount(mixed, isExpanded: true) == 2)
    }

    /// The compact row is untouched by G1: the fan-out is identity there and
    /// rides the disambiguator (R2/C4), so a collapsed row must produce no
    /// suffix at all — never a `· 0 subagents live` tail either.
    @Test
    func collapsedRowAndFinishedFanOutProduceNoSuffix() {
        let live = [subagent(id: "a"), subagent(id: "b"), subagent(id: "c")]
        #expect(PouredLiveSubagents.liveCount(live, isExpanded: false) == nil)
        #expect(PouredLiveSubagents.liveCount([], isExpanded: true) == nil)
        #expect(
            PouredLiveSubagents.liveCount(
                [subagent(id: "a", summary: "done"), subagent(id: "b", summary: "done")],
                isExpanded: true
            ) == nil
        )
    }

    /// Correction 2 (R5 exact-copy acceptance): the §G fixture is the board's
    /// own session, string for string (`01-poured-island.html:1281-1321`,
    /// `:1333-1372`) — workspace, branch, narration seam, the three subagent
    /// rows and the five todos. It used to be a native-flavoured paraphrase, so
    /// every §G capture read `open-vibe-island` / `Orchestrating` / theme-ticket
    /// task titles against a board that says none of those things.
    @Test
    func subagentsFixtureIsTheBoardsGSessionVerbatim() throws {
        let session = AppearancePreviewFixtures.subagentsAndTasks(now: Self.now)
        let claude = try #require(session.claudeMetadata)

        #expect(session.jumpTarget?.workspaceName == "the-automator")
        #expect(claude.worktreeBranch == "main")
        // Verb + object drive the row's `.act` and the closed pill's label:
        // `Refactoring hook installers` / `Refactoring · 3 agents`.
        let narrated = try #require(session.narratedActivityLine)
        #expect(narrated.verb == "Refactoring")
        #expect(narrated.object == "hook installers")

        #expect(claude.activeSubagents.map(\.agentType) == ["explore", "edit", "test"])
        #expect(claude.activeSubagents.map(\.taskDescription) == [
            "Map every ClaudeHooks call site",
            "Rewrite CodexHooks payload model",
            "Add BridgeCodec round-trip tests",
        ])
        #expect(claude.activeSubagents.map { Self.now.timeIntervalSince($0.startedAt ?? Self.now) } == [42, 75, 8])

        #expect(claude.activeTasks.map(\.title) == [
            "Extract shared hook installer",
            "Unify NDJSON envelope codec",
            "Rewrite per-agent payload models",
            "Wire fail-open fallback",
            "Update AGENTS.md matrix",
        ])
        let rollup = PouredTaskRollup(statuses: claude.activeTasks.map(\.status))
        #expect(rollup.done == 2)
        #expect(rollup.total == 5)
    }

    /// H1 correction 2: the board's sub-line is the literal `finished 12m ago`,
    /// and its footer the literal `43m` duration — both have to come off the
    /// fixture's own clock, not off a reading of "12m" as illustrative.
    @Test
    func completedSuccessFixtureFinishedTwelveMinutesAgoAfterAFortyThreeMinuteRun() {
        let session = AppearancePreviewFixtures.completedSuccess(now: Self.now)
        let sinceFinished = Self.now.timeIntervalSince(session.updatedAt)
        // Inside the "12m" bucket, and off a 60s boundary for capture
        // determinism.
        #expect(sinceFinished >= 12 * 60)
        #expect(sinceFinished < 13 * 60)
        #expect(session.updatedAt.timeIntervalSince(session.firstSeenAt) == 43 * 60)
    }

    /// I1/I2 correction 2: `UsageCountdownFormatter` floors, so an unpadded
    /// `now + 18h40m` renders `18h 40m` for exactly one instant and `18h 39m`
    /// forever after — which is what the Slice 6 captures recorded. The padded
    /// offsets must render the board's strings at load *and* a full minute later.
    @Test
    func usageFixtureCountdownsRenderTheBoardsStringsAcrossACaptureWindow() {
        let windows = AppearancePreviewFixtures.usageProviders(now: Self.now).flatMap(\.windows)
        let expected = ["2h 10m", "3d 4h", "18h 40m"]
        for offset in [0.0, 30.0, 58.0] {
            let asOf = Self.now.addingTimeInterval(offset)
            #expect(windows.map { $0.remainingLabel(asOf: asOf) } == expected, "drifted at +\(offset)s")
        }
    }

    /// The board's own §G fixture drives three live subagents, so the rendered
    /// suffix is `3 subagents live`.
    @Test
    func subagentsFixtureDrivesTheBoardsThreeLiveSubagents() {
        let session = AppearancePreviewFixtures.subagentsAndTasks(now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(
            PouredLiveSubagents.liveCount(session.claudeMetadata?.activeSubagents ?? [], isExpanded: true) == 3
        )
    }

    // MARK: - §H hero sub-line (H1 · `:1399`)

    @Test
    func heroSublineJoinsModelAndFinishedAgoWithTheBoardsMiddot() {
        #expect(
            PouredCompletionSubline.text(model: "Fable 5", finishedAgo: "finished 12m ago")
                == "Fable 5 \u{00B7} finished 12m ago"
        )
    }

    /// A session with no model metadata (Codex.app / MCP, and any agent that
    /// never reported one) drops the segment *and* the separator — the line must
    /// never render as a dangling `· finished 12m ago`.
    @Test
    func heroSublineDropsTheModelSegmentAndItsSeparatorWhenAbsent() {
        #expect(PouredCompletionSubline.text(model: nil, finishedAgo: "finished 2m ago") == "finished 2m ago")
        #expect(PouredCompletionSubline.text(model: "   ", finishedAgo: "finished 2m ago") == "finished 2m ago")
        #expect(PouredCompletionSubline.text(model: "Fable 5", finishedAgo: "") == "Fable 5")
    }

    /// The board's §H sub-line reads `Fable 5`, so the fixture behind the H1
    /// scenario has to carry a model the shared shortener resolves to it.
    @Test
    func completedSuccessFixtureCarriesTheBoardsModelString() {
        let session = AppearancePreviewFixtures.completedSuccess(now: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(session.displayModelName == "Fable 5")
    }

    // MARK: - §H badge override (`:1400`)

    /// The hero pill is the §C pill one size up — 11/650, not a new treatment.
    /// The list row's badge keeps the base role (R13/X5).
    @Test
    func heroOutcomeBadgeOverridesSizeOnly() {
        let hero = PouredType.Role.outcomeBadgeHero.spec
        let row = PouredType.Role.outcomeBadge.spec
        #expect(hero.size == 11)
        #expect(row.size == 10.5)
        #expect(hero.weight == row.weight)
        #expect(hero.isMono == row.isMono)
        #expect(hero.isTabular == row.isTabular)
    }

    // MARK: - §G″ right slot + pill label (G3 · `:174-176`, `:154`, `:1364-1367`)

    /// The board states one `.count` rule for the right slot and one `.pill .lab`
    /// rule for the label; native had mapped the counter onto the row `age` role
    /// and the label onto the row `.act` role. Both are pinned here because the
    /// second one is load-bearing for *layout*: the extra weight and the missing
    /// negative tracking are what truncated `Refactoring · 3 agents` inside the
    /// notch lane the pill already reserved.
    @Test
    func closedPillAdoptsTheBoardsCountCapsuleAndLabelFace() {
        let count = PouredType.Role.pillCountBadge.spec
        #expect(count.size == 12)
        #expect(count.weight == 650)
        #expect(count.isTabular)
        #expect(PouredPillMotion.RightSlot.countBadgeFillOpacity == 0.1)
        #expect(PouredPillMotion.RightSlot.countBadgeInkOpacity == 0.96)
        // The capsule reuses the A3/A4 badge box — 20pt tall, half-height radius.
        #expect(PouredPillMotion.RightSlot.badgeMinDiameter == 20)
        #expect(PouredPillMotion.RightSlot.badgeCornerRadius == 10)
        #expect(PouredPillMotion.RightSlot.badgeHPadding == 6)

        let label = PouredType.Role.pillLabel.spec
        #expect(label.size == 12.5)
        #expect(label.weight == 400)
        #expect(label.trackingEm == -0.01)
        #expect(!label.isMono)
        // Distinct from the row's `.act` rule it used to borrow.
        #expect(label.weight != PouredType.Role.activityLine.spec.weight)
    }

    /// The rest of the G3 truncation fix: the label may paint into the trailing
    /// safety margin the pill's own half-reserve already holds. The invariant
    /// that matters is that this is a *render* width only — the width math
    /// (`macbookOuterWidth`, which is what draws the silhouette) must be
    /// byte-identical whether the label renders into that margin or not.
    // `V6ClosedPill` is a SwiftUI `View`, so its layout statics are main-actor
    // isolated (see `PouredPillMotionTests`' own width-golden suite).
    @MainActor
    @Test
    func notchLaneRenderWidthExceedsTheReserveWithoutMovingThePill() {
        for notch in [140.0, 189.0, 220.0] as [CGFloat] {
            let lane = V6ClosedPill.notchLaneLabelWidth(physicalNotchWidth: notch, height: 32)
            let render = V6ClosedPill.notchLaneLabelRenderWidth(physicalNotchWidth: notch, height: 32)
            #expect(render > lane)
            // 4pt — the `notchLaneLabelTrailingMargin` already inside the reserve.
            #expect(render - lane == 4)
            // The silhouette is unchanged: outer width reads the lane, never the
            // render width, and a label long enough to saturate both is the same
            // pill.
            let saturating = String(repeating: "M", count: 80)
            #expect(
                V6ClosedPill.macbookOuterWidth(
                    label: saturating,
                    physicalNotchWidth: notch,
                    height: 32
                ) == 2 * (16 + 24 + 4 + 6 + lane) + notch
            )
        }
    }

    // MARK: - New copy (all three catalogs)

    /// Every string §G/§H gained must exist in en / zh-Hans / zh-Hant — a key
    /// missing from a catalog renders as the raw key on that language.
    @Test
    func slice6CopyExistsInEveryCatalog() throws {
        let keys = ["poured.subagents.live", "poured.completion.reply", "poured.completion.result"]
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
            for key in keys {
                #expect(catalog.contains("\"\(key)\" ="), "\(locale) is missing \(key)")
            }
        }
    }

    // MARK: - New deterministic scenarios

    /// H1's scenario needs BOTH seams: the row must be the surface's actionable
    /// one (`shouldShowEmbeddedDetailBody` gates a completed row's hero on it)
    /// and the expansion seam must be forced (a completed row in a click-opened
    /// list is collapsed by construction). Either one alone renders §D, not §H.
    @Test
    func completedSuccessScenarioReachesTheCompletionHero() {
        let snapshot = IslandDebugScenario.completedSuccess.snapshot()
        #expect(snapshot.sessions.map(\.id) == ["fixture-completed-success"])
        #expect(snapshot.selectedSessionID == "fixture-completed-success")
        #expect(snapshot.notchStatus == .opened)
        #expect(snapshot.forcesRowExpansion)
        #expect(snapshot.islandSurface.sessionID == "fixture-completed-success")
        #expect(snapshot.sessions[0].outcome == .success)
        #expect(snapshot.usageProviders == nil)
    }

    /// G3's scenario is the only closed state whose spotlight can reach the
    /// right slot's task counter: the resolver needs a *running* Claude session
    /// carrying tasks/subagents, and every pre-existing closed fixture
    /// spotlights a Codex session with no Claude metadata.
    @Test
    func closedTaskCounterScenarioSpotlightsARunningClaudeFanOut() {
        let snapshot = IslandDebugScenario.closedTaskCounter.snapshot()
        #expect(snapshot.notchStatus == .closed)
        #expect(snapshot.sessions.map(\.id) == ["fixture-subagents-tasks"])
        #expect(snapshot.selectedSessionID == "fixture-subagents-tasks")

        let session = try! #require(snapshot.sessions.first)
        #expect(session.phase == .running)
        #expect(session.tool == .claudeCode)
        let rollup = PouredTaskRollup(statuses: session.claudeMetadata?.activeTasks.map(\.status) ?? [])
        #expect(rollup.done == 2)
        #expect(rollup.total == 5)
        #expect(session.claudeMetadata?.activeSubagents.count == 3)
    }

    /// Both scenarios must be time-pure like every other fixture — two snapshots
    /// taken at the same `now` are identical, so a capture is reproducible.
    @Test
    func newScenariosAreDeterministicForAFixedNow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for scenario in [IslandDebugScenario.completedSuccess, .closedTaskCounter] {
            let first = scenario.snapshot(at: now)
            let second = scenario.snapshot(at: now)
            #expect(first.sessions.map(\.id) == second.sessions.map(\.id))
            #expect(first.sessions.map(\.updatedAt) == second.sessions.map(\.updatedAt))
            #expect(first.sessions.map(\.firstSeenAt) == second.sessions.map(\.firstSeenAt))
        }
    }
}
