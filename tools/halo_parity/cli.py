from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

from . import __version__
from .authenticity import validate_native_provenance, verify_authenticity_file
from .calibration import (
    analyze_neutral_manifest,
    threshold_proposal,
    validate_neutral_renderer_manifest,
)
from .masks import (
    MASK_SET_VERSION,
    PROFILE_LOGICAL_DIMENSIONS,
    generate_masks,
    verify_mask_manifest,
)
from .core import (
    ARTIFACT_ROOT,
    CALIBRATION_ROOT,
    DISPLAY_PROFILES,
    EXPECTED_SCENARIO_COUNT,
    MEASUREMENT_SPEC,
    REFERENCE_AUTHORITY,
    REFERENCE_ROOT,
    REPOSITORY_ROOT,
    SCENARIO_MANIFEST,
    Check,
    ParityError,
    canonical_json_bytes,
    environment_fingerprint,
    evidence_index,
    git_commit,
    git_dirty,
    make_spec_lock,
    make_gate_0a_authority_projection,
    read_json,
    read_strict_json,
    run,
    sha256_bytes,
    sha256_file,
    strict_json_loads,
    utc_now,
    validate_gate_0a_authority_projection,
    validate_measurement_spec,
    validate_profiles,
    validate_reference_authority,
    validate_scenario_manifest,
    write_json,
)

GATE_0A_APPROVAL_SCOPE = "reference-authoring-and-display-profile-authority"
GATE_0A_APPROVAL_STATEMENTS = {
    "authoringProfileAuthorityOnly": True,
    "noScenarioPass": True,
    "notGate7Approval": True,
    "noGoldens": True,
}
GATE_0A_DIRECT_USER_APPROVAL_METHOD = "codex-user-message"


def _path(value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return REPOSITORY_ROOT / path


def _print(value: Any) -> None:
    if isinstance(value, str):
        print(value)
    else:
        print(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False))


def _result(
    command: str,
    checks: list[Check],
    *,
    output: Path | None = None,
    metadata: dict[str, Any] | None = None,
) -> int:
    failed = [check for check in checks if not check.passed and check.hard]
    value = {
        "schemaVersion": "1.0.0",
        "command": command,
        "createdAt": utc_now(),
        "passed": not failed,
        "checks": [check.as_json() for check in checks],
        "metadata": metadata or {},
    }
    if output:
        write_json(output, value)
    _print(value)
    return 0 if not failed else 1


def command_doctor(args: argparse.Namespace) -> int:
    checks: list[Check] = []
    for path, name in (
        (SCENARIO_MANIFEST, "scenario manifest"),
        (MEASUREMENT_SPEC, "measurement specification"),
        (DISPLAY_PROFILES, "display profile lock"),
    ):
        checks.append(Check(name, path.is_file(), str(path)))
    for executable in ("git", "python3", "swift", "xcodebuild", "ffmpeg", "ssh-keygen"):
        resolved = shutil.which(executable)
        checks.append(Check(f"tool:{executable}", bool(resolved), resolved or "not found"))
    capture_source = (
        REPOSITORY_ROOT
        / "tools"
        / "halo_parity"
        / "capture"
        / "HaloWindowCapture.swift"
    )
    checks.append(
        Check("ScreenCaptureKit helper source", capture_source.is_file(), str(capture_source))
    )
    try:
        manifest_summary = validate_scenario_manifest(
            read_json(SCENARIO_MANIFEST),
            require_exact=False,
        )
        checks.append(
            Check(
                "57-row manifest",
                manifest_summary["scenarioCount"] == EXPECTED_SCENARIO_COUNT,
                json.dumps(manifest_summary["dispositions"], sort_keys=True),
            )
        )
    except ParityError as error:
        checks.append(Check("57-row manifest", False, str(error)))
    try:
        validate_measurement_spec(read_json(MEASUREMENT_SPEC))
        checks.append(Check("frozen measurement contract", True, str(MEASUREMENT_SPEC)))
    except ParityError as error:
        checks.append(Check("frozen measurement contract", False, str(error)))
    try:
        profile_summary = validate_profiles(
            read_json(DISPLAY_PROFILES),
            require_approval=not args.allow_unapproved,
        )
        checks.append(
            Check(
                "display profiles",
                True,
                json.dumps(profile_summary, sort_keys=True),
            )
        )
    except ParityError as error:
        checks.append(
            Check(
                "display profiles",
                False,
                str(error),
                hard=not args.allow_unapproved,
            )
        )
    fingerprint = environment_fingerprint()
    return _result(
        "doctor",
        checks,
        output=_path(args.output) if args.output else None,
        metadata={"environment": fingerprint, "allowUnapproved": args.allow_unapproved},
    )


def command_freeze_spec(args: argparse.Namespace) -> int:
    lock = make_spec_lock(allow_unapproved=args.allow_unapproved)
    output = (
        _path(args.output)
        if args.output
        else CALIBRATION_ROOT / f"bootstrap-spec-lock-{args.version}.json"
    )
    write_json(output, lock)
    _print({"written": str(output), "lockSha256": lock["lockSha256"]})
    return 0


def command_build_reference(args: argparse.Namespace) -> int:
    builder = REFERENCE_ROOT / "build-reference-harness.mjs"
    if not builder.is_file():
        raise ParityError(f"reference builder is not available: {builder}")
    completed = run(["node", str(builder)])
    print(completed.stdout, end="")
    return 0


