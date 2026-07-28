# Local-Only Security Cleanup Execution Plan

- **Status:** Active
- **Created:** 2026-07-29
- **Scope:** Local macOS use only
- **Supported runtime after completion:** `OpenIslandApp`

## Purpose

Open Island currently includes product and delivery surfaces that are outside the
intended deployment:

- iPhone and Apple Watch companion applications;
- a Bonjour-advertised HTTP relay that can return agent decisions;
- Sparkle update checks and appcast handling;
- CI, release, notarization, upload, and distribution automation;
- remote Swift package resolution;
- legacy local IPC compatibility paths;
- broader local transcript persistence and automation privileges than are needed.

A static source audit found no malicious code, covert payload, credential theft,
keylogging, screen capture, hidden remote shell, or telemetry. This plan is
preventive attack-surface reduction, privacy minimization, and enforcement of a
clear local-only product boundary.

## Required End State

- `OpenIslandApp` on macOS is the only supported product runtime.
- No iPhone, iPad, watchOS, remote companion, relay, remote-control, updater,
  appcast, telemetry, remote service, CI, release, upload, or distribution
  pipeline remains.
- No executable SwiftPM manifest references a remote package.
- Production and test dependencies are removed or vendored and reproducibly
  build offline from an empty dependency cache.
- The app has no network client or server entitlement, and Open Island-owned
  code and launched process trees perform no IP networking.
- Local Unix IPC is private, authenticated, role-authorized, resource-bounded,
  and free of legacy `/tmp` or environment redirects.
- Local history and logs are minimal, protected, expiring, and user-clearable.
- Hook management is explicit opt-in, local-source-only, symlink-safe, atomic,
  reversible, and permission-safe.
- AppleScript, cmux, URL opening, and subprocess behavior are fixed-operation
  and allowlisted.
- Stable local development signing, dev-bundle refresh, and offline packaging
  remain available.
- Product, privacy, architecture, hooks, and packaging documentation accurately
  describe the implementation.

## Boundary And Threat Model

“No network” applies to:

1. repository-owned build, test, packaging, and verification scripts;
2. `OpenIslandApp` and its bundled helpers;
3. any subprocess launched specifically by Open Island and its descendants;
4. Apple Events sent by Open Island when they request an operation.

It forbids TCP, UDP, and other IP sockets; network frameworks; remote URL loads;
telemetry; update checks; remote package resolution; and Apple Events or
subprocess commands that request network activity.

It does not claim to prevent an independently running terminal, IDE, browser,
or coding agent from using the network after Open Island performs only a local
focus, window-selection, or navigation action. Those applications are outside
the Open Island-owned process tree. Open Island must not pass them commands,
URLs, scripts, or arguments that request remote access.

Permitted local primitives are:

- Unix-domain sockets;
- local filesystem operations;
- Accessibility;
- LaunchServices for validated local file targets or approved non-network
  schemes;
- fixed AppleScript UI actions;
- audited local subprocess operations.

Same-EUID IPC checks prevent cross-user access and common permission mistakes.
They do not defend against a fully compromised process already running as the
same macOS user. Signed-helper identity, Keychain-protected bootstrap material,
role limits, short-lived capabilities, and resource bounds reduce accidental
or opportunistic misuse within that boundary.

## Assumptions And Out Of Scope

- macOS and `OpenIslandApp` remain the only supported platform and runtime.
- No mobile, remote companion, CI, public release, App Store, notarization, or
  hosted distribution work is included.
- Existing user files and hooks must not be silently destroyed.
- Inert upstream provenance URLs may appear in dependency-audit documentation,
  but not in executable manifests, runtime configuration, or scripts.
- Local Unix sockets, required Accessibility and Apple Events, and explicitly
  invoked local subprocesses remain permitted within the allowlists.
- Unrelated UI redesign and feature expansion are out of scope.
- Each round uses a new topic worktree and branch from `origin/main`, performs
  targeted verification, ends in one conventional commit, is squash-integrated
  to `main`, and leaves a clean tree before dependent work begins.

## Risk Order

1. Local IPC and arbitrary Automation or process execution.
2. Unintended networking and unsafe hook mutation.
3. Sensitive persistence and logs.
4. External dependency and updater or release supply-chain surface.
5. Unsupported targets and documentation drift.

## Implementation Rounds

