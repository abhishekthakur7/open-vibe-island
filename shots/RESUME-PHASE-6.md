# Resume prompt — overlay remediation, Phase 6

Copy everything below the line into a new chat window (run `/effort max` first).

---

You are resuming a multi-phase overlay visual-fidelity remediation on the Open Island macOS app.
**Phases 0–5 are complete and committed. The tree is CLEAN.** Run Phases 6–8, then merge to `main`.

## Your role — orchestrator only

Binding, from the original brief (`shots/REMEDIATION-PROMPT.md`):

> **You (the main agent) orchestrate only.** You do not read source files to analyse them, you do
> not write product code, you do not run captures.

- **Every sub-agent is Sonnet 5 with high reasoning**: pass `model: "sonnet"` on every `Agent` call.
  (The `Agent` tool exposes `model` but not `effort` — subagents inherit the session effort, so run
  `/effort max` yourself.)
- You may read: the plan document, sub-agent reports, and screenshots/diffs handed to you for a
  judgement call. You may edit the plan doc (§7 status table is your responsibility).
- Implementation agents run in parallel **only if their file sets are disjoint** — and **concurrent
  agents cannot `swift build` in the same worktree**, so in practice sequence them. A **read-only**
  reviewer (explicitly forbidden from building) *can* run alongside one builder.
- **Capture/verification is a strictly serial resource** — one verification agent per phase.
- Sub-agent reports must be structured (tables/lists with `file:line` and measured numbers).

## Where everything is

| What | Path |
|---|---|
| **Worktree — all edits happen here** | `/Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation` (branch `fix/overlay-fidelity-remediation`) |
| **Main checkout — read-only reference** | `/Users/abhishekthakur/Developer/open-vibe-island` |
| **The plan — your source of truth** | `<worktree>/docs/design/overlay-redesign/REMEDIATION-PLAN.md` |
| **Shared sub-agent briefs — hand these to every agent** | `/Users/abhishekthakur/Developer/open-vibe-island/shots/IMPL-BRIEF.md` and `.../shots/ANALYST-BRIEF.md` |
| Governing brief | `.../shots/REMEDIATION-PROMPT.md` |
| Mockup boards + crops | `<worktree>/docs/design/overlay-redesign/*.html`, `.../shots/mockup/` |
| Baseline captures (⛔ never overwrite) | `.../shots/app/`, `.../shots/notch/` |
| New captures / evidence pairs | `.../shots/after/`, `.../shots/pairs-after/` |

`shots/` exists **only in the main checkout** — hand agents absolute paths. Do **not** symlink it into
the worktree (`.git/info/exclude` is shared across worktrees and would hide it from `git status`).

## State

```
f074a27 feat: overlay remediation Phase 5 — layout          <- HEAD, tree clean
a5a5ed6 feat: overlay remediation Phase 4 — Flight Deck hero frame
792d52d fix: overlay remediation Phase 3 — safety, semantics, and a Codex data bug
3c79521 feat: overlay remediation Phase 2 — theme + paginate the shared question view
b5afaac test: overlay remediation Phase 1 — verification infrastructure
c5fbd53 (main) feat: Halo — permission hero, question, notification card... (AB-345)
```

**Full-suite baseline: 966 tests, 4 issues** — all in `AppModelSessionListTests`
(`islandSessionSectionsGroupStaleCompletedIntoIdle`,
`islandSessionSectionsKeepCompletedInDoneWhenStaleThresholdIsNever`,
`islandSessionListCanSortByLastUpdate`; an `activeAppearanceProfile` bucket race, diagnosed,
deliberately out of scope). Plus intermittent `cellStateReflectsSessionPhase` /
`bulkFirstObservationOrdersByHistoricalFirstSeenAt`. **Anything else is the agent's to fix.**

## Remaining phases

### Phase 6 — Type-scale hygiene (plan `:1496`)
1. **The lint FIRST**, in seed/allowlist mode, as a Swift `@Test` — **not** a shell script.
   `.github/` workflows are disabled and the two existing grep lints are wired into nothing;
   **`swift test` is the repo's only real gate.** Green on day one; every new escapee fails from then on.
2. Then, each removing its own allowlist entries: **F17** (FD `count` sub-roles, plan `:588`) ·
   **F18's role registration** · **F11** (`sideBadge` → `metaChip`, delete `monoChip`, plan `:609`) ·
   **F11b** (`heroButtonLabel`, plan `:626`) · **F19** (Halo `nestHeader: Font` constant, plan `:535`).
