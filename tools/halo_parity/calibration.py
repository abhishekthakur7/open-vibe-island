from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from .core import ParityError, canonical_json_bytes, read_json, sha256_bytes, sha256_file
from .neutral_analysis import SUITE_ID, analyze_gate_0b_manifest


ALLOWED_CONTENT_ROLE = "neutral-calibration"
FORBIDDEN_ROLES = {
    "halo-reference",
    "halo-native",
    "candidate",
    "parity-difference",
    "known-defect",
}


def _load_rgba(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if image is None:
        raise ParityError(f"unable to decode calibration PNG: {path}")
    if image.ndim == 2:
        image = image[:, :, None]
    return image.astype(np.float32)


def validate_neutral_manifest(path: Path) -> dict[str, Any]:
    manifest = read_json(path)
    if manifest.get("contentRole") != ALLOWED_CONTENT_ROLE:
        raise ParityError("calibration input must declare contentRole=neutral-calibration")
    if manifest.get("sourceRole") in FORBIDDEN_ROLES:
        raise ParityError("Halo/candidate divergence is forbidden calibration input")
    if manifest.get("haloSourceHashes"):
        raise ParityError("calibration input may not include Halo source hashes")
    samples = manifest.get("samples")
    if not isinstance(samples, list) or not samples:
        raise ParityError("neutral calibration manifest must contain samples")
    for sample in samples:
        if sample.get("contentRole") != ALLOWED_CONTENT_ROLE:
            raise ParityError("every calibration sample must be neutral-calibration")
        if sample.get("sourceRole") in FORBIDDEN_ROLES:
            raise ParityError("forbidden Halo-derived calibration sample")
        relative = Path(sample.get("path", ""))
        if not relative.name.lower().endswith(".png"):
            raise ParityError(f"calibration sample is not PNG: {relative}")
        if relative.name.lower().startswith("halo-"):
            raise ParityError("Halo-named images are not neutral calibration inputs")
        absolute = (path.parent / relative).resolve()
        if not absolute.is_file():
            raise ParityError(f"missing calibration sample: {absolute}")
        expected = sample.get("sha256")
        if expected and sha256_file(absolute) != expected:
            raise ParityError(f"calibration sample hash mismatch: {relative}")
    return manifest


def validate_neutral_renderer_manifest(
    path: Path,
    *,
    profile_id: str,
    window: dict[str, Any],
    expected_point_width: float,
    expected_pixel_width: int,
) -> dict[str, Any]:
    manifest = read_json(path)
    if manifest.get("schemaVersion") != "1.0.0":
        raise ParityError("neutral renderer manifest schemaVersion must be 1.0.0")
    if manifest.get("suiteId") != "halo-neutral-calibration-v1":
        raise ParityError("neutral renderer manifest suiteId is invalid")
    if manifest.get("contentRole") != ALLOWED_CONTENT_ROLE:
        raise ParityError("neutral renderer manifest must be neutral-calibration")
    if manifest.get("renderer") != "native-swiftui-calibration":
        raise ParityError("neutral renderer manifest has the wrong renderer")
    if manifest.get("haloSourceHashes") != []:
        raise ParityError("neutral renderer manifest must not bind Halo source hashes")
    if manifest.get("profileId") != profile_id:
        raise ParityError("neutral renderer manifest profile mismatch")
    process = manifest.get("process")
    if (
        not isinstance(process, dict)
        or process.get("pid") != window.get("ownerPid")
        or process.get("bundleId") != window.get("ownerBundleId")
    ):
        raise ParityError("neutral renderer manifest process does not own the window")
    executable = Path(str(process.get("executablePath", ""))).resolve()
    if not executable.is_file():
        raise ParityError("neutral renderer executable is missing")
    manifest_window = manifest.get("window")
    point_size = (
        manifest_window.get("pointSize")
        if isinstance(manifest_window, dict)
        else None
    )
    if (
        not isinstance(manifest_window, dict)
        or manifest_window.get("cgWindowId") != window.get("cgWindowId")
        or not isinstance(point_size, dict)
        or point_size.get("width") != expected_point_width
        or point_size.get("height") != 320
    ):
        raise ParityError("neutral renderer manifest window geometry mismatch")
    display = manifest.get("display")
    if not isinstance(display, dict) or display.get("backingScale") != 2:
        raise ParityError("neutral renderer manifest did not prove a 2x display")
    mapping = manifest.get("mapping")
    expected_pixels = (
        mapping.get("expectedPixelSize") if isinstance(mapping, dict) else None
    )
    if (
        not isinstance(mapping, dict)
        or mapping.get("swiftUiPointToDevicePixel") != 2
        or not isinstance(expected_pixels, dict)
        or expected_pixels.get("width") != expected_pixel_width
        or expected_pixels.get("height") != 640
    ):
        raise ParityError("neutral renderer manifest pixel mapping mismatch")
    return manifest


def analyze_neutral_manifest(path: Path) -> dict[str, Any]:
    candidate = read_json(path)
    if candidate.get("suiteId") == SUITE_ID or candidate.get("gate0BStrict") is True:
        return analyze_gate_0b_manifest(path)
    manifest = validate_neutral_manifest(path)
    grouped: dict[tuple[str, str, str], list[tuple[dict[str, Any], np.ndarray]]] = defaultdict(list)
    for sample in manifest["samples"]:
        key = (sample["renderer"], sample["profileId"], sample["primitiveId"])
        image = _load_rgba((path.parent / sample["path"]).resolve())
        grouped[key].append((sample, image))
    groups: list[dict[str, Any]] = []
    for key in sorted(grouped):
        samples = grouped[key]
        if len(samples) < 2:
            raise ParityError(
                f"neutral group {key} has {len(samples)} sample; at least 2 required "
                "for bootstrap analysis"
            )
        shapes = {image.shape for _, image in samples}
        if len(shapes) != 1:
            raise ParityError(f"neutral group {key} has inconsistent dimensions")
        reference = samples[0][1]
        mean_abs = []
        p95_abs = []
        changed_fraction = []
        for _, image in samples[1:]:
            difference = np.abs(image - reference)
            mean_abs.append(float(np.mean(difference)))
            p95_abs.append(float(np.percentile(difference, 95)))
            changed_fraction.append(float(np.mean(np.any(difference > 0, axis=2))))
        groups.append(
            {
                "renderer": key[0],
                "profileId": key[1],
                "primitiveId": key[2],
                "sampleCount": len(samples),
                "shape": list(reference.shape),
                "meanAbsoluteChannelDeltaMax": max(mean_abs),
                "p95AbsoluteChannelDeltaMax": max(p95_abs),
                "changedPixelFractionMax": max(changed_fraction),
            }
        )
    report = {
        "schemaVersion": "1.0.0",
        "reportType": "neutral-repeatability",
        "contentRole": ALLOWED_CONTENT_ROLE,
        "sourceManifest": str(path),
        "sourceManifestSha256": sha256_file(path),
        "groups": groups,
        "forbiddenInputsObserved": [],
    }
    report["reportSha256"] = sha256_bytes(canonical_json_bytes(report))
    return report


def threshold_proposal(report: dict[str, Any], *, version: str) -> dict[str, Any]:
    if (
        report.get("schemaVersion") == "2.0.0"
        and report.get("reportType") == "gate-0b-neutral-static-analysis"
    ):
        return _strict_threshold_proposal(report, version=version)
    groups = report.get("groups", [])
    if not groups:
        raise ParityError("neutral report has no groups")
    max_p95 = max(group["p95AbsoluteChannelDeltaMax"] for group in groups)
    max_changed = max(group["changedPixelFractionMax"] for group in groups)
    proposal = {
        "schemaVersion": "1.0.0",
        "profileId": f"halo-neutral-thresholds-{version}",
        "status": "proposed-unapproved",
        "sourceRole": ALLOWED_CONTENT_ROLE,
        "sourceReportSha256": report["reportSha256"],
        "sampleGroupCount": len(groups),
        "repeatability": {
            "p95AbsoluteChannelDelta": math.ceil(max_p95 * 1000) / 1000,
            "changedPixelFraction": math.ceil(max_changed * 1_000_000) / 1_000_000,
        },
        "hardCaps": {
            "interiorBlackRGB": [0, 0, 0],
            "registrationPhysicalPxMax": 0.5,
            "silhouetteIoUMin": 0.99,
            "silhouetteHausdorffPhysicalPxMax": 1.0,
            "neutralSolidMedianDeltaE00Max": 1.0,
            "neutralSolidP95DeltaE00Max": 2.0,
            "unexpectedDroppedFramesMax": 0,
            "unexpectedDuplicateFramesMax": 0,
            "motionBoundaryRefreshFramesMax": 1,
        },
        "forbiddenInputs": sorted(FORBIDDEN_ROLES),
    }
    proposal["proposalSha256"] = sha256_bytes(canonical_json_bytes(proposal))
    return proposal


def _strict_threshold_proposal(
    report: dict[str, Any], *, version: str
) -> dict[str, Any]:
    supplied_hash = report.get("reportSha256")
    unsigned = dict(report)
    unsigned.pop("reportSha256", None)
    if supplied_hash != sha256_bytes(canonical_json_bytes(unsigned)):
        raise ParityError("strict Gate 0B report hash is invalid")
    if report.get("gate0BPass") is not True:
        raise ParityError("thresholds cannot be proposed from a failed Gate 0B report")
    bindings = report.get("evidenceBindings")
    bound_fields = (
        "captureAuthenticity",
        "observations",
        "sameRendererAllPairs",
        "translationRegistration",
        "crossRendererProfileMatched",
        "unitTransformProof",
        "colorPatchAnalysis",
        "textAnalysis",
    )
    if not isinstance(bindings, dict) or set(bindings) != set(bound_fields):
        raise ParityError("strict Gate 0B evidence bindings are incomplete")
    for field in bound_fields:
        if bindings[field] != sha256_bytes(canonical_json_bytes(report.get(field))):
            raise ParityError(f"strict Gate 0B evidence binding mismatch: {field}")

    repeatability = report.get("sameRendererAllPairs")
    cross_renderer = report.get("crossRendererProfileMatched")
    if not isinstance(repeatability, list) or not isinstance(cross_renderer, list):
        raise ParityError("strict Gate 0B report has no neutral distributions")
    repeat_lookup: defaultdict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for item in repeatability:
        repeat_lookup[(item["profileId"], item["primitiveId"])].append(item)
    cross_lookup = {
        (item["profileId"], item["primitiveId"]): item for item in cross_renderer
    }
    expected = {
        (profile, primitive)
        for profile in ("notch-v1", "top-bar-v1")
        for primitive in (
            "registration-grid",
            "solid-srgb-patches",
            "neutral-width-lines",
            "rounded-geometry",
            "alpha-gradient-stack",
            "neutral-bloom",
            "font-raster-boxes",
            "motion-track",
        )
    }
    if set(repeat_lookup) != expected or set(cross_lookup) != expected:
        raise ParityError("strict Gate 0B threshold matrix is incomplete")
    if any(len(values) != 2 for values in repeat_lookup.values()):
        raise ParityError("strict Gate 0B thresholds require both renderer distributions")

    metric_fields = (
        "meanAbsoluteChannelDelta",
        "p95AbsoluteChannelDelta",
        "changedPixelFraction",
    )
    thresholds = []
    for key in sorted(expected):
        metrics = {}
        for metric in metric_fields:
            repeat_max = max(
                float(item[metric]["maximum"]) for item in repeat_lookup[key]
            )
            repeat_p95 = max(float(item[metric]["p95"]) for item in repeat_lookup[key])
            cross_max = float(cross_lookup[key][metric]["maximum"])
            cross_p95 = float(cross_lookup[key][metric]["p95"])
            stable_renderer_variance = max(0.0, cross_max - repeat_max)
            statistical_margin = max(
                0.0,
                repeat_max - repeat_p95,
                cross_max - cross_p95,
            )
            metrics[metric] = {
                "repeatabilityNoiseFloor": repeat_max,
                "stableNeutralRendererVariance": stable_renderer_variance,
                "statisticalSafetyMargin": statistical_margin,
                "proposedTolerance": (
                    repeat_max + stable_renderer_variance + statistical_margin
                ),
            }
        thresholds.append(
            {"profileId": key[0], "primitiveId": key[1], "metrics": metrics}
        )

    text_thresholds = []
    logical = report["textAnalysis"]["logicalLayout"]
    if logical.get("status") != "provenance-verified-and-measured":
        raise ParityError("strict Gate 0B text layout provenance is not verified")
    for comparison in logical.get("comparisons", []):
        fields = {}
        for field, distribution in sorted(
            comparison["deltaDistributionsLogicalUnits"].items()
        ):
            maximum = float(distribution["maximum"])
            p95 = float(distribution["p95"])
            margin = max(0.0, maximum - p95)
            fields[field] = {
                "stableNeutralRendererVariance": maximum,
                "statisticalSafetyMargin": margin,
                "proposedToleranceLogicalUnits": maximum + margin,
            }
        text_thresholds.append(
            {"profileId": comparison["profileId"], "fields": fields}
        )

    color_thresholds = []
    for profile in report["colorPatchAnalysis"].get("profiles", []):
        distribution = profile["deltaE2000"]
        maximum = float(distribution["maximum"])
        p95 = float(distribution["p95"])
        margin = max(0.0, maximum - p95)
        color_thresholds.append(
            {
                "profileId": profile["profileId"],
                "stableNeutralRendererVarianceDeltaE2000": maximum,
                "statisticalSafetyMarginDeltaE2000": margin,
                "proposedToleranceDeltaE2000": maximum + margin,
            }
        )
    if len(color_thresholds) != 2:
        raise ParityError("strict Gate 0B color distributions are incomplete")

    proposal = {
        "schemaVersion": "2.0.0",
        "profileId": f"halo-neutral-thresholds-{version}",
        "status": "proposed-unapproved",
        "sourceRole": ALLOWED_CONTENT_ROLE,
        "sourceReportSha256": supplied_hash,
        "derivationRule": {
            "id": "neutral-tail-span-v1",
            "formula": (
                "repeatability_max + max(0,cross_renderer_max-repeatability_max) "
                "+ max(repeatability_max-repeatability_p95,"
                "cross_renderer_max-cross_renderer_p95,0)"
            ),
            "rationale": (
                "budgets measured repeatability and stable neutral renderer variance; "
                "the empirical p95-to-maximum tail span is the finite-sample margin"
            ),
            "candidateOrHaloDivergenceUsed": False,
        },
        "staticPrimitiveThresholds": thresholds,
        "textLogicalLayoutThresholds": text_thresholds,
        "colorPatchThresholds": color_thresholds,
        "hardInvariants": {
            "separateFromLearnedTolerance": True,
            "registrationEvidenceSha256": bindings["translationRegistration"],
            "unitTransformEvidenceSha256": bindings["unitTransformProof"],
            "textEvidenceSha256": bindings["textAnalysis"],
            "colorEvidenceSha256": bindings["colorPatchAnalysis"],
        },
        "evidenceBindings": dict(bindings),
        "forbiddenInputs": sorted(FORBIDDEN_ROLES),
    }
    proposal["proposalSha256"] = sha256_bytes(canonical_json_bytes(proposal))
    return proposal
