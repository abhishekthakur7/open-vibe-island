# Halo visual-fidelity parity audit and validation specification

Status: implementation brief

Reference: [`06-halo.html`](./06-halo.html)

Audit date: 2026-07-30

Scope: Halo overlay only

## 1. Executive verdict

The implemented Halo is structurally much further along than its live presentation suggests: the theme has dedicated SwiftUI slots, most of the reference colors and timings are represented in code, and there are semantic and deterministic-rendering tests. That is not the same as visual parity.

The live overlay reviewed with computer-use is approximately **35–40% of the intended visual fidelity**. This is a qualitative design-review estimate, not a calibrated score. The current implementation recognizes many of the right nouns—black surface, edge light, liveness glyph, session rows, status colors—but it does not yet reproduce the reference's composition, restraint, saliency, density, or choreography.

The central mismatch is:

> The reference is a quiet black object whose light localizes only when it has meaning. The current live implementation reads as a conventional monitoring panel surrounded by a large decorative gradient glow.

The most consequential gaps are:

1. The edge light is too broad, continuous, and visually dominant in normal working states.
2. The expanded panel is too flat, tall, uniformly divided, and weakly grouped.
3. Status dots, gaps, labels, and repeated separators compete instead of establishing a single focal point.
4. Raw presentation strings such as `Exec`, `Wait`, `Thinking`, and `/` expose implementation state rather than narrated activity.
5. The intended light-travel choreography—especially the continuous surface morph and attention light condensing into a hero—is not proven.
6. The existing validation stack can preserve native output, but it cannot demonstrate that the output matches the HTML reference. It also freezes or reduces motion, so it cannot prove animation parity.

The correct starting point is therefore not styling. It is a reproducible reference/native scenario manifest, neutral renderer calibration, and failing parity evidence. Only then should implementation proceed in gated slices.

## 2. Purpose and non-goals

This document defines:

- what “Halo parity” means;
- what is currently missing or unproven;
- which reference states must be reproducible;
- how HTML and native output must be captured and compared;
- which conditions are hard failures;
- how static, interaction, motion, and accessibility evidence must be evaluated;
- the order in which implementation may proceed;
- when native goldens become eligible to record.

This document does **not**:

- implement a fix;
- prescribe a wholesale SwiftUI rewrite;
- claim browser and SwiftUI text pixels should be byte-identical;
- allow a perceptual score to override a broken design law;
- authorize regenerating snapshots to make tests pass;
- treat a unit-test pass as proof of visual parity.

## 3. Sources of truth

### 3.1 Design authority

The authoritative design artifact is [`06-halo.html`](./06-halo.html), including its thesis, sections A–K, captions, static compositions, and motion demonstrations.

When parts of the board conflict, use this precedence:

1. Product thesis and scenario caption.
2. The scenario's intended static composition.
3. CSS geometry, color, opacity, duration, and easing values.
4. Demonstration-loop mechanics used to keep the board visibly animated.
5. Native code comments and existing tests, which are implementation evidence rather than design authority.

This matters for repeating demonstrations. For example, the HTML success animation loops so it remains visible on a design board, while the caption says it is a brief moment that dissolves and settles. Product parity is a one-shot success event using the demonstrated 3-second envelope, not a permanent repeating success celebration. The same rule applies to a row “entrance” sweep: it is an entrance event, not ambient movement forever.

### 3.2 Native implementation evidence

Primary implementation surfaces:

- `Sources/OpenIslandApp/Views/Island/HaloEdgeLight.swift`
- `Sources/OpenIslandApp/Views/Island/HaloClosedPill.swift`
- `Sources/OpenIslandApp/Views/Island/HaloSessionRow.swift`
- `Sources/OpenIslandApp/Views/Island/HaloSessionListScaffold.swift`
- `Sources/OpenIslandApp/Views/Island/HaloHeaderControls.swift`
- `Sources/OpenIslandApp/Views/Island/HaloUsageSummary.swift`
- `Sources/OpenIslandApp/Views/Island/HaloUsageMeterCard.swift`
- `Sources/OpenIslandApp/Theme/HaloTheme.swift`
- `Sources/OpenIslandApp/Views/IslandPanelView.swift`
- `Sources/OpenIslandApp/OverlayPanelController.swift`
- `Sources/OpenIslandApp/IslandChromeLayout.swift`
- `Sources/OpenIslandApp/AppearancePreviewFixtures.swift`
- `Sources/OpenIslandApp/IslandDebugScenario.swift`

Validation and harness evidence:

- `Tests/OpenIslandAppTests/HaloConformanceSnapshotTests.swift`
- `Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift`
- `Tests/OpenIslandAppTests/HaloEdgeLightTests.swift`
- `Tests/OpenIslandAppTests/HaloClosedPillTests.swift`
- `Tests/OpenIslandAppTests/HaloSessionListTests.swift`
- `Tests/OpenIslandAppTests/HaloPermissionHeroTests.swift`
- `Tests/OpenIslandAppTests/HaloThemeTests.swift`
- `scripts/smoke-all-scenarios.sh`
- `scripts/validate-harness-artifacts.py`

### 3.3 Live evidence reviewed

The following states were inspected in the running app with computer-use:

- Collapsed, multiple sessions working.
- Expanded, mixed live sessions.
- The HTML reference board in `06-halo.html`.

Observed collapsed behavior:

