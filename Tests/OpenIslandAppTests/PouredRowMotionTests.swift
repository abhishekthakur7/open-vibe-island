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
            detailOverride: nil
        ))
    }

    @Test
    func manualOverrideWinsInBothDirections() {
        #expect(PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: false,
            isActionable: false,
            detailOverride: true
        ))
        #expect(!PouredRowExpansion.resolved(
            isInteractive: true,
            expandedByDefault: true,
            isActionable: true,
            detailOverride: false
        ))
    }

    // MARK: - Narrated activity tone split (mockup `.act` / `.act .live`)

    @Test
    func verbAndObjectSplitDimsVerbAndBrightensObject() {
        let segments = PouredRowActivityTone.segments(
            verb: "Editing",
            object: "AppModel.swift",
            fallback: nil
        )
        #expect(segments == [
            .init(text: "Editing", isPrimary: false),
            .init(text: " AppModel.swift", isPrimary: true),
        ])
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
            .init(text: "Running", isPrimary: false),
            .init(text: " git status", isPrimary: true),
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
