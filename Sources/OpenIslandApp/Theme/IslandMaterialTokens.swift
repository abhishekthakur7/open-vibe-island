import AppKit
import SwiftUI

/// A bright specular highlight painted along the top edge of a frosted
/// surface, expressed as data so a theme can declare one and the surface view
/// can apply it. `nil` on a theme means "no specular" — the flat, unlit look
/// Classic ships.
struct IslandSpecularEdge: Equatable, Sendable {
    /// Highlight colour, before `opacity` is applied.
    var color: Color

    /// Peak opacity of the highlight at the very top edge.
    var opacity: Double

    /// Height of the soft sheen that falls off below the crisp top line.
    var sheenHeight: CGFloat
}

/// One stop of a surface body gradient, expressed as data so a theme can
/// declare a multi-stop vertical fill and the surface view can apply it. Mirrors
/// `IslandShadowToken`'s shape — a base colour, an `opacity` folded into it, and
/// a `resolvedColor` convenience — plus the `location` along the 0→1 axis.
///
/// A theme carries `nil` for its body gradient (see `IslandMaterialTokens`) to
/// keep the flat single-ink fill Classic ships; a non-`nil` list paints inner
/// luminance (lighter top → darker bottom) so the slab reads as elevated glass.
struct IslandGradientStop: Equatable, Sendable {
    /// Base stop colour, before `opacity` is applied.
    var color: Color

    /// Opacity applied to `color`.
    var opacity: Double

    /// Position of the stop along the gradient's start→end axis (`0`…`1`).
    var location: CGFloat

    /// `color` with `opacity` folded in — the value handed to `Gradient.Stop`.
    var resolvedColor: Color {
        color.opacity(opacity)
    }
}

/// A faint inner inset stroke painted just inside a frosted surface's edge,
/// expressed as data so a theme can declare one and the surface view can apply
/// it. The stroke colour is white (matching the specular light-catch family);
/// only its `opacity` and `width` vary. `nil` on a theme means "no inner
/// hairline" — the un-edged look Classic ships.
///
/// A dedicated `Equatable`/`Sendable` struct rather than a bare tuple so the
/// enclosing `IslandMaterialTokens` keeps synthesising `Equatable`.
struct IslandHairlineToken: Equatable, Sendable {
    /// Opacity of the white inner stroke.
    var opacity: Double

    /// Line width of the inner stroke, in points.
    var width: CGFloat
}

/// The concave quarter-round corner piece a surface flares into at its **top
/// outer** corners, where the slab fuses back up into the menu-bar/notch line.
///
/// The reference draws it as two absolutely-positioned `.fillet.l` / `.fillet.r`
/// spans hanging OUTSIDE the body (`01-poured-island.html:136-143`): a
/// `--fillet` (12px) square at `left:-12px` / `right:-12px`, filled with
/// `--glass-fillet` (`rgba(20,25,36,.92)`, `:50`) and masked by a
/// `radial-gradient` centred on its own outer top corner so the remaining
/// opaque region is concave. Because they are positioned out of flow, they add
/// nothing to the pill's layout width — the native flares mirror that exactly
/// (drawn in an `.overlay`, offset outward), so every closed-pill width golden
/// is untouched.
///
/// `nil` on a theme means "no flares" — the square-topped surface every theme
/// but Poured has always drawn (Slice-2 nullable-token precedent).
struct IslandCornerFilletToken: Equatable, Sendable {
    /// Base fill tone, before `opacity` is applied. Body tone, **not** a sheen —
    /// the flare is a continuation of the slab, not a light layer.
    var color: Color

    /// Opacity applied to `color`.
    var opacity: Double

    /// Side of the square quarter-round piece, in points (the reference's
    /// `--fillet`).
    var size: CGFloat

    /// `color` with `opacity` folded in — the value handed to the fill.
    var resolvedColor: Color {
        color.opacity(opacity)
    }
}

/// Material half of the island theme token layer (AB-300).
///
/// The opened surface's vibrancy was hardcoded in `OpenedSurfaceMaterial.swift`
/// as `.hudWindow` / `.behindWindow` / `.vibrantDark` with a fixed `0.6` ink
/// tint and no specular edge. A liquid-glass theme needs its own material
/// family, a lighter tint so more of the blur reads through, and a specular
/// top edge — so those values move here, one axis per theme, exactly like the
/// colour / metric / motion axes.
///
/// The `NSVisualEffectView` enums are plain value types, so this struct stays
/// `Equatable` + `Sendable` like the rest of the token layer. The ink tint
/// itself is not stored here — it's derived from `IslandColorTokens.surfaceInk`
/// at the call site so the surface keeps one source of truth for its ink — only
/// the *opacity* of that tint lives here.
struct IslandMaterialTokens: Equatable, Sendable {
    /// `NSVisualEffectView.material` for the frosted base.
    var material: NSVisualEffectView.Material

