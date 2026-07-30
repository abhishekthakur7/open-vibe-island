from __future__ import annotations

import json
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

import jsonschema
from PIL import Image


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

from halo_parity.core import ParityError, canonical_json_bytes, sha256_bytes, sha256_file
from halo_parity.cli import main, verify_gate_0b_masks
from halo_parity.masks import generate_masks, verify_mask_manifest


def annotations() -> dict[str, object]:
    return {
        "schemaVersion": "1.0.0",
        "coordinateSpace": "reference-logical-points",
        "authority": {
            "sourceRole": "authoritative-reference",
            "sourcePath": "Validation/HaloParity/reference/generated/fixture.html",
            "sha256": "a" * 64,
        },
        "families": {
            "silhouette-body": {
                "selectors": ["#surface"],
                "geometry": [
                    {
                        "type": "rounded-rect",
                        "x": 20,
                        "y": 20,
                        "width": 200,
                        "height": 100,
                        "radius": 18,
                    }
                ],
            },
            "edge-core": {
                "selectors": ["#surface .edge"],
                "geometry": [
                    {
                        "type": "stroke-rounded-rect",
                        "x": 20,
                        "y": 20,
                        "width": 200,
                        "height": 100,
                        "radius": 18,
                        "strokeWidth": 1.5,
                    }
                ],
            },
            "emissive-bloom": {
                "selectors": ["#surface .bloom"],
                "geometry": [
                    {
                        "type": "rounded-rect",
                        "x": 18,
                        "y": 18,
                        "width": 204,
                        "height": 104,
                        "radius": 20,
                    }
                ],
            },
            "non-text-content": {
                "selectors": ["#surface .icon"],
                "geometry": [
                    {"type": "ellipse", "x": 40, "y": 40, "width": 8, "height": 8}
                ],
            },
            "text-layout-boxes": {
                "selectors": ["#surface .title"],
                "geometry": [
                    {"type": "rect", "x": 70, "y": 40, "width": 80, "height": 20}
                ],
            },
            "os-external": {
                "selectors": ["#capture-fiducial"],
                "geometry": [
                    {"type": "rect", "x": 500, "y": 0, "width": 4, "height": 4}
                ],
            },
        },
    }


def profile() -> dict[str, object]:
    return {
        "id": "notch-v1",
        "logicalSize": {"width": 540, "height": 320},
        "backingScale": 2,
    }


def transform() -> dict[str, object]:
    return {
        "schemaVersion": "1.0.0",
        "transformId": "neutral-unit-transform-v1",
        "status": "frozen",
        "scale": {"numerator": 2, "denominator": 1},
        "translationDevicePixels": {"x": 0, "y": 0},
        "provenance": {
            "sourceRole": "neutral-calibration",
            "sourcePath": "Validation/HaloParity/calibration/v1/unit-transform.json",
            "sha256": "b" * 64,
        },
    }


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def write_mask_aggregate(root: Path) -> tuple[Path, Path, Path]:
    scenario_path = root / "scenarios.json"
    write_json(
        scenario_path,
        {
            "schemaVersion": "1.0.0",
            "manifestDefaults": {
                "capture": {"stableCheckpoints": [], "timedCheckpoints": []}
            },
            "scenarios": [
                {
                    "id": "SYNTHETIC",
                    "capture": {
                        "stableCheckpoints": ["settled"],
                        "timedCheckpoints": [],
                    },
                }
            ],
        },
    )
    policy_path = root / "mask-policy-v1.json"
    policy_path.write_bytes(
        (
            REPOSITORY_ROOT
            / "Validation/HaloParity/calibration/v1/mask-policy-v1.json"
        ).read_bytes()
    )
    matrix = []
    for profile_id, width in (("notch-v1", 540), ("top-bar-v1", 520)):
        manifest_path = generate_masks(
            annotations=annotations(),
            profile={
                "id": profile_id,
                "logicalSize": {"width": width, "height": 320},
                "backingScale": 2,
            },
            neutral_transform=transform(),
            output_dir=root / "sets" / profile_id,
        )
        matrix.append(
            {
                "scenarioId": "SYNTHETIC",
                "checkpointKind": "stable",
                "checkpointId": "settled",
                "profileId": profile_id,
                "manifestPath": str(manifest_path.relative_to(root)),
                "manifestSha256": sha256_file(manifest_path),
            }
        )
    aggregate = {
        "schemaVersion": "1.0.0",
        "aggregateId": "halo-mask-matrix-v1",
        "status": "frozen",
        "maskSetVersion": "halo-reference-masks-v1",
        "policy": {
            "policyId": "halo-mask-policy-v1",
            "path": policy_path.name,
            "sha256": sha256_file(policy_path),
        },
        "scenarioManifest": {
            "path": scenario_path.name,
            "sha256": sha256_file(scenario_path),
        },
        "matrix": matrix,
        "matrixSha256": sha256_bytes(canonical_json_bytes(matrix)),
    }
    aggregate["aggregateSha256"] = sha256_bytes(canonical_json_bytes(aggregate))
    aggregate_path = root / "masks-v1.json"
    write_json(aggregate_path, aggregate)
    return aggregate_path, scenario_path, policy_path


