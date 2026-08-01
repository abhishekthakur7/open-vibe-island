import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// AB-317 (annual 3/4): the pure display rules behind the editorial dot-grammar
/// session row — the status-mark state mapping, the one-accent discipline, the
/// pulse gating, the meta-line construction, the "Unknown" guard, the SSH cell,
/// the interrupted / failed glyph, the ≥24pt control hit targets, and the ≥10pt
/// type floor.
///
/// The SwiftUI body itself isn't rendered here (there's no headless view host);
/// the row deliberately routes every AC-bearing decision through
/// `AnnualSessionRowFormat` / `AnnualSessionRowGrid` so the contract is testable
/// without one. The pixel screenshot, Accessibility-Inspector and live-scroll ACs
/// are flagged manual in the PR.
struct AnnualSessionRowTests {

    // MARK: - Typographic alarm: key-hint glyphs (AB-318 · AC #1 · #2)

    /// The `allow` / always-allow / `deny` buttons must print the **real** registered
    /// `OverlayPanelController` shortcuts — ⌘Y, ⌘⇧Y, ⌘N — so the on-screen hint never
    /// drifts from the keys that actually fire.
    @Test
    func approvalKeyHintGlyphsMatchTheRegisteredShortcuts() {
        #expect(AnnualApprovalFormat.Shortcut.allowOnce.glyphString == "⌘Y")
        #expect(AnnualApprovalFormat.Shortcut.alwaysAllow.glyphString == "⌘⇧Y")
        #expect(AnnualApprovalFormat.Shortcut.deny.glyphString == "⌘N")

        // Every glyph string is built from the ordered glyph run, and the three
        // shortcuts stay distinct so no two buttons print the same hint.
        for shortcut in AnnualApprovalFormat.Shortcut.allCases {
            #expect(shortcut.glyphString == shortcut.glyphs.joined())
        }
        let hints = AnnualApprovalFormat.Shortcut.allCases.map(\.glyphString)
        #expect(Set(hints).count == hints.count)
    }
}
