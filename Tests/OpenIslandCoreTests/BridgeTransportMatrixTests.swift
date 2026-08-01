import Darwin
import Foundation
import Testing
@testable import OpenIslandCore

struct BridgeTransportMatrixTests {
    @Test
    func codecCapsNestingWithoutCountingBracketsInStrings() throws {
        let safe = try BridgeCodec.encodeLine(.hello(.init(serverLabel: "[\\\"]", serverNonce: "nonce")))
        var safeBuffer = safe
        #expect(try BridgeCodec.decodeLines(from: &safeBuffer).count == 1)

        let nested = String(repeating: "{\"x\":", count: BridgeCodec.maximumJSONDepth + 1)
            + "0" + String(repeating: "}", count: BridgeCodec.maximumJSONDepth + 1) + "\n"
        var deepBuffer = Data(nested.utf8)
        #expect(throws: BridgeTransportError.self) { try BridgeCodec.decodeLines(from: &deepBuffer) }
    }

    @Test
    func codecRetainsPartialInputAndEnforcesExactInputAndOutputLimits() throws {
        let line = try BridgeCodec.encodeLine(.hello(.init(serverNonce: "partial")))
        var partial = line.dropLast()
        #expect(try BridgeCodec.decodeLines(from: &partial).isEmpty)
        #expect(partial.count == line.count - 1)
        partial.append(0x0A)
        #expect(try BridgeCodec.decodeLines(from: &partial).count == 1)

        var exactLimit = Data(repeating: 0x61, count: BridgeCodec.maximumFrameBytes)
        #expect(try BridgeCodec.decodeLines(from: &exactLimit).isEmpty)
        exactLimit.append(0x61)
        #expect(throws: BridgeTransportError.self) { try BridgeCodec.decodeLines(from: &exactLimit) }

        let oversized = BridgeEnvelope.hello(.init(serverLabel: String(repeating: "x", count: BridgeCodec.maximumFrameBytes), serverNonce: "n"))
        #expect(throws: BridgeTransportError.self) { try BridgeCodec.encodeLine(oversized) }
    }

    @Test
    func perPeerLimitLeavesGlobalCapacityForDifferentPeerAndReleasesOnEOF() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let identities = SequencedPeerIdentityProvider([101, 101, 202])
        let server = BridgeServer(
            socketURL: socketURL,
            bootstrapStore: InMemoryBridgeBootstrapStore(),
            peerIdentityProvider: identities,
            signatureValidator: BridgeTestSignatureValidator(),
            rotateBootstrapOnStart: false,
            limits: .init(maximumConnections: 3, maximumConnectionsPerPeer: 1)
        )
        try server.start()
        defer { server.stop() }

