import Foundation

/// Signed-bundle inventory for immutable helper and resource bytes. This is
/// separate from the per-user installation manifests written beside configs.
public struct BundledArtifactManifest: Codable, Sendable, Equatable {
    public static let fileName = "OpenIslandArtifacts.json"
    public static let formatVersion = 1

    public struct Entry: Codable, Sendable, Equatable {
        public var artifactID: String
        public var version: Int
        public var relativePath: String
        public var sha256: String
        public var expectedMode: UInt16
        public var managedMarker: String
        public var templateVersion: String

        public init(artifactID: String, version: Int, relativePath: String, sha256: String, expectedMode: UInt16, managedMarker: String, templateVersion: String) {
            self.artifactID = artifactID; self.version = version; self.relativePath = relativePath
            self.sha256 = sha256; self.expectedMode = expectedMode; self.managedMarker = managedMarker; self.templateVersion = templateVersion
        }
    }

    public var formatVersion: Int
    public var artifacts: [Entry]

    public init(formatVersion: Int = BundledArtifactManifest.formatVersion, artifacts: [Entry]) {
        self.formatVersion = formatVersion; self.artifacts = artifacts
    }
}

/// Proof that the helper is the byte-for-byte artifact from the fixed path in
/// a packaged app. URLs, environment overrides, and caller-computed digests
/// are not installation authority.
public struct VerifiedBundledHookArtifact: Sendable, Equatable {
    public let bundleURL: URL
    public let helperURL: URL
    public let entry: BundledArtifactManifest.Entry

    public static let helperID = "open-island-hooks"
    public static let helperRelativePath = "Contents/Helpers/OpenIslandHooks"

    public static func verify(bundleURL: URL, fileManager: FileManager = .default) throws -> VerifiedBundledHookArtifact {
        let bundleURL = bundleURL.standardizedFileURL
        let manifestURL = bundleURL.appendingPathComponent("Contents/Resources/\(BundledArtifactManifest.fileName)")
        guard fileManager.fileExists(atPath: manifestURL.path) else { throw BundledHookArtifactError.missingManifest(manifestURL.path) }
        try ManagedHookFileSystem.validateTarget(manifestURL, allowMissing: false)
        let manifest: BundledArtifactManifest
        do { manifest = try JSONDecoder().decode(BundledArtifactManifest.self, from: Data(contentsOf: manifestURL, options: [.mappedIfSafe])) }
        catch { throw BundledHookArtifactError.invalidManifest(manifestURL.path) }
        guard manifest.formatVersion == BundledArtifactManifest.formatVersion,
              manifest.artifacts.filter({ $0.artifactID == helperID }).count == 1,
              let entry = manifest.artifacts.first(where: { $0.artifactID == helperID }),
              entry.version >= 1, entry.relativePath == helperRelativePath,
              entry.managedMarker == "OpenIslandHooks", !entry.templateVersion.isEmpty
        else { throw BundledHookArtifactError.invalidManifest(manifestURL.path) }
        let helperURL = bundleURL.appendingPathComponent(entry.relativePath).standardizedFileURL
        try ManagedHookFileSystem.validateTarget(helperURL, allowMissing: false)
        guard try ManagedHookFileSystem.digest(ofFile: helperURL) == entry.sha256 else { throw BundledHookArtifactError.digestMismatch(helperURL.path) }
        let permissions = (try fileManager.attributesOfItem(atPath: helperURL.path)[.posixPermissions] as? NSNumber)?.uint16Value
        guard permissions == entry.expectedMode else { throw BundledHookArtifactError.modeMismatch(helperURL.path) }
        return VerifiedBundledHookArtifact(bundleURL: bundleURL, helperURL: helperURL, entry: entry)
    }

