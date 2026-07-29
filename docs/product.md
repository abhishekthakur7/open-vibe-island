# Product Scope

## Product boundary

Open Island is one local macOS product: `OpenIslandApp`. It gives developers a
native notch/top-bar surface for local AI coding-agent sessions, local approval
and question flows, and safe return-to-terminal focus. It has no mobile,
watch, relay, account, server, telemetry, updater, remote control, CI service,
or public-distribution runtime.

“Local-only” applies to behavior Open Island owns. When it focuses an existing
terminal, editor, or agent, that application remains independent. Open Island
does not request network activity from it and does not claim its traffic,
credentials, files, or cloud synchronization as its own.

## Product principles

- **Local by construction** — repository-owned code has no network entitlement,
  remote package dependency, or remote runtime endpoint.
- **Explicit integration** — managed hooks require a Settings confirmation and
  preserve ambiguous or user-owned configuration unchanged.
- **Fail closed for privileged work** — the bridge and Automation policy deny
  unknown roles, sources, paths, URLs, scripts, and commands.
- **Fail open for agents** — a missing bridge does not make an agent unusable.
- **Reversible local state** — Clear History and Reset Integrations have
  separate, documented scopes.

## Supported local integrations

The supported agent integrations are Claude Code and its listed compatible
forks, Codex CLI, Cursor, OpenCode, Gemini CLI, and Kimi CLI. Their exact
events and installation states are in [hooks.md](./hooks.md). Compatibility
classification of another terminal is not permission to control it.

## Supported jump-back actions

Only the following focus paths are implemented: Terminal.app by TTY, Ghostty
by terminal ID, and iTerm2 by session ID or TTY. They use immutable
AppleScript templates with typed local parameters. cmux, tmux, zellij, WezTerm,
Kaku, Warp, and terminal command/reply injection are not supported local
Automation actions.

## Features

- Notch overlay with a compact top-center fallback
- Local session discovery and a private Unix-domain bridge
- Settings for consented hook management, history clearing, and integration
  reset
- Local notification and sound preferences
- English and Simplified Chinese UI
- Local bundle packaging for developer-controlled installation

## Non-goals

Open Island does not provide a remote dashboard, collaborative relay, mobile
companion, automatic updating, release channel, hosted build system, terminal
command injection, arbitrary AppleScript, generic URL opening, or arbitrary
file access. A future change to any of those boundaries requires an explicit
product and security review.
