from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VALIDATION_ROOT = REPOSITORY_ROOT / "Validation" / "HaloParity"
SCENARIO_MANIFEST = VALIDATION_ROOT / "halo-scenarios.json"
MEASUREMENT_SPEC = VALIDATION_ROOT / "measurement-spec-v1.json"
DISPLAY_PROFILES = VALIDATION_ROOT / "display-profiles-v1.json"
REFERENCE_ROOT = VALIDATION_ROOT / "reference"
REFERENCE_AUTHORITY = REFERENCE_ROOT / "reference-authority-v1.json"
CALIBRATION_ROOT = VALIDATION_ROOT / "calibration" / "v1"
ARTIFACT_ROOT = REPOSITORY_ROOT / "artifacts" / "halo-parity"
EXPECTED_SCENARIO_COUNT = 57
ALLOWED_DISPOSITIONS = {
    "exact",
    "temporary-surrogate",
    "temporary-exclusion",
    "blocked",
}


class ParityError(RuntimeError):
    """An actionable validation failure."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def canonical_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        .encode("utf-8")
    )


def strict_json_loads(raw: str, *, source: str) -> Any:
    def reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ParityError(f"duplicate JSON key {key!r} in {source}")
            result[key] = value
        return result

    def reject_constant(value: str) -> Any:
        raise ParityError(f"non-finite JSON number {value} in {source}")

    try:
        return json.loads(
            raw,
            object_pairs_hook=reject_duplicate_pairs,
            parse_constant=reject_constant,
        )
    except json.JSONDecodeError as error:
        raise ParityError(f"invalid JSON {source}: {error}") from error


def read_strict_json(path: Path) -> Any:
    try:
        return strict_json_loads(path.read_text(encoding="utf-8"), source=str(path))
    except FileNotFoundError as error:
        raise ParityError(f"missing required JSON: {path}") from error


def _validate_rfc8785_subset(value: Any, *, path: str = "$") -> None:
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, int):
        if not -(2**53 - 1) <= value <= 2**53 - 1:
            raise ParityError(
                f"{path} uses an integer outside the frozen RFC 8785 safe range"
            )
        return
    if isinstance(value, float):
        raise ParityError(
            f"{path} uses a floating-point number outside the frozen RFC 8785 subset"
        )
    if isinstance(value, str):
        if any(
            ord(character) > 0xFFFF
            or 0xD800 <= ord(character) <= 0xDFFF
            for character in value
        ):
            raise ParityError(
                f"{path} uses a non-BMP or surrogate string outside the frozen "
                "RFC 8785 subset"
            )
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            _validate_rfc8785_subset(item, path=f"{path}[{index}]")
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if not isinstance(key, str):
                raise ParityError(f"{path} has a non-string JSON object key")
            _validate_rfc8785_subset(key, path=f"{path}.<key>")
            _validate_rfc8785_subset(item, path=f"{path}.{key}")
        return
    raise ParityError(f"{path} contains a non-JSON value")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ParityError(f"missing required JSON: {path}") from error
    except json.JSONDecodeError as error:
        raise ParityError(f"invalid JSON {path}: {error}") from error


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def repository_relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPOSITORY_ROOT.resolve()))
    except ValueError:
        return str(path.resolve())


def run(
    command: list[str],
    *,
    check: bool = True,
    cwd: Path = REPOSITORY_ROOT,
    environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=environment,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if check and completed.returncode != 0:
        rendered = " ".join(command)
        raise ParityError(
            f"command failed ({completed.returncode}): {rendered}\n{completed.stdout}"
        )
    return completed


def git_commit() -> str:
    return run(["git", "rev-parse", "HEAD"]).stdout.strip()


def git_dirty() -> bool:
    return bool(run(["git", "status", "--porcelain"]).stdout.strip())


def validate_scenario_manifest(
    manifest: dict[str, Any],
    *,
    require_exact: bool,
) -> dict[str, Any]:
    scenarios = manifest.get("scenarios")
    if not isinstance(scenarios, list):
        raise ParityError("scenario manifest must contain a scenarios array")
    ids = [record.get("id") for record in scenarios if isinstance(record, dict)]
    if len(scenarios) != EXPECTED_SCENARIO_COUNT:
        raise ParityError(
            f"scenario manifest has {len(scenarios)} rows; expected "
            f"{EXPECTED_SCENARIO_COUNT}"
        )
    if len(ids) != len(set(ids)) or any(not isinstance(item, str) or not item for item in ids):
        raise ParityError("scenario IDs must be unique non-empty strings")
    dispositions: dict[str, int] = {}
    for record in scenarios:
        if not isinstance(record, dict):
            raise ParityError("every scenario row must be an object")
        disposition = record.get("disposition")
        if disposition not in ALLOWED_DISPOSITIONS:
            raise ParityError(
                f"scenario {record.get('id')} has invalid disposition {disposition!r}"
            )
        dispositions[disposition] = dispositions.get(disposition, 0) + 1
        for field in (
            "id",
            "intent",
            "fixtureData",
            "html",
            "native",
            "capture",
            "expected",
            "reproductionEvidence",
            "rationale",
        ):
            if field not in record:
                raise ParityError(f"scenario {record.get('id')} is missing {field}")
    if require_exact and dispositions != {"exact": EXPECTED_SCENARIO_COUNT}:
        raise ParityError(
            "Gate 0A requires 57 exact rows; current disposition counts are "
            f"{json.dumps(dispositions, sort_keys=True)}"
        )
    return {
        "scenarioCount": len(scenarios),
        "scenarioIds": ids,
        "dispositions": dispositions,
    }


def validate_profiles(
    profiles: dict[str, Any],
    *,
    require_approval: bool,
    require_resolved_identity: bool = False,
) -> dict[str, Any]:
    records = profiles.get("profiles")
    if not isinstance(records, list) or len(records) != 2:
        raise ParityError("display profile lock must contain exactly two profiles")
    if any(not isinstance(record, dict) for record in records):
        raise ParityError("display profile records must be objects")
    ids = [record.get("id") for record in records]
    if set(ids) != {"notch-v1", "top-bar-v1"}:
        raise ParityError(
            "display profile IDs must be exactly notch-v1 and top-bar-v1"
        )
    resolved_identities: list[tuple[Any, ...]] = []
    unapproved_profiles: list[str] = []
    for record in records:
        for field in (
            "id",
            "displayClass",
            "pointSize",
            "pixelSize",
            "backingScale",
            "colorSpace",
            "refreshTargetHz",
            "captureDisplayIdentity",
            "panel",
            "crop",
            "provenance",
            "approvalStatus",
        ):
            if field not in record:
                raise ParityError(f"display profile {record.get('id')} missing {field}")
        expected_profile_contract = {
            "notch-v1": ("built-in-notch", "internal"),
            "top-bar-v1": ("external-top-bar", "external"),
        }
        expected_display_class, expected_connection = expected_profile_contract[
            record["id"]
        ]
        if record["displayClass"] != expected_display_class:
            raise ParityError(
                f"display profile {record['id']} has invalid displayClass"
            )
        if record["backingScale"] != 2 or record["refreshTargetHz"] != 60:
            raise ParityError(
                f"display profile {record['id']} must be canonical 2x at 60 Hz"
            )
        for size_field in ("pointSize", "pixelSize"):
            size = record[size_field]
            if (
                not isinstance(size, dict)
                or set(size) != {"width", "heightPolicy"}
                or not isinstance(size["width"], int)
                or isinstance(size["width"], bool)
                or size["width"] <= 0
                or not isinstance(size["heightPolicy"], str)
                or not size["heightPolicy"]
            ):
                raise ParityError(
                    f"display profile {record['id']} has invalid {size_field}"
                )
        if (
            not isinstance(record["panel"], dict)
            or not record["panel"]
            or not isinstance(record["crop"], dict)
            or set(record["crop"]) != {"include", "exclude"}
        ):
            raise ParityError(
                f"display profile {record['id']} panel/crop contract is invalid"
            )
        identity = record["captureDisplayIdentity"]
        if not isinstance(identity, dict) or identity.get("status") not in {
            "resolved",
            "pending-external-display",
        }:
            raise ParityError(
                f"display profile {record['id']} has invalid capture display identity"
            )
        if require_resolved_identity:
            if identity["status"] != "resolved":
                raise ParityError(
                    f"display profile {record['id']} has no resolved capture display "
                    "identity"
                )
            identity_fields = (
                "status",
                "displayID",
                "localizedName",
                "connectionType",
                "framePoints",
                "nativePixels",
                "backingScale",
                "maximumFramesPerSecond",
                "iccBytes",
                "iccSha256",
                "productID",
                "vendorID",
                "serialNumber",
            )
            if set(identity) != set(identity_fields):
                raise ParityError(
                    f"display profile {record['id']} capture identity fields are invalid"
                )
            for field in identity_fields[1:]:
                if identity.get(field) in (None, ""):
                    raise ParityError(
                        f"display profile {record['id']} capture identity missing {field}"
                    )
            if identity["connectionType"] != expected_connection:
                raise ParityError(
                    f"display profile {record['id']} capture connection type mismatch"
                )
            for field in (
                "displayID",
                "backingScale",
                "maximumFramesPerSecond",
                "iccBytes",
            ):
                if (
                    not isinstance(identity[field], int)
                    or isinstance(identity[field], bool)
                    or identity[field] <= 0
                ):
                    raise ParityError(
                        f"display profile {record['id']} capture identity has "
                        f"invalid {field}"
                    )
            for field in ("framePoints", "nativePixels"):
                size = identity[field]
                if (
                    not isinstance(size, dict)
                    or set(size) != {"width", "height"}
                    or any(
                        not isinstance(size[dimension], int)
                        or isinstance(size[dimension], bool)
                        or size[dimension] <= 0
                        for dimension in ("width", "height")
                    )
                ):
                    raise ParityError(
                        f"display profile {record['id']} capture identity has "
                        f"invalid {field}"
                    )
            icc_sha256 = identity["iccSha256"]
            if (
                not isinstance(icc_sha256, str)
                or len(icc_sha256) != 64
                or any(
                    character not in "0123456789abcdef"
                    for character in icc_sha256
                )
            ):
                raise ParityError(
                    f"display profile {record['id']} has invalid ICC SHA-256"
                )
            if identity["backingScale"] != record["backingScale"]:
                raise ParityError(
                    f"display profile {record['id']} capture identity scale mismatch"
                )
            resolved_identities.append(
                (
                    identity["productID"],
                    identity["vendorID"],
                    identity["serialNumber"],
                    identity["iccSha256"],
                )
            )
        if require_approval and record["approvalStatus"] != "approved":
            unapproved_profiles.append(
                f"{record['id']} ({record['approvalStatus']})"
            )
    if require_resolved_identity and len(set(resolved_identities)) != 2:
        raise ParityError(
            "notch-v1 and top-bar-v1 must resolve to distinct physical displays"
        )
    if unapproved_profiles:
        raise ParityError(
            "display profiles are not approved: " + ", ".join(unapproved_profiles)
        )
    if require_approval and not profiles.get("approval"):
        raise ParityError("display profile lock is missing authenticated approval")
    return {"profileIds": ids, "profileCount": len(records)}


def validate_reference_authority(authority: Any) -> dict[str, Any]:
    if not isinstance(authority, dict):
        raise ParityError("reference authority must be an object")
    required = {
        "schemaVersion",
        "authorityId",
        "status",
        "source",
        "referenceSeed",
        "designLaws",
        "defaultMode",
        "controllerSchema",
        "events",
        "scenarios",
    }
    if set(authority) != required:
        raise ParityError("reference authority fields do not match the v1 contract")
    if authority["schemaVersion"] != "1.0.0":
        raise ParityError("reference authority schemaVersion must be 1.0.0")
    if authority["authorityId"] != "halo-reference-authority-v1":
        raise ParityError("reference authority ID is invalid")
    if authority["status"] != "pending-authorized-human-approval":
        raise ParityError("reference authority status is invalid")
    source = authority["source"]
    if not isinstance(source, dict) or set(source) != {"path", "sha256"}:
        raise ParityError("reference authority source binding is invalid")
    source_path = REPOSITORY_ROOT / source["path"]
    if source_path.resolve() != (
        REPOSITORY_ROOT / "docs/design/overlay-redesign/06-halo.html"
    ).resolve():
        raise ParityError("reference authority must bind 06-halo.html")
    if not source_path.is_file() or sha256_file(source_path) != source["sha256"]:
        raise ParityError("reference authority source hash does not match 06-halo.html")
    if (
        not isinstance(authority["referenceSeed"], str)
        or not authority["referenceSeed"]
    ):
        raise ParityError("reference authority seed must be non-empty")
    laws = authority["designLaws"]
    if (
        not isinstance(laws, list)
        or len(laws) != 12
        or len(set(laws)) != 12
        or any(not isinstance(law, str) or not law for law in laws)
    ):
        raise ParityError("reference authority must contain 12 unique design laws")
    if authority["defaultMode"] != "inert-original-board":
        raise ParityError("reference authority default mode is invalid")
    controller = authority["controllerSchema"]
    controller_fields = {
        "required",
        "scenarioIds",
        "profiles",
        "motionModes",
        "accessibilityModes",
        "eventIds",
        "seedPattern",
        "timeMs",
    }
    if not isinstance(controller, dict) or set(controller) != controller_fields:
        raise ParityError("reference authority controller schema fields are invalid")
    if controller["profiles"] != ["notch-v1", "top-bar-v1"]:
        raise ParityError("reference authority controller profiles are invalid")
    if controller["motionModes"] != ["manual", "normal", "reduced"]:
        raise ParityError("reference authority controller motion modes are invalid")
    events = authority["events"]
    if (
        not isinstance(events, dict)
        or set(events) != set(controller["eventIds"])
        or any(
            not isinstance(transition, dict)
            or set(transition) != {"to"}
            or not isinstance(transition["to"], str)
            or not transition["to"]
            for transition in events.values()
        )
    ):
        raise ParityError("reference authority event contract is invalid")
    scenarios = authority["scenarios"]
    if not isinstance(scenarios, list) or len(scenarios) != EXPECTED_SCENARIO_COUNT:
        raise ParityError("reference authority must contain exactly 57 scenarios")
    ids = [scenario.get("id") for scenario in scenarios if isinstance(scenario, dict)]
    if (
        len(ids) != EXPECTED_SCENARIO_COUNT
        or len(set(ids)) != EXPECTED_SCENARIO_COUNT
        or any(not isinstance(item, str) or not item for item in ids)
    ):
        raise ParityError("reference authority scenario IDs must be unique")
    manifest_ids = sorted(
        record["id"] for record in read_json(SCENARIO_MANIFEST)["scenarios"]
    )
    if sorted(ids) != manifest_ids:
        raise ParityError("reference authority and scenario manifest ID sets differ")
    if (
        controller["scenarioIds"] != ids
        or len(set(controller["scenarioIds"])) != EXPECTED_SCENARIO_COUNT
    ):
        raise ParityError(
            "reference authority controller scenario IDs must match scenario order"
        )
    for scenario in scenarios:
        if not isinstance(scenario, dict):
            raise ParityError("reference authority scenario rows must be objects")
        expected_fields = {
            "id",
            "referenceSection",
            "intent",
            "mapping",
            "expected",
            "checkpoints",
            "referenceEvents",
        }
        if set(scenario) != expected_fields:
            raise ParityError(
                f"reference authority scenario {scenario.get('id')} fields are invalid"
            )
        checkpoints = scenario["checkpoints"]
        if (
            not isinstance(checkpoints, dict)
            or set(checkpoints) != {"stable", "timed"}
            or any(
                not isinstance(checkpoints[field], list)
                or any(
                    not isinstance(item, str) or not item
                    for item in checkpoints[field]
                )
                for field in ("stable", "timed")
            )
        ):
            raise ParityError(
                f"reference authority scenario {scenario['id']} checkpoints are invalid"
            )
        mapping = scenario["mapping"]
        if not isinstance(mapping, dict) or mapping.get("kind") not in {
            "established-anchor",
            "authored-variant",
        }:
            raise ParityError(
                f"reference authority scenario {scenario['id']} mapping is invalid"
            )
        if mapping["kind"] == "established-anchor":
            if set(mapping) != {"kind", "selector", "stateMechanism"}:
                raise ParityError(
                    f"reference authority scenario {scenario['id']} established "
                    "mapping fields are invalid"
                )
        else:
            authored_fields = {
                "kind",
                "variantId",
                "selector",
                "sourceAnchor",
                "laws",
                "decision",
            }
            if set(mapping) != authored_fields:
                raise ParityError(
                    f"reference authority scenario {scenario['id']} authored "
                    "mapping fields are invalid"
                )
            if mapping["variantId"] != scenario["id"]:
                raise ParityError(
                    f"reference authority scenario {scenario['id']} variant ID mismatch"
                )
            decision = mapping["decision"]
            if (
                not isinstance(decision, dict)
                or set(decision)
                != {"cloneSelector", "laws", "eventSeam", "patches"}
                or decision["cloneSelector"] != mapping["sourceAnchor"]
                or decision["laws"] != mapping["laws"]
                or any(law not in laws for law in mapping["laws"])
            ):
                raise ParityError(
                    f"reference authority scenario {scenario['id']} authored "
                    "decision is invalid"
                )
            event_seam = decision["eventSeam"]
            if (
                not isinstance(event_seam, dict)
                or set(event_seam)
                != {
                    "frameZeroEvent",
                    "clockModes",
                    "stableCheckpoints",
                    "timedCheckpoints",
                    "deterministicPhaseKey",
                }
                or event_seam["frameZeroEvent"] not in events
                or event_seam["stableCheckpoints"] != scenario["checkpoints"]["stable"]
                or event_seam["timedCheckpoints"] != scenario["checkpoints"]["timed"]
                or event_seam["clockModes"] not in (
                    ["manual"],
                    ["normal"],
                    ["manual", "normal"],
                )
                or not isinstance(decision["patches"], list)
                or not decision["patches"]
            ):
                raise ParityError(
                    f"reference authority scenario {scenario['id']} event seam is invalid"
                )
            for patch in decision["patches"]:
                if (
                    not isinstance(patch, dict)
                    or not {"op", "selector", "value"} <= set(patch)
                    or not set(patch) <= {"op", "selector", "name", "value"}
                    or patch["op"]
                    not in {
                        "appendBadge",
                        "replaceText",
                        "setAttribute",
                        "setStateClass",
                    }
                    or not isinstance(patch["selector"], str)
                    or not patch["selector"]
                    or not isinstance(patch["value"], str)
                    or (
                        patch["op"] == "setAttribute"
                        and (
                            not isinstance(patch.get("name"), str)
                            or not patch["name"]
                        )
                    )
                ):
                    raise ParityError(
                        f"reference authority scenario {scenario['id']} patch is invalid"
                    )
        expected = scenario["expected"]
        if (
            not isinstance(expected, dict)
            or set(expected)
            != {
                "visibleCopy",
                "grouping",
                "order",
                "stateMembership",
                "lightBehavior",
            }
            or not isinstance(expected["lightBehavior"], str)
            or not expected["lightBehavior"]
            or any(
                not isinstance(expected[field], list)
                or any(not isinstance(item, str) or not item for item in expected[field])
                for field in ("visibleCopy", "grouping", "order", "stateMembership")
            )
        ):
            raise ParityError(
                f"reference authority scenario {scenario['id']} expected contract is invalid"
            )
        reference_events = scenario["referenceEvents"]
        if (
            not isinstance(reference_events, list)
            or len(reference_events) != len(set(reference_events))
            or any(event not in events for event in reference_events)
        ):
            raise ParityError(
                f"reference authority scenario {scenario['id']} reference events are invalid"
            )
    _validate_rfc8785_subset(authority)
    return {"scenarioIds": ids, "scenarioCount": len(ids)}


def make_gate_0a_authority_projection(
    authority: Any,
    profiles: Any,
) -> dict[str, Any]:
    validated = validate_reference_authority(authority)
    validate_profiles(
        profiles,
        require_approval=False,
        require_resolved_identity=True,
    )
    projected_profiles = []
    for record in sorted(profiles["profiles"], key=lambda item: item["id"]):
        projected_profiles.append(
            {
                "id": record["id"],
                "displayClass": record["displayClass"],
                "pointSize": record["pointSize"],
                "pixelSize": record["pixelSize"],
                "backingScale": record["backingScale"],
                "colorSpace": record["colorSpace"],
                "refreshTargetHz": record["refreshTargetHz"],
                "panel": record["panel"],
                "crop": record["crop"],
                "captureDisplayIdentity": {
                    field: record["captureDisplayIdentity"][field]
                    for field in (
                        "status",
                        "displayID",
                        "localizedName",
                        "connectionType",
                        "framePoints",
                        "nativePixels",
                        "backingScale",
                        "maximumFramesPerSecond",
                        "iccBytes",
                        "iccSha256",
                        "productID",
                        "vendorID",
                        "serialNumber",
                    )
                },
            }
        )
    projection = {
        "schemaVersion": "1.0.0",
        "projectionType": "halo-gate-0a-reference-and-display-authority",
        "referenceAuthority": authority,
        "displayProfiles": projected_profiles,
        "scenarioIds": sorted(validated["scenarioIds"]),
    }
    _validate_rfc8785_subset(projection)
    return projection


def validate_gate_0a_authority_projection(projection: Any) -> dict[str, Any]:
    if not isinstance(projection, dict):
        raise ParityError("Gate 0A authority projection must be an object")
    if set(projection) != {
        "schemaVersion",
        "projectionType",
        "referenceAuthority",
        "displayProfiles",
        "scenarioIds",
    }:
        raise ParityError("Gate 0A authority projection fields are invalid")
    if projection["schemaVersion"] != "1.0.0":
        raise ParityError("Gate 0A authority projection schemaVersion is invalid")
    if (
        projection["projectionType"]
        != "halo-gate-0a-reference-and-display-authority"
    ):
        raise ParityError("Gate 0A authority projection type is invalid")
    authority_summary = validate_reference_authority(
        projection["referenceAuthority"]
    )
    profiles = {"profiles": []}
    for record in projection["displayProfiles"]:
        if not isinstance(record, dict):
            raise ParityError("Gate 0A projected display profile must be an object")
        projected_fields = {
            "id",
            "displayClass",
            "pointSize",
            "pixelSize",
            "backingScale",
            "colorSpace",
            "refreshTargetHz",
            "panel",
            "crop",
            "captureDisplayIdentity",
        }
        if set(record) != projected_fields:
            raise ParityError(
                f"Gate 0A projected display profile {record.get('id')} fields are invalid"
            )
        profiles["profiles"].append(
            {
                **record,
                "provenance": "projection-validation-only",
                "approvalStatus": "pending",
            }
        )
    validate_profiles(
        profiles,
        require_approval=False,
        require_resolved_identity=True,
    )
    if projection["scenarioIds"] != sorted(authority_summary["scenarioIds"]):
        raise ParityError(
            "Gate 0A authority projection scenario IDs do not match its authority"
        )
    _validate_rfc8785_subset(projection)
    return {
        "scenarioCount": len(projection["scenarioIds"]),
        "profileCount": len(projection["displayProfiles"]),
    }


def validate_measurement_spec(spec: dict[str, Any]) -> dict[str, Any]:
    required = (
        "schemaVersion",
        "specId",
        "status",
        "coordinateSpaces",
        "registration",
        "sampling",
        "staticMetrics",
        "motionMetrics",
        "semanticChecks",
        "interactionChecks",
        "accessibilityChecks",
        "hardCaps",
        "forbiddenInputs",
    )
    for field in required:
        if field not in spec:
            raise ParityError(f"measurement spec is missing {field}")
    if spec["status"] != "frozen-before-calibration":
        raise ParityError("measurement spec status must be frozen-before-calibration")
    forbidden = spec.get("forbiddenInputs", [])
    if "halo-reference-divergence" not in forbidden or "halo-candidate-divergence" not in forbidden:
        raise ParityError("measurement spec must forbid Halo divergence inputs")
    return {"measurementSpecId": spec["specId"]}


def file_record(path: Path, role: str) -> dict[str, Any]:
    return {
        "path": repository_relative(path),
        "role": role,
        "sha256": sha256_file(path),
        "bytes": path.stat().st_size,
    }


def make_spec_lock(*, allow_unapproved: bool) -> dict[str, Any]:
    manifest = read_json(SCENARIO_MANIFEST)
    profiles = read_json(DISPLAY_PROFILES)
    measurement = read_json(MEASUREMENT_SPEC)
    manifest_summary = validate_scenario_manifest(manifest, require_exact=False)
    profile_summary = validate_profiles(profiles, require_approval=not allow_unapproved)
    measurement_summary = validate_measurement_spec(measurement)
    inputs = [
        file_record(SCENARIO_MANIFEST, "scenario-manifest"),
        file_record(DISPLAY_PROFILES, "display-profile-lock"),
        file_record(MEASUREMENT_SPEC, "measurement-spec"),
    ]
    reference_spec = REFERENCE_ROOT / "reference-spec-v1.json"
    reference_lock = REFERENCE_ROOT / "reference-input-lock-v1.json"
    for path, role in (
        (reference_spec, "reference-spec"),
        (reference_lock, "reference-input-lock"),
    ):
        if path.exists():
            inputs.append(file_record(path, role))
        elif not allow_unapproved:
            raise ParityError(f"missing strict Gate 0A input: {path}")
    lock_body = {
        "schemaVersion": "1.0.0",
        "lockVersion": "v1",
        "createdAt": utc_now(),
        "commitSha": git_commit(),
        "dirty": git_dirty(),
        "allowUnapproved": allow_unapproved,
        "manifest": manifest_summary,
        "profiles": profile_summary,
        "measurement": measurement_summary,
        "inputs": inputs,
    }
    lock_body["lockSha256"] = sha256_bytes(canonical_json_bytes(lock_body))
    return lock_body


def environment_fingerprint() -> dict[str, Any]:
    commands = {
        "xcode": ["xcodebuild", "-version"],
        "swift": ["swift", "--version"],
        "ffmpeg": ["ffmpeg", "-version"],
        # OpenSSH exposes its version through `ssh -V`; `ssh-keygen` has no
        # non-interactive version flag (`-V` is a certificate-validity option).
        "sshKeygen": ["ssh", "-V"],
    }
    tools: dict[str, Any] = {}
    for name, command in commands.items():
        executable = shutil.which(command[0])
        if not executable:
            tools[name] = {"available": False}
            continue
        completed = run(command, check=False)
        tools[name] = {
            "available": True,
            "path": executable,
            "version": completed.stdout.splitlines()[0] if completed.stdout else "",
            "exitCode": completed.returncode,
        }
    try:
        import cv2
        import numpy
        import PIL
        import scipy

        python_libraries = {
            "opencv": cv2.__version__,
            "numpy": numpy.__version__,
            "pillow": PIL.__version__,
            "scipy": scipy.__version__,
        }
    except Exception as error:  # pragma: no cover - doctor reports host variance
        python_libraries = {"error": str(error)}
    return {
        "capturedAt": utc_now(),
        "commitSha": git_commit(),
        "dirty": git_dirty(),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "python": sys.version.split()[0],
        "timezone": os.environ.get("TZ"),
        "displays": display_fingerprint(),
        "tools": tools,
        "pythonLibraries": python_libraries,
    }


def display_fingerprint() -> dict[str, Any]:
    """Return current AppKit/ColorSync and system-profiler display identity."""

    swift = shutil.which("swift")
    system_profiler = shutil.which("system_profiler")
    result: dict[str, Any] = {}
    if swift:
        source = r"""
