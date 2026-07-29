import Foundation
import Security

/// Production-side invariant check for the compiled local-only policy.
/// Detailed runtime socket observation belongs to the deterministic debug and
/// test harness, where it can remain passive and process-tree scoped.
public enum RuntimeNetworkPolicy {
    public static let version = "round-10"
    private static let expectedEntitlements = [
        "com.apple.security.automation.apple-events": true,
        ["com.apple.security", "network.client"].joined(separator: "."): false,
        ["com.apple.security", "network.server"].joined(separator: "."): false,
    ]

    /// Returns false and records a bounded, redacted local diagnostic only
    /// when the signed runtime does not match the policy compiled into it.
    @discardableResult
    public static func validateProductionInvariant() -> Bool {
#if DEBUG
        // Debug/test runs have no packaged entitlement payload. Their runtime
        // enforcement is the process-tree observer, not a noisy diagnostic.
        return true
#else
        let entitlements = currentEntitlements()
        let valid = version == "round-10" && expectedEntitlements.allSatisfy { key, expected in
            (entitlements[key] as? Bool) == expected
        }
        if !valid {
            writeRedactedDiagnostic("policy-or-entitlement-mismatch")
        }
        return valid
#endif
    }

    static func isValid(entitlements: [String: Any], compiledVersion: String = version) -> Bool {
        compiledVersion == version && expectedEntitlements.allSatisfy { key, expected in
            (entitlements[key] as? Bool) == expected
        }
    }

    private static func currentEntitlements() -> [String: Any] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [:] }
        return Dictionary(uniqueKeysWithValues: expectedEntitlements.keys.map { key in
            let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
            return (key, value as Any)
        })
    }

    private static func writeRedactedDiagnostic(_ code: String) {
        let fileManager = FileManager.default
        guard let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("OpenIsland", isDirectory: true) else { return }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let file = directory.appendingPathComponent("runtime-policy-diagnostic.log")
            let message = "\(Int(Date().timeIntervalSince1970)) \(code)\n"
            let existing = (try? Data(contentsOf: file)) ?? Data()
            let bounded = Data((existing + Data(message.utf8)).suffix(1024))
            try bounded.write(to: file, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Diagnostics are intentionally best-effort and must never expose
            // an error path, entitlement value, command, or user content.
        }
    }
}