        let first = try connectRaw(to: socketURL)
        defer { close(first) }
        eventually { server.activeConnectionCountForTests() == 1 }
        let rejected = try connectRaw(to: socketURL)
        defer { close(rejected) }
        usleep(20_000)
        #expect(server.activeConnectionCountForTests() == 1)
        let secondPeer = try connectRaw(to: socketURL)
        eventually { server.activeConnectionCountForTests() == 2 }
        close(secondPeer)
        eventually { server.activeConnectionCountForTests() == 1 }
    }

    @Test
    func handshakeTimeoutAndMalformedFloodCloseAndReleaseConnections() throws {
        let clock = LockedClock(Date(timeIntervalSince1970: 1))
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(
            socketURL: socketURL,
            bootstrapStore: InMemoryBridgeBootstrapStore(),
            peerIdentityProvider: SequencedPeerIdentityProvider([303, 304]),
            signatureValidator: BridgeTestSignatureValidator(),
            rotateBootstrapOnStart: false,
            limits: .init(maximumMalformedRequests: 3, handshakeTimeout: 1),
            now: { clock.value }
        )
        try server.start()
        defer { server.stop() }

        let stalled = try connectRaw(to: socketURL)
        eventually { server.activeConnectionCountForTests() == 1 }
        clock.value = clock.value.addingTimeInterval(2)
        server.performMaintenanceForTests()
        eventually { server.activeConnectionCountForTests() == 0 }
        close(stalled)

        let malformed = try connectRaw(to: socketURL)
        eventually { server.activeConnectionCountForTests() == 1 }
        for _ in 0..<3 { _ = "{bad}\n".withCString { write(malformed, $0, strlen($0)) } }
        eventually { server.activeConnectionCountForTests() == 0 }
        close(malformed)
    }

    @Test
    func globalThirtyTwoConnectionFloodRejectsAndEOFAndPartialFramesReleaseCapacity() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(
            socketURL: socketURL, bootstrapStore: InMemoryBridgeBootstrapStore(),
            peerIdentityProvider: SequencedPeerIdentityProvider((1...34).map(pid_t.init)),
            signatureValidator: BridgeTestSignatureValidator(), rotateBootstrapOnStart: false,
            limits: .init(maximumConnections: 32, maximumConnectionsPerPeer: 1)
        )
        try server.start(); defer { server.stop() }
        var clients = try (0..<32).map { _ in try connectRaw(to: socketURL) }
        defer { clients.forEach { close($0) } }
        eventually { server.activeConnectionCountForTests() == 32 }
        let rejected = try connectRaw(to: socketURL); defer { close(rejected) }
        usleep(20_000)
        #expect(server.activeConnectionCountForTests() == 32)
        _ = "{\"type\":\"authenticate\"".withCString { write(clients[0], $0, strlen($0)) }
        close(clients.removeFirst())
        eventually { server.activeConnectionCountForTests() == 31 }
        let replacement = try connectRaw(to: socketURL); defer { close(replacement) }
        eventually { server.activeConnectionCountForTests() == 32 }
    }

    @Test
    func nonceReplayCapabilityRoleVersionIdleAndRequestTimeoutsFailClosedAndCleanUp() throws {
        let clock = LockedClock(Date(timeIntervalSince1970: 1))
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let store = InMemoryBridgeBootstrapStore()
        let server = BridgeServer(
            socketURL: socketURL, bootstrapStore: store,
            peerIdentityProvider: SequencedPeerIdentityProvider([501, 502, 503, 504, 505]),
            signatureValidator: BridgeTestSignatureValidator(), rotateBootstrapOnStart: false,
            limits: .init(handshakeTimeout: 2, idleTimeout: 3, requestTimeout: 4, capabilityLifetime: 5),
            now: { clock.value }
        )
        try server.start(); defer { server.stop() }

        let first = try connectRaw(to: socketURL)
        let firstCapability = try authenticateRaw(first, store: store, role: .hookEventSubmit, clientNonce: "reused")
        #expect(firstCapability.protocolVersion == 2)
        try writeAll(try BridgeCodec.encodeLine(.command(.resolvePermission(sessionID: "x", resolution: .allowOnce()))), to: first)
        #expect(try responseRaw(first) == .denied)
        close(first)

        let replay = try connectRaw(to: socketURL)
        #expect(throws: BridgeTransportError.self) {
            _ = try authenticateRaw(replay, store: store, role: .hookEventSubmit, clientNonce: "reused")
        }
        close(replay)

        clock.value = clock.value.addingTimeInterval(6)
        server.performMaintenanceForTests()
        let afterExpiry = try connectRaw(to: socketURL)
        _ = try authenticateRaw(afterExpiry, store: store, role: .hookEventSubmit, clientNonce: "reused")
        close(afterExpiry)

        let versionMismatch = try connectRaw(to: socketURL)
        #expect(throws: BridgeTransportError.self) {
            _ = try authenticateRaw(versionMismatch, store: store, role: .hookEventSubmit, clientNonce: "old", version: 1)
        }
        close(versionMismatch)

        let pending = try connectRaw(to: socketURL)
        _ = try authenticateRaw(pending, store: store, role: .hookEventSubmit, clientNonce: "pending")
        let preTool = CodexHookPayload(cwd: "/x", hookEventName: .preToolUse, model: "m", permissionMode: .default, sessionID: "pending", transcriptPath: nil)
        try writeAll(try BridgeCodec.encodeLine(.command(.processCodexHook(preTool))), to: pending)
        eventually { server.pendingInteractionCountForTests() == 1 }
        clock.value = clock.value.addingTimeInterval(5)
        server.performMaintenanceForTests()
        eventually { server.activeConnectionCountForTests() == 0 }
        #expect(server.pendingInteractionCountForTests() == 0)
        close(pending)
    }

    @Test
    func registrationRolesRejectEmbeddedMismatchesAndObserverAuthentication() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let store = InMemoryBridgeBootstrapStore()
        let server = BridgeServer(
            socketURL: socketURL, bootstrapStore: store,
            peerIdentityProvider: SequencedPeerIdentityProvider([701, 702]),
            signatureValidator: BridgeTestSignatureValidator(), rotateBootstrapOnStart: false
        )
        try server.start(); defer { server.stop() }

        let statusClient = try connectRaw(to: socketURL)
        _ = try authenticateRaw(statusClient, store: store, role: .localStatusRead, clientNonce: "status")
        try writeAll(try BridgeCodec.encodeLine(.command(.registerClient(role: .observer))), to: statusClient)
        #expect(try responseRaw(statusClient) == .denied)
        close(statusClient)

        let observer = try connectRaw(to: socketURL)
        #expect(throws: BridgeTransportError.self) {
            _ = try authenticateRaw(observer, store: store, role: .observer, clientNonce: "observer")
        }
        close(observer)
    }
}