### Round 1: Commit The Audit-Derived Disposition Map

**Round 1 audit artifacts**

- [`docs/audits/local-only-disposition-map.md`](../../audits/local-only-disposition-map.md)
- [`docs/audits/local-only-disposition-map.json`](../../audits/local-only-disposition-map.json)
- `python3 scripts/verify-local-only-audit.py`

The JSON inventory is the gate's canonical source. The verifier fails closed
when a current powerful source match, manifest surface, dependency, entitlement,
or required allowlist family has no recorded disposition.

**Owned files**

- this execution plan;
- a repository audit and allowlist document;
- package and Xcode target inventories;
- entitlement, script, workflow, source, test, persistence, hook, and
  process-action inventories.

**Work**

Use CodeGraph when available, plus manifest and project inspection, to enumerate:

- every product, target, platform, source directory, test target, fixture,
  resource, entitlement, dependency, workflow, release script, updater symbol,
  and documentation claim;
- every persistence store and stored field;
- every socket path and environment redirect;
- every hook target and installer mutation;
- every subprocess executable, AppleScript template, LaunchServices operation,
  URL scheme, and cmux action;
- every migration or deletion consequence.

For each item, record:

- `retain`, `remove`, `replace`, or `migrate`;
- the owning implementation round;
- acceptance and verification evidence;
- migration and rollback behavior.

Commit explicit allowlists for:

- permitted local IPC operations and roles;
- executable paths, hashes, or signing requirements;
- allowed argument shapes and environment keys;
- AppleScript templates and bundle identifiers;
- local URL and file schemes;
- cmux operations.

The target map must include corresponding manifests, Xcode targets, tests,
fixtures, documentation, and data migration.

**Gate**

No destructive round starts until every discovered item has a disposition and
every retained powerful action has an allowlist entry. Unknown items fail the
audit.

**Verification**

- `git status -sb`
- CodeGraph and source inspection
- `swift package describe`
- Xcode target listing
- static inventory script
- existing targeted tests

**Migration and rollback**

Diagnostic and documentation changes only. Revert the round if the inventory is
incomplete or the boundary is incorrect.

**Commit**

`docs: define audited local-only disposition map`

### Round 2: Remove Mobile, Watch, And Relay Surfaces

**Owned files**

- `ios/**`;
- `Sources/OpenIslandCore/WatchHTTPEndpoint.swift`;
- `Sources/OpenIslandCore/WatchNotificationRelay.swift`;
- Watch state and callbacks in `AppModel`;
- Watch settings UI;
- related tests, fixtures, resources, project metadata, and documentation
  identified in Round 1.

**Dependencies**

Approved Round 1 disposition map.

**Work**

- Remove all mobile and watchOS targets.
- Remove the macOS Watch listener, relay, pairing, discovery, and response path.
- Remove shared relay models not used by the macOS runtime.
- Remove Watch settings, persisted feature state, assets, tests, and product
  claims.
- Preserve shared code only where a mapped macOS call path requires it.

**Acceptance**

- The build graph contains only approved macOS products and tests.
- Every mapped mobile, Watch, and relay item is removed.
- No Bonjour or local-network declaration remains.

**Verification**

- `swift build`
- `swift test`
- Xcode macOS target build
- static searches for removed target names, relay protocols, Watch UI, Bonjour,
  and local-network declarations

**Migration and rollback**

Stop reading obsolete relay preferences. Leave inert old defaults for normal
preference cleanup rather than deleting unrelated settings. Revert the isolated
squash commit to restore the removed product surface.

**Commit**

`refactor: remove mobile companion and relay surfaces`

### Round 3: Remove Updater, Workflows, And Distribution Automation

**Owned files**

- updater source, UI, and tests;
- Sparkle package and bundle configuration;
- appcasts and feed metadata;
- `.github/workflows/**`;
- release, signing, notarization, upload, publishing, and distribution scripts
  and documentation.

**Dependencies**

Round 2.

**Work**

- Remove Sparkle, `UpdateChecker`, updater UI and app lifecycle wiring.
- Remove `SUFeedURL`, `SUPublicEDKey`, appcast files, and appcast scripts.
- Remove GitHub Actions, release mutation, Homebrew tap, upload, notarization,
  and distribution signing automation.
- Delete `.github/workflows`.

Retain only after audit:

