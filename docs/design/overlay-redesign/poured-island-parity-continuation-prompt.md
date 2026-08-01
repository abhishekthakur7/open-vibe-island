# Continuation prompt: implement and visually validate Poured Island parity

Copy the block below into a fresh Codex task. It is self-contained; do not rely on context from the task that authored it.

---

You are the root orchestrator for an evidence-driven native Poured Island parity program in the `open-vibe-island` repository.

## Mission

Bring the repo-built `OpenIslandApp` into visual, UX, interaction, and motion parity with `docs/design/overlay-redesign/01-poured-island.html`.

Every coherent visual change must be compared against the reference and independently reviewed. Builds, lint, unit tests, snapshots, and image metrics are required supporting evidence, but **none of them proves visual parity**. Do not redesign the reference and do not make opportunistic “premium” or random UI fixes. Every source edit must map to a stable audit ledger ID, deterministic scenario, affected region, expected result, and acceptance check.

Continue until full parity is proven or an evidence-backed stop condition makes progress unsafe. Do not stop merely because the code builds or a first pass looks better.

## Required first reads

Read these completely before planning or editing:

1. `AGENTS.md`
2. The worktree guide referenced by `AGENTS.md`, if it exists in the current checkout. At this audit commit it is not present; record that documentation gap and inspect `scripts/agent-worktree.sh` plus Git's actual worktree metadata instead of inventing commands.
3. `docs/design/overlay-redesign/01-poured-island.html`
4. `docs/design/overlay-redesign/poured-island-visual-parity-audit.md`
5. This continuation prompt
6. Current Poured/native symbols covering:
   - `AppModel`, session projection, visibility, grouping, ordering, capping, workspace identity, and presentation;
   - `PouredClosedPill`, `PouredSessionListScaffold`, `PouredSessionRow`, usage, empty, permission, question, task, and completion views;
   - `PouredIslandTheme`, Poured color/metrics/material/motion tokens;
   - `OpenedIslandSurfaceShape`, `OpenedSurfaceMaterial`, and the shared morph in `IslandPanelView`;
   - appearance preview fixtures, Poured tests, launch/capture harnesses, and parity tooling.

Inspect current source; audit line numbers are evidence from its baseline, not permanent authority. If `.codegraph/` exists, use CodeGraph before broad `rg`/file reading. Existing Halo parity tools are Halo-specific: generalize only genuinely shared primitives or create a Poured namespace. Do not silently relabel Halo scenarios as Poured evidence.

At the start of every round run `git status -sb`. Resolve the actual Git common directory and canonical `main` integration worktree before creating a topic worktree. `AGENTS.md` contains historical `/Users/wangruobing/...` examples while this checkout may be under `/Users/abhishekthakur/...`; trust Git's actual worktree metadata, do not guess. Never edit the shared `main` checkout.

## Non-negotiable design laws

- Pill, peek, and panel are one continuous blue-black glass body.
- Light traces the shape through a delicate contour catch; it is not broad silver chrome.
- Quiet is near-monochrome; one warm amber event receives attention.
- State grouping makes “Needs you” precede “Working” and “Done.”
- The overlay narrates work in human language and never uses `/` or raw internals as the main title.
- Density is curated; the overlay is not an unbounded session table.
- Progressive disclosure preserves context.
- The morph has no visible crossfade, seam, topology break, fillet snap, or content flash.
- State is carried by shape/copy/semantics as well as color.
- Accessibility adaptations preserve hierarchy, meaning, and functional equivalence.
- “Premium” means restraint, precision, and coherence, not more blur, glow, capsules, or motion.

## Orchestration contract

The current task's root is the sole orchestrator. The root owns intent, canonical plan, ledger, task packets, fixture/capture matrix, diff and evidence inspection, pass/fail adjudication, integration, push, and cleanup.

For every bounded researcher, executor, or visual reviewer, spawn an isolated subagent with exactly:

```json
{
  "model": "opus5",
  "reasoning_effort": "medium",
  "fork_turns": "none"
}
```

Give each spawn a complete self-contained packet. If this exact route is rejected or unavailable, stop and report it; do not silently substitute a model or effort. Record only whether the requested route parameters were accepted—do not claim hidden runtime identity. Subagents may not redesign the root plan, spawn descendants, or coordinate laterally. Executors do not approve their own work. Visual reviewers do not implement. Root must inspect every diff and every asset rather than trusting an agent's completion message.

Use no more than the available root + three child slots. The mandatory first three parallel, read-only subagents are:

1. **Reference mapper:** map A–K DOM, CSS tokens, geometry, copy, interactions, JavaScript transitions, timings, and capture triggers to stable scenario IDs.
2. **Native mapper:** map each scenario and audit ledger item to current source symbols, fixtures, runtime triggers, accessibility behavior, and missing deterministic controls.
3. **Validation auditor:** inspect current capture/snapshot/Halo tooling and propose the smallest Poured-specific or safely generalized Gate 0 implementation, including unit calibration, registration, masks, artifact schema, and freshness checks.

Root integrates their evidence into plan version 1 before any write. Disagreements remain explicitly `unvalidated` until root resolves them from source or captures.

## Worktree and ownership contract

- One branch per worktree and one worktree per writing agent.
- No two agents write in the same checkout or share a branch.
- Create every implementation slice from the latest `origin/main`.
- Assign narrow, non-overlapping file ownership; never run parallel writes to shared source files.
- Reviewer checkouts are separate and read-only at the exact executor commit.
- Do not chain dependent feature branches. Integrate each accepted slice into `main`, push, then branch the next dependent slice from the new `origin/main`.
- Root alone updates/rebases, squash-merges, verifies integrated `main`, pushes, and cleans up.
- Preserve unexpected user changes. Stop on ambiguous overlap. Never use destructive Git operations to simplify integration.

Follow the repository's required commit workflow. Every meaningful modifying round ends in a focused conventional commit.

## Computer-use and visual-evidence requirement

Use the `computer-use` skill before UI edits to inspect the current app and reference, and use it again at every visual gate to operate and capture the actual UI. Follow the skill instructions exactly and report when it affects an action.

For repo-native live checks, refresh the development bundle from the exact candidate with:

```sh
zsh scripts/launch-dev-app.sh
```

Do not merely reopen a possibly stale installed app. Run `zsh scripts/setup-dev-signing.sh` before repeated TCC-sensitive checks when Accessibility, Automation, or precision jump behavior is involved. Record bundle/binary identity in the environment manifest.

## Mandatory kickoff: no visual edits before Gates 0A–0C

1. Establish the canonical environment fingerprint: commit/dirty state, source/fixture hashes, binary/build, macOS/hardware/GPU, display logical resolution, backing scale/DPR, profile, appearance/accent/a11y settings, locale/time format, browser/version/zoom/DPR, window bounds, backdrop hash, capture encoding, and bundle/signing identity.
2. Inventory the static board honestly and classify every A–K scenario as `rendered-canonical`, `rendered-motion-exemplar`, `specified-invariant`, `derived-validation`, or `platform-adaptation`. Materialize direct HTML fixtures only for states it actually renders. For all others, create a versioned behavior/fixture/adaptation manifest and deterministic driver, then obtain independent approval before treating it as acceptance authority.
3. Prove CSS px ↔ SwiftUI pt ↔ captured device-pixel mapping using neutral calibration assets.
4. Repeat at least five still captures per renderer and three repeated motion runs under the frozen fingerprint; quantify per-pixel/landmark noise, color variance, and timing jitter.
5. Have a non-implementing visual reviewer inspect and approve neutral assets, registration anchors, mask/exclusion rationale, antialiasing bands, and provisional thresholds before viewing candidates.
6. Version the calibration manifest, neutral artifacts, masks, and thresholds as one unit. A later revision invalidates prior comparisons, requires a written neutral-evidence rationale and independent approval, increments the version, and forces recapture. Never revise calibration in response to a candidate failure.
7. Capture every rendered-canonical HTML state and rendered CSS motion exemplar at 2×. Do not fabricate reference frames for stress, accessibility, reversal, or interaction states the board cannot drive.
8. Surface three reference conflicts: `PI-REF-001` (looping CSS versus settle-to-quiet prose), `PI-REF-002` (3.4 s cubic morph demo versus spring prose), and `PI-REF-003` (2.6 s infinite ease-out row demo versus “spring settle” label). The root, implementers, and reviewers must not choose the authority. Stop and obtain an explicit recorded product/design-owner ruling or updated canonical reference artifact. Only then encode it in a versioned behavior manifest/driver and ask an independent reviewer to validate fidelity to the ruling. Until then leave the affected behavior `blocked-unvalidated`; non-conflicting slices may proceed.
9. Build/restart and capture the unchanged native baseline at the same logical canvas, scale, backdrop, appearance, and crop. For derived/adaptation cases, bind the approved manifest and relevant rendered-canonical regions instead of a nonexistent direct HTML frame.
10. Produce registered full frames/crops, masks, side-by-sides, blinks, 50% overlays, diffs, heatmaps, and geometry/light/text reports where direct reference exists; produce manifest-linked native visual evidence for derived/adaptation cases.
11. Run a source survey that binds every `confirmed` ledger item to a reference selector/line, native file/symbol/line, and capture path where applicable. Use explicit `not-located` and `not-reproducible` outcomes; both mean `blocked-unvalidated`, not “missing.”
12. Populate the initial ledger with confidence and evidence paths.
13. Send the actual baseline assets/manifests to an independent Sol-medium visual reviewer and record `PASS`, `FAIL`, or `BLOCKED` for baseline adequacy—not native parity.