- a large continuous cyan/violet bloom surrounds the pill;
- the three liveness bars read predominantly white rather than like cyan/violet light filaments;
- the agents grid reads gray and passive;
- the right-side narration is `3 working`.

Observed expanded behavior:

- the panel reads as a flat list of roughly eight sessions;
- large vertical gaps and strong repeated dividers create a tall monitoring table;
- status dots are optically large and repetitive;
- visible labels include raw/generic activity such as `Exec`, `Wait`, and `Thinking`;
- some project labels appear as `/`;
- state priority is weak; “needs you” does not visually dominate;
- the outer perimeter remains prominent instead of yielding to localized row or hero light.

States not directly observed in that live review remain **unverified**, not assumed correct. Code and comments that describe the intended state are evidence of implementation intent only.

## 4. What already exists and should be preserved

The implementation is not empty. Several reference-level decisions are already encoded:

| System | Reference | Native evidence |
|---|---|---|
| Edge width | 1.5 CSS px | `HaloMetrics.edge = 1.5` pt |
| Working orbit | 6 s linear | `HaloMotion.orbit = 6` |
| Permission pulse | 1.9 s | `HaloMotion.permissionPulse = 1.9` |
| Question pulse | 2.6 s | `HaloMotion.question = 2.6` |
| Success dissolve | 3 s | `HaloMotion.success = 3` |
| Hero ring | 2.2 s | `HaloMotion.heroRing = 2.2` |
| Liveness wave | 1.05 s, 0/.13/.26 delays | matching `HaloMotion` values |
| Waiting breathe | 2.4 s | `HaloMotion.breathe = 2.4` |
| Pill height | 38 logical units | `HaloClosedPill.height = 38` |
| Open/close | native spring/smooth | Halo motion tokens, currently 0.46/0.86 and 0.32 s |
| Surface | true-black intent | Halo surface tokens and dedicated views |
| Semantic states | idle/running/permission/question/success/failure | dedicated state model and tests |
| Expanded structures | groups, rails, hero, detail, usage, subagents | dedicated Halo views exist |

This table proves that the implementation contains much of the intended vocabulary. It does **not** prove that:

- the edge renders at the intended optical weight;
- SwiftUI shadow behavior matches the CSS bloom;
- the correct state is composed in the live app;
- native layout density matches the reference;
- the light travels along the same path;
- a single surface morphs without crossfade;
- the intended copy is what the user actually sees.

Future work should measure and repair the rendering/composition path before replacing these primitives.

## 5. The Halo design laws

These are the product-level invariants behind every scenario.

### L1. One true-black body

Halo is a `#000000` object fused to the notch. The body is not charcoal, vibrancy, translucent material, or a stack of independently appearing black cards.

### L2. The 1.5-unit edge is the state channel

The edge is not generic decoration. Its segment, hue, opacity, and bloom communicate idle, work, attention, success, and failure.

### L3. Quiet is the default

Most of the time Halo is a bare 8%-white hairline or a barely bright working segment. Idle must almost disappear. Working may have a faint supporting haze, but a broad, bright full-perimeter bloom must not become the main object.

### L4. One loud thing at a time

When permission or a question needs attention, that state becomes the single dominant visual event. The outer perimeter, every status dot, and every row must not compete at equal intensity.

### L5. Light localizes and travels

Working light orbits. Attention light warms and condenses. On open, attention transfers from the perimeter to the actionable row or hero. The transition should read as the same light moving to the place that needs the user.

### L6. The shape is continuous

The pill, peek, and panel are phases of one black surface. The edge remains attached to that surface throughout the morph. There is no pill-to-panel crossfade, duplicate silhouette, flash, seam, or broken ring.

### L7. Content is still

Outside the defined container morph, nothing moves except light. Text, rows, badges, and metadata do not bob, float, shimmer, or pulse to manufacture liveliness.

### L8. Hierarchy comes from type, spacing, and hairlines

Rows are near-chromeless. Fills are whispers. Repeated heavyweight dividers, oversized dots, and uniform card chrome are contrary to the reference.

### L9. Attention floats to the top

The expanded list is organized as **Needs You → Running → Done**. Rails appear only on active/actionable rows. Completed and idle content settle.

### L10. The product narrates work

The user sees “Editing AppModel.swift,” “Wants to run swift build,” or another human phrase—not internal enum cases, raw tool IDs, generic `Thinking`, or `/` as a project name.

### L11. State is never color alone

Permission, question, success, interrupted, and failure differ through glyph, wording, behavior, and placement as well as hue.

### L12. Accessibility preserves comprehension

Reduced motion removes nonessential animation without erasing state. Increased contrast, reduced transparency, keyboard focus, VoiceOver, and supported text scaling remain coherent.

## 6. Five independent parity dimensions

A single “looks close” score is prohibited. Each dimension passes separately.

| Dimension | Question |
|---|---|
| Structural | Are the correct states, groups, elements, order, and one-surface topology present? |
| Visual | Do geometry, density, type hierarchy, color, edge, bloom, and saliency match? |
| Copy/data | Are user-facing labels, names, counts, normalization, and fallbacks correct? |
| Interaction | Do hover, open, row expansion, approval, questions, focus, scrolling, and controls behave correctly? |
| Motion | Do duration, easing, silhouette continuity, light path, intensity envelope, stillness, and reduced-motion behavior match? |

A failure in any dimension blocks a full-parity claim even if an aggregate perceptual metric is high.

## 7. Current gap ledger

Severity:

- **P0**: breaks the Halo identity or makes parity unprovable.
- **P1**: major scenario or hierarchy divergence.
- **P2**: localized polish or coverage gap.

Evidence state:

- **Observed**: seen in the live computer-use review.
- **Source**: established only from implementation/reference inspection.
- **Unverified**: a required live state lacks parity evidence.

| ID | Sev. | Area | Evidence | Current gap | Reference requirement | Primary validation |
|---|---:|---|---|---|---|---|
| H-01 | P0 | A2′, C | Observed | Broad cyan/violet bloom makes the entire perimeter continuously loud. | A barely bright moving segment; faint haze may support it but must not dominate. | Edge-core/bloom masks, intensity/falloff, saliency review. |
| H-02 | P1 | A2′ | Observed | Liveness bars read white and the agents grid reads gray/passive. | Cyan→violet filament wave and bloomed active grid cells. | Crop, color/brightness samples, timed glyph frames. |
| H-03 | P0 | B/B′/K | Unverified | No accepted evidence proves one continuous pill→peek→panel silhouette. | One liquid black body; attached unbroken edge; no crossfade. | 60 fps alpha/silhouette track and adjacent-frame topology. |
| H-04 | P0 | E/K | Unverified | No evidence proves attention light travels from perimeter to row/hero. | Perimeter dims while the amber/qgold hero becomes dominant. | Light-centroid path, perimeter/card intensity envelopes. |
| H-05 | P1 | C | Observed | Expanded panel is tall, flat, and uniformly list-like. | Compact grouped instrument with hierarchy through type and hairlines. | Bounds, row-height, whitespace, and density measurements. |
| H-06 | P1 | C | Observed | Repeated heavy dividers and large status dots carry equal saliency. | Near-chromeless rows; 8-unit light-source dots; selective 2-unit rails. | Per-region size/contrast measurement and five-second saliency test. |
| H-07 | P0 | C | Observed + Source | Live state did not communicate Needs You → Running → Done even though grouping scaffolding exists. | Attention group first, then running, then done; counts and rails support order. | Exact group/order/state-membership assertion plus live capture. |
| H-08 | P1 | C | Observed | Outer edge remains a main focus when opened. | Opened mixed list is calm; state light localizes to active/actionable rows. | Outer-edge vs active-region luminance ratio. |
| H-09 | P0 | A/C/D | Observed | `Exec`, `Wait`, `Thinking`, and `/` expose raw or empty data. | Narrated action, normalized workspace, meaningful fallback. | Exact visible-string inventory; forbidden-string assertion. |
| H-10 | P1 | C | Observed | Uniform spacing and row treatment flatten state priority. | Attention floats to top; live rails, badges, and typography create clear tiers. | Layout anchors plus human hierarchy ranking. |
| H-11 | P1 | C/I | Observed | Split header and usage filaments do not carry the intended premium instrument quality. | Compact usage arcs on header wings around notch gap; quiet circular controls. | Header crop, geometry, optical weight, control-state captures. |
| H-12 | P1 | A3/A4/A5/A6 | Unverified | Permission, question, success, interrupted, and failed ambient states are not reference-validated. | Distinct hue + glyph + copy + motion/static behavior for each. | Exact scenario captures and state-specific motion traces. |
| H-13 | P1 | D–J | Unverified | Detail, hero, question, subagent, completion, usage, and empty states lack accepted reference/native comparison. | Every A–K composition must have exact mapped evidence. | Scenario manifest and per-state comparison bundle. |
| H-14 | P0 | K | Source | Existing deterministic snapshots force reduced motion/model-layer output. | Normal-motion parity requires real event recordings. | 60 fps canonical recording with locked event frame. |
| H-15 | P0 | Validation | Source | Native snapshots compare only against native goldens, not the HTML reference. | Cross-renderer reference conformance must precede regression locking. | Reference/native capture and registered per-mask reports. |
| H-16 | P0 | Validation | Source | Halo snapshot directory contains only `environment-fingerprint.txt`; no committed Halo PNG goldens were found. | Approved native candidate must eventually be regression-locked. | File manifest and Gate 8 eligibility check. |
| H-17 | P0 | Validation | Source | Environment mismatch skips pixel comparison. | A parity run must fail or quarantine mismatch, never silently pass through it. | Environment gate result in `summary.md`. |
| H-18 | P1 | Validation | Source | Harness strongly verifies geometry ranges, semantics, strings, process ownership, and artifact integrity but not reference composition or animation. | Reference-specific static and motion measurements. | Coverage matrix mapping each assertion to a parity dimension. |
| H-19 | P1 | Validation | Source | No `overlay.png` was found in existing Halo evidence directories during this audit. | Every required static state must have a canonical surface capture. | Evidence bundle completeness check. |
| H-20 | P2 | Code/test comments | Source | Several glow/morph properties are explicitly left to “judged by eye.” | Human review remains necessary, but it must be attached to measurable evidence and a checklist. | Signed review record linked to objective reports. |

The ledger must become a versioned artifact during implementation. No visual change may be made without a ledger ID, target scenarios, target regions, and expected measurable outcome.

## 8. Required A–K scenario manifest

Every row below needs an exact HTML/native mapping before dependent styling begins.

