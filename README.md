# Open Island

Open Island is a native, local-only macOS companion for AI coding agents. It
lives in the notch or top bar, displays local agent-session state, and can
return focus to a supported local terminal session. It has no account, server,
telemetry, updater, relay, remote runtime, or distribution service.

Open Island observes and controls only the software and files it owns. A
focused terminal or agent remains an independent application: its own network
traffic, credentials, transcripts, and permissions are not Open Island traffic
or storage.

## Install

Requires macOS 14+ and Swift 6.2 (Xcode). One command builds the release bundle
and installs it to `/Applications`, replacing any previous copy:

```bash
zsh scripts/package-local-app.sh --install
```

It signs with a local identity when available (otherwise ad-hoc) and never
uploads, notarizes, publishes, checks for updates, or contacts a service. Drop
`--install` to only build the bundle under `output/local-package/`. You may be
prompted for your password if `/Applications` is not writable.

## Develop

```bash
swift run OpenIslandApp   # canonical dev runtime (or open Package.swift in Xcode)
swift build && swift test # build and verify the current checkout
```

The package has no third-party SwiftPM dependencies, so these build only the
current checkout. For a refreshable dev bundle at `~/Applications/Open Island
Dev.app`, use `zsh scripts/launch-dev-app.sh`; run `zsh scripts/setup-dev-signing.sh`
once first for stable Accessibility/Automation grants across rebuilds. See
[docs/packaging.md](docs/packaging.md) for details.

## First launch and integrations

Session discovery reads supported local agent data and starts the private local
bridge. Hook installation is opt-in in Settings: it previews every target and
does not change ambiguous or user-owned configuration. See
[docs/hooks.md](docs/hooks.md) for consent, recovery, and uninstall behavior.

## More

[docs/index.md](docs/index.md) is the documentation map. The privacy,
data-lifecycle, architecture, and local security boundaries are documented
there in detail.
