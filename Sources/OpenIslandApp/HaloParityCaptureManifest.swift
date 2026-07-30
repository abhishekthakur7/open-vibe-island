#if HALO_PARITY_TESTING
import AppKit
import CryptoKit
import Darwin
import Foundation
import OpenIslandCore

struct HaloParityBootstrapIsolationProof: Codable, Equatable, Sendable {
    let runtimeStateLoadingDisabled: Bool
    let bridgeStartupDisabled: Bool
}

struct HaloParityLiveDataIsolationProof: Codable, Equatable, Sendable {
    let runtimeStateLoadingDisabled: Bool
    let bridgeStartupDisabled: Bool
    let allSessionsAreDemoOrigin: Bool
    let fixtureSessionIDs: [String]
}

struct HaloParityExecutableProvenance: Codable, Equatable, Sendable {
    let path: String
    let sha256: String
    let buildId: String
    let configuration: String
    let gitRevision: String
    let sourceTreeDirty: Bool

    static func resolve(configuration: String) throws -> Self {
        guard let executableURL = currentExecutableURL() else {
            throw HaloParityConfigurationError.missingExecutableProvenance(
                "_NSGetExecutablePath did not resolve the running image"
            )
        }
        let executableData: Data
        do {
            executableData = try Data(contentsOf: executableURL, options: .mappedIfSafe)
        } catch {
            throw HaloParityConfigurationError.missingExecutableProvenance(
                "cannot read executable: \(error)"
            )
        }
        let digest = SHA256.hash(data: executableData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard let buildID = machOUUID(in: executableData) else {
            throw HaloParityConfigurationError.missingExecutableProvenance(
                "Mach-O LC_UUID is missing or unsupported"
            )
        }
        guard let repository = repository(near: executableURL) else {
            throw HaloParityConfigurationError.missingExecutableProvenance(
                "no verifiable git HEAD is reachable from the executable"
            )
        }
        return Self(
            path: executableURL.path,
            sha256: digest,
            buildId: buildID,
            configuration: configuration,
            gitRevision: repository.revision,
            sourceTreeDirty: sourceTreeIsDirty(at: repository.root)
        )
    }

    private static func currentExecutableURL() -> URL? {
        var capacity: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &capacity)
        guard capacity > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(capacity))
        guard _NSGetExecutablePath(&buffer, &capacity) == 0 else { return nil }
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        let path = String(
            decoding: buffer[..<end].map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        return URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
    }

    private static func machOUUID(in data: Data) -> String? {
        // Canonical capture executes the native slice. Fail closed for a fat
        // container instead of guessing which architecture supplied the UUID.
        guard data.count >= 32, readUInt32LE(data, at: 0) == 0xfeedfacf else {
            return nil
        }
        let commandCount = Int(readUInt32LE(data, at: 16))
        var offset = 32
        for _ in 0..<commandCount {
            guard offset + 8 <= data.count else { return nil }
            let command = readUInt32LE(data, at: offset)
            let size = Int(readUInt32LE(data, at: offset + 4))
            guard size >= 8, offset + size <= data.count else { return nil }
            if command == 0x1b, size >= 24 {
                let bytes = Array(data[(offset + 8)..<(offset + 24)])
                return String(
                    format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                    bytes[0], bytes[1], bytes[2], bytes[3],
                    bytes[4], bytes[5], bytes[6], bytes[7],
                    bytes[8], bytes[9], bytes[10], bytes[11],
                    bytes[12], bytes[13], bytes[14], bytes[15]
                )
            }
            offset += size
        }
        return nil
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func repository(
        near executableURL: URL
    ) -> (root: URL, revision: String)? {
        var candidate = executableURL.deletingLastPathComponent()
        for _ in 0..<12 {
            let dotGit = candidate.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: dotGit.path),
               let gitDirectory = resolveGitDirectory(dotGit, worktree: candidate),
               let revision = readGitHEAD(gitDirectory) {
                return (candidate, revision)
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        return nil
    }

    private static func sourceTreeIsDirty(at repositoryRoot: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--",
            "Package.swift",
            "Package.resolved",
            "Sources",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return true }
            return !output.fileHandleForReading.readDataToEndOfFile().isEmpty
        } catch {
            return true
        }
    }

