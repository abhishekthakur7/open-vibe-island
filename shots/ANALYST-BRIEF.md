# Shared verification brief — overlay visual-fidelity remediation

You are a **verification agent**. You do **not** write product code. You capture, measure, and report
PASS/FAIL **per criterion, with numbers**. Read this whole file before starting.

**Capture is a strictly serial resource** — there is one overlay panel, one `defaults` theme key, and
one shared dev bundle. You are the only capture agent running. Do not spawn parallel capture work.

## Where everything is

| What | Path |
|---|---|
| **Worktree — the build under test** | `/Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation` |
| Main checkout — read-only | `/Users/abhishekthakur/Developer/open-vibe-island` |
| The plan | `<worktree>/docs/design/overlay-redesign/REMEDIATION-PLAN.md` |
| Mockup boards | `<worktree>/docs/design/overlay-redesign/*.html` |
| Mockup crops | `/Users/abhishekthakur/Developer/open-vibe-island/shots/mockup/` |
| ⛔ Baseline captures — **never overwrite** | `.../shots/app/`, `.../shots/notch/` |
| **Your new captures** | `/Users/abhishekthakur/Developer/open-vibe-island/shots/after/` |
| **Your before/after evidence pairs** | `/Users/abhishekthakur/Developer/open-vibe-island/shots/pairs-after/` |

`shots/` exists **only in the main checkout** — use absolute paths. Do **not** symlink it into the worktree.

