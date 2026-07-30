from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path
from typing import Any

from .core import ParityError, read_json, sha256_file


REQUIRED_COMMON = (
    "schemaVersion",
    "renderer",
    "captureMode",
    "captureAPI",
    "artifactPath",
    "artifactSha256",
    "profileId",
    "scenarioId",
    "onScreen",
    "window",
    "captureHelper",
)

REQUIRED_NATIVE_PROVENANCE = (
    "executable",
    "process",
    "fixture",
    "placement",
    "clock",
    "isolation",
)
REQUIRED_NATIVE_TOP_LEVEL = (
    "schemaVersion",
    "scenario",
    "manifestDisposition",
    "lockedNativeFixtureIdentifier",
    "profile",
    "motion",
    "accessibility",
    "event",
    "seed",
    "fixtureSchemaVersion",
    "fixtureHash",
    "fixtureVariant",
    "resolvedThemeID",
    "clock",
    "executable",
    "process",
    "fixture",
    "placement",
    "generatedAt",
    "isolation",
)

SHA256_PATTERN = re.compile(r"^[a-f0-9]{64}$")
GIT_REVISION_PATTERN = re.compile(r"^[a-f0-9]{40}$")
BUILD_ID_PATTERN = re.compile(
    r"^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-"
    r"[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$"
)
NATIVE_SCHEMA_VERSION = "halo-native-capture-sidecar-v1"
NATIVE_ACCESSIBILITY_MODES = {
    "standard",
    "reduce-motion",
    "increase-contrast",
    "reduce-transparency",
    "keyboard",
    "voiceover",
    "text-scale",
}
_UNSET = object()


def _nonempty_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ParityError(f"native authenticity {field} must be a non-empty string")
    return value


def _nested_object(value: dict[str, Any], field: str) -> dict[str, Any]:
    item = value.get(field)
    if not isinstance(item, dict):
        raise ParityError(
            f"native authenticity requires nested {field} provenance; "
            "flat legacy sidecars are unsupported"
        )
    return item


def _rect(value: Any, field: str) -> dict[str, float | int]:
    if not isinstance(value, dict):
        raise ParityError(f"native placement {field} must be an object")
    for coordinate in ("x", "y", "width", "height"):
        if (
            coordinate not in value
            or isinstance(value[coordinate], bool)
            or not isinstance(value[coordinate], (int, float))
        ):
            raise ParityError(f"native placement {field}.{coordinate} must be numeric")
    if value["width"] <= 0 or value["height"] <= 0:
        raise ParityError(f"native placement {field} must have positive dimensions")
    return value


