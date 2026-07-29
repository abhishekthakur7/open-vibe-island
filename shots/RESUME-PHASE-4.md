# Resume prompt — overlay remediation, Phase 4

Copy everything below the line into a new chat window (run `/effort max` first).

---

You are resuming a multi-phase overlay visual-fidelity remediation on the Open Island macOS app.
Phases 0–3 are complete and committed. **Start at Phase 4 and run through Phase 8, then merge to
`main`.**

## Your role — orchestrator only

Binding, from the original brief (`shots/REMEDIATION-PROMPT.md`):

> **You (the main agent) orchestrate only.** You do not read source files to analyse them, you do
> not write product code, you do not run captures.

- **Every sub-agent is Sonnet 5 with high reasoning**: pass `model: "sonnet"` and `effort: "high"`
  on every `Agent` call. No exceptions.
- You may read: the plan document, sub-agent reports, and screenshots/diffs handed to you for a
  judgement call.
- Implementation agents run in parallel **only if their file sets are disjoint** — and note that
  concurrent agents cannot `swift build` in the same worktree, so in practice sequence them.
- **Capture/verification is a strictly serial resource** — one verification agent per phase.
- Sub-agent reports must be structured (tables/lists with `file:line` and measured numbers).

## Where everything is

| What | Path |
|---|---|
| **Worktree — all edits happen here** | `/Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation` (branch `fix/overlay-fidelity-remediation`, clean, off `main` @ `c5fbd53`) |
| **Main checkout — read-only reference** | `/Users/abhishekthakur/Developer/open-vibe-island` |
| **The plan — your source of truth** | `<worktree>/docs/design/overlay-redesign/REMEDIATION-PLAN.md` (1562 lines) |
| Governing brief | `/Users/abhishekthakur/Developer/open-vibe-island/shots/REMEDIATION-PROMPT.md` |
| Findings report | `.../shots/REPORT.md`, `.../shots/REPORT-ranked-verified.md` |
| Mockup boards + crops | `.../docs/design/overlay-redesign/*.html`, `.../shots/mockup/` |
| Baseline captures (⛔ never overwrite) | `.../shots/app/`, `.../shots/notch/` |
| New captures / evidence pairs | `.../shots/after/`, `.../shots/pairs-after/` |
| Shared sub-agent briefs (reuse these) | `<scratchpad>/IMPL-BRIEF.md`, `<scratchpad>/ANALYST-BRIEF.md` — **re-create them if the new session's scratchpad is empty**; their contents are summarised below |

