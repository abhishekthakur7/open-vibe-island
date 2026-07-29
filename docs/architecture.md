# Architecture

## System shape

Open Island is a single local Swift package with four products.

| Target | Role |
| --- | --- |
| `OpenIslandApp` | SwiftUI/AppKit menu-bar and island UI; owns application state, private bridge, Settings, and local actions |
| `OpenIslandCore` | Shared event models, private bridge protocol, hook management, persistence, discovery, and policy |
| `OpenIslandHooks` | Bundled helper invoked by a managed hook; reads stdin, submits a local event, and writes only protocol directives to stdout |
| `OpenIslandSetup` | Read-only command-line status/consent surface for managed hook configuration |

The supported product is the macOS `OpenIslandApp`. There is no companion
mobile product, watch product, relay, server, updater, remote endpoint, or
distribution service.

## Local-only boundary and trust boundaries

Open Island owns only its process, bundled helpers, app-owned files, and the
private local socket. An agent, terminal, or editor that Open Island observes
or focuses remains an independent process: its traffic, credentials,
transcripts, cloud behavior, and permissions are not Open Island behavior.
Open Island does not create IP sockets, load remote URLs, resolve a remote
package, or ask an external application to make a network request.

| Boundary | Data/action allowed | Protection |
| --- | --- | --- |
| Agent → helper | Hook payload on stdin; source-protocol directive on stdout only when needed | Fixed bundled helper and source enum |
| Helper/plugin → app | Bounded JSON event over private `AF_UNIX` | Safe path/mode checks, peer PID/signature, nonce proof, role capability |
| App → terminal | Probe/focus for Terminal.app, Ghostty, or iTerm2 | Immutable AppleScript template with typed local parameter |
| App → filesystem | App data and approved local agent/config roots | Fixed paths; lifecycle, owner, and symlink controls |

## Local data flow

```
Agent hook or OpenCode plugin
  │ stdin event / local plugin event
  ▼
Bundled OpenIslandHooks (fixed role) ── private Unix socket ──► BridgeServer
                                                               │
                                                               ▼
                                                        AppModel → UI
                                                               │
Agent directive (only when protocol requires it) ◄────────────┘
```

On launch, the app restores minimized session metadata, reads supported local
agent transcript sources in place, reconciles active local processes, then
starts the bridge. It does not copy source-agent transcripts into an
app-owned store. If the bridge is unavailable, the helper fails open: it emits
no directive and the agent continues under its own behavior.

The exact paths, fields, retention, user controls, and owners are in
[data-lifecycle.md](./data-lifecycle.md).

## Private IPC contract

The only bridge socket is
`~/Library/Application Support/OpenIsland/bridge.sock`. Its directory is
`0700` and its socket is `0600`; legacy `/tmp` paths and environment socket
redirects are unsupported. The protocol is newline-delimited JSON, version 2.

Before a privileged connection is usable, the server verifies the current UID,
kernel-reported peer PID, and designated code-signature requirement. It then
requires a role-specific Keychain bootstrap secret in a nonce proof. Same UID
alone is never authority. A successful proof produces a connection-bound,
60-second capability; client nonces are single-use and expire with the bounded
handshake/capability lifetime.

| Role | Permitted operations |
| --- | --- |
| `hook-event-submit` | Submit Codex, Claude-family, OpenCode, Cursor, or Gemini hook events |
| `local-status-read` | Register only local status |
| `app-internal-control` | Register app/observer state; request/resolve a local question or permission |
| `observer` | Wire compatibility only; cannot authenticate or mutate |

The server fails closed for an unsafe socket path, wrong peer/signature,
unknown/cross role, invalid proof, replay, expiration, malformed frame, or
resource exhaustion. Defaults are 256 KiB frames, JSON depth 64, 32 active
connections, 4 connections per peer, 3 malformed requests, a 5-second
handshake, 60-second idle/capability lifetime, and a 45-second request limit.
Bootstrap credentials rotate when the bridge starts or a managed helper changes
and revoke on uninstall, signature mismatch, or Reset Integrations.

## Local Automation policy

Every powerful action requires `app-internal-control`. The allowed set is
closed:

- process inspection through fixed `/bin/ps`, `/usr/sbin/lsof`, and
  `/usr/bin/pgrep` argument shapes;
- immutable AppleScript probe/focus templates for Terminal.app, Ghostty, and
  iTerm2;
- activation of an approved terminal bundle identifier;
- Finder reveal of an existing regular file or directory under approved local
  agent/config roots; and
- the two fixed System Settings privacy panes.

The process runner uses direct absolute executables with no shell, empty
environment, `/` as working directory, null stdin, 64 KiB bounded output,
short timeout, and process-group cleanup. AppleScript source is fixed;
parameters are bounded typed data passed to `on run argv` templates. Arbitrary
commands, terminal reply/injection, cmux socket actions, arbitrary AppleScript,
URLs, bundle identifiers, paths, executables, cwd, and environment are denied.

Focus restoration is supported for Terminal.app (TTY), Ghostty (terminal ID),
and iTerm2 (session ID or TTY). cmux, tmux, zellij, WezTerm, Kaku, Warp, and
all terminal command injection are deliberately unsupported Automation paths.

## Runtime no-network evidence and limitation

Release builds check their compiled no-network policy version and expected
entitlements at launch. A mismatch writes only a 1 KiB, mode-restricted local
diagnostic with a timestamp and policy code; it records no path, command,
payload, entitlement value, or user data.

`scripts/smoke-all-scenarios.sh` records a `network-observation.json` for
identity-bound harness actions. The observer follows the launched root process
and descendants with fixed `ps`/`lsof` calls, rejects unallowlisted children,
prohibited tools or remote-URL arguments, and live IP sockets. Private Unix
sockets are allowed. It does not scan or attribute traffic from a separately
running app that Open Island merely focuses.

This is passive sampling, not a privileged historical traffic recorder: a
socket that opens and closes between samples can escape observation. Static
no-network policy, deliberate negative fixtures, packaged-entitlement
inspection, and fixtures that hold test sockets across multiple samples are the
compensating controls. Owner: the maintainer running the local verification
matrix in [quality.md](./quality.md).

## UI composition

`SessionState.apply(_:)` is the pure reducer for session changes; `AppModel`
owns live state and bridge lifecycle. The island appearance is a swappable
`IslandTheme` with a stable persisted ID, shared behavior, accessibility
invariants, and slot factories for the closed pill, opened chrome, session
rows, notifications, and empty/install states. A theme changes visual tokens,
not session, hook, IPC, or Automation behavior.

## Engineering rules

- Keep UI state separate from bridge and hook transport.
- Version protocol changes and ship app/helper changes together.
- Treat hook configuration as user-owned unless exact managed provenance proves
  otherwise.
- Keep any new persistence field in the data-lifecycle matrix.
- Do not widen the local-only boundary without an explicit product and security
  decision.
