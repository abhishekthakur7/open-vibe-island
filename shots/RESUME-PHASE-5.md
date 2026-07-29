# Resume prompt — overlay remediation, Phase 5 (mid-phase)

Copy everything below the line into a new chat window (run `/effort max` first).

---

You are resuming a multi-phase overlay visual-fidelity remediation on the Open Island macOS app.
Phases 0–4 are complete and committed. **Phase 5 is partially done and UNCOMMITTED.** Finish Phase 5,
then run Phases 6–8, then merge to `main`.

## Your role — orchestrator only

Binding, from the original brief (`shots/REMEDIATION-PROMPT.md`):

> **You (the main agent) orchestrate only.** You do not read source files to analyse them, you do
> not write product code, you do not run captures.

- **Every sub-agent is Sonnet 5 with high reasoning**: pass `model: "sonnet"` and `effort: "high"`
  on every `Agent` call. No exceptions.
- You may read: the plan document, sub-agent reports, and screenshots/diffs handed to you for a
  judgement call.
- Implementation agents run in parallel **only if their file sets are disjoint** — and **concurrent
  agents cannot `swift build` in the same worktree**, so in practice sequence them.
- **Capture/verification is a strictly serial resource** — one verification agent per phase.
- Sub-agent reports must be structured (tables/lists with `file:line` and measured numbers).

## Where everything is

| What | Path |
|---|---|
| **Worktree — all edits happen here** | `/Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation` (branch `fix/overlay-fidelity-remediation`) |
| **Main checkout — read-only reference** | `/Users/abhishekthakur/Developer/open-vibe-island` |
| **The plan — your source of truth** | `<worktree>/docs/design/overlay-redesign/REMEDIATION-PLAN.md` |
| **Shared sub-agent briefs — hand these to every agent** | `/Users/abhishekthakur/Developer/open-vibe-island/shots/IMPL-BRIEF.md` and `.../shots/ANALYST-BRIEF.md` (durable copies; the scratchpad is session-scoped and will be empty) |
| Governing brief | `.../shots/REMEDIATION-PROMPT.md` |
| Findings report | `.../shots/REPORT.md`, `.../shots/REPORT-ranked-verified.md` |
| Mockup boards + crops | `<worktree>/docs/design/overlay-redesign/*.html`, `.../shots/mockup/` |
| Baseline captures (⛔ never overwrite) | `.../shots/app/`, `.../shots/notch/` |
| New captures / evidence pairs | `.../shots/after/`, `.../shots/pairs-after/` |

`shots/` exists **only in the main checkout** — hand agents absolute paths. Do **not** symlink it into
the worktree (`.git/info/exclude` is shared across worktrees and would hide it from `git status`).

## State — read this carefully, the tree is DIRTY

Committed:
```
a5a5ed6 feat: overlay remediation Phase 4 — Flight Deck hero frame
792d52d fix: overlay remediation Phase 3 — safety, semantics, and a Codex data bug
3c79521 feat: overlay remediation Phase 2 — theme + paginate the shared question view
b5afaac test: overlay remediation Phase 1 — verification infrastructure
c5fbd53 (main) feat: Halo — permission hero, question, notification card... (AB-345)
```

**Uncommitted in the worktree — Phase 5A + 5B, both green, neither capture-verified:**

| Files | What |
|---|---|
| `FlightDeckTheme.swift`, `FlightDeckUsageSummary.swift`, `FlightDeckClosedPill.swift`, `FlightDeckThemeTests.swift` | **F18** (`gaugeUnitSize = 10`, registered in `roleFamilies`), **F8** (chip `VStack`→`HStack`), **F15** (usage colours → FD tokens, test updated atomically) |
| six `*HeaderControls.swift` (−97 lines each), `IslandUsageSummary.swift` (+171), **new** `Tests/OpenIslandAppTests/IslandHeaderLaneLayoutTests.swift` (185 lines) | **F7** — the six byte-identical lane splitters deduplicated into one shared function |

Verified state as of handoff: `swift build` completes; `swift test --filter
"IslandHeaderLaneLayoutTests|FlightDeckThemeTests|ThemeSnapshotHarnessTests"` → **43 tests + 14
snapshot tests, all green**. Zero goldens moved (no FD golden renders the opened header at all).

⚠️ **The F7 agent was interrupted before it could file a report.** Its code is present and green, but
**nobody has reviewed its algorithm or captured it**. Treat F7 as *implemented but unreviewed*: have
the Phase 5 verification agent measure it, and consider a short adversarial review of the shared
function's flatten/reflow logic before committing.

