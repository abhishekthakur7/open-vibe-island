import SwiftUI

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    /// Concave fillet at the top (notch-junction) corners, in points (AB-300).
    /// `0` reproduces the plain concave top corner Open Island has always
    /// shipped; a positive value deepens and softens the transition into a
    /// "poured" fillet. Deliberately *not* part of `animatableData`: the fillet
    /// is a constant per-theme identity, only the corner radii interpolate
    /// across the closed↔opened morph.
    var filletRadius: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let topR = min(topCornerRadius, rect.width / 4, rect.height / 4)
        let botR = min(bottomCornerRadius, rect.width / 4, rect.height / 2)

        var path = Path()

        // Start at top-left, after the inward curve
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        guard filletRadius > 0 else {
            // Classic path — byte-identical to before AB-300.
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + topR, y: rect.minY + topR),
                control: CGPoint(x: rect.minX + topR, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
                control: CGPoint(x: rect.minX + topR, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
                control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.maxX - topR, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        }

        // Filleted ("poured") path: the top edge lingers near the menu bar and
        // the wall drops away through a deeper concave curve, so the stem
        // merges into the panel body instead of turning a hard concave corner.
        // The fillet is clamped so the two top curves never meet the bottom
        // corners, keeping the outline free of self-intersections at any size.
        let f = min(filletRadius, rect.height / 2 - botR, rect.width / 4)

        // Top-left concave fillet
        path.addCurve(
            to: CGPoint(x: rect.minX + topR, y: rect.minY + topR + f),
            control1: CGPoint(x: rect.minX + topR, y: rect.minY),
            control2: CGPoint(x: rect.minX + topR, y: rect.minY + f)
        )

        // Left edge down to bottom-left corner
        path.addLine(to: CGPoint(x: rect.minX + topR, y: rect.maxY - botR))

        // Bottom-left rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topR + botR, y: rect.maxY),
            control: CGPoint(x: rect.minX + topR, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topR - botR, y: rect.maxY))

        // Bottom-right rounded corner
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topR, y: rect.maxY - botR),
            control: CGPoint(x: rect.maxX - topR, y: rect.maxY)
        )

        // Right edge up to the top-right concave fillet
        path.addLine(to: CGPoint(x: rect.maxX - topR, y: rect.minY + topR + f))

        // Top-right concave fillet
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - topR, y: rect.minY + f),
            control2: CGPoint(x: rect.maxX - topR, y: rect.minY)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        path.closeSubpath()
        return path
    }
}

extension NotchShape {
    /// The opened island uses a concave-top-corner notch shape so it blends
    /// with the physical MacBook notch on built-in displays. The closed
    /// state no longer uses this shape — it renders via `V6ClosedPillShape`
    /// instead.
    static let openedTopRadius: CGFloat = 22
    static let openedBottomRadius: CGFloat = 22

    static var opened: NotchShape {
        NotchShape(topCornerRadius: openedTopRadius, bottomCornerRadius: openedBottomRadius)
    }
}
