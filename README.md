<p align="center">
  <img src="docs/images/readme-banner.svg" alt="Open Island - agents in your menu bar" width="760">
</p>

<h1 align="center">Open Island</h1>

<p align="center">
  <strong>Keep an eye on your AI coding agents — right from the notch.</strong>
  <br>
  Open-source, local-first, native macOS. No server, no account, no telemetry.
</p>

<p align="center">
  <a href="https://github.com/Octane0411/open-vibe-island/releases/latest"><img src="https://img.shields.io/github/v/release/Octane0411/open-vibe-island?style=flat-square&label=release&color=blue" alt="Latest Release"></a>
  <a href="https://github.com/Octane0411/open-vibe-island/stargazers"><img src="https://img.shields.io/github/stars/Octane0411/open-vibe-island?style=flat-square&color=yellow" alt="Stars"></a>
  <a href="https://discord.gg/bPF2HpbCFb"><img src="https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord" alt="Discord"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL%20v3-green?style=flat-square" alt="License: GPL v3"></a>
</p>

<p align="center">
  <a href="https://github.com/Octane0411/open-vibe-island/releases">Download</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="docs/roadmap.md">Roadmap</a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" alt="Open Island in action" width="720">
</p>

---

## What is Open Island?

Open Island lives in your Mac's **notch** (or top bar) and gives you a real-time view of every AI coding agent you run — session status, permission prompts, and one-click jump-back to the exact terminal or IDE, without breaking your flow.

It's an open-source alternative to [Vibe Island](https://vibeisland.app/): free, local-first, and yours to modify.

## Why Open Island?

- **Open source** — GPL v3. Fork it, mod it, ship your own version.
- **Local-first** — No server, no telemetry, no account. Everything runs on your Mac.
- **Native macOS** — SwiftUI + AppKit, not an Electron wrapper.
- **Multi-agent** — One surface for Claude Code, Codex, Cursor, Gemini CLI, OpenCode, and more.
- **Multi-terminal** — Jump back to the exact terminal or IDE session in one click.

## Supported Agents & Terminals

**10 agents**: Claude Code, Codex, Cursor, Gemini CLI, Kimi CLI, OpenCode, Qoder, Qwen Code, Factory, CodeBuddy

**15+ terminals & IDEs**: Terminal.app, Ghostty, iTerm2, WezTerm, Zellij, tmux, cmux, Kaku, Warp, VS Code, Cursor, Windsurf, Trae, JetBrains IDEs (IDEA, WebStorm, PyCharm, GoLand, CLion, RubyMine, PhpStorm, Rider, RustRover)

<details>
<summary>Full compatibility table</summary>

### Code Agents

| Agent | Status | Description |
|---|---|---|
| **Claude Code** | Supported | Hook integration, JSONL session discovery, status line bridge, usage tracking |
| **Claude Code (Desktop App)** | Supported | Same hooks as the CLI. Claude Desktop runs Claude Code as a TTY-less subprocess invisible to process discovery, so liveness follows the running desktop app (like Codex.app); jump-back activates Claude. Usage panel is account-wide but seeded by the CLI status line — see note below |
| **Codex** (CLI) | Supported | Hook integration (SessionStart, UserPromptSubmit, Stop by default; PreToolUse/PostToolUse parseable but not default), usage tracking |
| **Codex Desktop App** | Supported | Hook integration + app-server JSON-RPC connection for real-time thread/turn lifecycle. Precise conversation jump via `codex://threads/<id>` deep-link |
| **OpenCode** | Supported | JS plugin integration, permission/question flows, process detection |
| **Qoder** | Supported | Claude Code fork — same hook format, config at `~/.qoder/settings.json` |
| **Qwen Code** | Supported | Claude Code fork — same hook format, config at `~/.qwen/settings.json` |
| **Factory** | Supported | Claude Code fork — same hook format, config at `~/.factory/settings.json` |
| **CodeBuddy** | Supported | Claude Code fork — same hook format, config at `~/.codebuddy/settings.json` |
| **Cursor** | Supported | Hook integration via `~/.cursor/hooks.json`, session tracking, workspace jump-back |
| **Gemini CLI** | Supported | Hook integration via `~/.gemini/settings.json`, session tracking, fire-and-forget events |
| **Kimi CLI** | Supported | Hook integration via `~/.kimi/config.toml` `[[hooks]]`, session tracking, permission flow (reuses Claude payload) |

### Terminals & IDEs

| Terminal / IDE | Support Level | Description |
|---|---|---|
| **Terminal.app** | Full | Jump-back with TTY targeting |
| **Ghostty** | Full | Jump-back with ID matching |
| **cmux** | Full | Jump-back via Unix socket API |
| **Kaku** | Full | Jump-back via CLI pane targeting |
| **WezTerm** | Full | Jump-back via CLI pane targeting |
| **iTerm2** | Full | Jump-back with session ID / TTY matching |
| **tmux** (multiplexer) | Full | Jump-back with session/window/pane targeting |
| **Zellij** | Full | Jump-back via CLI pane/tab targeting |
| **VS Code** | Workspace | Activate workspace via `code` CLI |
| **Cursor** | Workspace | Activate workspace via `cursor` CLI |
| **Windsurf** | Workspace | Activate workspace via `windsurf` CLI |
| **Trae** | Workspace | Activate workspace via `trae` CLI |
| **JetBrains IDEs** | Workspace | IDEA, WebStorm, PyCharm, GoLand, CLion, RubyMine, PhpStorm, Rider, RustRover |
| **Warp** | Full | Precision tab jump via SQLite pane lookup + AX menu click |

