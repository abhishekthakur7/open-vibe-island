import XCTest

@testable import OpenIslandApp

/// AB-345 (T26): the Halo 2.0 A–K conformance snapshot pins.
///
/// Each `AppearancePreviewScenario` that maps to a SPEC-halo §5 scenario is pinned
/// through the shared `ThemeSnapshotting` harness (AB-327 / T09) at both panel
/// widths (notch 540pt / top-bar 520pt). The harness forces the deterministic
/// render path: reduce-transparency (flat `#000` void, no `NSVisualEffectView`),
/// the frozen `\.haloEdgePhase` (orbit 0 / pulse 0, SPEC §6.3), and a settled
/// resting frame (the row entrance sweep latches off-screen and the hero pulse ring
/// resolves to its peak on appear — both deterministic at capture).
///
/// **Scope of the harness (and what is verified elsewhere).** The harness renders
/// the *opened session list* in English, so:
/// - The **panel** perimeter edge-light (A1–A6 pill glows) is driven upstream of the
///   `sessionList` slot; it is pinned at code + token level in `HaloEdgeLightTests`
///   / `IslandSurfaceEdgeTests` and judged-by-eye per SPEC §6.4, not here.
/// - **Increase Contrast / Reduce Motion** variants cannot be pinned: those
///   environment keys are read-only in this SDK (the harness note in
///   `PouredConformanceSnapshotTests` documents the same limit). The branches that
///   read them are unit-pinned in `HaloThemeTests` (the +0.24 ramps, the static
///   attention peak) — the A–K checklist in the ticket report carries the mapping.
/// - **zh-Hans** is not a harness axis (it hard-pins English so golden text never
///   drifts with locale); the bilingual identity + copy is asserted string-by-string
///   in `HaloThemeTests` instead.
///
/// Goldens are byte-exact and gated on the environment fingerprint, so a
/// differently-rendering runner skips the pixel compare rather than failing.
/// Re-record with `OPEN_ISLAND_RECORD_SNAPSHOTS=1`.
@MainActor
final class HaloConformanceSnapshotTests: XCTestCase {

    private func theme() -> HaloTheme { HaloTheme() }

    // MARK: - Scenario list frames (C · D · E1–E3 · F · G · H · A6 · I · J)

    /// Pins one scenario at both panel widths under `named`-`notch` / `-topbar`.
    private func assertBothProfiles(
        _ scenario: AppearancePreviewScenario,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) throws {
        for profile in [ThemeSnapshotting.Profile.notch, .topBar] {
            let suffix = profile == .notch ? "notch" : "topbar"
            try ThemeSnapshotting.assertSnapshot(
                theme: theme(),
                slot: .sessionList(scenario: scenario),
                profile: profile,
                named: "\(name)-\(suffix)",
                file: file,
                testName: testName,
                line: line
            )
        }
    }

    /// C — the grouped session list with the duplicate-workspace branch disambiguation
    /// ("Needs you" floats to top, mono branch chips, the edge-lit rails).
    func testSessionListDuplicates() throws {
        try assertBothProfiles(.duplicates, named: "halo-C-session-list")
    }

    /// D · G — the expanded running row: quiet metadata grid + the subagent / todo nest.
    func testExpandedDetailAndSubagents() throws {
        try assertBothProfiles(.subagents, named: "halo-D-G-subagents")
    }

    /// E1 — permission hero over a shell command (syntax-lit `.cmd`, scoped allow rows,
    /// keycaps, the amber ring + pulse).
    func testPermissionCommandHero() throws {
        try assertBothProfiles(.permissionCommand, named: "halo-E1-permission-command")
    }

    /// E2 — permission hero with the inline gutter-numbered Edit diff.
    func testPermissionDiffHero() throws {
        try assertBothProfiles(.permissionDiff, named: "halo-E2-permission-diff")
    }

    /// E3 — Codex terminal-approval hero (amber ring, cool-blue note + single jump CTA,
    /// no fake Approve).
    func testCodexApprovalHero() throws {
        try assertBothProfiles(.codexApproval, named: "halo-E3-codex-approval")
    }

    /// F1/F2 — the question hero: qgold ring shell, `.q-tag` chip, the shared T07
    /// interior (ring+tick single-select, square multi-select, freeform last, digit hints).
    func testQuestionHero() throws {
        try assertBothProfiles(.questionMulti, named: "halo-F-question")
    }

    /// H — the completion body: outcome badge + tabular duration + rich prose + follow-up rail.
    func testCompletionSuccess() throws {
        try assertBothProfiles(.completedSuccess, named: "halo-H-completed-success")
    }

    /// A6 — the completed outcome variants (interrupted expanded, failed collapsed).
    func testCompletedOutcomeVariants() throws {
        try assertBothProfiles(.completedVariants, named: "halo-A6-completed-variants")
    }

    /// I — the usage meters (header filament rings + the full §I meter card).
    func testUsageMeters() throws {
        try assertBothProfiles(.meters, named: "halo-I-usage-meters")
    }

    /// J — the empty state (static monitor glyph, "All quiet", monitoring pill).
    func testEmptyState() throws {
        try assertBothProfiles(.empty, named: "halo-J-empty")
    }

    // MARK: - Closed-pill ambient frames the harness supports (A1 · A2)

    /// A1 — idle pill (still 3-bar glyph, no glow). The living edge is driven upstream
    /// of the shared `V6ClosedPill` the harness renders, so this pins the void-token
    /// application; the edge itself is judged-by-eye (§6.4).
    func testClosedPillIdle() throws {
        for profile in [ThemeSnapshotting.Profile.notch, .topBar] {
            let suffix = profile == .notch ? "notch" : "topbar"
            try ThemeSnapshotting.assertSnapshot(
                theme: theme(),
                slot: .closedPill(mode: .idle, rightSlot: nil),
                profile: profile,
                named: "halo-A1-idle-pill-\(suffix)"
            )
        }
    }

    /// A2 — working pill (running wave glyph, `×3` count).
    func testClosedPillWorking() throws {
        for profile in [ThemeSnapshotting.Profile.notch, .topBar] {
            let suffix = profile == .notch ? "notch" : "topbar"
            try ThemeSnapshotting.assertSnapshot(
                theme: theme(),
                slot: .closedPill(mode: .running, rightSlot: .count(3)),
                profile: profile,
                named: "halo-A2-working-pill-\(suffix)"
            )
        }
    }
}
