import Foundation
@testable import OpenIslandCore

/// Transport tests deliberately inject this validator. Production always uses
/// `DefaultBridgeSignatureValidator`, which requires a real peer PID and a
/// designated-requirement match for the bundled helper or running app.
struct BridgeTestSignatureValidator: BridgeSignatureValidating {
    func validates(peer: BridgePeerIdentity, role: BridgeClientRole) -> Bool {
        peer.uid == getuid() && peer.pid != nil
    }
}

extension BridgeServer {
    convenience init(socketURL: URL) {
        self.init(
            socketURL: socketURL,
            signatureValidator: BridgeTestSignatureValidator(),
            rotateBootstrapOnStart: false
        )
    }
}
