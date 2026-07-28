import Dispatch
import Darwin
import Foundation

public final class LocalBridgeClient: @unchecked Sendable {
    private let socketURL: URL
    private let bootstrapStore: any BridgeBootstrapStore
    private let queue = DispatchQueue(label: "app.openisland.bridge.client")

    private var fileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation?
    private var buffer = Data()

    public init(socketURL: URL = BridgeSocketLocation.defaultURL, bootstrapStore: any BridgeBootstrapStore = KeychainBridgeBootstrapStore.shared) {
        self.socketURL = socketURL
        self.bootstrapStore = bootstrapStore
    }

    public func connect() throws -> AsyncThrowingStream<AgentEvent, Error> {
        guard fileDescriptor == -1 else {
            throw BridgeTransportError.alreadyConnected
        }

        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor != -1 else {
            throw BridgeTransportError.systemCallFailed("socket", errno)
        }

        do {
            try disableSocketSigPipe(fileDescriptor)
            try withUnixSocketAddress(path: socketURL.path) { address, length in
                guard Darwin.connect(fileDescriptor, address, length) != -1 else {
                    throw BridgeTransportError.systemCallFailed("connect", errno)
                }
            }
            let hello = try readHandshakeEnvelope(from: fileDescriptor)
            guard case let .hello(serverHello) = hello, serverHello.protocolVersion == 2 else { throw BridgeTransportError.protocolUpgradeRequired }
            let secret = try bootstrapStore.secret(for: .appInternalControl)
            let nonce = UUID().uuidString
            let authentication = BridgeAuthentication(role: .appInternalControl, clientNonce: nonce, proof: BridgeCrypto.proof(secret: secret, serverNonce: serverHello.serverNonce, clientNonce: nonce, role: .appInternalControl))
            try writeAll(try BridgeCodec.encodeLine(.authenticate(authentication)), to: fileDescriptor)
            guard case .response(.authenticated) = try readHandshakeEnvelope(from: fileDescriptor) else { throw BridgeTransportError.unauthorized }
            try makeSocketNonBlocking(fileDescriptor)
        } catch {
            close(fileDescriptor)
            throw error
        }

        self.fileDescriptor = fileDescriptor

        let stream = AsyncThrowingStream<AgentEvent, Error> { continuation in
            self.continuation = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.disconnect()
            }
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: queue)
        readSource.setEventHandler { [weak self] in
            self?.readAvailableData()
        }
        readSource.setCancelHandler { [weak self] in
            guard let self else {
                return
            }

            if self.fileDescriptor != -1 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.readSource = readSource
        readSource.resume()

        return stream
    }

    private func readHandshakeEnvelope(from descriptor: Int32) throws -> BridgeEnvelope {
        var buffer = Data(); var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = read(descriptor, &bytes, bytes.count)
            if count > 0 { buffer.append(bytes, count: count); if let message = try BridgeCodec.decodeLines(from: &buffer).first { return message }; continue }
            if count == 0 { throw BridgeTransportError.protocolUpgradeRequired }
            throw BridgeTransportError.systemCallFailed("read", errno)
        }
    }

    public func send(_ command: BridgeCommand) async throws {
        guard fileDescriptor != -1 else {
            throw BridgeTransportError.notConnected
        }

        let data = try BridgeCodec.encodeLine(.command(command))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: BridgeTransportError.notConnected)
                    return
                }

                guard self.fileDescriptor != -1 else {
                    continuation.resume(throwing: BridgeTransportError.notConnected)
                    return
                }

                do {
                    try writeAll(data, to: self.fileDescriptor)
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.readSource?.cancel()
            self.readSource = nil
            self.buffer.removeAll(keepingCapacity: false)
            self.finish(throwing: nil)
        }
    }

    private func readAvailableData() {
        guard fileDescriptor != -1 else {
            return
        }

        var localBuffer = [UInt8](repeating: 0, count: 8_192)

        while true {
            let bytesRead = read(fileDescriptor, &localBuffer, localBuffer.count)

            if bytesRead > 0 {
                buffer.append(localBuffer, count: bytesRead)

                do {
                    let messages = try BridgeCodec.decodeLines(from: &buffer)

                    for message in messages {
                        if case let .event(event) = message {
                            continuation?.yield(event)
                        }
                    }
                } catch {
                    finish(throwing: error)
                    readSource?.cancel()
                    readSource = nil
                    return
                }

                continue
            }

            if bytesRead == 0 {
                finish(throwing: nil)
                readSource?.cancel()
                readSource = nil
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }

            finish(throwing: BridgeTransportError.systemCallFailed("read", errno))
            readSource?.cancel()
            readSource = nil
            return
        }
    }

    private func finish(throwing error: Error?) {
        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }

        continuation = nil
    }
}
