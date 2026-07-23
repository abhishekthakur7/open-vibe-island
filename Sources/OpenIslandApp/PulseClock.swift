import Foundation
import Observation

/// Shared 15fps "pulse" clock for the animated status dot (AB-228).
///
/// Before this, every row showing an animated dot (each running or
/// actionable session) spun its own `TimelineView(.periodic(from: .now, by:
/// 1/15))`, so N running/actionable sessions meant N independent 15fps
/// timelines all ticking at once. This single shared clock publishes one
/// `phase` value instead; only the small leaf view that actually reads
/// `phase` (`PulsingStatusDot` in `IslandPanelView.swift`) gets invalidated
/// on each tick — Observation tracks property access per-view, so the
/// row/list around it is untouched — and the visual result (a soft breathing
/// pulse) is unchanged.
///
/// The underlying `Timer` is ref-counted via `acquire`/`release` and only
/// runs while at least one dot is actually animating, so a session list with
/// no running/actionable rows costs nothing.
@MainActor
@Observable
final class PulseClock: NSObject {
    private(set) var phase: Double = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var subscriberCount = 0

    private static let frequency: TimeInterval = 1.0 / 15.0

    /// Call when a view that animates off `phase` appears on screen.
    func acquire() {
        subscriberCount += 1
        startIfNeeded()
    }

    /// Call when that view disappears (or stops needing the pulse).
    /// Balances a prior `acquire()`; the timer stops once nothing is left
    /// subscribed.
    func release() {
        subscriberCount = max(0, subscriberCount - 1)
        guard subscriberCount == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private func startIfNeeded() {
        guard timer == nil else { return }

        // Target/selector (rather than a closure) sidesteps Swift 6 Sendable
        // checking on `Timer`'s closure-based initializers entirely — the
        // ObjC runtime dispatch is invisible to the concurrency checker, and
        // the callback still fires synchronously on `RunLoop.main` (the mode
        // it's added under), i.e. on the main thread, same as every other
        // MainActor-isolated call in this class.
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

    @objc private func tick() {
        phase = (sin(Date.now.timeIntervalSinceReferenceDate * 3.2) + 1) / 2
    }
}