3. **Not this round**: the remaining ~130 sites — follow-up per-theme chore tickets.

⚠️ Phase 5 already added two FD roles additively (`gaugeUnitSize = 10`, `annunciatorCountSize = 17`),
both registered in `roleFamilies`. Keep further insertions additive; **never bump a shared role in
place** — `FlightDeckTypography.countSize` (11pt) is also the closed-pill count badge.

### Phase 7 — Component unification (plan `:1504`)
`IslandDiffRenderer` + `IslandDiffStyle`. Migration order: fixture+component → Poured → Halo →
**FD on `.chamfered(5)`, which resolves F14** (plan `:748`). Annual/Instrument **keep** the legacy
`PermissionDiffPreview` (D2 — it is **NOT** deleted). Then **F16** (plan `:807`), one Poured button
contract (r11, pad 14/8, 13/600), **preserving the primary-vs-ghost glow distinction** (event vs
wayfinding vs decision — a real semantic, not drift).
⚠️ **F14 must not be fixed independently of F12** (plan `:407`).

### Phase 8 — Full-matrix recapture + SPEC audit (plan `:1511`)
3×15 matrix via the Phase 1 script · computer-use for motion (§K), hover-peek (§B), expand/collapse
morph, focus rings, pressed states · add a **"shipped" column** to the FD and Halo typography tables ·
adjudicate the FD identity-run layout deviation (mockup shows a third column; we shipped a second
line, for measured reasons) and the listed fixture gaps.

## Carried-forward follow-ups (recorded in the plan, deliberately unfixed)

- **Halo's row-packed header lane is unreachable at 540pt** — needs ~600pt for a bare 58pt sliver,
  ~676pt for a 96pt gauge. Panel growth is symmetric about the notch, so 1pt of lane costs 2pt of
  width. A geometry decision, not a bug.
- **At 3+ usage windows a window is necessarily hidden** (two gauges need `g ≤ 46.25pt`, below
  legibility). A corner `+N` overlay makes the omission visible at zero lane-width cost.
- **⚠️ Accessibility defect, pre-existing and independent of the remediation**: the session rows'
  `NSAccessibilityCustomAction`s (`expand session detail`, `collapse session detail`,
  `dismiss session`) are registered with **`target:0x0 selector:(null)`** — listed by VoiceOver,
  non-invocable — and the opened panel has **no keyboard focus loop** (Tab moves nothing;
  `focusedElementId` never leaves the root). So VoiceOver and keyboard-only users cannot reach the
  expand affordance at all. Suspected at `PouredSessionRow.swift:1231-1267` and per-theme siblings.
  The chevron works fine with a mouse (confirmed by hand). **The user may want this filed in Linear.**

## Per-phase verification protocol (plan §6, `:1576`) — non-negotiable

1. **One** verification agent per phase. It gets: acceptance criteria, frames to capture, mockup crops,
   the scale rule, the surface-scope table, known artifacts.
2. Re-capture affected frames in **all three themes** where the change is shared. PASS/FAIL **per
   criterion, with numbers**.
3. Motion / hover / morph / focus / pressed → **computer-use**. Stills can't settle them.
4. **Any FAIL means the phase is not done.** Dispatch a fix agent with the measurement, re-verify, loop.
5. For every MAJOR fix, a second **adversarial verifier** tries to REFUTE the pass, defaulting to
   REFUTED when uncertain.
6. Evidence pairs → `shots/pairs-after/`; new captures → `shots/after/`.
7. Update the plan's §7 status table (`:1600`) before starting the next phase.

**A phase is not done because the code compiles — it is done when the pixels match.**

## Hard-won lessons — hand these to every agent

- ⚠️ **THE LESSON OF PHASE 5: tests here keep asserting what the CODE DOES rather than what a USER
  SHOULD SEE.** Three separate instances in one phase — a test pinning a defective lane split as
  correct, a test pinning "zero gauges rendered" as intended, and a width-only invariant that happily
  accepted an invisible window. **Two regressions passed a fully green suite** and were caught only by
  driving the real app: an FD header rendering 324pt of unclipped gauges into a 119.5pt lane, and an
  emptyState fix that turned clipped text into an infinite layout loop (100% CPU, unbounded RSS).
  **Assert the user-visible invariant.**