def command_serve_reference(args: argparse.Namespace) -> int:
    os.chdir(REPOSITORY_ROOT)
    server = ThreadingHTTPServer((args.host, args.port), SimpleHTTPRequestHandler)
    print(f"Serving Halo reference harness on http://{args.host}:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


def _scenario_profile_records() -> list[dict[str, Any]]:
    manifest = read_json(SCENARIO_MANIFEST)
    profiles = read_json(DISPLAY_PROFILES)["profiles"]
    records = []
    for scenario in manifest["scenarios"]:
        for profile in profiles:
            records.append(
                {
                    "scenarioId": scenario["id"],
                    "profileId": profile["id"],
                    "result": "pending",
                }
            )
    return records


def _validate_reference_queue(queue: dict[str, Any]) -> list[dict[str, Any]]:
    records = queue.get("records")
    if not isinstance(records, list):
        raise ParityError("capture queue must contain a records array")
    expected = {
        (record["id"], profile["id"])
        for record in read_json(SCENARIO_MANIFEST)["scenarios"]
        for profile in read_json(DISPLAY_PROFILES)["profiles"]
    }
    actual: list[tuple[str, str]] = []
    for record in records:
        if not isinstance(record, dict):
            raise ParityError("capture queue records must be objects")
        pair = (record.get("scenarioId"), record.get("profileId"))
        actual.append(pair)
        if record.get("result") != "pending":
            raise ParityError(f"capture queue record {pair} is not pending")
        if record.get("renderer") not in (None, "in-app-browser"):
            raise ParityError(f"capture queue record {pair} has the wrong renderer")
    if len(actual) != len(expected) or set(actual) != expected or len(set(actual)) != len(actual):
        raise ParityError(
            "capture queue must contain each of the 114 scenario/profile pairs exactly once"
        )
    return records


def _png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ParityError("capture helper output is not a PNG")
    return struct.unpack(">II", header[16:24])


def command_queue_reference(args: argparse.Namespace) -> int:
    base_url = args.base_url.rstrip("/")
    records = _scenario_profile_records()
    for record in records:
        query = urlencode(
            {
                "haloParity": "1",
                "scenario": record["scenarioId"],
                "profile": record["profileId"],
                "motion": "manual",
                "a11y": "default",
                "seed": "0",
                "time": "0",
            }
        )
        record["url"] = (
            f"{base_url}/Validation/HaloParity/reference/generated/"
            f"halo-reference-v1.html?{query}"
        )
        record["renderer"] = "in-app-browser"
        record["canonicalRequired"] = "live-window"
    queue = {
        "schemaVersion": "1.0.0",
        "createdAt": utc_now(),
        "commitSha": git_commit(),
        "browserRequirement": "in-app-browser",
        "screenshotAPIStatus": "jpeg-corroboration-only",
        "records": records,
    }
    queue["queueSha256"] = sha256_bytes(canonical_json_bytes(queue))
    output = _path(args.output)
    write_json(output, queue)
    _print({"written": str(output), "recordCount": len(records)})
    return 0


def command_capture_plan(args: argparse.Namespace) -> int:
    queue_path = _path(args.queue)
    queue = read_json(queue_path)
    records = _validate_reference_queue(queue)
    renderer = args.capture_command.replace("capture-", "")
    plan = {
        "schemaVersion": "1.0.0",
        "renderer": "in-app-browser" if renderer == "reference" else "open-island-app",
        "captureMode": "live-window",
        "captureAPI": "ScreenCaptureKit",
        "queueSha256": sha256_file(queue_path),
        "recordCount": len(records),
        "status": "awaiting-window-capture",
        "strict": args.strict,
    }
    if args.strict:
        raise ParityError(
            f"{args.capture_command} strict mode requires completed live-window "
            "authenticity sidecars; queue creation alone is not capture"
        )
    output = _path(args.output)
    write_json(output, plan)
    _print({"written": str(output), **plan})
    return 0


def _profile(profile_id: str) -> dict[str, Any]:
    for profile in read_json(DISPLAY_PROFILES)["profiles"]:
        if profile["id"] == profile_id:
            return profile
    raise ParityError(f"unknown display profile: {profile_id}")


def command_capture_window(args: argparse.Namespace) -> int:
    output = _path(args.output).resolve()
    sidecar_path = (
        _path(args.sidecar).resolve()
        if args.sidecar
        else output.with_suffix(".authenticity.json")
    )
    helper = (
        _path(args.helper).resolve()
        if args.helper
        else REPOSITORY_ROOT
        / "tools"
        / "halo_parity"
        / "capture"
        / "bin"
        / "halo-window-capture"
    )
    if not helper.is_file():
        raise ParityError(f"capture helper is not built: {helper}")
    profile = _profile(args.profile)
    native_path = _path(args.native_sidecar) if args.native_sidecar else None
    native = read_json(native_path) if native_path else None
    calibration_path = (
        _path(args.calibration_manifest) if args.calibration_manifest else None
    )
    native_expectations: dict[str, Any] | None = None
    if args.renderer == "open-island-app":
        if native_path is None:
            raise ParityError(
                "open-island-app capture requires --native-sidecar provenance"
            )
        native_validation_arguments: dict[str, Any] = {}
        if args.expected_native_event is not None:
            native_validation_arguments["expected_event"] = args.expected_native_event
        validate_native_provenance(
            native,
            native_sidecar_path=native_path,
            scenario_id=args.scenario,
            profile_id=args.profile,
            expected_theme=args.expected_native_theme,
            expected_motion=args.expected_native_motion,
            expected_accessibility=args.expected_native_accessibility,
            **native_validation_arguments,
        )
        expected_pid = native["process"]["pid"]
        expected_bundle = native["process"]["bundleId"]
        native_expectations = {
            "scenarioId": args.scenario,
            "profileId": args.profile,
            "resolvedThemeID": args.expected_native_theme or "halo",
            "motion": args.expected_native_motion or native["motion"],
            "accessibility": (
                args.expected_native_accessibility or native["accessibility"]
            ),
            "event": (
                args.expected_native_event
                if args.expected_native_event is not None
                else native.get("event")
            ),
        }
        if native["executable"]["sourceTreeDirty"]:
            native_expectations["sourceTreeDirty"] = True
    else:
        expected_pid = args.expected_pid
        expected_bundle = args.expected_bundle_id
    if args.renderer == "native-swiftui-calibration" and calibration_path is None:
        raise ParityError(
            "native-swiftui-calibration capture requires --calibration-manifest"
        )
    crop_values = (
        args.crop_x,
        args.crop_y,
        args.crop_width,
        args.crop_height,
    )
    supplied_crop_count = sum(value is not None for value in crop_values)
    if supplied_crop_count not in (0, 4):
        raise ParityError(
            "all four --crop-x/--crop-y/--crop-width/--crop-height values are required"
        )
    helper_command = [
        str(helper),
        "capture",
        "--window-id",
        str(args.window_id),
        "--output",
        str(output),
        "--scale",
        str(profile["backingScale"]),
    ]
    if supplied_crop_count == 4:
        helper_command.extend(
            [
                "--crop-x",
                str(args.crop_x),
                "--crop-y",
                str(args.crop_y),
                "--crop-width",
                str(args.crop_width),
                "--crop-height",
                str(args.crop_height),
            ]
        )
    completed = run(helper_command, check=False)
    if completed.returncode != 0:
        raise ParityError(
            f"ScreenCaptureKit helper failed ({completed.returncode}):\n{completed.stdout}"
        )
    try:
        helper_result = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise ParityError(f"capture helper returned invalid JSON: {error}") from error
    if not output.is_file():
        raise ParityError("capture helper reported success without writing the PNG")
    png_width, png_height = _png_dimensions(output)
    if (
        helper_result.get("pixelWidth") != png_width
        or helper_result.get("pixelHeight") != png_height
    ):
        raise ParityError(
            "capture helper pixel dimensions do not match the written PNG: "
            f"reported={helper_result.get('pixelWidth')}x{helper_result.get('pixelHeight')} "
            f"actual={png_width}x{png_height}"
        )
    window = helper_result.get("window")
    source_rect = helper_result.get("sourceRect")
    capture_timing = helper_result.get("captureTiming")
    if (
        helper_result.get("captureAPI") != "ScreenCaptureKit"
        or helper_result.get("captureMode") != "live-window"
        or not isinstance(window, dict)
        or not isinstance(source_rect, dict)
        or window.get("cgWindowId") != args.window_id
        or window.get("isOnScreen") is not True
    ):
        raise ParityError("capture helper result is not an explicit live-window capture")
    if args.renderer == "native-swiftui-calibration":
        if (
            not isinstance(capture_timing, dict)
            or not isinstance(capture_timing.get("startedAt"), str)
            or not isinstance(capture_timing.get("completedAt"), str)
            or not isinstance(capture_timing.get("monotonicStartNanoseconds"), str)
            or not isinstance(capture_timing.get("monotonicEndNanoseconds"), str)
            or isinstance(capture_timing.get("durationMilliseconds"), bool)
            or not isinstance(capture_timing.get("durationMilliseconds"), (int, float))
            or capture_timing["durationMilliseconds"] < 0
        ):
            raise ParityError(
                "native neutral calibration capture requires helper timing provenance"
            )
    expected_source_rect = (
        {
            "x": args.crop_x,
            "y": args.crop_y,
            "width": args.crop_width,
            "height": args.crop_height,
        }
        if supplied_crop_count == 4
        else {
            "x": 0,
            "y": 0,
            "width": window.get("bounds", {}).get("width"),
            "height": window.get("bounds", {}).get("height"),
        }
    )
    if any(
        source_rect.get(field) != expected_source_rect[field]
        for field in ("x", "y", "width", "height")
    ):
        raise ParityError(
            "capture helper source rectangle does not match the requested live-window crop"
        )
    reasons: list[str] = []
    if expected_pid is None:
        reasons.append("expected window owner PID was not supplied")
    elif window.get("ownerPid") != expected_pid:
        raise ParityError(
            f"window owner PID mismatch: expected {expected_pid}, got {window.get('ownerPid')}"
        )
    if not expected_bundle:
        reasons.append("expected window owner bundle ID was not supplied")
    elif window.get("ownerBundleId") != expected_bundle:
        raise ParityError(
            "window owner bundle mismatch: expected "
            f"{expected_bundle}, got {window.get('ownerBundleId')}"
        )
    expected_point_width = profile["pointSize"]["width"]
    expected_pixel_width = profile["pixelSize"]["width"]
    if source_rect.get("width") != expected_point_width:
        reasons.append(
            f"window width does not prove {args.profile}: "
            f"{source_rect.get('width')}pt != {expected_point_width}pt"
        )
    if helper_result.get("pixelWidth") != expected_pixel_width:
        reasons.append(
            f"pixel width does not prove {args.profile}: "
            f"{helper_result.get('pixelWidth')}px != {expected_pixel_width}px"
        )
    crop_geometry_proven = (
        source_rect.get("width") == expected_point_width
        and helper_result.get("pixelWidth") == expected_pixel_width
    )
    calibration_manifest: dict[str, Any] | None = None
    if args.renderer == "native-swiftui-calibration":
        calibration_manifest = validate_neutral_renderer_manifest(
            calibration_path,
            profile_id=args.profile,
            window=window,
            expected_point_width=expected_point_width,
            expected_pixel_width=expected_pixel_width,
        )
    if not args.profile_crop_proven or not crop_geometry_proven:
        reasons.append("profile crop provenance was not explicitly proven")
    # A dirty source tree is retained as explicit native provenance, but it is
    # not a capture-authenticity failure. The evidence bundle binds the exact
    # executable and task-owned source/artifact hashes; requiring a commit here
    # would make faithful validation of the user's preserved worktree impossible.
    if args.renderer == "open-island-app":
        validate_native_provenance(
            native,
            native_sidecar_path=native_path,
            scenario_id=args.scenario,
            profile_id=args.profile,
            window=window,
            expected_theme=native_expectations["resolvedThemeID"],
            expected_motion=native_expectations["motion"],
            expected_accessibility=native_expectations["accessibility"],
            expected_event=native_expectations["event"],
        )
    canonical_eligible = not reasons
    try:
        artifact_path = str(output.relative_to(sidecar_path.parent))
    except ValueError:
        artifact_path = str(output)
    record: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "renderer": args.renderer,
        "captureMode": "live-window",
        "captureAPI": "ScreenCaptureKit",
        "result": "captured",
        "canonicalEligible": canonical_eligible,
        "canonicalIneligibilityReasons": reasons,
        "artifactPath": artifact_path,
        "artifactSha256": sha256_file(output),
        "profileId": args.profile,
        "scenarioId": args.scenario,
        "onScreen": True,
        "proxyRenderer": False,
        "pixelSize": {
            "width": helper_result.get("pixelWidth"),
            "height": helper_result.get("pixelHeight"),
        },
        "window": window,
        "captureHelper": {
            "path": str(helper),
            "sha256": sha256_file(helper),
        },
        "captureTiming": capture_timing,
        "profileValidation": {
            "expectedPointWidth": expected_point_width,
            "expectedPixelWidth": expected_pixel_width,
            "cropProven": args.profile_crop_proven and crop_geometry_proven,
            "captureRectSource": (
                "explicit-live-window-source-rect"
                if supplied_crop_count == 4
                else "full-live-window"
            ),
            "sourceRectPoints": source_rect,
            "windowBoundsPoints": window.get("bounds"),
        },
    }
    if args.renderer == "open-island-app":
        record["nativeSidecar"] = native
        record["nativeExpectations"] = native_expectations
    if args.renderer == "native-swiftui-calibration":
        executable = Path(calibration_manifest["process"]["executablePath"]).resolve()
        record["calibrationRenderer"] = {
            "manifestPath": str(calibration_path),
            "manifestSha256": sha256_file(calibration_path),
            "executablePath": str(executable),
            "executableSha256": sha256_file(executable),
            "suiteId": calibration_manifest["suiteId"],
            "contentRole": calibration_manifest["contentRole"],
            "mode": calibration_manifest["mode"],
            "timeMilliseconds": calibration_manifest["timeMilliseconds"],
            "display": calibration_manifest["display"],
            "mapping": calibration_manifest["mapping"],
        }
    write_json(sidecar_path, record)
    _print(
        {
            "written": str(output),
            "sidecar": str(sidecar_path),
            "result": "captured",
            "canonicalEligible": canonical_eligible,
            "canonicalIneligibilityReasons": reasons,
        }
    )
    return 0