def validate_native_provenance(
    native: Any,
    *,
    native_sidecar_path: Path,
    scenario_id: str,
    profile_id: str,
    window: dict[str, Any] | None = None,
    expected_theme: str | None = None,
    expected_motion: str | None = None,
    expected_accessibility: str | None = None,
    expected_event: Any = _UNSET,
) -> dict[str, Any]:
    if not isinstance(native, dict):
        raise ParityError("native capture requires a nested Swift authenticity sidecar")
    for field in REQUIRED_NATIVE_PROVENANCE:
        _nested_object(native, field)
    missing_top = [field for field in REQUIRED_NATIVE_TOP_LEVEL if field not in native]
    if missing_top:
        raise ParityError(
            "native Swift authenticity sidecar missing fields: "
            + ", ".join(missing_top)
        )
    if native.get("schemaVersion") != NATIVE_SCHEMA_VERSION:
        raise ParityError(
            f"native sidecar schemaVersion must be {NATIVE_SCHEMA_VERSION}"
        )
    if native.get("scenario") != scenario_id:
        raise ParityError(
            f"native scenario mismatch: expected {scenario_id}, got {native.get('scenario')}"
        )
    if native.get("profile") != profile_id:
        raise ParityError(
            f"native profile mismatch: expected {profile_id}, got {native.get('profile')}"
        )
    if native.get("manifestDisposition") != "exact":
        raise ParityError("native manifestDisposition must be exact")
    _nonempty_string(
        native.get("lockedNativeFixtureIdentifier"),
        "lockedNativeFixtureIdentifier",
    )
    _nonempty_string(native.get("fixtureSchemaVersion"), "fixtureSchemaVersion")
    _nonempty_string(native.get("fixtureVariant"), "fixtureVariant")
    if (
        isinstance(native.get("seed"), bool)
        or not isinstance(native.get("seed"), int)
        or native["seed"] < 0
    ):
        raise ParityError("native seed must be a non-negative integer")
    generated_at = _nonempty_string(native.get("generatedAt"), "generatedAt")
    try:
        datetime.fromisoformat(generated_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise ParityError("native generatedAt must be ISO-8601") from error

    resolved_theme = _nonempty_string(native.get("resolvedThemeID"), "resolvedThemeID")
    required_theme = expected_theme or "halo"
    if resolved_theme != required_theme:
        raise ParityError(
            f"native resolved theme mismatch: expected {required_theme}, got {resolved_theme}"
        )

    motion = _nonempty_string(native.get("motion"), "motion")
    if motion == "manual":
        raise ParityError("manual native determinism is unsupported for canonical capture")
    if motion not in {"normal", "reduced"}:
        raise ParityError(f"unsupported native motion mode: {motion}")
    if expected_motion and motion != expected_motion:
        raise ParityError(
            f"native motion mismatch: expected {expected_motion}, got {motion}"
        )
    accessibility = _nonempty_string(native.get("accessibility"), "accessibility")
    if accessibility not in NATIVE_ACCESSIBILITY_MODES:
        raise ParityError(f"unsupported native accessibility mode: {accessibility}")
    if expected_accessibility and accessibility != expected_accessibility:
        raise ParityError(
            "native accessibility mismatch: expected "
            f"{expected_accessibility}, got {accessibility}"
        )
    if (motion == "reduced") != (accessibility == "reduce-motion"):
        raise ParityError("native motion/accessibility attestations are contradictory")
    clock = _nested_object(native, "clock")
    expected_clock = "production-monotonic" if motion == "normal" else "reduced-motion"
    if clock.get("mode") != expected_clock:
        raise ParityError(
            f"native clock mismatch: expected {expected_clock}, got {clock.get('mode')}"
        )

    event = native.get("event")
    if event is not None and (not isinstance(event, str) or not event):
        raise ParityError("native event must be null or a non-empty string")
    if expected_event is not _UNSET and event != expected_event:
        raise ParityError(
            f"native event mismatch: expected {expected_event}, got {event}"
        )
    state = native.get("state")
    acknowledgements = native.get("acknowledgedEvents")
    if state is not None:
        if not isinstance(state, dict):
            raise ParityError("native state acknowledgement must be an object")
        for field, expected in (
            ("scenario", scenario_id),
            ("profile", profile_id),
            ("motion", motion),
            ("accessibility", accessibility),
        ):
            if state.get(field) != expected:
                raise ParityError(
                    f"native state {field} mismatch: expected {expected}, got {state.get(field)}"
                )
        state_acknowledgements = state.get("acknowledgedEvents")
        if acknowledgements is not None and acknowledgements != state_acknowledgements:
            raise ParityError("native control acknowledgement fields disagree")
        acknowledgements = state_acknowledgements
    if acknowledgements is not None:
        if (
            not isinstance(acknowledgements, list)
            or any(not isinstance(item, str) or not item for item in acknowledgements)
        ):
            raise ParityError("native acknowledgedEvents must be a string array")
        if event is None and acknowledgements:
            raise ParityError("native sidecar acknowledges an event that was not requested")
        if event is not None and acknowledgements != [event]:
            raise ParityError(
                "native control acknowledgement must exactly match the requested event"
            )
    elif event is not None:
        raise ParityError("native requested event lacks a control acknowledgement")

    executable = _nested_object(native, "executable")
    for field in (
        "path",
        "sha256",
        "buildId",
        "configuration",
        "gitRevision",
        "sourceTreeDirty",
    ):
        if field not in executable:
            raise ParityError(f"native executable authenticity missing {field}")
    executable_path = Path(_nonempty_string(executable["path"], "executable.path"))
    if not executable_path.is_absolute():
        raise ParityError("native executable.path must be absolute")
    if not executable_path.is_file():
        raise ParityError(f"native executable does not exist: {executable_path}")
    executable_sha = executable["sha256"]
    if not isinstance(executable_sha, str) or not SHA256_PATTERN.fullmatch(executable_sha):
        raise ParityError("native executable.sha256 must be lowercase SHA-256")
    if sha256_file(executable_path) != executable_sha:
        raise ParityError("native executable SHA-256 does not match file bytes")
    build_id = _nonempty_string(executable["buildId"], "executable.buildId")
    if not BUILD_ID_PATTERN.fullmatch(build_id):
        raise ParityError("native executable.buildId must be a Mach-O UUID")
    _nonempty_string(executable["configuration"], "executable.configuration")
    revision = executable["gitRevision"]
    if not isinstance(revision, str) or not GIT_REVISION_PATTERN.fullmatch(revision):
        raise ParityError(
            "native executable.gitRevision must be a lowercase 40-character Git SHA"
        )
    if not isinstance(executable["sourceTreeDirty"], bool):
        raise ParityError("native executable.sourceTreeDirty must be boolean")

    process = _nested_object(native, "process")
    for field in ("pid", "startTime", "bundleId"):
        if field not in process:
            raise ParityError(f"native process authenticity missing {field}")
    if (
        isinstance(process["pid"], bool)
        or not isinstance(process["pid"], int)
        or process["pid"] < 1
    ):
        raise ParityError("native process.pid must be a positive integer")
    bundle_id = _nonempty_string(process["bundleId"], "process.bundleId")
    start_time = _nonempty_string(process["startTime"], "process.startTime")
    try:
        datetime.fromisoformat(start_time.replace("Z", "+00:00"))
    except ValueError as error:
        raise ParityError("native process.startTime must be ISO-8601") from error
    if process.get("executablePath") is not None:
        process_executable_path = _nonempty_string(
            process["executablePath"],
            "process.executablePath",
        )
        if Path(process_executable_path).resolve() != executable_path.resolve():
            raise ParityError("native process executable path drifted from executable provenance")
    if process.get("executableSha256") is not None:
        if process["executableSha256"] != executable_sha:
            raise ParityError("native process executable identity drifted from executable provenance")
    if process.get("executable") is not None:
        process_executable = process["executable"]
        if not isinstance(process_executable, dict):
            raise ParityError("native process.executable identity must be an object")
        if (
            process_executable.get("path") != executable["path"]
            or process_executable.get("sha256") != executable_sha
        ):
            raise ParityError("native process executable identity drifted from executable provenance")

    fixture = _nested_object(native, "fixture")
    for field in ("id", "payloadSha256", "liveDataAbsent"):
        if field not in fixture:
            raise ParityError(f"native fixture authenticity missing {field}")
    fixture_id = _nonempty_string(fixture["id"], "fixture.id")
    payload_hash = fixture["payloadSha256"]
    if not isinstance(payload_hash, str) or not SHA256_PATTERN.fullmatch(payload_hash):
        raise ParityError("native fixture.payloadSha256 must be lowercase SHA-256")
    if fixture["liveDataAbsent"] is not True:
        raise ParityError("native fixture did not attest live-data isolation")
    if native["lockedNativeFixtureIdentifier"] != fixture_id:
        raise ParityError("native locked fixture identifier does not match fixture.id")
    if (
        not isinstance(native["fixtureHash"], str)
        or not SHA256_PATTERN.fullmatch(native["fixtureHash"])
        or native["fixtureHash"] != payload_hash
    ):
        raise ParityError("native fixtureHash does not match fixture.payloadSha256")

    isolation = _nested_object(native, "isolation")
    for field in (
        "runtimeStateLoadingDisabled",
        "bridgeStartupDisabled",
        "allSessionsAreDemoOrigin",
    ):
        if isolation.get(field) is not True:
            raise ParityError(f"native isolation did not attest {field}=true")
    fixture_session_ids = isolation.get("fixtureSessionIDs")
    if (
        not isinstance(fixture_session_ids, list)
        or any(not isinstance(item, str) or not item for item in fixture_session_ids)
    ):
        raise ParityError("native isolation.fixtureSessionIDs must be a string array")

    placement = _nested_object(native, "placement")
    if placement.get("requestedProfileId") != profile_id:
        raise ParityError("native placement requested profile does not match capture profile")
    expected_mode = "notch" if profile_id == "notch-v1" else "topBar"
    if placement.get("resolvedMode") != expected_mode:
        raise ParityError(
            "native actual placement mode mismatch: expected "
            f"{expected_mode}, got {placement.get('resolvedMode')}"
        )
    for field in ("targetScreenId", "targetScreenName", "selectionSummary"):
        _nonempty_string(placement.get(field), f"placement.{field}")
    for field in ("screenFrame", "visibleFrame", "actualWindowGeometry"):
        _rect(placement.get(field), field)
    if (
        isinstance(placement.get("cgWindowId"), bool)
        or not isinstance(placement.get("cgWindowId"), int)
        or placement["cgWindowId"] < 1
    ):
        raise ParityError("native placement.cgWindowId must be a positive integer")
    if (
        isinstance(placement.get("windowLayer"), bool)
        or not isinstance(placement.get("windowLayer"), int)
    ):
        raise ParityError("native placement.windowLayer must be an integer")
    safe_area = placement.get("safeAreaInsets")
    if not isinstance(safe_area, dict) or any(
        isinstance(safe_area.get(field), bool)
        or not isinstance(safe_area.get(field), (int, float))
        for field in ("top", "left", "bottom", "right")
    ):
        raise ParityError("native placement.safeAreaInsets must contain numeric edges")
    if window is not None:
        if process["pid"] != window.get("ownerPid"):
            raise ParityError("native process PID does not own the captured window")
        if bundle_id != window.get("ownerBundleId"):
            raise ParityError("native process bundle ID does not own the captured window")
        if placement["cgWindowId"] != window.get("cgWindowId"):
            raise ParityError("native placement window ID does not match captured window")
        if placement["windowLayer"] != window.get("layer"):
            raise ParityError("native placement layer does not match captured window")
        actual_geometry = placement["actualWindowGeometry"]
        window_bounds = window.get("bounds")
        if not isinstance(window_bounds, dict) or any(
            actual_geometry.get(field) != window_bounds.get(field)
            for field in ("x", "y", "width", "height")
        ):
            raise ParityError(
                "native actual placement geometry does not match WindowServer bounds"
            )
    return native


def verify_authenticity_record(
    record: dict[str, Any],
    *,
    sidecar_path: Path,
    expected_renderer: str | None = None,
    require_canonical: bool = False,
) -> dict[str, Any]:
    missing = [field for field in REQUIRED_COMMON if field not in record]
    if missing:
        raise ParityError(f"authenticity sidecar missing fields: {', '.join(missing)}")
    if expected_renderer and record["renderer"] != expected_renderer:
        raise ParityError(
            f"renderer mismatch: expected {expected_renderer}, got {record['renderer']}"
        )
    if record["captureMode"] != "live-window":
        raise ParityError("canonical evidence must use captureMode=live-window")
    if record["captureAPI"] != "ScreenCaptureKit":
        raise ParityError("canonical evidence must use ScreenCaptureKit")
    if record["onScreen"] is not True:
        raise ParityError("canonical evidence window must be on-screen")
    if record.get("proxyRenderer") not in (None, False):
        raise ParityError("proxy/offscreen renderer provenance is forbidden")
    if record.get("result") != "captured":
        raise ParityError("authenticity sidecar result must be captured")
    if require_canonical and record.get("canonicalEligible") is not True:
        reasons = record.get("canonicalIneligibilityReasons", [])
        raise ParityError(
            "canonical verification requires canonicalEligible=true"
            + (f": {', '.join(str(item) for item in reasons)}" if reasons else "")
        )
    if require_canonical:
        if record.get("canonicalIneligibilityReasons") not in ([], None):
            raise ParityError("canonical sidecar must not contain ineligibility reasons")
        profile_validation = record.get("profileValidation")
        if (
            not isinstance(profile_validation, dict)
            or profile_validation.get("cropProven") is not True
        ):
            raise ParityError("canonical sidecar must prove profile crop provenance")
        expected_point_width = profile_validation.get("expectedPointWidth")
        expected_pixel_width = profile_validation.get("expectedPixelWidth")
        source_rect = profile_validation.get("sourceRectPoints")
        window_bounds = profile_validation.get("windowBoundsPoints")
        capture_rect_source = profile_validation.get("captureRectSource")
        if (
            isinstance(expected_point_width, bool)
            or not isinstance(expected_point_width, (int, float))
            or isinstance(expected_pixel_width, bool)
            or not isinstance(expected_pixel_width, int)
            or not isinstance(source_rect, dict)
            or not isinstance(window_bounds, dict)
            or capture_rect_source
            not in {"explicit-live-window-source-rect", "full-live-window"}
        ):
            raise ParityError("canonical sidecar crop provenance fields are invalid")
        for field in ("x", "y", "width", "height"):
            if (
                isinstance(source_rect.get(field), bool)
                or not isinstance(source_rect.get(field), (int, float))
                or isinstance(window_bounds.get(field), bool)
                or not isinstance(window_bounds.get(field), (int, float))
            ):
                raise ParityError(
                    "canonical sidecar crop/window rectangles must be numeric"
                )
        if (
            source_rect["x"] < 0
            or source_rect["y"] < 0
            or source_rect["width"] <= 0
            or source_rect["height"] <= 0
            or source_rect["x"] + source_rect["width"] > window_bounds["width"]
            or source_rect["y"] + source_rect["height"] > window_bounds["height"]
            or source_rect["width"] != expected_point_width
        ):
            raise ParityError(
                "canonical sidecar source rectangle does not prove the profile crop"
            )
        pixel_size = record.get("pixelSize")
        if (
            not isinstance(pixel_size, dict)
            or not isinstance(pixel_size.get("width"), int)
            or not isinstance(pixel_size.get("height"), int)
            or pixel_size["width"] < 1
            or pixel_size["height"] < 1
            or pixel_size["width"] != expected_pixel_width
        ):
            raise ParityError("canonical sidecar must record positive PNG pixel dimensions")
        if (
            capture_rect_source == "full-live-window"
            and (
                source_rect["x"] != 0
                or source_rect["y"] != 0
                or source_rect["width"] != window_bounds["width"]
                or source_rect["height"] != window_bounds["height"]
            )
        ):
            raise ParityError(
                "full-live-window provenance does not match the WindowServer bounds"
            )
    window = record["window"]
    if not isinstance(window, dict):
        raise ParityError("window authenticity must be an object")
    for field in ("cgWindowId", "ownerPid", "bounds", "layer", "isOnScreen"):
        if field not in window:
            raise ParityError(f"window authenticity missing {field}")
    if window["isOnScreen"] is not True:
        raise ParityError("WindowServer record is not on-screen")
    if window.get("ownerPid") is None or not isinstance(window["ownerPid"], int):
        raise ParityError("captured window must have an owner PID")
    if not window.get("ownerBundleId"):
        raise ParityError("captured window must have an owner bundle ID")
    capture_helper = record["captureHelper"]
    if (
        not isinstance(capture_helper, dict)
        or not isinstance(capture_helper.get("sha256"), str)
        or len(capture_helper["sha256"]) != 64
    ):
        raise ParityError("capture helper authenticity must include its SHA-256")
    artifact = (sidecar_path.parent / record["artifactPath"]).resolve()
    if not artifact.is_file():
        raise ParityError(f"captured artifact is missing: {artifact}")
    if sha256_file(artifact) != record["artifactSha256"]:
        raise ParityError("captured artifact hash does not match sidecar")
    if record["renderer"] == "open-island-app":
        native = record.get("nativeSidecar")
        native_expectations = record.get("nativeExpectations")
        if not isinstance(native_expectations, dict):
            raise ParityError("native authenticity is missing coordinator expectations")
        for field, expected in (
            ("scenarioId", record["scenarioId"]),
            ("profileId", record["profileId"]),
        ):
            if native_expectations.get(field) != expected:
                raise ParityError(
                    f"native coordinator {field} mismatch: "
                    f"expected {expected}, got {native_expectations.get(field)}"
                )
        event_arguments = (
            {"expected_event": native_expectations["event"]}
            if "event" in native_expectations
            else {}
        )
        validate_native_provenance(
            native,
            native_sidecar_path=sidecar_path,
            scenario_id=record["scenarioId"],
            profile_id=record["profileId"],
            window=window,
            expected_theme=native_expectations.get("resolvedThemeID"),
            expected_motion=native_expectations.get("motion"),
            expected_accessibility=native_expectations.get("accessibility"),
            **event_arguments,
        )
    return {
        "valid": True,
        "canonicalEligible": record.get("canonicalEligible") is True,
        "renderer": record["renderer"],
        "scenarioId": record["scenarioId"],
        "profileId": record["profileId"],
        "artifactSha256": record["artifactSha256"],
    }


def verify_authenticity_file(
    path: Path,
    *,
    expected_renderer: str | None = None,
    require_canonical: bool = False,
) -> dict[str, Any]:
    return verify_authenticity_record(
        read_json(path),
        sidecar_path=path,
        expected_renderer=expected_renderer,
        require_canonical=require_canonical,
    )
