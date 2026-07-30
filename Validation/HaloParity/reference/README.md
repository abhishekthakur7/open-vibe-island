# Halo deterministic reference harness

This directory builds an instrumented copy of the authoritative static board. It never edits
`docs/design/overlay-redesign/06-halo.html`. With no query parameters the generated page is the
original board plus inert, non-visible instrumentation.

Build from the repository root:

```sh
node Validation/HaloParity/reference/build-reference-harness.mjs
python3 -m http.server 8765
```

Open this URL using the product's **in-app Browser**:

```text
http://127.0.0.1:8765/Validation/HaloParity/reference/generated/halo-reference-v1.html
```

Do not use standalone Playwright or a general browser as canonical reference evidence. The
in-app Browser screenshot API emits JPEG. Canonical lossless evidence therefore requires an
actual in-app-Browser WindowServer capture with provenance retained. `exportPNG()` uses a
canvas/foreignObject path and returns genuine PNG bytes, but its result is always labeled
`candidate-unqualified`; it is not proof of IAB capture fidelity.

## Explicit harness mode

The UI/status/fiducial stay hidden unless `scenario` is supplied. Example:

```text
...?scenario=A3&profile=notch-v1&motion=manual&a11y=default&seed=review-1&event=none&time=950&debug=1
```

Allowed values originate in the authored
`reference-authority-v1.json` and are projected into `reference-spec-v1.json`. Unknown scenario,
profile, motion, accessibility, event, config key, or invalid time/seed is rejected.

## Controller API

The page exposes `window.HaloReferenceController`:

```js
await HaloReferenceController.ready
HaloReferenceController.setState({
  scenarioId: "A3",
  profile: "notch-v1",
  motionMode: "manual",
  accessibilityMode: "default",
  seed: "review-1",
  eventId: "none",
  timeMs: 950
})
HaloReferenceController.dispatchEvent("open", {})
HaloReferenceController.seek(475)
HaloReferenceController.playNormal()
HaloReferenceController.dumpDOM()
HaloReferenceController.dumpAXHints()
await HaloReferenceController.exportPNG({ download: true })
HaloReferenceController.reset()
```

Manual time pauses descendant Web Animations and sets `currentTime`; `playNormal()` resumes the
original real-time animations. Dumps include visible-copy order, selected markup, state, and
provenance. Authored variants are declarative clones/patches of established fragments and carry
their design-law list, frozen authored decision, and null approval. They are reference-authoring
decisions only: no native fixture, coverage disposition, reproduction evidence, parity result, or
human approval is inferred by the builder.

## Determinism and lock

`reference-authority-v1.json` is the stable, reviewable source of reference decisions. The scenario
manifest is consulted only to require the same 57-ID set; native fixture, trigger, disposition,
result, rationale, and evidence fields are not inputs to reference generation.

The builder emits the generated HTML, the 57-row spec, explicit authored-variant decisions, and
`reference-input-lock-v1.json`. The lock hashes the transitive authored/code inputs, records all
three generated outputs, and computes a reproducible Merkle root without timestamps. The scenario
manifest, gap ledger, and audit are intentionally absent from the lock. Run the builder twice and
compare the lock/generated hashes to check determinism.