| ID | Required reference behavior | Required evidence |
|---|---|---|
| A1 | Idle pill: still dim glyph, dim dot, bare 8% hairline, no glow. | Stable frame; interior/edge samples; 2-second stillness clip. |
| A2 | One working: narrated activity, cyan→violet segment, 6 s linear orbit. | Stable quadrants plus full 6-second orbit trace. |
| A2′ | Many working: count, active agents grid, restrained orbit/bloom. | Static crop, grid cell state map, full orbit trace. |
| A3 | Permission: amber→magenta, hottest ambient state, 1.9 s pulse. | Trough/peak frames, intensity envelope, exact copy/glyph. |
| A4 | Question: softer qgold, breathing glyph, `?`, 2.6 s pulse. | Trough/peak frames, waveform, non-color distinction. |
| A5 | Success: green/cyan bloom, one-shot 3 s dissolve to quiet. | Event-to-settle recording and final hairline frame. |
| A6 | Interrupted vs failed: distinct glyph/copy; failure static dim red. | Side-by-side frames and 3-second no-pulse proof. |
| B | Hover peek after 0.15 s dwell; 1.03 scale; actionable item only. | Pointer-trigger log, pre/dwell/peek frames, focus/exit behavior. |
| B′ | Pill→peek→panel and reverse as one silhouette with attached edge. | 60 fps alpha/silhouette filmstrip both directions. |
| C | Compact grouped list: Needs You, Running, Done; selective rails. | Full panel, group/order manifest, density/rail/divider measurements. |
| D | In-place row detail: metadata grid, narrated activity, rich last message, primary Jump. | Collapsed/expanded frames and interaction/focus sequence. |
| E1 | Command permission hero with syntax, scope actions, keycaps. | Hero/perimeter intensity handoff, exact layout and action states. |
| E2 | Edit permission hero with real inline diff. | Diff geometry/copy, hero ring, scroll/overflow behavior. |
| E3 | Codex terminal approval with honest Jump CTA, no fake approval. | Copy/action assertion, hero composition, keyboard path. |
| F1 | Multi-question pagination and option descriptions. | Each page, selection, Next/Submit, keyboard and focus sequence. |
| F2 | Multi-select with square markers and Other input. | Empty/selected/freeform/submitted states. |
| F3 | Compact simple question. | Static compact state and answer interaction. |
| G | Expanded subagents/tasks with per-agent status and todo progress. | Expanded detail, nested hierarchy, overflow and updates. |
| G′ | Compressed subagent count/agents-grid in pill. | Pill frame and live-grid mapping. |
| H | Completed session with outcome, rich result, conditional Reply. | Success/interrupted/failed variants and action availability. |
| I | Full usage meters, thresholds, reset copy, provider windows. | Fine/warn/critical and zero/missing-data variants. |
| I′ | Critical usage compressed into pill without competing with attention. | Static priority combinations and copy. |
| J | Empty expanded state mirrors A1 calmness. | Empty panel, workspace-count variants, stillness proof. |
| J′ | Idle collapsed form indistinguishable from A1. | Registered A1/J′ comparison. |
| K | Orbit, morph, condense, success, row entrance, failure, idle, glyph motion. | Normal-motion videos, frame strips, timing and path reports. |

Additional required stress scenarios:

- long workspace, branch, command, and activity strings;
- duplicate workspace names;
- missing workspace metadata (must not render `/`);
- zero, one, and many sessions;
- overflow and scrolling;
- fine, warning, and critical usage;
- permission plus other running sessions;
- question plus permission priority;
- keyboard focus and full keyboard operation;
- Increase Contrast;
- Reduce Transparency where applicable;
- Reduce Motion;
- supported text scaling;
- both shipped display profiles where geometry differs.

### 8.1 Manifest row schema

Each scenario record must include:

- scenario ID and reference section;
- human-readable intent;
- deterministic fixture data and seed;
- HTML DOM selector and state-setting mechanism;
- native fixture/harness state and trigger sequence;
- SHA-256 of the reference HTML and relevant native sources;
- commit SHA and dirty-state flag;
- viewport, browser zoom, panel geometry, scale, and crop;
- stable frame and timed checkpoints;
- expected visible copy, grouping, order, and state membership;
- required mask IDs and threshold-profile ID;
- reference/native capture filenames;
- reproduction evidence;
- disposition and scenario result;
- approver, rationale, risk, and restoration requirement.

Allowed dispositions:

- `exact`: reproducible reference state mapped to a semantically equivalent native state; eligible to pass.
- `temporary-surrogate`: investigation may continue with a documented approximation; scenario remains **NOT PASSED**.
- `temporary-exclusion`: unrelated investigation may continue without this state; scenario remains **NOT PASSED**.
- `blocked`: dependent work stops.

A surrogate or exclusion never silently becomes accepted coverage.

## 9. Why the existing validation stack is insufficient

### 9.1 Native snapshot tests can lock the wrong pixels perfectly

`HaloConformanceSnapshotTests` renders Halo scenarios through native SwiftUI. `ThemeSnapshotting` can then perform byte-exact normalized RGBA comparison against a native PNG recorded on a matching environment.

That is useful for regression protection **after** a native frame has been approved. It does not compare native output with `06-halo.html`, so it cannot establish design-reference parity.

### 9.2 There are currently no Halo PNG goldens

At audit time:

```text
Tests/OpenIslandAppTests/__Snapshots__/HaloConformanceSnapshotTests/
└── environment-fingerprint.txt
```

No Halo PNG goldens were present. On a matching environment this is a missing-golden failure; on a mismatched environment the test can skip before reaching useful pixel enforcement.

### 9.3 Environment mismatch is treated as skip

