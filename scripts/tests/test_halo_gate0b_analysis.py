from __future__ import annotations

import hashlib
import io
import json
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageCms


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

from halo_parity.core import ParityError
from halo_parity.calibration import threshold_proposal
from halo_parity.neutral_analysis import (
    DEVICE_ROIS,
    PRIMITIVES,
    PROFILES,
    RENDERERS,
    analyze_gate_0b_manifest,
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Gate0BNeutralAnalysisTests(unittest.TestCase):
    def _write_fixture(self, root: Path) -> tuple[Path, dict[str, object]]:
        samples = []
        icc_bytes = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
        icc_name = ImageCms.getProfileName(
            ImageCms.ImageCmsProfile(io.BytesIO(icc_bytes))
        ).strip()
        for renderer in sorted(RENDERERS):
            for profile, (logical_width, logical_height) in PROFILES.items():
                pixel_width, pixel_height = logical_width * 2, logical_height * 2
                for repetition in range(10):
                    image = np.zeros((pixel_height, pixel_width, 4), dtype=np.uint8)
                    image[:, :, 3] = 255
                    for primitive_index, primitive in enumerate(PRIMITIVES):
                        x, y, width, height = DEVICE_ROIS[profile][primitive]
                        crop = image[y : y + height, x : x + width]
                        crop[:, :, :3] = 0
                        cv2.rectangle(
                            crop,
                            (1, 1),
                            (width - 2, height - 2),
                            (64, 64, 64, 255),
                            2,
                        )
                        if primitive == "registration-grid":
                            for anchor_x, anchor_y in (
                                (18, 18),
                                (width - 19, 18),
                                (18, height - 19),
                                (width - 19, height - 19),
                            ):
                                cv2.rectangle(
                                    crop,
                                    (anchor_x - 4, anchor_y - 4),
                                    (anchor_x + 4, anchor_y + 4),
                                    (255, 255, 255, 255),
                                    2,
                                )
                        elif primitive == "neutral-width-lines":
                            for line_y, thickness in ((42, 2), (67, 3), (94, 4)):
                                cv2.line(
                                    crop,
                                    (24, line_y),
                                    (width - 25, line_y),
                                    (255, 255, 255, 255),
                                    thickness,
                                )
                        elif primitive == "solid-srgb-patches":
                            for patch, value in enumerate((0, 32, 128, 255)):
                                left = round(patch * width / 4)
                                right = round((patch + 1) * width / 4)
                                crop[:, left:right, :3] = value
                    filename = f"{renderer}-{profile}-{repetition}.png"
                    path = root / filename
                    Image.fromarray(image, "RGBA").save(path, icc_profile=icc_bytes)
                    sample = {
                            "captureId": f"{renderer}:{profile}:{repetition}",
                            "renderer": renderer,
                            "profileId": profile,
                            "repetitionId": repetition,
                            "mode": "static",
                            "scenarioId": "neutral-calibration-static",
                            "contentRole": "neutral-calibration",
                            "sourceRole": "neutral-primitives",
                            "logicalSize": {
                                "width": logical_width,
                                "height": logical_height,
                            },
                            "pixelSize": {
                                "width": pixel_width,
                                "height": pixel_height,
                            },
                            "captureTransform": {"scale": 1, "rotationDegrees": 0},
                            "path": filename,
                            "sha256": sha256(path),
                    }
                    sidecar_name = f"{renderer}-{profile}-{repetition}.authenticity.json"
                    sidecar_path = root / sidecar_name
                    sidecar = {
                        "schemaVersion": "1.0.0",
                        "renderer": (
                            "native-swiftui-calibration"
                            if renderer == "open-island-app"
                            else "in-app-browser"
                        ),
                        "captureMode": "live-window",
                        "captureAPI": "ScreenCaptureKit",
                        "result": "captured",
                        "canonicalEligible": True,
                        "artifactPath": filename,
                        "artifactSha256": sample["sha256"],
                        "profileId": profile,
                        "scenarioId": "neutral-calibration-static",
                        "pixelSize": sample["pixelSize"],
                        "window": {
                            "ownerBundleId": (
                                "com.example.NeutralCalibration"
                                if renderer == "open-island-app"
                                else "com.openai.codex"
                            )
                        },
                        "calibrationRenderer": {
                            "suiteId": "halo-neutral-calibration-v1",
                            "contentRole": "neutral-calibration",
                            "sourceRole": "neutral-primitives",
                            "mode": "static",
                            "profileId": profile,
                        },
                    }
                    sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
                    sample["authenticitySidecarPath"] = sidecar_name
                    sample["authenticitySidecarSha256"] = sha256(sidecar_path)
                    samples.append(sample)
        suite_source_hash = "b" * 64
        text_proofs = []
        for renderer in sorted(RENDERERS):
            for profile in PROFILES:
                sidecar_name = f"text-{renderer}-{profile}.json"
                sidecar_path = root / sidecar_name
                boxes = [
                    {
                        "id": "sans-10-left",
                        "x": 9 if renderer == "in-app-browser" else 8,
                        "y": 8,
                        "width": 48,
                        "height": 10,
                        "baseline": 16,
                    },
                    {
                        "id": "mono-10-right",
                        "x": 130.5,
                        "y": 8,
                        "width": 52,
                        "height": 10,
                        "baseline": 16,
                    },
                ]
                sidecar = {
                    "schemaVersion": "1.0.0",
                    "suiteId": "halo-neutral-calibration-v1",
                    "contentRole": "neutral-calibration",
                    "sourceRole": "renderer-layout-sidecar",
                    "renderer": renderer,
                    "profileId": profile,
                    "primitiveId": "font-raster-boxes",
                    "sourceHashes": {
                        "suiteSourceSha256": suite_source_hash,
                        "rendererSourceSha256": (
                            "c" * 64 if renderer == "in-app-browser" else "d" * 64
                        ),
                    },
                    "boxes": boxes,
                }
                sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
                text_proofs.append(
                    {
                        "renderer": renderer,
                        "profileId": profile,
                        "sidecarPath": sidecar_name,
                        "sidecarSha256": sha256(sidecar_path),
                    }
                )
        manifest: dict[str, object] = {
            "schemaVersion": "1.0.0",
            "suiteId": "halo-neutral-calibration-v1",
            "contentRole": "neutral-calibration",
            "sourceRole": "neutral-primitives",
            "haloSourceHashes": [],
            "staticRepetitions": 10,
            "suiteSourceSha256": suite_source_hash,
            "approvedDisplayProfiles": [
                {
                    "profileId": profile,
                    "approvalId": f"test-approval-{profile}",
                    "approved": True,
                    "profileName": icc_name,
                    "byteLength": len(icc_bytes),
                    "sha256": hashlib.sha256(icc_bytes).hexdigest(),
                }
                for profile in PROFILES
            ],
            "primitives": list(PRIMITIVES),
            "samples": samples,
            "textLayoutProofs": text_proofs,
        }
        path = root / "manifest.json"
        path.write_text(json.dumps(manifest), encoding="utf-8")
        return path, manifest

    def _write_manifest(self, path: Path, manifest: dict[str, object]) -> None:
        path.write_text(json.dumps(manifest), encoding="utf-8")

    def test_exact_matrix_produces_hashed_roi_observations_and_proofs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self._write_fixture(Path(directory))
            report = analyze_gate_0b_manifest(path)
            self.assertEqual(report["captureCount"], 40)
            self.assertEqual(report["primitiveObservationCount"], 320)
            self.assertEqual(len(report["observations"]), 320)
            self.assertEqual(len(report["sameRendererAllPairs"]), 32)
            self.assertTrue(
                all(item["pairCount"] == 45 for item in report["sameRendererAllPairs"])
            )
            self.assertEqual(len(report["crossRendererProfileMatched"]), 16)
            self.assertEqual(len(report["translationRegistration"]), 20)
            self.assertTrue(
                all(item["passed"] for item in report["translationRegistration"])
            )
            self.assertTrue(
                all(
                    len(item["derivedCropSha256"]) == 64
                    for item in report["observations"]
                )
            )
            self.assertEqual(
                report["unitTransformProof"]["nominalStrokePhysicalPixels"],
                [2, 3, 4],
            )
            self.assertEqual(report["colorPatchAnalysis"]["status"], "measured")
            self.assertTrue(report["textAnalysis"]["logicalLayout"]["passed"])
            self.assertEqual(
                report["textAnalysis"]["logicalLayout"]["comparisons"][0][
                    "deltaDistributionsLogicalUnits"
                ]["x"]["maximum"],
                1,
            )
            self.assertTrue(report["gate0BPass"], report["failureReasons"])

    def test_strict_threshold_derivation_is_complete_and_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path, _ = self._write_fixture(Path(directory))
            report = analyze_gate_0b_manifest(path)
            first = threshold_proposal(report, version="v-test")
            second = threshold_proposal(deepcopy(report), version="v-test")
            self.assertEqual(first, second)
            self.assertEqual(first["status"], "proposed-unapproved")
            self.assertEqual(first["derivationRule"]["id"], "neutral-tail-span-v1")
            self.assertFalse(
                first["derivationRule"]["candidateOrHaloDivergenceUsed"]
            )
            self.assertEqual(len(first["staticPrimitiveThresholds"]), 16)
            self.assertEqual(len(first["textLogicalLayoutThresholds"]), 2)
            self.assertEqual(len(first["colorPatchThresholds"]), 2)
            self.assertNotIn("hardCaps", first)
            metric = first["staticPrimitiveThresholds"][0]["metrics"][
                "changedPixelFraction"
            ]
            self.assertEqual(
                metric["proposedTolerance"],
                metric["repeatabilityNoiseFloor"]
                + metric["stableNeutralRendererVariance"]
                + metric["statisticalSafetyMargin"],
            )
            tampered = deepcopy(report)
            tampered["crossRendererProfileMatched"][0][
                "changedPixelFraction"
            ]["maximum"] = 1
            with self.assertRaisesRegex(ParityError, "report hash is invalid"):
                threshold_proposal(tampered, version="v-test")

    def test_missing_and_duplicate_matrix_cells_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path, manifest = self._write_fixture(Path(directory))
            missing = deepcopy(manifest)
            missing["samples"].pop()  # type: ignore[union-attr]
            self._write_manifest(path, missing)
            with self.assertRaisesRegex(ParityError, "exactly 40"):
                analyze_gate_0b_manifest(path)

            duplicate = deepcopy(manifest)
            duplicate["samples"][-1] = deepcopy(duplicate["samples"][0])  # type: ignore[index]
            self._write_manifest(path, duplicate)
            with self.assertRaisesRegex(ParityError, "duplicate Gate 0B capture cell"):
                analyze_gate_0b_manifest(path)

    def test_wrong_counts_ids_dimensions_and_hashes_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path, manifest = self._write_fixture(Path(directory))
            mutations = (
                (
                    "count",
                    lambda value: value.__setitem__("staticRepetitions", 9),
                    "exactly 10",
                ),
                (
                    "renderer",
                    lambda value: value["samples"][0].__setitem__("renderer", "webkit"),
                    "unknown renderer",
                ),
                (
                    "profile",
                    lambda value: value["samples"][0].__setitem__("profileId", "other"),
                    "unknown profile",
                ),
                (
                    "primitive ids",
                    lambda value: value["primitives"].__setitem__(0, "other"),
                    "primitive IDs",
                ),
                (
                    "declared dimensions",
                    lambda value: value["samples"][0]["pixelSize"].__setitem__(
                        "width", 1
                    ),
                    "pixel dimensions",
                ),
                (
                    "hash",
                    lambda value: value["samples"][0].__setitem__("sha256", "0" * 64),
                    "hash mismatch",
                ),
                (
                    "rotation",
                    lambda value: value["samples"][0].__setitem__(
                        "captureTransform", {"scale": 1, "rotationDegrees": 0.1}
                    ),
                    "translation-only",
                ),
            )
            for label, mutate, message in mutations:
                with self.subTest(label=label):
                    candidate = deepcopy(manifest)
                    mutate(candidate)
                    self._write_manifest(path, candidate)
                    with self.assertRaisesRegex(ParityError, message):
                        analyze_gate_0b_manifest(path)

    def test_decoded_dimension_tampering_and_missing_icc_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self._write_fixture(root)
            first = manifest["samples"][0]  # type: ignore[index]
            image_path = root / first["path"]
            bad = np.zeros((10, 10, 4), dtype=np.uint8)
            self.assertTrue(cv2.imwrite(str(image_path), bad))
            first["sha256"] = sha256(image_path)
            self._write_manifest(path, manifest)
            with self.assertRaisesRegex(ParityError, "decoded dimensions mismatch"):
                analyze_gate_0b_manifest(path)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self._write_fixture(root)
            sample = manifest["samples"][0]  # type: ignore[index]
            image_path = root / sample["path"]
            with Image.open(image_path) as source:
                pixels = np.asarray(source.convert("RGBA")).copy()
            Image.fromarray(pixels, "RGBA").save(image_path)
            sample["sha256"] = sha256(image_path)
            sidecar_path = root / sample["authenticitySidecarPath"]
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            sidecar["artifactSha256"] = sample["sha256"]
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            sample["authenticitySidecarSha256"] = sha256(sidecar_path)
            self._write_manifest(path, manifest)
            report = analyze_gate_0b_manifest(path)
            self.assertEqual(
                report["colorPatchAnalysis"]["status"], "unavailable-fail-closed"
            )
            self.assertFalse(report["gate0BPass"])
            self.assertIn("ICC-backed DeltaE2000 unavailable", report["failureReasons"])

    def test_capture_sidecar_hash_content_and_path_tampering_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self._write_fixture(root)
            sample = manifest["samples"][0]  # type: ignore[index]
            sample["authenticitySidecarSha256"] = "0" * 64
            self._write_manifest(path, manifest)
            with self.assertRaisesRegex(ParityError, "sidecar hash mismatch"):
                analyze_gate_0b_manifest(path)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self._write_fixture(root)
            sample = manifest["samples"][0]  # type: ignore[index]
            sidecar_path = root / sample["authenticitySidecarPath"]
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            sidecar["canonicalEligible"] = False
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            sample["authenticitySidecarSha256"] = sha256(sidecar_path)
            self._write_manifest(path, manifest)
            with self.assertRaisesRegex(ParityError, "not canonical ScreenCaptureKit"):
                analyze_gate_0b_manifest(path)

        with tempfile.TemporaryDirectory() as directory:
            path, manifest = self._write_fixture(Path(directory))
            manifest["samples"][0]["authenticitySidecarPath"] = "../escape.json"  # type: ignore[index]
            self._write_manifest(path, manifest)
            with self.assertRaisesRegex(ParityError, "relative .json path"):
                analyze_gate_0b_manifest(path)

    def test_embedded_icc_and_text_sidecar_tampering_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path, manifest = self._write_fixture(Path(directory))
            manifest["approvedDisplayProfiles"][0]["sha256"] = "0" * 64  # type: ignore[index]
            self._write_manifest(path, manifest)
            with self.assertRaisesRegex(ParityError, "does not match approved"):
                analyze_gate_0b_manifest(path)

        with tempfile.TemporaryDirectory() as directory:
            path, manifest = self._write_fixture(Path(directory))
            manifest["textLayoutProofs"][0]["sidecarSha256"] = "0" * 64  # type: ignore[index]
            self._write_manifest(path, manifest)
            with self.assertRaisesRegex(ParityError, "text layout sidecar hash mismatch"):
                analyze_gate_0b_manifest(path)

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path, manifest = self._write_fixture(root)
            proof = manifest["textLayoutProofs"][0]  # type: ignore[index]
            sidecar_path = root / proof["sidecarPath"]
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            sidecar["boxes"][0]["x"] = "fabricated"
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            proof["sidecarSha256"] = sha256(sidecar_path)
            self._write_manifest(path, manifest)
            with self.assertRaisesRegex(ParityError, "box ID/coordinates"):
                analyze_gate_0b_manifest(path)

    def test_text_layout_is_not_inferred_from_glyph_pixels(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path, manifest = self._write_fixture(Path(directory))
            manifest.pop("textLayoutProofs")
            self._write_manifest(path, manifest)
            report = analyze_gate_0b_manifest(path)
            self.assertEqual(
                report["textAnalysis"]["logicalLayout"]["status"],
                "unavailable-fail-closed",
            )
            self.assertEqual(
                report["textAnalysis"]["glyphRasterization"]["status"],
                "measured-separately",
            )
            self.assertFalse(report["gate0BPass"])


if __name__ == "__main__":
    unittest.main()