def rehash_aggregate(path: Path, value: dict[str, object]) -> None:
    value["matrixSha256"] = sha256_bytes(canonical_json_bytes(value["matrix"]))
    value.pop("aggregateSha256", None)
    value["aggregateSha256"] = sha256_bytes(canonical_json_bytes(value))
    write_json(path, value)


class HaloMaskTests(unittest.TestCase):
    def test_generation_is_byte_deterministic_and_verifies(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_manifest = generate_masks(
                annotations=annotations(),
                profile=profile(),
                neutral_transform=transform(),
                output_dir=Path(first),
            )
            second_manifest = generate_masks(
                annotations=annotations(),
                profile=profile(),
                neutral_transform=transform(),
                output_dir=Path(second),
            )
            self.assertEqual(first_manifest.read_bytes(), second_manifest.read_bytes())
            for path in sorted(Path(first).glob("*.png")):
                self.assertEqual(
                    path.read_bytes(), (Path(second) / path.name).read_bytes()
                )
            result = verify_mask_manifest(first_manifest)
            self.assertTrue(result["valid"])
            self.assertEqual(result["dimensions"], {"width": 1080, "height": 640})
            self.assertEqual(result["familyCount"], 6)

            manifest = json.loads(first_manifest.read_text(encoding="utf-8"))
            text = Image.open(first_manifest.parent / manifest["families"][4]["path"])
            body = Image.open(first_manifest.parent / manifest["families"][0]["path"])
            self.assertEqual(text.getpixel((160, 90)), 255)
            self.assertEqual(body.getpixel((160, 90)), 0)
            edge = Image.open(first_manifest.parent / manifest["families"][1]["path"])
            self.assertEqual(edge.getpixel((200, 100)), 0)

    def test_top_bar_profile_has_exact_canonical_device_dimensions(self) -> None:
        top_bar = {
            "id": "top-bar-v1",
            "logicalSize": {"width": 520, "height": 320},
            "backingScale": 2,
        }
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = generate_masks(
                annotations=annotations(),
                profile=top_bar,
                neutral_transform=transform(),
                output_dir=Path(directory),
            )
            self.assertEqual(
                verify_mask_manifest(manifest_path)["dimensions"],
                {"width": 1040, "height": 640},
            )

    def test_manifest_matches_closed_mask_set_schema(self) -> None:
        schema = json.loads(
            (
                REPOSITORY_ROOT
                / "Validation/HaloParity/schemas/mask-set.schema.json"
            ).read_text(encoding="utf-8")
        )
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = generate_masks(
                annotations=annotations(),
                profile=profile(),
                neutral_transform=transform(),
                output_dir=Path(directory),
            )
            jsonschema.Draft202012Validator(schema).validate(
                json.loads(manifest_path.read_text(encoding="utf-8"))
            )

    def test_calibrate_masks_cli_generates_and_prints_verification(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            annotations_path = root / "annotations.json"
            transform_path = root / "transform.json"
            output = root / "output"
            write_json(annotations_path, annotations())
            write_json(transform_path, transform())
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                result = main(
                    [
                        "calibrate",
                        "masks",
                        "--annotations",
                        str(annotations_path),
                        "--profile",
                        "notch-v1",
                        "--neutral-transform",
                        str(transform_path),
                        "--output-dir",
                        str(output),
                    ]
                )
            self.assertEqual(result, 0)
            printed = json.loads(stdout.getvalue())
            self.assertTrue(printed["verification"]["valid"])
            self.assertEqual(printed["verification"]["profileId"], "notch-v1")
            self.assertTrue((output / "manifest.json").is_file())

    def test_gate_0b_mask_matrix_accepts_closed_declared_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            aggregate, scenarios, policy = write_mask_aggregate(root)
            result = verify_gate_0b_masks(
                aggregate,
                scenario_manifest_path=scenarios,
                policy_path=policy,
            )
            self.assertTrue(result["valid"])
            self.assertEqual(result["matrixCellCount"], 2)
            self.assertEqual(result["verifiedManifestCount"], 2)

    def test_gate_0b_mask_matrix_rejects_missing_profile_and_tamper(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            aggregate_path, scenarios, policy = write_mask_aggregate(root)
            aggregate = json.loads(aggregate_path.read_text(encoding="utf-8"))
            aggregate["matrix"].pop()
            rehash_aggregate(aggregate_path, aggregate)
            with self.assertRaisesRegex(ParityError, "does not exactly match"):
                verify_gate_0b_masks(
                    aggregate_path,
                    scenario_manifest_path=scenarios,
                    policy_path=policy,
                )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            aggregate_path, scenarios, policy = write_mask_aggregate(root)
            aggregate = json.loads(aggregate_path.read_text(encoding="utf-8"))
            aggregate["matrix"][0]["manifestSha256"] = "0" * 64
            rehash_aggregate(aggregate_path, aggregate)
            with self.assertRaisesRegex(ParityError, "manifest hash mismatch"):
                verify_gate_0b_masks(
                    aggregate_path,
                    scenario_manifest_path=scenarios,
                    policy_path=policy,
                )

    def test_rejects_candidate_paths_unknown_or_missing_families_and_bounds(self) -> None:
        bad_path = annotations()
        bad_path["authority"]["sourcePath"] = "artifacts/candidate/frame.json"
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ParityError, "candidate/native"):
                generate_masks(
                    annotations=bad_path,
                    profile=profile(),
                    neutral_transform=transform(),
                    output_dir=Path(directory),
                )

        bad_families = annotations()
        bad_families["families"]["unknown"] = bad_families["families"].pop(
            "os-external"
        )
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ParityError, "missing=.*os-external.*unknown"):
                generate_masks(
                    annotations=bad_families,
                    profile=profile(),
                    neutral_transform=transform(),
                    output_dir=Path(directory),
                )

        missing = annotations()
        missing["families"]["edge-core"]["geometry"] = []
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ParityError, "requires authoritative geometry"):
                generate_masks(
                    annotations=missing,
                    profile=profile(),
                    neutral_transform=transform(),
                    output_dir=Path(directory),
                )

        outside = annotations()
        outside["families"]["os-external"]["geometry"][0]["x"] = 539
        outside["families"]["os-external"]["geometry"][0]["width"] = 2
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ParityError, "outside reference bounds"):
                generate_masks(
                    annotations=outside,
                    profile=profile(),
                    neutral_transform=transform(),
                    output_dir=Path(directory),
                )

    def test_rejects_os_external_overlap(self) -> None:
        value = annotations()
        value["families"]["os-external"]["geometry"] = [
            {"type": "rect", "x": 30, "y": 30, "width": 2, "height": 2}
        ]
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ParityError, "os-external overlaps Halo-owned"):
                generate_masks(
                    annotations=value,
                    profile=profile(),
                    neutral_transform=transform(),
                    output_dir=Path(directory),
                )

    def test_verifier_rejects_manifest_dimension_and_hash_tampering(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = generate_masks(
                annotations=annotations(),
                profile=profile(),
                neutral_transform=transform(),
                output_dir=Path(directory),
            )
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["dimensions"]["width"] = 1
            unhashed = dict(manifest)
            del unhashed["manifestSha256"]
            manifest["manifestSha256"] = sha256_bytes(canonical_json_bytes(unhashed))
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ParityError, "dimensions"):
                verify_mask_manifest(manifest_path)

        with tempfile.TemporaryDirectory() as directory:
            manifest_path = generate_masks(
                annotations=annotations(),
                profile=profile(),
                neutral_transform=transform(),
                output_dir=Path(directory),
            )
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            png = manifest_path.parent / manifest["families"][0]["path"]
            image = Image.open(png)
            image.putpixel((0, 0), 255)
            image.save(png)
            with self.assertRaisesRegex(ParityError, "PNG hash mismatch"):
                verify_mask_manifest(manifest_path)

    def test_verifier_rejects_non_binary_pixels_even_with_rehashed_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = generate_masks(
                annotations=annotations(),
                profile=profile(),
                neutral_transform=transform(),
                output_dir=Path(directory),
            )
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            entry = manifest["families"][0]
            png = manifest_path.parent / entry["path"]
            image = Image.open(png)
            image.putpixel((0, 0), 127)
            image.save(png)
            entry["sha256"] = sha256_file(png)
            unhashed = dict(manifest)
            del unhashed["manifestSha256"]
            manifest["manifestSha256"] = sha256_bytes(canonical_json_bytes(unhashed))
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ParityError, "non-binary"):
                verify_mask_manifest(manifest_path)

    def test_verifier_rejects_binary_png_not_derived_from_geometry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = generate_masks(
                annotations=annotations(),
                profile=profile(),
                neutral_transform=transform(),
                output_dir=Path(directory),
            )
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            entry = manifest["families"][0]
            png = manifest_path.parent / entry["path"]
            image = Image.open(png)
            image.putpixel((0, 0), 255)
            image.save(png)
            entry["sha256"] = sha256_file(png)
            unhashed = dict(manifest)
            del unhashed["manifestSha256"]
            manifest["manifestSha256"] = sha256_bytes(canonical_json_bytes(unhashed))
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(
                ParityError, "does not match frozen source geometry"
            ):
                verify_mask_manifest(manifest_path)


if __name__ == "__main__":
    unittest.main()
