import AppKit
import OpenIslandCore

/// Fixed Finder-only local navigation. It deliberately exposes neither a URL
/// opener nor an application selector: validated local items are only revealed
/// in Finder, under the roots owned by Open Island's supported integrations.
enum LocalFileReveal {
    static func reveal(_ candidate: URL) {
        guard let url = try? LocalAutomationPolicy.validatedApprovedLocalRevealURL(
            candidate,
            role: .appInternalControl
        ) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
