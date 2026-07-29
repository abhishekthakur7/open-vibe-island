import Foundation

/// Retained only as a source-compatible inert type for callers compiled
/// against earlier releases. Local-only mode never sends keys or invokes
/// Accessibility/AppleScript to control another application.
public protocol KeystrokeInjector {
    func sendCmdShiftRightBracket()
}

public struct DefaultKeystrokeInjector: KeystrokeInjector {
    public init() {}
    public func sendCmdShiftRightBracket() {}
}
