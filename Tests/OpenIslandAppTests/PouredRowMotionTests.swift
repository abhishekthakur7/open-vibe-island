import Testing
import OpenIslandCore
@testable import OpenIslandApp

/// AB-332 (Poured 2.0 session rows, stage 1): pins the row's motion constants
/// and its two pure presentation decisions — the narrated-activity tone split
/// and the disambiguator suffix styling input — so any drift in the row list
/// state (`SPEC-poured-island` §3.3 / §4C · mockup §C) fails the build.
struct PouredRowMotionTests {

    // MARK: - Expansion-state source of truth

    @Test
    func ordinaryRunningNonActionableRowStartsCollapsed() {
        #expect(!PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: false,
            isActionable: false,
            autoExpandsActionable: false,
            detailOverride: nil
        ))
    }

    /// PI-C-006: an actionable row auto-expands only on the dedicated
    /// notification surface (§E/§F). Inside the §C grouped list the same row
    /// stays compact — the hero opens deliberately, and an explicit override
    /// still wins over both.
    @Test
    func actionableRowExpandsOnlyOnTheNotificationSurface() {
        #expect(!PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: false,
            isActionable: true,
            autoExpandsActionable: false,
            detailOverride: nil
        ))
        #expect(PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: false,
            isActionable: true,
            autoExpandsActionable: true,
            detailOverride: nil
        ))
        #expect(PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: false,
            isActionable: true,
            autoExpandsActionable: false,
            detailOverride: true
        ))
    }

    @Test
    func manualOverrideWinsInBothDirections() {
        #expect(PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: false,
            isActionable: false,
            autoExpandsActionable: false,
            detailOverride: true
        ))
        #expect(!PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: true,
            isActionable: true,
            autoExpandsActionable: true,
            detailOverride: false
        ))
    }

    // MARK: - Compact activity narrative (PI-C-005)

    /// The board narrates on all six §C rows, including a 22-minute-old
    /// interrupted one — past the point where the shared spotlight line falls
    /// silent — and it never prints Markdown. Both halves of that contract:
    /// a settled row falls back to its own one-line summary, and a Markdown
    /// last-message is flattened to one plain line.
    @Test
    func compactActivityNarratesAgedRowsWithoutLeakingMarkdown() {
        let aged = PouredCompactActivity.text(
            isSettled: true,
            summary: "Stopped while editing BridgeServer.swift",
            spotlight: nil,
            lastAssistantMessage: nil,
            hasJumpTarget: false
        )
        #expect(aged == "Stopped while editing BridgeServer.swift")

        let markdown = PouredCompactActivity.text(
            isSettled: false,
            summary: nil,
            spotlight: nil,
            lastAssistantMessage: """
            Updated **AGENTS.md** and `CLAUDE.md`.

            - 2 files changed
            """,
            hasJumpTarget: true
        )
        #expect(markdown == "Updated AGENTS.md and CLAUDE.md. 2 files changed")

        // Nothing to say still says something rather than leaving the row mute.
        #expect(PouredCompactActivity.text(
            isSettled: true,
            summary: nil,
            spotlight: nil,
            lastAssistantMessage: nil,
            hasJumpTarget: true
        ) == "Ready")
    }

    // MARK: - Narrated activity tone split (mockup `.act` / `.act .live`)

    /// R2/C3 (`01-poured-island.html:852`): only the verb takes the run-blue
    /// `.live` tone; the object and the `\u{00B7} live 1m 42s` tail both stay at
    /// the base `.act` ink, and the tail is appended only when a suffix is
    /// supplied (the board's row 4 has none).
    @Test
    func verbTakesLiveToneAndTheLiveTailStaysSecondary() {
        #expect(PouredRowActivityTone.segments(
            verb: "Editing",
            object: "AppModel.swift",
            fallback: nil
        ) == [
            .init(text: "Editing", tone: .live),
            .init(text: " AppModel.swift", tone: .secondary),
        ])

        #expect(PouredRowActivityTone.segments(
            verb: "Editing",
            object: "AppModel.swift",
            fallback: nil,
            liveSuffix: "live 1m 42s"
        ) == [
            .init(text: "Editing", tone: .live),
            .init(text: " AppModel.swift", tone: .secondary),
            .init(text: " \u{00B7} live 1m 42s", tone: .secondary),
        ])

        // A row with nothing to narrate gains no orphan tail.
        #expect(PouredRowActivityTone.segments(
            verb: nil, object: nil, fallback: nil, liveSuffix: "live 3s"
        ).isEmpty)

        // The tail's own formatting keeps seconds under an hour — the age
        // column's coarser `1m` is a different reading of a different clock.
        #expect(PouredLiveElapsed.text(seconds: 102) == "1m 42s")
        #expect(PouredLiveElapsed.text(seconds: 42) == "42s")
        #expect(PouredLiveElapsed.text(seconds: 3_720) == "1h 2m")
    }

    @Test
    func narrationWinsOverFallbackWhenBothPresent() {
        // The narrated verb/object is authoritative; a stray fallback is ignored.
        let segments = PouredRowActivityTone.segments(
            verb: "Running",
            object: "git status",
            fallback: "ignored"
        )
        #expect(segments == [
            .init(text: "Running", tone: .live),
            .init(text: " git status", tone: .secondary),
        ])
    }

    // MARK: - Subagent live timer (mockup §G `.sa-time` — `M:SS`)

    @Test
    func subagentClockZeroPadsSecondsUnderAMinute() {
        // Mockup renders `0:42`, `0:08` — not the shipped `42s` / `8s`.
        #expect(PouredSubagentTiming.clockLabel(seconds: 42) == "0:42")
        #expect(PouredSubagentTiming.clockLabel(seconds: 8) == "0:08")
        #expect(PouredSubagentTiming.clockLabel(seconds: 0) == "0:00")
    }

    // MARK: - Task rollup (mockup §G nest header + §G′ chip)

    @Test
    func taskRollupCountsCompletedOnly() {
        let rollup = PouredTaskRollup(statuses: [.completed, .completed, .inProgress, .pending, .pending])
        // "2 of 5 done" — in-progress is not done.
        #expect(rollup.done == 2)
        #expect(rollup.total == 5)
    }

    // MARK: - Pane attachment chip (mockup §D — first surfacing of the field)

    @Test
    func attachmentChipMapsStateToCopyAndLiveness() {
        #expect(PouredAttachmentChip(.attached) == .attached)
        #expect(PouredAttachmentChip(.attached).localizationKey == "poured.detail.attachment.attached")
        #expect(PouredAttachmentChip(.attached).isLive)

        #expect(PouredAttachmentChip(.stale) == .stale)
        #expect(PouredAttachmentChip(.stale).localizationKey == "poured.detail.attachment.stale")
        #expect(!PouredAttachmentChip(.stale).isLive)

        #expect(PouredAttachmentChip(.detached) == .detached)
        #expect(PouredAttachmentChip(.detached).localizationKey == "poured.detail.attachment.detached")
        #expect(!PouredAttachmentChip(.detached).isLive)
    }
}
