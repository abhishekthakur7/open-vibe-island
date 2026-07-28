import Foundation
import Testing
import Darwin
@testable import OpenIslandCore

struct BridgeSecurityTests {
    @Test
    func rolesDefaultDenyAndHaveDisjointOperations() {
        #expect(BridgeClientRole.hookEventSubmit.permits(.processGeminiHook(.init(cwd: "/x", hookEventName: .sessionStart, sessionID: "s"))))
        #expect(BridgeClientRole.hookEventSubmit.permits(.resolvePermission(sessionID: "s", resolution: .allowOnce())) == false)
        #expect(BridgeClientRole.appInternalControl.permits(.resolvePermission(sessionID: "s", resolution: .allowOnce())))
        #expect(BridgeClientRole.localStatusRead.permits(.processCodexHook(.init(cwd: "/x", hookEventName: .stop, model: "m", permissionMode: .default, sessionID: "s", transcriptPath: nil))) == false)

        let commands: [BridgeCommand] = [
            .registerClient(role: .localStatusRead),
            .requestQuestion(sessionID: "s", prompt: .init(title: "Question", questions: [])),
            .resolvePermission(sessionID: "s", resolution: .allowOnce()),
            .answerQuestion(sessionID: "s", response: .init(answers: [:])),
            .processCodexHook(.init(cwd: "/x", hookEventName: .stop, model: "m", permissionMode: .default, sessionID: "s", transcriptPath: nil)),
            .processClaudeHook(.init(cwd: "/x", hookEventName: .stop, sessionID: "s")),
            .processOpenCodeHook(.init(hookEventName: .stop, sessionID: "s", cwd: "/x")),
            .processCursorHook(.init(hookEventName: .stop, conversationId: "s", generationId: "g", workspaceRoots: ["/x"])),
            .processGeminiHook(.init(cwd: "/x", hookEventName: .sessionStart, sessionID: "s")),
        ]
        for command in commands {
            #expect(BridgeClientRole.allCases.filter { $0.permits(command) }.count == 1)
        }

        #expect(BridgeClientRole.localStatusRead.permits(.registerClient(role: .localStatusRead)))
        #expect(!BridgeClientRole.localStatusRead.permits(.registerClient(role: .observer)))
        #expect(BridgeClientRole.appInternalControl.permits(.registerClient(role: .observer)))
        #expect(BridgeClientRole.appInternalControl.permits(.registerClient(role: .appInternalControl)))
        #expect(!BridgeClientRole.appInternalControl.permits(.registerClient(role: .localStatusRead)))
        #expect(!BridgeClientRole.observer.permits(.registerClient(role: .observer)))
    }

    @Test
    func bootstrapRotationAndRevocationInvalidateMaterial() throws {
        let store = InMemoryBridgeBootstrapStore()
        let first = try store.secret(for: .hookEventSubmit)
        let status = try store.secret(for: .localStatusRead)
        let control = try store.secret(for: .appInternalControl)
        #expect(first != status)
        #expect(status != control)
        try store.rotate(role: .hookEventSubmit)
        let rotated = try store.secret(for: .hookEventSubmit)
        #expect(first != rotated)
        try store.revoke(role: .hookEventSubmit)
        let replacement = try store.secret(for: .hookEventSubmit)
        #expect(rotated != replacement)

        try BridgeCredentialLifecycle.revokeManagedHookCredential(store: store)
        #expect(try store.secret(for: .hookEventSubmit) != replacement)
    }

    @Test
    func codecRejectsPartialOversizedFrame() throws {
        var buffer = Data(repeating: 0x61, count: BridgeCodec.maximumFrameBytes + 1)
        #expect(throws: BridgeTransportError.self) { try BridgeCodec.decodeLines(from: &buffer) }
    }

    @Test
    func peerIdentityIncludesKernelPid() throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { close(descriptors[0]); close(descriptors[1]) }