If any affected scenario is not deterministic or the renderers cannot be calibrated to the same logical geometry, stop and report `blocked-unvalidated`. Do not begin UI edits.

Store evidence under `artifacts/poured-parity/<native-commit>/<run-id>/` using the audit's manifest and artifact schema. Evidence is invalid if its commit, fixtures, environment, masks, or thresholds differ from the candidate.

## Canonical implementation order

Use this sequence unless current dependency evidence requires a change. Record and justify any adjustment before editing.

1. **Slice 0 — Validation foundation**
   - Deterministic scenarios, reference/native drivers, fingerprints, unit calibration, registration, masks, reports, ledger, freshness enforcement.
   - No visual redesign.

2. **Slice 1 — Session projection and identity**
   - Default state grouping/headers, stable attention-first ordering, display cap/overflow, workspace fallback, identity/disambiguation, and the 40-session stress case.
   - Principal IDs: `PI-C-001`, `PI-C-002`, `PI-C-003`, `PI-C-007`, `PI-V-001`.

3. **Slice 2 — Shell geometry and material**
   - Actual poured contour, shape-traced hairline/specular catch, blue-black fill, shadow, notch/center label, removal or reduction of the broad wash as the reference dictates.
   - Principal IDs: `PI-M-001`, `PI-M-002`, `PI-A-001`.

4. **Slice 3 — Collapsed, hover, and morph**
   - A, B, and affected K states: narrative/status cues, 0.15 s dwell, 1.03 hover, actionable peek, compressed overflow, animatable fillet/topology, one-material transition, reveal choreography, reversal.
   - Principal IDs: `PI-A-001`, `PI-B-001`, `PI-B-002`, `PI-B-003`.

5. **Slice 4 — Expanded list hierarchy**
   - C: shallow summary strip, grouped rows, compact narrative/metadata, density/rhythm, compact attention versus selected hero, and usage/chrome priority.
   - Principal IDs: `PI-C-004`, `PI-C-005`, `PI-C-006`, `PI-I-001`.

6. **Slice 5 — Detail, permission, questions**
   - D, E, F geometry, hierarchy, controls, focus, keyboard behavior, compact/hero transitions, and motion.
   - Principal blocker: close the applicable parts of `PI-X-001` and `PI-A11Y-001`.

7. **Slice 6 — Tasks, completion, usage, empty**
   - G, H, I, J hierarchy, task compression, completion outcome, usage thresholds, empty recovery, and non-conflicting motion. Do not prescribe the success lifecycle until `PI-REF-001` receives a product/design-owner ruling.

8. **Slice 7 — Motion and accessibility closure**
   - Full K transition matrix, cross-state choreography, rapid reversals, Reduce Motion/Transparency, Increase Contrast, VoiceOver, keyboard, appearance, and supported text sizes. Keep morph/row timing blocked until `PI-REF-002`/`003` receive product/design-owner rulings.

9. **Slice 8 — Integrated parity review**
   - Rebuild integrated `main`, recapture all A–K scenarios, run two fresh independent final visual reviewers, close the ledger, and retain useful conformance tooling.

## Exact per-slice loop

Run this loop for every coherent visual change, including correction rounds:

1. Root selects ledger IDs, scenarios, regions, expected differences, hard invariants, and applicable gates.
2. Root writes a complete executor packet and creates its branch/worktree from current `origin/main`.
3. Executor confirms scope, reads assigned source, implements only those IDs, runs targeted regression checks, and commits.
4. Root inspects the full diff and commit for scope, correctness, and unexpected changes.
5. Root builds/restarts the exact commit and captures the candidate in the frozen environment. It captures the direct HTML reference only for rendered states; otherwise it supplies the approved invariant/derived/adaptation manifest and related canonical reference regions. Every change still requires visual candidate evidence.
6. Root produces registered side-by-side, blink, overlay, diff/heatmap, silhouette/geometry/light/text reports, and 60 fps video/frame strips when shape, state, attention, reveal, or motion can be affected.
7. Root creates a separate read-only reviewer checkout at that commit and sends a fresh independent Sol-medium reviewer the full asset packet.
8. Reviewer directly inspects the assets at realtime, frame-step, and 0.25× where applicable and returns:
   - ledger IDs and scenarios reviewed;
   - evidence paths/hashes inspected;
   - visible mismatches by region and timestamp;
   - metric interpretation;
   - topology, material, content choreography, attention-flow, interaction, and accessibility verdicts as applicable;
   - one overall `PASS`, `FAIL`, or `BLOCKED`;
   - exact ledger-linked correction requests.