### Other Features

| Feature | Description |
|---|---|
| Notch / top-bar overlay | Notch area on notch Macs, top-center bar on others |
| Settings | Hook install/uninstall, usage dashboard |
| Notification mode | Auto-height panel for permission requests and session events |
| Notification sounds | Configurable system sounds, mute toggle |
| i18n | English, Simplified Chinese |
| Session discovery | Auto-discover from local transcripts, persist across launches |
| Auto-update | Sparkle-based automatic updates |
| Signed & notarized | DMG packaging with Apple notarization |

</details>

## Quick Start

### Option 1: Download

Grab the latest DMG from [GitHub Releases](https://github.com/Octane0411/open-vibe-island/releases) — signed and notarized, ready to run.

### Option 2: Homebrew

```bash
brew install --cask open-island
```

Upgrade later with `brew upgrade --cask open-island`.

### Option 3: Build from source

```bash
git clone https://github.com/Octane0411/open-vibe-island.git
cd open-vibe-island
open Package.swift   # Opens in Xcode — hit Run
```

On first launch, Open Island auto-discovers your active agent sessions and starts the live bridge. Install hooks from the in-app **Settings** window.

> **Requirements**: macOS 14+, Swift 6.2, Xcode

## How It Works

```
Agent (Claude Code / Codex / Cursor / ...)
  ↓ hook event
OpenIslandHooks CLI (stdin → Unix socket)
  ↓ JSON envelope
BridgeServer (in-app)
  ↓ state update
Notch overlay UI ← you see it here
  ↓ click
Jump back → correct terminal / IDE
```

Hooks **fail open** — if Open Island isn't running, your agents continue unaffected.

<details>
<summary>Architecture details</summary>

Four targets in one Swift package:

| Target | Role |
|---|---|
| **OpenIslandApp** | SwiftUI + AppKit shell — menu bar, overlay panel, settings |
| **OpenIslandCore** | Shared library — models, bridge transport (Unix socket IPC), hooks, session persistence |
| **OpenIslandHooks** | Lightweight CLI invoked by agent hooks, forwards payloads via Unix socket |
| **OpenIslandSetup** | Installer CLI for managing `~/.codex/config.toml` and hook entries |

See [docs/architecture.md](docs/architecture.md) for the full system design.

</details>

## Development

Contributions welcome. Build and run:

```bash
swift build && swift test
swift run OpenIslandApp        # canonical dev runtime
zsh scripts/harness.sh ci      # what CI runs: lint, docs, tests, build
```

Where to look next:

- [docs/index.md](docs/index.md) — repository map for humans and agents
- [docs/architecture.md](docs/architecture.md) — runtime shape and transport boundaries
- [docs/hooks.md](docs/hooks.md) — hook events, payloads, and per-agent `--source` flags

## Community

Join us on **Discord** for discussion, feedback, and faster issue resolution:

[![Discord](https://img.shields.io/discord/1490752192368476253?style=for-the-badge&logo=discord&label=Join%20Discord&color=5865F2)](https://discord.gg/bPF2HpbCFb)

We welcome issues, pull requests, and new maintainers — open an issue or PR to get started.

<details>
<summary>WeChat group (for Chinese-speaking users)</summary>

<img src="docs/images/wechat-group.jpg" alt="WeChat group QR code" width="240">

</details>

## Report a Bug via Your Code Agent

Copy this prompt into your agent (Claude Code, Codex, etc.) to auto-generate a well-structured issue:

<details>
<summary>Click to expand</summary>

```
I'm having an issue with Open Island (https://github.com/Octane0411/open-vibe-island).

Please help me file a GitHub issue. Do the following:

1. Collect my environment info:
   - Run `sw_vers` to get macOS version
   - Run `swift --version` to get Swift version
   - Check if Open Island is running: `ps aux | grep -i "open.island\|OpenIslandApp" | grep -v grep`
   - Get the app version: `defaults read ~/Applications/Open\ Island\ Dev.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "unknown"`
   - Check which terminal I'm using

2. Ask me to describe:
   - What I expected to happen
   - What actually happened
   - Steps to reproduce

3. Create the issue on GitHub using `gh issue create` with this format:
   - Title: concise summary
   - Body with sections: **Environment**, **Description**, **Steps to Reproduce**, **Expected vs Actual Behavior**
   - Add label "bug" if applicable

Repository: Octane0411/open-vibe-island
```

</details>

## Star History

<a href="https://star-history.com/#Octane0411/open-vibe-island&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=Octane0411/open-vibe-island&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=Octane0411/open-vibe-island&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=Octane0411/open-vibe-island&type=Date" />
 </picture>
</a>

## Contributors

<a href="https://github.com/Octane0411/open-vibe-island/graphs/contributors">
  <!-- CONTRIBUTORS-IMG:START -->
  <img src="https://contrib.rocks/image?repo=Octane0411/open-vibe-island&t=1783932921" />
  <!-- CONTRIBUTORS-IMG:END -->
</a>

---

## License

[GPL v3](LICENSE)