- ⚠️ **Four structural harness blind spots** — do not assume coverage exists:
  1. `SnapshotSessionListPanel` hardcodes `usesNotchAwareLayout: false`
     (`Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift:467-468`) — **no golden in any theme
     exercises the notch-aware header branch**, and no FD golden touches the usage lane at all.
  2. Halo `.accessibilityElement(children: .ignore)` (`HaloSessionRow.swift:206-208`) — AX tree blind
     to row detail.
  3. `ThemeSnapshotting.swift:507` hardcodes `keyboardCoordinator: nil` — **no** snapshot can render
     the keyboard hint, in any theme.
  4. The `.closedPill` harness slot renders `V6ClosedPill` directly, never through `\.islandTheme` —
     no snapshot can verify the closed-pill glyph seam.
- ⚠️ **The snapshot harness NEVER instantiates `IslandPanelView`.** It builds a private
  `SnapshotSessionListPanel` replica (`ThemeSnapshotting.swift:430-526`) with its **own**
  hand-maintained clip, and its offscreen `NSHostingView` rasterizer does **not** render `.blur()`
  faithfully. **Goldens settle layout and typography only — never glow, bleed, or panel geometry.**
  A Phase 4 agent overturned an adversarially-verified root cause on the strength of a harness
  experiment measuring a code path where the clip does not exist.
- **The real-app capture technique that works**:
  ```bash
  defaults write OpenIslandApp "appearance.island.v8.theme" -string flightDeck
  OPEN_ISLAND_HARNESS_SCENARIO=<x> OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1 \
    OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 OPEN_ISLAND_HARNESS_START_BRIDGE=0 swift run OpenIslandApp
  ```
  then capture via `orca computer get-app-state` (screenCaptureKit — a genuine WindowServer composite
  of the real `IslandPanelView`). ⚠️ A bare `swift run OpenIslandApp` uses UserDefaults domain
  `OpenIslandApp`, **NOT** `app.openisland.dev` — **verify the theme actually took.**
- ⚠️⚠️ **BUNDLE-ID COLLISION — this already caused two incidents.** The user's production
  `/Applications/Open Island.app` is signed with bundle id **`app.openisland.dev` — the SAME domain as
  the test target.** `orca computer --app app.openisland.dev` **drove the user's live app**, and a bare
  `pkill -9 -f OpenIslandApp` **killed it**. Capture agents must target **`--app pid:<own pid>`**, kill
  **only their own PIDs by exact PID**, confine `defaults` writes to the sandboxed `OpenIslandApp`
  domain, and **record the production app's PID at the start and confirm it alive at the end.**
- **Verify a feature is OBSERVABLE before verifying it is correct.** F2.4 passed review, compiled, and
  shipped for a full round while rendering **nothing** — no fixture set the data it needed.
- ⛔ **NEVER `git checkout --` a golden to make a test pass.** A Phase 4 agent did exactly that,
  destroyed a legitimate re-record, then misdiagnosed the failure it had just caused. If a golden
  fails, decide whether the **code** or the **golden** is wrong, and say which.
- **Predict which goldens will move BEFORE recording**, tracing **fixture → scenario → golden** across
  all six themes — fixtures are shared, so a "FD-only" fixture edit moves Halo and Poured goldens too.
  If a golden outside the predicted list moves, **STOP and investigate.** (Phase 5 predicted 17 and
  moved exactly 17.)
- **Q-descender trap**: "PERMISSION **REQUIRED**" and "**QUESTION**" contain a capital Q whose
  descender extends below true cap-height. Masking the whole string gives a **false tie (~0.99)**.
  Measure Q-free substrings ("PERMISSION", "UESTION"). This caught two separate agents.
- **Colour space**: captures are **Display-P3**. Convert before comparing to sRGB tokens — a raw
  `(244,180,96)` is exactly `(255,177,77)` sRGB. A naive comparison reports a false FAIL.
- **Scale rule**: app captures are **@2x** (1px = 0.5pt); mockup crops are **@1x**. **Halve every app
  pixel measurement.** The #1 source of false findings.
- **Confirm notch mode by panel width 540pt** (top-bar is 520pt) before trusting any notch claim.
  Forced-notch display UUID `37D8832A-2D66-02CA-B9F7-8F30A301B230`. Note FD's window is
  `540 + 2×18pt` shadow inset = 576pt; Halo/Poured use a 40pt inset → 620pt.
