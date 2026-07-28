import Darwin
import Foundation

public final class BridgeCommandClient: @unchecked Sendable {
    private let socketURL: URL
    private let bootstrapStore: any BridgeBootstrapStore
    private let requestedRole: BridgeClientRole?
    /// A single kernel read may contain several newline-delimited envelopes
    /// (for example, a broadcast event followed by the command response).
    /// Keep decoded trailing envelopes for the next receive instead of
    /// discarding them and falsely timing out a request.
    private var receiveBuffer = Data()
    private var pendingEnvelopes: [BridgeEnvelope] = []

    public init(
        socketURL: URL = BridgeSocketLocation.defaultURL,
        bootstrapStore: any BridgeBootstrapStore = KeychainBridgeBootstrapStore.shared,
        role: BridgeClientRole? = nil
    ) {
        self.socketURL = socketURL
        self.bootstrapStore = bootstrapStore
        self.requestedRole = role
    }

    public func send(
        _ command: BridgeCommand,
        timeout: TimeInterval = 45
    ) throws -> BridgeResponse? {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor != -1 else {
            throw BridgeTransportError.systemCallFailed("socket", errno)
        }

        defer {
            close(fileDescriptor)
        }

        do {
            try disableSocketSigPipe(fileDescriptor)
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                guard Darwin.connect(fileDescriptor, address, length) != -1 else {
                    throw BridgeTransportError.systemCallFailed("connect", errno)
                }
            }

            var timeoutValue = timeval(
                tv_sec: Int(timeout),
                tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
            )

            guard setsockopt(
                fileDescriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeoutValue,
                socklen_t(MemoryLayout<timeval>.size)
            ) != -1 else {
                throw BridgeTransportError.systemCallFailed("setsockopt", errno)
            }

            guard setsockopt(
                fileDescriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                &timeoutValue,
                socklen_t(MemoryLayout<timeval>.size)
            ) != -1 else {
                throw BridgeTransportError.systemCallFailed("setsockopt", errno)
            }

            let hello = try readEnvelope(from: fileDescriptor, timeout: timeout)
            guard case let .hello(serverHello) = hello, serverHello.protocolVersion == 2 else {
                throw BridgeTransportError.protocolUpgradeRequired
            }
            let role = requestedRole ?? roleRequired(for: command)
            let secret = try bootstrapStore.secret(for: role)
            let clientNonce = UUID().uuidString
            let authentication = BridgeAuthentication(
                protocolVersion: serverHello.protocolVersion,
                role: role,
                clientNonce: clientNonce,
                proof: BridgeCrypto.proof(secret: secret, serverNonce: serverHello.serverNonce, clientNonce: clientNonce, role: role)
            )
            try writeAll(try BridgeCodec.encodeLine(.authenticate(authentication)), to: fileDescriptor)
            let authenticationResponse = try readEnvelope(from: fileDescriptor, timeout: timeout)
            guard case .response(.authenticated) = authenticationResponse else { throw BridgeTransportError.unauthorized }
            let data = try BridgeCodec.encodeLine(.command(command))
            try writeAll(data, to: fileDescriptor)
        } catch {
            throw error
        }

        while true {
            let message = try readEnvelope(from: fileDescriptor, timeout: timeout)
            if case let .response(response) = message { return response }
        }
    }

    private func roleRequired(for command: BridgeCommand) -> BridgeClientRole {
        switch command {
        case .processCodexHook, .processClaudeHook, .processOpenCodeHook, .processCursorHook, .processGeminiHook:
            .hookEventSubmit
        case let .registerClient(role):
            switch role {
            case .localStatusRead: .localStatusRead
            case .observer, .appInternalControl, .hookEventSubmit: .appInternalControl
            }
        case .requestQuestion, .resolvePermission, .answerQuestion:
            .appInternalControl
        }
    }

    private func readEnvelope(from fileDescriptor: Int32, timeout: TimeInterval) throws -> BridgeEnvelope {
        if !pendingEnvelopes.isEmpty {
            return pendingEnvelopes.removeFirst()
        }
        var localBuffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let bytesRead = read(fileDescriptor, &localBuffer, localBuffer.count)
            if bytesRead > 0 {
                receiveBuffer.append(localBuffer, count: bytesRead)
                let decoded = try BridgeCodec.decodeLines(from: &receiveBuffer)
                if !decoded.isEmpty {
                    pendingEnvelopes.append(contentsOf: decoded)
                    return pendingEnvelopes.removeFirst()
                }
                continue
            }
            if bytesRead == 0 { throw BridgeTransportError.protocolUpgradeRequired }
            if errno == EAGAIN || errno == EWOULDBLOCK { throw BridgeTransportError.responseTimedOut }
            throw BridgeTransportError.systemCallFailed("read", errno)
        }
    }
}
