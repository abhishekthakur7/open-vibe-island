import AppKit
import SwiftUI

/// Thin `NSVisualEffectView` wrapper providing a themed vibrancy base (AB-242,
/// AB-300). The material / blending / appearance are supplied by the active
/// theme's `IslandMaterialTokens` rather than hardcoded, so a liquid-glass
/// theme can pick its own family without every surface knowing about it.
///
/// Classic keeps the same `.hudWindow` / `.behindWindow` / `.vibrantDark`
/// configuration it always shipped — the HUD family is always dark and always
/// translucent regardless of system light/dark mode, matching this app's forced
/// `.dark` `preferredColorScheme`, and `.behindWindow` samples whatever sits
/// behind the panel so the overlay reads as a native blurred surface.
private struct VibrancyView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var appearanceName: NSAppearance.Name?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Reapply so a live theme switch retargets the effect view.
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.appearance = appearanceName.map { NSAppearance(named: $0) } ?? nil
    }
}

/// The bright specular highlight painted along a frosted surface's top edge
/// (AB-300): a crisp near-opaque line at the very top fading into a soft sheen
/// below. Clipped by the caller to the surface shape, so it follows the
/// concave/filleted top rather than a plain rectangle.
struct OpenedSurfaceSpecularEdge: View {
    var edge: IslandSpecularEdge

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: edge.color.opacity(edge.opacity), location: 0),
                .init(color: edge.color.opacity(edge.opacity * 0.35), location: 0.14),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: edge.sheenHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

/// Opened-surface fill (AB-242, AB-300): themed vibrancy tinted toward the
/// theme's `surfaceInk`, topped with the theme's specular edge, so the surface
/// reads as translucent native glass instead of a flat slab. Falls back to a
/// flat `surfaceInk` fill whenever `reduceTransparency` is set (or the theme
/// opts out of vibrancy) — pass in `@Environment(\.accessibilityReduceTransparency)`,
/// which SwiftUI keeps current as the user toggles System Settings →
/// Accessibility → Display → Reduce Transparency.
struct OpenedSurfaceBackground: View {
    var reduceTransparency: Bool

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        if reduceTransparency {
            // Flat, opaque, legible — no glass, no specular sheen.
            tokens.colors.surfaceInk
        } else {
            let material = tokens.material
            ZStack {
                VibrancyView(
                    material: material.material,
                    blendingMode: material.blendingMode,
                    appearanceName: material.appearanceName
                )
                // Keeps the surface's ink identity and text contrast intact
                // over both bright and dark wallpapers — the blur alone would
                // let a light wallpaper wash the panel out.
                tokens.colors.surfaceInk.opacity(material.tintOpacity)

                if let specular = material.specularTopEdge {
                    OpenedSurfaceSpecularEdge(edge: specular)
                }
            }
        }
    }
}
