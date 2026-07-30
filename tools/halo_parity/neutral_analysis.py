from __future__ import annotations

import io
import math
from collections import defaultdict
from pathlib import Path
from types import MappingProxyType
from typing import Any, Iterable

import cv2
import numpy as np
from PIL import Image, ImageCms

from .core import ParityError, canonical_json_bytes, read_json, sha256_bytes, sha256_file


SUITE_ID = "halo-neutral-calibration-v1"
RENDERERS = frozenset(("in-app-browser", "open-island-app"))
PROFILES = MappingProxyType({"notch-v1": (540, 320), "top-bar-v1": (520, 320)})
PRIMITIVES = (
    "registration-grid",
    "solid-srgb-patches",
    "neutral-width-lines",
    "rounded-geometry",
    "alpha-gradient-stack",
    "neutral-bloom",
    "font-raster-boxes",
    "motion-track",
)
STATIC_REPETITIONS = 10
SCALE = 2
PHYSICAL_PIXEL_EPSILON = 1e-6


def _logical_rois(width: int) -> dict[str, tuple[float, float, float, float]]:
    # Both frozen renderers use a one-unit outer rule, 12-unit inset, 8-unit gap,
    # two equal columns, and four equal rows. The native 13-unit origin is the
    # same border-box geometry as the HTML's one-unit rule plus 12-unit padding.
    column_width = (width - 34) / 2
    row_height = 67.5
    return {
        primitive: (
            13 + (index % 2) * (column_width + 8),
            13 + (index // 2) * (row_height + 8),
            column_width,
            row_height,
        )
        for index, primitive in enumerate(PRIMITIVES)
    }


LOGICAL_ROIS = MappingProxyType(
    {
        profile: MappingProxyType(_logical_rois(size[0]))
        for profile, size in PROFILES.items()
    }
)
DEVICE_ROIS = MappingProxyType(
    {
        profile: MappingProxyType(
            {
                primitive: tuple(int(round(value * SCALE)) for value in roi)
                for primitive, roi in LOGICAL_ROIS[profile].items()
            }
        )
        for profile in PROFILES
    }
)


def _load_rgba(path: Path) -> np.ndarray:
    image = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if image is None:
        raise ParityError(f"unable to decode calibration PNG: {path}")
    if image.ndim == 2:
        image = cv2.cvtColor(image, cv2.COLOR_GRAY2RGBA)
    elif image.shape[2] == 3:
        image = cv2.cvtColor(image, cv2.COLOR_BGR2RGBA)
    elif image.shape[2] == 4:
        image = cv2.cvtColor(image, cv2.COLOR_BGRA2RGBA)
    else:
        raise ParityError(f"unsupported calibration PNG channel count: {path}")
    return image


def _resolve_relative_file(root: Path, raw: Any, *, label: str, suffix: str) -> Path:
    relative = Path(str(raw or ""))
    if (
        relative.is_absolute()
        or ".." in relative.parts
        or relative.suffix.lower() != suffix
    ):
        raise ParityError(f"{label} must be a relative {suffix} path without '..'")
    absolute = (root / relative).resolve()
    if not absolute.is_relative_to(root.resolve()):
        raise ParityError(f"{label} resolves outside its evidence directory")
    if not absolute.is_file():
        raise ParityError(f"missing {label}: {absolute}")
    return absolute


def _crop_png_hash(crop: np.ndarray) -> str:
    encoded_source = cv2.cvtColor(crop, cv2.COLOR_RGBA2BGRA)
    ok, encoded = cv2.imencode(".png", encoded_source)
    if not ok:
        raise ParityError("unable to encode derived neutral crop")
    return sha256_bytes(encoded.tobytes())


def _distribution(values: Iterable[float]) -> dict[str, float | int]:
    array = np.asarray(list(values), dtype=np.float64)
    if not len(array):
        raise ParityError("cannot summarize an empty metric distribution")
    return {
        "count": int(len(array)),
        "minimum": float(np.min(array)),
        "maximum": float(np.max(array)),
        "mean": float(np.mean(array)),
        "p50": float(np.percentile(array, 50)),
        "p95": float(np.percentile(array, 95)),
        "p99": float(np.percentile(array, 99)),
    }


def _pair_metrics(first: np.ndarray, second: np.ndarray) -> tuple[float, float, float]:
    difference = np.abs(first.astype(np.float32) - second.astype(np.float32))
    return (
        float(np.mean(difference)),
        float(np.percentile(difference, 95)),
        float(np.mean(np.any(difference > 0, axis=2))),
    )


def _embedded_icc(path: Path) -> dict[str, Any] | None:
    try:
        with Image.open(path) as image:
            raw = image.info.get("icc_profile")
    except (OSError, ValueError) as error:
        raise ParityError(f"unable to inspect PNG ICC profile: {path}: {error}") from error
    if not isinstance(raw, bytes) or not raw:
        return None
    try:
        profile = ImageCms.ImageCmsProfile(io.BytesIO(raw))
        name = ImageCms.getProfileName(profile).strip()
    except (OSError, ValueError) as error:
        raise ParityError(f"embedded PNG ICC profile is invalid: {path}: {error}") from error
    if not name:
        raise ParityError(f"embedded PNG ICC profile has no name: {path}")
    return {
        "profileName": name,
        "byteLength": len(raw),
        "sha256": sha256_bytes(raw),
        "source": "embedded-png",
    }


def _approved_icc_profiles(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values = manifest.get("approvedDisplayProfiles")
    if not isinstance(values, list):
        raise ParityError("Gate 0B requires approvedDisplayProfiles")
    result: dict[str, dict[str, Any]] = {}
    required = {
        "profileId",
        "approvalId",
        "approved",
        "profileName",
        "byteLength",
        "sha256",
    }
    for value in values:
        if not isinstance(value, dict) or set(value) != required:
            raise ParityError("approved display profile metadata has invalid fields")
        profile = value.get("profileId")
        if profile not in PROFILES or profile in result:
            raise ParityError("approvedDisplayProfiles must contain each profile exactly once")
        if (
            value.get("approved") is not True
            or not isinstance(value.get("approvalId"), str)
            or not value["approvalId"]
            or not isinstance(value.get("profileName"), str)
            or not value["profileName"]
            or type(value.get("byteLength")) is not int
            or value["byteLength"] <= 0
            or not isinstance(value.get("sha256"), str)
            or len(value["sha256"]) != 64
        ):
            raise ParityError(f"approved display profile metadata is incomplete: {profile}")
        result[profile] = value
    if set(result) != set(PROFILES):
        raise ParityError("approvedDisplayProfiles must cover both frozen profiles")
    return result


def _validate_authenticity_sidecar(
    manifest_path: Path,
    sample: dict[str, Any],
    capture_path: Path,
) -> tuple[dict[str, Any], Path]:
    sidecar_path = _resolve_relative_file(
        manifest_path.parent,
        sample.get("authenticitySidecarPath"),
        label="capture authenticity sidecar",
        suffix=".json",
    )
    expected_sidecar_hash = sample.get("authenticitySidecarSha256")
    if not isinstance(expected_sidecar_hash, str) or len(expected_sidecar_hash) != 64:
        raise ParityError("every Gate 0B sample requires an authenticity sidecar SHA-256")
    if sha256_file(sidecar_path) != expected_sidecar_hash:
        raise ParityError("Gate 0B capture authenticity sidecar hash mismatch")
    sidecar = read_json(sidecar_path)
    required_common = {
        "schemaVersion",
        "renderer",
        "captureMode",
        "captureAPI",
        "result",
        "canonicalEligible",
        "artifactPath",
        "artifactSha256",
        "profileId",
        "scenarioId",
        "pixelSize",
        "window",
        "calibrationRenderer",
    }
    if set(sidecar) != required_common:
        raise ParityError("Gate 0B capture authenticity sidecar has unknown/missing fields")
    if (
        sidecar.get("schemaVersion") != "1.0.0"
        or sidecar.get("captureMode") != "live-window"
        or sidecar.get("captureAPI") != "ScreenCaptureKit"
        or sidecar.get("result") != "captured"
        or sidecar.get("canonicalEligible") is not True
    ):
        raise ParityError("Gate 0B capture authenticity is not canonical ScreenCaptureKit")
    artifact_path = _resolve_relative_file(
        sidecar_path.parent,
        sidecar.get("artifactPath"),
        label="authenticity artifact",
        suffix=".png",
    )
    if artifact_path != capture_path:
        raise ParityError("Gate 0B authenticity artifactPath does not match capture path")
    if (
        sidecar.get("artifactSha256") != sample.get("sha256")
        or sidecar.get("artifactSha256") != sha256_file(capture_path)
        or sidecar.get("profileId") != sample.get("profileId")
        or sidecar.get("scenarioId") != sample.get("scenarioId")
        or sidecar.get("pixelSize") != sample.get("pixelSize")
    ):
        raise ParityError("Gate 0B capture authenticity binding mismatch")
    window = sidecar.get("window")
    calibration = sidecar.get("calibrationRenderer")
    if not isinstance(window, dict) or set(window) != {"ownerBundleId"}:
        raise ParityError("Gate 0B authenticity window identity is invalid")
    if not isinstance(calibration, dict) or set(calibration) != {
        "suiteId",
        "contentRole",
        "sourceRole",
        "mode",
        "profileId",
    }:
        raise ParityError("Gate 0B calibrationRenderer provenance is invalid")
    if (
        calibration.get("suiteId") != SUITE_ID
        or calibration.get("contentRole") != "neutral-calibration"
        or calibration.get("sourceRole") != "neutral-primitives"
        or calibration.get("mode") != "static"
        or calibration.get("profileId") != sample.get("profileId")
    ):
        raise ParityError("Gate 0B calibrationRenderer binding mismatch")
    if sample.get("renderer") == "open-island-app":
        if sidecar.get("renderer") != "native-swiftui-calibration":
            raise ParityError("native Gate 0B sidecar renderer must be native-swiftui-calibration")
    elif (
        sidecar.get("renderer") != "in-app-browser"
        or window.get("ownerBundleId") != "com.openai.codex"
    ):
        raise ParityError("browser Gate 0B sidecar/window identity mismatch")
    return sidecar, sidecar_path


def _validate_strict_manifest(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    manifest = read_json(path)
    if manifest.get("schemaVersion") != "1.0.0":
        raise ParityError("Gate 0B neutral manifest schemaVersion must be 1.0.0")
    if manifest.get("suiteId") != SUITE_ID:
        raise ParityError(f"Gate 0B neutral manifest suiteId must be {SUITE_ID}")
    if manifest.get("contentRole") != "neutral-calibration":
        raise ParityError("Gate 0B input must declare contentRole=neutral-calibration")
    if manifest.get("sourceRole") != "neutral-primitives":
        raise ParityError("Gate 0B sourceRole must be neutral-primitives")
    if manifest.get("haloSourceHashes") != []:
        raise ParityError("Gate 0B input must not bind Halo source hashes")
    if manifest.get("staticRepetitions") != STATIC_REPETITIONS:
        raise ParityError("Gate 0B requires exactly 10 static repetitions")
    approved_icc = _approved_icc_profiles(manifest)
    declared = manifest.get("primitives")
    if (
        not isinstance(declared, list)
        or not all(isinstance(item, str) for item in declared)
        or set(declared) != set(PRIMITIVES)
        or len(declared) != len(PRIMITIVES)
    ):
        raise ParityError("Gate 0B primitive IDs do not match the frozen suite")
    samples = manifest.get("samples")
    if not isinstance(samples, list):
        raise ParityError("Gate 0B neutral manifest samples must be an array")
    expected_cells = {
        (renderer, profile, repetition)
        for renderer in RENDERERS
        for profile in PROFILES
        for repetition in range(STATIC_REPETITIONS)
    }
    observed_cells: set[tuple[str, str, int]] = set()
    capture_ids: set[str] = set()
    resolved: list[dict[str, Any]] = []
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            raise ParityError(f"Gate 0B sample {index} must be an object")
        renderer = sample.get("renderer")
        profile = sample.get("profileId")
        repetition = sample.get("repetitionId")
        if renderer not in RENDERERS:
            raise ParityError(f"Gate 0B sample has unknown renderer: {renderer}")
        if profile not in PROFILES:
            raise ParityError(f"Gate 0B sample has unknown profile: {profile}")
        if type(repetition) is not int or repetition not in range(STATIC_REPETITIONS):
            raise ParityError("Gate 0B repetitionId must be an integer from 0 through 9")
        cell = (renderer, profile, repetition)
        if cell in observed_cells:
            raise ParityError(f"duplicate Gate 0B capture cell: {cell}")
        observed_cells.add(cell)
        capture_id = sample.get("captureId")
        if not isinstance(capture_id, str) or not capture_id:
            raise ParityError("every Gate 0B sample requires a nonempty captureId")
        if capture_id in capture_ids:
            raise ParityError(f"duplicate Gate 0B captureId: {capture_id}")
        capture_ids.add(capture_id)
        if sample.get("mode") != "static":
            raise ParityError("Gate 0B primitive observations must use mode=static")
        if sample.get("scenarioId") != "neutral-calibration-static":
            raise ParityError(
                "Gate 0B primitive observations require scenarioId=neutral-calibration-static"
            )
        if sample.get("contentRole") != "neutral-calibration":
            raise ParityError("every Gate 0B sample must be neutral-calibration")
        if sample.get("sourceRole") != "neutral-primitives":
            raise ParityError("every Gate 0B sample sourceRole must be neutral-primitives")
        if "icc" in sample:
            raise ParityError("Gate 0B ICC metadata must be derived from PNG bytes")
        width, height = PROFILES[profile]
        if sample.get("logicalSize") != {"width": width, "height": height}:
            raise ParityError(f"Gate 0B {profile} logical dimensions are invalid")
        if sample.get("pixelSize") != {"width": width * SCALE, "height": height * SCALE}:
            raise ParityError(f"Gate 0B {profile} pixel dimensions are invalid")
        transform = sample.get("captureTransform", {})
        if transform not in ({}, {"scale": 1, "rotationDegrees": 0}):
            raise ParityError("Gate 0B rejects scale or rotation; registration is translation-only")
        absolute = _resolve_relative_file(
            path.parent,
            sample.get("path"),
            label="Gate 0B capture",
            suffix=".png",
        )
        relative = absolute.relative_to(path.parent.resolve())
        expected_hash = sample.get("sha256")
        if not isinstance(expected_hash, str) or len(expected_hash) != 64:
            raise ParityError("every Gate 0B full-suite PNG requires a SHA-256")
        if sha256_file(absolute) != expected_hash:
            raise ParityError(f"Gate 0B full-suite PNG hash mismatch: {relative}")
        image = _load_rgba(absolute)
        if image.shape != (height * SCALE, width * SCALE, 4):
            raise ParityError(
                f"Gate 0B decoded dimensions mismatch for {relative}: {list(image.shape)}"
            )
        sidecar, sidecar_path = _validate_authenticity_sidecar(path, sample, absolute)
        embedded_icc = _embedded_icc(absolute)
        if embedded_icc is not None:
            approved = approved_icc[profile]
            approved_projection = {
                key: approved[key] for key in ("profileName", "byteLength", "sha256")
            }
            embedded_projection = {
                key: embedded_icc[key] for key in ("profileName", "byteLength", "sha256")
            }
            if embedded_projection != approved_projection:
                raise ParityError(
                    f"embedded PNG ICC does not match approved display profile: {relative}"
                )
        resolved.append(
            {
                **sample,
                "_path": absolute,
                "_image": image,
                "_authenticity": sidecar,
                "_authenticityPath": sidecar_path,
                "_embeddedIcc": embedded_icc,
            }
        )
    missing = expected_cells - observed_cells
    extra = observed_cells - expected_cells
    if missing or extra or len(samples) != len(expected_cells):
        raise ParityError(
            "Gate 0B requires exactly 40 distinct renderer/profile/repetition cells; "
            f"missing={sorted(missing)} extra={sorted(extra)}"
        )
    return manifest, resolved


def _delta_e_2000(first_rgb: np.ndarray, second_rgb: np.ndarray) -> np.ndarray:
    # OpenCV's 8-bit Lab representation is stable here; convert it to conventional
    # L*, a*, b* coordinates before applying the CIEDE2000 equations.
    first = cv2.cvtColor(first_rgb.astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float64)
    second = cv2.cvtColor(second_rgb.astype(np.uint8), cv2.COLOR_RGB2LAB).astype(np.float64)
    l1, a1, b1 = first[..., 0] * 100 / 255, first[..., 1] - 128, first[..., 2] - 128
    l2, a2, b2 = second[..., 0] * 100 / 255, second[..., 1] - 128, second[..., 2] - 128
    c1, c2 = np.hypot(a1, b1), np.hypot(a2, b2)
    cbar = (c1 + c2) / 2
    g = 0.5 * (1 - np.sqrt(cbar**7 / (cbar**7 + 25**7)))
    ap1, ap2 = (1 + g) * a1, (1 + g) * a2
    cp1, cp2 = np.hypot(ap1, b1), np.hypot(ap2, b2)
    hp1 = np.mod(np.degrees(np.arctan2(b1, ap1)), 360)
    hp2 = np.mod(np.degrees(np.arctan2(b2, ap2)), 360)
    dlp, dcp = l2 - l1, cp2 - cp1
    dh = hp2 - hp1
    dh = np.where(dh > 180, dh - 360, np.where(dh < -180, dh + 360, dh))
    dh = np.where((cp1 * cp2) == 0, 0, dh)
    dhp = 2 * np.sqrt(cp1 * cp2) * np.sin(np.radians(dh / 2))
    lp, cp = (l1 + l2) / 2, (cp1 + cp2) / 2
    hp = np.where(
        (cp1 * cp2) == 0,
        hp1 + hp2,
        np.where(
            np.abs(hp1 - hp2) <= 180,
            (hp1 + hp2) / 2,
            np.where(hp1 + hp2 < 360, (hp1 + hp2 + 360) / 2, (hp1 + hp2 - 360) / 2),
        ),
    )
    t = (
        1
        - 0.17 * np.cos(np.radians(hp - 30))
        + 0.24 * np.cos(np.radians(2 * hp))
        + 0.32 * np.cos(np.radians(3 * hp + 6))
        - 0.20 * np.cos(np.radians(4 * hp - 63))
    )
    sl = 1 + 0.015 * (lp - 50) ** 2 / np.sqrt(20 + (lp - 50) ** 2)
    sc, sh = 1 + 0.045 * cp, 1 + 0.015 * cp * t
    rt = -2 * np.sqrt(cp**7 / (cp**7 + 25**7)) * np.sin(
        np.radians(60 * np.exp(-((hp - 275) / 25) ** 2))
    )
    return np.sqrt(
        (dlp / sl) ** 2
        + (dcp / sc) ** 2
        + (dhp / sh) ** 2
        + rt * (dcp / sc) * (dhp / sh)
    )


def _registration(
    browser: np.ndarray, native: np.ndarray
) -> tuple[dict[str, Any], np.ndarray]:
    def fiducials(image: np.ndarray) -> np.ndarray:
        gray = cv2.cvtColor(image[:, :, :3], cv2.COLOR_RGB2GRAY)
        count, _, stats, centroids = cv2.connectedComponentsWithStats(
            (gray >= 240).astype(np.uint8), connectivity=8
        )
        candidates = [
            centroids[index]
            for index in range(1, count)
            if 4 <= stats[index, cv2.CC_STAT_AREA] <= 200
        ]
        if len(candidates) != 4:
            raise ParityError(
                "registration-grid must expose exactly four isolated white fiducials"
            )
        return np.asarray(sorted(candidates, key=lambda point: (point[1], point[0])))

    browser_fiducials = fiducials(browser)
    native_fiducials = fiducials(native)
    browser_horizontal = browser_fiducials[1] - browser_fiducials[0]
    native_horizontal = native_fiducials[1] - native_fiducials[0]
    browser_vertical = browser_fiducials[2] - browser_fiducials[0]
    native_vertical = native_fiducials[2] - native_fiducials[0]
    scale_residual = max(
        abs(np.linalg.norm(browser_horizontal) - np.linalg.norm(native_horizontal)),
        abs(np.linalg.norm(browser_vertical) - np.linalg.norm(native_vertical)),
    )
    rotation_degrees = abs(
        math.degrees(
            math.atan2(native_horizontal[1], native_horizontal[0])
            - math.atan2(browser_horizontal[1], browser_horizontal[0])
        )
    )
    rotation_endpoint_residual = (
        np.linalg.norm(browser_horizontal) * math.sin(math.radians(rotation_degrees))
    )
    scale_rotation_residual = float(max(scale_residual, rotation_endpoint_residual))
    first = cv2.cvtColor(browser[:, :, :3], cv2.COLOR_RGB2GRAY).astype(np.float32)
    second = cv2.cvtColor(native[:, :, :3], cv2.COLOR_RGB2GRAY).astype(np.float32)
    shift, response = cv2.phaseCorrelate(first, second)
    matrix = np.float32([[1, 0, -shift[0]], [0, 1, -shift[1]]])
    aligned = cv2.warpAffine(
        native,
        matrix,
        (native.shape[1], native.shape[0]),
        flags=cv2.INTER_NEAREST,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0, 255),
    )
    residual_shift, residual_response = cv2.phaseCorrelate(
        first,
        cv2.cvtColor(aligned[:, :, :3], cv2.COLOR_RGB2GRAY).astype(np.float32),
    )
    residual = float(math.hypot(*residual_shift))
    return (
        {
            "model": "translation-only",
            "scale": 1,
            "rotationDegrees": 0,
            "scaleRotationDisposition": "explicitly-rejected",
            "fiducialScaleRotationResidualPhysicalPx": scale_rotation_residual,
            "fiducialScaleRotationResidualLimitPhysicalPx": 0.5,
            "translationPhysicalPx": {"x": float(shift[0]), "y": float(shift[1])},
            "phaseCorrelationResponse": float(response),
            "residualPhysicalPx": residual,
            "residualResponse": float(residual_response),
            "residualLimitPhysicalPx": 0.5,
            "passed": bool(
                np.isfinite(residual)
                and residual <= 0.5 + PHYSICAL_PIXEL_EPSILON
                and scale_rotation_residual <= 0.5 + PHYSICAL_PIXEL_EPSILON
            ),
        },
        aligned,
    )


def _text_layout_report(manifest_path: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    proofs = manifest.get("textLayoutProofs")
    if not isinstance(proofs, list):
        return {
            "logicalLayout": {"status": "unavailable-fail-closed", "passed": False},
            "glyphRasterization": {
                "status": "measured-separately",
                "metric": "cross-renderer pixel distributions",
            },
        }
    suite_source_hash = manifest.get("suiteSourceSha256")
    if not isinstance(suite_source_hash, str) or len(suite_source_hash) != 64:
        raise ParityError("text layout provenance requires suiteSourceSha256")
    cells: dict[tuple[str, str], dict[str, Any]] = {}
    for proof in proofs:
        if not isinstance(proof, dict) or set(proof) != {
            "renderer",
            "profileId",
            "sidecarPath",
            "sidecarSha256",
        }:
            raise ParityError("textLayoutProofs entries must be objects")
        key = (proof.get("renderer"), proof.get("profileId"))
        if key[0] not in RENDERERS or key[1] not in PROFILES or key in cells:
            raise ParityError("textLayoutProofs must have one valid renderer/profile cell")
        sidecar_path = _resolve_relative_file(
            manifest_path.parent,
            proof.get("sidecarPath"),
            label="text layout sidecar",
            suffix=".json",
        )
        expected_hash = proof.get("sidecarSha256")
        if not isinstance(expected_hash, str) or len(expected_hash) != 64:
            raise ParityError("text layout proof requires sidecarSha256")
        if sha256_file(sidecar_path) != expected_hash:
            raise ParityError("text layout sidecar hash mismatch")
        sidecar = read_json(sidecar_path)
        if set(sidecar) != {
            "schemaVersion",
            "suiteId",
            "contentRole",
            "sourceRole",
            "renderer",
            "profileId",
            "primitiveId",
            "sourceHashes",
            "boxes",
        }:
            raise ParityError("text layout sidecar has unknown/missing fields")
        if (
            sidecar.get("schemaVersion") != "1.0.0"
            or sidecar.get("suiteId") != SUITE_ID
            or sidecar.get("contentRole") != "neutral-calibration"
            or sidecar.get("sourceRole") != "renderer-layout-sidecar"
            or sidecar.get("renderer") != key[0]
            or sidecar.get("profileId") != key[1]
            or sidecar.get("primitiveId") != "font-raster-boxes"
        ):
            raise ParityError("text layout sidecar provenance mismatch")
        source_hashes = sidecar.get("sourceHashes")
        if (
            not isinstance(source_hashes, dict)
            or set(source_hashes) != {"suiteSourceSha256", "rendererSourceSha256"}
            or source_hashes.get("suiteSourceSha256") != suite_source_hash
            or not isinstance(source_hashes.get("rendererSourceSha256"), str)
            or len(source_hashes["rendererSourceSha256"]) != 64
        ):
            raise ParityError("text layout sidecar source hashes are invalid")
        boxes = sidecar.get("boxes")
        if not isinstance(boxes, list) or not boxes:
            raise ParityError("text layout sidecar requires boxes")
        by_id: dict[str, dict[str, float | str]] = {}
        for box in boxes:
            if not isinstance(box, dict) or set(box) != {
                "id",
                "x",
                "y",
                "width",
                "height",
                "baseline",
            }:
                raise ParityError("text layout box fields are invalid")
            box_id = box.get("id")
            coordinates = [box.get(field) for field in ("x", "y", "width", "height", "baseline")]
            if (
                not isinstance(box_id, str)
                or not box_id
                or box_id in by_id
                or any(type(value) not in (int, float) for value in coordinates)
                or any(not math.isfinite(float(value)) for value in coordinates)
                or float(box["width"]) < 0
                or float(box["height"]) < 0
            ):
                raise ParityError("text layout box ID/coordinates are invalid")
            by_id[box_id] = box
        cells[key] = {
            "boxes": by_id,
            "sidecarPath": str(sidecar_path),
            "sidecarSha256": expected_hash,
            "sourceHashes": source_hashes,
        }
    expected = {(renderer, profile) for renderer in RENDERERS for profile in PROFILES}
    if set(cells) != expected:
        raise ParityError("textLayoutProofs must cover all four renderer/profile cells")
    comparisons = []
    for profile in PROFILES:
        browser = cells[("in-app-browser", profile)]["boxes"]
        native = cells[("open-island-app", profile)]["boxes"]
        if set(browser) != set(native):
            raise ParityError("browser/native text layout box IDs do not match")
        deltas: defaultdict[str, list[float]] = defaultdict(list)
        records = []
        for box_id in sorted(browser):
            fields = {}
            for field in ("x", "y", "width", "height", "baseline"):
                delta = abs(float(browser[box_id][field]) - float(native[box_id][field]))
                deltas[field].append(delta)
                fields[field] = delta
            records.append({"id": box_id, "absoluteLogicalDeltas": fields})
        comparisons.append(
            {
                "profileId": profile,
                "boxCount": len(records),
                "boxDeltas": records,
                "deltaDistributionsLogicalUnits": {
                    field: _distribution(values) for field, values in sorted(deltas.items())
                },
            }
        )
    return {
        "logicalLayout": {
            "status": "provenance-verified-and-measured",
            "passed": True,
            "comparisons": comparisons,
            "sidecars": [
                {
                    "renderer": renderer,
                    "profileId": profile,
                    "path": cells[(renderer, profile)]["sidecarPath"],
                    "sha256": cells[(renderer, profile)]["sidecarSha256"],
                    "sourceHashes": cells[(renderer, profile)]["sourceHashes"],
                }
                for renderer in sorted(RENDERERS)
                for profile in PROFILES
            ],
        },
        "glyphRasterization": {
            "status": "measured-separately",
            "metric": "cross-renderer pixel distributions",
        },
    }


def analyze_gate_0b_manifest(path: Path) -> dict[str, Any]:
    manifest, samples = _validate_strict_manifest(path)
    observations: list[dict[str, Any]] = []
    crops: dict[tuple[str, str, str, int], np.ndarray] = {}
    for sample in samples:
        profile = sample["profileId"]
        for primitive in PRIMITIVES:
            x, y, width, height = DEVICE_ROIS[profile][primitive]
            crop = sample["_image"][y : y + height, x : x + width].copy()
            key = (sample["renderer"], profile, primitive, sample["repetitionId"])
            crops[key] = crop
            observations.append(
                {
                    "captureId": sample["captureId"],
                    "renderer": sample["renderer"],
                    "profileId": profile,
                    "primitiveId": primitive,
                    "repetitionId": sample["repetitionId"],
                    "logicalRoi": list(LOGICAL_ROIS[profile][primitive]),
                    "deviceRoi": {"x": x, "y": y, "width": width, "height": height},
                    "derivedEncoding": "png",
                    "derivedCropSha256": _crop_png_hash(crop),
                }
            )
    repeatability = []
    for renderer in sorted(RENDERERS):
        for profile in PROFILES:
            for primitive in PRIMITIVES:
                metrics = []
                for first in range(STATIC_REPETITIONS):
                    for second in range(first + 1, STATIC_REPETITIONS):
                        metrics.append(
                            _pair_metrics(
                                crops[(renderer, profile, primitive, first)],
                                crops[(renderer, profile, primitive, second)],
                            )
                        )
                repeatability.append(
                    {
                        "renderer": renderer,
                        "profileId": profile,
                        "primitiveId": primitive,
                        "pairCount": 45,
                        "meanAbsoluteChannelDelta": _distribution(item[0] for item in metrics),
                        "p95AbsoluteChannelDelta": _distribution(item[1] for item in metrics),
                        "changedPixelFraction": _distribution(item[2] for item in metrics),
                    }
                )
    stroke_centerlines = []
    for renderer in sorted(RENDERERS):
        for profile in PROFILES:
            for repetition in range(STATIC_REPETITIONS):
                crop = crops[(renderer, profile, "neutral-width-lines", repetition)]
                luminance = cv2.cvtColor(crop[:, :, :3], cv2.COLOR_RGB2GRAY)
                interior = luminance[16:-16, 24:-24]
                active_rows = np.flatnonzero(np.mean(interior, axis=1) >= 24)
                bands = []
                for row in active_rows:
                    if not bands or row > bands[-1][-1] + 1:
                        bands.append([int(row)])
                    else:
                        bands[-1].append(int(row))
                if len(bands) != 3:
                    raise ParityError(
                        "neutral-width-lines must expose exactly three isolated stroke bands"
                    )
                observations_for_capture = []
                for nominal, band in zip((1, 1.5, 2), bands):
                    weights = np.mean(interior[band], axis=1) / 255
                    centerline = float(np.average(np.asarray(band), weights=weights) + 16)
                    effective_width = float(np.sum(weights))
                    observations_for_capture.append(
                        {
                            "nominalMappedUnits": nominal,
                            "nominalPhysicalPixels": nominal * SCALE,
                            "observedCenterlinePhysicalPx": centerline,
                            "observedEffectiveWidthPhysicalPx": effective_width,
                        }
                    )
                stroke_centerlines.append(
                    {
                        "renderer": renderer,
                        "profileId": profile,
                        "repetitionId": repetition,
                        "strokes": observations_for_capture,
                    }
                )
    registrations = []
    cross_metrics: defaultdict[
        tuple[str, str], list[tuple[float, float, float]]
    ] = defaultdict(list)
    delta_e_values: defaultdict[str, list[float]] = defaultdict(list)
    icc_states = [sample["_embeddedIcc"] is not None for sample in samples]
    icc_available = all(icc_states)
    for profile in PROFILES:
        for repetition in range(STATIC_REPETITIONS):
            browser_registration = crops[
                ("in-app-browser", profile, "registration-grid", repetition)
            ]
            native_registration = crops[
                ("open-island-app", profile, "registration-grid", repetition)
            ]
            registration, _ = _registration(browser_registration, native_registration)
            registration.update({"profileId": profile, "repetitionId": repetition})
            registrations.append(registration)
            dx = registration["translationPhysicalPx"]["x"]
            dy = registration["translationPhysicalPx"]["y"]
            matrix = np.float32([[1, 0, -dx], [0, 1, -dy]])
            for primitive in PRIMITIVES:
                browser = crops[("in-app-browser", profile, primitive, repetition)]
                native = crops[("open-island-app", profile, primitive, repetition)]
                aligned = cv2.warpAffine(
                    native,
                    matrix,
                    (native.shape[1], native.shape[0]),
                    flags=cv2.INTER_NEAREST,
                    borderMode=cv2.BORDER_CONSTANT,
                    borderValue=(0, 0, 0, 255),
                )
                cross_metrics[(profile, primitive)].append(_pair_metrics(browser, aligned))
                if primitive == "solid-srgb-patches" and icc_available:
                    patch_width = browser.shape[1] / 4
                    for patch in range(4):
                        left = int(round(patch * patch_width)) + 8
                        right = int(round((patch + 1) * patch_width)) - 8
                        browser_rgb = browser[8:-20, left:right, :3]
                        native_rgb = aligned[8:-20, left:right, :3]
                        delta_e_values[profile].extend(
                            _delta_e_2000(browser_rgb, native_rgb).ravel().tolist()
                        )
    cross_renderer = []
    for (profile, primitive), metrics in sorted(cross_metrics.items()):
        cross_renderer.append(
            {
                "profileId": profile,
                "primitiveId": primitive,
                "comparisonCount": STATIC_REPETITIONS,
                "meanAbsoluteChannelDelta": _distribution(item[0] for item in metrics),
                "p95AbsoluteChannelDelta": _distribution(item[1] for item in metrics),
                "changedPixelFraction": _distribution(item[2] for item in metrics),
            }
        )
    color = {
        "iccMetadataFields": ["profileName", "byteLength", "sha256", "source"],
        "status": "measured" if icc_available else "unavailable-fail-closed",
        "passed": icc_available,
        "profiles": (
            [
                {
                    "profileId": profile,
                    "deltaE2000": _distribution(delta_e_values[profile]),
                }
                for profile in PROFILES
            ]
            if icc_available
            else []
        ),
    }
    text = _text_layout_report(path, manifest)
    registration_passed = all(item["passed"] for item in registrations)
    stroke_lookup = {
        (item["renderer"], item["profileId"], item["repetitionId"]): item["strokes"]
        for item in stroke_centerlines
    }
    registration_lookup = {
        (item["profileId"], item["repetitionId"]): item for item in registrations
    }
    stroke_comparisons = []
    for profile in PROFILES:
        for stroke_index, nominal in enumerate((1, 1.5, 2)):
            centerline_deltas = []
            effective_width_deltas = []
            for repetition in range(STATIC_REPETITIONS):
                browser_stroke = stroke_lookup[
                    ("in-app-browser", profile, repetition)
                ][stroke_index]
                native_stroke = stroke_lookup[
                    ("open-island-app", profile, repetition)
                ][stroke_index]
                registration_dy = registration_lookup[
                    (profile, repetition)
                ]["translationPhysicalPx"]["y"]
                centerline_deltas.append(
                    abs(
                        browser_stroke["observedCenterlinePhysicalPx"]
                        - (
                            native_stroke["observedCenterlinePhysicalPx"]
                            - registration_dy
                        )
                    )
                )
                effective_width_deltas.append(
                    abs(
                        browser_stroke["observedEffectiveWidthPhysicalPx"]
                        - native_stroke["observedEffectiveWidthPhysicalPx"]
                    )
                )
            stroke_comparisons.append(
                {
                    "profileId": profile,
                    "nominalMappedUnits": nominal,
                    "nominalPhysicalPixels": nominal * SCALE,
                    "centerlineDeltaPhysicalPx": _distribution(centerline_deltas),
                    "effectiveRasterWidthDeltaPhysicalPx": _distribution(
                        effective_width_deltas
                    ),
                    "centerlinePassed": (
                        max(centerline_deltas) <= 0.5 + PHYSICAL_PIXEL_EPSILON
                    ),
                }
            )
    stroke_centerline_passed = all(
        item["centerlinePassed"] for item in stroke_comparisons
    )
    report = {
        "schemaVersion": "2.0.0",
        "reportType": "gate-0b-neutral-static-analysis",
        "suiteId": SUITE_ID,
        "contentRole": "neutral-calibration",
        "sourceManifest": str(path),
        "sourceManifestSha256": sha256_file(path),
        "captureCount": len(samples),
        "captureAuthenticity": [
            {
                "captureId": sample["captureId"],
                "sidecarPath": str(sample["_authenticityPath"]),
                "sidecarSha256": sample["authenticitySidecarSha256"],
                "renderer": sample["_authenticity"]["renderer"],
                "canonicalEligible": True,
            }
            for sample in samples
        ],
        "embeddedIccEvidence": [
            {
                "captureId": sample["captureId"],
                "profileId": sample["profileId"],
                "icc": sample["_embeddedIcc"],
            }
            for sample in samples
        ],
        "primitiveObservationCount": len(observations),
        "expectedPrimitiveObservationCount": 320,
        "frozenRoiVersion": "halo-neutral-roi-v1",
        "frozenLogicalRois": {
            profile: {primitive: list(roi) for primitive, roi in values.items()}
            for profile, values in LOGICAL_ROIS.items()
        },
        "frozenDeviceRois": {
            profile: {primitive: list(roi) for primitive, roi in values.items()}
            for profile, values in DEVICE_ROIS.items()
        },
        "observations": observations,
        "sameRendererAllPairs": repeatability,
        "groups": [
            {
                "renderer": item["renderer"],
                "profileId": item["profileId"],
                "primitiveId": item["primitiveId"],
                "sampleCount": STATIC_REPETITIONS,
                "p95AbsoluteChannelDeltaMax": item["p95AbsoluteChannelDelta"]["maximum"],
                "changedPixelFractionMax": item["changedPixelFraction"]["maximum"],
            }
            for item in repeatability
        ],
        "translationRegistration": registrations,
        "crossRendererProfileMatched": cross_renderer,
        "unitTransformProof": {
            "cssPxToSwiftUiPoint": 1,
            "mappedUnitToPhysicalPixel": SCALE,
            "nominalStrokeMappedUnits": [1, 1.5, 2],
            "nominalStrokePhysicalPixels": [2, 3, 4],
            "strokeProofMethod": "declared vector centerlines plus isolated ROI raster profiles",
            "rasterWidthAloneIsProof": False,
            "profileDimensionsProven": True,
            "strokeCenterlineObservations": stroke_centerlines,
            "crossRendererStrokeComparisons": stroke_comparisons,
            "strokeCenterlineResidualLimitPhysicalPx": 0.5,
            "passed": stroke_centerline_passed,
        },
        "colorPatchAnalysis": color,
        "textAnalysis": text,
        "gate0BPass": bool(
            len(observations) == 320
            and registration_passed
            and stroke_centerline_passed
            and color["status"] == "measured"
            and text["logicalLayout"]["passed"]
        ),
        "failureReasons": [
            reason
            for condition, reason in (
                (registration_passed, "translation registration residual exceeded 0.5 physical px"),
                (stroke_centerline_passed, "stroke centerline residual exceeded 0.5 physical px"),
                (color["status"] == "measured", "ICC-backed DeltaE2000 unavailable"),
                (text["logicalLayout"]["passed"], "text logical layout proof unavailable or mismatched"),
            )
            if not condition
        ],
        "forbiddenInputsObserved": [],
    }
    report["evidenceBindings"] = {
        field: sha256_bytes(canonical_json_bytes(report[field]))
        for field in (
            "captureAuthenticity",
            "observations",
            "sameRendererAllPairs",
            "translationRegistration",
            "crossRendererProfileMatched",
            "unitTransformProof",
            "colorPatchAnalysis",
            "textAnalysis",
        )
    }
    report["reportSha256"] = sha256_bytes(canonical_json_bytes(report))
    return report
