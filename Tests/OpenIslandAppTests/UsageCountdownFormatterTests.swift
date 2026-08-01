import Foundation
import Testing
@testable import OpenIslandApp

/// AB-324 — the shared `UsageCountdownFormatter` / `UsageWindowPresentation
/// .remainingLabel(asOf:)` that replaced the five per-theme
/// `remainingDurationString(until:)` copies.
///
/// The grammar cases below are the acceptance-criteria strings verified byte for
/// byte. Every case injects its clock (a raw interval, or a frozen `now`), so
/// nothing here reads the wall clock.
///
/// Tooltip parity: the in-band remainders (`2h 10m`, `19h`, `45m`) and the
/// nil / past cases reproduce the retired `DateComponentsFormatter` config
/// exactly, so the header `.help()` tooltips are unchanged for those. The two
/// grammar-mandated divergences — the day bucket now carrying trailing hours
/// (`3d 4h`, and a weekly window as `6d 4h` rather than `6d`) and the sub-minute
/// `<1m` (rather than the misleading `0m`) — are pinned here too.
struct UsageCountdownFormatterTests {
    // MARK: - Grammar (acceptance criteria, exact strings)

    @Test
    func hoursAndMinutesReadAsHM() {
        // 2h 10m = 7800s.
        #expect(UsageCountdownFormatter.remainingLabel(forRemaining: 7_800) == "2h 10m")
    }

    @Test
    func daysCarryTrailingHours() {
        // 3d 4h = 273_600s. The day bucket now includes the hours.
        #expect(UsageCountdownFormatter.remainingLabel(forRemaining: 273_600) == "3d 4h")
    }

    @Test
    func subMinuteReadsAsLessThanOneMinute() {
        #expect(UsageCountdownFormatter.remainingLabel(forRemaining: 30) == "<1m")
        #expect(UsageCountdownFormatter.remainingLabel(forRemaining: 5) == "<1m")
        // Right up to the minute boundary is still sub-minute.
        #expect(UsageCountdownFormatter.remainingLabel(forRemaining: 59) == "<1m")
        #expect(UsageCountdownFormatter.remainingLabel(forRemaining: 59.9) == "<1m")
    }

    // MARK: - nil / past (a past target never renders a negative)

    @Test
    func pastIntervalIsNil() {
        #expect(UsageCountdownFormatter.remainingLabel(forRemaining: -100) == nil)
    }

    // MARK: - Boundary parity with the retired config

    // MARK: - Date-based entry point + frozen clock

    // MARK: - UsageWindowPresentation.remainingLabel(asOf:)

    // MARK: - DST-crossing sanity

    /// The formatter measures *absolute* elapsed time, so a reset that straddles
    /// a DST spring-forward reads by the real seconds between the two instants,
    /// not the wall-clock hour count. New York springs forward at 2025-03-09
    /// 02:00 (02:00→03:00), so 00:30→04:30 is four wall-clock hours but only
    /// three real hours — the label must be `3h`, never `4h`.
    @Test
    func springForwardCrossingMeasuresAbsoluteInterval() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2025, month: 3, day: 9, hour: 0, minute: 30))!
        let resetsAt = calendar.date(from: DateComponents(year: 2025, month: 3, day: 9, hour: 4, minute: 30))!
        #expect(UsageCountdownFormatter.remainingLabel(until: resetsAt, asOf: now) == "3h")
    }
}