- `scripts/setup-dev-signing.sh`, limited to creating and using a stable local
  development identity;
- `scripts/launch-dev-app.sh`, limited to building the current checkout,
  refreshing `~/Applications/Open Island Dev.app`, local signing, and launch;
- `scripts/package-local-app.sh`, or a renamed existing equivalent, limited to
  producing a local app bundle or archive without network, notarization, upload,
  feed generation, or release mutation.

**Acceptance**

- No updater endpoint, Sparkle artifact, workflow, distribution credential
  handling, or publishing command remains.
- Retained scripts have an explicit no-network contract and no update-feed
  coupling.
- Local stable signing still preserves TCC identity during manual verification.

**Verification**

- static audit for updater, feed, workflow, release, notary, upload, and remote
  publishing symbols;
- offline execution of retained local scripts;
- inspection of the produced bundle and signing identity.

**Migration and rollback**

Existing installations stop receiving in-app updates. Documentation must state
that future replacement is manual and local. Revert the round rather than
recreating only part of the removed distribution path.

**Commit**

`chore: remove updater and distribution automation`

### Round 4: Eliminate Remote Dependency Resolution

**Owned files**

- `Package.swift`;
- Xcode package references;
- `Package.resolved`;
- `Vendor/**`;
- dependency audit and license notices.

**Dependencies**

Round 3.

**Work**

- Remove `MarkdownUI` and `SnapshotTesting` if their remaining uses can be
  replaced with bounded native rendering and test assertions.
- Remove every unused package.
- If a production or test source dependency remains justified, vendor its
  reviewed source under `Vendor/<Package>` and use only `.package(path:)`.

For every vendored package, record:

- canonical upstream project and revision or tag;
- upstream archive or source SHA-256 and repository tree hash;
- license and notices;
- reason retained and reachable targets;
- excluded examples, workflows, binaries, scripts, and unnecessary platforms;
- an update procedure that requires explicit source review.

Track `Package.resolved` if SwiftPM produces it, but do not treat it as the
dependency supply source. No manifest or Xcode project may contain remote
package URLs.

**Acceptance**

Starting with empty SwiftPM caches and network disabled, resolve, build, and
test succeed using repository content only. A second resolution produces no
diff.

**Verification**

- isolated empty cache and home directories;
- network-disabled `swift package resolve`;
- network-disabled `swift build` and `swift test`;
- dependency graph inspection;
- remote-URL audit;
- vendored license, revision, and hash verification.

**Migration and rollback**

No user-data migration. Restore a dependency only through vendoring and review,
never through a remote executable manifest URL.

**Commit**

`build: vendor audited dependencies for offline builds`

### Round 5: Remove Network Capability And Add Static Enforcement

**Owned files**

- macOS entitlements;
- package and project settings;
- static audit script;
- invariant tests.

**Dependencies**

Rounds 2 through 4.

**Work**

- Remove `com.apple.security.network.client`,
  `com.apple.security.network.server`, and unused network entitlements.
- Ban Network framework, URLSession and network URL loading, TCP and UDP socket
  families, listener APIs, remote endpoint literals, telemetry and update code,
  network-capable shell tools, and remote package references.
- Permit `AF_UNIX` only in mapped bridge files.
- Allow inert provenance URLs only in the audited documentation paths.

**Acceptance**

Source, manifests, scripts, entitlements, and the packaged app pass the static
policy. Deliberate prohibited fixtures make the policy fail.

**Verification**

- build and tests;
- entitlement inspection;
- positive and negative invariant tests;
- offline local packaging.

**Migration and rollback**

No migration. Any new exception must amend this plan’s boundary and receive
explicit approval; broad network entitlement restoration is not acceptable.

**Commit**

`security: enforce the no-network build boundary`

### Round 6: Harden Unix IPC Bootstrap And Transport

**Owned files**

- bridge server, client, and bundled helper code;
- app integration;
- bridge tests;
- protocol documentation.

**Dependencies**

Rounds 1 and 5.

**Work**

- Remove legacy `/tmp` sockets and all legacy socket-path environment
  redirects.
- Use one app-owned per-user directory at mode `0700`.
- Use mode `0600` for sockets, bootstrap metadata, and state files where the
  filesystem object supports it.
- Reject symlinks, wrong owner or type, and group or world-writable path
  components.
