import AppKit
import SwiftUI

/// Thin `NSVisualEffectView` wrapper providing the opened overlay's vibrancy
/// base (AB-242). `.hudWindow` is the same material family macOS uses for
/// floating HUD-style panels — always dark, always translucent regardless of
/// system light/dark mode — which matches this app's forced `.dark`
/// `preferredColorScheme`. `.behindWindow` blending samples whatever sits
/// behind the panel (desktop, other app windows) so the overlay reads as a
/// native blurred surface instead of a flat slab.
private struct VibrancyView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        // Static configuration — nothing changes per-render.
    }
}

/// Opened-surface fill (AB-242): HUD vibrancy tinted toward the theme's
/// `surfaceInk` under normal conditions, so the surface reads as translucent
/// native material instead of the previous flat `#0d0d0f` slab. Falls back to
/// that original flat fill whenever `reduceTransparency` is set — pass in
/// `@Environment(\.accessibilityReduceTransparency)`, which SwiftUI keeps
/// current as the user toggles System Settings → Accessibility → Display →
/// Reduce Transparency, not just at launch.
struct OpenedSurfaceBackground: View {
    var reduceTransparency: Bool

    @Environment(\.islandTokens) private var tokens

    var body: some View {
        if reduceTransparency {
            tokens.colors.surfaceInk
        } else {
            ZStack {
                VibrancyView()
                // Keeps the surface's ink identity and text contrast intact
                // over both bright and dark wallpapers — the blur alone would
                // let a light wallpaper wash the panel out.
                tokens.colors.surfaceInk.opacity(0.6)
            }
        }
    }
}
