import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// Halo parity V2 · G-62/M-27 — the §B hover peek's *copy* resolution
/// (`06-halo.html:709-721`), pinned view-free so the peek's vocabulary can be
/// asserted without standing up an overlay or driving a pointer.
///
/// Only the structure is asserted, never the rendered sentence: the title is a
/// localized format whose one substitution is the workspace, so `contains` holds
/// in en / zh-Hans / zh-Hant alike and these tests never depend on the machine's
/// language.
@MainActor
struct HaloHoverPeekTests {

    private var lang: LanguageManager { LanguageManager() }

    /// The board only ever draws a peek for an *actionable* island. A collapsed
    /// notch with work running but nothing blocked on the user keeps the bare
    /// 1.03 scale bump (M-16) — no invented surface.
    @Test
    func noPeekWhenNothingIsWaiting() {
        let sessions = IslandDebugScenario.closed.snapshot().sessions
        #expect(sessions.contains { $0.phase == .running })
        #expect(HaloHoverPeekContent.resolve(sessions: sessions, lang: lang) == nil)
    }

}
