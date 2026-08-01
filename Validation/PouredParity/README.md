# Poured parity authority

This directory is the versioned, fail-closed authority input for Poured Island
validation. It does not contain baseline approval and cannot by itself establish
parity. `authority.json` remains approval-pending until a product/design owner
and an independent reviewer record the required decisions.

All JSON documents are validated by `scripts/poured-parity/poured
verify-manifests`. Source anchors and hashes are checked against the repository;
missing or changed anchors invalidate the authority.

The native capture seam (`Sources/OpenIslandApp/PouredParity*.swift` and the
`#if POURED_PARITY_TESTING` regions it extends) is compiled only when that flag
is defined. `scripts/poured-parity/poured swift-test` is the command that builds
and runs it (`swift test -Xswiftc -DPOURED_PARITY_TESTING --filter
PouredParityTests`); a normal `swift build` deliberately excludes the seam.
Every `native.mapping` in `scenarios-v1.json` is checked against the Swift source
text, so a scenario cannot claim a driver symbol the repository does not declare.

`reference-verify` executes the exact hashed HTML in a local Chrome/Chromium
renderer and requires one identity-matching DOM node for every directly rendered
scenario. Evidence commands accept only immutable run roots shaped as
`artifacts/poured-parity/<native-commit>/<run-id>/`; diagnostic runs may be
created with unresolved fingerprints, but Gates 0A–0C cannot accept them.

Raster and browser commands use the version-pinned environment in
`requirements-v1.txt`; install it into an isolated environment before invoking
those commands. Manifest-only commands load none of those optional packages.
Binding inputs use the exact v1 schema and repository-relative authority paths.
`init-run` stores genesis-bound copies and retains the original binding and
attestation paths/hashes outside mutable `artifacts/poured-parity` storage.
Freshness requires the stored bytes to remain identical to those originals, so
coordinated rewrites inside a run do not become new authority. This is not a
cryptographic immutability claim: while attestor and implementation principal
registries remain empty, every such run stays explicitly noncanonical.
Locally derivable OS, architecture, Git, Python, and package facts are measured.
Browser name/version are measured only when a local Chrome/Chromium executable
exists; when none can be measured the bound browser identity is recorded as
unresolved (`environment.browser.measurement`), so the run cannot be canonical.
Display, accessibility, window, signing, and capture facts require the hashed
`environment-collector.py` sidecar seam and authorized attestation.

Authority identities are admitted only through `principals-v1.json`, while each
unresolved reference conflict has its own vocabulary in
`conflict-dispositions-v1.json`. Both remain pending and empty/unresolved in this
foundation, so they cannot be used to manufacture an approval.

Calibration inputs bind one canonical run, environment, binding set, capture
session, and capture metadata. Every still and motion frame requires a globally
unique capture ID, path, and content hash; byte-identical repetitions cannot
qualify independence. Limits are read only from `calibration-v1.json`; its null
pending values make analysis diagnostic and make freezing impossible today.
Masks are reconstructed byte-for-pixel from scoped annotations and each scope
binds an exact capture sidecar and source artifact. Static registration is
derived from named anchor pairs. Motion evidence binds exact run/frame capture
lineage, ordered checkpoints/events, landmarks, PTS, and manual-clock facts to
the canonical run environment and bindings.

Gate 0C consumes the explicit scenario/profile/variant records in
`applicability-v1.json` and the exact matrix/report contracts in
`baseline-matrix-schema-v1.json`, `baseline-evidence-sidecar-schema-v1.json`, and
`metric-report-schema-v1.json`. Applicability contains all 39 scenarios and
expands across both profiles and all nine named standard/adaptation variants.
Non-standard variants use platform-adaptation authority plus native visual/a11y
or interaction/a11y evidence; they never inherit default HTML pixels as direct
authority. Baseline sidecars are parsed semantically and cannot reuse artifact,
sidecar, or capture identities. Metric wrappers are checked against recognized
generator reports. The role-resolved static adapter and interaction/a11y
generators remain deliberately unsupported and block Gate 0C rather than
accepting generic files.

The evidence index exposes a stable `source_evidence_sha256` for raw sources and
a final `evidence_set_sha256` for the complete sealed run. Baseline matrices and
metric wrappers bind the stable source digest; one-way review sealing retains
their validity while still indexing and freshness-checking every derived file.
Unresolved review authority is derived from the current conflicts and ledger,
not from a hard-coded list. Applicability and all three reference conflicts are
still pending, so the outcome remains `BLOCKED-UNVALIDATED`.

`runtime-v1.json` and `requirements-v1.txt` bind supported Python and exact
installed module versions into fingerprints and generated reports. Secure wheel
hashes are not available in this repository; that remains an honest P1
reproducibility limitation, and the tooling does not claim a hash-locked supply
chain.
