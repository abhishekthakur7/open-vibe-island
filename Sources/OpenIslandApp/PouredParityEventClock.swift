#if POURED_PARITY_TESTING
import Foundation

struct PouredParityClockAttestation: Codable, Equatable, Sendable { let fixedEpochMilliseconds:UInt64; let seed:UInt64; let manualTimeMilliseconds:UInt64?; let consumedByPouredViews:Bool }
enum PouredParityEventClock {
    static func attestation(_ configuration:PouredParityConfiguration)->PouredParityClockAttestation { .init(fixedEpochMilliseconds:configuration.epochMilliseconds,seed:configuration.seed,manualTimeMilliseconds:configuration.manualTimeMilliseconds,consumedByPouredViews:false) }
}
#endif
