PROMPT — Remediate the overlay visual-fidelity findings (plan-first, phase-gated, sub-agent driven)

Paste this whole file as the first message in a fresh Claude Code chat opened in
/Users/abhishekthakur/Developer/open-vibe-island. It is a self-contained brief with the
operational playbook baked in. Everything below was learned the hard way in the review session
that produced these findings — do not rediscover it.

═══════════════════════════════════════════════════════════════════════════════
MISSION
═══════════════════════════════════════════════════════════════════════════════

A pixel-level visual-fidelity review compared the three shipped overlay themes (Poured Island 2.0,
Flight Deck 2.0, Halo) against their approved high-fidelity mockup boards. Every finding was put
through an adversarial verifier that defaulted to REFUTED. The surviving findings are in
`shots/REPORT.md`.

Your job: **fix them.** Specifically —

1. FIRST produce a **plan document** with detailed analysis and phase-wise fixes. Do not write
   product code until the plan exists and the user has approved it.
2. THEN execute the phases one at a time. After each phase, **re-capture the affected frames and
   verify against the mockups**. If a phase's output does not match the mockup, fix it within that
   phase before moving on. A phase is not done because the code compiles — it is done when the
   pixels match.
3. Use **computer-use** (the `computer-use` skill, `orca` CLI) plus the harness and mockup-render
   tooling described below to do that verification.

═══════════════════════════════════════════════════════════════════════════════
ORCHESTRATION MODEL (binding)
═══════════════════════════════════════════════════════════════════════════════

- **You (the main agent) orchestrate only.** You do not read source files to analyse them, you do
  not write product code, you do not run captures. You dispatch sub-agents, read their structured
  reports, decide what happens next, and keep the plan document current.
- **Every sub-agent is Sonnet 5 with high reasoning**: pass `model: "sonnet"` and `effort: "high"`
  on every `Agent` call. No exceptions.
- **You may read**: the plan document, sub-agent reports, and screenshots/diffs handed back to you
  for a judgement call. Looking at an image to decide "does this match the mockup" is orchestration,
  not implementation — do that yourself when a sub-agent's verdict needs adjudicating.
- **Parallelism rules**:
  - Implementation agents may run in parallel **only if their file sets are disjoint**. State the
    file set for each in its prompt and enforce it. Two agents editing `PouredSessionRow.swift`
    concurrently will corrupt the work.
  - **Capture/verification is a strictly serial resource.** There is one overlay panel, one
    `defaults` theme key, one dev-app bundle. Never run two capture agents at once. Dispatch one
    verification agent per phase and wait for it.
  - Analysis/exploration agents (read-only) may always run in parallel.
- **Sub-agent reports must be structured** (tables/lists with file:line and measured numbers), not
  prose, so you can merge them without context bloat.

═══════════════════════════════════════════════════════════════════════════════
DELIVERABLE 1 — THE PLAN DOCUMENT
═══════════════════════════════════════════════════════════════════════════════

Write it to `docs/design/overlay-redesign/REMEDIATION-PLAN.md`.

Build it by dispatching read-only analysis sub-agents (parallel, disjoint areas) to answer the
questions below, then synthesising. Do not guess at any of it.

The plan must contain:

**A. Per-finding analysis.** For each finding in `shots/REPORT.md`:
   - the exact current behaviour with file:line,
   - the exact target behaviour with the mockup element it must match,
   - **root cause** (several findings share one — say so),
   - blast radius: what else touches this code (use `codegraph_explore` — the repo is CodeGraph-
     indexed; one call beats a grep/read loop),
   - risk of regression and which existing tests cover it,
   - a measurable **acceptance criterion** (see "Acceptance criteria" below).

**B. Shared-root-cause consolidation.** Several findings collapse into one fix. Identify these
   explicitly — the plan should not create N tickets where one change closes N findings. Known
   examples to confirm: the unthemed shared question view underlies findings across all three
   themes; `splitUsageProviders` is triplicated verbatim; there are three forked diff renderers.

**C. Phase breakdown**, ordered by dependency, not by severity. **Verification infrastructure
   comes first** — see the proposed phasing below and refine it.