def command_verify_authenticity(args: argparse.Namespace) -> int:
    result = verify_authenticity_file(
        _path(args.sidecar),
        expected_renderer=args.renderer,
        require_canonical=args.require_canonical,
    )
    _print(result)
    return 0


def command_calibrate_capture(args: argparse.Namespace) -> int:
    suite = read_json(_path(args.suite))
    if suite.get("contentRole") != "neutral-calibration":
        raise ParityError("calibration suite must be neutral-calibration")
    queue = {
        "schemaVersion": "1.0.0",
        "contentRole": "neutral-calibration",
        "suiteSha256": sha256_file(_path(args.suite)),
        "createdAt": utc_now(),
        "status": "pending-capture",
        "records": suite.get("captureMatrix", []),
    }
    output = _path(args.output)
    write_json(output, queue)
    _print({"written": str(output), "recordCount": len(queue["records"])})
    return 0


def command_calibrate_analyze(args: argparse.Namespace) -> int:
    report = analyze_neutral_manifest(_path(args.manifest))
    output = _path(args.output)
    write_json(output, report)
    _print({"written": str(output), "groupCount": len(report["groups"])})
    return 0


def command_calibrate_freeze(args: argparse.Namespace) -> int:
    report = read_json(_path(args.report))
    if report.get("contentRole") != "neutral-calibration":
        raise ParityError("thresholds may be frozen only from neutral-calibration")
    proposal = threshold_proposal(report, version=args.version)
    if args.approved:
        proposal["status"] = "frozen"
        proposal["approval"] = read_json(_path(args.approved))
    output = _path(args.output)
    write_json(output, proposal)
    _print({"written": str(output), "status": proposal["status"]})
    return 0 if proposal["status"] == "frozen" else 1


def command_calibrate_masks(args: argparse.Namespace) -> int:
    profile_width, profile_height = PROFILE_LOGICAL_DIMENSIONS[args.profile]
    manifest_path = generate_masks(
        annotations=read_strict_json(_path(args.annotations)),
        profile={
            "id": args.profile,
            "logicalSize": {
                "width": profile_width,
                "height": profile_height,
            },
            "backingScale": 2,
        },
        neutral_transform=read_strict_json(_path(args.neutral_transform)),
        output_dir=_path(args.output_dir),
    )
    result = verify_mask_manifest(manifest_path)
    _print({"written": str(manifest_path), "verification": result})
    return 0


def command_baseline_capture(args: argparse.Namespace) -> int:
    records = _scenario_profile_records()
    queue = {
        "schemaVersion": "1.0.0",
        "createdAt": utc_now(),
        "commitSha": git_commit(),
        "status": "pending-canonical-capture",
        "requiredRenderers": ["in-app-browser", "open-island-app"],
        "records": records,
    }
    output = _path(args.output)
    write_json(output, queue)
    _print({"written": str(output), "recordCount": len(records)})
    return 0


def command_baseline_report(args: argparse.Namespace) -> int:
    root = _path(args.evidence_root)
    index = evidence_index(root)
    output = root / "evidence-index.json"
    write_json(output, index)
    queue = read_json(_path(args.queue))
    queue_records = _validate_reference_queue(queue)
    expected_keys = {
        (renderer, record["scenarioId"], record["profileId"])
        for renderer in ("in-app-browser", "open-island-app")
        for record in queue_records
    }
    expected = len(expected_keys)
    accepted: list[dict[str, Any]] = []
    rejected: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for sidecar in sorted(root.rglob("*authenticity.json")):
        try:
            result = verify_authenticity_file(sidecar, require_canonical=True)
            key = (result["renderer"], result["scenarioId"], result["profileId"])
            if key in seen:
                raise ParityError(f"duplicate canonical authenticity record: {key}")
            seen.add(key)
            accepted.append({"path": str(sidecar), **result})
        except ParityError as error:
            rejected.append({"path": str(sidecar), "error": str(error)})
    report = {
        "schemaVersion": "1.0.0",
        "reportType": "gate-0c-baseline-completeness",
        "createdAt": utc_now(),
        "expectedRendererScenarioProfileRecords": expected,
        "acceptedAuthenticitySidecars": len(accepted),
        "rejectedAuthenticitySidecars": rejected,
        "complete": seen == expected_keys and not rejected,
        "evidenceIndexSha256": index["indexSha256"],
        "parityResult": "not-evaluated",
    }
    report_path = root / "reports" / "gate-0c-baseline.json"
    write_json(report_path, report)
    _print({"written": str(report_path), **report})
    return 0 if report["complete"] else 1