The native helper intentionally skips byte comparison when the fingerprint differs. That is reasonable for general CI stability, but unacceptable as the acceptance result of a parity run. A canonical parity run must have a matching fingerprint or be reported as **quarantined/not evaluated**.

### 9.4 Motion is removed from deterministic snapshots

The native renderer forces Reduce Motion, captures the model layer, and omits live clocks. That makes static screenshots repeatable. It also means:

- orbit continuity is not tested;
- permission/question pulse envelopes are not tested;
- success entry/dissolve is not tested;
- hover dwell and peek are not tested;
- pill/panel morph topology is not tested;
- attention-light travel is not tested.

Reduced-motion evidence is required, but it cannot substitute for normal motion.

### 9.5 Smoke evidence is semantic, not compositional

The scenario smoke scripts and artifact validator provide valuable evidence for:

- process ownership;
- artifact integrity;
- accessibility semantics;
- strings;
- expected geometry ranges;
- scenario reachability.

They do not currently answer whether the reference's density, saliency, bloom, edge behavior, hierarchy, or motion path has been reproduced.

## 10. Validation architecture

Validation has two layers:

1. **Cross-renderer design-reference conformance**
   HTML reference versus native SwiftUI using logical geometry, registered masks, perceptual metrics, event traces, and human sign-off.

2. **Native regression locking**
   Byte-exact native 2× PNG comparison on a matching canonical environment, recorded only after the reference-conformance candidate is approved.

Cross-renderer byte equality is not an appropriate goal because WebKit/CoreText and SwiftUI/CoreText may rasterize equivalent text and fractional geometry differently. That renderer difference must be characterized with neutral primitives—not inferred from current Halo differences.

## 11. Gate 0A: reproduce and map every state

Before calibration, styling, or goldens:

1. Reproduce every required HTML state deterministically.
2. Reproduce its native state with fixed fixture data.
3. Prove the trigger reaches the intended state.
4. Record selectors, fixtures, source hashes, geometry, checkpoints, and disposition.
5. Mark every row `exact`, `temporary-surrogate`, `temporary-exclusion`, or `blocked`.

If a required state is not reproducible:

- dependent implementation is blocked;
- unrelated investigation may continue only with an approved temporary disposition;
- the scenario remains NOT PASSED;
- Gate 7 and Gate 8 remain blocked.

Only the user may approve a named waiver allowing a missing state to proceed beyond Gate 7. That result must be labeled **parity-with-waiver**, never full parity. The waiver must name the lost coverage, risk, evidence, and restoration condition.

## 12. Gate 0B: neutral pre-edit calibration

Calibration measures the comparison system, not the quality of the current UI.

### 12.1 Allowed inputs

- repeated identical captures in each renderer;
- intentionally matched neutral black rectangles and rounded shapes;
- known-width neutral strokes;
- fixed geometry anchors;
- controlled neutral color patches;
- matched non-Halo glyph/icon primitives;
- fixed text boxes used only to characterize layout/rasterization variance;
- known capture/encoding transforms.

### 12.2 Forbidden inputs

- current live Halo versus `06-halo.html`;
- a candidate Halo implementation versus the reference;
- any known difference in bloom, spacing, hierarchy, copy, shape, or motion;
- samples selected after styling because they make a candidate pass.

The current implementation/reference delta is the defect being measured. It cannot become the tolerance budget.

### 12.3 Same-renderer repeatability

For both HTML and native:

1. Capture at least five identical static samples.
2. Capture at least three identical motion runs.
3. Measure encoding variance, antialiasing variability, font rasterization variability, capture jitter, and dropped/duplicated frames.
4. Establish per-region noise floors.
5. Stabilize the renderer if repeatability is too weak.

### 12.4 Cross-renderer neutral calibration

Use intentionally equivalent neutral primitives to:

- verify CSS px to SwiftUI pt mapping;
- measure stable edge antialiasing differences;
- characterize color-management differences;
- characterize text rasterization separately from text layout;
- determine crop registration precision;
- measure motion-capture timestamp error.

### 12.5 Tolerance budget and freezing

A threshold profile may contain only:

- measured same-renderer repeatability noise;
- stable renderer-specific raster variance demonstrated by neutral primitives;
- a documented statistical safety margin derived from those samples.

Profiles are frozen before candidate styling. Every profile records raw samples, sample count, distributions, mapping transform, tolerance, rationale, date, and approver.

A candidate failure is never grounds to loosen a profile. Revision requires new neutral evidence, a new version, impact analysis, and approval.

Hard design invariants sit outside calibration and cannot be weakened.

## 13. Canonical units and 2× capture

The provisional canonical transform is:

```text
1 CSS px = 1 SwiftUI pt = 2 device pixels at 2×
1.5 CSS px edge = 1.5 SwiftUI pt = 3 device pixels nominally
```

All reports must include logical units and device pixels.

Fractional strokes spread across additional raster pixels because of antialiasing. Measure:

- vector/layout centerline where available;
- nominal stroke width;
- edge-core intensity profile;
- bloom separately from edge core.

Do not infer a 1.5-unit stroke solely by counting every non-black antialiased pixel.

If neutral calibration disproves the provisional transform, record the replacement transform, samples, affected environments, and approval before any candidate styling.

## 14. Canonical capture environment

Every parity run records:

