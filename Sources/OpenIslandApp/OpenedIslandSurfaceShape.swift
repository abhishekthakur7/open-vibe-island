import SwiftUI

struct OpenedIslandSurfaceShape: Shape {
    enum TopProfile: Equatable {
        case notch
        case topBar
    }

    var topProfile: TopProfile
    /// Only meaningful for `.notch` — `NotchShape`'s concave top curve
    /// degenerates to a flat top edge at `0`, which is what makes it usable
    /// as the single shape driving the closed→opened morph on notched Macs
    /// (AB-243): the closed pill's flat top *is* `topCornerRadius == 0`.
    /// `.topBar` ignores this entirely (`V6ClosedPillShape` never rounds
    /// its top edge, at rest or mid-morph).
    var topCornerRadius: CGFloat = NotchShape.openedTopRadius
    var bottomCornerRadius: CGFloat = NotchShape.openedBottomRadius

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch topProfile {
        case .notch:
            return NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .path(in: rect)
        case .topBar:
            return V6ClosedPillShape(cornerRadius: bottomCornerRadius)
                .path(in: rect)
        }
    }
}
