# CLAUDE.md

## Project

Open Island — native macOS companion for AI coding agents. Sits in the notch / top bar, monitors local sessions, surfaces permission and question events, and jumps back to the right terminal/IDE. Local-first, no server.

- **Target product** (closed-source baseline): https://vibeisland.app/
- **OSS reference** (design ideas only, not a spec): https://github.com/farouqaldori/claude-island

## Architecture

One Swift package (`OpenIsland`), four targets:

- **OpenIslandApp** — SwiftUI + AppKit shell. `AppModel` owns state.
- **OpenIslandCore** — Models, bridge transport (Unix socket, NDJSON), hook installers, session discovery & registry.
- **OpenIslandHooks** — CLI invoked by agent hooks. Forwards stdin payload → bridge.
- **OpenIslandSetup** — Installer CLI for agent config files.

Data flow: `agent hook → OpenIslandHooks (stdin) → Unix socket → BridgeServer → AppModel → UI`. On launch: registry restore → JSONL transcript discovery → reconcile with active processes → live bridge.

Requires macOS 14+, Swift 6.2.

## Build & run

```bash
swift build
swift test
swift run OpenIslandApp                            # canonical dev runtime
swift build -c release --product OpenIslandHooks
```

For Xcode: open `Package.swift`.

## Dev app (Open Island Dev.app)

`~/Applications/Open Island Dev.app` is a wrapper around the repo build, not a separate product.

- **Launch**: `zsh scripts/launch-dev-app.sh` — never just `open -na`, the bundle goes stale.
- **One-time signing**: `zsh scripts/setup-dev-signing.sh` — without this every rebuild changes cdhash and silently invalidates TCC grants (Accessibility, Automation). Required for any AX-touching feature (precision jump, keystroke/menu injection).
- `scripts/harness.sh smoke` / `scripts/smoke-dev-app.sh` are for deterministic harness runs only.

## Workflow

- **Never edit in the main worktree.** Use `EnterWorktree` (preferred) or `git worktree add`, branched off latest local `main`.
- Branch name matches topic: `feat/<topic>`, `fix/<topic>`. One coherent change per round.
- Changes land by **direct merge to `main`** — no PR required. From the main checkout: `git merge --squash <branch>`, commit with the conventional message (one commit per ticket), push `origin main`. Dependent tickets wait for the prerequisite to land on `main`, then branch off it.
- Conventional commit messages (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`). Never `--amend` unless asked.
- After changes: run the matching verification (`swift build` / `swift test` / manual). If no check exists, say so in the summary and still commit.
- Never `git reset --hard`, force-push, or overwrite user changes without explicit approval. If unexpected state appears, inspect — don't bulldoze.

## Ticket execution protocol

Rules for working a Linear ticket (or any batch of agent-driven changes). They exist because a
timed 11-ticket run showed ~85% of wall clock inside agent build/test loops, not CI.

- **Worktrees**: create via `zsh scripts/agent-worktree.sh <branch>` — it branches off latest
  `origin/main` and seeds `.build` from the main checkout (APFS clone, ~instant), skipping the
  ~5-min cold dependency build. Don't hand-roll `git worktree add` for ticket work.
- **Warm cache upkeep**: after merging a ticket, run `swift build` in the main checkout so the
  next worktree seeds from a current cache. Building in the main worktree is fine; editing it is not.
- **Toolchain**: always prefix `swift build` / `swift test` with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` — the CLT default lacks the SwiftUI
  macro plugin and fails inside the NetworkImage dependency.
- **Test scoping**: during development run `swift test --filter <touched suites>`. Run the FULL
  suite exactly once per ticket — the last agent, before the final commit. Snapshot golden
  record (`OPEN_ISLAND_RECORD_SNAPSHOTS=1`) + verify runs must be `--filter`ed to the snapshot
  suite, never two full passes.
- **Known-red tests** (pre-existing, do NOT chase; confirm the count is unchanged and move on):
  `islandSessionSectionsGroupStaleCompletedIntoIdle`,
  `islandSessionSectionsKeepCompletedInDoneWhenStaleThresholdIsNever`,
  `islandSessionListCanSortByLastUpdate`, `cellStateReflectsSessionPhase`,
  `bulkFirstObservationOrdersByHistoricalFirstSeenAt`. The first three are an
  `activeAppearanceProfile` bucket race (the getter falls back to the other profile's default when a
  placement arrives mid-test); `AgentsGridRightSlotTests.swift:184-193` already documents and fixes
  the same race via a both-buckets pin (AB-322) — never back-ported here. The last two are
  genuinely intermittent and often pass.
  The two Poured session-list baseline goldens were **not** drifting environmentally, despite what
  this file previously claimed — their references predated the Poured 2.0 redesign (no `</>` icon,
  Deny-left button order, a nested command block). Re-recorded to current truth and **now passing**.
- **Multi-agent tickets**: split big tickets into sequential parts sharing one worktree; each
  part's report must end with landmarks for the next part (file:line, gotchas, leftover ACs).
- **Merge protocol**: the local full suite (plus `swift build`) is the merge gate — the GitHub
  CI workflow is disabled (PR #55) and PRs are not used. Once the gate is green: squash-merge
  the ticket branch to `main`, push directly, mark the Linear ticket Done, remove the worktree
  and branch.

## Scope guardrails

Current support matrix (agents / terminals / IDEs) lives in `README.md` — that's the single source of truth, keep it accurate at release time.

The project is past MVP and welcomes new ideas and creative directions, but the following stay off-limits without an explicit ask:

- Analytics or telemetry SDKs (Mixpanel etc.)
- Window-manager dependencies (`yabai` etc.)
- Claude-only assumptions that weaken the multi-agent model
- Anything that breaks local-first (remote-server dependencies, cloud-only paths)

## Conventions

- `SessionState.apply(_:)` is the single source of truth for session mutations.
- Bridge protocol: newline-delimited JSON envelopes (`BridgeCodec`).
- All models `Sendable` + `Codable`.
- Hooks **fail open** — if app/bridge is down, the agent runs unchanged.
- Native macOS APIs over cross-platform abstractions. Small end-to-end slices over speculative scaffolding.

## Key files

- `Sources/OpenIslandApp/AppModel.swift` — central state, session management, bridge lifecycle
- `Sources/OpenIslandCore/SessionState.swift` — pure reducer
- `Sources/OpenIslandCore/AgentEvent.swift` — event enum driving all transitions
- `Sources/OpenIslandCore/BridgeTransport.swift` + `BridgeServer.swift` — socket protocol & dispatch
- `Sources/OpenIslandCore/{Claude,Codex,Gemini,Kimi,Cursor}Hooks.swift` etc. — per-agent hook payload models
- `Sources/OpenIslandHooks/main.swift` — hook CLI entry
- `docs/product.md`, `docs/architecture.md`, `AGENTS.md` — design / working-agreement docs