def _gate_0a_current_bindings() -> dict[str, Any]:
    authority = read_strict_json(REFERENCE_AUTHORITY)
    profiles = read_strict_json(DISPLAY_PROFILES)
    projection = make_gate_0a_authority_projection(authority, profiles)
    return {
        "canonicalization": "RFC8785-integer-BMP-subset",
        "digestAlgorithm": "sha256",
        "authorityProjection": projection,
        "authorityProjectionSha256": sha256_bytes(canonical_json_bytes(projection)),
    }


def verify_recorded_gate_0a_user_approval() -> dict[str, Any]:
    profiles = read_strict_json(DISPLAY_PROFILES)
    approval = profiles.get("approval")
    required = {
        "method",
        "threadId",
        "approvedAt",
        "userStatement",
        "scope",
        "decision",
        "authorityProjectionSha256",
        "noWaivers",
    }
    if not isinstance(approval, dict) or set(approval) != required:
        raise ParityError("recorded Gate 0A user approval is missing or malformed")
    constants = {
        "method": GATE_0A_DIRECT_USER_APPROVAL_METHOD,
        "scope": GATE_0A_APPROVAL_SCOPE,
        "decision": "approve",
        "noWaivers": True,
    }
    for field, expected in constants.items():
        if approval.get(field) != expected:
            raise ParityError(
                f"recorded Gate 0A user approval {field} must be {expected!r}"
            )
    for field in ("threadId", "approvedAt", "userStatement"):
        if not isinstance(approval.get(field), str) or not approval[field]:
            raise ParityError(
                f"recorded Gate 0A user approval {field} must be non-empty"
            )
    validate_profiles(
        profiles,
        require_approval=True,
        require_resolved_identity=True,
    )
    current = _gate_0a_current_bindings()
    if approval["authorityProjectionSha256"] != current["authorityProjectionSha256"]:
        raise ParityError(
            "recorded Gate 0A user approval does not match the current authority projection"
        )
    return {
        "valid": True,
        "gate": "0A",
        "scope": GATE_0A_APPROVAL_SCOPE,
        "method": GATE_0A_DIRECT_USER_APPROVAL_METHOD,
        "threadId": approval["threadId"],
        "approvedAt": approval["approvedAt"],
        "authorityProjectionSha256": approval["authorityProjectionSha256"],
        "noWaivers": True,
        "scenarioPassGranted": False,
        "gate7ApprovalGranted": False,
        "goldensAuthorized": False,
    }