    private static func resolveGitDirectory(_ dotGit: URL, worktree: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue { return dotGit }
        guard let contents = try? String(contentsOf: dotGit, encoding: .utf8),
              contents.hasPrefix("gitdir:") else {
            return nil
        }
        let rawPath = contents.dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: rawPath, relativeTo: worktree)
        return url.standardizedFileURL
    }

    private static func readGitHEAD(_ gitDirectory: URL) -> String? {
        let headURL = gitDirectory.appendingPathComponent("HEAD")
        guard let rawHead = try? String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        if !rawHead.hasPrefix("ref: ") {
            return validatedRevision(rawHead)
        }
        let reference = String(rawHead.dropFirst("ref: ".count))
        let referenceURL = gitDirectory.appendingPathComponent(reference)
        if let loose = try? String(contentsOf: referenceURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let revision = validatedRevision(loose) {
            return revision
        }
        let packedRefsURL = gitDirectory.appendingPathComponent("packed-refs")
        guard let packedRefs = try? String(contentsOf: packedRefsURL, encoding: .utf8) else {
            return nil
        }
        for line in packedRefs.split(separator: "\n") where !line.hasPrefix("#") && !line.hasPrefix("^") {
            let fields = line.split(separator: " ", maxSplits: 1)
            if fields.count == 2, fields[1] == reference {
                return validatedRevision(String(fields[0]))
            }
        }
        return nil
    }

    private static func validatedRevision(_ value: String) -> String? {
        guard (value.count == 40 || value.count == 64),
              value.allSatisfy(\.isHexDigit) else {
            return nil
        }
        return value.lowercased()
    }
}

struct HaloParityProcessProvenance: Codable, Equatable, Sendable {
    let pid: Int32
    let startTime: Date
    let bundleId: String
}

struct HaloParityFixtureProvenance: Codable, Equatable, Sendable {
    let id: String
    let payloadSha256: String
    let liveDataAbsent: Bool
}

struct HaloParityWindowServerWindow: Equatable, Sendable {
    let cgWindowId: UInt32
    let layer: Int
    let bounds: CGRect

    static func resolve(
        processID: Int32,
        expectedAppKitFrame: CGRect
    ) throws -> Self {
        guard let records = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            throw HaloParityConfigurationError.missingWindowServerPlacement
        }
        let matches = records.compactMap { record -> Self? in
            guard
                (record[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID,
                (record[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true,
                let identifier = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let layer = (record[kCGWindowLayer as String] as? NSNumber)?.intValue,
                let boundsDictionary = record[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary
                ),
                abs(bounds.width - expectedAppKitFrame.width) <= 0.5,
                abs(bounds.height - expectedAppKitFrame.height) <= 0.5
            else {
                return nil
            }
            return Self(cgWindowId: identifier, layer: layer, bounds: bounds)
        }
        guard let match = matches.first else {
            throw HaloParityConfigurationError.missingWindowServerPlacement
        }
        guard matches.count == 1 else {
            throw HaloParityConfigurationError.ambiguousWindowServerPlacement(matches.count)
        }
        return match
    }
}

struct HaloParityRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }
}

struct HaloParityInsets: Codable, Equatable, Sendable {
    let top: Double
    let left: Double
    let bottom: Double
    let right: Double

    init(_ insets: NSEdgeInsets) {
        top = insets.top
        left = insets.left
        bottom = insets.bottom
        right = insets.right
    }
}

struct HaloParityPlacementProvenance: Codable, Equatable, Sendable {
    let requestedProfileId: String
    let resolvedMode: String
    let targetScreenId: String
    let targetScreenName: String
    let selectionSummary: String
    let screenFrame: HaloParityRect
    let visibleFrame: HaloParityRect
    let safeAreaInsets: HaloParityInsets
    let cgWindowId: UInt32
    let windowLayer: Int
    let actualWindowGeometry: HaloParityRect
}

struct HaloParityEventProvenance: Codable, Equatable, Sendable {
    let value: HaloParityEvent?

