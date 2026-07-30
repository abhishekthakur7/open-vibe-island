# Halo Window Capture

This helper lists and captures one explicit, visible WindowServer window through
ScreenCaptureKit. It never captures the full desktop by default.

```sh
tools/halo_parity/capture/build.sh
tools/halo_parity/capture/bin/halo-window-capture permission
tools/halo_parity/capture/bin/halo-window-capture list --bundle-id com.abhishek.OpenIsland
tools/halo_parity/capture/bin/halo-window-capture capture \
  --window-id 123 \
  --output /absolute/path/window.png \
  --scale 2
```

## Normal-motion capture

`motion` records the exact BGRA pixel bytes delivered by `SCStream` at a
nominal 60 fps. It does not synthesize timestamps or pass frames through a
lossy or timing-rewriting video encoder.

```sh
tools/halo_parity/capture/bin/halo-window-capture motion \
  --window-id 123 \
  --output /absolute/path/run-01.frames \
  --duration-seconds 6.5 \
  --event-frame-zero neutral-motion-run-01 \
  --expected-pid 456 \
  --expected-bundle-id com.example.NeutralRenderer \
  --scale 2 \
  --crop-x 0 \
  --crop-y 0 \
  --crop-width 540 \
  --crop-height 320
```

The output directory must not already exist. Each `frame-NNNNNN.bgra` is a
tightly packed, row-major BGRA8 frame (`width * 4` bytes per row), and
`motion.json` is the closed provenance record. The same JSON is emitted on
stdout. The caller-provided event binding is attached to frame zero, defined
truthfully as the first complete frame delivered after `SCStream` starts. A
coordinator that needs a UI trigger at frame zero must arrange the trigger and
supply the binding; this helper does not inject browser or application events.

The motion sidecar schema is `1.0.0`:

- Capture identity: `captureAPI`, `captureMode`, `storageEncoding`,
  `outputDirectory`, `manifest`, requested duration, nominal frame rate, actual
  PTS span, pixel size, source crop, and scale.
- Authenticity: the resolved WindowServer `window`, active `display`, required
  expected owner PID and bundle ID, plus pre/post-stream identity and bounds
  checks. A missing/disappearing/off-screen/mismatched window fails the run.
- Timing: UTC start/end, `DispatchTime.uptimeNanoseconds` host-monotonic
  start/end, and `eventFrameZero`.
- Every delivered frame: index, filename, dimensions, packed row size,
  SHA-256 of the exact stored bytes, duplicate flag, exact
  `CMSampleBuffer` PTS value/timescale/seconds, callback host-monotonic time,
  nominal/observed interval and error, and ScreenCaptureKit status,
  display-time, scale, content-scale, content-rect, and dirty-rect attachments.
- Run statistics: duplicate count, PTS-inferred drop count, non-complete
  attachment count, conservative drop count (the greater of those two signals),
  all drop records with their PTS/status/reason, mean/min/max interval,
  standard deviation, p95 absolute interval error, and effective delivered fps.

The helper fails closed when ScreenCaptureKit supplies non-screen output,
blank/stopped window content, an invalid or missing image/PTS/status/content
rect, a pixel buffer whose size differs from the requested crop, a non-BGRA
frame, no complete frames, or a non-monotonic PTS. `idle`, `started`, and
`suspended` status attachments do not contain a complete new window frame; they
are retained as dropped-frame reasons when ScreenCaptureKit provides them.
Gaps in complete-frame PTS are independently reported as inferred drops.
Identical delivered pixel hashes are duplicates; no duplicate frames are
manufactured to fill a gap.

At 60 fps, raw BGRA capture is large: a 1080×640 frame is about 2.6 MiB before
filesystem compression. Keep motion runs task-owned and delete or archive them
only through the evidence coordinator.

The JSON result is only the WindowServer portion of an authenticity sidecar.
The coordinator must merge and verify executable, process, fixture, profile,
display, capture-helper, environment, and source hashes before accepting an
artifact as canonical.

The repository coordinator invokes the helper for one explicit window:

```sh
scripts/halo-parity/halo capture-window \
  --window-id 123 \
  --output /absolute/path/reference.png \
  --renderer in-app-browser \
  --scenario A1 \
  --profile notch-v1 \
  --expected-pid 456 \
  --expected-bundle-id com.openai.codex
```

It writes the PNG and a sibling `.authenticity.json`. Captures remain
`canonicalEligible: false` unless owner identity, locked profile dimensions,
and crop provenance are all supplied and proven. Queue or plan creation is
never treated as a completed capture.

Native captures additionally require the Swift-generated, nested capture
manifest:

```sh
scripts/halo-parity/halo capture-window \
  --window-id 123 \
  --output /absolute/path/native.png \
  --renderer open-island-app \
  --scenario A3 \
  --profile notch-v1 \
  --native-sidecar /absolute/path/halo-parity-capture-manifest.json \
  --profile-crop-proven
```

For native evidence, command-line PID and bundle hints are not authoritative.
The coordinator derives identity from the manifest's nested `process` object,
then requires it to match the ScreenCaptureKit WindowServer owner. It also
rehashes the executable at `executable.path`, checks the Mach-O build UUID and
Git revision formats, verifies fixture and live-data isolation attestations,
and matches resolved placement geometry to the captured window. Flat legacy
sidecars and manual-motion diagnostics are rejected.

If an event was requested, the supplied native manifest must also contain an
`acknowledgedEvents` array, or a nested `state.acknowledgedEvents` array, that
exactly acknowledges that event. The current Swift writer emits the state dump
as a separate file, so callers must truthfully merge that acknowledgement into
the capture manifest before event evidence can be accepted.