def _is_sha256(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def _validate_gate_0a_approval_envelope(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ParityError("Gate 0A approval envelope must be an object")
    required = {
        "schemaVersion",
        "namespace",
        "gate",
        "scope",
        "principal",
        "decision",
        "createdAt",
        "bindings",
        "noWaivers",
        "statements",
    }
    if set(value) != required:
        missing = sorted(required - set(value))
        extra = sorted(set(value) - required)
        raise ParityError(
            f"Gate 0A approval envelope fields mismatch: missing={missing} extra={extra}"
        )
    constants = {
        "schemaVersion": "2.0.0",
        "namespace": "halo-parity",
        "gate": "0A",
        "scope": GATE_0A_APPROVAL_SCOPE,
        "decision": "approve",
        "noWaivers": True,
    }
    for field, expected in constants.items():
        if value.get(field) != expected:
            raise ParityError(f"Gate 0A approval {field} must be {expected!r}")
    for field in ("principal", "createdAt"):
        if not isinstance(value.get(field), str) or not value[field]:
            raise ParityError(f"Gate 0A approval {field} must be a non-empty string")
    if any(character.isspace() for character in value["principal"]):
        raise ParityError("Gate 0A approval principal must contain no whitespace")
    if value.get("statements") != GATE_0A_APPROVAL_STATEMENTS:
        raise ParityError(
            "Gate 0A approval statements must limit authority to authoring/profiles, "
            "mark no scenario passed, exclude Gate 7 approval, and forbid goldens"
        )
    bindings = value.get("bindings")
    if not isinstance(bindings, dict):
        raise ParityError("Gate 0A approval bindings must be an object")
    binding_fields = {
        "canonicalization",
        "digestAlgorithm",
        "authorityProjection",
        "authorityProjectionSha256",
    }
    if set(bindings) != binding_fields:
        raise ParityError("Gate 0A approval binding fields are invalid")
    if bindings["canonicalization"] != "RFC8785-integer-BMP-subset":
        raise ParityError("Gate 0A approval canonicalization contract is invalid")
    if bindings["digestAlgorithm"] != "sha256":
        raise ParityError("Gate 0A approval digest algorithm is invalid")
    projection = bindings["authorityProjection"]
    validate_gate_0a_authority_projection(projection)
    embedded_digest = bindings["authorityProjectionSha256"]
    if (
        not _is_sha256(embedded_digest)
        or sha256_bytes(canonical_json_bytes(projection)) != embedded_digest
    ):
        raise ParityError(
            "Gate 0A approval embedded authority projection digest is invalid"
        )
    expected_bindings = _gate_0a_current_bindings()
    if canonical_json_bytes(projection) != canonical_json_bytes(
        expected_bindings["authorityProjection"]
    ):
        raise ParityError(
            "Gate 0A approval authority projection does not match current inputs"
        )
    if embedded_digest != expected_bindings["authorityProjectionSha256"]:
        raise ParityError(
            "Gate 0A approval authority projection digest does not match current inputs"
        )
    return value


def command_gate_0a_approval_prepare(args: argparse.Namespace) -> int:
    principal = args.principal
    if not principal or any(character.isspace() for character in principal):
        raise ParityError("authorized principal must be non-empty and contain no whitespace")
    envelope = {
        "schemaVersion": "2.0.0",
        "namespace": "halo-parity",
        "gate": "0A",
        "scope": GATE_0A_APPROVAL_SCOPE,
        "principal": principal,
        "decision": "approve",
        "createdAt": utc_now(),
        "bindings": _gate_0a_current_bindings(),
        "noWaivers": True,
        "statements": dict(GATE_0A_APPROVAL_STATEMENTS),
    }
    _validate_gate_0a_approval_envelope(envelope)
    output = _path(args.output).resolve()
    authority = read_strict_json(REFERENCE_AUTHORITY)
    bound_files = {
        REFERENCE_AUTHORITY.resolve(),
        DISPLAY_PROFILES.resolve(),
        (REPOSITORY_ROOT / authority["source"]["path"]).resolve(),
    }
    aliases_bound_input = output in bound_files
    if output.exists():
        aliases_bound_input = aliases_bound_input or any(
            os.path.samefile(output, bound) for bound in bound_files
        )
    if aliases_bound_input:
        raise ParityError("Gate 0A approval output must be external to every bound input")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(canonical_json_bytes(envelope))
    _print(
        {
            "written": str(output),
            "approvalSha256": sha256_file(output),
            "principal": principal,
            "signCommand": (
                f"ssh-keygen -Y sign -f <authorized-private-key> "
                f"-n halo-parity {output}"
            ),
        }
    )
    return 0


def verify_gate_0a_approval(
    approval: Path,
    signature: Path,
    allowed_signers: Path,
    principal: str,
) -> dict[str, Any]:
    if not approval.is_file() or not signature.is_file() or not allowed_signers.is_file():
        raise ParityError(
            "Gate 0A approval, signature, and allowed-signers files are required"
        )
    raw = approval.read_bytes()
    signature_raw = signature.read_bytes()
    allowed_signers_raw = allowed_signers.read_bytes()
    try:
        value = strict_json_loads(raw.decode("utf-8"), source=str(approval))
    except UnicodeDecodeError as error:
        raise ParityError("Gate 0A approval envelope is not valid UTF-8") from error
    if raw != canonical_json_bytes(value):
        raise ParityError("Gate 0A approval envelope is not canonical JSON")
    validated = _validate_gate_0a_approval_envelope(value)
    if principal != validated["principal"]:
        raise ParityError("allowed-signers principal does not match approval principal")
    with tempfile.TemporaryDirectory(prefix="halo-gate0a-verify-") as directory:
        verification_root = Path(directory)
        captured_signature = verification_root / "approval.sig"
        captured_allowed_signers = verification_root / "allowed-signers"
        captured_signature.write_bytes(signature_raw)
        captured_allowed_signers.write_bytes(allowed_signers_raw)
        completed = subprocess.run(
            [
                "ssh-keygen",
                "-Y",
                "verify",
                "-f",
                str(captured_allowed_signers),
                "-I",
                principal,
                "-n",
                "halo-parity",
                "-s",
                str(captured_signature),
            ],
            input=raw,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
            check=False,
        )
    if completed.returncode != 0:
        raise ParityError(
            "Gate 0A authorized human signature verification failed:\n"
            + completed.stdout.decode("utf-8", errors="replace")
        )
    if (
        approval.read_bytes() != raw
        or signature.read_bytes() != signature_raw
        or allowed_signers.read_bytes() != allowed_signers_raw
    ):
        raise ParityError(
            "Gate 0A approval inputs changed during signature verification"
        )
    # Close the authority-input time-of-check/time-of-use window.
    _validate_gate_0a_approval_envelope(validated)
    return {
        "valid": True,
        "gate": "0A",
        "scope": GATE_0A_APPROVAL_SCOPE,
        "principal": principal,
        "approvalSha256": sha256_bytes(raw),
        "signatureSha256": sha256_bytes(signature_raw),
        "allowedSignersSha256": sha256_bytes(allowed_signers_raw),
        "noWaivers": True,
        "scenarioPassGranted": False,
        "gate7ApprovalGranted": False,
        "goldensAuthorized": False,
    }


def command_gate_0a_approval_verify(args: argparse.Namespace) -> int:
    result = verify_gate_0a_approval(
        _path(args.approval),
        _path(args.signature),
        _path(args.allowed_signers),
        args.principal,
    )
    _print(result)
    return 0


def _check_gate_0a(
    approval_paths: tuple[Path, Path, Path, str] | None = None,
) -> list[Check]:
    checks: list[Check] = []
    authority_valid = False
    if approval_paths is None:
        try:
            authority = verify_recorded_gate_0a_user_approval()
            authority_valid = True
            checks.append(
                Check(
                    "authenticated Gate 0A authoring/profile authority",
                    True,
                    json.dumps(authority, sort_keys=True),
                )
            )
        except ParityError as error:
            checks.append(
                Check(
                    "authenticated Gate 0A authoring/profile authority",
                    False,
                    str(error),
                )
            )
    else:
        try:
            authority = verify_gate_0a_approval(*approval_paths)
            authority_valid = True
            checks.append(
                Check(
                    "authenticated Gate 0A authoring/profile authority",
                    True,
                    json.dumps(authority, sort_keys=True),
                )
            )
        except ParityError as error:
            checks.append(
                Check(
                    "authenticated Gate 0A authoring/profile authority",
                    False,
                    str(error),
                )
            )
    try:
        summary = validate_scenario_manifest(
            read_json(SCENARIO_MANIFEST),
            require_exact=True,
        )
        checks.append(Check("57 exact scenario rows", True, json.dumps(summary)))
    except ParityError as error:
        checks.append(Check("57 exact scenario rows", False, str(error)))
    try:
        authority_summary = validate_reference_authority(
            read_strict_json(REFERENCE_AUTHORITY)
        )
        checks.append(
            Check(
                "authored reference authority integrity",
                True,
                json.dumps(authority_summary, sort_keys=True),
            )
        )
    except ParityError as error:
        checks.append(
            Check("authored reference authority integrity", False, str(error))
        )
    try:
        profiles = validate_profiles(
            read_json(DISPLAY_PROFILES),
            require_approval=not authority_valid,
            require_resolved_identity=True,
        )
        checks.append(
            Check(
                "authorized display profiles",
                authority_valid,
                json.dumps(profiles),
            )
        )
    except ParityError as error:
        checks.append(Check("authorized display profiles", False, str(error)))
    for path, name in (
        (REFERENCE_ROOT / "reference-spec-v1.json", "reference row specification"),
        (REFERENCE_ROOT / "reference-input-lock-v1.json", "reference input lock"),
        (
            REFERENCE_ROOT / "generated" / "halo-reference-v1.html",
            "generated reference harness",
        ),
        (
            REPOSITORY_ROOT / "Sources" / "OpenIslandApp" / "HaloParityScenario.swift",
            "native parity scenario catalog",
        ),
    ):
        checks.append(Check(name, path.is_file(), str(path)))
    proof = CALIBRATION_ROOT / "gate-0a-capture-authenticity.json"
    try:
        value = read_json(proof)
        if value.get("schemaVersion") != "1.0.0":
            raise ParityError("Gate 0A capture proof schemaVersion must be 1.0.0")
        if value.get("passed") is not True:
            raise ParityError("Gate 0A capture proof must declare passed=true")
        renderer_proofs = value.get("rendererProofs")
        if not isinstance(renderer_proofs, dict):
            raise ParityError("Gate 0A capture proof must contain rendererProofs")
        for renderer in ("in-app-browser", "open-island-app"):
            item = renderer_proofs.get(renderer)
            if not isinstance(item, dict):
                raise ParityError(f"Gate 0A capture proof is missing {renderer}")
            if item.get("canonicalEligible") is not True:
                raise ParityError(f"{renderer} proof is not canonicalEligible")
            if item.get("captureMode") != "live-window":
                raise ParityError(f"{renderer} proof is not live-window")
            if item.get("captureAPI") != "ScreenCaptureKit":
                raise ParityError(f"{renderer} proof is not ScreenCaptureKit")
            if item.get("authenticityComplete") is not True:
                raise ParityError(f"{renderer} proof authenticity is incomplete")
            sidecar_value = item.get("authenticitySidecar")
            sidecar = (proof.parent / sidecar_value).resolve() if sidecar_value else None
            if sidecar is None:
                raise ParityError(f"{renderer} proof is missing authenticitySidecar")
            if item.get("authenticitySha256") != sha256_file(sidecar):
                raise ParityError(f"{renderer} proof sidecar hash mismatch")
            verify_authenticity_file(
                sidecar,
                expected_renderer=renderer,
                require_canonical=True,
            )
        checks.append(Check("canonical reference/native live-window proof", True, str(proof)))
    except (ParityError, OSError) as error:
        checks.append(
            Check("canonical reference/native live-window proof", False, str(error))
        )
    return checks


def _required_mask_matrix(scenario_manifest: dict[str, Any]) -> list[dict[str, str]]:
    scenarios = scenario_manifest.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        raise ParityError("mask matrix requires a non-empty scenario manifest")
    default_capture = scenario_manifest.get("manifestDefaults", {}).get("capture", {})
    if not isinstance(default_capture, dict):
        raise ParityError("scenario manifest default capture must be an object")
    matrix: list[dict[str, str]] = []
    scenario_ids: set[str] = set()
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            raise ParityError("every mask-matrix scenario must be an object")
        scenario_id = scenario.get("id")
        if (
            not isinstance(scenario_id, str)
            or not scenario_id
            or scenario_id in scenario_ids
        ):
            raise ParityError("mask-matrix scenario IDs must be unique and non-empty")
        scenario_ids.add(scenario_id)
        capture = scenario.get("capture", {})
        if not isinstance(capture, dict):
            raise ParityError(f"scenario {scenario_id} capture must be an object")
        checkpoint_count = 0
        for kind, field in (
            ("stable", "stableCheckpoints"),
            ("timed", "timedCheckpoints"),
        ):
            checkpoints = capture.get(field, default_capture.get(field, []))
            if (
                not isinstance(checkpoints, list)
                or any(
                    not isinstance(checkpoint, str) or not checkpoint
                    for checkpoint in checkpoints
                )
                or len(checkpoints) != len(set(checkpoints))
            ):
                raise ParityError(
                    f"scenario {scenario_id} {field} must contain unique "
                    "non-empty strings"
                )
            checkpoint_count += len(checkpoints)
            for checkpoint in checkpoints:
                for profile_id in ("notch-v1", "top-bar-v1"):
                    matrix.append(
                        {
                            "scenarioId": scenario_id,
                            "checkpointKind": kind,
                            "checkpointId": checkpoint,
                            "profileId": profile_id,
                        }
                    )
        if checkpoint_count == 0:
            raise ParityError(
                f"scenario {scenario_id} has no declared stable or timed checkpoints"
            )
    return matrix


def _resolved_bound_path(root: Path, value: Any, label: str) -> Path:
    if not isinstance(value, str) or not value:
        raise ParityError(f"{label} must be a non-empty path")
    path = Path(value)
    return path.resolve() if path.is_absolute() else (root / path).resolve()


def verify_gate_0b_masks(
    aggregate_path: Path,
    *,
    scenario_manifest_path: Path = SCENARIO_MANIFEST,
    policy_path: Path = CALIBRATION_ROOT / "mask-policy-v1.json",
) -> dict[str, Any]:
    aggregate_path = Path(aggregate_path).resolve()
    scenario_manifest_path = Path(scenario_manifest_path).resolve()
    policy_path = Path(policy_path).resolve()
    aggregate = read_strict_json(aggregate_path)
    required_fields = {
        "schemaVersion",
        "aggregateId",
        "status",
        "maskSetVersion",
        "policy",
        "scenarioManifest",
        "matrix",
        "matrixSha256",
        "aggregateSha256",
    }
    if not isinstance(aggregate, dict) or set(aggregate) != required_fields:
        raise ParityError("Gate 0B mask aggregate fields are not closed")
    constants = {
        "schemaVersion": "1.0.0",
        "aggregateId": "halo-mask-matrix-v1",
        "status": "frozen",
        "maskSetVersion": MASK_SET_VERSION,
    }
    for field, expected in constants.items():
        if aggregate.get(field) != expected:
            raise ParityError(
                f"Gate 0B mask aggregate {field} must be {expected!r}"
            )
    claimed_aggregate_hash = aggregate["aggregateSha256"]
    unhashed = dict(aggregate)
    del unhashed["aggregateSha256"]
    if (
        not _is_sha256(claimed_aggregate_hash)
        or sha256_bytes(canonical_json_bytes(unhashed)) != claimed_aggregate_hash
    ):
        raise ParityError("Gate 0B mask aggregate hash mismatch")

    policy = aggregate["policy"]
    if not isinstance(policy, dict) or set(policy) != {
        "policyId",
        "path",
        "sha256",
    }:
        raise ParityError("Gate 0B mask policy binding is not closed")
    if not policy_path.is_file():
        raise ParityError(f"Gate 0B mask policy is missing: {policy_path}")
    if (
        policy.get("policyId") != "halo-mask-policy-v1"
        or _resolved_bound_path(aggregate_path.parent, policy.get("path"), "policy path")
        != policy_path
        or policy.get("sha256") != sha256_file(policy_path)
    ):
        raise ParityError("Gate 0B mask policy binding mismatch")
    policy_value = read_strict_json(policy_path)
    if (
        policy_value.get("policyId") != "halo-mask-policy-v1"
        or policy_value.get("requiredMaskFamilies")
        != [
            "silhouette-body",
            "edge-core",
            "emissive-bloom",
            "non-text-content",
            "text-layout-boxes",
            "os-external",
        ]
    ):
        raise ParityError("Gate 0B mask policy content is invalid")

    scenario_binding = aggregate["scenarioManifest"]
    if not isinstance(scenario_binding, dict) or set(scenario_binding) != {
        "path",
        "sha256",
    }:
        raise ParityError("Gate 0B scenario manifest binding is not closed")
    if not scenario_manifest_path.is_file():
        raise ParityError(
            f"Gate 0B scenario manifest is missing: {scenario_manifest_path}"
        )
    if (
        _resolved_bound_path(
            aggregate_path.parent,
            scenario_binding.get("path"),
            "scenario manifest path",
        )
        != scenario_manifest_path
        or scenario_binding.get("sha256") != sha256_file(scenario_manifest_path)
    ):
        raise ParityError("Gate 0B scenario manifest binding mismatch")
    expected_cells = _required_mask_matrix(read_strict_json(scenario_manifest_path))
    matrix = aggregate["matrix"]
    if not isinstance(matrix, list):
        raise ParityError("Gate 0B mask matrix must be an array")
    if (
        not _is_sha256(aggregate["matrixSha256"])
        or sha256_bytes(canonical_json_bytes(matrix)) != aggregate["matrixSha256"]
    ):
        raise ParityError("Gate 0B mask matrix hash mismatch")
    actual_cells: list[dict[str, str]] = []
    verified: list[dict[str, Any]] = []
    verification_cache: dict[Path, tuple[str, dict[str, Any]]] = {}
    for index, entry in enumerate(matrix):
        fields = {
            "scenarioId",
            "checkpointKind",
            "checkpointId",
            "profileId",
            "manifestPath",
            "manifestSha256",
        }
        if not isinstance(entry, dict) or set(entry) != fields:
            raise ParityError(f"Gate 0B mask matrix entry {index} is not closed")
        cell = {field: entry[field] for field in fields - {"manifestPath", "manifestSha256"}}
        actual_cells.append(
            {
                "scenarioId": cell["scenarioId"],
                "checkpointKind": cell["checkpointKind"],
                "checkpointId": cell["checkpointId"],
                "profileId": cell["profileId"],
            }
        )
        manifest_relative = entry["manifestPath"]
        if not isinstance(manifest_relative, str) or not manifest_relative:
            raise ParityError(f"Gate 0B mask matrix entry {index} path is invalid")
        manifest_path = Path(manifest_relative)
        if manifest_path.is_absolute():
            raise ParityError("Gate 0B mask manifest paths must be aggregate-relative")
        manifest_path = (aggregate_path.parent / manifest_path).resolve()
        try:
            manifest_path.relative_to(aggregate_path.parent)
        except ValueError as error:
            raise ParityError(
                "Gate 0B mask manifest path escapes the aggregate root"
            ) from error
        if not manifest_path.is_file():
            raise ParityError(
                f"Gate 0B mask manifest is missing at entry {index}: {manifest_path}"
            )
        if not _is_sha256(entry["manifestSha256"]):
            raise ParityError(f"Gate 0B mask manifest hash mismatch at entry {index}")
        cached = verification_cache.get(manifest_path)
        if cached is None:
            actual_hash = sha256_file(manifest_path)
            if actual_hash != entry["manifestSha256"]:
                raise ParityError(
                    f"Gate 0B mask manifest hash mismatch at entry {index}"
                )
            result = verify_mask_manifest(manifest_path)
            verification_cache[manifest_path] = (actual_hash, result)
            verified.append(result)
        else:
            actual_hash, result = cached
            if actual_hash != entry["manifestSha256"]:
                raise ParityError(
                    f"Gate 0B mask manifest hash binding differs at entry {index}"
                )
        if result["profileId"] != entry["profileId"]:
            raise ParityError(f"Gate 0B mask profile mismatch at entry {index}")
    if actual_cells != expected_cells:
        raise ParityError(
            "Gate 0B mask matrix does not exactly match declared "
            "scenario/checkpoint/profile requirements"
        )
    return {
        "valid": True,
        "aggregateId": aggregate["aggregateId"],
        "maskSetVersion": aggregate["maskSetVersion"],
        "matrixCellCount": len(matrix),
        "profileIds": ["notch-v1", "top-bar-v1"],
        "aggregateSha256": claimed_aggregate_hash,
        "verifiedManifestCount": len(verified),
    }


def _check_gate_0b() -> list[Check]:
    checks: list[Check] = []
    threshold = CALIBRATION_ROOT / "thresholds-v1.json"
    masks = CALIBRATION_ROOT / "masks-v1.json"
    neutral = CALIBRATION_ROOT / "neutral-repeatability-v1.json"
    motion = CALIBRATION_ROOT / "neutral-motion-repeatability-v1.json"
    for path, name in (
        (threshold, "frozen neutral thresholds"),
        (neutral, "neutral repeatability report"),
        (motion, "neutral motion repeatability report"),
    ):
        checks.append(Check(name, path.is_file(), str(path)))
    try:
        mask_summary = verify_gate_0b_masks(masks)
        checks.append(
            Check("frozen scenario/checkpoint mask matrix", True, json.dumps(mask_summary))
        )
    except (ParityError, OSError) as error:
        checks.append(
            Check("frozen scenario/checkpoint mask matrix", False, str(error))
        )
    if threshold.is_file():
        value = read_json(threshold)
        checks.append(
            Check(
                "threshold provenance is neutral",
                value.get("sourceRole") == "neutral-calibration"
                and value.get("status") == "frozen",
                f"sourceRole={value.get('sourceRole')} status={value.get('status')}",
            )
        )
    return checks


def _check_gate_0c() -> list[Check]:
    run_pointer = ARTIFACT_ROOT / "current"
    checks = [Check("current evidence pointer", run_pointer.exists(), str(run_pointer))]
    if run_pointer.exists():
        root = run_pointer.resolve()
        baseline = root / "reports" / "gate-0c-baseline.json"
        index = root / "evidence-index.json"
        checks.append(Check("baseline report", baseline.is_file(), str(baseline)))
        checks.append(Check("evidence index", index.is_file(), str(index)))
        if baseline.is_file():
            value = read_json(baseline)
            checks.append(
                Check(
                    "baseline completeness",
                    value.get("complete") is True,
                    json.dumps(value, sort_keys=True),
                )
            )
    return checks


def command_verify(args: argparse.Namespace) -> int:
    gate = args.gate.upper()
    checks: list[Check] = []
    approval_values = (
        args.gate_0a_approval,
        args.gate_0a_signature,
        args.gate_0a_allowed_signers,
        args.gate_0a_principal,
    )
    supplied_approval_values = [value is not None for value in approval_values]
    if any(supplied_approval_values) and not all(supplied_approval_values):
        raise ParityError(
            "Gate 0A authority requires --gate-0a-approval, --gate-0a-signature, "
            "--gate-0a-allowed-signers, and --gate-0a-principal together"
        )
    approval_paths = (
        (
            _path(args.gate_0a_approval),
            _path(args.gate_0a_signature),
            _path(args.gate_0a_allowed_signers),
            args.gate_0a_principal,
        )
        if all(supplied_approval_values)
        else None
    )
    if gate in {"0A", "0B", "0C"}:
        checks.extend(_check_gate_0a(approval_paths))
    if gate in {"0B", "0C"}:
        checks.extend(_check_gate_0b())
    if gate == "0C":
        checks.extend(_check_gate_0c())
    if gate not in {"0A", "0B", "0C"}:
        report = ARTIFACT_ROOT / "current" / "reports" / f"gate-{gate.lower()}.json"
        checks.append(Check(f"Gate {gate} report", report.is_file(), str(report)))
        if report.is_file():
            value = read_json(report)
            checks.append(
                Check(
                    f"Gate {gate} passed",
                    value.get("passed") is True,
                    json.dumps(value, sort_keys=True),
                )
            )
    return _result(
        f"verify:{gate}",
        checks,
        output=_path(args.output) if args.output else None,
    )


def command_signoff_prepare(args: argparse.Namespace) -> int:
    index_path = _path(args.evidence_index)
    index = read_json(index_path)
    digest = {
        "schemaVersion": "1.0.0",
        "namespace": "halo-parity",
        "status": "awaiting-authorized-human-signature",
        "createdAt": utc_now(),
        "commitSha": git_commit(),
        "evidenceIndexSha256": sha256_file(index_path),
        "evidenceLogicalHash": index.get("indexSha256"),
        "scenarioManifestSha256": sha256_file(SCENARIO_MANIFEST),
        "measurementSpecSha256": sha256_file(MEASUREMENT_SPEC),
        "displayProfilesSha256": sha256_file(DISPLAY_PROFILES),
        "noWaivers": True,
    }
    reference_lock = REFERENCE_ROOT / "reference-input-lock-v1.json"
    if reference_lock.exists():
        digest["referenceInputLockSha256"] = sha256_file(reference_lock)
    digest["approvalDigestSha256"] = sha256_bytes(canonical_json_bytes(digest))
    output = _path(args.output)
    write_json(output, digest)
    _print({"written": str(output), "digest": digest["approvalDigestSha256"]})
    return 0


def command_signoff_verify(args: argparse.Namespace) -> int:
    approval = _path(args.approval)
    signature = _path(args.signature)
    allowed = _path(args.allowed_signers)
    if not approval.is_file() or not signature.is_file() or not allowed.is_file():
        raise ParityError("approval, signature, and allowed-signers files are required")
    principal = args.principal
    with approval.open("rb") as handle:
        completed = subprocess.run(
            [
                "ssh-keygen",
                "-Y",
                "verify",
                "-f",
                str(allowed),
                "-I",
                principal,
                "-n",
                "halo-parity",
                "-s",
                str(signature),
            ],
            stdin=handle,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
            check=False,
        )
    if completed.returncode != 0:
        raise ParityError(
            "authorized human signature verification failed:\n"
            + completed.stdout.decode("utf-8", errors="replace")
        )
    value = read_json(approval)
    if value.get("noWaivers") is not True:
        raise ParityError("Gate 7 approval must explicitly attest noWaivers=true")
    result = {
        "valid": True,
        "principal": principal,
        "approvalSha256": sha256_file(approval),
        "signatureSha256": sha256_file(signature),
    }
    _print(result)
    return 0


def command_test(args: argparse.Namespace) -> int:
    if args.test_kind == "semantic":
        command = [
            "swift",
            "test",
            "-Xswiftc",
            "-DHALO_PARITY_TESTING",
            "--filter",
            "Halo(ClosedPill|EdgeLight|PermissionHero|SessionList|Theme|Usage|Parity)Tests|IslandDebugScenarioTests",
        ]
    elif args.test_kind == "smoke":
        command = ["zsh", "scripts/smoke-all-scenarios.sh"]
        if args.dry_run:
            command.append("--dry-run")
    else:
        if args.record:
            raise ParityError(
                "snapshot recording is forbidden here; use record-goldens after Gate 7"
            )
        command = ["swift", "test", "--filter", "HaloConformanceSnapshotTests"]
    completed = run(command, check=False)
    print(completed.stdout, end="")
    if args.test_kind == "snapshots" and args.expect_missing is not None:
        marker = f"with {args.expect_missing} failures (0 unexpected)"
        if args.expect_missing == 0:
            return completed.returncode
        return 0 if marker in completed.stdout else 1
    return completed.returncode


def command_record_goldens(args: argparse.Namespace) -> int:
    gate7 = read_json(_path(args.gate7_report))
    if gate7.get("passed") is not True or gate7.get("signatureVerified") is not True:
        raise ParityError("record-goldens requires a passed, signature-verified Gate 7 report")
    if gate7.get("noWaivers") is not True:
        raise ParityError("record-goldens refuses Gate 7 reports with waivers")
    provenance = read_json(_path(args.provenance))
    records = provenance.get("records", [])
    if len(records) != 26:
        raise ParityError("golden promotion requires exactly 26 provenance records")
    destination = _path(args.destination)
    destination.mkdir(parents=True, exist_ok=True)
    promoted = []
    for record in records:
        if (
            record.get("renderer") != "open-island-app"
            or record.get("captureMode") != "live-window"
            or record.get("captureAPI") != "ScreenCaptureKit"
            or record.get("gate7EvidenceApproved") is not True
        ):
            raise ParityError("golden provenance contains non-live or unapproved evidence")
        source = _path(record["source"])
        if not source.is_file() or sha256_file(source) != record["sha256"]:
            raise ParityError(f"golden source missing or hash mismatch: {source}")
        target = destination / record["goldenName"]
        shutil.copy2(source, target)
        promoted.append({"path": str(target), "sha256": sha256_file(target)})
    manifest = {
        "schemaVersion": "1.0.0",
        "createdAt": utc_now(),
        "gate7ReportSha256": sha256_file(_path(args.gate7_report)),
        "records": promoted,
    }
    manifest["manifestSha256"] = sha256_bytes(canonical_json_bytes(manifest))
    write_json(destination / "golden-provenance.json", manifest)
    _print({"promoted": len(promoted), "destination": str(destination)})
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="halo",
        description="Validation-first Halo cross-renderer parity coordinator",
    )
    parser.add_argument("--version", action="version", version=__version__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    doctor = subparsers.add_parser("doctor")
    doctor.add_argument("--allow-unapproved", action="store_true")
    doctor.add_argument("--output")
    doctor.set_defaults(handler=command_doctor)

    freeze = subparsers.add_parser("freeze-spec")
    freeze.add_argument("--version", default="v1")
    freeze.add_argument("--allow-unapproved", action="store_true")
    freeze.add_argument("--output")
    freeze.set_defaults(handler=command_freeze_spec)

    build_reference = subparsers.add_parser("build-reference")
    build_reference.set_defaults(handler=command_build_reference)

    serve = subparsers.add_parser("serve-reference")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=4173)
    serve.set_defaults(handler=command_serve_reference)

    queue = subparsers.add_parser("queue-reference")
    queue.add_argument("--base-url", default="http://127.0.0.1:4173")
    queue.add_argument(
        "--output",
        default="Validation/HaloParity/calibration/v1/reference-capture-queue.json",
    )
    queue.set_defaults(handler=command_queue_reference)

    for name in ("capture-reference", "capture-native"):
        capture = subparsers.add_parser(name)
        capture.add_argument("--queue", required=True)
        capture.add_argument("--output", required=True)
        capture.add_argument("--strict", action="store_true")
        capture.set_defaults(handler=command_capture_plan, capture_command=name)

    capture_window = subparsers.add_parser("capture-window")
    capture_window.add_argument("--window-id", type=int, required=True)
    capture_window.add_argument("--output", required=True)
    capture_window.add_argument("--sidecar")
    capture_window.add_argument(
        "--renderer",
        choices=(
            "in-app-browser",
            "open-island-app",
            "native-swiftui-calibration",
        ),
        required=True,
    )
    capture_window.add_argument("--scenario", required=True)
    capture_window.add_argument(
        "--profile", choices=("notch-v1", "top-bar-v1"), required=True
    )
    capture_window.add_argument("--expected-pid", type=int)
    capture_window.add_argument("--expected-bundle-id")
    capture_window.add_argument("--native-sidecar")
    capture_window.add_argument("--calibration-manifest")
    capture_window.add_argument("--expected-native-theme")
    capture_window.add_argument(
        "--expected-native-motion", choices=("normal", "reduced")
    )
    capture_window.add_argument(
        "--expected-native-accessibility",
        choices=(
            "standard",
            "reduce-motion",
            "increase-contrast",
            "reduce-transparency",
            "keyboard",
            "voiceover",
            "text-scale",
        ),
    )
    capture_window.add_argument("--expected-native-event")
    capture_window.add_argument("--crop-x", type=float)
    capture_window.add_argument("--crop-y", type=float)
    capture_window.add_argument("--crop-width", type=float)
    capture_window.add_argument("--crop-height", type=float)
    capture_window.add_argument("--profile-crop-proven", action="store_true")
    capture_window.add_argument("--helper", help=argparse.SUPPRESS)
    capture_window.set_defaults(handler=command_capture_window)

    authenticity = subparsers.add_parser("verify-authenticity")
    authenticity.add_argument("--sidecar", required=True)
    authenticity.add_argument(
        "--renderer",
        choices=(
            "in-app-browser",
            "open-island-app",
            "native-swiftui-calibration",
        ),
    )
    authenticity.add_argument("--require-canonical", action="store_true")
    authenticity.set_defaults(handler=command_verify_authenticity)

    calibrate = subparsers.add_parser("calibrate")
    calibrate_sub = calibrate.add_subparsers(dest="calibrate_command", required=True)
    calibrate_capture = calibrate_sub.add_parser("capture")
    calibrate_capture.add_argument(
        "--suite",
        default="Validation/HaloParity/calibration/v1/suite.json",
    )
    calibrate_capture.add_argument(
        "--output",
        default="Validation/HaloParity/calibration/v1/capture-queue.json",
    )
    calibrate_capture.set_defaults(handler=command_calibrate_capture)
    calibrate_analyze = calibrate_sub.add_parser("analyze")
    calibrate_analyze.add_argument("--manifest", required=True)
    calibrate_analyze.add_argument(
        "--output",
        default="Validation/HaloParity/calibration/v1/neutral-repeatability-v1.json",
    )
    calibrate_analyze.set_defaults(handler=command_calibrate_analyze)
    calibrate_freeze = calibrate_sub.add_parser("freeze")
    calibrate_freeze.add_argument("--report", required=True)
    calibrate_freeze.add_argument("--version", default="v1")
    calibrate_freeze.add_argument("--approved")
    calibrate_freeze.add_argument(
        "--output",
        default="Validation/HaloParity/calibration/v1/thresholds-v1.json",
    )
    calibrate_freeze.set_defaults(handler=command_calibrate_freeze)
    calibrate_masks = calibrate_sub.add_parser("masks")
    calibrate_masks.add_argument("--annotations", required=True)
    calibrate_masks.add_argument(
        "--profile",
        choices=("notch-v1", "top-bar-v1"),
        required=True,
    )
    calibrate_masks.add_argument("--neutral-transform", required=True)
    calibrate_masks.add_argument("--output-dir", required=True)
    calibrate_masks.set_defaults(handler=command_calibrate_masks)

    baseline = subparsers.add_parser("baseline")
    baseline_sub = baseline.add_subparsers(dest="baseline_command", required=True)
    baseline_capture = baseline_sub.add_parser("capture")
    baseline_capture.add_argument(
        "--output",
        default="Validation/HaloParity/calibration/v1/baseline-capture-queue.json",
    )
    baseline_capture.set_defaults(handler=command_baseline_capture)
    baseline_report = baseline_sub.add_parser("report")
    baseline_report.add_argument("--evidence-root", required=True)
    baseline_report.add_argument(
        "--queue",
        default="Validation/HaloParity/calibration/v1/baseline-capture-queue.json",
    )
    baseline_report.set_defaults(handler=command_baseline_report)

    verify = subparsers.add_parser("verify")
    verify.add_argument("--gate", required=True)
    verify.add_argument("--output")
    verify.add_argument("--gate-0a-approval")
    verify.add_argument("--gate-0a-signature")
    verify.add_argument("--gate-0a-allowed-signers")
    verify.add_argument("--gate-0a-principal")
    verify.set_defaults(handler=command_verify)

    gate_0a_approval = subparsers.add_parser("gate0a-approval")
    gate_0a_approval_sub = gate_0a_approval.add_subparsers(
        dest="gate_0a_approval_command",
        required=True,
    )
    gate_0a_prepare = gate_0a_approval_sub.add_parser("prepare")
    gate_0a_prepare.add_argument("--principal", required=True)
    gate_0a_prepare.add_argument("--output", required=True)
    gate_0a_prepare.set_defaults(handler=command_gate_0a_approval_prepare)
    gate_0a_verify = gate_0a_approval_sub.add_parser("verify")
    gate_0a_verify.add_argument("--approval", required=True)
    gate_0a_verify.add_argument("--signature", required=True)
    gate_0a_verify.add_argument("--allowed-signers", required=True)
    gate_0a_verify.add_argument("--principal", required=True)
    gate_0a_verify.set_defaults(handler=command_gate_0a_approval_verify)

    signoff = subparsers.add_parser("signoff")
    signoff_sub = signoff.add_subparsers(dest="signoff_command", required=True)
    signoff_prepare = signoff_sub.add_parser("prepare")
    signoff_prepare.add_argument("--evidence-index", required=True)
    signoff_prepare.add_argument("--output", required=True)
    signoff_prepare.set_defaults(handler=command_signoff_prepare)
    signoff_verify = signoff_sub.add_parser("verify")
    signoff_verify.add_argument("--approval", required=True)
    signoff_verify.add_argument("--signature", required=True)
    signoff_verify.add_argument("--allowed-signers", required=True)
    signoff_verify.add_argument("--principal", required=True)
    signoff_verify.set_defaults(handler=command_signoff_verify)

    test = subparsers.add_parser("test")
    test.add_argument("test_kind", choices=("semantic", "smoke", "snapshots"))
    test.add_argument("--dry-run", action="store_true")
    test.add_argument("--record", action="store_true")
    test.add_argument("--expect-missing", type=int)
    test.set_defaults(handler=command_test)

    record = subparsers.add_parser("record-goldens")
    record.add_argument("--gate7-report", required=True)
    record.add_argument("--provenance", required=True)
    record.add_argument(
        "--destination",
        default="Tests/OpenIslandAppTests/__Snapshots__/HaloConformanceSnapshotTests",
    )
    record.set_defaults(handler=command_record_goldens)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except ParityError as error:
        print(f"halo: ERROR: {error}", file=sys.stderr)
        return 2
