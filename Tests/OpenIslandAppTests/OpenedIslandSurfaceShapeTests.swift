import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// PI-B-003: the notch fillet travels inside `animatableData` with the two
/// corner radii, so every silhouette parameter interpolates together and no
/// implicit animation can snap one of them to its endpoint on frame one.
struct OpenedIslandSurfaceShapeTests {

    // MARK: - Helpers

    /// Every point the path emits, in order (endpoints *and* control points).
    /// A stable count is topology; a small per-step delta is continuity.
    private func points(_ shape: OpenedIslandSurfaceShape, in rect: CGRect) -> [CGPoint] {
        var collected: [CGPoint] = []
        shape.path(in: rect).cgPath.applyWithBlock { element in
            let e = element.pointee
            let count: Int
            switch e.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            case .closeSubpath: count = 0
            @unknown default: count = 0
            }
            for i in 0..<count { collected.append(e.points[i]) }
        }
        return collected
    }

    private func maxDelta(_ a: [CGPoint], _ b: [CGPoint]) -> CGFloat {
        guard a.count == b.count else { return .infinity }
        return zip(a, b).reduce(0) { partial, pair in
            max(partial, max(abs(pair.0.x - pair.1.x), abs(pair.0.y - pair.1.y)))
        }
    }

    /// The Poured morph's own geometry (`IslandPanelView.morphingIslandSurface`):
    /// top radius grows from 0, bottom radius from the closed pill's half-height.
    private func morphShape(_ t: CGFloat, fillet: CGFloat, closedHalfHeight: CGFloat = 16) -> OpenedIslandSurfaceShape {
        OpenedIslandSurfaceShape(
            topProfile: .notch,
            topCornerRadius: NotchShape.openedTopRadius * t,
            bottomCornerRadius: closedHalfHeight + (NotchShape.openedBottomRadius - closedHalfHeight) * t,
            filletRadius: fillet
        )
    }

    // MARK: - Animatable data

    @Test
    func animatableDataInterpolatesTheFilletRatherThanSnappingIt() {
        // What SwiftUI does per frame: scale the delta and add it.
        var mid = OpenedIslandSurfaceShape(
            topProfile: .notch,
            topCornerRadius: 0,
            bottomCornerRadius: 16,
            filletRadius: 0
        )
        var delta = OpenedIslandSurfaceShape(
            topProfile: .notch,
            topCornerRadius: 22,
            bottomCornerRadius: 22,
            filletRadius: 12
        ).animatableData
        delta.scale(by: 0.5)
        var half = mid.animatableData
        half.scale(by: 0.5)
        half += delta
        mid.animatableData = half

        #expect(mid.topCornerRadius == 11)
        #expect(mid.bottomCornerRadius == 19)
        // The regression this guards: with the fillet outside `animatableData`
        // this would still read 0 (or its endpoint) at t = 0.5.
        #expect(mid.filletRadius == 6)
    }

    // MARK: - Path continuity

    @Test
    func morphPathStaysContinuousAcrossTheInterpolantAtPouredsConstantFillet() {
        let rect = CGRect(x: 0, y: 0, width: 420, height: 220)
        var previous = points(morphShape(0, fillet: 12), in: rect)
        let baselineCount = previous.count
        #expect(baselineCount > 0)

        for step in 1...50 {
            let t = CGFloat(step) / 50
            let current = points(morphShape(t, fillet: 12), in: rect)
            // Topology never changes mid-morph…
            #expect(current.count == baselineCount)
            // …and no control point can jump: a 1/50 step of a ≤22pt radius
            // sweep moves any point well under a point.
            #expect(maxDelta(previous, current) < 2)
            previous = current
        }
    }

}
