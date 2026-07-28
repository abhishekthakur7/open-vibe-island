# Local-Only Disposition Map

**Audit date:** 2026-07-29

**Machine-readable inventory:** [`local-only-disposition-map.json`](local-only-disposition-map.json)
**Gate command:** `python3 scripts/verify-local-only-audit.py`

This is the Round 1 control surface for the local-only cleanup. It records the
current repository state, not the desired end state as if it already existed.
`retain` means an item stays only after the owning round's acceptance evidence;
`remove`, `replace`, and `migrate` are work still to be performed. An item with
no disposition, round, evidence, and migration/rollback consequence blocks the
next destructive round.

The JSON inventory is canonical because it is checked by a static gate. This
document is the review-oriented map of its decisions.

## Completed cleanup rounds

- Round 2 removed the mobile, Watch, and relay surfaces.
- Round 3 removed the updater and public distribution automation. Local bundle,
  archive, and development-signing workflows remain.
- Round 4 removed all remote SwiftPM dependencies. Native Markdown rendering
  and golden assertions retain the app and test behavior; no vendored package
  is required. See [`dependency-provenance.md`](dependency-provenance.md).
- Round 5 removed network entitlements, loopback reply handling, and live SSH
  setup instructions. `scripts/verify-no-network-policy.py` enforces a
  Git-scoped static boundary; runtime traffic observation remains Round 10.

## Boundary and audit rule

The supported runtime after the cleanup is the macOS `OpenIslandApp` product.
Open Island may use local files, private `AF_UNIX` IPC, Accessibility, and the
fixed local actions in the allowlist below. It may not create IP sockets, load
remote URLs, resolve remote packages, run network-requesting tools, or instruct
a focused external application to do so.

The static gate enumerates sensitive source matches (socket, process launch,
Apple Events/LaunchServices, persistence, SQLite, hook mutation, and network
APIs). Every match must be listed under `powerful_source_paths` in the JSON.
Consequently, a newly discovered powerful file fails closed until it has a
disposition. The inventory itself rejects unknown dispositions and incomplete
entries.

Round 5 separately rejects Network and URL-loading APIs, IP socket
families/listeners, remote endpoints and package references, network shell
tools, telemetry/update surfaces, and network entitlements. `AF_UNIX` is
permitted only in the policy's named bridge and local-cmux adapter files. The
dependency provenance document is the sole scanned documentation exception for
inert upstream URLs. Policy implementation and invariant-fixture files are
excluded from content scanning because they deliberately contain signatures
that the fixtures test; all other live source, manifests, build/test/package/
verification scripts, entitlements, and packaged metadata are covered.

## Product, build graph, and delivery disposition

| Current item | Disposition / owner | Acceptance evidence | Migration / rollback |
| --- | --- | --- | --- |
| SwiftPM `OpenIslandCore`, `OpenIslandApp` | retain, Round 4 | offline resolve/build | no data migration |
| SwiftPM `OpenIslandHooks` | replace, Round 6 | signed fixed-role helper tests | app and helper roll back together |
| SwiftPM `OpenIslandSetup` and hook managers | replace, Round 8 | consent, symlink, atomic-write and recovery tests | only verified managed backup restored |
| Removed `ios/OpenIslandMobile.xcodeproj`, `ios/OpenIslandMobile/**`, `ios/OpenIslandWatch/**`, `ios/Shared/**` | removed in Round 2 | SwiftPM macOS graph and static no-target/no-relay/Bonjour audit | existing watch preference is inert; no user data deleted |
| Removed `WatchHTTPEndpoint`, `WatchNotificationRelay`, AppModel watch callbacks/UI/default | removed in Round 2 | macOS tests plus relay/Bonjour absence | leave old default inert |
| Removed `UpdateChecker`, `appcast.xml`, and Sparkle | removed in Round 3 | updater/feed/bundle audit | manual local replacement only |
| Removed GitHub workflows, release/notary/upload scripts and claims | removed in Round 3 | workflow/release symbol audit | no partial release-path restoration |
| Removed remote Swift packages, including transitive `swift-cmark`, `NetworkImage`, `swift-syntax`, `swift-custom-dump`, and `xctest-dynamic-overlay` | removed in Round 4 | empty-cache offline resolve/build/test plus static manifest/Xcode audit | future dependency requires reviewed repository-local source; currently zero vendored dependencies |
| macOS entitlement network client | remove, Round 5 | entitlement and prohibited-API audit | no rollback to broad network entitlement |
| Network client/server entitlement, loopback reply path, and live SSH setup | removed, Round 5 | static policy fixtures and packaged entitlement inspection | no restoration without an approved boundary change |

