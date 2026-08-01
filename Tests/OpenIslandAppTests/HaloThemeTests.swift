import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-340 (T21 · Halo 1/N): the Halo theme's shell — the pure-black void token
/// identity, the edge-light accent + wash tables, the ambient motion periods, the
/// grown window insets, the mono/sans typography floor, the bloomed-circle
/// agents-grid geometry, and the "never color alone" edge-state resolver.
///
/// Halo is built **unregistered** across T21–T25 (T26 registers it), so these
/// tests instantiate `HaloTheme()` / read `IslandThemeTokens.halo` directly rather
/// than through the registry. One assertion documents the interim registry state.
///
/// `@MainActor` because `HaloTheme` is a main-actor value type.
@MainActor
struct HaloThemeTests {

    // MARK: - Registry position (AC: appended last, non-default)

    /// T26 (AB-345) registers Halo: appended last in `ThemeRegistry.all`,
    /// **non-default**. Poured Island stays `all[0]` (the product's face), and
    /// `theme(id:)` resolves the real theme instead of falling back. This pins
    /// the position so a reorder (or a change of default) is caught.
    ///
    /// The roster is four since the 2026-08-01 owner ruling retired Annual and
    /// Instrument; Halo used to sit directly after Annual and now simply stays
    /// last.
    @Test
    func haloIsRegisteredLastAndIsNotTheDefault() {
        let ids = ThemeRegistry.all.map(\.id)
        // Present and resolvable by id.
        #expect(ids.contains("halo"))
        #expect(ThemeRegistry.theme(id: "halo").id == "halo")
        // Full registry order after the retirement: the surviving four.
        #expect(ids == ["poured", "classic", "flightDeck", "halo"])
        #expect(ids.firstIndex(of: "halo") == ids.count - 1)   // last entry
        // Non-default: Poured stays the product's face at slot 0.
        #expect(ThemeRegistry.default.id == "poured")
        #expect(ThemeRegistry.default.id != "halo")
        #expect(ids.first == "poured")
    }

    // MARK: - Surface: the pure-black void (the defining value)

    // MARK: - Status tints (8-bit component equality per hex)

    // MARK: - Text ramp + hairline (the corrected tertiary opacity)

    // MARK: - Metrics (radii, fillet, hover, shadow, the grown insets)

    // MARK: - Motion (open/close/pop/unmount)

    // MARK: - Material + capability flags (opaque void, no specular)

    // MARK: - Question-prompt pagination (overlay remediation Phase 2B · F1a/D1)

    // MARK: - Halo-local edge accents + washes

    // MARK: - Halo-local metrics

    // MARK: - Halo-local ambient motion periods

    // MARK: - Typography floor (every readable role ≥ 10pt)

    // MARK: - Mono/sans split (mono limited to the five code roles)

    // MARK: - Agents-grid geometry (bloomed circles; balancedRows delegates)

    // MARK: - "Never color alone" (non-color channel per state)

    /// The edge-state resolver maps phase / presence / outcome exactly, and an
    /// inactive process always recedes to `idle` so a dead session never keeps a
    /// loud edge.
    @Test
    func edgeStateResolverMapsPhasePresenceAndOutcome() {
        typealias F = HaloSessionRowFormat
        #expect(F.edgeState(phase: .running, presence: .running, outcome: .success) == .running)
        #expect(F.edgeState(phase: .waitingForApproval, presence: .running, outcome: .success) == .permission)
        #expect(F.edgeState(phase: .waitingForAnswer, presence: .running, outcome: .success) == .question)
        #expect(F.edgeState(phase: .completed, presence: .active, outcome: .success) == .success)
        #expect(F.edgeState(phase: .completed, presence: .active, outcome: .interrupted) == .interrupted)
        #expect(F.edgeState(phase: .completed, presence: .active, outcome: .failed) == .failed)
        // An inactive process recedes to idle regardless of stored phase.
        #expect(F.edgeState(phase: .running, presence: .inactive, outcome: .success) == .idle)
        #expect(F.edgeState(phase: .waitingForApproval, presence: .inactive, outcome: .success) == .idle)
    }

    // MARK: - Collapsed-row rail mapping (AB-344 · SPEC §5C/§5D)

    /// The collapsed row's edge-lit rail marks **only** the live / actionable rows —
    /// running, permission, question — and is absent on every settled or idle row
    /// (success / interrupted / failed / idle), so a list with nothing live is
    /// rail-free and calm. Pure logic pinned here so the phase → rail mapping can't
    /// drift without a rendered row (AB-344 acceptance).
    @Test
    func railAppearsOnlyOnLiveAndActionableRows() {
        typealias F = HaloSessionRowFormat
        // The three states that draw a rail, each with its distinct style.
        #expect(F.rail(for: .running) == .running)
        #expect(F.rail(for: .permission) == .permission)
        #expect(F.rail(for: .question) == .question)
        // Every settled / idle state is rail-free.
        #expect(F.rail(for: .success) == nil)
        #expect(F.rail(for: .interrupted) == nil)
        #expect(F.rail(for: .failed) == nil)
        #expect(F.rail(for: .idle) == nil)

        // Exactly the live/actionable states carry a rail — no more, no fewer.
        let railed = F.EdgeState.allCases.filter { F.rail(for: $0) != nil }
        #expect(Set(railed) == [.running, .permission, .question])

        // The three rail styles are distinct (each state reads a different rail).
        let styles = railed.map { F.rail(for: $0) }
        #expect(Set(styles).count == 3)
    }

    // MARK: - Agent monogram derivation (achromatic identity mark)

    // MARK: - Subagents & completion formats (Part 2 · §5G/§5H)

    // MARK: - Identity strings localize (AC: name/descriptor per language ≠ key)

    // MARK: - §5F question q-tag format (pure)

}
