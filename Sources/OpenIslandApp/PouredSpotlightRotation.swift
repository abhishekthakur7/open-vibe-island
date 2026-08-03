import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - The rule (pure)

/// R7 — the collapsed pill's multi-waiting spotlight rotation (PI-A-002).
///
/// Owner ruling R7 (`docs/design/overlay-redesign/poured-owner-rulings.md`):
///
/// > "if multiple are waiting, loop through them one at a time. may be wait 3-4
/// > seconds for 1 then move to 2nd one and then again back to 1 depending upon
/// > how many are waiting."
///
/// The board renders **no** N > 1 waiting collapsed frame (R6 · N-7 —
/// `--aggregate` / `--attn-hot` are tokenised and never drawn), so the ruling is
/// the whole authority here and the unrendered details were adjudicated by the
/// Slice 5 root packet rather than measured:
///
/// - rotation runs only at **N ≥ 2** (one waiting session is not a cycle);
/// - each item is held **3.5 s**, inside the ruled 3–4 s band;
/// - the cycle is a plain round-robin `1 → 2 → … → 1` over the waiting sessions
///   in the spotlight resolver's own stable order (`AppModel.surfacedSessions`
///   filtered by `phase.requiresAttention`), so pill, peek and list agree;
/// - the badge follows the **spotlighted item's** template, not the aggregate:
///   owner ruling **R12** (2026-08-03) makes a question hold render the
///   A4-verbatim gold `?` while a permission hold keeps A3's amber count. The
///   total stays reachable through the hover peek and the pill's VoiceOver
///   summary (`poured.a11y.rightSlot.attention.mixed`);
/// - the swap is the sequential fade below (X1) — the outgoing item reaches zero
///   and stays there before the incoming one starts, and lead marker, badge and
///   label all commit in the SAME transaction so no frame can mix two items;
/// - under Reduce Motion the cycle keeps running (it is informational, not
///   decorative) and only the swap stops being animated.
///
/// Everything here is a pure function of `(waitingCount, elapsedMs)` so the
/// rotation phase can be pinned exactly — by a unit test, or by the parity
/// driver's `--poured-time-ms` manual clock — without standing up a timer.
enum PouredSpotlightRotation: Sendable {

    /// How long one waiting session holds the spotlight. R7 says "3-4 seconds";
    /// 3.5 s is the midpoint and is the value the Slice 5 packet adjudicated.
    static let holdMilliseconds = 3_500

    /// Rotation is a *multi*-waiting affordance. Below this the pill keeps the
    /// shipped single-winner behaviour byte-for-byte.
    static let minimumWaitingCount = 2

    /// Whether the cycle runs at all for `waitingCount` sessions.
    static func isActive(waitingCount: Int) -> Bool {
        waitingCount >= minimumWaitingCount
    }

    /// The index into the waiting sessions that holds the spotlight after
    /// `elapsedMs` of rotation.
    ///
    /// Returns `0` whenever the cycle is inactive, which is exactly the shipped
    /// "first waiting session" winner — so a single waiting session, and the
    /// first hold of any cycle, render identically to before this ruling.
    /// Negative elapsed time (a clock that ran backwards, or a manual phase
    /// below zero) clamps to the first item rather than wrapping into a
    /// negative modulus.
    static func index(waitingCount: Int, elapsedMs: Int) -> Int {
        guard isActive(waitingCount: waitingCount) else { return 0 }
        let elapsed = max(0, elapsedMs)
        return (elapsed / holdMilliseconds) % waitingCount
    }

    /// The full cycle length in milliseconds — one hold per waiting session.
    /// `0` when the cycle is inactive.
    static func cycleMilliseconds(waitingCount: Int) -> Int {
        isActive(waitingCount: waitingCount) ? waitingCount * holdMilliseconds : 0
    }

    // MARK: R3 / X1 — the swap