## Build the bundle under test

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /Users/abhishekthakur/Developer/open-vibe-island/.claude/worktrees/overlay-remediation
swift build
zsh scripts/launch-dev-app.sh --skip-setup     # ⛔ the WORKTREE's copy; --skip-setup is MANDATORY
```

`launch-dev-app.sh` derives `repo_root` from **its own location** — running the main checkout's copy
captures the wrong build. Without `--skip-setup`, `OpenIslandSetup install` **rewrites the user's real
agent hook configs**.

**ModuleCache gotcha** — `precompiled file … module cache path …/open-vibe-island/.build/… but the
path is currently …/worktrees/…` is a path baked into the APFS-cloned `.build`, not a code bug:
`rm -rf .build/arm64-apple-macosx/debug/ModuleCache .build/arm64-apple-macosx/release/ModuleCache`.
**Never `rm -rf .build` wholesale.**

## Measurement rules — these decide PASS/FAIL correctness

### Scale rule (the #1 source of false findings)
App captures are **@2x** (1px = 0.5pt). Mockup crops are **@1x** (1px = 1pt).
**Halve every app pixel measurement before comparing.** State both the raw px and the derived pt.

### Colour space
Captures are **Display-P3**. **Convert to sRGB before comparing to token values.** Phase 3 sampled
`(244,180,96)` raw, which is *exactly* `(255,177,77)` sRGB — a naive comparison would have reported a
false FAIL. Report the raw sample, the converted value, and the target.

### Surface scope — every claim must name its surface
| Surface | Config | Scenarios |
|---|---|---|
| Notification card | `notchOpenReason:.notification` + `islandSurface:.sessionList(actionableSessionID:)` | `approvalCard`, `questionCard`, `completionCard`, `longCompletionCard`, `diffApprovalCard`, `codexApprovalCard`, `multiQuestionCard`, `completedInterrupted`, `completedFailed` |
| Plain session list | `notchOpenReason:.click` + `islandSurface:.sessionList()` | `sessionList`, `subagentsCard`, `usageMeters` |
| **Expanded row** (mockup §D/§H, §G engine cluster) | a **third** surface | reachable since Phase 1 |

Mockup **§H/§D depict the EXPANDED ROW**. Comparing a notification card against §H produces false
"missing action" findings.

### Focus / key delivery
The overlay is a `.nonactivatingPanel` and calls `makeKeyAndOrderFront` **only** when
`notchOpenReason == .click`. Notification-opened cards deliberately do not steal key focus —
**send one synthetic click on a neutral, non-interactive element before sending keys.** This is
product behaviour, not a defect.

### Notch vs top-bar
Forced-notch captures use built-in display UUID `37D8832A-2D66-02CA-B9F7-8F30A301B230`.
**Confirm notch mode by panel width 540pt** (vs top-bar 520pt).

## Known harness artifacts — never file, never "fix"
- Install-hint banner ("No agent hooks installed — SETUP") — the bundled binary's hooks probe reads
  false. Phase 1 added a **harness-only** suppression. ⛔ Do NOT change the real hooks-installed probe.
- `appearance.island.v8.notch.sessionGroup = none` is the **user's setting**, not a missing feature.
- Notch↔top-bar metric deltas (pill 38↔24pt, panel 540↔520pt, insets 46↔16pt, ring 30↔22pt) are SPEC-sanctioned.

## Three structural blind spots in the snapshot harness
Do **not** report "no coverage" as a defect, and do not expect these to appear in stills:
1. Halo `.accessibilityElement(children: .ignore)` (`HaloSessionRow.swift:206-208`) — AX tree blind to row detail.
2. `ThemeSnapshotting.swift:507` hardcodes `keyboardCoordinator: nil` — **no snapshot can render the keyboard hint, in any theme.**
3. `.closedPill` harness slot renders `V6ClosedPill` directly, never through `\.islandTheme` — no snapshot can verify the closed-pill glyph seam.

## Motion, hover, morph, focus rings, pressed states
**Stills cannot settle these — drive them live via computer-use (the `orca` CLI).** Load the
`computer-use` skill. Anything you could not drive, report explicitly as UNMEASURED with the reason —
never as PASS.

## ⛔ Hard guardrails

### ⚠️ BUNDLE-ID COLLISION — this already caused two incidents in Phase 5
The user's **production** `/Applications/Open Island.app` is signed with bundle id
**`app.openisland.dev` — the SAME domain as the test target.** In Phase 5 verification this caused
`orca computer --app app.openisland.dev` calls to **drive the user's live app** (opening its Settings
window), and a mandated `pkill -9 -f OpenIslandApp` to **kill it**.

- **NEVER** run a bare `pkill -f OpenIslandApp`, or any pattern that could match another process.
  Kill **only** processes you launched, **by exact PID**.
- With `orca computer`, always target **`--app pid:<your pid>`**. **Never** a bundle id.
- Confine `defaults` writes to the sandboxed **`OpenIslandApp`** domain, never `app.openisland.dev`.
- **Record the production app's PID before you start; confirm it is still alive at the end.** Report both.

- **Never edit the main worktree**; never edit product code at all.
- **Never write to or overwrite `shots/app/` or `shots/notch/`.**
- Do **NOT** use `scripts/replay-bridge-scenarios.py` — a live production `/Applications/Open Island.app`
  owns the single bridge socket and the app ignores `OPEN_ISLAND_SOCKET_PATH`; it would drive the user's real app.
- You do **not** commit, never `git add -A`, never `git stash`.
- The plan's §1 out-of-scope / DO-NOT-FIX table is binding — see below.

## ⛔ Out of scope — investigated, correct as-is (plan §1, binding)

| Apparent problem | Reality |
|---|---|
| Completion card has no **Dismiss** | Deliberate (`IslandPanelView.swift:937-945` omits `dismiss:` with a comment). |
| Completion card has no **Reply** | Feature flag `model.completionReplyEnabled`, default `false`. |
| Halo/Poured completion card has no **Transcript** | Fixture gap, not a bug. (Flight Deck's *is* real — F13.) |
| Poured's A3 attention glyph "malformed" | REFUTED. The capture shows **A4 question**, not A3. |
| Halo's Failed outcome "different template" | Fixture bug — `completedFailed.updatedAt` is 9 min old → stale → idle template. |
| Halo session list "missing section headers" | User setting `sessionGroup = none`. |
| Attention pills "huge banded glow" | REFUTED. Bleed within spec (Poured 5.0pt, FD 1.5pt, Halo 9.5pt). The drama is capturing against pure black vs the mockup's grey desktop. |
| Halo's row edge-rail "missing" | Present at 2.0pt, correct cyan→violet gradient. |
| FD hero "drops the whole identity block" | Partly refuted — the agent name IS rendered above the card. Only **Model and Branch** are genuinely absent. |
| Notch vs top-bar metric differences | SPEC-sanctioned. |
| FD flat/opaque body, no gradients/specular | **Correct by design** (tintOpacity 1.0). Its signature is phosphor glow bleed on lamps. |
| Halo's pure-black void, no fills/cards | **Correct by design.** Only chrome is the 1.5pt edge-light. |

⚠️ The SPEC files' ✅ markers are **not trustworthy** — that column is headed "Floor" and only ever
claimed the target clears 10pt. **Verify against code and pixels, never the checkmark.**

## Your report — required shape

1. **Criterion table**: one row per acceptance criterion → `PASS` / `FAIL` / `UNMEASURED` → **the
   measured number** (raw px, derived pt, sampled RGB + sRGB conversion) → the target → the capture
   file path backing it.
2. **Surface** named on every row.
3. **Captures written**: list of paths under `shots/after/` and `shots/pairs-after/`.
4. **UNMEASURED items**: each with the precise reason it could not be driven.
5. **For any FAIL**: the exact measurement, the file:line you believe is responsible, and what a fix
   agent would need to change. Do not fix it yourself.
6. **Anything that surprised you** — new defects found incidentally, artifacts, drift.

Default to **FAIL** when uncertain. A criterion you could not measure is never a PASS.