        let identity = try DarwinBridgePeerIdentityProvider().identity(for: descriptors[0])
        #expect(identity.uid == getuid())
        #expect(identity.pid == getpid())
    }

    @Test
    func invalidPeerSignatureFailsBeforeProofCanAuthorize() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let store = InMemoryBridgeBootstrapStore()
        let previousSecret = try store.secret(for: .hookEventSubmit)
        let server = BridgeServer(
            socketURL: socketURL,
            bootstrapStore: store,
            signatureValidator: RejectingBridgeSignatureValidator()
        )
        try server.start()
        defer { server.stop() }

        let client = BridgeCommandClient(socketURL: socketURL, bootstrapStore: store, role: .hookEventSubmit)
        #expect(throws: BridgeTransportError.self) {
            _ = try client.send(.processGeminiHook(.init(cwd: "/x", hookEventName: .sessionStart, sessionID: "s")))
        }
        #expect(try store.secret(for: .hookEventSubmit) != previousSecret)
    }

    @Test
    func privilegedRolesFailClosedWhenPeerPidIsMissing() {
        let peer = BridgePeerIdentity(uid: getuid(), gid: getgid(), pid: nil)
        let validator = DefaultBridgeSignatureValidator(helperURL: URL(fileURLWithPath: "/missing/OpenIslandHooks"))
        #expect(!validator.validates(peer: peer, role: .hookEventSubmit))
        #expect(!validator.validates(peer: peer, role: .appInternalControl))
    }

    @Test
    func privatePathValidationRejectsSyntheticWrongOwnerAndUnsafeComponents() throws {
        let target = URL(fileURLWithPath: "/private/bridge-owner-test", isDirectory: true)
        let wrongOwner = SyntheticMetadataProvider(overrides: [
            target.path: .init(mode: S_IFDIR | 0o700, owner: getuid() + 1),
        ])
        #expect(throws: BridgeTransportError.self) {
            try validatePrivatePathComponents(through: target, metadataProvider: wrongOwner)
        }

        let writable = SyntheticMetadataProvider(overrides: [
            target.path: .init(mode: S_IFDIR | 0o770, owner: getuid()),
        ])
        #expect(throws: BridgeTransportError.self) {
            try validatePrivatePathComponents(through: target, metadataProvider: writable)
        }
    }

    @Test
    func bootstrapKeychainItemHasExplicitTrustedApplicationAccessAndFailsClosed() throws {
        let item = try BridgeBootstrapKeychainItemBuilder(
            service: "test.service",
            accessBuilder: FixedAccessBuilder()
        ).item(role: .hookEventSubmit, secret: Data([1, 2, 3]))
        #expect(item[kSecAttrAccess] as? String == "restricted-access")
        #expect(item[kSecAttrAccessible] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(throws: BridgeTransportError.self) {
            _ = try BridgeBootstrapKeychainItemBuilder(
                service: "test.service",
                accessBuilder: RejectingAccessBuilder()
            ).item(role: .hookEventSubmit, secret: Data([1]))
        }
        #expect(throws: BridgeTransportError.self) {
            _ = try DarwinBridgeKeychainAccessBuilder(
                trustedURLs: [URL(fileURLWithPath: "/not-an-open-island-executable")]
            ).makeAccess()
        }
    }
}

private struct RejectingBridgeSignatureValidator: BridgeSignatureValidating {
    func validates(peer: BridgePeerIdentity, role: BridgeClientRole) -> Bool { false }
}

private struct SyntheticMetadataProvider: BridgeFileMetadataProviding {
    let overrides: [String: BridgeFileMetadata]
    func metadata(at url: URL) throws -> BridgeFileMetadata? {
        if let override = overrides[url.path] { return override }
        return try DarwinBridgeFileMetadataProvider().metadata(at: url)
    }
}

private struct FixedAccessBuilder: BridgeKeychainAccessBuilding {
    func makeAccess() throws -> CFTypeRef { "restricted-access" as CFString }
}

private struct RejectingAccessBuilder: BridgeKeychainAccessBuilding {
    func makeAccess() throws -> CFTypeRef { throw BridgeTransportError.bootstrapUnavailable }
}