    /// R3 (root amendment, correction round 2): one leg of the swap.
    ///
    /// The original design reused the pill's 0.45 s layout **crossfade**, which
    /// double-exposes: for roughly the middle third of the transition both the
    /// outgoing and the incoming sentence are legible at once, and the pill reads
    /// as two overlapping claims. The swap is therefore sequential — fade the
    /// outgoing label out over `swapFadeSeconds`, *then* fade the incoming one in
    /// over the same — so exactly one label is ever legible. `0.2 + 0.2 = 0.4`,
    /// inside the ruled `≤ 0.45 s` total.
    static let swapFadeSeconds: TimeInterval = 0.2

    /// The whole swap, both legs. Pinned so the ≤ 0.45 s budget is a test, not a
    /// comment.
    static var swapSeconds: TimeInterval { swapFadeSeconds * 2 }

    /// X1: the budget the root adjudication set for a whole swap.
    static let swapBudgetSeconds: TimeInterval = 0.45

    /// R3: Reduce Motion keeps the **instant** swap — the cycle itself is
    /// informational and keeps running; only the animation is dropped.
    static func swapFadeSeconds(reduceMotion: Bool) -> TimeInterval? {
        reduceMotion ? nil : swapFadeSeconds
    }

    /// X1: one leg's curve, stated **once**.
    ///
    /// Both the model-side `withAnimation` that mutates the shared opacity and
    /// the view-side `.animation(_:value:)` that guarantees no outer modifier can
    /// nullify it read this, so the pill's label, its lead marker (drawn by the
    /// morph overlay) and the ambient glow cannot end up on three subtly
    /// different curves — which is how round 2's 0.15 s desync started.
    static func swapAnimation(fadingOut: Bool) -> Animation {
        fadingOut ? .easeOut(duration: swapFadeSeconds) : .easeIn(duration: swapFadeSeconds)
    }

    // MARK: X1 — one phase clock

    /// X1: the swap as a pure two-step state machine, so the sequencing is a
    /// unit test rather than a video measurement.
    ///
    /// Round 2 ran the fade inside `PouredClosedPill` against the pill's own
    /// 0.45 s layout crossfade — two drivers on one property — and left the lead
    /// marker, the right-slot badge and the ambient glow on a *third* driver
    /// (they read the model directly and flipped the instant the spotlight moved,
    /// ~0.15 s before the label caught up). Reviewers measured both faults: the
    /// outgoing label re-entering at ≈35 % for ≈140 ms, and a 0.64 s total.
    ///
    /// The fix is to make the item flip a **model** event that every consumer
    /// sees in one transaction, and to give that transaction one opacity. This
    /// enum is that schedule:
    ///
    /// 1. `fadeOut` — the target index moved; drive the shared opacity `1 → 0`
    ///    over `swapFadeSeconds`. The displayed index has NOT moved, so the pill
    ///    is still item A all the way down.
    /// 2. `commit` — one runloop transaction: adopt the new index (label, lead
    ///    marker, badge and glow all change together, while invisible) and drive
    ///    the opacity `0 → 1` over `swapFadeSeconds`.
    ///
    /// Zero overlap is structural: nothing of item B is ever drawn above opacity
    /// 0 until every part of item A has been replaced.
    enum SwapStep: Equatable, Sendable {
        /// Nothing to do — the displayed item is already the target.
        case settled
        /// Adopt the target immediately, no animation (Reduce Motion, a
        /// deterministic parity phase, or the first frame of a cycle).
        case snap
        /// Begin the outgoing leg; commit after `swapFadeSeconds`.
        case fadeOut
    }

    /// What the clock should do, given where it is and where it wants to be.
    ///
    /// `isSwapping` guards re-entrancy: a 4 Hz tick can fire twice inside one
    /// 0.4 s swap, and restarting the fade mid-flight is exactly the stutter
    /// this round is removing.
    static func swapStep(
        displayedIndex: Int,
        targetIndex: Int,
        isSwapping: Bool,
        reduceMotion: Bool
    ) -> SwapStep {
        guard displayedIndex != targetIndex else { return .settled }
        if reduceMotion { return .snap }
        guard !isSwapping else { return .settled }
        return .fadeOut
    }

