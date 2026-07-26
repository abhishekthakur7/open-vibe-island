# Worktree Workflow

This repository should use Git worktrees as the default shape for development.

## Goals

- keep `main` stable enough to integrate and verify
- give each agent or human one isolated checkout
- reduce accidental interference across unrelated slices
- keep merge and rollback boundaries obvious

## Roles

### 1. Integration worktree

- Path: `/Users/wangruobing/Personal/open-island`
- Branch: `main`
- Purpose: fetch, integrate finished branches into `main`, and verify

Rules:

- Do not start feature work here.
- Do not edit files or author new commits directly on `main` — the only commits made here are squash-merge commits of finished topic branches.
- Use this worktree to inspect the overall state, fetch, update local `main` with `git pull --ff-only`, perform squash-merges + pushes, and run final verification after merges.

### 2. Topic worktrees

- Path pattern: `/Users/wangruobing/Personal/open-island-<topic>`
- Branch pattern: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`, `investigate/<topic>`
- Purpose: isolated implementation for one slice

Rules:

- One worktree owns one branch.
- One branch should represent one coherent slice.
- If two agents are working in parallel, they must use different worktrees and different branches.
- If two slices would touch many of the same files, do not run them in parallel unless one slice clearly owns the shared files.

## Standard Lifecycle

### Create a new topic worktree

From the integration worktree:

```bash
git fetch origin
git worktree add /Users/wangruobing/Personal/open-island-<topic> -b <branch-name> origin/main
```

Example:

```bash
git fetch origin
git worktree add /Users/wangruobing/Personal/open-island-island-polish -b feat/island-polish origin/main
```

## Work inside the topic worktree

Inside the topic worktree:

```bash
git status -sb
```

Then follow the normal repository workflow:

1. read the relevant files
2. make one coherent change
3. verify the change
4. commit before stopping

If the branch needs new `main` changes during development:

```bash
git fetch origin
git rebase origin/main
```

If rebase is risky for that slice, merge `origin/main` into the topic branch explicitly instead.

## Integrate back into `main`

First make sure the topic worktree is committed and verified (build + full test suite — the local gate).

Then, from the integration worktree, squash-merge and push directly:

```bash
git fetch origin
git pull --ff-only origin main
git merge --squash <branch-name>
git commit -m "<conventional message> (<ticket>)"
git push origin main
```

- One squash commit per coherent change, conventional message, ticket reference included.
- PRs are optional: open one only when the user explicitly asks for remote review. In that case it is ready-for-review by default; draft only on explicit request or intentional WIP, with the reason stated.

## Push policy

- Push topic branches when you want backup, review, or collaboration.
- `main` is pushed directly as part of the squash-merge integration above. Never force-push `main`.

## Cleanup

After the topic branch is merged:

```bash
git worktree remove /Users/wangruobing/Personal/open-island-<topic>
git branch -d <branch-name>
```

If the branch was pushed upstream:

```bash
git push origin --delete <branch-name>
```

## Recommended Conventions

- Keep topic names short and concrete: `codex-hooks-noise`, `island-geometry`, `claude-usage`.
- Prefer sibling directories under `/Users/wangruobing/Personal/` so all worktrees stay easy to discover.
- Do not leave long-lived unmerged worktrees drifting far away from `origin/main`.
- If a worktree becomes exploratory rather than shippable, rename the branch into `investigate/<topic>` or close it.
- When assigning work to multiple agents, split by file ownership or subsystem, not by vague goal.

## Suggested Workstream Layout

Good parallel split:

- `feat/island-visual-polish`: `Sources/OpenIslandApp/Views/*`
- `fix/codex-hook-installer`: `Sources/OpenIslandCore/CodexHookInstaller.swift`
- `investigate/jump-accuracy`: terminal jump diagnostics and docs

Bad split:

- two agents both editing `AppModel.swift`
- one branch mixing hook installer work, island UI changes, and docs cleanup
- direct feature edits on the shared `main` worktree