**D. Per-phase verification protocol**: which frames to re-capture, which mockup crops to compare
   against, which specific measurement decides pass/fail, and how motion/hover states (which stills
   cannot show) will be checked via computer-use.

**E. Sequencing/merge plan** consistent with the repo's ticket-execution protocol (see below).

**F. Explicit out-of-scope list**, copied from the DO-NOT-FIX section below.

Present the plan to the user for approval before Phase 1 implementation. Use `ExitPlanMode`.

═══════════════════════════════════════════════════════════════════════════════
⛔ DO NOT "FIX" THESE — they were investigated and are correct as-is
═══════════════════════════════════════════════════════════════════════════════

This list exists because a naive reading of the findings would break working behaviour. Put it in
the plan document verbatim and make every implementation sub-agent read it.

| Apparent problem | Reality |
|---|---|
| Completion card has no **Dismiss** | Deliberate. `notificationRowActions` (`IslandPanelView.swift:937-945`) omits `dismiss:` with an explicit comment — the notification card isn't dismissible. Row wiring is correct and is handed `nil` on this surface. **Do not add a Dismiss button here.** |
| Completion card has no **Reply** | Feature flag `model.completionReplyEnabled`, default `false` (`AppModel.swift:298,758`), matching BRIEF §6 "narrow support". Not a rendering bug. |
| Halo/Poured completion card has no **Transcript** | Fixture gap — no fixture sets `transcriptPath`. The code path is untested, not broken. (Flight Deck's *is* a real gap — see finding 13.) |
| Poured's A3 attention glyph "is malformed" (2 bars, no dot) | REFUTED. Matches `UnifiedBars(mode:.waiting)` exactly — the capture legitimately shows **A4 question**, not A3 permission. Poured's ringed dot is fine. |
| Halo's Failed outcome "uses a different template" | Fixture bug, not a template bug. `completedFailed.updatedAt` is 9 min old, exceeding the 5-min stale threshold → `presence:.inactive` → idle template. **Fix the fixture, not the badge/dot code.** |
| Halo session list "missing section headers" | User setting: `appearance.island.v8.notch.sessionGroup = none`. |
| Attention pills have a "huge banded glow" | REFUTED by measurement. Bleed is within spec (Poured 5.0pt, FD 1.5pt, Halo 9.5pt). The apparent drama is the harness capturing against pure black vs the mockup's grey desktop. |
| Halo's row edge-rail "is missing" | Present at 2.0pt with the correct cyan→violet gradient, correctly gated to live/actionable rows. |
| Flight Deck hero "drops the whole identity block" | Partly refuted — the agent name IS rendered, relocated above the card (defensible). Only **Model and Branch** are genuinely absent. Fix only those. |
| Notch vs top-bar metric differences (pill 38↔24pt, panel 540↔520pt, insets 46↔16pt, usage ring 30↔22pt) | SPEC-sanctioned. Not defects. |
| Flight Deck's flat/opaque body, no gradients, no specular | **Correct by design** (tintOpacity 1.0). Its signature is phosphor glow bleed on lamps. Do not add gradients. |
| Halo's pure-black void, no fills/cards/vibrancy | **Correct by design.** Its only chrome is the 1.5pt edge-light. Do not add card fills. |

Only **Poured** owes layered glass (3-stop body gradient + two specular layers + inner hairline),
and it already has it — verified present and smooth.

═══════════════════════════════════════════════════════════════════════════════
PROPOSED PHASING (refine in the plan, but keep Phase 1 first)
═══════════════════════════════════════════════════════════════════════════════

**Phase 1 — Verification infrastructure. Must come first: without it, later phases cannot be
verified at all.**
- Add harness scenarios that drive the **expanded row** (§D detail, §G engine cluster + task list)
  and the **§I full usage-meter card**. Today `subagentsCard` has no `actionableSessionID` so the
  row never expands, and `usageMeters` only injects fixtures into the header lane — so §D/§G/§I
  **cannot currently be regression-tested**. (`IslandDebugScenario.swift:108-300`)
- Fix `AppearancePreviewFixtures.completedFailed.updatedAt` (exceeds the stale threshold and masks
  the failed-outcome template).
- Fix `AppearancePreviewFixtures.stableID` truncating seeds to 16 bytes → colliding UUIDs, which
  makes every multi-question option render as option[0]/digit "1".
- Give a fixture a `transcriptPath` so the Transcript affordance becomes testable.
- Add a way to suppress the install-hint banner under the harness (it clips `poured-emptyState`,
  `poured-completedFailed`, `flightDeck-emptyState`, `halo-emptyState`). A harness env var is fine;
  **do not** change the real hooks-installed probe.

**Phase 2 — Shared views (one fix, closes findings in all three themes).**
- Theme `StructuredQuestionPromptView`'s interior via an injection point (mirror how `sessionRow` is
  themed through `\.islandTheme`), and consume each theme's already-defined `questionText` /
  `optionLabel` / `optionDesc` / `optionNumber` roles.