All macOS source, resource, test, fixture, documentation, and design paths are
listed by path group in the canonical inventory. Test targets are migrated with
their implementation round: Watch tests go in Round 2; dependency-linked tests
in Round 4; persistence/harness fixtures in Round 7 and 10; action tests in
Round 9. Localized resources and branding remain, while the OpenCode JS bridge
resource and updater packaging content are replaced or removed with their
respective security rounds.

## State, IPC, and hook disposition

| Surface | Current state | Disposition / owner | Migration consequence |
| --- | --- | --- | --- |
| Bridge | private app-support socket | retained and hardened, Round 6 | one private app-owned socket; legacy clients receive a protocol-upgrade response where possible and must reinstall the bundled helper |
| cmux | application-support and `/tmp` discovery paths, `CMUX_SOCKET_PATH` | replace, Round 9 | only a validated local socket may drive fixed focus operation |
| Persistent state | UserDefaults, three app-support registries, intent data, debug/harness artifacts, external transcripts and SQLite readers | migrate, Round 7 | data matrix, expiry, redaction and Clear History; never recreate discarded content |
| Hook targets | Claude/Codex/Cursor/OpenCode/Gemini/Kimi and Claude-family fork files, manifests, installed binary and backups | replace, Round 8 | explicit consent; ambiguous/unmanaged targets are untouched; one 0600 verified backup |
| Legacy remote client | Python hook client and SSH setup | replace/remove, Round 6 | remote and forwarding behavior is deleted, not reimplemented |

The field-level persistence groups, paths, collection purpose, protection,
retention target, deletion trigger, Clear History behavior, and rollback rule
are enumerated in `inventory.persistence`. Round 7 must replace that audit
entry with the implementation data-lifecycle matrix; no persistent field may
remain merely because it existed before this audit.

## Retained powerful-action allowlist

The following is intentionally a contract for later code, not a statement that
the current implementation already complies. Every action not named here is
denied after its owning round.

| Class | Allowed after cleanup | Owner / evidence |
| --- | --- | --- |
| Local IPC roles | `hook-event-submit`, `local-status-read`, `app-internal-control`; each concrete registration target and every operation maps to exactly one role; wire-only `observer` cannot authenticate | Round 6 peer-signature, nonce, capability, timeout and bound tests |
| Helper | bundled `OpenIslandHooks`, embedded digest plus designated requirement, fixed `--source` enum | Round 6 helper/signature tests |
| System executables | `/bin/ps`, `/usr/sbin/lsof`, `/usr/bin/osascript`, `/usr/bin/open`, then verified absolute terminal CLI paths | Round 9 exact executable/argument/environment tests |
| Apple Events | named `terminal-frontmost-probe` and `terminal-focus` templates for the listed terminal bundle IDs; typed local identifiers only | Round 9 adversarial bundle/script input tests |
| URLs/files | canonical `file:` targets under an approved local root; the fixed System Settings privacy pane only if required | Round 9 scheme/path tests |
| cmux | focus a validated numeric surface on a validated local socket, then activate `com.cmuxterm.app` | Round 9 local cmux test |

The complete executable requirements, argument shapes, permitted environment
keys, template bundle IDs, schemes, and cmux fields are in `allowlists` in the
JSON. This list deliberately contains no shells, `PATH` lookup, arbitrary
AppleScript, generic URLs, `http`, `https`, `ssh`, `mailto`, package managers,
or arbitrary terminal commands.

## Verification and safe handoff

Run the following before using this map as a destructive-round gate:

```sh
python3 scripts/verify-local-only-audit.py
python3 scripts/verify-no-network-policy.py
swift package describe
swift build --product OpenIslandApp
```

The verifier checks machine-readable completeness, all allowlist families,
inventory coverage of current products, dependencies, workflows, entitlements,
and current sensitive-source matches. It is intentionally conservative: if
macOS tooling is unavailable, record that limitation and do not claim Xcode
verification passed. Diagnostic/documentation changes have no user-data
migration; reverting this commit simply removes the audit gate and map.