- **Focus**: the overlay is a `.nonactivatingPanel` and calls `makeKeyAndOrderFront` only when
  `notchOpenReason == .click`. Notification-opened cards deliberately don't take key focus — send one
  synthetic click on a neutral element before sending keys.
- **Surface-scope trap**: mockup **§H/§D depict the EXPANDED ROW**, a third surface. Comparing a
  notification card against §H produces false "missing action" findings. Every claim must name its surface.
- **The mockup boards are not physically faithful.** They are drawn at a **520px** panel (narrower than
  the real 540pt), under-model the ~189pt notch tax, and disagree with each other about lane
  arrangement. Verify a board's geometry is reachable before treating it as an acceptance criterion.

## Operational facts every agent needs

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # CLT default lacks the SwiftUI macro plugin
cd /Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation
swift build
```
**ModuleCache gotcha** — `precompiled file … module cache path …/open-vibe-island/.build/… but the path
is currently …/worktrees/…` is a path baked into the APFS-cloned `.build`, **not a code bug**:
```bash
rm -rf .build/arm64-apple-macosx/debug/ModuleCache .build/arm64-apple-macosx/release/ModuleCache
```
Never `rm -rf .build` wholesale (~5 min cold rebuild).

**Tests**: agents run only their assigned `--filter`. The orchestrator runs the full suite once per phase.

**Snapshots**: `Tests/OpenIslandAppTests/__Snapshots__/<TestClass>/<method>.<name>.png`, rendered @2x
unconditionally. `OPEN_ISLAND_RECORD_SNAPSHOTS=1` is a per-call default parameter, so `--filter`
genuinely scopes recording. Never blanket-re-record.

## ⛔ Hard guardrails

- **Never edit the main worktree.**
- `zsh scripts/launch-dev-app.sh` must be run from the **worktree's own copy** (it derives repo root
  from its own location) and **`--skip-setup` is mandatory** — without it `OpenIslandSetup install`
  rewrites the user's real agent hook configs.
- **Do NOT change the real hooks-installed probe** — only the harness override. The install-hint
  banner is a known harness artifact, already suppressed; never file it.
- **Never** write to or overwrite `shots/app/` or `shots/notch/` — immutable baselines.
- **Do NOT** use `scripts/replay-bridge-scenarios.py` — a live production `/Applications/Open Island.app`
  owns the single bridge socket and the app ignores `OPEN_ISLAND_SOCKET_PATH`; it would drive the
  user's real app.
- Never `git reset --hard`, force-push, or overwrite user changes without explicit approval.
- Sub-agents **do not commit**, never `git add -A`, never `git stash`. The orchestrator commits after
  verification — **one commit per phase**.
- The plan's **§1 out-of-scope / DO-NOT-FIX table** (`:67`) is binding. Hand it to every agent.
  ⚠️ The SPEC files' ✅ conformance markers are **not trustworthy** — that column is headed "Floor" and
  only ever claimed the target clears 10pt. **Verify against code and pixels, never the checkmark.**

## Cleanup, every session

```bash
# kill ONLY your own PIDs, by exact PID — never `pkill -f OpenIslandApp` (see bundle-id collision)
defaults write app.openisland.dev appearance.island.v8.theme -string halo
defaults write OpenIslandApp appearance.island.v8.theme -string halo
```

## Finishing

After Phase 8 verifies green: run the **full** suite plus `swift build` as the merge gate, then
squash-merge `fix/overlay-fidelity-remediation` to `main` with a conventional commit — the user has
authorised the merge. **Ask before pushing to `origin`.** Then remove the worktree and branch.

## Start now

1. Read `shots/IMPL-BRIEF.md` and `shots/ANALYST-BRIEF.md` — hand them to every sub-agent.
2. Read plan `:1439-1495` (Phase 5's outcome + corrections — the context you're inheriting),
   `:1496-1503` (Phase 6), and the F-sections for the findings you're about to fix.
   **The plan is the one file you are allowed to read.**
3. Dispatch the Phase 6 **lint** agent first (Sonnet 5) — seed/allowlist mode, as a Swift `@Test`.
   It is additive and changes no pixels, so it needs no capture round.
4. Then sequence F17 / F18-registration / F11 / F11b / F19, each removing its own allowlist entries.
5. Then the single Phase 6 verification agent, then commit Phase 6.
