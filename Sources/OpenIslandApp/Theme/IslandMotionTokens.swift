import SwiftUI

/// A SwiftUI `Animation` described by its parameters instead of by the opaque
/// `Animation` value itself.
///
/// Storing parameters (rather than a built `Animation`) keeps the token layer
/// inspectable: tests can pin `response`/`dampingFraction`/`duration` exactly,
/// and a future theme can derive one animation from another (e.g. scale a
/// duration for Reduce Motion) instead of only replacing it wholesale.
/// `animation` builds the SwiftUI value at the call site.
enum IslandAnimationToken: Equatable, Sendable {
    /// `Animation.spring(response:dampingFraction:blendDuration:)`
    case spring(response: Double, dampingFraction: Double, blendDuration: Double)

    /// `Animation.smooth(duration:extraBounce:)`
    case smooth(duration: TimeInterval, extraBounce: Double)

    /// `Animation.easeInOut(duration:)`
    case easeInOut(duration: TimeInterval)

    /// The SwiftUI animation these parameters describe.
    var animation: Animation {
        switch self {
        case let .spring(response, dampingFraction, blendDuration):
            .spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
        case let .smooth(duration, extraBounce):
            .smooth(duration: duration, extraBounce: extraBounce)
        case let .easeInOut(duration):
            .easeInOut(duration: duration)
        }
    }
}

/// Motion half of the island theme token layer.
///
/// Values are lifted verbatim from the file-private animation constants in
/// `IslandPanelView` that drive the closed ↔ opened ↔ popping transitions.
///
/// Nothing consumes these yet — later tickets route views through the token
/// layer one region at a time.
struct IslandMotionTokens: Equatable, Sendable {
    /// Closed → opened transition.
    var openAnimation: IslandAnimationToken

    /// Opened → closed transition.
    var closeAnimation: IslandAnimationToken

    /// The attention "pop" the closed pill performs on a new event.
    var popAnimation: IslandAnimationToken

    /// How long the opened surface stays mounted after a close, so the
    /// closing animation can finish before the view tears down.
    var openedSurfaceUnmountDelay: TimeInterval
}

// MARK: - Classic

extension IslandMotionTokens {
    /// Today's shipping motion, expressed as literals so the token layer is
    /// self-contained once the legacy constants are retired.
    static let classic = IslandMotionTokens(
        openAnimation: .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0),
        closeAnimation: .smooth(duration: 0.3, extraBounce: 0),
        popAnimation: .spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0),
        openedSurfaceUnmountDelay: 0.36
    )
}