- Add **question pagination** — it has no pagination state at all today; a `ForEach` stacks every
  question in one `VStack`/`ScrollView`.
- Fix the persistent hollow radio circle on unselected options (mockup shows a control only on the
  selected row).
  Files: `Sources/OpenIslandApp/Views/IslandPanelView.swift:2290-2481, 2953-2985`

**Phase 3 — Safety and semantics (small, high-value, low-risk).**
- Flight Deck Allow/Deny **order** → Allow before Deny (`FlightDeckSessionRow.swift:2804`).
- Halo diff **`+`/`−` markers** (`HaloSessionRow.swift:2186`) — currently colour-only, violating
  BRIEF §5.
- Halo `closedGlyphTint` override in `HaloTheme.swift` (the glyph falls back to achromatic paper
  because Halo never overrides the hook; its correct cyan/gold/amber logic in `HaloClosedPill.swift`
  is dead code in the normal render path), and add a **permission case to `UnifiedBars.Mode`** so
  Halo's A3 ringed-dot shape becomes reachable.

**Phase 4 — Flight Deck hero frame (the "must feel like an EVENT" bar).**
Glow bleed on the hero card · card fill #682E27 → #231718 · MASTER placard → 12/800/0.12em ·
Model + Branch reachable (incl. VoiceOver) · E3 CTA extracted into its own neutral sub-panel.

**Phase 5 — Layout.**
Poured `showsDetail` gate (`PouredSessionRow.swift:116`) · FD annunciator strip tile size ·
notch usage-lane split + the provider-dropping fallback · FD gauge header overflow.

**Phase 6 — Type-scale hygiene.**
`monoChip`/`sideBadge` · Poured hero button role · FD `count` sub-roles · FD 9pt `%` ·
Halo `nestHeader` weight · extend FD `roleFamilies`/`readableRoleSizes` (or lint-fail inline
`.system(size:` outside the theme file) — this is the structural root cause of several findings.

**Phase 7 — Component unification.**
Unify the three diff renderers behind one metric set + marker contract · FD chamfer-native diff (no
`RoundedRectangle(r7)` nested in a `chamfer:5` well) · Poured button family onto one contract.

**Phase 8 — Full-matrix re-capture + motion/hover verification via computer-use, and a
SPEC-conformance-marker audit** (`SPEC-flight-deck.md:158` marks the placard ✅ while the code
ships 10.5/700 — the ✅ markers are not a trustworthy record; audit them all).

═══════════════════════════════════════════════════════════════════════════════
ACCEPTANCE CRITERIA — how a phase passes
═══════════════════════════════════════════════════════════════════════════════

Each finding needs a criterion a verification agent can mechanically check. Prefer measurements
over impressions. Examples of the right shape:

- FD hero card fill samples within ΔE ≤ 8 of `#231718`; beacon/card luminance ratio ≥ 2.4.
- FD hero card edge shows a ≥ 6px alpha transition (today: 0px).
- MASTER placard cap-height ≥ the kicker's cap-height beside it.
- Halo diff: a `+` or `−` glyph is present on every added/removed row, in a dedicated column,
  and the row is still distinguishable with colour removed (desaturate the crop and re-check).
- FD approval buttons: leftmost button's accessibility label is the Allow action.
- Poured session list: ≥ 5 session rows visible in the default panel height; collapsed row pitch
  within 86–98pt of the mockup.
