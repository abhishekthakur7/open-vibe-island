import SwiftUI

/// A drop shadow expressed as data rather than a pre-applied modifier, so a
/// theme can declare one and any view can apply it.
struct IslandShadowToken: Equatable, Sendable {
    /// Base shadow colour, before `opacity` is applied.
    var color: Color

    /// Opacity applied to `color`.
    var opacity: Double

    /// Blur radius passed to `View.shadow(color:radius:x:y:)`.
    var radius: CGFloat

    /// Vertical offset passed to `View.shadow(color:radius:x:y:)`.
    var yOffset: CGFloat

    /// `color` with `opacity` folded in — the value handed to `.shadow(...)`.
    var resolvedColor: Color {
        color.opacity(opacity)
    }
}

/// Geometry half of the island theme token layer.
///
/// Values are lifted verbatim from `NotchShape`'s opened-state radii,
/// `IslandChromeMetrics`' shadow insets and hover scale, and the opened
/// surface's shadow in `IslandPanelView`.
///
/// Nothing consumes these yet — later tickets route views through the token
/// layer one region at a time.
struct IslandMetricsTokens: Equatable, Sendable {
    /// Concave top-corner radius of the opened island shape.
    var openedTopRadius: CGFloat

    /// Rounded bottom-corner radius of the opened island shape.
    var openedBottomRadius: CGFloat

    /// Drop shadow cast by the opened island surface.
    var surfaceShadow: IslandShadowToken

    /// Horizontal padding the opened shadow needs inside the overlay window
    /// so it is not clipped.
    var openedShadowHorizontalInset: CGFloat

    /// Bottom padding the opened shadow needs inside the overlay window.
    var openedShadowBottomInset: CGFloat

    /// Horizontal padding reserved for the closed pill's shadow.
    var closedShadowHorizontalInset: CGFloat

    /// Bottom padding reserved for the closed pill's shadow.
    var closedShadowBottomInset: CGFloat

    /// Scale applied to the closed pill while the pointer hovers it.
    var closedHoverScale: CGFloat
}

// MARK: - Classic

extension IslandMetricsTokens {
    /// Today's shipping geometry, expressed as literals so the token layer is
    /// self-contained once the legacy constants are retired.
    static let classic = IslandMetricsTokens(
        openedTopRadius: 22,
        openedBottomRadius: 22,
        surfaceShadow: IslandShadowToken(
            color: .black,
            opacity: 0.36,
            radius: 22,
            yOffset: 12
        ),
        openedShadowHorizontalInset: 18,
        openedShadowBottomInset: 22,
        closedShadowHorizontalInset: 12,
        closedShadowBottomInset: 14,
        closedHoverScale: 1.028
    )
}