    // MARK: R2 — constant silhouette

    /// R2: the label a rotating pill sizes itself to — the **widest** item in the
    /// cycle, so the silhouette holds still while the content swaps.
    ///
    /// The board renders A3 and A4 at one identical 352 × 40 geometry
    /// (`mapper-reference.md` §7.1/§7.2), which is board authority that the
    /// waiting pill's outline does not track its content. `measure` is injected
    /// (in practice `V6CenterLabelView.intrinsicWidth`) so the choice is pure and
    /// testable without a text renderer.
    ///
    /// Returns `nil` for an empty set, or when there is nothing to hold still for.
    static func widthReferenceLabel(
        _ labels: [String],
        measuredBy measure: (String) -> CGFloat
    ) -> String? {
        let candidates = labels.filter { !$0.isEmpty }
        guard candidates.count > 1 else { return candidates.first }
        // Ties break on the label itself, so the reference is deterministic and a
        // capture at any phase of the cycle sizes identically.
        var best: String = candidates[0]
        var bestWidth: CGFloat = measure(best)
        for candidate in candidates.dropFirst() {
            let width = measure(candidate)
            if width > bestWidth || (width == bestWidth && candidate > best) {
                best = candidate
                bestWidth = width
            }
        }
        return best
    }
}

// MARK: - The live phase source

/// Publishes the elapsed rotation phase `PouredSpotlightRotation` consumes.
///
/// Built on the `PulseClock` precedent (AB-228) rather than a `TimelineView`:
/// the collapsed pill is **not** inside any timeline — `IslandPanelView`'s
/// `v6ClosedSurface` calls `model.islandClosedLabel()` / `islandClosedActivity()`
/// directly — so its re-render depends purely on Observation invalidation of an
/// `AppModel` property. Publishing the phase here and reading it from
/// `AppModel.islandClosedSpotlight` therefore rotates the pill with **no edit to
/// `IslandPanelView` at all**.
///
/// The timer runs only while `AppModel` says the cycle is live (Poured, island
/// collapsed, ≥ 2 sessions waiting), so an idle or single-waiting app pays
/// nothing. 4 Hz keeps the observed swap within 250 ms of the 3.5 s boundary at
/// roughly a quarter of `PulseClock`'s cost.
@MainActor
@Observable
final class PouredSpotlightRotationClock: NSObject {

    /// Milliseconds since the current cycle started. `0` while stopped.
    private(set) var elapsedMilliseconds: Int = 0

    /// X1: the item actually **on screen**, which lags the phase's own index by
    /// the fade-out leg of a swap. Every collapsed-pill consumer — label, lead
    /// marker, right-slot badge, ambient glow — reads the spotlight this index
    /// selects, so they can only ever change together.
    private(set) var displayedIndex: Int = 0

    /// X1: the shared opacity of everything the rotation swaps. Mutated inside
    /// `withAnimation`, so every observing view animates in one transaction
    /// rather than each running its own timer.
    private(set) var contentOpacity: Double = 1

    /// How many sessions the cycle rotates through. Pushed in by `AppModel`
    /// (rather than pulled) so a tick never has to reach back into the model.
    @ObservationIgnored var waitingCount: Int = 0
    /// R3: Reduce Motion — the cycle keeps running (it is informational); only
    /// the fade is dropped, and the item swaps instantly.
    ///
    /// Read straight off `NSWorkspace`, the same route `UnifiedBars` takes for
    /// its own CA-driven glyph, so flipping the toggle live takes effect on the
    /// very next hold without waiting for a session mutation to push it in. The
    /// override exists purely so a unit test can pin either branch.
    @ObservationIgnored var reduceMotionOverride: Bool?

