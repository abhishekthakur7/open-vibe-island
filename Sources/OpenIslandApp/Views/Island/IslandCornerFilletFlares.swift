import SwiftUI

/// R6 · N-10 (PI-B-003) — one concave quarter-round corner piece, the native
/// counterpart of the reference's `.fillet.l` / `.fillet.r` spans
/// (`docs/design/overlay-redesign/01-poured-island.html:136-143`).
///
/// The reference builds it by **masking a square with a radial gradient**
/// centred on the square's own outer top corner: everything within `--fillet` of
/// that corner is transparent, everything beyond it is filled. What survives is
/// the concave wedge that hugs the body wall — the shape that makes the slab
/// read as *poured out of* the menu-bar line rather than butted against it.
///
/// This reproduces that mask exactly rather than approximating it with an arc:
/// the square minus the quarter disc, via `Path.subtracting`. Same region, same
/// tangency, no hand-rolled arc-direction ambiguity.
struct IslandCornerFilletShape: Shape {
    /// Which body edge this piece sits **outside** of. `.leading` hangs off the
    /// left wall (its disc is centred on its own top-left corner), `.trailing`
    /// off the right (top-right corner).
    enum Side: Equatable {
        case leading
        case trailing
    }

    var side: Side

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height)
        let centre: CGPoint
        switch side {
        case .leading:  centre = CGPoint(x: rect.minX, y: rect.minY)
        case .trailing: centre = CGPoint(x: rect.maxX, y: rect.minY)
        }
        let disc = Path(
            ellipseIn: CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        return Path(rect).subtracting(disc)
    }
}

/// The two flares a surface wears at its top outer corners, drawn in an
/// `.overlay` and offset **outward** by one fillet so they sit outside the
/// silhouette — mirroring the reference's `position:absolute; left:-12px /
/// right:-12px` spans, which are likewise out of flow. The host view's layout
/// width is therefore unchanged, which is what keeps the closed-pill width
/// goldens (`V6ClosedPill.externalOuterWidth` and friends) green.
///
/// **Reduce Transparency**: the flare is *body tone*, not sheen — the reference
/// fills it from `--glass-fillet`, a near-opaque ink, not from `--specular` or
/// `--hairline-inset`. So unlike the light layers (which stand down entirely
/// under RT) the flares stay, repainted in the flat RT body tone
/// (`surfaceInk`) so the corner piece and the slab it continues are the same
/// colour. Standing them down instead would change the *silhouette* under RT,
/// which no accessibility setting asks for.
struct IslandCornerFilletFlares: ViewModifier {
    let token: IslandCornerFilletToken
    /// Fades the pair out as the closed pill morphs into the panel, whose own
    /// concave shoulders (`NotchShape`'s top fillet, live from
    /// `topCornerRadius > 0`) take over the same corner.
    var flareOpacity: Double = 1

    @Environment(\.islandTokens) private var tokens
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                flare(.leading).offset(x: -token.size)
            }
            .overlay(alignment: .topTrailing) {
                flare(.trailing).offset(x: token.size)
            }
    }

    private func flare(_ side: IslandCornerFilletShape.Side) -> some View {
        IslandCornerFilletShape(side: side)
            .fill(reduceTransparency ? tokens.colors.surfaceInk : token.resolvedColor)
            .frame(width: token.size, height: token.size)
            .opacity(flareOpacity)
            .allowsHitTesting(false)
    }
}

extension View {
    /// Attaches the theme's top-corner fillet flares, or nothing at all when the
    /// theme declares none (`nil` — every theme but Poured, whose render tree is
    /// therefore untouched).
    @ViewBuilder
    func islandCornerFilletFlares(_ token: IslandCornerFilletToken?, opacity: Double = 1) -> some View {
        if let token, opacity > 0 {
            modifier(IslandCornerFilletFlares(token: token, flareOpacity: opacity))
        } else {
            self
        }
    }
}
