# Local Dependency Provenance

**Status:** Round 4 complete (2026-07-29)

Open Island has zero third-party SwiftPM dependencies and no `Vendor/`
directory. `Package.swift` defines only repository-owned targets, so an empty
SwiftPM cache resolves from the checkout without a registry or source-control
fetch. There are therefore no current third-party source hashes, licenses, or
notices to recompute; “none” is the audited provenance result, not an omitted
check.

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

## Verification

The offline dependency gate is:

```bash
swift package resolve
swift build
swift test
swift package describe
```

Run it with empty temporary SwiftPM caches and host-level network denial when
proving a clean checkout. A second resolve must leave no dependency-state diff.
`python3 scripts/verify-local-only-audit.py` additionally rejects remote
SwiftPM/Xcode references; `python3 scripts/verify-no-network-policy.py` rejects
remote package URLs in live manifests.

## Future reviewed update procedure

There is no automatic dependency update mechanism. A future dependency must be
removed where possible; otherwise the maintainer must first obtain and review
the source outside this repository, vendor only the required source under
`Vendor/<Package>`, and add only a repository-local `.package(path:)` reference.
Before committing, record here the canonical upstream, revision/tag, archive
SHA-256, repository-tree hash, SPDX/license text and notices, reachable targets,
excluded examples/workflows/binaries/platforms, and the reviewer. Re-run the
offline gate and recompute both hashes from the vendored files. A remote URL,
registry lookup, or executable dependency manifest is never an acceptable
update path.