- commit SHA and dirty state;
- SHA-256 of reference and relevant native sources;
- macOS product/build version and architecture;
- hardware identifier;
- Xcode and Swift versions;
- app build configuration;
- browser engine and version;
- viewport, browser zoom, and device scale;
- display resolution, refresh rate, scale factor, and color profile;
- font names, files, and versions;
- locale, timezone, appearance, and content-size settings;
- Reduce Motion, Increase Contrast, and Reduce Transparency values;
- fixture seed and wall-clock strategy;
- overlay position, pointer origin, and crop;
- capture tool/version and image/video encoding;
- event timestamp method and frame-rate report.

For static captures:

- use 2× output;
- align the surface crop, not the decorative desktop board;
- keep the pointer outside unless hover is under test;
- capture a lossless PNG;
- retain uncropped source evidence.

For motion:

- target 60 fps;
- record actual frame timestamps;
- mark the triggering event as frame zero;
- detect dropped or duplicated frames;
- capture at least one complete cycle plus settled state;
- repeat enough times to establish capture stability.

An environment mismatch fails or quarantines the run. It never produces a passing parity result by skipping checks.

## 15. Region and mask policy

Every comparison uses registered, versioned masks.

| Mask | Includes | Evaluated for |
|---|---|---|
| `silhouette/body` | owned black surface, bounds, corners, continuity | topology, geometry, black value |
| `edge-core` | nominal living stroke only | width, centerline, stops, opacity |
| `emissive-bloom` | falloff outside edge/card/rail/dot | area, centroid, intensity, localization |
| `non-text-content` | glyphs, dots, rails, meters, dividers, owned icons | geometry, color, contrast, SSIM |
| `text/layout-boxes` | string boxes, baselines, wrapping, truncation | exact copy, role, position, size |
| `os-external` | narrowly scoped nondeterministic OS content | excluded only with written reason |

Rules:

- Hard invariants are evaluated before aggregate metrics.
- Edge core and bloom are always scored separately.
- Text raster pixels are excluded from aggregate SSIM, changed-pixel, and color scores.
- Text still requires exact approved strings, correct font role, bounds/position within the frozen layout tolerance, baseline alignment, wrapping, and truncation.
- `os-external` may not cover Halo-owned visuals.
- Masks freeze with source hashes and threshold profiles before styling.
- A mask cannot be enlarged after seeing a candidate without new neutral evidence and approval.
- Large black areas cannot average away a critical edge, hero, or hierarchy failure.

## 16. Hard invariants and automatic failures

The following are automatic failures, regardless of SSIM or another aggregate score:

- Halo-owned surface is not logically and visually true `#000000`.
- Nominal living edge is not 1.5 mapped units.
- Idle shows glow instead of a bare hairline.
- Working shows a broad, bright continuous perimeter as its dominant signal rather than a moving segment with only restrained supporting haze.
- Two black silhouettes coexist during open/close, or the transition crossfades.
- The edge breaks, detaches, flashes, or changes to a separate shape during the morph.
- Attention fails to become the single dominant emphasis.
- Permission/question outer light does not hand off to the actionable row/hero on open.
- Raw user-visible `Exec`, `Wait`, `Thinking`, or `/` fallback appears in an acceptance scenario.
- Needs You, Running, Done ordering or state membership is wrong.
- Failure pulses; success remains permanently loud; an entrance sweep becomes ambient perpetual content motion.
- Settled non-light content moves without an approved interaction reason.
- A normal-motion scenario is “validated” only with frozen or reduced motion.
- A required scenario is silently skipped.
- A temporary surrogate/exclusion is counted as passed.
- A threshold is derived from current/candidate Halo divergence.
- A mask hides Halo-owned disagreement.
- A golden is recorded before Gate 7 approval.

## 17. Provisional metric targets

These are starting targets, not acceptance thresholds, until Gate 0B freezes evidence-derived profiles.

| Measurement | Provisional target |
|---|---:|
| Primary anchor displacement | ≤ 1 pt / 2 device px |
| Key dimension, radius, internal spacing | ± 2 pt / 4 device px |
| Text box/baseline displacement | ≤ 1 pt / 2 device px |
| Overall non-text SSIM after registration | ≥ 0.970 |
| Critical silhouette/body SSIM | ≥ 0.985 |
| Changed non-text area above calibrated threshold | ≤ 3% overall |
| Changed area in edge/hero critical regions | ≤ 1% |
| Median ΔE2000 outside emissive bloom | ≤ 2.0 |
| 95th percentile ΔE2000 outside emissive bloom | ≤ 5.0 |
| Settled non-light changed area in motion | ≤ 0.5% |
| Light centroid/path error | ≤ 3 pt / 6 device px |
| Explicit motion duration error | ≤ 2 frames or 50 ms where capture supports it; otherwise ≤ 10% |
| Adjacent-frame unexplained silhouette jump | ≤ 1 pt / 2 device px |

After calibration, profiles may differ by mask/scenario where neutral evidence justifies it. They must not differ merely because one scenario is harder to implement.

## 18. Static and structural validation

For each stable frame:

1. Normalize reference/native surface crops to the same logical size.
2. Register using surface geometry, not text.
3. Validate group/order/state membership and component presence.
4. Evaluate hard invariants.
5. Compare silhouette bounds, corner radii, notch relationship, row heights, group gaps, rails, dividers, dots, controls, and meters.
6. Evaluate per-mask perceptual/color metrics.
7. Evaluate text separately.
8. Produce reference/native/overlay/heatmap views.
9. Require a human saliency review.

Required human questions:

- What is the first thing seen in five seconds?
- Is there exactly one loud thing?
- Does the black surface read as the notch growing?
- Does working feel alive but quiet?
- Does attention visibly localize?
- Does the expanded panel scan by state before it scans by row?
- Do the dots and dividers support hierarchy rather than become the hierarchy?
- Does the design feel still except for meaningful light?

The reviewer records pass/fail and a short rationale; “looks premium” alone is not evidence.

## 19. Copy and typography validation

### 19.1 Exact copy

For every acceptance frame, inventory visible strings and compare them with the manifest. Assert:

- no raw internal state names;
- no empty `/` workspace fallback;
- human activity narration;
- correct singular/plural counts;
- correct provider and reset labels;
- honest agent-specific actions;
- correct permission/question wording;
- correct group titles and order.

### 19.2 Text geometry

Because browser/native rasterization differs, validate:

- font role/family;
- logical point size and weight;
- tracking role;
- bounding box and baseline;
- line count and wrapping;
- truncation behavior;
- tabular numerals where intended;
- mono only in approved code/value roles;
- contrast role (`t1`, `t2`, `t3` equivalent).

Text pixels are not allowed to contaminate non-text SSIM or ΔE results, but text layout remains binding.

## 20. Interaction validation

Record trigger-to-state evidence for:

- pointer dwell, enter, and exit;
- peek to full open;
- open to close;
- row expand/collapse;
- hover-reveal dismiss;
- Jump, Transcript, Reply, Approve, Deny, and scoped approval;
- Codex terminal jump without fake approval;
- question selection, multi-select, Other input, page progression, and submission;
- scrolling and overflow;
- mute/settings/quit controls;
- keyboard focus order and visible focus;
- Escape and other documented dismissal behavior.

Each interaction must:

- reach the manifest state;
- preserve a continuous surface where required;
- expose no dead or ambiguous target;
- preserve semantic and keyboard order;
- leave the correct settled visual state.

## 21. Motion validation

### 21.1 Reference motion table

| Primitive | Reference behavior |
|---|---|
| Working orbit | 6 s, linear, continuous angle, restrained brightness |
| Permission ambient | 1.9 s ease-in-out edge/bloom pulse |
| Question ambient | 2.6 s gentler opacity pulse; steady softer bloom |
| Success | 3 s ease-out, one event, settles to hairline |
| Hero ring | 2.2 s ease-in-out pulse |
| Liveness run | 1.05 s wave, bar delays 0/.13/.26 s |
| Liveness wait | 2.4 s breathe |
| Hover peek | 0.15 s dwell, scale 1.03 |
| Morph | continuous black geometry; no crossfade or detached edge |
| Row entrance | one faint light sweep on entry |
| Failure | static dim red segment; no pulse |
| Idle | static bare hairline |

Native open/close tokens do not have an automatically authoritative HTML equivalent. Their parity must be based on the captured reference interaction and the continuous-shape law, not merely on matching a number in code.

### 21.2 Capture and checkpoints

For each event:

- frame zero is the trigger timestamp;
- compare 0%, 10%, 25%, 50%, 75%, and 100%/settled;
- include cycle trough and peak for pulses;
- record full cycles for periodic light;
- record both expand and collapse;
- retain timestamps rather than assuming perfect 60 fps.

### 21.3 Measurements

Measure:

- silhouette bounds and topology per frame;
- corner-radius evolution;
- edge continuity and centerline;
- orbit angle monotonicity and angular velocity;
- light centroid/path;
- perimeter, rail, and hero intensity envelopes;
- bloom alpha area and falloff;
- non-light optical flow;
- duration and easing curve;
- dropped/duplicate frames;
- settled-state variance.

Key motion assertions:

- orbit angle is monotonic and approximately linear;
- permission/question peaks and troughs occur at the intended cadence;
- success is one-shot and reaches a quiet settled frame;
- no double silhouette or alpha crossfade appears;
- no edge discontinuity occurs during the morph;
- permission/question light visibly transfers inward;
- the outer perimeter dims as the hero becomes dominant;
- row sweep happens only on row entry;
- failure and idle remain static;
- non-light optical flow settles to the calibrated noise floor.

## 22. Accessibility and reduced motion

Validate accessibility as separate scenarios:

- Reduce Motion;
- Increase Contrast;
- Reduce Transparency where relevant;
- keyboard-only operation;
- VoiceOver labels, grouping, order, and actions;
- supported text scaling.

Reduced Motion must:

- suppress orbit/pulse/wave/breathe/morph flourishes that are nonessential;
- preserve a legible static state-specific edge/glyph;
- preserve permission/question distinction beyond color;
- avoid freezing a transient success peak permanently;
- keep focus and interactions functional.

An accessibility adaptation may intentionally differ from the default reference, but its disposition and semantic-equivalence criteria must be explicit. Default parity cannot be claimed from the accessibility rendering.

## 23. Anti-random-fix rules

1. No edit without a gap-ledger ID, scenario IDs, target regions, intended metric, and predicted effect.
2. Finish scenario mapping and neutral calibration before styling.
3. Change one visual system at a time.
4. Use this order: structure/copy → surface/geometry → hierarchy → light → interaction → motion → accessibility.
5. Do not tune against one screenshot, one profile, or one renderer.
6. Do not use a large black area to average away a critical-region failure.
7. Do not revise thresholds because a candidate fails.
8. Do not expand masks to hide Halo-owned pixels.
9. Do not accept a metric improvement that breaks a hard invariant or another parity dimension.
10. Do not create an abstraction solely to satisfy a snapshot without proving all affected scenarios.
11. Do not record or update native goldens before Gate 7.
12. Every exception records rationale, owner, evidence, affected scenarios, risk, approval, and outcome-label impact.