- On each accepted `AF_UNIX` connection, use macOS `getpeereid`.
- Where macOS exposes the peer PID, validate the bundled helper’s code signature
  or designated requirement.
- Have shell hooks invoke a bundled signed helper with a fixed compiled role
  instead of connecting as a generic client.
- Define roles such as `hook-event-submit`, `local-status-read`, and narrowly
  scoped app-internal control; map every operation to exactly one role.
- During explicit helper registration, create role-specific random bootstrap
  material in Keychain with access restricted to the app and signed helper.
- After UID and signature validation, perform nonce challenge-response and
  issue a connection-bound capability containing protocol version, peer
  identity, role, allowed operations, nonce, and short expiry.
- Rotate bootstrap material on managed helper or hook updates.
- Revoke credentials on uninstall, security reset, signature mismatch, or
  explicit integration reset.
- Retain used challenge state only for the maximum handshake and capability
  lifetime.
- Bound frame size, decoding depth, active connections, per-peer concurrency,
  handshake time, idle time, request time, output size, and malformed-request
  count.

**Acceptance**

Same EUID alone is insufficient for privileged roles. Unknown, expired,
replayed, cross-role, incorrectly signed, oversized, stalled, or malformed
clients fail closed.

**Verification**

Automated tests must cover:

- directory, socket, and file modes;
- ownership and symlink rejection;
- peer UID and helper signature mismatch;
- role denial;
- Keychain bootstrap creation and access;
- rotation and revocation;
- nonce replay before and after expiry;
- capability expiry and connection binding;
- stale sockets;
- connection floods and concurrency limits;
- partial and oversized frames;
- decoding-depth and output limits;
- timeout and crash cleanup.

**Migration and rollback**

Remove a legacy socket only when it is actually a socket owned by the current
EUID. Otherwise leave it untouched and report the path. Existing clients receive
an actionable protocol-upgrade error. Bridge and bundled helper changes must
roll back together.

**Commit**

`security: authenticate and bound local bridge access`

### Round 7: Define And Implement The Data Lifecycle Matrix

**Owned files**

- persistence stores and models;
- logging;
- Keychain wrapper;
- Clear History and Reset Integrations UI;
- migration tests;
- privacy documentation.

**Dependencies**

Round 6.

The implementation-specific matrix must list the exact path, every field,
collection trigger, purpose, protection, retention clock, deletion trigger,
migration, Clear History behavior, and owner for every store.

| Store | Minimum policy |
|---|---|
| Transcript and event content | Collect only fields required for visible local history; app-owned `0700/0600` storage; default retention no more than 7 days; Clear History deletes |
| Session metadata | Retain only needed IDs, timestamps, local source/tool, and state; default retention no more than 30 days; Clear History deletes |
| Logs | No command bodies, transcript text, tokens, full paths, environment, or payloads; bounded rotation no more than 7 days; Clear History deletes eligible files |
| Keychain IPC bootstrap | Store only role/helper identity and random secret; retain while managed integration is enabled; Clear History preserves; Reset Integrations revokes |
| Hook backups | At most one backup per managed target; mode `0600`; retain 30 days or until successful uninstall/restore; exclude from Clear History and disclose separately |
| Socket and replay state | No content payload; memory-only where possible; remove stale filesystem state at launch; capability and replay entries expire at the protocol maximum |
| Caches | Content-minimized and bounded; retain no more than 7 days; Clear History deletes |
| Preferences | Feature settings only; retain until changed or reset; exclude from Clear History |

**Work**

- Remove persistent fields without an explicit visible product purpose.
- Migrate existing records by dropping unnecessary content and adding expiry.
- Store secrets only in Keychain.
- Redact logs.
- Run expiry at launch and periodically.
- Implement Clear History for local content.
- Implement Reset Integrations for IPC credentials and managed integration
  state.

**Acceptance**

No persistent field lacks a matrix entry. Seeded secrets do not appear in
databases or logs. Clear History and Reset Integrations match their documented
scope.

**Verification**

- schema migration and absent-field rollback tests;
- retention-boundary and clock tests;
- file ownership and mode inspection;
- seeded-secret redaction tests;
- Clear History integration tests;
- Keychain credential revocation tests;
- crash and interrupted-cleanup recovery tests;
- hook backup exclusion tests.

**Migration and rollback**