- Halo closed pill: running glyph sampled hue is cyan-family, not R=G=B.
- No readable text role renders below 10pt (assert via the theme's `readableRoleSizes` test).

**Every measurement must respect the scale rule below.**

═══════════════════════════════════════════════════════════════════════════════
OPERATIONAL PLAYBOOK (reuse verbatim — hard-won, do not rediscover)
═══════════════════════════════════════════════════════════════════════════════

── Scale rule (the #1 source of false findings) ────────────────────────────────
App captures are **@2x** (1px = 0.5pt). Mockup crops are **@1x** (1px = 1pt). **Halve every app
pixel measurement before comparing.** State this in every verification sub-agent's prompt.

── Build & toolchain ───────────────────────────────────────────────────────────
Always prefix Swift with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` — the
CLT default lacks the SwiftUI macro plugin and fails inside the NetworkImage dependency.

**Never edit the main worktree.** Create one worktree for this effort via
`zsh scripts/agent-worktree.sh <branch>` (it branches off latest `origin/main` and APFS-clones
`.build`, skipping the ~5-min cold build). Run all phases in that one worktree, sequentially —
the dev-app bundle is built from the working directory, so the capture agent must run where the
fixes are.

Test scoping: during development `swift test --filter <touched suites>`. Run the **full suite
exactly once per phase**, before that phase's commit.

**Known-red tests — pre-existing, do NOT chase.** Confirm the count is unchanged and move on:
`islandSessionSectionsGroupStaleCompletedIntoIdle`,
`islandSessionSectionsKeepCompletedInDoneWhenStaleThresholdIsNever`,
`islandSessionListCanSortByLastUpdate`, `cellStateReflectsSessionPhase`,
`bulkFirstObservationOrdersByHistoricalFirstSeenAt`; plus two Poured session-list snapshot goldens
that drift environmentally — if they fail, verify they also fail on clean HEAD.
⚠️ Phase 1 changes fixtures, so some snapshot goldens will legitimately change. Re-record
deliberately with `OPEN_ISLAND_RECORD_SNAPSHOTS=1`, **`--filter`ed to the snapshot suite only**,
and review the diff — never blanket-re-record.

── Deterministic app capture (THE reliable path) ───────────────────────────────
Build/refresh the dev bundle with `zsh scripts/launch-dev-app.sh --skip-setup`
(never `open -na` — the bundle goes stale). Then run the bundled binary directly:

```bash
BIN="$HOME/Applications/Open Island Dev.app/Contents/MacOS/OpenIslandApp"
defaults write app.openisland.dev "appearance.island.v8.theme" -string "poured"   # or flightDeck / halo
adir=$(mktemp -d)
OPEN_ISLAND_HARNESS_SCENARIO=diffApprovalCard \
OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1 \
OPEN_ISLAND_HARNESS_START_BRIDGE=0 \
OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 \
OPEN_ISLAND_HARNESS_CAPTURE_DELAY_SECONDS=1.5 \
OPEN_ISLAND_HARNESS_AUTO_EXIT_SECONDS=3 \
OPEN_ISLAND_HARNESS_ARTIFACT_DIR="$adir" "$BIN" >/dev/null 2>&1
cp "$adir/overlay.png" shots/after/<theme>-<scenario>.png     # + overlay.ax.json for label text
```
`pkill -9 -f OpenIslandApp` between theme switches; verify the PID changed.

Scenarios: `closed · closedAttention · sessionList · approvalCard · questionCard · completionCard ·
longCompletionCard · diffApprovalCard · codexApprovalCard · multiQuestionCard · subagentsCard ·
completedInterrupted · completedFailed · usageMeters · emptyState` (+ whatever Phase 1 adds).

**Forced notch-mode capture** (this Mac's main display is an external 4K, so the harness defaults
to top-bar and the notch design surface — split usage lanes around the cutout — would never be
reviewed). Built-in display UUID: `37D8832A-2D66-02CA-B9F7-8F30A301B230`.
```bash
defaults write app.openisland.dev "overlay.display.preference" -string "37D8832A-2D66-02CA-B9F7-8F30A301B230"
# ... capture ...
defaults write app.openisland.dev "overlay.display.preference" -string "F3BDCAC0-1700-415E-817D-AC4E69D405BC"  # RESTORE
```
Confirm notch mode by panel width: 540pt (notch) vs 520pt (top-bar).

── Rendering the mockups ───────────────────────────────────────────────────────
Boards: `docs/design/overlay-redesign/{01-poured-island,02-flight-deck,06-halo}.html`.
Use the `playwright-cli` skill with `run-code --filename=<script>`. Gotchas that cost time:
- the script must be a **bare async arrow function expression** (`async page => { … }`) — not
  `module.exports = …`, and no trailing semicolon;
- **no Node APIs** — `require`/`fs` are unavailable; `mkdir` the output dir from the shell first.
- Frames are `.frame` elements labelled by an inner `.fid` span; sections are `section` with an
  inner `.id` span; **Flight Deck puts several scenarios in `.board` containers instead of
  `.frame`**, so screenshot all three selector families or you will silently miss §C/§D/§G/§H/§J/§K.
- 104 baseline mockup crops already exist in `shots/mockup/` — reuse them, don't re-render.

── computer-use (for what stills cannot show) ──────────────────────────────────
Load the `computer-use` skill; CLI is `orca`. `orca computer get-app-state --app app.openisland.dev
--json` returns a screenshot path + AX tree. Permissions are already granted.
⚠️ One-time: run `zsh scripts/setup-dev-signing.sh` if AX-dependent behaviour misbehaves — without
it every rebuild changes the cdhash and silently invalidates TCC grants.
Use computer-use for: **hover-peek (§B), the expand/collapse morph, motion identity (§K), hover-
reveal affordances, focus rings, pressed states** — none of which a harness still can show. Screen-
record or capture successive frames where a single still cannot settle it.
AX/computer-use JSON often contains control chars → parse with `json.loads(s, strict=False)`.

── ⚠️ The surface-scope trap (this invalidated several original findings) ──────
`IslandDebugScenario.swift:108-300` renders **two different surfaces**:
- **Notification card** (`notchOpenReason: .notification` + `islandSurface: .sessionList(
  actionableSessionID:)`) — the compact auto-surfaced card. Used by `approvalCard`, `questionCard`,
  `completionCard`, `longCompletionCard`, `diffApprovalCard`, `codexApprovalCard`,
  `multiQuestionCard`, `completedInterrupted`, `completedFailed`.
- **Plain session list** (`notchOpenReason: .click` + `islandSurface: .sessionList()`) — used by
  `sessionList`, `subagentsCard`, `usageMeters`.

Mockup §H/§D depict the **expanded row**, a third surface. Comparing a notification card against
§H produces false "missing action" findings — that is exactly what happened. **Always state which
surface a capture shows before comparing it to a mockup frame.**

── Known artifacts — never file, never "fix" ───────────────────────────────────
- Install-hint banner ("No agent hooks installed — SETUP"): the bundled binary's hooks probe reads
  false. Harness artifact. It clips short panels (see Phase 1).
- `appearance.island.v8.notch.sessionGroup = none` is the user's setting, not a bug.

═══════════════════════════════════════════════════════════════════════════════
PER-PHASE VERIFICATION LOOP (the core of this job)
═══════════════════════════════════════════════════════════════════════════════

For each phase, after implementation agents report done:

1. Dispatch **one** verification sub-agent (serial — single overlay resource). Give it: the phase's
   acceptance criteria, the frames to capture, the mockup crops to compare against, the scale rule,
   the surface-scope warning, and the known-artifacts list.
2. It re-captures the affected frames (all three themes where the change is shared), measures each
   acceptance criterion, and reports PASS/FAIL per criterion **with numbers**.
3. Where stills cannot decide (motion, hover, morph, focus), it drives the live app via
   computer-use.
4. **If any criterion FAILS, the phase is not done.** Dispatch a fix agent with the measurement,
   and re-verify. Loop until green. Do not carry a failure into the next phase.
5. For every MAJOR fix, dispatch a second **adversarial verifier** that tries to REFUTE the pass —
   defaulting to REFUTED when uncertain. This caught real mistakes in the review session (wrong
   file cited, wrong frame measured, an "artifact" that was actually correct behaviour).
6. Keep a before/after evidence pair per finding in `shots/pairs-after/`. Baseline "before"
   captures already exist in `shots/app/` and `shots/notch/` — **do not overwrite them**; write new
   captures to `shots/after/`.
7. Update the plan document's status table before starting the next phase.

═══════════════════════════════════════════════════════════════════════════════
COMMIT / MERGE PROTOCOL
═══════════════════════════════════════════════════════════════════════════════

- Conventional commit messages (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`). Never `--amend`
  unless asked. One coherent commit per phase.
- **Changes land by direct squash-merge to `main` — no PRs.** From the main checkout:
  `git merge --squash <branch>`, commit, push `origin main`.
- The **local full suite + `swift build`** is the merge gate; the GitHub CI workflow is disabled.
- Never `git reset --hard`, force-push, or overwrite user changes without explicit approval.
- After merging, run `swift build` in the main checkout so the next worktree seeds a warm cache.
- **Ask before pushing.** Do not push to `main` without confirming with the user.

═══════════════════════════════════════════════════════════════════════════════
CLEANUP OBLIGATIONS (every session, every phase)
═══════════════════════════════════════════════════════════════════════════════

- `pkill -9 -f OpenIslandApp`; `playwright-cli close-all`.
- Restore `appearance.island.v8.theme` → **`halo`** (the user's selection).
- Restore `overlay.display.preference` → **`F3BDCAC0-1700-415E-817D-AC4E69D405BC`**.
- Remove the worktree and branch once merged.

═══════════════════════════════════════════════════════════════════════════════
INPUTS ALREADY ON DISK — READ THESE FIRST, DO NOT REDO THEM
═══════════════════════════════════════════════════════════════════════════════

| What | Path |
|---|---|
| **The findings report (start here)** | `shots/REPORT.md` |
| Methodology, capture pipeline, coverage caveats | `shots/REPORT-methodology.md` |
| Ranked verified findings w/ file:line + tickets | `shots/REPORT-ranked-verified.md` |
| Appendix A — type-scale audit | `shots/audit-type-scale.md` |
| Appendix B — component audit | `shots/audit-components.md` |
| Raw per-theme critiques | `shots/critique-{poured,flightdeck,halo}.md` |
| Coordinator findings + verifier corrections | `shots/findings-coordinator.md` |
| **Per-theme measuring rulers** (type scale, component metrics, fidelity bar) | `shots/rulers/ruler-{poured,flightdeck,halo}.md` |
| Baseline app captures (top-bar, 45) | `shots/app/` |
| Baseline app captures (notch, 15) | `shots/notch/` |
| Mockup crops (104, full §A–§K) | `shots/mockup/` |
| Existing before/after evidence pairs | `shots/pairs/` |
| Authority docs | `docs/design/overlay-redesign/BRIEF.md` (§2 metrics, §7 fidelity bar), `SPEC-{poured-island,flight-deck,halo}.md` |

The **rulers** are the measuring instrument — each carries the theme's exact type scale, component
metrics, slot→Swift type map, its theme-specific fidelity bar, and known SPEC-vs-code drift. Give
the relevant ruler to every implementation and verification sub-agent.

⚠️ The SPEC files' ✅ conformance markers are **not trustworthy** — at least one
(`SPEC-flight-deck.md:158`) asserts conformance the code does not have. Verify against code, not
against the checkmark.

═══════════════════════════════════════════════════════════════════════════════
START HERE
═══════════════════════════════════════════════════════════════════════════════

1. Read `shots/REPORT.md` yourself (orchestrator context).
2. Create the worktree.
3. Dispatch parallel read-only analysis sub-agents (Sonnet 5, high effort) to produce the per-
   finding analysis in section A above. Use `codegraph_explore` for blast radius.
4. Synthesise `docs/design/overlay-redesign/REMEDIATION-PLAN.md`.
5. Present it via `ExitPlanMode` for approval.
6. Execute phases with the verification loop. Do not skip the loop, and do not let a phase pass on
   "it compiles".
