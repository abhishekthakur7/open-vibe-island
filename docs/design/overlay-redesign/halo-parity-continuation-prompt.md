# Continuation prompt: implement and validate Halo parity

Copy everything below this line into a new Codex task.

---

You are the root orchestrator for a validation-first Halo visual-parity program in:

`/Users/abhishekthakur/Developer/open-vibe-island`

Your objective is to bring the native SwiftUI Halo overlay to full visual, interaction, and motion parity with:

`docs/design/overlay-redesign/06-halo.html`

Do not make random cosmetic fixes. Establish reproducible reference/native states, neutral calibration, masks, and failing parity evidence before changing product visuals. Continue gate by gate until full parity is proven, or report the earliest blocked/failed gate with evidence.

## Mandatory first reads

Read these completely before editing:

1. `docs/design/overlay-redesign/halo-visual-parity-audit.md`
2. `docs/design/overlay-redesign/06-halo.html`
3. `Sources/OpenIslandApp/Views/Island/HaloEdgeLight.swift`
4. `Sources/OpenIslandApp/Views/Island/HaloClosedPill.swift`
5. `Sources/OpenIslandApp/Views/Island/HaloSessionRow.swift`
6. `Sources/OpenIslandApp/Views/Island/HaloSessionListScaffold.swift`
7. `Sources/OpenIslandApp/Views/Island/HaloHeaderControls.swift`
8. `Sources/OpenIslandApp/Views/Island/HaloUsageSummary.swift`
9. `Sources/OpenIslandApp/Views/Island/HaloUsageMeterCard.swift`
10. `Sources/OpenIslandApp/Theme/HaloTheme.swift`
11. `Sources/OpenIslandApp/Views/IslandPanelView.swift`
12. `Sources/OpenIslandApp/OverlayPanelController.swift`
13. `Sources/OpenIslandApp/IslandChromeLayout.swift`
14. `Sources/OpenIslandApp/AppearancePreviewFixtures.swift`
15. `Sources/OpenIslandApp/IslandDebugScenario.swift`
16. `Tests/OpenIslandAppTests/HaloConformanceSnapshotTests.swift`
17. `Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift`
18. Halo-specific unit tests under `Tests/OpenIslandAppTests/`
19. `scripts/smoke-all-scenarios.sh`
20. `scripts/validate-harness-artifacts.py`

Also inspect repository instructions and the current worktree. Preserve unrelated user changes.

## Known baseline

The prior computer-use review assessed live fidelity at roughly 35–40% qualitatively:

- collapsed working state has a large continuous cyan/violet bloom;
- liveness bars read white and the active agents grid reads gray;
- expanded state reads as a flat, over-spaced monitoring table;
- dividers, dots, and rows have overly uniform saliency;
- Needs You → Running → Done priority is weak in the live composition;
- raw/generic labels such as `Exec`, `Wait`, `Thinking`, and `/` are visible;
- the outer perimeter remains prominent rather than light localizing to the actionable region;
- continuous morph and attention-light travel are not validated;
- existing tests validate native determinism/semantics, not HTML-reference parity;
- no committed Halo PNG goldens were present;
- environment mismatch can skip native pixel checks;
- deterministic snapshots freeze/reduce motion and cannot prove normal animation.

Several reference constants already exist in code—1.5 pt edge, 6 s orbit, 1.9/2.6/3 s state cycles, 2.2 s hero ring, 1.05 s liveness wave, 2.4 s breathe. Token presence is not proof of rendered parity.

## Non-negotiable design laws

Treat the audit's hard invariants as automatic failures outside calibration:

- one true-`#000000` Halo-owned surface;
- nominal 1.5 mapped-unit living edge;
- idle is a bare hairline with no glow;
- working is restrained: a moving segment is dominant, not a broad bright continuous perimeter;
- one loud thing at a time;
- attention light localizes and hands off from perimeter to actionable row/hero;
- pill, peek, and panel are one continuous silhouette with an attached unbroken edge;
- no crossfade, duplicate silhouette, flash, or seam;
- after the defined morph, nothing moves except permitted light;
- Needs You → Running → Done order and membership;
- exact approved copy with no raw `Exec`, `Wait`, `Thinking`, or `/` fallback;
- state is never color alone;
- normal-motion evidence is mandatory;
- no required scenario may be silently skipped.

No perceptual metric, calibration profile, mask, snapshot, or waiver disguised as tolerance may override these laws.

## Required orchestration

Remain the root orchestrator. Own the canonical plan, architecture, integration, code review, evidence review, and final verification.

For bounded subagent research, implementation, and validation tasks, use:

- model: `gpt-5.6-sol`
- reasoning effort: `medium`
- fork turns: `none`

Do not silently substitute another model. If this exact route is unavailable, stop and report that blocker.

Limit practical concurrency to the root plus three subagents.

Each subagent packet must be self-contained and include:

- objective;
- relevant facts and required reads;
- owned files or read-only scope;
- dependencies and forbidden scope;
- acceptance criteria;
- exact verification/evidence expectations;
- handoff format.

Inspect every handoff. Do not trust a completion claim without reading the changes/evidence and running root-level checks.