Never reconstruct discarded sensitive content. Schema rollback must tolerate
absent fields. Back up schema metadata rather than copying discarded content.

**Commit**

`privacy: minimize expire and clear local data`

### Round 8: Harden Hook Installation And Update

**Owned files**

- hook manager and managed binary locator;
- bundled hook templates;
- hook settings UI;
- hook tests;
- `docs/hooks.md`.

**Dependencies**

Rounds 6 and 7.

**Work**

- Require explicit opt-in showing the exact target, source, permissions, and
  managed changes.
- Accept only bundled versioned content matching an embedded digest.
- For each path component, reject symlinks, wrong owners, non-directory
  components, and group or world-writable directories.
- Allow directories writable only by the current user where installation
  requires it.
- Require target files to be regular, current-user-owned, and not multiply
  linked where detectable.
- Preserve unmanaged, marker-mismatched, partially managed, or otherwise
  ambiguous hooks untouched.
- Make noninteractive commands return a distinct status and exact remediation
  guidance for ambiguity.
- Use same-directory atomic replacement: create a private temporary file,
  write and `fsync`, apply the mode, verify digest, type, and owner, rename,
  then `fsync` the directory.
- Keep a recovery journal until successful completion.
- Preserve at most one prior managed target backup at mode `0600` for 30 days.
- Never overwrite an unmanaged backup.
- On interruption, restore the verified prior file or report the unresolved
  state without guessing.

**Acceptance**

No silent installation or update occurs. Unsafe or ambiguous paths fail closed.
Update, uninstall, restore, and crash recovery are deterministic.

**Verification**

Tests must cover:

- consent and source preview;
- idempotence;
- digest mismatch;
- symlink and race attempts;
- owner, type, link count, and mode validation;
- current-user-writable directory acceptance;
- group and world-writable rejection;
- ambiguity status;
- atomic-write interruption;
- recovery journal behavior;
- backup expiry and restore;
- uninstall and credential revocation.

**Migration and rollback**

Existing hooks become managed only when marker and digest match. All others
remain untouched. Rollback restores only a verified managed backup.

**Commit**

`security: make hook management explicit and symlink safe`

### Round 9: Constrain AppleScript, cmux, URLs, And Subprocesses

**Owned files**

- process launcher;
- cmux adapter;
- AppleScript and Automation helpers;
- focus and jump handlers;
- tests;
- architecture documentation.

**Dependencies**

Round 1 action allowlist and Round 6 roles.

**Work**

- Use direct executable paths and fixed argument arrays.
- Do not use shells, command strings, login environments, PATH lookup, or
  arbitrary working directories.
- Use a minimal environment, bounded standard input and output, fixed timeout,
  and descendant termination.
- Enumerate every surviving operation in the committed action inventory.
- Default-deny network-capable tools such as `curl`, `ssh`, package managers,
  browsers, and arbitrary terminal commands.
- Reject arbitrary AppleScript source, bundle IDs, URLs, file paths, cmux
  subcommands, or arguments.
- Reject Apple Events that request scripts, downloads, remote URLs, or terminal
  command execution.
- Permit only fixed local UI, focus, and window-selection templates; validated
  local file navigation; approved non-network URL schemes; audited cmux
  local-control actions; and the signed bridge helper.
- Pass AppleScript data as typed parameters rather than source interpolation.
- Require the appropriate bridge role for every powerful action.

**Acceptance**

External input cannot select an executable, script source, remote scheme,
bundle ID, environment, working directory, or unsupported operation. Focused
external applications may independently use the network, but Open Island passes
no network-requesting action.

**Verification**

- adversarial shell metacharacter, newline, option, URL, bundle, path, and
  action tests;
- oversized input and output tests;
- timeout and descendant cleanup tests;
- role mismatch tests;
- manual cmux, local focus, and precision-jump verification.

**Migration and rollback**

Unsupported free-form behavior returns a local-only policy error. Do not add a
compatibility shell escape hatch. Revert action implementation and tests
together.

**Commit**

`security: constrain local automation and execution`

### Round 10: Enforce Runtime Process-Tree No-Network Behavior

**Owned files**

- runtime diagnostics;
- test harness;
- smoke scripts;
- policy tests.

**Dependencies**

Rounds 5 and 9.

**Work**

