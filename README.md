# Open Island

Native macOS companion for AI coding agents — lives in the notch / top bar, tracks your local agent sessions, and jumps you back to the right terminal or IDE. Open-source, local-first, no server.

## Requirements

- macOS 14+
- Swift 6.2 (Xcode)

## Build & run

Canonical dev runtime — build and launch the app straight from the package:

```bash
swift build                    # compile all targets
swift test                     # run the test suite
swift run OpenIslandApp        # build + launch the app
```

Or open it in Xcode and hit **Run**:

```bash
open Package.swift
```

Run the full local check suite — lint, docs, tests, and build:

```bash
zsh scripts/harness.sh ci
```

## Build a local app bundle

Create a standalone bundle and ZIP archive for local use:

```bash
zsh scripts/package-local-app.sh
```

The script writes `output/local-package/Open Island.app` and
`output/local-package/Open Island.zip`. It builds only from the current
checkout's locally available dependencies, signs locally (or ad-hoc), and does
not upload, notarize, publish, or check for updates.

For a refreshable development bundle at `~/Applications/Open Island Dev.app`,
run `zsh scripts/launch-dev-app.sh`.

### "Open Island is damaged and can't be opened"

Gatekeeper shows this for an unsigned local build. Clear the quarantine flag (dev use only):

```bash
xattr -dr com.apple.quarantine "/Applications/Open Island.app"
```

Or right-click the app → **Open** → **Open** to bypass it once. See
[docs/packaging.md](docs/packaging.md) for the local packaging contract.

## On first launch

Open Island auto-discovers your active agent sessions and starts the live bridge. Install the per-agent hooks from the in-app **Settings** window.

## More

Repository map, architecture, and deeper docs: [docs/index.md](docs/index.md).
