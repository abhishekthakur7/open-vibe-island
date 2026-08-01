import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-313 (flightdeck 3/4): the pure display rules behind the annunciator
/// session row — the status-lane state / prominence / pulse mapping, the column-
/// register widths, the row rhythm, the "Unknown" guard, the SSH / app cell, the
/// interrupted/failed glyph, the motion-gated pulse, and the ≥10pt floor.
///
/// The SwiftUI body itself isn't rendered here (there's no headless view host);
/// the row deliberately routes every AC-bearing decision through
/// `FlightDeckSessionRowFormat` / `FlightDeckSessionRowGrid` so the contract is
/// testable without one.
struct FlightDeckSessionRowTests {

    // MARK: - STATUS code column (AB-337 · SPEC §3-Slot3)

    /// The STATUS text-code that heads each row is a pure function of
    /// phase / presence / outcome — the code + lamp pair pinned here so the code
    /// can never drift from the lamp's colour. Inactive presence wins first
    /// (idle-wins, mirroring `lanePriority`); otherwise phase → code, with the
    /// completion outcome splitting `DONE` / `INTR` / `FAIL`.
    @Test
    func statusCodePairsPhaseOutcomeToTheEICASCode() {
        // Running → RUN (nominal); fresh success → DONE (advisory).
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .running, presence: .running, outcome: .success) == "RUN")
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .completed, presence: .active, outcome: .success) == "DONE")
        // Attention phases: permission is the red WARN, question the amber CAUT.
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .waitingForApproval, presence: .active, outcome: .success) == "WARN")
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .waitingForAnswer, presence: .active, outcome: .success) == "CAUT")
        // Non-success completions split into the amber INTR and the red FAIL.
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .completed, presence: .active, outcome: .interrupted) == "INTR")
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .completed, presence: .active, outcome: .failed) == "FAIL")
        // Inactive presence recedes to IDLE regardless of the stored phase/outcome
        // — a stale completed or a stale running row both read IDLE (idle-wins).
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .completed, presence: .inactive, outcome: .failed) == "IDLE")
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .running, presence: .inactive, outcome: .success) == "IDLE")
        #expect(FlightDeckSessionRowFormat.statusCode(phase: .waitingForApproval, presence: .inactive, outcome: .success) == "IDLE")

        // Every code is a short (≤4-glyph) uppercase Latin EICAS placard — the
        // fixed-width column the caption registers over depends on it.
        let codes = [
            FlightDeckSessionRowFormat.statusCode(phase: .running, presence: .running, outcome: .success),
            FlightDeckSessionRowFormat.statusCode(phase: .completed, presence: .active, outcome: .success),
            FlightDeckSessionRowFormat.statusCode(phase: .waitingForApproval, presence: .active, outcome: .success),
            FlightDeckSessionRowFormat.statusCode(phase: .waitingForAnswer, presence: .active, outcome: .success),
            FlightDeckSessionRowFormat.statusCode(phase: .completed, presence: .active, outcome: .interrupted),
            FlightDeckSessionRowFormat.statusCode(phase: .completed, presence: .active, outcome: .failed),
            FlightDeckSessionRowFormat.statusCode(phase: .running, presence: .inactive, outcome: .success),
        ]
        #expect(codes.allSatisfy { !$0.isEmpty && $0.count <= 4 && $0 == $0.uppercased() })
    }

    // MARK: - MASTER CAUTION approval surfaces (AB-314)

    /// AC #1 / #2: the ALLOW / always-allow / DENY switches must print the
    /// **real** registered `OverlayPanelController` shortcuts — ⌘Y, ⌘⇧Y, ⌘N —
    /// never the mockup's ⏎/⎋.
    @Test
    func approvalKeyHintGlyphsMatchTheRegisteredShortcuts() {
        #expect(FlightDeckApprovalFormat.Shortcut.allowOnce.glyphString == "⌘Y")
        #expect(FlightDeckApprovalFormat.Shortcut.alwaysAllow.glyphString == "⌘⇧Y")
        #expect(FlightDeckApprovalFormat.Shortcut.deny.glyphString == "⌘N")

        // Every glyph string is built from the ordered glyph run, and the three
        // shortcuts stay distinct so no two switches print the same hint.
        for shortcut in FlightDeckApprovalFormat.Shortcut.allCases {
            #expect(shortcut.glyphString == shortcut.glyphs.joined())
        }
        let hints = FlightDeckApprovalFormat.Shortcut.allCases.map(\.glyphString)
        #expect(Set(hints).count == hints.count)
    }
}
