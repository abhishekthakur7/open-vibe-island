import CryptoKit
import Darwin
import Foundation
import Security

/// The bridge is deliberately split into three principals. A command is never
/// authorized merely because it came from the same login session.
public enum BridgeClientRole: String, Codable, Sendable, CaseIterable {
    case hookEventSubmit = "hook-event-submit"
    case localStatusRead = "local-status-read"
    case appInternalControl = "app-internal-control"
    /// Wire compatibility for pre-v2 in-process observers. It can only receive
    /// events and is never accepted for a mutating command.
    case observer

    public func permits(_ command: BridgeCommand) -> Bool {
        switch (self, command) {
        case (.hookEventSubmit, .processCodexHook),
             (.hookEventSubmit, .processClaudeHook),
             (.hookEventSubmit, .processOpenCodeHook),
             (.hookEventSubmit, .processCursorHook),
             (.hookEventSubmit, .processGeminiHook):
            true
        case (.localStatusRead, .registerClient(.localStatusRead)),
             (.appInternalControl, .registerClient(.observer)),
             (.appInternalControl, .registerClient(.appInternalControl)),
             (.appInternalControl, .requestQuestion),
             (.appInternalControl, .resolvePermission),
             (.appInternalControl, .answerQuestion):
            true
        default:
            false
        }
    }
}

public protocol BridgeBootstrapStore: AnyObject, Sendable {
    func secret(for role: BridgeClientRole) throws -> Data
    func rotate(role: BridgeClientRole) throws
    func revoke(role: BridgeClientRole) throws
}

/// Keychain is the only persistent location for bridge bootstrap material.
/// Every item carries a macOS trusted-application ACL for the current app and
/// the fixed signed helper candidates; no access group or caller path is used.
public final class KeychainBridgeBootstrapStore: BridgeBootstrapStore, @unchecked Sendable {
    public static let shared = KeychainBridgeBootstrapStore()
    private static let lock = NSLock()
    private let service = "app.openisland.local.bridge.bootstrap.v2"
    private let accessBuilder: any BridgeKeychainAccessBuilding

    init(accessBuilder: any BridgeKeychainAccessBuilding = DarwinBridgeKeychainAccessBuilder()) {
        self.accessBuilder = accessBuilder
    }

    public func secret(for role: BridgeClientRole) throws -> Data {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return try secretLocked(for: role)
    }

    private func secretLocked(for role: BridgeClientRole) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: role.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return data }
        guard status == errSecItemNotFound else { throw BridgeTransportError.bootstrapUnavailable }
        try rotateLocked(role: role)
        return try secretLocked(for: role)
    }

    public func rotate(role: BridgeClientRole) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try rotateLocked(role: role)
    }

    private func rotateLocked(role: BridgeClientRole) throws {
        try revokeLocked(role: role)
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw BridgeTransportError.bootstrapUnavailable
        }
        let item = try BridgeBootstrapKeychainItemBuilder(service: service, accessBuilder: accessBuilder)
            .item(role: role, secret: Data(bytes))
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw BridgeTransportError.bootstrapUnavailable
        }
    }

    public func revoke(role: BridgeClientRole) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try revokeLocked(role: role)
    }

    private func revokeLocked(role: BridgeClientRole) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: role.rawValue]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw BridgeTransportError.bootstrapUnavailable }
    }
}

/// Builds the `kSecAttrAccess` object separately so tests can verify the
/// Keychain query without modifying the login Keychain.
protocol BridgeKeychainAccessBuilding: Sendable {
    func makeAccess() throws -> CFTypeRef
}

struct BridgeBootstrapKeychainItemBuilder: Sendable {
    let service: String
    let accessBuilder: any BridgeKeychainAccessBuilding

    func item(role: BridgeClientRole, secret: Data) throws -> [CFString: Any] {
        let access = try accessBuilder.makeAccess()
        return [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: role.rawValue,
            kSecValueData: secret,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrAccess: access,
        ]
    }
}