- Add debug and test observation that fails when the app, bundled helper, or an
  Open Island-launched descendant creates, binds, or connects an IP socket or
  invokes a prohibited networking API or tool.
- Record the PID tree for each launched action during deterministic smoke
  verification.
- Observe the process tree with native macOS process and socket tooling.
- Do not attribute independent traffic from a pre-existing app merely focused
  by Open Island.
- If Open Island launches an app as a child, require the launch to be allowlisted
  and its observed descendants to remain network-silent for the tested action.
- In production, validate expected entitlements and compiled policy version,
  writing only redacted local diagnostics when they do not match.

**Acceptance**

Representative IP socket, remote URL, network tool, and descendant-network
fixtures fail. `AF_UNIX` bridge tests pass. Traffic from unrelated pre-existing
focused applications does not produce a false product claim.

**Verification**

- deliberate negative fixtures followed by removal;
- offline full smoke suite;
- process-tree and socket observation;
- packaged entitlement inspection.

**Migration and rollback**

No user-data migration. Retain static enforcement if a macOS-specific runtime
observation mechanism requires adjustment.

**Commit**

`test: enforce runtime process-tree network policy`

### Round 11: Align Documentation And Close The Plan

**Owned files**

- `README.md`;
- `PRIVACY_POLICY.md`;
- `docs/product.md`;
- architecture, hooks, dependency, local packaging, and worktree documentation;
- this plan.

**Dependencies**

All prior rounds.

**Work**

Document:

- the exact local-only boundary and external-application exclusion;
- local data flows and trust boundaries;
- dependency provenance and offline update process;
- IPC roles, capabilities, and threat limits;
- retention, Clear History, and Reset Integrations;
- hook consent, update, backup, recovery, and uninstall behavior;
- permitted Automation actions;
- stable local development signing and bundle refresh;
- the sole offline packaging workflow;
- stale socket, hook, and local-state recovery.

Move this plan to `docs/exec-plans/completed/` only after all gates pass.

**Acceptance**

No unsupported mobile, Watch, relay, updater, remote, CI, or distribution claim
remains. Every retained script and powerful action is documented.

**Verification**

- link and path audit;
- execute every documented build, test, sign, launch, and package command
  offline;
- prohibited-term audit with narrow historical and provenance exceptions;
- docs index review.

**Commit**

`docs: document local-only architecture and privacy model`

## Final Verification

1. Build and test SwiftPM and the Xcode macOS app target with network disabled
   and empty SwiftPM caches.
2. Confirm no executable manifest or Xcode package reference contains a remote
   dependency.
3. Recompute vendored-source hashes and verify licenses and notices.
4. Run the static no-network and surface-removal audits, including deliberate
   failure fixtures.
5. Package locally and confirm there is no network client or server entitlement.
6. Run `scripts/setup-dev-signing.sh`, then refresh and launch through
   `scripts/launch-dev-app.sh`.
7. Exercise the bridge, hooks, history clearing, integration reset, cmux,
   focus, AppleScript, and precision jump.
8. Verify Unix paths, owners, modes, peer rejection, capability expiry and
   replay, and resource limits.
9. Observe the app, bundled helpers, and Open Island-launched descendants and
   confirm no IP listener or connection.
10. Confirm independent traffic from an already-running focused application is
    excluded from the assertion and no Open Island action requests that traffic.
11. Confirm mobile, Watch, relay, Sparkle, updater, appcast, workflows,
    release, notary, upload, and remote runtime configuration are absent.
12. Confirm every audit-map item has its final disposition, every round is
    committed and integrated, and `main` is clean.

## Definition Of Done

- Only the local macOS `OpenIslandApp` product remains.
- All repository-owned build, package, test, runtime, and launched-process
  behavior satisfies the defined no-network boundary.
- Dependencies build offline from repository content with empty caches and have
  verified provenance, hashes, and licenses.
- IPC, hooks, persistence, Automation, URLs, and processes meet their specified
  authentication, permission, retention, recovery, validation, and resource
  limits.
- Stable local development signing, current-bundle refresh, and local-only
  packaging work without distribution coupling.
- Static tests, adversarial tests, runtime observation, entitlement inspection,
  and offline smoke verification pass.
- Documentation and the Round 1 disposition map match the final implementation.
- No known verification gap remains. Any unavoidable macOS limitation is
  recorded with a compensating control and named owner.
