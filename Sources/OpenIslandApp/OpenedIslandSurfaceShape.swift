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

    /// Concave notch-junction fillet (AB-300), forwarded to `NotchShape`. Only
    /// meaningful for the `.notch` profile — the `.topBar` variant has no
    /// physical notch to merge with, so it renders matched radii with no
    /// fillet regardless of this value.
    var filletRadius: CGFloat = 0

    /// PI-B-003: all three silhouette radii travel together.
    ///
    /// `filletRadius` used to sit outside `animatableData`, which made it a
    /// *plain* argument on an otherwise animatable shape: on any implicit
    /// animation whose endpoints differ in fillet (the Reduce-Motion closed
    /// surface, the docked hover peek, or any future theme whose closed and
    /// opened fillets are not equal) the two corner radii would interpolate
    /// while the fillet snapped to its final value on the first frame — a
    /// topology break exactly where the reference demands one continuous body.
    /// Nesting it here removes that whole class of snap. For Poured today both
    /// endpoints pass the same token fillet (12), so this is behaviour-neutral
    /// at the current values and correct for differing ones.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(topCornerRadius, bottomCornerRadius), filletRadius) }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            filletRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch topProfile {
        case .notch:
            return NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius,
                filletRadius: filletRadius
            )
            .path(in: rect)
        case .topBar:
            return V6ClosedPillShape(cornerRadius: bottomCornerRadius)
                .path(in: rect)
        }
    }
}
