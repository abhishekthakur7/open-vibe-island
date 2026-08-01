#if POURED_PARITY_TESTING
import Foundation

enum PouredParityScenario: String, CaseIterable, Codable, Sendable {
    case a2WorkingOne = "A2-working-one"
    case a2mWorkingMany = "A2m-working-many"
    case a3Permission = "A3-permission"
    case e1CommandPermission = "E1-command-permission"
    case h1Completed = "H1-completed"
    // PI-V-001: the §C grouped list. `diagnostic-partial` like every other case
    // — a deterministic fixture is not capture authority.
    case c1GroupedSix = "C1-grouped-six"
    // PI-B-001: the §B hover peek. `diagnostic-partial` like every other case —
    // and doubly so here, because the driver reaches the peek *endpoint*
    // directly and never runs the 0.15s dwell (see `applyConfiguredEvent`).
    case b1HoverPeek = "B1-hover-peek"
}

enum PouredParityProfile: String, CaseIterable, Codable, Sendable { case notch = "notch-v1"; case topBar = "top-bar-v1" }
enum PouredParityAccessibility: String, CaseIterable, Codable, Sendable { case standard; case reduceMotion = "reduce-motion"; case reduceTransparency = "reduce-transparency"; case increaseContrast = "increase-contrast"; case keyboard; case voiceOver = "voiceover" }
enum PouredParityEvent: String, CaseIterable, Codable, Sendable { case open; case close; case hover; case reverse; case settle; case rowMutation = "row-mutation"; case success = "success" }

struct PouredParityConfiguration: Codable, Equatable, Sendable {
    let scenario: PouredParityScenario
    let profile: PouredParityProfile
    let accessibility: PouredParityAccessibility
    let event: PouredParityEvent?
    let seed: UInt64
    let epochMilliseconds: UInt64
    let manualTimeMilliseconds: UInt64?

    func validated() throws -> Self {
        if seed == 0 { throw PouredParityError.invalidSeed }
        if epochMilliseconds == 0 { throw PouredParityError.invalidEpoch }
        return self
    }

    static func launchState(environment: [String:String], arguments: [String]) -> PouredParityLaunchState {
        let enabled = arguments.contains("--poured-parity") || ["1","true","yes","on"].contains(environment["OPEN_ISLAND_POURED_PARITY"]?.lowercased() ?? "")
        guard enabled else { return .inactive }
        let names = ["--poured-scenario","--poured-profile","--poured-accessibility","--poured-event","--poured-seed","--poured-epoch-ms","--poured-time-ms"]
        var values: [String:String] = [:]; var index = 0
        while index < arguments.count {
            let name = arguments[index]
            if names.contains(name) {
                guard values[name] == nil else { return .rejected(.duplicateArgument(name)) }
                guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else { return .rejected(.missing(name)) }
                values[name] = arguments[index + 1]; index += 2
            } else { index += 1 }
        }
        func value(_ name:String,_ key:String)->String? { values[name] ?? environment[key] }
        guard let scenarioRaw=value("--poured-scenario","OPEN_ISLAND_POURED_SCENARIO") else { return .rejected(.missing("--poured-scenario")) }
        guard let profileRaw=value("--poured-profile","OPEN_ISLAND_POURED_PROFILE") else { return .rejected(.missing("--poured-profile")) }
        guard let a11yRaw=value("--poured-accessibility","OPEN_ISLAND_POURED_ACCESSIBILITY") else { return .rejected(.missing("--poured-accessibility")) }
        guard let seedRaw=value("--poured-seed","OPEN_ISLAND_POURED_SEED"), let seed=UInt64(seedRaw) else { return .rejected(.invalidSeed) }
        guard let epochRaw=value("--poured-epoch-ms","OPEN_ISLAND_POURED_EPOCH_MS"), let epoch=UInt64(epochRaw) else { return .rejected(.invalidEpoch) }
        guard let scenario=PouredParityScenario(rawValue:scenarioRaw) else { return .rejected(.unknown("--poured-scenario",scenarioRaw)) }
        guard let profile=PouredParityProfile(rawValue:profileRaw) else { return .rejected(.unknown("--poured-profile",profileRaw)) }
        guard let accessibility=PouredParityAccessibility(rawValue:a11yRaw) else { return .rejected(.unknown("--poured-accessibility",a11yRaw)) }
        let eventRaw=value("--poured-event","OPEN_ISLAND_POURED_EVENT"); let event=PouredParityEvent(rawValue:eventRaw ?? "")
        if eventRaw != nil && event == nil { return .rejected(.unknown("--poured-event",eventRaw!)) }
        let timeRaw=value("--poured-time-ms","OPEN_ISLAND_POURED_TIME_MS"); let time=timeRaw.flatMap(UInt64.init)
        if timeRaw != nil && time == nil { return .rejected(.invalidTime) }
        do { return .configured(try Self(scenario:scenario,profile:profile,accessibility:accessibility,event:event,seed:seed,epochMilliseconds:epoch,manualTimeMilliseconds:time).validated()) }
        catch let error as PouredParityError { return .rejected(error) }
        catch { return .rejected(.unknown("configuration",error.localizedDescription)) }
    }
}

enum PouredParityLaunchState: Equatable { case inactive; case configured(PouredParityConfiguration); case rejected(PouredParityError) }
enum PouredParityError: Error, Equatable, CustomStringConvertible {
    case missing(String), unknown(String,String), duplicateArgument(String), invalidSeed, invalidEpoch, invalidTime
    case partialFixture(PouredParityScenario), wrongTheme(String), accessibilityMismatch(PouredParityAccessibility), liveDataContamination, fixtureMismatch, unsupportedEvent(PouredParityEvent), manualClockNotConsumed, missingPlacement, staleExecutable, incompleteSidecar
    var description: String { switch self {
    case .missing(let value): "missing required Poured input \(value)"; case .unknown(let name,let value): "unknown \(name) value \(value)"; case .duplicateArgument(let value): "duplicate argument \(value)"; case .invalidSeed:"seed must be nonzero UInt64"; case .invalidEpoch:"epoch must be nonzero UInt64 milliseconds"; case .invalidTime:"time must be UInt64 milliseconds"; case .partialFixture(let value):"\(value.rawValue) is diagnostic-partial, not canonical"; case .wrongTheme(let value):"resolvedThemeID is \(value), expected poured"; case .accessibilityMismatch(let value):"accessibility environment does not attest \(value.rawValue)"; case .liveDataContamination:"fixture contains non-demo sessions"; case .fixtureMismatch:"live state differs from fixture"; case .unsupportedEvent(let value):"unsupported production event \(value.rawValue)"; case .manualClockNotConsumed:"Poured views do not consume the manual clock"; case .missingPlacement:"WindowServer placement is missing"; case .staleExecutable:"executable provenance is stale or dirty"; case .incompleteSidecar:"sidecar completion marker is missing" }
    }
}
#endif