/// Resolves only product-controlled executables.  The helper is never taken
/// from an environment variable or arbitrary filesystem location.
struct DarwinBridgeKeychainAccessBuilder: BridgeKeychainAccessBuilding {
    private let trustedURLs: [URL]?

    init(trustedURLs: [URL]? = nil) {
        self.trustedURLs = trustedURLs
    }

    func makeAccess() throws -> CFTypeRef {
        // `SecTrustedApplicationCreateFromPath` / `SecAccessCreate` are deprecated
        // (SecKeychain, 10.10) but retained deliberately: they build the
        // trusted-application ACL that lets both the app and the signed helper
        // read the shared bridge secret without a password prompt. The modern
        // replacement — keychain access groups — keys off a Team-ID prefix this
        // local-only, ad-hoc-signed build does not have, so it is not an option
        // here. The APIs remain functional on current macOS.
        let urls = trustedURLs ?? Self.defaultTrustedURLs()
        guard urls.count >= 2 else { throw BridgeTransportError.bootstrapUnavailable }
        var applications: [SecTrustedApplication] = []
        for url in urls {
            guard FileManager.default.isExecutableFile(atPath: url.path) else {
                throw BridgeTransportError.bootstrapUnavailable
            }
            var application: SecTrustedApplication?
            let status = url.path.withCString { SecTrustedApplicationCreateFromPath($0, &application) }
            guard status == errSecSuccess, let application else {
                throw BridgeTransportError.bootstrapUnavailable
            }
            applications.append(application)
        }
        var access: SecAccess?
        let status = SecAccessCreate(
            "Open Island local bridge bootstrap" as CFString,
            applications as CFArray,
            &access
        )
        guard status == errSecSuccess, let access else {
            throw BridgeTransportError.bootstrapUnavailable
        }
        return access
    }

    private static func defaultTrustedURLs() -> [URL] {
        guard let appExecutable = Bundle.main.executableURL,
              appExecutable.lastPathComponent == "OpenIslandApp" else {
            // The signed helper may read an already-provisioned item, but it
            // must never create bridge bootstrap material without the app.
            return []
        }
        var helpers: [URL] = []
        let packaged = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OpenIslandHooks")
        if auditedExecutable(packaged) { helpers.append(packaged) }

        let sibling = appExecutable.deletingLastPathComponent().appendingPathComponent("OpenIslandHooks")
        if auditedExecutable(sibling) { helpers.append(sibling) }

        let devBundle = URL(fileURLWithPath: "/Applications/Open Island Dev.app/Contents/Helpers/OpenIslandHooks")
        if auditedExecutable(devBundle) { helpers.append(devBundle) }

        guard !helpers.isEmpty else { return [] }
        return [appExecutable] + Array(Set(helpers.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
    }

    private static func auditedExecutable(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return false }
        var code: SecStaticCode?
        return SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess
            && code.map { SecStaticCodeCheckValidity($0, SecCSFlags(), nil) == errSecSuccess } == true
    }
}

/// Deterministic test double and a useful dependency-injection boundary for
/// development builds where a signed Keychain access group is not available.
public final class InMemoryBridgeBootstrapStore: BridgeBootstrapStore, @unchecked Sendable {
    private var secrets: [BridgeClientRole: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func secret(for role: BridgeClientRole) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let secret = secrets[role] { return secret }
        let secret = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        secrets[role] = secret
        return secret
    }
    public func rotate(role: BridgeClientRole) throws { lock.lock(); secrets[role] = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }); lock.unlock() }
    public func revoke(role: BridgeClientRole) throws { lock.lock(); secrets.removeValue(forKey: role); lock.unlock() }
}

public enum BridgeCredentialLifecycle {
    /// Hook installers and explicit integration reset paths use this narrow
    /// entry point.  The next authenticated helper receives fresh material;
    /// every proof made with the revoked secret immediately fails.
    public static func revokeManagedHookCredential(
        store: any BridgeBootstrapStore = KeychainBridgeBootstrapStore.shared
    ) throws {
        try store.revoke(role: .hookEventSubmit)
    }