private final class SequencedPeerIdentityProvider: BridgePeerIdentityProviding, @unchecked Sendable {
    private var pids: [pid_t]
    private let lock = NSLock()
    init(_ pids: [pid_t]) { self.pids = pids }
    func identity(for fileDescriptor: Int32) throws -> BridgePeerIdentity {
        lock.lock(); defer { lock.unlock() }
        return BridgePeerIdentity(uid: getuid(), gid: getgid(), pid: pids.removeFirst())
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock(); private var storage: Date
    init(_ value: Date) { storage = value }
    var value: Date { get { lock.lock(); defer { lock.unlock() }; return storage } set { lock.lock(); storage = newValue; lock.unlock() } }
}

private func connectRaw(to url: URL) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw BridgeTransportError.systemCallFailed("socket", errno) }
    do {
        for attempt in 0..<20 {
            let connected = try withUnixSocketAddress(path: url.path) { address, length in
                connect(descriptor, address, length) == 0
            }
            if connected { return descriptor }
            guard errno == ECONNREFUSED, attempt < 19 else {
                throw BridgeTransportError.systemCallFailed("connect", errno)
            }
            usleep(1_000)
        }
        fatalError("unreachable")
    } catch { close(descriptor); throw error }
}

private func authenticateRaw(
    _ descriptor: Int32,
    store: any BridgeBootstrapStore,
    role: BridgeClientRole,
    clientNonce: String,
    version: Int = 2
) throws -> BridgeCapability {
    let hello = try readEnvelopeRaw(descriptor)
    guard case let .hello(serverHello) = hello else { throw BridgeTransportError.malformedEnvelope }
    let authentication = BridgeAuthentication(
        protocolVersion: version, role: role, clientNonce: clientNonce,
        proof: BridgeCrypto.proof(secret: try store.secret(for: role), serverNonce: serverHello.serverNonce, clientNonce: clientNonce, role: role)
    )
    try writeAll(try BridgeCodec.encodeLine(.authenticate(authentication)), to: descriptor)
    guard case let .response(.authenticated(capability)) = try readEnvelopeRaw(descriptor) else {
        throw BridgeTransportError.unauthorized
    }
    return capability
}

private func responseRaw(_ descriptor: Int32) throws -> BridgeResponse {
    guard case let .response(response) = try readEnvelopeRaw(descriptor) else { throw BridgeTransportError.malformedEnvelope }
    return response
}

private func readEnvelopeRaw(_ descriptor: Int32) throws -> BridgeEnvelope {
    var buffer = Data(); var bytes = [UInt8](repeating: 0, count: 8_192)
    while true {
        let count = read(descriptor, &bytes, bytes.count)
        if count > 0 {
            buffer.append(bytes, count: count)
            if let envelope = try BridgeCodec.decodeLines(from: &buffer).first { return envelope }
        } else if count == 0 { throw BridgeTransportError.unauthorized }
        else if errno != EAGAIN && errno != EWOULDBLOCK { throw BridgeTransportError.systemCallFailed("read", errno) }
    }
}

private func eventually(_ condition: @escaping () -> Bool) {
    for _ in 0..<100 where !condition() { usleep(2_000) }
    #expect(condition())
}
