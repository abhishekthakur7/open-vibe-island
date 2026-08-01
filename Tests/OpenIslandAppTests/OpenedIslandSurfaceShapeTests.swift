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
    func animatableDataRoundTripsAllThreeRadiiIncludingFillet() {
        var shape = OpenedIslandSurfaceShape(
            topProfile: .notch,
            topCornerRadius: 4,
            bottomCornerRadius: 9,
            filletRadius: 3
        )

        let data = shape.animatableData
        #expect(data.first.first == 4)
        #expect(data.first.second == 9)
        #expect(data.second == 3)

        shape.animatableData = .init(.init(22, 22), 12)
        #expect(shape.topCornerRadius == 22)
        #expect(shape.bottomCornerRadius == 22)
        #expect(shape.filletRadius == 12)
    }

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

    @Test
    func pathStaysContinuousWhenTheFilletItselfInterpolates() {
        // The case the plain-argument fillet used to snap through — differing
        // endpoints. Sampled through the `filletRadius > 0` branch boundary.
        let rect = CGRect(x: 0, y: 0, width: 420, height: 220)
        var previous = points(morphShape(0.5, fillet: 0.0001), in: rect)

        for step in 1...50 {
            let fillet = CGFloat(step) / 50 * 12
            let current = points(morphShape(0.5, fillet: fillet), in: rect)
            #expect(current.count == previous.count)
            #expect(maxDelta(previous, current) < 1)
            previous = current
        }
    }

    @Test
    func filletCollapsesContinuouslyIntoTheZeroFilletBranch() {
        // `NotchShape` swaps a cubic pair for a quadratic pair at exactly 0, so
        // the element *count* differs there by construction; what must hold is
        // that the rendered outline converges. Compare bounding boxes and the
        // shared endpoints instead of the raw control lists.
        let rect = CGRect(x: 0, y: 0, width: 420, height: 220)
        let zero = morphShape(0.5, fillet: 0).path(in: rect)
        let epsilon = morphShape(0.5, fillet: 0.0001).path(in: rect)
        #expect(abs(zero.boundingRect.width - epsilon.boundingRect.width) < 0.01)
        #expect(abs(zero.boundingRect.height - epsilon.boundingRect.height) < 0.01)
        #expect(abs(zero.boundingRect.minX - epsilon.boundingRect.minX) < 0.01)
        #expect(abs(zero.boundingRect.minY - epsilon.boundingRect.minY) < 0.01)
    }

    // MARK: - Profile consistency

    @Test
    func topBarProfileIgnoresTheFilletEntirely() {
        let rect = CGRect(x: 0, y: 0, width: 420, height: 220)
        let withoutFillet = points(
            OpenedIslandSurfaceShape(topProfile: .topBar, topCornerRadius: 22, bottomCornerRadius: 22, filletRadius: 0),
            in: rect
        )
        let withFillet = points(
            OpenedIslandSurfaceShape(topProfile: .topBar, topCornerRadius: 22, bottomCornerRadius: 22, filletRadius: 12),
            in: rect
        )
        #expect(withoutFillet.count == withFillet.count)
        #expect(maxDelta(withoutFillet, withFillet) == 0)
    }
}