    /// `NSVisualEffectView.blendingMode`.
    var blendingMode: NSVisualEffectView.BlendingMode

    /// Forced appearance for the effect view, or `nil` to inherit.
    var appearanceName: NSAppearance.Name?

    /// Opacity of the `surfaceInk` tint painted over the vibrancy to hold the
    /// surface's identity and text contrast against bright wallpapers.
    var tintOpacity: Double

    /// Specular top edge, or `nil` for a flat, unlit surface (Classic).
    var specularTopEdge: IslandSpecularEdge?

    // MARK: - Poured 2.0 liquid-glass layers (AB-329)
    //
    // All three are optional and default to `nil` so the memberwise
    // initializer keeps the four flat themes' `static let` call sites compiling
    // unchanged — `nil` reproduces exactly today's rendering
    // (`OpenedSurfaceBackground` byte-identical). Only Poured opts in.

    /// A multi-stop vertical body gradient painted **instead of** the flat
    /// `surfaceInk.opacity(tintOpacity)` fill, so elevation is carried by inner
    /// luminance (lighter top → darker bottom) rather than a flat panel. `nil`
    /// keeps the flat ink tint.
    var bodyGradient: [IslandGradientStop]? = nil

    /// A crisp 1pt hard specular line painted at the very top edge **in addition
    /// to** the soft `specularTopEdge` sheen — the `sheenHeight` field is read as
    /// the line's thickness (1pt). `nil` keeps only the soft sheen (or nothing).
    var specularHardEdge: IslandSpecularEdge? = nil

    /// A faint white inner inset stroke just inside the surface edge. `nil`
    /// leaves the surface un-edged.
    var innerHairline: IslandHairlineToken? = nil

    /// The white edge stroke the opened surface's *content* layer carries
    /// (`IslandPanelView` / `AppearanceSettingsPane`), previously hardcoded as
    /// `0.07 @ 1pt` for every theme. Defaulted to exactly that value so the five
    /// non-Poured themes render byte-identically without touching their
    /// `static let`s; `nil` drops the stroke entirely.
    ///
    /// Poured opts out (PI-M-002): the reference glass body
    /// (`01-poured-island.html:48-53`) declares exactly ONE inner edge — the
    /// 0.5pt `--hairline-inset` carried by `innerHairline` — so keeping this
    /// second stroke would double the surface's inner edge.
    var contentEdgeStroke: IslandHairlineToken? = IslandHairlineToken(opacity: 0.07, width: 1)

    /// PI-B-002: the closed pill, the hover peek and the opened panel are ONE
    /// continuous glass body, so the open/close morph must paint exactly ONE
    /// background at rest and at every point of the interpolant.
    ///
    /// When `false` (every theme but Poured, so their render trees are
    /// untouched) a vibrancy theme's morph stacks two materials and crossfades
    /// them by opacity — two layers at `o` and `1 - o` composite to
    /// `1 - o + o²`, i.e. the body is only ~75% opaque at the midpoint and the
    /// desktop reads straight through it (the M-23 defect, previously fixed
    /// only for opaque-ink themes). It also parks the theme's inner hairline
    /// inside the opacity-gated layer, so the one edge the reference declares
    /// is only partially painted mid-morph.
    ///
    /// When `true` the morph renders a single `OpenedSurfaceBackground` over
    /// the live interpolating shape — no underlay, no opacity stack — and the
    /// closed pill stands its own fill down (`\.islandClosedPillPaintsOwnSurface`)
    /// so the rest-state pill is painted by that same one body. Reduce
    /// Transparency still wins: the opaque-ink branch is already a single
    /// layer.
    var morphsAsOneBody: Bool = false

    /// R6 · N-10 (PI-B-003): the concave top-outer-corner flares the closed pill
    /// and the hover peek draw. `nil` (every theme but Poured) keeps the
    /// square-topped surface they have always rendered.
    var cornerFillet: IslandCornerFilletToken? = nil
}

// MARK: - Classic

extension IslandMaterialTokens {
    /// Today's shipping vibrancy: the `.hudWindow` HUD family sampling what's
    /// behind the window, tinted `0.6` toward ink, with no specular edge.
    /// Lifted verbatim from `OpenedSurfaceMaterial.swift`.
    static let classic = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 0.6,
        specularTopEdge: nil
    )
}

// MARK: - Poured Island

