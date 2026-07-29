# Shared implementation brief — overlay visual-fidelity remediation

You are an **implementation agent**. Read this whole file before touching code.

## Where you work

| What | Path |
|---|---|
| **Worktree — ALL edits happen here** | `/Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation` (branch `fix/overlay-fidelity-remediation`) |
| Main checkout — **read-only reference, NEVER edit** | `/Users/abhishekthakur/Developer/open-vibe-island` |
| The plan — your source of truth | `<worktree>/docs/design/overlay-redesign/REMEDIATION-PLAN.md` |
| Mockup boards | `<worktree>/docs/design/overlay-redesign/*.html` |
| Mockup crops | `/Users/abhishekthakur/Developer/open-vibe-island/shots/mockup/` |
| Baseline captures (⛔ never overwrite) | `/Users/abhishekthakur/Developer/open-vibe-island/shots/app/`, `.../shots/notch/` |

`shots/` exists **only in the main checkout** — use absolute paths. Do **not** symlink it into the
worktree (`.git/info/exclude` is shared across worktrees and would hide it from the user's git status).

## Build

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # CLT default lacks the SwiftUI macro plugin
cd /Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation
swift build
```

**ModuleCache gotcha** — if the first build fails with `precompiled file … was compiled with module
cache path …/open-vibe-island/.build/… but the path is currently …/worktrees/…`, that is a path baked
into the APFS-cloned `.build`, **not a code bug**:

```bash
rm -rf .build/arm64-apple-macosx/debug/ModuleCache .build/arm64-apple-macosx/release/ModuleCache
```

**Never `rm -rf .build` wholesale** (~5 min cold rebuild).

## Tests

- Run **only your assigned `--filter`**. The orchestrator runs the full suite once per phase.
- **Known-red baseline** (pre-existing, do NOT chase): 3–6 failures across `AppModelSessionListTests`
  (`activeAppearanceProfile` bucket race — diagnosed, deliberately out of scope), plus intermittent
  `cellStateReflectsSessionPhase` and `bulkFirstObservationOrdersByHistoricalFirstSeenAt`.
  **Anything else that fails is yours to fix.**

## Snapshots

- Path: `Tests/OpenIslandAppTests/__Snapshots__/<TestClass>/<method>.<name>.png`, rendered **@2x unconditionally**.
- `OPEN_ISLAND_RECORD_SNAPSHOTS=1` is a **per-call default parameter**, so `--filter` genuinely scopes recording.
- **Never blanket-re-record.** Before recording, *predict* which goldens will move by tracing the
  **fixture → scenario → golden** chain — not from the motivating finding. (A Phase 1 prediction of 15
  came out at 19 for exactly that reason.)
- **If a golden outside your predicted list moves, STOP and investigate.** Report it; do not re-record it blindly.

## Scale rule (the #1 source of false findings)

App captures are **@2x** (1px = 0.5pt). Mockup crops are **@1x** (1px = 1pt).
**Halve every app pixel measurement before comparing.**

## Colour space

Captures are **Display-P3**. Convert before comparing to sRGB token values. Phase 3 sampled
(244,180,96) raw, which is exactly (255,177,77) sRGB — a naive comparison reports a false FAIL.

## Surface-scope trap

`IslandDebugScenario.swift:108-300` renders **two** surfaces:

| Surface | Config | Scenarios |
|---|---|---|
| Notification card | `notchOpenReason:.notification` + `islandSurface:.sessionList(actionableSessionID:)` | `approvalCard`, `questionCard`, `completionCard`, `longCompletionCard`, `diffApprovalCard`, `codexApprovalCard`, `multiQuestionCard`, `completedInterrupted`, `completedFailed` |
| Plain session list | `notchOpenReason:.click` + `islandSurface:.sessionList()` | `sessionList`, `subagentsCard`, `usageMeters` |
| **Expanded row** (mockup §D/§H, §G) | a **third** surface | Phase 1 added reachability |

Mockup §H/§D depict the **EXPANDED ROW**. Comparing a notification card against §H produces false
"missing action" findings. **Every claim must state which surface it applies to.**

## Three structural blind spots in the snapshot harness

Do **not** assume snapshot coverage exists for these:

1. Halo `.accessibilityElement(children: .ignore)` (`HaloSessionRow.swift:206-208`) — the AX tree is blind to row detail.
2. `ThemeSnapshotting.swift:507` hardcodes `keyboardCoordinator: nil` — **no snapshot can render the keyboard hint, in any theme.**
3. The `.closedPill` harness slot renders `V6ClosedPill` directly and never dispatches through
   `\.islandTheme` — **no snapshot can verify the closed-pill glyph seam.**

## ⛔ Hard guardrails

- **Never edit the main worktree.**
- `zsh scripts/launch-dev-app.sh` must be run from **the worktree's own copy** (it derives repo root
  from its own location) and **`--skip-setup` is mandatory** — without it `OpenIslandSetup install`
  rewrites the user's real agent hook configs.
- Do **NOT** change the real hooks-installed probe — only the harness override.
- **Never write to or overwrite `shots/app/` or `shots/notch/`** — immutable baselines.
- Do **NOT** use `scripts/replay-bridge-scenarios.py` — a live production `/Applications/Open Island.app`
  owns the single bridge socket and the app ignores `OPEN_ISLAND_SOCKET_PATH`; it would drive the user's real app.
- Never `git reset --hard`, force-push, or overwrite user changes.
- **You do not commit. Never `git add -A`. Never `git stash`.** The orchestrator commits after verification.

## ⛔ Out of scope — investigated, correct as-is (plan §1, binding)

| Apparent problem | Reality |
|---|---|
| Completion card has no **Dismiss** | Deliberate. `notificationRowActions` (`IslandPanelView.swift:937-945`) omits `dismiss:` with an explicit comment. **Do not add a Dismiss button here.** |
| Completion card has no **Reply** | Feature flag `model.completionReplyEnabled`, default `false` (`AppModel.swift:298,758`). Not a rendering bug. |
| Halo/Poured completion card has no **Transcript** | Fixture gap — no fixture sets `transcriptPath`. Code path untested, not broken. (Flight Deck's *is* a real gap — F13.) |
| Poured's A3 attention glyph "is malformed" | REFUTED. Matches `UnifiedBars(mode:.waiting)`; the capture shows **A4 question**, not A3. |
| Halo's Failed outcome "uses a different template" | Fixture bug. `completedFailed.updatedAt` is 9 min old → stale → idle template. **Fix the fixture, not the badge/dot code.** |
| Halo session list "missing section headers" | User setting: `appearance.island.v8.notch.sessionGroup = none`. |
| Attention pills have a "huge banded glow" | REFUTED by measurement. Bleed within spec (Poured 5.0pt, FD 1.5pt, Halo 9.5pt). |
| Halo's row edge-rail "is missing" | Present at 2.0pt, correct cyan→violet gradient, correctly gated. |
| Flight Deck hero "drops the whole identity block" | Partly refuted — the agent name IS rendered, relocated above the card (defensible). Only **Model and Branch** are genuinely absent. **Fix only those.** |
| Notch vs top-bar metric differences | SPEC-sanctioned. Not defects. |
| Flight Deck's flat/opaque body, no gradients, no specular | **Correct by design** (tintOpacity 1.0). Its signature is phosphor glow bleed on lamps. **Do not add gradients.** |
| Halo's pure-black void, no fills/cards/vibrancy | **Correct by design.** Its only chrome is the 1.5pt edge-light. **Do not add card fills.** |

Only **Poured** owes layered glass, and it already has it.

⚠️ The SPEC files' ✅ conformance markers are **not trustworthy** — the ✅ column is headed "Floor";
it only ever claimed the target clears 10pt. **Verify against code, never the checkmark.**

## Your report

Structured — tables/lists, `file:line`, **measured numbers**. End with:

1. **Changes**: table of `file:line` → what changed → why.
2. **Build/test result**: exact command, exact pass/fail counts, named failures.
3. **Goldens**: predicted list vs actual moved list; explain any delta.
4. **Landmarks for the next agent**: `file:line`, gotchas, leftover ACs, anything you deferred.
5. **Anything you could NOT do** and precisely why.