    var reduceMotion: Bool {
        reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var swapTask: Task<Void, Never>?

    private static let frequency: TimeInterval = 0.25

    var isRunning: Bool { timer != nil }

    /// X1: `true` between the start of a fade-out and the end of the following
    /// fade-in — the window `swapStep` must not restart.
    var isSwapping: Bool { swapTask != nil }

    /// Starts the cycle if it is not already running. Deliberately idempotent:
    /// a session list that mutates while several sessions are waiting must not
    /// restart the phase and re-show item 1 on every bridge event.
    func start(now: Date = .now) {
        guard timer == nil else { return }
        startedAt = now
        elapsedMilliseconds = 0

        // Target/selector (rather than a closure) sidesteps Swift 6 Sendable
        // checking on `Timer`'s closure-based initializers — the same reason
        // `PulseClock` does it. The callback still fires on `RunLoop.main`.
        let newTimer = Timer(
            timeInterval: Self.frequency,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    /// Stops the cycle and resets the phase, so the next cycle opens on the
    /// first waiting session exactly as the shipped single-winner pill does.
    func stop() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
        swapTask?.cancel()
        swapTask = nil
        if elapsedMilliseconds != 0 { elapsedMilliseconds = 0 }
        if displayedIndex != 0 { displayedIndex = 0 }
        if contentOpacity != 1 { contentOpacity = 1 }
    }

    func setRunning(_ running: Bool) {
        running ? start() : stop()
    }

    /// Test seam for the elapsed reading without a real timer. Advancing the
    /// phase also runs the swap schedule, so a test can pin the whole sequence.
    func advance(to milliseconds: Int) {
        elapsedMilliseconds = max(0, milliseconds)
        syncDisplayedIndex()
    }

    /// X1 test seam: adopt the phase's index with no animation at all — what a
    /// deterministic parity capture and Reduce Motion both want.
    func snapToPhase() {
        swapTask?.cancel()
        swapTask = nil
        displayedIndex = PouredSpotlightRotation.index(
            waitingCount: waitingCount,
            elapsedMs: elapsedMilliseconds
        )
        contentOpacity = 1
    }

    @objc private func tick() {
        guard let startedAt else { return }
        elapsedMilliseconds = max(0, Int(Date.now.timeIntervalSince(startedAt) * 1_000))
        syncDisplayedIndex()
    }

    /// X1: the one place the displayed item changes.
    ///
    /// Everything the collapsed pill swaps is a function of `displayedIndex`, so
    /// committing it inside a single synchronous block (together with the
    /// opacity's fade-in) puts label, lead marker, badge and glow in ONE SwiftUI
    /// transaction. The 0.15 s marker/label desync round 2 shipped is not
    /// "tightened" here — it is made structurally unrepresentable.
    private func syncDisplayedIndex() {
        let target = PouredSpotlightRotation.index(
            waitingCount: waitingCount,
            elapsedMs: elapsedMilliseconds
        )
        switch PouredSpotlightRotation.swapStep(
            displayedIndex: displayedIndex,
            targetIndex: target,
            isSwapping: isSwapping,
            reduceMotion: reduceMotion
        ) {
        case .settled:
            return
        case .snap:
            displayedIndex = target
            contentOpacity = 1
        case .fadeOut:
            beginSwap()
        }
    }

    private func beginSwap() {
        let fade = PouredSpotlightRotation.swapFadeSeconds
        withAnimation(PouredSpotlightRotation.swapAnimation(fadingOut: true)) { contentOpacity = 0 }
        swapTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(fade * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            // The commit. Both mutations flush in the same runloop iteration, so
            // the incoming item is already fully in place on the first frame the
            // fade-in draws — there is no instant at which item A's marker sits
            // beside item B's label.
            self.displayedIndex = PouredSpotlightRotation.index(
                waitingCount: self.waitingCount,
                elapsedMs: self.elapsedMilliseconds
            )
            withAnimation(PouredSpotlightRotation.swapAnimation(fadingOut: false)) { self.contentOpacity = 1 }
            self.swapTask = nil
        }
    }
}
