#if HALO_PARITY_TESTING
import Foundation

/// Attests which clock produced a capture. Manual time is a diagnostic phase
/// override only: animation periods and interpolation remain owned by the
/// production Halo views.
enum HaloParityClockAttestation: Codable, Equatable, Sendable {
    case productionMonotonic
    case reducedMotion
    case manualDiagnostic(milliseconds: UInt64, orbitAngle: Double, pulse: Double)

    private enum CodingKeys: String, CodingKey { case mode, milliseconds, orbitAngle, pulse }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(String.self, forKey: .mode) {
        case "production-monotonic": self = .productionMonotonic
        case "reduced-motion": self = .reducedMotion
        case "manual-diagnostic":
            self = .manualDiagnostic(
                milliseconds: try values.decode(UInt64.self, forKey: .milliseconds),
                orbitAngle: try values.decode(Double.self, forKey: .orbitAngle),
                pulse: try values.decode(Double.self, forKey: .pulse)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .mode,
                in: values,
                debugDescription: "Unknown Halo parity clock mode"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .productionMonotonic:
            try values.encode("production-monotonic", forKey: .mode)
        case .reducedMotion:
            try values.encode("reduced-motion", forKey: .mode)
        case let .manualDiagnostic(milliseconds, orbitAngle, pulse):
            try values.encode("manual-diagnostic", forKey: .mode)
            try values.encode(milliseconds, forKey: .milliseconds)
            try values.encode(orbitAngle, forKey: .orbitAngle)
            try values.encode(pulse, forKey: .pulse)
        }
    }
}

enum HaloParityEventClock {
    /// Read by the Halo phase environment's default only in an explicitly
    /// configured debug parity process. Main-actor installation happens before
    /// the comparison window is presented; production and Release never set it.
    nonisolated(unsafe) static var installedManualPhase: HaloEdgePhase?

    static func attestation(for configuration: HaloParityConfiguration) -> HaloParityClockAttestation {
        switch configuration.motion {
        case .normal:
            return .productionMonotonic
        case .reduced:
            return .reducedMotion
        case .manual:
            let milliseconds = configuration.manualTimeMilliseconds ?? 0
            let seconds = Double(milliseconds) / 1_000
            // These are phase projections of the production-owned periods,
            // not replacement animation curves.
            let orbit = (seconds.truncatingRemainder(dividingBy: 6) / 6) * 360
            let pulse = (sin(seconds * 2 * .pi / 1.9) + 1) / 2
            return .manualDiagnostic(milliseconds: milliseconds, orbitAngle: orbit, pulse: pulse)
        }
    }

    static func manualPhase(for configuration: HaloParityConfiguration) -> HaloEdgePhase? {
        guard case let .manualDiagnostic(_, orbitAngle, pulse) = attestation(for: configuration) else {
            return nil
        }
        return HaloEdgePhase(orbitAngle: orbitAngle, pulse: pulse)
    }

    @MainActor
    static func install(configuration: HaloParityConfiguration) {
        installedManualPhase = manualPhase(for: configuration)
    }
}
#endif
