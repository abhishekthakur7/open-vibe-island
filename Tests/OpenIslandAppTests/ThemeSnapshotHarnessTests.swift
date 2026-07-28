import XCTest

@testable import OpenIslandApp

/// AB-327 (draft T09): seed goldens proving the theme-conformance snapshot
/// harness is wired end-to-end and deterministic.
///
/// These are the two pins the ticket calls for — the Classic closed pill in its
/// running state, and the Poured opened session list over the five-fixture
/// baseline set (recorded at both panel widths). Later theme tickets add their
/// own scenarios by calling ``ThemeSnapshotting/assertSnapshot(theme:slot:profile:named:record:file:testName:line:)``.
///
/// XCTest (not swift-testing) on purpose: the fingerprint gate leans on
/// `XCTSkip`, and the native recorder is XCTest-based — both
/// keep the harness robust and CI-green. See the helper's doc and
/// `docs/quality.md`.
@MainActor
final class ThemeSnapshotHarnessTests: XCTestCase {

    /// Classic · closed pill · running · top-bar layout, `×5` right slot.
    func testClassicClosedPillRunning() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: ClassicTheme(),
            slot: .closedPill(mode: .running, rightSlot: .count(5)),
            profile: .topBar,
            named: "classic-closed-pill-running"
        )
    }

    /// Poured · opened session list · five-fixture baseline · notch (540pt).
    func testPouredSessionListBaselineNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: PouredIslandTheme(),
            slot: .sessionList(scenario: .list),
            profile: .notch,
            named: "poured-session-list-baseline-notch"
        )
    }

    /// Poured · opened session list · five-fixture baseline · top-bar (520pt).
    func testPouredSessionListBaselineTopBar() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: PouredIslandTheme(),
            slot: .sessionList(scenario: .list),
            profile: .topBar,
            named: "poured-session-list-baseline-topbar"
        )
    }

    // MARK: - Flight Deck actionable annunciators (AB-334)

    /// Flight Deck · permission command · the red **MASTER WARNING** annunciator
    /// (placard + `PERMISSION REQUIRED` kicker + `HELD` count-up), the
    /// syntax-highlighted command box, and the ⌘Y / ⌘⇧Y / ⌘N ACK switches. The
    /// beacon draws steady-lit here (no `PulseClock` is supplied to the harness).
    /// English only — the harness pins the language (see ``ThemeSnapshotting``).
    func testFlightDeckPermissionMasterWarningNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .permissionCommand),
            profile: .notch,
            named: "flightdeck-permission-master-warning-notch"
        )
    }

    /// Flight Deck · permission command · the same **MASTER WARNING** annunciator
    /// at the narrower top-bar profile (520pt / 504pt after insets). Overlay
    /// remediation Phase 4 coverage-closure: F2.3 (placard 10.5→12pt / `.heavy`
    /// / tracking 1.44 / new `.lineLimit(1)` + `.fixedSize`) only had a notch
    /// golden — this is a layout-pressure transfer (the placard now refuses to
    /// shrink while the kicker's `minimumScaleFactor` dropped 0.85→0.6), so the
    /// narrower profile is the one that could actually expose truncation or a
    /// collision with the `HELD` readout in the trailing slot.
    func testFlightDeckPermissionMasterWarningTopBar() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .permissionCommand),
            profile: .topBar,
            named: "flightdeck-permission-master-warning-topbar"
        )
    }

    /// Flight Deck · multi-question · the amber **MASTER CAUTION** annunciator
    /// (placard + `QUESTION` kicker + steady amber beacon) wrapping the shared
    /// `StructuredQuestionPromptView` interior. English only.
    func testFlightDeckQuestionMasterCautionNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .questionMulti),
            profile: .notch,
            named: "flightdeck-question-master-caution-notch"
        )
    }

    /// Flight Deck · multi-question · the same **MASTER CAUTION** annunciator at
    /// the narrower top-bar profile (520pt). Same F2.3 coverage-closure rationale
    /// as the permission top-bar golden above — "QUESTION" is the other kicker
    /// string the layout-pressure transfer could truncate or shrink.
    func testFlightDeckQuestionMasterCautionTopBar() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .questionMulti),
            profile: .topBar,
            named: "flightdeck-question-master-caution-topbar"
        )
    }

    /// Flight Deck · multi-question · Submit enabled (overlay remediation
    /// Phase 2B · F1 Task 2): the same MASTER CAUTION card with
    /// `\.islandQuestionPromptPreselectsFirstOption` injected, so every
    /// question's first option starts pre-selected and `canSubmit` is `true`
    /// at capture time — the only way to photograph the *enabled*
    /// `FlightDeckApprovalButton` `.tinted` chip (the translucent amber
    /// chamfered chip 2A2 built), since a real question card always starts
    /// from an empty selection. Flight Deck's page holds every question
    /// (`questionPageSize == Int.max`), so this stays on its one and only
    /// page and the label reads the same final-page "Submit" as the disabled
    /// golden above — pagination doesn't relabel this theme's button, only
    /// its keyboard model (continuous 1-7). Notch only, matching the
    /// disabled golden above (no FD topbar question golden exists). A new
    /// scenario, not a redefinition — `testFlightDeckQuestionMasterCautionNotch`
    /// keeps the *disabled* Submit's own regression coverage (mirrors Phase
    /// 1's `subagentsExpanded` alongside `subagentsCard`): both states matter.
    func testFlightDeckQuestionMasterCautionSubmitEnabledNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .questionMulti),
            profile: .notch,
            named: "flightdeck-question-master-caution-submit-enabled-notch",
            preselectsQuestionSelection: true
        )
    }

    // MARK: - Flight Deck row register + chips (AB-337 · AC #7)

    /// Flight Deck · duplicate-workspace trio · notch (540pt) **and** top-bar
    /// (520pt). Evidence the `STATUS | SESSION | MODEL | TIME` register survives at
    /// both panel widths with the new folded chips: the two Claude rows carry `⑂`
    /// branch chips (`feat/bridge-auth` / `main`) that double as the T05
    /// disambiguator, one adds `⚙ 3 SUB`, and both narrate a verb-mapped activity
    /// (`Editing …` / `Orchestrating …`), while the Codex row carries no branch
    /// chip (SPEC §6 honesty gate). The name column absorbs truncation; the chips
    /// and fixed lanes hold their columns. The trio carries no actionable HELD
    /// counter, so unlike the `.list` baseline these goldens are time-stable.
    func testFlightDeckDuplicateWorkspaceBranchChipsNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .duplicates),
            profile: .notch,
            named: "flightdeck-duplicates-branch-chips-notch"
        )
    }

    func testFlightDeckDuplicateWorkspaceBranchChipsTopBar() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .duplicates),
            profile: .topBar,
            named: "flightdeck-duplicates-branch-chips-topbar"
        )
    }

    // MARK: - Flight Deck hero surfaces (AB-339)

    /// Flight Deck · engine cluster + todo list · notch (540pt). The §4G interior
    /// of the non-actionable spotlight: three engines (`EXPLORE` / `GENERAL` /
    /// `PLAN` placards + breathing lamps + task lines + per-subagent elapsed) and
    /// the `2 / 5 DONE` todo well (blue check + strikethrough / green breathing box
    /// / dim hollow). The engine elapsed and the row uptime are `now`-anchored
    /// fixtures (`startedAt = now − 42/75/8`), so — like the permission `HELD`
    /// counter this suite already pins — they resolve to the same `0m 42s` /
    /// `1m 15s` / `0m 08s` every run and the golden stays stable. English only.
    func testFlightDeckEngineClusterNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .subagents),
            profile: .notch,
            named: "flightdeck-engine-cluster-notch"
        )
    }

    /// Flight Deck · completion (advisory blue) · notch (540pt). The §4H `SUCCESS`
    /// badge + prose result + donestats grid (Outcome `✓ Success` / Duration
    /// `43m 12s` = `updatedAt − firstSeenAt`, a fixed fixture delta / Agent — no
    /// Files stat). The settled advisory lane is born completed (settle one-shot at
    /// rest, not re-flashing), so the frame is time-stable. English only.
    func testFlightDeckCompletionSuccessNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .completedSuccess),
            profile: .notch,
            named: "flightdeck-completion-success-notch"
        )
    }

    /// Flight Deck · empty state · **ALL SYSTEMS NOMINAL** · notch (540pt) **and**
    /// top-bar (520pt). The §4J confident tone flip: the lamp grid (one lit lamp
    /// captured at its breathing peak — the model layer holds the target, so no
    /// clock reaches the bitmap — + three dark), the bright heading, the monitoring
    /// copy, and the `BRIDGE LINK · MONITORING · 0 SESSIONS` sysline in its live
    /// nominal variant (the harness injects `islandBridgeIsLive = true`). Fully
    /// static — no counter, no age badge — so the pin is deterministic. English only.
    func testFlightDeckEmptyNominalNotch() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .empty),
            profile: .notch,
            named: "flightdeck-empty-nominal-notch"
        )
    }

    func testFlightDeckEmptyNominalTopBar() throws {
        try ThemeSnapshotting.assertSnapshot(
            theme: FlightDeckTheme(),
            slot: .sessionList(scenario: .empty),
            profile: .topBar,
            named: "flightdeck-empty-nominal-topbar"
        )
    }

    // NOTE (AB-339): the §4G closed-pill **subagents wing** (`3 subagents · 2/5`,
    // the `.taskCounter` right slot → `FlightDeckTaskCounterChip`) is *not* pinned
    // here. The harness `.closedPill` slot renders the theme-agnostic
    // `V6ClosedPill`, which resolves `.taskCounter` through the shared
    // `V6RightSlotView` (the `×N` degradation), never the Flight Deck
    // `FlightDeckRightSlotView` that draws the wing — so a pill golden would show
    // `×5`, not the FD wing. The wing is verified by eye against the running
    // overlay + covered by `IslandRightSlotContentTests` (the `.taskCounter`
    // payload) and `FlightDeckThemeTests` (its badge width math).

    // NOTE (AB-338): the tape gauges' three bands (NOM 34% / CAUT 78% / CRIT 92%)
    // are driven by the `.meters` scenario and were verified by eye against a
    // recorded render, but that scenario is deliberately *not* pinned as a
    // committed golden here: `.meters` reuses the full five-fixture session list,
    // whose live `HELD` count-up and the 5H window's minute-granular `RESET`
    // countdown drift second-to-second — the same temporal instability that keeps
    // the Poured `.list` baselines in the known-drift set. The tape geometry and
    // colour bands are pinned deterministically by `FlightDeckThemeTests`
    // (`tapeGaugePinsThresholdTicksAtSeventyAndNinety`, the cutoff/placard tests).
}
