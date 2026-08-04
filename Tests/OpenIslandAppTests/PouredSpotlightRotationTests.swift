import Foundation
import Testing
@testable import OpenIslandApp
@testable import OpenIslandCore

/// R7 / PI-A-002 — the collapsed pill's multi-waiting spotlight rotation.
///
/// The board renders no N > 1 waiting frame, so every number here traces to the
/// owner ruling (3–4 s hold, wrap-around cycle sized by the waiting count) and
/// the Slice 5 packet's adjudication of the details it left open.
@Suite("Poured spotlight rotation")
struct PouredSpotlightRotationTests {

    // MARK: - The rule

    @Test
    func rotationStaysOffBelowTwoWaitingSessions() {
        // One waiting session is not a cycle: the pill must keep the shipped
        // single-winner behaviour byte-for-byte, at every phase.
        for waiting in 0...1 {
            #expect(!PouredSpotlightRotation.isActive(waitingCount: waiting))
            #expect(PouredSpotlightRotation.cycleMilliseconds(waitingCount: waiting) == 0)
            for elapsed in [0, 3_499, 3_500, 10_000, 1_000_000] {
                #expect(PouredSpotlightRotation.index(waitingCount: waiting, elapsedMs: elapsed) == 0)
            }
        }
        #expect(PouredSpotlightRotation.isActive(waitingCount: 2))
    }

    @Test
    func eachWaitingSessionHoldsForThreeAndAHalfSecondsThenWrapsAround() {
        #expect(PouredSpotlightRotation.holdMilliseconds == 3_500)

        // N = 2: 1 → 2 → 1, boundaries exactly on the hold.
        #expect(PouredSpotlightRotation.index(waitingCount: 2, elapsedMs: 0) == 0)
        #expect(PouredSpotlightRotation.index(waitingCount: 2, elapsedMs: 3_499) == 0)
        #expect(PouredSpotlightRotation.index(waitingCount: 2, elapsedMs: 3_500) == 1)
        #expect(PouredSpotlightRotation.index(waitingCount: 2, elapsedMs: 6_999) == 1)
        #expect(PouredSpotlightRotation.index(waitingCount: 2, elapsedMs: 7_000) == 0)
        #expect(PouredSpotlightRotation.cycleMilliseconds(waitingCount: 2) == 7_000)

        // N = 3: the wrap is a full 1 → 2 → 3 → 1, not a ping-pong.
        let threeWayCycle = (0..<8).map {
            PouredSpotlightRotation.index(waitingCount: 3, elapsedMs: $0 * 3_500)
        }
        #expect(threeWayCycle == [0, 1, 2, 0, 1, 2, 0, 1])
        #expect(PouredSpotlightRotation.cycleMilliseconds(waitingCount: 3) == 10_500)
    }

    @Test
    func phaseZeroAndBackwardsClocksLandOnTheShippedFirstWaitingSession() {
        // Index 0 is what the un-rotated ladder already answers, so the first
        // hold of any cycle — and any clock that ran backwards, or a manual
        // parity phase below zero — renders the pre-R7 pill.
        #expect(PouredSpotlightRotation.index(waitingCount: 4, elapsedMs: 0) == 0)
        #expect(PouredSpotlightRotation.index(waitingCount: 4, elapsedMs: -1) == 0)
        #expect(PouredSpotlightRotation.index(waitingCount: 4, elapsedMs: -50_000) == 0)
    }

    // MARK: - The live phase source

    @Test @MainActor
    func clockRunsOnlyWhileAskedAndResetsThePhaseWhenItStops() {
        let clock = PouredSpotlightRotationClock()
        #expect(!clock.isRunning)
        #expect(clock.elapsedMilliseconds == 0)

        clock.setRunning(true)
        #expect(clock.isRunning)

        // Re-asking is idempotent: a bridge event while several sessions wait
        // must not restart the cycle and re-show item 1.
        clock.advance(to: 5_000)
        clock.setRunning(true)
        #expect(clock.elapsedMilliseconds == 5_000)

        clock.setRunning(false)
        #expect(!clock.isRunning)
        #expect(clock.elapsedMilliseconds == 0)
    }

    // MARK: - The integration

    @Test @MainActor
    func collapsedPouredPillRotatesThroughEveryWaitingSessionAndBackToTheFirst() {
        let model = AppModel()
        model.islandThemeID = "poured"
        model.loadDebugSnapshot(
            IslandDebugScenario.closedAttentionQueue.snapshot(at: Date(timeIntervalSince1970: 1_700_000_000)),
            presentOverlay: false
        )

        let waiting = model.pouredRotationWaitingSessions
        #expect(waiting.count == 2)
        #expect(model.pouredSpotlightRotationIsLive)

        model.pouredSpotlightRotationPhaseOverride = 0
        #expect(model.islandClosedSpotlight?.id == waiting[0].id)
        model.pouredSpotlightRotationPhaseOverride = 3_500
        #expect(model.islandClosedSpotlight?.id == waiting[1].id)
        model.pouredSpotlightRotationPhaseOverride = 7_000
        #expect(model.islandClosedSpotlight?.id == waiting[0].id)

        // The two fixtures are a permission and a question, so the rotation is
        // visible in the pill's *vocabulary*, not just in the session id.
        model.pouredSpotlightRotationPhaseOverride = 0
        let first = model.islandClosedLabel(at: Date(timeIntervalSince1970: 1_700_000_000))
        model.pouredSpotlightRotationPhaseOverride = 3_500
        let second = model.islandClosedLabel(at: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(first != second)
    }

    @Test @MainActor
    func rotationIsConfinedToPouredAndToTheCollapsedIsland() {
        let model = AppModel()
        model.loadDebugSnapshot(
            IslandDebugScenario.closedAttentionQueue.snapshot(at: Date(timeIntervalSince1970: 1_700_000_000)),
            presentOverlay: false
        )
        let waiting = model.pouredRotationWaitingSessions
        #expect(waiting.count == 2)
        model.pouredSpotlightRotationPhaseOverride = 3_500

        // Every other theme keeps the shipped first-waiting winner — R7 is a
        // Poured ruling and the other registered theme stays byte-identical.
        for themeID in ["halo"] {
            model.islandThemeID = themeID
            #expect(!model.pouredSpotlightRotationIsLive)
            #expect(model.islandClosedSpotlight?.id == waiting[0].id)
        }

        // Opening the island shows every waiting session as its own row, so the
        // cycle stops rather than mutating the spotlight behind an open panel.
        model.islandThemeID = "poured"
        #expect(model.islandClosedSpotlight?.id == waiting[1].id)
        model.notchStatus = .opened
        #expect(!model.pouredSpotlightRotationIsLive)
        #expect(model.islandClosedSpotlight?.id == waiting[0].id)
    }

    @Test @MainActor
    func aSingleWaitingSessionNeverRotatesAndNeverRunsTheTimer() {
        let model = AppModel()
        model.islandThemeID = "poured"
        model.loadDebugSnapshot(
            IslandDebugScenario.closedAttention.snapshot(at: Date(timeIntervalSince1970: 1_700_000_000)),
            presentOverlay: false
        )

        #expect(model.pouredRotationWaitingSessions.count == 1)
        #expect(!model.pouredSpotlightRotationIsLive)
        #expect(!model.pouredSpotlightRotationClock.isRunning)

        let spotlight = model.islandClosedSpotlight?.id
        model.pouredSpotlightRotationPhaseOverride = 999_999
        #expect(model.islandClosedSpotlight?.id == spotlight)
    }
}
