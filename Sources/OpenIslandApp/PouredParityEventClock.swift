#if POURED_PARITY_TESTING
import Foundation

struct PouredParityClockAttestation: Codable, Equatable, Sendable { let fixedEpochMilliseconds:UInt64; let seed:UInt64; let manualTimeMilliseconds:UInt64?; let consumedByPouredViews:Bool }
enum PouredParityEventClock {
    /// R7 / PI-A-002 · the manual clock's one production consumer.
    ///
    /// Mirrors `HaloParityEventClock.installedManualPhase`: an explicitly
    /// configured debug parity process installs a fixed phase before the
    /// comparison window is presented; production and Release never set it.
    /// Halo's consumer was a leaf view, so it reached this through an
    /// `EnvironmentKey` default (`IslandSurfaceEdge.HaloEdgePhaseKey`); the
    /// Poured spotlight rotation resolves on `AppModel`
    /// (`islandClosedSpotlight`), so the driver hands the phase straight to
    /// `AppModel.pouredSpotlightRotationPhaseOverride` rather than adding an
    /// environment hop no view would read.
    nonisolated(unsafe) static var installedRotationPhaseMilliseconds:Int?

    /// `consumedByPouredViews` is now derived rather than hardcoded `false`:
    /// `--poured-time-ms` drives `PouredSpotlightRotation.index(waitingCount:elapsedMs:)`
    /// through the override above, so a manual-clock launch really does pin the
    /// rendered rotation phase. It stays an *attestation*, not a licence —
    /// `PouredParityDriver.captureManifest` still refuses to emit a manifest
    /// whenever a manual clock is configured, so manual-clock stills never
    /// claim canonical pixels.
    static func attestation(_ configuration:PouredParityConfiguration)->PouredParityClockAttestation { .init(fixedEpochMilliseconds:configuration.epochMilliseconds,seed:configuration.seed,manualTimeMilliseconds:configuration.manualTimeMilliseconds,consumedByPouredViews:configuration.manualTimeMilliseconds != nil) }

    @MainActor
    static func install(configuration:PouredParityConfiguration) { installedRotationPhaseMilliseconds = configuration.manualTimeMilliseconds.map { Int(clamping:$0) } }
}
#endif