    /// Reset Integrations revokes every credential that can authorize a bridge
    /// role. The next enabled integration receives newly generated material.
    public static func revokeAllIntegrationCredentials(
        store: any BridgeBootstrapStore = KeychainBridgeBootstrapStore.shared
    ) throws {
        for role in BridgeClientRole.allCases where role != .observer {
            try store.revoke(role: role)
        }
    }
}

public struct BridgePeerIdentity: Equatable, Sendable {
    public let uid: uid_t
    public let gid: gid_t
    public let pid: pid_t?
}

public protocol BridgePeerIdentityProviding: Sendable {
    func identity(for fileDescriptor: Int32) throws -> BridgePeerIdentity
}

public struct DarwinBridgePeerIdentityProvider: BridgePeerIdentityProviding {
    public init() {}
    public func identity(for fileDescriptor: Int32) throws -> BridgePeerIdentity {
        var uid: uid_t = 0; var gid: gid_t = 0
        guard getpeereid(fileDescriptor, &uid, &gid) == 0 else { throw BridgeTransportError.peerIdentityUnavailable }
        // LOCAL_PEERPID is the only supported way to bind a Unix-domain
        // connection to the process whose signature we verify below.  Do not
        // silently downgrade to a UID-only identity if it is unavailable.
        var pid: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fileDescriptor, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0,
              length == MemoryLayout<pid_t>.size,
              pid > 0 else {
            throw BridgeTransportError.peerIdentityUnavailable
        }
        return BridgePeerIdentity(uid: uid, gid: gid, pid: pid)
    }
}

public protocol BridgeSignatureValidating: Sendable {
    func validates(peer: BridgePeerIdentity, role: BridgeClientRole) -> Bool
}

public struct DefaultBridgeSignatureValidator: BridgeSignatureValidating {
    private let helperURL: URL

    /// The helper path is injectable so tests can validate a deterministic
    /// signed fixture.  Production resolves only the helper embedded in the
    /// running app bundle; no environment or caller-provided path is accepted.
    public init(helperURL: URL? = nil) {
        if let helperURL {
            self.helperURL = helperURL.standardizedFileURL
        } else {
            self.helperURL = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/OpenIslandHooks")
        }
    }

    public func validates(peer: BridgePeerIdentity, role: BridgeClientRole) -> Bool {
        guard peer.uid == getuid(), let pid = peer.pid,
              let expectedRequirement = designatedRequirement(for: role),
              let guestCode = guestCode(pid: pid) else {
            return false
        }
        return SecCodeCheckValidity(guestCode, SecCSFlags(), expectedRequirement) == errSecSuccess
    }

    private func guestCode(pid: pid_t) -> SecCode? {
        var code: SecCode?
        let attributes: [CFString: Any] = [kSecGuestAttributePid: pid]
        guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, SecCSFlags(), &code) == errSecSuccess else {
            return nil
        }
        return code
    }

    private func designatedRequirement(for role: BridgeClientRole) -> SecRequirement? {
        switch role {
        case .hookEventSubmit:
            return requirement(forExecutable: helperURL)
        case .localStatusRead, .appInternalControl:
            // Status and in-app controls are accepted only from the running
            // app image, never merely from another same-UID executable.
            guard let executableURL = Bundle.main.executableURL else { return nil }
            return requirement(forExecutable: executableURL)
        case .observer:
            return nil
        }
    }

    private func requirement(forExecutable url: URL) -> SecRequirement? {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(), nil) == errSecSuccess else {
            return nil
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, SecCSFlags(), &requirement) == errSecSuccess else { return nil }
        return requirement
    }
}

enum BridgeCrypto {
    static func proof(secret: Data, serverNonce: String, clientNonce: String, role: BridgeClientRole) -> Data {
        let message = Data("v2|\(serverNonce)|\(clientNonce)|\(role.rawValue)".utf8)
        return Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: secret)))
    }
    static func equals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<lhs.count { difference |= lhs[lhs.startIndex + index] ^ rhs[rhs.startIndex + index] }
        return difference == 0
    }
}
