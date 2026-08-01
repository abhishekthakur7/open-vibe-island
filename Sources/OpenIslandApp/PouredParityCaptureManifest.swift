#if POURED_PARITY_TESTING
import Foundation

struct PouredParityBootstrapIsolationProof: Codable, Equatable, Sendable { let runtimeStateLoadingDisabled:Bool; let bridgeStartupDisabled:Bool }
struct PouredParityStateDump: Codable, Equatable, Sendable { let schemaVersion:String; let scenario:PouredParityScenario; let resolvedThemeID:String; let fixture:PouredParityFixtureRecord; let sessionIDs:[String]; let selectedSessionID:String?; let presentation:String; let profile:PouredParityProfile; let accessibility:PouredParityAccessibility; let acknowledgedEvents:[PouredParityEvent]; let clock:PouredParityClockAttestation; let complete:Bool }
struct PouredParityCaptureManifest: Codable, Equatable, Sendable { let schemaVersion:String; let namespace:String; let scenario:PouredParityScenario; let resolvedThemeID:String; let fixtureHash:String; let executablePath:String; let executableSHA256:String; let gitRevision:String; let sourceTreeDirty:Bool; let bundleIdentifier:String; let signingIdentity:String?; let windowServerPlacement:String; let stateDumpSHA256:String; let complete:Bool }

enum PouredParitySidecarWriter {
    static func write(state:PouredParityStateDump, manifest:PouredParityCaptureManifest, to directory:URL) throws {
        guard state.complete, manifest.complete else { throw PouredParityError.incompleteSidecar }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        try atomic(encoder.encode(state),to:directory.appendingPathComponent("poured-state.json"))
        try atomic(encoder.encode(manifest),to:directory.appendingPathComponent("poured-capture-manifest.json"))
    }
    private static func atomic(_ data:Data,to url:URL)throws { let temporary=url.appendingPathExtension("tmp"); try data.write(to:temporary,options:.atomic); if FileManager.default.fileExists(atPath:url.path) { _=try FileManager.default.replaceItemAt(url,withItemAt:temporary,backupItemName:nil,options:[]) } else { try FileManager.default.moveItem(at:temporary,to:url) } }
}
#endif
