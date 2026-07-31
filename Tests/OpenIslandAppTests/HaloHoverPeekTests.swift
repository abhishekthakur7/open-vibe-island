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

    /// One blocked session: the peek names it, quotes the pending command, and
    /// shows no `+N more` chip — there is nothing compressed behind it.
    @Test
    func singleWaitingSessionPeeksWithoutTheOverflowChip() throws {
        let sessions = IslandDebugScenario.closedAttention.snapshot().sessions
        let content = try #require(HaloHoverPeekContent.resolve(sessions: sessions, lang: lang))

        #expect(content.kind == .permission)
        #expect(content.title.contains("open-island"))
        #expect(content.detail?.contains("sed") == true)
        #expect(content.monogram == "C")
        #expect(content.moreWaiting == 0)
    }

    /// Two blocked sessions (`closedAttentionQueue`, the V2 enabler): the most
    /// actionable one surfaces inline and the rest compress to `+N`.
    @Test
    func aQueueCompressesTheRestIntoTheOverflowChip() throws {
        let sessions = IslandDebugScenario.closedAttentionQueue.snapshot().sessions
        let waiting = sessions.filter {
            $0.phase == .waitingForApproval || $0.phase == .waitingForAnswer
        }
        #expect(waiting.count == 2)

        let content = try #require(HaloHoverPeekContent.resolve(sessions: sessions, lang: lang))
        #expect(content.kind == .permission)
        #expect(content.moreWaiting == 1)
        // The hint's verb forks with the kind, so the peek never promises
        // "approve" for a question.
        #expect(content.hint(lang) != HaloHoverPeekContent(
            kind: .question,
            title: "",
            detail: nil,
            monogram: "",
            moreWaiting: 0
        ).hint(lang))
    }
}