9. Root adjudicates. A visible reviewer mismatch fails even if tests and metrics pass. A metric miss remains open except for a proven `S4` platform variance.
10. On failure, send only ledger-backed corrections to the executor. Do not improvise unrelated fixes. Rebuild, recapture, and obtain fresh independent review.
11. When every affected gate passes, update from `origin/main`, squash-merge the slice into `main`, push, rebuild/verify integrated `main`, and remove its worktree/branch.
12. Start a dependent slice only from the newly pushed `origin/main`.

No implementer may approve their own pixels. No reviewer may pass without opening the visual assets. No threshold, mask, crop, backdrop, or golden may be changed to make a failed candidate pass. Native goldens become eligible only after cross-renderer parity approval.

## Comparison and acceptance requirements

Use the audit's static targets after Gate 0B freezes them: exact structure/copy/order/wraps; key geometry within 1 logical pixel; silhouette IoU ≥ 0.985; symmetric edge p95 ≤ 1 logical pixel/max ≤ 2 outside the antialiasing band; stable opaque ΔE2000 median ≤ 2/p95 ≤ 5; stable masked non-text SSIM ≥ 0.98; chrome-area ratio within 2%.

For motion capture at 60 fps or better, include explicit `t=0`, trigger, 10/25/50/75%, settled, extrema, reversal, and exit where the approved timeline defines them. Target landmark timing within one frame and key geometry within 2 logical pixels. Require event-order parity, continuous silhouette/material, no visible crossfade, notch/fillet snap, seam, content flash, or reversal discontinuity. Directly compare only CSS-rendered events. Treat 0.15 s hover dwell/1.03 scale and the conflicting spring/settle prose as specified invariants requiring an approved driver; do not pretend the static board can execute them.

These numeric checks screen evidence; they never override a visual `FAIL`.

## Stop conditions

Stop and report the evidence-backed blocker instead of improvising when:

- exact `gpt-5.6-sol` / `medium` / `none` routing is rejected or unavailable;
- the canonical integration worktree cannot be resolved;
- unexpected user changes overlap assigned files;
- a deterministic A–K scenario cannot be reproduced;
- HTML/native logical size, scale, or backdrop cannot be matched;
- the reference is ambiguous enough that the next action is a new design decision;
- an independent visual reviewer is unavailable;
- evidence is stale relative to the implementation commit;
- visual review fails despite passing tests or metrics;
- a requested correction has no ledger/scenario/region/acceptance mapping;
- integration would overwrite user work or require destructive Git operations.

Do not call ordinary difficulty, a failed first attempt, or incomplete parity a blocker. Iterate safely when evidence identifies a correction.

## Completion contract

Use exactly four outcome labels: `FULL PARITY` with no waivers; `PARITY WITH S4 WAIVER` when everything passes except independently approved renderer-only tolerances; `BLOCKED-UNVALIDATED` when required authority/evidence cannot be established; and `NOT YET PARITY` when reproducible requirements remain open or failing.

Do not claim `FULL PARITY` until:

- all A–K scenarios have valid evidence for their class: direct rendered comparison where the HTML actually renders the state, or an approved invariant/derived/adaptation authority plus baseline/final native visual evidence;
- every scenario passes structure, visual/material, copy/data, interaction/UX, and motion where applicable;
- the ledger has no `open`, `blocked-unvalidated`, `metric-fail`, or `review-fail` item;
- every S0–S3 issue is closed as `passed` and no issue is waived. A documented S4 platform-rendering tolerance may be waived only under the audit contract; if any exists, the highest outcome is `PARITY WITH S4 WAIVER`, and it remains visible in the ledger/final report with root and both-final-reviewer approval;
- normal and reduced-motion behavior are approved separately;
- every slice has an independent visual-review `PASS`;
- two fresh final reviewers pass the same integrated commit after inspecting the complete assets;
- regression checks pass as supporting evidence;
- integrated `main` is rebuilt, pushed, and clean;
- no unrelated UI change is included.

The final report must state:

- outcome: `FULL PARITY`, `PARITY WITH S4 WAIVER`, `BLOCKED-UNVALIDATED`, or `NOT YET PARITY`, using the definitions above;
- integrated commit and dirty state;
- ledger counts by severity and A–K state;
- scenario/gate coverage;
- artifact bundle paths and hashes;
- static and motion results;
- every independent reviewer disposition;
- interaction and accessibility results;
- build/test/lint results labeled `REGRESSION`, never parity proof;
- any narrowly approved S4 waiver;
- push, worktree, and branch-cleanup status;
- confirmation that no unrelated design change was included.

Begin with read-only discovery, the three required Sol-medium subagents, and Gates 0A–0C. Do not edit the overlay until the baseline evidence itself has passed review.

---
