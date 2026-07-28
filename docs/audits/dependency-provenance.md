# Local Dependency Provenance

**Status:** Round 4 complete (2026-07-29)

Open Island has zero third-party SwiftPM dependencies and no `Vendor/`
directory. `Package.swift` defines only repository-owned targets, so an empty
SwiftPM cache resolves from the checkout without a registry or source-control
fetch.

| Removed package | Replacement | Reachable behavior retained |
| --- | --- | --- |
| `MarkdownUI` | `LocalMarkdownText`, backed by Foundation `AttributedString(markdown:)` and SwiftUI `Text` | Agent-message emphasis, code, headings, lists, and links remain native-rendered; image Markdown is reduced to accessible alternative text and never loads a URL. |
| `SnapshotTesting` | `ThemeSnapshotting` native AppKit/XCTest PNG comparator | Existing committed theme goldens, explicit recording via `OPEN_ISLAND_RECORD_SNAPSHOTS=1`, environment fingerprints, and exact normalized-pixel comparisons remain. |

Their former transitive packages (`swift-cmark`, `NetworkImage`,
`swift-syntax`, `swift-custom-dump`, and `xctest-dynamic-overlay`) are absent
with their direct parents.

`Package.resolved` is ignored because it is generated resolver state, not a
dependency supply source. With no package dependencies SwiftPM need not create
one; if a future local path dependency creates it, it must contain no remote
location and must not replace source committed under this repository.

There are no vendored packages to license, hash, or update. Any future package
must either be removed or be reviewed into `Vendor/<Package>` with its upstream
revision/tag, archive SHA-256, tree hash, license/notices, exclusions, reachable
targets, and an explicit reviewed update procedure recorded here before a local
`.package(path:)` reference is added.
