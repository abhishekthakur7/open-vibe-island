#if HALO_PARITY_TESTING
import Foundation

/// The closed, versioned scenario namespace consumed by the Gate 0A native
/// harness. Keep this list in lock-step with
/// `Validation/HaloParity/halo-scenarios.json`; unknown IDs are never coerced
/// to a nearby visual state.
enum HaloParityScenarioID: String, CaseIterable, Codable, Sendable {
    case a1 = "A1"
    case a2 = "A2"
    case a2Prime = "A2-prime"
    case a3 = "A3"
    case a4 = "A4"
    case a5 = "A5"
    case a6Interrupted = "A6-interrupted"
    case a6Failed = "A6-failed"
    case b = "B"
    case bPrime = "B-prime"
    case c = "C"
    case d = "D"
    case eTravel = "E-travel"
    case e1 = "E1"
    case e2 = "E2"
    case e3 = "E3"
    case f1 = "F1"
    case f2 = "F2"
    case f3 = "F3"
    case g = "G"
    case gPrime = "G-prime"
    case hSuccess = "H-success"
    case hInterrupted = "H-interrupted"
    case hFailed = "H-failed"
    case i = "I"
    case iPrime = "I-prime"
    case j = "J"
    case jPrime = "J-prime"
    case kOrbit = "K-orbit"
    case kMorph = "K-morph"
    case kCondense = "K-condense"
    case kSuccess = "K-success"
    case kRow = "K-row"
    case kFailure = "K-failure"
    case kIdle = "K-idle"
    case kGlyph = "K-glyph"
    case stressLong = "ST-LONG"
    case stressDuplicate = "ST-DUP"
    case stressMissing = "ST-MISSING"
    case stressCount0 = "ST-COUNT-0"
    case stressCount1 = "ST-COUNT-1"
    case stressCountMany = "ST-COUNT-MANY"
    case stressOverflow = "ST-OVERFLOW"
    case stressUsage0 = "ST-USAGE-0"
    case stressUsageMissing = "ST-USAGE-MISSING"
    case stressAttentionRunning = "ST-ATTN-RUN"
    case stressQuestionPermission = "ST-Q-P"
    case stressIPrimeAttention = "ST-IPRIME-ATTN"
    case accessibilityReduceMotion = "AX-RM"
    case accessibilityIncreaseContrast = "AX-IC"
    case accessibilityReduceTransparency = "AX-RT"
    case accessibilityKeyboard = "AX-KBD"
    case accessibilityVoiceOver = "AX-VO"
    case accessibilityText = "AX-TEXT"
    case displayNotch = "DP-NOTCH"
    case displayTopBar = "DP-TOPBAR"
    case responsive560 = "RESPONSIVE-560"
}

enum HaloParityProfile: String, CaseIterable, Codable, Sendable {
    case notch = "notch-v1"
    case topBar = "top-bar-v1"
}

enum HaloParityManifestDisposition: String, Codable, Equatable, Sendable {
    case exact
    case blocked
    case temporarySurrogate = "temporary-surrogate"
}

extension HaloParityScenarioID {
    /// Locked from Validation/HaloParity/halo-scenarios.json. Every authored
    /// reference state has a dedicated, deterministic native fixture record.
    /// This makes the state reproducible; it does not mark visual parity passed.
    var manifestDisposition: HaloParityManifestDisposition {
        .exact
    }

    var lockedNativeFixtureIdentifier: String? {
        "HaloParityFixtureCatalog.\(rawValue)"
    }
}

enum HaloParityMotionMode: String, CaseIterable, Codable, Sendable {
    case normal
    case reduced
    case manual
}

enum HaloParityAccessibility: String, CaseIterable, Codable, Sendable {
    case standard
    case reduceMotion = "reduce-motion"
    case increaseContrast = "increase-contrast"
    case reduceTransparency = "reduce-transparency"
    case keyboard
    case voiceOver = "voiceover"
    case textScale = "text-scale"
}

enum HaloParityEvent: String, CaseIterable, Codable, Sendable {
    case launch
    case open
    case close
    case hover
    case advanceQuestion = "advance-question"
    case selectOptions = "select-options"
    case submit
    case retriggerSuccess = "retrigger-success"
    case settle
}

struct HaloParityConfiguration: Codable, Equatable, Sendable {
    let scenario: HaloParityScenarioID
    let profile: HaloParityProfile
    let motion: HaloParityMotionMode
    let accessibility: HaloParityAccessibility
    let event: HaloParityEvent?
    let seed: UInt64
    let manualTimeMilliseconds: UInt64?