### The F8↔F7 coupling (why these two must ship together)
F8 moved FD's gauge growth from height to width — a 2-window chip went ~168pt → **~327pt**
(2×150 `gaugeWidth` + 9 spacing + 18 padding). `gaugeWidth = 150` is fixed and the `ViewThatFits`
short-title fallback only shortens the **title string**, so it cannot rescue a too-narrow lane.
F7's flatten-to-`(provider, window)` split is what caps a lane back to one window (~150pt) — which is
also exactly the mockup's arrangement. **Verify that actually happened; do not assume it.**

## Phase 5 — what is LEFT

Plan §4 `:1424`. Sequence these (shared worktree ⇒ no concurrent builds):

1. **F9 — FD §C annunciator strip is ~2.4× too small** (plan `:372`) · MAJOR
   ⚠️ **Not a leaf-view resize.** In the mockup the strip is its **own full-width band**, separate from
   the brand/usage header; there is **no mockup equivalent of a "SESSION LIST" title sharing a row with
   the tiles**. The app fuses title + tiles into one `HStack` inside one `.frame(height:40)`
   (`FlightDeckSessionListScaffold.swift:141`). **The fix must restructure `sessionPanelHeader`.**
   Rewrite `FlightDeckAnnunciatorTileView.body` (`:364-407`) to `VStack(spacing:3)`, replace the 6×6
   lamp with a leading **full-height 2pt accent `Rectangle`** (keep `phosphorGlow`), padding v9/h12,
   and give the count a **new dedicated typography role** — do **NOT** bump the shared
   `FlightDeckTypography.countSize` in place, it is also the closed-pill count badge.
   AC: tile height **49–55pt @1x**; ≥2pt accent mark spanning full tile height when lit; count ≥15pt
   stacked **above** a ≤10pt uppercase caption. Panel height is measured dynamically
   (`OverlayPanelController.swift:589-604`), so growing the tile is safe (~+11–15pt on ~650pt).
   Open copy decision: whether to keep a "SESSION LIST" title at all — the mockup shows none.
   ⚠️ Touches `FlightDeckTheme.swift`, which Phase 5A already edited — keep insertions **additive**.

2. **NEW — `emptyState` clipping on Flight Deck and Halo** (plan `:1432`)
   Found during Phase 1 verification: even with the install hint suppressed, both themes cut off
   secondary body copy at the panel's bottom edge (FD's "…watching the bridge…" tail, Halo's
   "Monitoring" footer). **Poured is fine.** The panel does not resize when the hint is suppressed, so
   this is an independent height/layout defect.
   AC: every text run present in the AX tree for `emptyState` is fully within the captured frame, all
   three themes.

3. **F6 + P1.a — Poured buries the list under expanded rows** (plan `:762`, `:839`) · MAJOR
   **These two MUST land together.** The precise defect is the **unconditional `else` branch** at
   `PouredSessionRow.swift:145-150`, **not** the `showsDetail` predicate. Fix:
   `else { sessionDetailBody(…) }` → `else if detailOverride == true { … }`. The plumbing already
   exists — `@State private var detailOverride: Bool?` (`:82`) plus a working chevron
   `detailToggleButton` (`:1231+`). The hero path (`shouldShowEmbeddedDetailBody`) never reads
   `detailOverride`, so the notification card is **provably unaffected**.
   ⚠️ **P1.a**: `testExpandedDetailAndSubagents`'s golden exists ONLY because of this bug
   (`ThemeSnapshotting.swift:224` forces `actionableSessionID = nil` for `.subagents`). Fixing F6 makes
   that path unreachable from static snapshots — **a testability seam is required**. The seam already
   exists but was never wired: `IslandRowExpandedByDefaultKey`
   (`IslandThemeEnvironment.swift:107-127`). Add `forcesRowExpansion: Bool = false` to
   `IslandDebugSnapshot`; set it on a **new** scenario (`subagentsExpanded`) so the existing
   `subagentsCard` keeps documenting the collapsed state; thread through `AppModel.loadDebugSnapshot` →
   `.environment(\.islandRowExpandedByDefault, …)` at `OverlayPanelController.swift:134`.
   AC (F6): all 9 fixture rows fit — post-fix 9 rows = 2×62 + 7×49 = **467pt ≤ 560pt** cap; ≥5 rows
   visible in the 430pt preview budget in every scenario.
   AC (P1.a): `overlay.ax.json` for the new FD/Halo captures contains the fixture's task titles
   (e.g. `"Header + meters + scaffold"`) — currently absent, already present for Poured.
   Decided already (plan §5): keep the Poured-scoped fix; `IslandPanelView.swift:1158`'s duplicate
   `showsDetail` and Halo's own `sessionDetailBody` **stay untouched** — flag it in the commit.