import AppKit
import CryptoKit
import Foundation

let screens: [[String: Any]] = NSScreen.screens.map { screen in
    let icc = screen.colorSpace?.iccProfileData ?? Data()
    let iccHash = icc.isEmpty
        ? ""
        : SHA256.hash(data: icc).map { String(format: "%02x", $0) }.joined()
    let number = screen.deviceDescription[
        NSDeviceDescriptionKey("NSScreenNumber")
    ] as? NSNumber
    return [
        "localizedName": screen.localizedName,
        "displayID": number?.uint32Value ?? 0,
        "frame": [
            "x": screen.frame.origin.x,
            "y": screen.frame.origin.y,
            "width": screen.frame.width,
            "height": screen.frame.height,
        ],
        "visibleFrame": [
            "x": screen.visibleFrame.origin.x,
            "y": screen.visibleFrame.origin.y,
            "width": screen.visibleFrame.width,
            "height": screen.visibleFrame.height,
        ],
        "backingScaleFactor": screen.backingScaleFactor,
        "maximumFramesPerSecond": screen.maximumFramesPerSecond,
        "colorSpaceName": screen.colorSpace?.localizedName ?? "",
        "iccSha256": iccHash,
        "iccBytes": icc.count,
    ]
}
let data = try JSONSerialization.data(
    withJSONObject: screens,
    options: [.sortedKeys]
)
FileHandle.standardOutput.write(data)
"""
        completed = subprocess.run(
            [swift, "-e", source],
            cwd=REPOSITORY_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        result["appKit"] = {
            "available": completed.returncode == 0,
            "exitCode": completed.returncode,
        }
        if completed.returncode == 0:
            try:
                screens = json.loads(completed.stdout)
                result["appKit"]["screens"] = screens
                result["appKit"]["screenCount"] = len(screens)
            except json.JSONDecodeError as error:
                result["appKit"]["available"] = False
                result["appKit"]["error"] = f"invalid display probe JSON: {error}"
        else:
            result["appKit"]["error"] = completed.stdout.strip()
    else:
        result["appKit"] = {"available": False, "error": "swift not found"}

    if system_profiler:
        completed = run(
            [system_profiler, "SPDisplaysDataType", "-json"],
            check=False,
        )
        result["systemProfiler"] = {
            "available": completed.returncode == 0,
            "exitCode": completed.returncode,
        }
        if completed.returncode == 0:
            try:
                result["systemProfiler"]["value"] = json.loads(completed.stdout)
            except json.JSONDecodeError as error:
                result["systemProfiler"]["available"] = False
                result["systemProfiler"]["error"] = (
                    f"invalid system_profiler JSON: {error}"
                )
        else:
            result["systemProfiler"]["error"] = completed.stdout.strip()
    else:
        result["systemProfiler"] = {
            "available": False,
            "error": "system_profiler not found",
        }
    return result


@dataclass(frozen=True)
class Check:
    name: str
    passed: bool
    detail: str
    hard: bool = True

    def as_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "passed": self.passed,
            "detail": self.detail,
            "hard": self.hard,
        }


def evidence_index(root: Path) -> dict[str, Any]:
    if not root.is_dir():
        raise ParityError(f"evidence root is not a directory: {root}")
    records = [
        file_record(path, "evidence")
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.name != "evidence-index.json"
    ]
    index = {
        "schemaVersion": "1.0.0",
        "createdAt": utc_now(),
        "commitSha": git_commit(),
        "root": repository_relative(root),
        "files": records,
    }
    index["indexSha256"] = sha256_bytes(canonical_json_bytes(index))
    return index