### First three parallel subagents

Before any edit, start these independent read-only tasks:

1. **Reference/spec auditor**
   Map every A–K reference state to DOM selectors, fixture/state-setting requirements, static checkpoints, motion checkpoints, copy, geometry, and light behavior. Identify reference ambiguities such as demo loops versus product one-shot behavior.

2. **Native implementation mapper**
   Map every A–K state to SwiftUI views, models, fixtures, triggers, and current tests. Identify where live composition diverges even when tokens exist. Do not propose styling changes yet.

3. **Validation-harness auditor**
   Map existing snapshot/smoke/artifact coverage to the five parity dimensions. Design the minimum Gates 0A–0C infrastructure, neutral primitives, masks, manifests, and reports. Confirm exact commands and current artifact behavior.

Integrate these handoffs into one root-owned scenario manifest and gap ledger.

## Computer-use requirement

Use the available computer-use skill.

Before edits:

1. Inspect the live collapsed overlay.
2. Inspect the live expanded overlay.
3. Inspect the HTML reference.
4. Capture the same initial evidence states.
5. Record the visible differences in the gap ledger.

Repeat computer-use inspection at every visual gate. Automated reports do not replace direct live review, and direct live review does not replace reports.

## Required execution order

### Gate 0A — Exact reference/native state reproduction

Do not style.

Create the scenario manifest described in the audit. Cover:

A1, A2, A2′, A3, A4, A5, A6, B, B′, C, D, E1, E2, E3, F1, F2, F3, G, G′, H, I, I′, J, J′, and K, plus stress/accessibility variants.

For every row record:

- deterministic fixture seed/data;
- HTML DOM selector and state mechanism;
- native fixture/harness state and trigger;
- reference/native source hashes;
- viewport, panel size, scale, crop;
- static and timed checkpoints;
- expected copy, grouping, ordering, and light behavior;
- mask/profile IDs and artifact names;
- reproduction evidence;
- disposition.

Allowed dispositions:

- `exact`
- `temporary-surrogate`
- `temporary-exclusion`
- `blocked`

Temporary surrogates/exclusions may unblock unrelated investigation only. They remain NOT PASSED and block full parity.

If a state is unreproducible, provide evidence of attempts and stop dependent work. Do not invent a surrogate and call it equivalent.

Only the user may approve a named waiver for missing coverage. A waived result is `parity-with-waiver`, never full parity.

### Gate 0B — Neutral calibration and threshold freezing

Do not style.

At canonical 2×, provisionally use:

`1 CSS px = 1 SwiftUI pt = 2 device pixels`

Therefore:

`1.5 CSS px = 1.5 SwiftUI pt = 3 device pixels nominally`

Prove or replace this transform using neutral intentionally matched primitives.

Calibration may use only:

- repeated identical captures;
- neutral matched black shapes;
- known-width neutral strokes;
- fixed anchors;
- controlled neutral color patches;
- matched non-Halo glyphs/icons;
- fixed text boxes for raster/layout characterization;
- known capture/encoding transforms.

Calibration must not use:

- current Halo/reference divergence;
- candidate/reference divergence;
- known Halo defects;
- post-styling samples chosen to make a candidate pass.

Measure:

- same-renderer repeatability;
- encoding/antialiasing variance;
- crop registration error;
- neutral cross-renderer raster variance;
- color-management variance;
- text rasterization separately from text layout;
- motion timestamp/frame jitter.

Freeze versioned per-region/scenario threshold profiles before styling. A profile may budget only measured repeatability noise, neutral renderer variance, and a statistically justified margin.

Hard invariants stay outside calibration.

Never loosen a threshold because a candidate fails. Changes require new neutral evidence, a new version, impact analysis, and approval.

### Gate 0C — Baseline evidence

Do not style until all are complete:

- source manifest and hashes;
- scenario manifest;
- versioned gap ledger;
- canonical reference static/motion captures;
- current-native static/motion captures;
- registered masks;
- frozen threshold profiles;
- reference/native/overlay/heatmap reports;
- current hard-invariant failures;
- five-dimension baseline;
- complete environment fingerprint.

Use:

`artifacts/halo-parity/<commit>/<run-id>/`

Follow the exact evidence structure in the audit.

### Gate 1 — Structure and copy

Implement only ledger-backed findings for:

- Needs You → Running → Done grouping/order;
- state membership and counts;
- attention priority;
- normalized workspace names and meaningful fallbacks;
- narrated activity;
- removal of raw internal labels;
- accurate actions for each agent;
- compact information hierarchy.

Pass structural, copy, interaction, and live computer-use checks before moving on.

### Gate 2 — Surface and geometry

Implement only ledger-backed findings for:

- one true-black surface;
- pill/panel silhouette;
- row density and spacing;
- header/notch relationship;
- dot/glyph scale;
- dividers and near-chromeless rows;
- selective rails;
- usage geometry;
- detail/hero layout geometry.

Pass silhouette/body, non-text, text-layout, and density checks in every affected scenario.

### Gate 3 — Light system

Implement only ledger-backed findings for:

- edge-core width/centerline;
- restrained working segment and haze;
- idle hairline;
- permission/question state distinction;
- success/failure behavior;
- rail/dot optical weight;
- one dominant emphasis;
- perimeter-to-row/hero attention handoff;
- bloom localization and falloff.

Score edge core and bloom separately. A large glow cannot compensate for an incorrect edge.

### Gate 4 — Interaction

Validate and correct:

- 0.15 s hover dwell and peek;
- 1.03 hover scale where intended;
- open/close triggers;
- row expansion;
- hover-reveal dismissal;
- Jump/Transcript/Reply;
- permission/deny/scoped actions;
- Codex terminal jump;
- question pagination, selection, freeform, submit;
- focus, keyboard, scrolling, and overflow.

### Gate 5 — Normal motion

Record normal motion at a targeted 60 fps with actual timestamps and event frame zero.

Validate:

- 6 s linear orbit;
- 1.9 s permission pulse;
- 2.6 s question pulse;
- 3 s one-shot success dissolve;
- 2.2 s hero ring;
- 1.05 s liveness wave with 0/.13/.26 s stagger;
- 2.4 s wait breathe;
- continuous open and close silhouettes;
- attached unbroken edge;
- light-centroid travel and intensity handoff;
- row entrance sweep only on entry;
- static idle/failure;
- non-light stillness after settling.

Compare 0%, 10%, 25%, 50%, 75%, settled, and pulse extrema. Measure silhouette, edge continuity, duration/easing, light path, bloom area, intensity envelope, and non-light optical flow.

Never use frozen or reduced-motion evidence to pass this gate.

### Gate 6 — Accessibility and reduced motion

Validate Reduce Motion, Increase Contrast, Reduce Transparency where applicable, keyboard-only operation, VoiceOver order/actions, and supported text scaling.

Reduced Motion must preserve state meaning without freezing a transient peak or relying on color alone.

### Gate 7 — Final parity

Run:

- the complete exact A–K matrix;
- stress and accessibility scenarios;
- existing native semantic/unit/snapshot tests;
- smoke/artifact validation;
- cross-renderer static reports;
- normal-motion reports;
- computer-use live review;
- human saliency review.

Full parity requires:

- every required scenario disposition is `exact`;
- every hard invariant passes;
- all five parity dimensions pass separately;
- all frozen profiles pass;
- no environment skip;
- normal and reduced motion pass independently;
- cross-renderer and human reviewers approve the same commit;
- the evidence bundle is reproducible and complete.

If any gate fails, reopen the earliest affected gate.

### Gate 8 — Native golden eligibility

Only after Gate 7:

1. Record native 2× goldens from the approved commit and canonical environment.
2. Tie golden metadata to scenario, sources, fingerprint, profile/mask versions, and approval.
3. Require byte-exact native regression on the matching environment.
4. Never regenerate a golden merely to make a failing test pass.

If the user explicitly approved missing coverage, label the result and golden metadata `parity-with-waiver`. Never call it full parity.

## Region and text rules

Maintain versioned masks:

- `silhouette/body`
- `edge-core`
- `emissive-bloom`
- `non-text-content`
- `text/layout-boxes`
- `os-external`

Text pixels are excluded from aggregate SSIM/color/diff because browser/native rasterization differs. Text still requires:

- exact approved copy;
- correct font role/family/weight/size;
- correct bounding box and baseline;
- correct wrap/truncation;
- correct tabular/mono roles;
- the frozen logical layout tolerance.

`os-external` masks must be narrow and may not cover Halo-owned visuals. Never enlarge a mask because a candidate fails.

## Anti-random-fix rules

- Every edit cites a gap-ledger ID, target scenarios, regions, metric, and expected effect.
- Change one system at a time.
- Do not tune against one screenshot or one display profile.
- Do not average away a critical region with a large black area.
- Do not violate a hard invariant to improve an aggregate score.
- Do not derive tolerances from Halo divergence.
- Do not loosen thresholds after candidate styling.
- Do not grow masks to hide differences.
- Do not count temporary coverage as passed.
- Do not claim parity from unit/snapshot tests alone.
- Do not update goldens before Gate 7.

## Verification and reporting contract

Discover and record the exact working commands rather than assuming flags. At minimum, run the relevant Swift tests, Halo conformance tests on the canonical environment, scenario smoke harness, artifact validator, static comparison pipeline, and motion pipeline. Preserve stdout/stderr in the evidence bundle.

After each gate, report:

- files changed;
- ledger IDs addressed;
- scenarios affected;
- commands run and results;
- artifact paths;
- hard-invariant status;
- five-dimension status;
- remaining failures;
- earliest open gate;
- exceptions or temporary dispositions.

The final response must include:

1. Outcome label: `full parity`, `parity-with-waiver`, or `not passed`.
2. Hard-invariant checklist.
3. Five-dimension scorecard.
4. Exact/temporary/blocked scenario coverage.
5. Gate results.
6. Commands and test results.
7. Evidence bundle path.
8. Threshold/mask versions.
9. Human and cross-renderer approvals.
10. Waivers, exceptions, residual risks, and restoration work.

Do not stop at an attractive screenshot. Stop only when the validation contract passes or an evidence-backed blocker requires user authority.