4. **One Phase 5 verification agent** (serial), then **commit Phase 5** — one commit for the phase.

## Remaining phases (plan §4)

- **Phase 6 — Type-scale hygiene** (`:1439`): **the lint FIRST**, in seed/allowlist mode, as a Swift
  `@Test` (not a shell script — `.github/` workflows are disabled and the two existing grep lints are
  wired into nothing; `swift test` is the repo's only real gate). Then F17 / F18's role registration /
  F11 (`sideBadge`→`metaChip`, delete `monoChip`) / F11b (`heroButtonLabel`) / F19 — each removing its
  own allowlist entries. ~130 remaining sites are explicitly **follow-up tickets, not this round**.
- **Phase 7 — Component unification** (`:1447`): `IslandDiffRenderer` + `IslandDiffStyle`; migration
  order fixture+component → Poured → Halo → **FD on `.chamfered(5)`, which resolves F14** →
  Annual/Instrument **keep** the legacy `PermissionDiffPreview` (D2 — it is NOT deleted). Then **F16**,
  one Poured button contract (r11, pad 14/8, 13/600), preserving the primary-vs-ghost glow distinction.
  ⚠️ **F14 must not be fixed independently of F12** — plan `:757`.
- **Phase 8 — Full-matrix recapture + SPEC audit** (`:1454`): 3×15 matrix via the Phase 1 script ·
  computer-use for motion (§K), hover-peek (§B), expand/collapse morph, focus rings, pressed states ·
  add a **"shipped" column** to the FD and Halo typography tables. **Two items carried in from Phase 4
  are recorded in the plan at `:1454`** — adjudicate the FD identity-run layout deviation (mockup shows
  a third column; we shipped a second line, for measured reasons) and the listed fixture gaps.

## Per-phase verification protocol (plan §6, `:1504`) — non-negotiable

1. **One** verification agent per phase. It gets: acceptance criteria, frames to capture, mockup crops,
   the scale rule, the surface-scope table, known artifacts.
2. Re-capture affected frames in **all three themes** where the change is shared. PASS/FAIL **per
   criterion, with numbers**.
3. Motion / hover / morph / focus / pressed → **computer-use**. Stills can't settle them.
4. **Any FAIL means the phase is not done.** Dispatch a fix agent with the measurement, re-verify, loop.
5. For every MAJOR fix, a second **adversarial verifier** tries to REFUTE the pass, defaulting to
   REFUTED when uncertain.
6. Evidence pairs → `shots/pairs-after/`; new captures → `shots/after/`.
7. Update the plan's §7 status table before starting the next phase.

**A phase is not done because the code compiles — it is done when the pixels match.**

## Hard-won lessons from Phases 1–4 — hand these to every agent

- ⚠️ **The snapshot harness NEVER instantiates `IslandPanelView`.** It builds a private
  `SnapshotSessionListPanel` replica (`Tests/OpenIslandAppTests/Support/ThemeSnapshotting.swift:430-526`)
  with its **own** hand-maintained clip, and its offscreen `NSHostingView` rasterizer does **not**
  render `.blur()` faithfully. **Goldens cannot settle glow, bleed, or panel-geometry claims** — only
  layout and typography. A Phase 4 agent overturned an adversarially-verified root cause on the
  strength of a harness experiment that was measuring a code path where the clip does not exist.
- **The real-app capture technique that works** (this is how Phase 4 was settled):
  ```bash
  defaults write OpenIslandApp "appearance.island.v8.theme" -string flightDeck
  OPEN_ISLAND_HARNESS_SCENARIO=<x> OPEN_ISLAND_HARNESS_PRESENT_OVERLAY=1 \
    OPEN_ISLAND_HARNESS_BOOT_ANIMATION=0 swift run OpenIslandApp
  ```
  then capture via `orca computer get-app-state` (screenCaptureKit — a genuine WindowServer composite
  of the real `IslandPanelView`). ⚠️ **A bare `swift run OpenIslandApp` uses UserDefaults domain
  `OpenIslandApp`, NOT `app.openisland.dev`** — setting the theme on the wrong domain silently renders
  the developer's real theme instead. Verify the theme actually took.
- **Verify a feature is OBSERVABLE before verifying it is correct.** F2.4 passed review, compiled, and
  shipped for a full round while rendering **nothing** — no fixture set the data it needed. Closing
  that fixture gap is what exposed a genuine layout collapse that a green criterion had masked.
- ⛔ **NEVER `git checkout --` a golden to make a test pass.** A Phase 4 agent did exactly that,
  destroyed a legitimate re-record, then misdiagnosed the failure it had just caused. If a golden
  fails, decide whether the **code** or the **golden** is wrong, and say which.
- **Predict which goldens will move BEFORE recording**, tracing **fixture → scenario → golden** across
  all six themes — fixtures are shared, so a "FD-only" fixture edit moves Halo and Poured goldens too.
  If a golden outside the predicted list moves, **STOP and investigate**.
- **Q-descender trap**: "PERMISSION **REQUIRED**" and "**QUESTION**" contain a capital Q whose descender
  extends below true cap-height. Masking the whole string gives a **false tie (~0.99)**. Measure Q-free
  substrings ("PERMISSION", "UESTION"). This caught two separate agents.
- **Colour space**: captures are **Display-P3**. Convert before comparing to sRGB tokens — a raw
  `(244,180,96)` is exactly `(255,177,77)` sRGB. A naive comparison reports a false FAIL.
- **Scale rule**: app captures are **@2x** (1px = 0.5pt); mockup crops are **@1x**. **Halve every app
  pixel measurement.** The #1 source of false findings.
- **Focus**: the overlay is a `.nonactivatingPanel` and calls `makeKeyAndOrderFront` only when
  `notchOpenReason == .click`. Notification-opened cards deliberately don't take key focus — send one
  synthetic click on a neutral element before sending keys.
- **Surface-scope trap**: mockup **§H/§D depict the EXPANDED ROW**, a third surface. Comparing a
  notification card against §H produces false "missing action" findings. Every claim must name its surface.

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

**Tests**: agents run only their assigned `--filter`. The orchestrator runs the full suite once per
phase. **Known-red baseline: 4 issues, all `AppModelSessionListTests`** (`activeAppearanceProfile`
bucket race — diagnosed, fix pattern known, deliberately out of scope), plus intermittent
`cellStateReflectsSessionPhase` / `bulkFirstObservationOrdersByHistoricalFirstSeenAt`. Anything else is
the agent's to fix. Full suite at Phase 4: **929 tests, 4 issues.**

**Snapshots**: `Tests/OpenIslandAppTests/__Snapshots__/<TestClass>/<method>.<name>.png`, rendered @2x
unconditionally. `OPEN_ISLAND_RECORD_SNAPSHOTS=1` is a per-call default parameter, so `--filter`
genuinely scopes recording. Never blanket-re-record.

**Three structural blind spots in the harness** (do not assume coverage exists):
1. Halo `.accessibilityElement(children: .ignore)` (`HaloSessionRow.swift:206-208`) — AX tree blind to row detail.
2. `ThemeSnapshotting.swift:507` hardcodes `keyboardCoordinator: nil` — **no** snapshot can render the keyboard hint, in any theme.
3. The `.closedPill` harness slot renders `V6ClosedPill` directly, never through `\.islandTheme` — no snapshot can verify the closed-pill glyph seam.

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
- Sub-agents **do not commit**, never `git add -A`, never `git stash`. The orchestrator commits after
  verification — **one commit per phase**.
- The plan's **§1 out-of-scope / DO-NOT-FIX table** (`:67`) is binding. Hand it to every agent.

## Cleanup, every session

```bash
pkill -9 -f OpenIslandApp
defaults write app.openisland.dev appearance.island.v8.theme -string halo
defaults write app.openisland.dev overlay.display.preference -string F3BDCAC0-1700-415E-817D-AC4E69D405BC
# and reset the bare-run domain if a capture agent touched it:
defaults write OpenIslandApp appearance.island.v8.theme -string halo
```
Forced-notch captures use built-in display UUID `37D8832A-2D66-02CA-B9F7-8F30A301B230`; confirm notch
mode by panel width **540pt** (vs top-bar 520pt).

## Finishing

After Phase 8 verifies green: run the **full** suite plus `swift build` as the merge gate, then
squash-merge `fix/overlay-fidelity-remediation` to `main` with a conventional commit — the user has
authorised the merge. **Ask before pushing to `origin`.** Then remove the worktree and branch.

## Start now

1. Read `shots/IMPL-BRIEF.md` and `shots/ANALYST-BRIEF.md` — hand them to every sub-agent.
2. Read plan `:225-263` (F7, for review context), `:372-405` (F9), `:762-805` (F6), `:839-857` (P1.a),
   and `:1424-1437` (Phase 5). **The plan is the one file you are allowed to read.**
3. Consider a short **adversarial review of the uncommitted F7 shared function** — it is green but its
   author never reported, so its algorithm is unreviewed.
4. Dispatch the F9 + emptyState implementation agent (Sonnet 5, high effort), then F6 + P1.a, then the
   single Phase 5 verification agent, then commit Phase 5.
