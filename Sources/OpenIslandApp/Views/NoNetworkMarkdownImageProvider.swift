import SwiftUI
@preconcurrency import MarkdownUI

// Agent completion messages are rendered as Markdown. MarkdownUI's default image
// providers fetch remote image URLs over the network, so a prompt-injected
// `![](https://tracker/pixel.png)` in an agent's text would silently issue an
// outbound request — a tracking-beacon / data-egress path. Open Island is
// local-first, so remote image loading is suppressed entirely at those sites.

/// A block-image provider that renders nothing and never performs network I/O.
struct NoNetworkImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        EmptyView()
    }
}

extension ImageProvider where Self == NoNetworkImageProvider {
    /// Suppresses remote image loading for Markdown block images.
    static var noNetwork: Self { NoNetworkImageProvider() }
}

/// An inline-image provider that loads nothing and never performs network I/O.
struct NoNetworkInlineImageProvider: InlineImageProvider {
    private struct Suppressed: Error {}

    func image(with url: URL, label: String) async throws -> Image {
        throw Suppressed()
    }
}

extension InlineImageProvider where Self == NoNetworkInlineImageProvider {
    /// Suppresses remote image loading for Markdown inline images.
    static var noNetwork: Self { NoNetworkInlineImageProvider() }
}