extension IslandMaterialTokens {
    /// Poured Island's frosted slab: the same always-dark HUD family, but a
    /// lighter ink tint so more of the heavy blur reads through as glass, plus
    /// the light-carried layers (AB-329) so hierarchy comes from light rather
    /// than chrome — a 3-stop body gradient (inner luminance, lighter top →
    /// darker bottom), a crisp 1pt hard specular top line, and a faint 0.5pt
    /// inner hairline.
    ///
    /// PI-M-001: `specularTopEdge` is deliberately `nil`. The reference glass
    /// body (`docs/design/overlay-redesign/01-poured-island.html:48-53`) carries
    /// only `--specular` (a 1px white@14% top catch), `--hairline-inset` (0.5px
    /// white@5%) and the drop shadow — there is **no** broad soft sheen anywhere
    /// in it, so the native 26pt white@50% wash had no reference counterpart and
    /// is removed.
    static let poured = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 0.5,
        specularTopEdge: nil,
        bodyGradient: [
            IslandGradientStop(
                color: Color(red: 26 / 255.0, green: 31 / 255.0, blue: 44 / 255.0),
                opacity: 0.86,
                location: 0.0
            ),
            IslandGradientStop(
                color: Color(red: 13 / 255.0, green: 17 / 255.0, blue: 26 / 255.0),
                opacity: 0.94,
                location: 0.62
            ),
            IslandGradientStop(
                color: Color(red: 9 / 255.0, green: 12 / 255.0, blue: 20 / 255.0),
                opacity: 0.96,
                location: 1.0
            ),
        ],
        specularHardEdge: IslandSpecularEdge(
            color: .white,
            opacity: 0.14,
            sheenHeight: 1
        ),
        innerHairline: IslandHairlineToken(
            opacity: 0.05,
            width: 0.5
        ),
        // PI-M-002: exactly ONE inner edge on the glass body — the 0.5pt
        // hairline above. The all-theme 0.07/1pt content-layer stroke would be a
        // second one, so Poured drops it.
        contentEdgeStroke: nil,
        // PI-B-002: pill → peek → panel is one continuous blue-black glass
        // body, so the morph paints one material for the whole interpolant.
        morphsAsOneBody: true,
        // R6 · N-10: `--glass-fillet: rgba(20,25,36,.92)` at `--fillet: 12px`
        // (`01-poured-island.html:50,56,136-143`) — every rendered `.pill` and
        // the §B peek body carry the two concave flares.
        cornerFillet: IslandCornerFilletToken(
            color: Color(red: 20 / 255.0, green: 25 / 255.0, blue: 36 / 255.0),
            opacity: 0.92,
            size: 12
        )
    )
}

// MARK: - Instrument

extension IslandMaterialTokens {
    /// Instrument is a flat panel, not glass: `InstrumentTheme.usesVibrancy` is
    /// `false`, so `OpenedSurfaceBackground` takes the opaque `surfaceInk` path
    /// and never instantiates a vibrancy view. These values are the fallback the
    /// surface would use if vibrancy were ever forced on — a fully opaque ink
    /// tint (`1.0`) and no specular edge, i.e. the same flat, unlit readout even
    /// then. Reduce Transparency is therefore a no-op for this theme: the surface
    /// is already flat.
    static let instrument = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 1.0,
        specularTopEdge: nil
    )
}

// MARK: - Flight Deck

extension IslandMaterialTokens {
    /// Flight Deck is unlit hardware, not glass: `FlightDeckTheme.usesVibrancy`
    /// is `false`, so `OpenedSurfaceBackground` takes the opaque `surfaceInk`
    /// path and never instantiates a vibrancy view. These values are the fallback
    /// the surface would use if vibrancy were ever forced on — a fully opaque ink
    /// tint (`1.0`) and no specular edge, i.e. the same flat annunciator ground
    /// even then. Reduce Transparency is therefore a no-op for this theme: the
    /// panel is already opaque.
    static let flightDeck = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 1.0,
        specularTopEdge: nil
    )
}

// MARK: - Annual

extension IslandMaterialTokens {
    /// Annual is a printed editorial page, not glass: `AnnualTheme.usesVibrancy`
    /// is `false`, so `OpenedSurfaceBackground` takes the opaque `surfaceInk` path
    /// and never instantiates a vibrancy view. These values are the fallback the
    /// surface would use if vibrancy were ever forced on — a fully opaque ink
    /// tint (`1.0`) and no specular edge, i.e. the same flat warm ground even
    /// then. Reduce Transparency is therefore a no-op for this theme: the page is
    /// already opaque.
    static let annual = IslandMaterialTokens(
        material: .hudWindow,
        blendingMode: .behindWindow,
        appearanceName: .vibrantDark,
        tintOpacity: 1.0,
        specularTopEdge: nil
    )
}