`shots/` exists **only in the main checkout** — hand agents absolute paths to it. Do **not** symlink
it into the worktree (`.git/info/exclude` is shared across worktrees and would hide it from the
user's `git status`).

## State: what is already done

Three commits on `fix/overlay-fidelity-remediation`, working tree clean:

```
792d52d fix: overlay remediation Phase 3 — safety, semantics, and a Codex data bug
3c79521 feat: overlay remediation Phase 2 — theme + paginate the shared question view
b5afaac test: overlay remediation Phase 1 — verification infrastructure
c5fbd53 (main) feat: Halo — permission hero, question, notification card... (AB-345)
```

- **Phase 1** — verification infrastructure. 6/6 ACs, 24 live captures. Retired 2 of 5 known-red
  tests (the two Poured goldens were stale references predating Poured 2.0, not environmental
  drift — `CLAUDE.md` was corrected accordingly).
- **Phase 2** — F1/F1a/F1b: shared question view themed + paginated (per-theme page size:
  Poured/Halo `1`, Flight Deck `Int.max`). 7/9 criteria measured, 2 blocked by tooling.
- **Phase 3** — F3/F4/F5/F19/F20. **13/13 criteria PASS** via computer-use. Also fixed a
  production Codex data bug (`mergedRolloutMetadata`, `CodexSessionTracking.swift:803-816`) that
  F20 alone would not have surfaced.

Full suite at the Phase 3 commit: **929 tests, 4 issues, all `AppModelSessionListTests`** (known-red).

## Phase 4 — Flight Deck hero frame (start here)

Plan §4, line 1408. **Strict internal order — two of these are the same bug:**

1. **F2.3 placard** (plan `:636`) — 12pt / `.heavy` / tracking 1.44. Isolated, zero dependency;
   fixes MASTER WARNING **and** MASTER CAUTION in one edit.
2. **F2.4 Model + Branch** — same component as F2.3; combine to avoid re-measuring the header twice.
3. **F2.1 glow hoist** — the clip fix.
4. **F2.2 card fill re-tune** — **only after 2.1.** Tuning against today's glow-bleed-through
   baseline guarantees a second retune.
5. **F13 Transcript** (plan `:732`) — needs Phase 1's `.completedSuccess` fixture to be observable.
6. **F10 E3 CTA** (plan `:711`) — extract into an advisory-blue sub-panel **at the call site**,
   never by restyling `.ghost` globally.

**Facts the implementation agent must be handed:**

- The glow is clipped by the shared `.clipShape` around `openedSurfaceContent`
  (`IslandPanelView.swift:797` + `:815`). `closedAmbientGlow` (`:456-474`, wired at `:782`) is the
  **AB-330 precedent** for hoisting a glow outside that clip.
- `cardFill` is `alarm.opacity(0.08)` at `FlightDeckSessionRow.swift:2932-2934` and does **not**
  route through `FlightDeckSurfaces`. The excess brightness *is* the un-bled glow — same bug as
  F2.1, which is why 2.2 must follow 2.1.
- The mockup's `.codexbar` uses Flight Deck's own `statusCompleted` advisory-blue
  (`rgba(99,146,196,…)`), **not** neutral grey.
- `.ghost` has a second caller (`alwaysAllowOptions`) that must not change.
- ⚠️ FD has **no golden** for `permissionDiff`, `codexApproval`, or `completedVariants`, and **no
  topBar golden** for the permission/question heroes. Phase 4 relies on eye-check against the
  mockup for those.

## Remaining phases (plan §4)

- **Phase 5 — Layout** (`:1424`): F6 Poured `showsDetail` `else` branch · F9 FD annunciator strip ·
  F18→F8 FD gauges (that order) · F15 FD usage colours (atomic with its test, which pins the wrong
  values) · F7 notch usage lanes across **all six** themes (D2) · **NEW**: `emptyState` clipping on
  FD and Halo, found during Phase 1 verification.
- **Phase 6 — Type-scale hygiene** (`:1439`): the lint **first**, in seed/allowlist mode, as a
  Swift `@Test`; then F17 / F18 role registration / F11 / F11b / F19.
- **Phase 7 — Component unification** (`:1447`): `IslandDiffRenderer` + `IslandDiffStyle`; migration
  order fixture+component → Poured → Halo → **FD on `.chamfered(5)`, which resolves F14** →
  Annual/Instrument → keep the legacy `PermissionDiffPreview` (D2). Then **F16**, one Poured button
  contract.
- **Phase 8 — Full-matrix recapture + SPEC audit** (`:1454`): 3×15 matrix via the Phase 1 script ·
  computer-use for motion (§K), hover-peek (§B), expand/collapse morph, focus rings, pressed states ·
  add a **"shipped" column** to the FD and Halo typography tables.

## Per-phase verification protocol (plan §6, `:1504`) — non-negotiable

1. **One** verification agent per phase (capture is serial). It gets: the acceptance criteria,
   frames to capture, mockup crops, the scale rule, the surface-scope table, known artifacts.
2. Re-capture affected frames in **all three themes** where the change is shared. Report PASS/FAIL
   **per criterion, with numbers**.
3. Motion / hover / morph / focus / pressed → **computer-use** (the `orca` CLI). Stills can't settle them.
4. **Any FAIL means the phase is not done.** Dispatch a fix agent with the measurement, re-verify, loop.
5. For every MAJOR fix, a second **adversarial verifier** tries to REFUTE the pass, defaulting to
   REFUTED when uncertain. This has caught real mistakes.
6. Evidence pairs → `shots/pairs-after/`; new captures → `shots/after/`.
7. Update the plan's §7 status table (`:1528`) before starting the next phase.

**A phase is not done because the code compiles — it is done when the pixels match.**

## Operational facts every agent needs

**Build:**
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # CLT default lacks the SwiftUI macro plugin
cd /Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation
swift build
```
**ModuleCache gotcha** — if the first build fails with `precompiled file … was compiled with module
cache path …/open-vibe-island/.build/… but the path is currently …/worktrees/…`, that is a path
baked into the APFS-cloned `.build`, **not a code bug**:
```bash
rm -rf .build/arm64-apple-macosx/debug/ModuleCache .build/arm64-apple-macosx/release/ModuleCache
```
Never `rm -rf .build` wholesale (~5 min cold rebuild).

**Tests:** agents run only their assigned `--filter`. The orchestrator runs the full suite **once
per phase**. Known-red baseline: 3–6 failures across `AppModelSessionListTests`
(`activeAppearanceProfile` bucket race — diagnosed, fix pattern known, deliberately out of scope)
plus intermittent `cellStateReflectsSessionPhase` /
`bulkFirstObservationOrdersByHistoricalFirstSeenAt`. Anything else is the agent's to fix.

**Snapshots:** `Tests/OpenIslandAppTests/__Snapshots__/<TestClass>/<method>.<name>.png`, rendered
**@2x unconditionally**. `OPEN_ISLAND_RECORD_SNAPSHOTS=1` is a per-call default parameter, so
`--filter` genuinely scopes recording. **Never blanket-re-record.** Predict which goldens will move
from the **fixture → scenario → golden chain**, not from the motivating finding — a Phase 1
prediction of 15 came out at 19 for exactly that reason. If a golden outside the predicted list
moves, stop and investigate.

**Scale rule (the #1 source of false findings):** app captures are **@2x** (1px = 0.5pt); mockup
crops are **@1x** (1px = 1pt). **Halve every app pixel measurement before comparing.**

**Colour space:** captures are **Display-P3**. Convert before comparing to sRGB token values —
Phase 3 sampled `(244,180,96)` raw, which is *exactly* `(255,177,77)` sRGB. A naive comparison
would have reported a false FAIL.

**Surface-scope trap:** `IslandDebugScenario.swift:108-300` renders **two** surfaces — the
notification card (`notchOpenReason:.notification` + `islandSurface:.sessionList(actionableSessionID:)`)
and the plain session list (`.click`). Mockup **§H/§D depict the EXPANDED ROW**, a third surface.
Comparing a notification card against §H produces false "missing action" findings. Every claim must
state which surface it applies to.

**Focus:** the overlay is a `.nonactivatingPanel` and only calls `makeKeyAndOrderFront` when
`notchOpenReason == .click`. Notification-opened cards deliberately don't steal key focus — send one
synthetic click on a neutral element before sending keys.

**Three structural blind spots in the snapshot harness** (discovered in Phases 1–3 — do not assume
snapshot coverage exists for these):
1. Halo `.accessibilityElement(children: .ignore)` (`HaloSessionRow.swift:206-208`) — the AX tree is
   blind to row detail.
2. `ThemeSnapshotting.swift:507` hardcodes `keyboardCoordinator: nil` — **no** snapshot can render
   the keyboard hint, in any theme.
3. The `.closedPill` harness slot renders `V6ClosedPill` directly and never dispatches through
   `\.islandTheme` — **no** snapshot can verify the closed-pill glyph seam.

## ⛔ Hard guardrails

- **Never edit the main worktree.**
- `zsh scripts/launch-dev-app.sh` must be run from the **worktree's own copy** (it derives repo root
  from its own location) and **`--skip-setup` is mandatory** — without it `OpenIslandSetup install`
  rewrites the user's real agent hook configs.
- **Do NOT change the real hooks-installed probe** — only the harness override.
- **Never** write to or overwrite `shots/app/` or `shots/notch/` — immutable baselines.
- **Do NOT** use `scripts/replay-bridge-scenarios.py` — a live production `/Applications/Open Island.app`
  owns the single bridge socket and the app ignores `OPEN_ISLAND_SOCKET_PATH`; it would drive the
  user's real app.
- Never `git reset --hard`, force-push, or overwrite user changes without explicit approval.
- Sub-agents **do not commit**, never `git add -A`, never `git stash`. The orchestrator commits
  after verification — one commit per phase.
- The plan's **§1 out-of-scope / DO-NOT-FIX table** (`:67`) is binding. Hand it to every agent.

## Cleanup, every session

```bash
pkill -9 -f OpenIslandApp
defaults write <app-domain> appearance.island.v8.theme -string halo
defaults write <app-domain> overlay.display.preference -string F3BDCAC0-1700-415E-817D-AC4E69D405BC
```
(Exact domain is in plan §0, `:59`.)

## Finishing

After Phase 8 verifies green: run the **full** suite plus `swift build` as the merge gate, then
squash-merge `fix/overlay-fidelity-remediation` to `main` with a conventional commit — the user has
authorised the merge. **Ask before pushing to `origin`.** Then remove the worktree and branch.

## Start now

Mark Phase 4 in progress and dispatch the Phase 4 implementation agent (Sonnet 5, high effort) with
the strict F2.3 → F2.4 → F2.1 → F2.2 → F13 → F10 order and the facts above. Read plan `:636-760`
and `:1408-1422` yourself first — that is the one file you are allowed to read.