    init(_ value: HaloParityEvent?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = container.decodeNil() ? nil : try container.decode(HaloParityEvent.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let value {
            try container.encode(value)
        } else {
            try container.encodeNil()
        }
    }
}

struct HaloParityCaptureManifest: Codable, Equatable, Sendable {
    let schemaVersion: String
    let scenario: HaloParityScenarioID
    let manifestDisposition: HaloParityManifestDisposition
    let lockedNativeFixtureIdentifier: String
    let profile: HaloParityProfile
    let motion: HaloParityMotionMode
    let accessibility: HaloParityAccessibility
    let event: HaloParityEventProvenance
    let seed: UInt64
    let fixtureSchemaVersion: String
    let fixtureHash: String
    let fixtureVariant: String
    let resolvedThemeID: String
    let clock: HaloParityClockAttestation
    let executable: HaloParityExecutableProvenance
    let process: HaloParityProcessProvenance
    let fixture: HaloParityFixtureProvenance
    let placement: HaloParityPlacementProvenance
    let generatedAt: Date
    let isolation: HaloParityLiveDataIsolationProof
    let acknowledgedEvents: [HaloParityEvent]

    func encoded(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }
}

enum HaloParityFixturePayloadHasher {
    private struct UsageWindow: Encodable {
        let id: String
        let label: String
        let usedPercentage: Double
        let resetsAt: Date?
    }

    private struct UsageProvider: Encodable {
        let id: String
        let title: String
        let windows: [UsageWindow]
    }

    private struct Payload: Encodable {
        let fixture: HaloParityFixtureRecord
        let sessions: [AgentSession]
        let selectedSessionID: String?
        let presentation: String
        let openReason: String?
        let actionableSessionID: String?
        let usageProviders: [UsageProvider]?
        let forcesRowExpansion: Bool
        let profile: String
        let themeID: String
        let appearancePreferences: [String: String]
    }

    @MainActor
    static func hash(
        fixture: HaloParityResolvedFixture,
        model: AppModel
    ) throws -> String {
        let preferences = model.appearancePreferences(for: model.activeAppearanceProfile)
        let usage = model.debugUsageProvidersOverride?.map { provider in
            UsageProvider(
                id: provider.id,
                title: provider.title,
                windows: provider.windows.map {
                    UsageWindow(
                        id: $0.id,
                        label: $0.label,
                        usedPercentage: $0.usedPercentage,
                        resetsAt: $0.resetsAt
                    )
                }
            )
        }
        let payload = Payload(
            fixture: fixture.record,
            sessions: model.sessions,
            selectedSessionID: model.selectedSessionID,
            presentation: String(describing: model.notchStatus),
            openReason: model.notchOpenReason.map { String(describing: $0) },
            actionableSessionID: model.islandSurface.sessionID,
            usageProviders: usage,
            forcesRowExpansion: model.debugForcesRowExpansion,
            profile: model.activeAppearanceProfile.rawValue,
            themeID: model.islandTheme.id,
            appearancePreferences: [
                "rightSlot": preferences.rightSlot.rawValue,
                "centerLabel": preferences.centerLabel.rawValue,
                "usageDisplay": preferences.usageDisplay.rawValue,
                "sessionStateIndicator": preferences.sessionStateIndicator.rawValue,
                "sessionGroup": preferences.sessionGroup.rawValue,
                "sessionSort": preferences.sessionSort.rawValue,
                "completedStaleThreshold": preferences.completedStaleThreshold.rawValue,
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct HaloParityStateDump: Codable, Equatable, Sendable {
    struct Session: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let phase: String
        let outcome: String
        let origin: String
    }

    let scenario: HaloParityScenarioID
    let fixture: HaloParityFixtureRecord
    let sessions: [Session]
    let selectedSessionID: String?
    let presentation: String
    let profile: HaloParityProfile
    let accessibility: HaloParityAccessibility
    let motion: HaloParityMotionMode
    let acknowledgedEvents: [HaloParityEvent]
}
#endif