## 24. Implementation gates

| Gate | Required outcome | Blocks |
|---|---|---|
| 0A State mapping | Every A–K state reproduced and mapped exactly, or explicitly temporary/blocked. | Dependent calibration/implementation |
| 0B Neutral calibration | Repeatability measured; logical transform proven; masks/profiles frozen from neutral evidence. | Styling |
| 0C Baseline | Reference/native captures, hashes, masks, manifest, and gap ledger complete. | Candidate edits |
| 1 Structure & copy | Correct groups/order/hierarchy/state membership and narrated copy. | Geometry/light work that would mask structure |
| 2 Surface & geometry | One true-black surface, compact density, correct rows/rails/header/usage geometry. | Final light tuning |
| 3 Light | Correct edge core, restrained work state, localized attention, hero handoff, saliency. | Motion acceptance |
| 4 Interaction | Hover, morph triggers, actions, focus, scroll, permission/question paths pass. | Motion acceptance |
| 5 Normal motion | Silhouette, timing, easing, light path, stillness, and event behavior pass. | Accessibility/final |
| 6 Accessibility | Reduced motion and other accessibility variants pass independently. | Final |
| 7 Final parity | Full matrix, native tests, cross-renderer review, human sign-off, evidence complete. | Goldens |
| 8 Golden eligibility | Only the Gate 7 candidate may become native regression goldens. | Release claim |

A regression reopens the earliest affected gate.

Temporary surrogates/exclusions may unblock unrelated investigation but remain NOT PASSED. Gate 7/8 require exact coverage unless the user explicitly approves a named waiver. Waived results and any associated golden metadata must say **parity-with-waiver**.

## 25. Evidence bundle

Use:

```text
artifacts/halo-parity/<commit>/<run-id>/
├── environment.json
├── source-manifest.json
├── scenario-manifest.json
├── gap-ledger.md
├── calibration/
│   ├── neutral-primitives/
│   ├── same-renderer-repeatability/
│   ├── cross-renderer-neutral/
│   ├── unit-transform.json
│   ├── noise-floor-report.json
│   └── threshold-profiles/
├── masks/
├── reference/
│   ├── static/
│   └── motion/
├── native/
│   ├── static/
│   └── motion/
├── diffs/
│   ├── overlays/
│   ├── heatmaps/
│   └── reports/
├── motion/
│   ├── frame-strips/
│   ├── silhouette-tracks/
│   ├── optical-flow/
│   └── light-paths/
├── accessibility/
├── logs/
├── review/
│   ├── dispositions/
│   ├── waivers/
│   ├── threshold-approvals/
│   └── human-signoff.md
└── summary.md
```

Every artifact identifies scenario ID, commit, source hashes, renderer, fingerprint hash, capture timestamp, mask/profile version, and tool provenance.

`summary.md` must include:

- every hard invariant and result;
- five independent dimension results;
- exact/temporary/blocked coverage;
- per-scenario result;
- earliest failed gate;
- threshold profile versions;
- exceptions and waivers;
- native test status;
- human and cross-renderer approvals;
- final outcome label: `full parity`, `parity-with-waiver`, or `not passed`.

## 26. How to start implementation

The first implementation task should not change Halo visuals. It should deliver Gates 0A–0C:

1. Build the source/scenario manifests and hash both render paths.
2. Make every A–K state deterministically reproducible.
3. Capture canonical HTML and current-native baselines.
4. Build neutral calibration primitives and establish noise floors.
5. Prove or replace the CSS px/SwiftUI pt/device-pixel transform.
6. Create and freeze masks and threshold profiles.
7. Emit current failing comparison reports.
8. Review the gap ledger against those reports.

Only then implement in this order:

1. Structure and presentation language.
2. Surface geometry and density.
3. Edge and localized light.
4. Hover, morph, and attention handoff.
5. Detail/hero states.
6. Normal motion.
7. Accessibility and reduced motion.
8. Full regression and, only after approval, native goldens.

This order prevents a polished glow from hiding the wrong hierarchy and prevents a newly recorded snapshot from blessing an unvalidated candidate.

## 27. Definition of done

### Full parity

Halo has full parity only when:

- every required A–K scenario has disposition `exact`;
- Gates 0A and 0B passed before candidate styling;
- every scenario has source hashes, fixtures, checkpoints, masks, and a frozen threshold profile;
- every hard invariant passes;
- all five parity dimensions pass independently;
- all frozen metric profiles pass;
- exact copy and text-layout checks pass;
- normal motion and reduced motion pass separately;
- existing native semantic/conformance tests remain green;
- no scenario or metric was skipped because of environment mismatch;
- cross-renderer review and human review approve the same commit;
- the evidence bundle is complete and reproducible;
- native goldens, if added, come only from that approved commit.

### Parity-with-waiver

If exact coverage is missing:

- the missing scenario remains NOT PASSED;
- the user must approve a named waiver acknowledging lost coverage and risk;
- reports and goldens must say `parity-with-waiver`;
- the result must never be described as full parity;
- exact coverage restoration remains open work.

Anything else is `not passed`, regardless of how attractive an individual screenshot appears.
