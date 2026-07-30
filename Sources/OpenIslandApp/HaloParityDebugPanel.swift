#if HALO_PARITY_TESTING
import SwiftUI

/// Reserved out-of-crop diagnostics surface. It is intentionally not mounted
/// by the first native packet; state and timing travel in JSON sidecars, so the
/// production Halo comparison surface contains no harness pixels.
struct HaloParityDebugPanel: View {
    let state: HaloParityStateDump

    var body: some View {
        EmptyView()
            .accessibilityHidden(true)
    }
}
#endif