    func validated() throws -> Self {
        if motion == .manual, manualTimeMilliseconds == nil {
            throw HaloParityConfigurationError.manualMotionRequiresTime
        }
        if motion != .manual, manualTimeMilliseconds != nil {
            throw HaloParityConfigurationError.timeRequiresManualMotion
        }
        if motion == .reduced, accessibility != .reduceMotion {
            throw HaloParityConfigurationError.contradictoryMotionAndAccessibility
        }
        if accessibility == .reduceMotion, motion != .reduced {
            throw HaloParityConfigurationError.contradictoryMotionAndAccessibility
        }
        if scenario == .accessibilityReduceMotion,
           motion != .reduced,
           accessibility != .reduceMotion {
            throw HaloParityConfigurationError.scenarioRequires("AX-RM requires reduced motion")
        }
        if scenario == .accessibilityIncreaseContrast, accessibility != .increaseContrast {
            throw HaloParityConfigurationError.scenarioRequires("AX-IC requires increase-contrast")
        }
        if scenario == .accessibilityReduceTransparency, accessibility != .reduceTransparency {
            throw HaloParityConfigurationError.scenarioRequires("AX-RT requires reduce-transparency")
        }
        if scenario == .displayNotch, profile != .notch {
            throw HaloParityConfigurationError.scenarioRequires("DP-NOTCH requires notch-v1")
        }
        if scenario == .displayTopBar, profile != .topBar {
            throw HaloParityConfigurationError.scenarioRequires("DP-TOPBAR requires top-bar-v1")
        }
        return self
    }
}

enum HaloParityConfigurationError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case unknown(String, String)
    case invalidSeed
    case invalidTime
    case duplicateArgument(String)
    case danglingArgument(String)
    case manualMotionRequiresTime
    case timeRequiresManualMotion
    case contradictoryMotionAndAccessibility
    case scenarioRequires(String)
    case manifestNotCapturable(HaloParityScenarioID, HaloParityManifestDisposition)
    case missingLockedNativeFixture(HaloParityScenarioID)
    case accessibilityEnvironmentMismatch(HaloParityAccessibility)
    case resolvedThemeMismatch(String)
    case manualCanonicalCaptureUnsupported(HaloParityScenarioID)
    case missingPlacementDiagnostics
    case placementProfileMismatch(expected: HaloParityProfile, actual: String)
    case invalidPlacementGeometry
    case bootstrapIsolationUnproven
    case fixtureIsolationMismatch
    case missingExecutableProvenance(String)
    case missingWindowServerPlacement
    case ambiguousWindowServerPlacement(Int)

    var description: String {
        switch self {
        case let .missing(name): "missing required parity input \(name)"
        case let .unknown(name, value): "unknown \(name) value \(value)"
        case .invalidSeed: "halo seed must be an unsigned integer"
        case .invalidTime: "halo time must be an unsigned integer number of milliseconds"
        case let .duplicateArgument(name): "duplicate parity argument \(name)"
        case let .danglingArgument(name): "missing value after \(name)"
        case .manualMotionRequiresTime: "manual motion requires --halo-time-ms"
        case .timeRequiresManualMotion: "--halo-time-ms is only valid with manual motion"
        case .contradictoryMotionAndAccessibility: "reduced motion contradicts the requested accessibility mode"
        case let .scenarioRequires(message): message
        case let .manifestNotCapturable(scenario, disposition):
            "\(scenario.rawValue) is \(disposition.rawValue) in the locked manifest"
        case let .missingLockedNativeFixture(scenario):
            "\(scenario.rawValue) has no locked native fixture"
        case let .accessibilityEnvironmentMismatch(mode):
            "actual OS accessibility environment does not match \(mode.rawValue)"
        case let .resolvedThemeMismatch(themeID):
            "resolved parity theme is \(themeID), expected halo"
        case let .manualCanonicalCaptureUnsupported(scenario):
            "manual canonical capture is unsupported for \(scenario.rawValue) because full-surface animation is not frozen"
        case .missingPlacementDiagnostics:
            "real overlay placement diagnostics are unavailable"
        case let .placementProfileMismatch(expected, actual):
            "resolved overlay placement \(actual) does not match \(expected.rawValue)"
        case .invalidPlacementGeometry:
            "resolved overlay placement has empty screen identity or window geometry"
        case .bootstrapIsolationUnproven:
            "bridge/runtime bootstrap isolation was not proven"
        case .fixtureIsolationMismatch:
            "live model state does not exactly match the isolated fixture"
        case let .missingExecutableProvenance(reason):
            "native executable provenance unavailable: \(reason)"
        case .missingWindowServerPlacement:
            "no visible WindowServer window matches the real overlay placement"
        case let .ambiguousWindowServerPlacement(count):
            "\(count) visible WindowServer windows match the real overlay placement"
        }
    }
}

enum HaloParityLaunchState: Equatable {
    case inactive
    case configured(HaloParityConfiguration)
    case rejected(HaloParityConfigurationError)
}
#endif