    public static func verify(helperURL: URL, fileManager: FileManager = .default) throws -> VerifiedBundledHookArtifact {
        let helperURL = helperURL.standardizedFileURL
        guard helperURL.path.hasSuffix("/\(helperRelativePath)") else { throw BundledHookArtifactError.untrustedLocation(helperURL.path) }
        let bundlePath = String(helperURL.path.dropLast(helperRelativePath.count + 1))
        return try verify(bundleURL: URL(fileURLWithPath: bundlePath, isDirectory: true), fileManager: fileManager)
    }

    /// Verifies static template/resource bytes listed in the same signed app
    /// inventory. Dynamic user configuration is still verified separately at
    /// the destination by the descriptor-anchored atomic writer.
    public static func verifiedResource(at resourceURL: URL, fileManager: FileManager = .default) throws -> VerifiedBundledResource {
        let resourceURL = resourceURL.standardizedFileURL
        let marker = "/Contents/Resources/"
        guard let range = resourceURL.path.range(of: marker) else { throw BundledHookArtifactError.untrustedLocation(resourceURL.path) }
        let bundleURL = URL(fileURLWithPath: String(resourceURL.path[..<range.lowerBound]), isDirectory: true)
        _ = try verify(bundleURL: bundleURL, fileManager: fileManager)
        let manifestURL = bundleURL.appendingPathComponent("Contents/Resources/\(BundledArtifactManifest.fileName)")
        guard let manifest = try? JSONDecoder().decode(BundledArtifactManifest.self, from: Data(contentsOf: manifestURL, options: [.mappedIfSafe])),
              let entry = manifest.artifacts.first(where: { bundleURL.appendingPathComponent($0.relativePath).standardizedFileURL == resourceURL }),
              !entry.artifactID.isEmpty, !entry.managedMarker.isEmpty, entry.version >= 1, !entry.templateVersion.isEmpty
        else { throw BundledHookArtifactError.invalidManifest(manifestURL.path) }
        try ManagedHookFileSystem.validateTarget(resourceURL, allowMissing: false)
        guard try ManagedHookFileSystem.digest(ofFile: resourceURL) == entry.sha256 else { throw BundledHookArtifactError.digestMismatch(resourceURL.path) }
        let permissions = (try fileManager.attributesOfItem(atPath: resourceURL.path)[.posixPermissions] as? NSNumber)?.uint16Value
        guard permissions == entry.expectedMode else { throw BundledHookArtifactError.modeMismatch(resourceURL.path) }
        return VerifiedBundledResource(resourceURL: resourceURL, entry: entry, data: try Data(contentsOf: resourceURL, options: [.mappedIfSafe]))
    }

    public static func verifiedResourceData(at resourceURL: URL, fileManager: FileManager = .default) throws -> Data {
        try verifiedResource(at: resourceURL, fileManager: fileManager).data
    }
}

/// Verified immutable resource material from a signed app inventory.  Keep
/// the entry with the bytes so installers can persist the exact artifact
/// identity they accepted, rather than reconstructing authority from a path.
public struct VerifiedBundledResource: Sendable, Equatable {
    public let resourceURL: URL
    public let entry: BundledArtifactManifest.Entry
    public let data: Data
}

public enum BundledHookArtifactError: LocalizedError, Sendable, Equatable {
    case missingManifest(String), invalidManifest(String), untrustedLocation(String), digestMismatch(String), modeMismatch(String)

    public var errorDescription: String? {
        switch self {
        case let .missingManifest(path), let .invalidManifest(path):
            return "Open Island will not install hooks because its bundled artifact manifest is missing or invalid at \(path). Refresh Open Island Dev with zsh scripts/launch-dev-app.sh, then retry from Settings."
        case let .untrustedLocation(path):
            return "Open Island will not install hooks from \(path). Hook installation requires the verified helper in a refreshed Open Island Dev.app bundle; run zsh scripts/launch-dev-app.sh, then retry from Settings."
        case let .digestMismatch(path), let .modeMismatch(path):
            return "Open Island will not install the modified bundled helper at \(path). Refresh Open Island Dev with zsh scripts/launch-dev-app.sh, then retry from Settings."
        }
    }
}
