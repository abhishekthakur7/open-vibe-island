from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest import mock

from PIL import Image


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tools"))

from halo_parity.authenticity import verify_authenticity_file
from halo_parity.cli import _check_gate_0a
from halo_parity.cli import command_test
from halo_parity.cli import command_gate_0a_approval_prepare
from halo_parity.cli import verify_gate_0a_approval
from halo_parity.cli import verify_recorded_gate_0a_user_approval
from halo_parity.calibration import analyze_neutral_manifest
from halo_parity.core import (
    DISPLAY_PROFILES,
    MEASUREMENT_SPEC,
    REFERENCE_AUTHORITY,
    SCENARIO_MANIFEST,
    ParityError,
    canonical_json_bytes,
    make_gate_0a_authority_projection,
    read_json,
    read_strict_json,
    sha256_bytes,
    strict_json_loads,
    validate_measurement_spec,
    validate_profiles,
    validate_reference_authority,
    validate_scenario_manifest,
)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fully_resolved_profiles() -> dict[str, object]:
    value = deepcopy(read_json(DISPLAY_PROFILES))
    top_bar = next(
        profile for profile in value["profiles"] if profile["id"] == "top-bar-v1"
    )
    top_bar["captureDisplayIdentity"] = {
        "status": "resolved",
        "displayID": 2,
        "localizedName": "External Retina Display",
        "connectionType": "external",
        "framePoints": {"width": 2560, "height": 1440},
        "nativePixels": {"width": 5120, "height": 2880},
        "backingScale": 2,
        "maximumFramesPerSecond": 60,
        "iccBytes": 4096,
        "iccSha256": "e" * 64,
        "productID": "1234",
        "vendorID": "5678",
        "serialNumber": "abcdef",
    }
    return value


def write_resolved_profiles(root: Path) -> Path:
    path = root / "display-profiles-resolved.json"
    path.write_text(json.dumps(fully_resolved_profiles()), encoding="utf-8")
    return path


def native_manifest(
    executable: Path,
    *,
    pid: int = 123,
    bundle_id: str = "com.example.OpenIsland",
    scenario: str = "A3",
    profile: str = "notch-v1",
) -> dict[str, object]:
    return {
        "schemaVersion": "halo-native-capture-sidecar-v1",
        "scenario": scenario,
        "manifestDisposition": "exact",
        "lockedNativeFixtureIdentifier": "IslandDebugScenario.closedAttention",
        "profile": profile,
        "motion": "normal",
        "accessibility": "standard",
        "event": None,
        "seed": 0,
        "fixtureSchemaVersion": "halo-native-fixture-v1",
        "fixtureHash": "d" * 64,
        "fixtureVariant": "closed-attention",
        "resolvedThemeID": "halo",
        "clock": {"mode": "production-monotonic"},
        "executable": {
            "path": str(executable.resolve()),
            "sha256": sha256(executable),
            "buildId": "12345678-1234-1234-1234-123456789ABC",
            "configuration": "debug",
            "gitRevision": "c" * 40,
            "sourceTreeDirty": False,
        },
        "process": {
            "pid": pid,
            "startTime": "2026-01-01T00:00:00Z",
            "bundleId": bundle_id,
            "executablePath": str(executable.resolve()),
            "executableSha256": sha256(executable),
        },
        "fixture": {
            "id": "IslandDebugScenario.closedAttention",
            "payloadSha256": "d" * 64,
            "liveDataAbsent": True,
        },
        "placement": {
            "requestedProfileId": profile,
            "resolvedMode": "notch" if profile == "notch-v1" else "topBar",
            "targetScreenId": "screen-1",
            "targetScreenName": "Test Display",
            "selectionSummary": "explicit test display",
            "screenFrame": {"x": 0, "y": 0, "width": 1728, "height": 1117},
            "visibleFrame": {"x": 0, "y": 25, "width": 1728, "height": 1092},
            "safeAreaInsets": {"top": 0, "left": 0, "bottom": 0, "right": 0},
            "cgWindowId": 42,
            "windowLayer": 0,
            "actualWindowGeometry": {
                "x": 0,
                "y": 0,
                "width": 540,
                "height": 360,
            },
        },
        "generatedAt": "2026-01-01T00:00:01Z",
        "isolation": {
            "runtimeStateLoadingDisabled": True,
            "bridgeStartupDisabled": True,
            "allSessionsAreDemoOrigin": True,
            "fixtureSessionIDs": ["session-1"],
        },
    }


def native_authenticity_record(
    root: Path,
    native: dict[str, object],
    *,
    canonical: bool = False,
) -> dict[str, object]:
    artifact = root / "capture.png"
    Image.new("RGBA", (1080, 720), (0, 0, 0, 255)).save(artifact)
    return {
        "schemaVersion": "1.0.0",
        "renderer": "open-island-app",
        "captureMode": "live-window",
        "captureAPI": "ScreenCaptureKit",
        "result": "captured",
        "canonicalEligible": canonical,
        "canonicalIneligibilityReasons": (
            [] if canonical else ["profile crop provenance was not explicitly proven"]
        ),
        "artifactPath": artifact.name,
        "artifactSha256": sha256(artifact),
        "profileId": "notch-v1",
        "scenarioId": "A3",
        "onScreen": True,
        "window": {
            "cgWindowId": 42,
            "ownerPid": 123,
            "ownerBundleId": "com.example.OpenIsland",
            "bounds": {"x": 0, "y": 0, "width": 540, "height": 360},
            "layer": 0,
            "isOnScreen": True,
        },
        "pixelSize": {"width": 1080, "height": 720},
        "captureHelper": {"sha256": "a" * 64},
        "profileValidation": {
            "expectedPointWidth": 540,
            "expectedPixelWidth": 1080,
            "cropProven": canonical,
            "captureRectSource": "full-live-window",
            "sourceRectPoints": {"x": 0, "y": 0, "width": 540, "height": 360},
            "windowBoundsPoints": {"x": 0, "y": 0, "width": 540, "height": 360},
        },
        "nativeSidecar": native,
        "nativeExpectations": {
            "scenarioId": "A3",
            "profileId": "notch-v1",
            "resolvedThemeID": "halo",
            "motion": "normal",
            "accessibility": "standard",
            "event": None,
        },
    }


class HaloParityToolingTests(unittest.TestCase):
    def test_cli_help_lists_validation_commands(self) -> None:
        completed = subprocess.run(
            [str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"), "--help"],
            cwd=REPOSITORY_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout)
        for command in (
            "doctor",
            "freeze-spec",
            "queue-reference",
            "verify-authenticity",
            "calibrate",
            "baseline",
            "gate0a-approval",
            "signoff",
            "record-goldens",
        ):
            self.assertIn(command, completed.stdout)

    @unittest.skipUnless(shutil.which("ssh-keygen"), "ssh-keygen is required")
    def test_gate_0a_external_approval_is_canonical_signed_and_limited(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resolved_profiles = write_resolved_profiles(root)
            key = root / "reviewer-key"
            generated = subprocess.run(
                ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(generated.returncode, 0, generated.stdout)
            allowed = root / "allowed-signers"
            allowed.write_text(
                f'reviewer namespaces="halo-parity" '
                f'{key.with_suffix(".pub").read_text(encoding="utf-8").strip()}\n',
                encoding="utf-8",
            )
            approval = root / "gate-0a-approval.json"
            args = type(
                "Args",
                (),
                {"principal": "reviewer", "output": str(approval)},
            )()
            with mock.patch(
                "halo_parity.cli.DISPLAY_PROFILES",
                resolved_profiles,
            ):
                self.assertEqual(command_gate_0a_approval_prepare(args), 0)
                value = json.loads(approval.read_bytes())
                self.assertEqual(
                    approval.read_bytes(),
                    canonical_json_bytes(value),
                )
                bindings = value["bindings"]
                self.assertEqual(
                    {
                        "canonicalization",
                        "digestAlgorithm",
                        "authorityProjection",
                        "authorityProjectionSha256",
                    },
                    set(bindings),
                )
                projection = bindings["authorityProjection"]
                self.assertEqual(
                    [profile["id"] for profile in projection["displayProfiles"]],
                    ["notch-v1", "top-bar-v1"],
                )
                self.assertEqual(
                    sha256_bytes(canonical_json_bytes(projection)),
                    bindings["authorityProjectionSha256"],
                )
                signed = subprocess.run(
                    [
                        "ssh-keygen",
                        "-Y",
                        "sign",
                        "-f",
                        str(key),
                        "-n",
                        "halo-parity",
                        str(approval),
                    ],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=False,
                )
                self.assertEqual(signed.returncode, 0, signed.stdout)
                signature = Path(f"{approval}.sig")
                result = verify_gate_0a_approval(
                    approval,
                    signature,
                    allowed,
                    "reviewer",
                )
                self.assertTrue(result["valid"])
                self.assertFalse(result["scenarioPassGranted"])
                self.assertFalse(result["gate7ApprovalGranted"])
                self.assertFalse(result["goldensAuthorized"])

                checks = _check_gate_0a((approval, signature, allowed, "reviewer"))
                authority = next(
                    check
                    for check in checks
                    if check.name == "authenticated Gate 0A authoring/profile authority"
                )
                profiles = next(
                    check
                    for check in checks
                    if check.name == "authorized display profiles"
                )
                coverage = next(
                    check
                    for check in checks
                    if check.name == "57 exact scenario rows"
                )
                self.assertTrue(authority.passed)
                self.assertTrue(profiles.passed)
                self.assertTrue(coverage.passed)

    @unittest.skipUnless(shutil.which("ssh-keygen"), "ssh-keygen is required")
    def test_gate_0a_approval_rejects_wrong_principal_scope_and_hash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            resolved_profiles = write_resolved_profiles(root)
            key = root / "reviewer-key"
            subprocess.run(
                ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            allowed = root / "allowed-signers"
            allowed.write_text(
                f'reviewer namespaces="halo-parity" '
                f'{key.with_suffix(".pub").read_text(encoding="utf-8").strip()}\n',
                encoding="utf-8",
            )
            approval = root / "gate-0a-approval.json"
            args = type(
                "Args",
                (),
                {"principal": "reviewer", "output": str(approval)},
            )()
            with mock.patch(
                "halo_parity.cli.DISPLAY_PROFILES",
                resolved_profiles,
            ):
                command_gate_0a_approval_prepare(args)
                subprocess.run(
                    [
                        "ssh-keygen",
                        "-Y",
                        "sign",
                        "-f",
                        str(key),
                        "-n",
                        "halo-parity",
                        str(approval),
                    ],
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                )
                signature = Path(f"{approval}.sig")
                original_approval = approval.read_bytes()
                with self.assertRaisesRegex(ParityError, "principal does not match"):
                    verify_gate_0a_approval(
                        approval,
                        signature,
                        allowed,
                        "somebody-else",
                    )

                value = json.loads(approval.read_bytes())
                value["noWaivers"] = False
                approval.write_bytes(canonical_json_bytes(value))
                with self.assertRaisesRegex(ParityError, "noWaivers must be True"):
                    verify_gate_0a_approval(
                        approval,
                        signature,
                        allowed,
                        "reviewer",
                    )

                value["noWaivers"] = True
                value["scope"] = "gate-7-final-approval"
                approval.write_bytes(canonical_json_bytes(value))
                with self.assertRaisesRegex(ParityError, "scope must be"):
                    verify_gate_0a_approval(
                        approval,
                        signature,
                        allowed,
                        "reviewer",
                    )

                value["scope"] = "reference-authoring-and-display-profile-authority"
                value["bindings"]["authorityProjectionSha256"] = "0" * 64
                approval.write_bytes(canonical_json_bytes(value))
                with self.assertRaisesRegex(
                    ParityError,
                    "embedded authority projection digest is invalid",
                ):
                    verify_gate_0a_approval(
                        approval,
                        signature,
                        allowed,
                        "reviewer",
                    )

                approval.write_bytes(original_approval)
                bad_signature = root / "bad.sig"
                signature_bytes = bytearray(signature.read_bytes())
                signature_bytes[len(signature_bytes) // 2] ^= 1
                bad_signature.write_bytes(signature_bytes)
                with self.assertRaisesRegex(
                    ParityError,
                    "signature verification failed",
                ):
                    verify_gate_0a_approval(
                        approval,
                        bad_signature,
                        allowed,
                        "reviewer",
                    )

    def test_manifest_has_exactly_57_exact_reproducible_rows(self) -> None:
        manifest = read_json(SCENARIO_MANIFEST)
        summary = validate_scenario_manifest(manifest, require_exact=False)
        self.assertEqual(summary["scenarioCount"], 57)
        self.assertEqual(summary["dispositions"], {"exact": 57})
        strict_summary = validate_scenario_manifest(manifest, require_exact=True)
        self.assertEqual(strict_summary["scenarioCount"], 57)

    def test_measurement_contract_is_frozen_before_calibration(self) -> None:
        value = read_json(MEASUREMENT_SPEC)
        summary = validate_measurement_spec(value)
        self.assertEqual(summary["measurementSpecId"], "halo-measurement-v1")
        self.assertFalse(value["authority"]["haloCandidatePixelsUsed"])
        self.assertIn("halo-reference-divergence", value["forbiddenInputs"])

    def test_display_profiles_are_resolved_and_user_approved(self) -> None:
        value = read_json(DISPLAY_PROFILES)
        summary = validate_profiles(value, require_approval=False)
        self.assertEqual(summary["profileCount"], 2)
        approved = validate_profiles(
            value,
            require_approval=True,
            require_resolved_identity=True,
        )
        self.assertEqual(approved["profileCount"], 2)
        authority = verify_recorded_gate_0a_user_approval()
        self.assertTrue(authority["valid"])
        self.assertEqual(authority["method"], "codex-user-message")
        self.assertFalse(authority["scenarioPassGranted"])

    def test_gate_0a_prepare_succeeds_for_resolved_production_profiles(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "approval.json"
            args = type(
                "Args",
                (),
                {"principal": "reviewer", "output": str(output)},
            )()
            self.assertEqual(command_gate_0a_approval_prepare(args), 0)
            self.assertTrue(output.is_file())
            approval = read_strict_json(output)
            self.assertEqual(approval["principal"], "reviewer")
            self.assertEqual(approval["decision"], "approve")
            self.assertTrue(approval["noWaivers"])
            self.assertEqual(
                len(approval["bindings"]["authorityProjection"]["displayProfiles"]),
                2,
            )

    def test_gate_0a_projection_excludes_workflow_and_native_coverage_state(self) -> None:
        authority = read_strict_json(REFERENCE_AUTHORITY)
        profiles = fully_resolved_profiles()
        baseline = make_gate_0a_authority_projection(authority, profiles)

        workflow_mutation = deepcopy(profiles)
        workflow_mutation["status"] = "mutated-workflow-status"
        workflow_mutation["approval"] = {"reviewer": "mutated"}
        workflow_mutation["sourceAnchors"] = ["mutated"]
        for profile in workflow_mutation["profiles"]:
            profile["provenance"] = "mutated workflow narrative"
            profile["approvalStatus"] = "approved"
        self.assertEqual(
            baseline,
            make_gate_0a_authority_projection(authority, workflow_mutation),
        )

        manifest = read_json(SCENARIO_MANIFEST)
        for index, row in enumerate(manifest["scenarios"]):
            row["fixtureData"] = {"nativeMutation": index}
            row["native"] = {"triggerSequence": ["mutated"]}
            row["disposition"] = "exact"
            row["reproductionEvidence"] = {"mutated": True}
            row["rationale"] = "mutated coverage rationale"
            row["result"] = "passed"
            row["approver"] = "mutated"
        with tempfile.TemporaryDirectory() as directory:
            manifest_path = Path(directory) / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with mock.patch(
                "halo_parity.core.SCENARIO_MANIFEST",
                manifest_path,
            ):
                self.assertEqual(
                    baseline,
                    make_gate_0a_authority_projection(authority, profiles),
                )

    def test_gate_0a_projection_rejects_duplicate_identity_and_unknown_fields(self) -> None:
        authority = read_strict_json(REFERENCE_AUTHORITY)
        profiles = fully_resolved_profiles()
        duplicate = deepcopy(profiles)
        notch = next(
            item for item in duplicate["profiles"] if item["id"] == "notch-v1"
        )
        top_bar = next(
            item for item in duplicate["profiles"] if item["id"] == "top-bar-v1"
        )
        for field in ("productID", "vendorID", "serialNumber", "iccSha256"):
            top_bar["captureDisplayIdentity"][field] = notch[
                "captureDisplayIdentity"
            ][field]
        with self.assertRaisesRegex(ParityError, "distinct physical displays"):
            make_gate_0a_authority_projection(authority, duplicate)

        unknown = fully_resolved_profiles()
        unknown["profiles"][0]["captureDisplayIdentity"]["workflowNote"] = "forbidden"
        with self.assertRaisesRegex(ParityError, "identity fields are invalid"):
            make_gate_0a_authority_projection(authority, unknown)

    def test_authority_json_and_canonicalization_subset_fail_closed(self) -> None:
        with self.assertRaisesRegex(ParityError, "duplicate JSON key"):
            strict_json_loads('{"a":1,"a":2}', source="duplicate-test")
        for token in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(token=token):
                with self.assertRaisesRegex(ParityError, "non-finite JSON number"):
                    strict_json_loads(f'{{"value":{token}}}', source="number-test")

        authority = read_strict_json(REFERENCE_AUTHORITY)
        unsafe = fully_resolved_profiles()
        unsafe["profiles"][0]["captureDisplayIdentity"]["displayID"] = 2**53
        with self.assertRaisesRegex(ParityError, "safe range"):
            make_gate_0a_authority_projection(authority, unsafe)

        surrogate = fully_resolved_profiles()
        surrogate["profiles"][0]["captureDisplayIdentity"][
            "localizedName"
        ] = "\ud800"
        with self.assertRaisesRegex(ParityError, "surrogate"):
            make_gate_0a_authority_projection(authority, surrogate)

    def test_gate_0a_schemas_validate_current_authority_and_v2_envelope(self) -> None:
        from jsonschema import Draft202012Validator
        from referencing import Registry, Resource

        schema_root = REPOSITORY_ROOT / "Validation/HaloParity/schemas"
        names = (
            "reference-authority.schema.json",
            "gate-0a-authority-projection.schema.json",
            "gate-0a-approval.schema.json",
        )
        schemas = {
            name: json.loads((schema_root / name).read_text(encoding="utf-8"))
            for name in names
        }
        registry = Registry()
        for schema in schemas.values():
            Draft202012Validator.check_schema(schema)
            registry = registry.with_resource(
                schema["$id"],
                Resource.from_contents(schema),
            )

        authority = read_strict_json(REFERENCE_AUTHORITY)
        projection = make_gate_0a_authority_projection(
            authority,
            fully_resolved_profiles(),
        )
        envelope = {
            "schemaVersion": "2.0.0",
            "namespace": "halo-parity",
            "gate": "0A",
            "scope": "reference-authoring-and-display-profile-authority",
            "principal": "reviewer",
            "decision": "approve",
            "createdAt": "2026-07-30T00:00:00Z",
            "bindings": {
                "canonicalization": "RFC8785-integer-BMP-subset",
                "digestAlgorithm": "sha256",
                "authorityProjection": projection,
                "authorityProjectionSha256": sha256_bytes(
                    canonical_json_bytes(projection)
                ),
            },
            "noWaivers": True,
            "statements": {
                "authoringProfileAuthorityOnly": True,
                "noScenarioPass": True,
                "notGate7Approval": True,
                "noGoldens": True,
            },
        }
        Draft202012Validator(
            schemas["reference-authority.schema.json"],
            registry=registry,
        ).validate(authority)
        Draft202012Validator(
            schemas["gate-0a-approval.schema.json"],
            registry=registry,
        ).validate(envelope)

    def test_reference_queue_uses_versioned_harness_contract(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "queue.json"
            completed = subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                    "queue-reference",
                    "--output",
                    str(output),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)
            queue = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(len(queue["records"]), 114)
            for record in queue["records"]:
                self.assertIn("/generated/halo-reference-v1.html?", record["url"])
                self.assertIn("a11y=default", record["url"])
                self.assertNotIn("accessibility=", record["url"])
                self.assertIn(record["profileId"], {"notch-v1", "top-bar-v1"})

    def test_capture_plan_rejects_duplicate_queue_and_strict_never_claims_capture(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            queue_path = root / "queue.json"
            subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                    "queue-reference",
                    "--output",
                    str(queue_path),
                ],
                cwd=REPOSITORY_ROOT,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            queue = json.loads(queue_path.read_text(encoding="utf-8"))
            queue["records"][-1] = dict(queue["records"][0])
            queue_path.write_text(json.dumps(queue), encoding="utf-8")
            completed = subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                    "capture-reference",
                    "--queue",
                    str(queue_path),
                    "--output",
                    str(root / "plan.json"),
                    "--strict",
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("exactly once", completed.stdout)
            self.assertFalse((root / "plan.json").exists())

    def test_neutral_repeatability_analysis_and_halo_input_guard(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first = root / "neutral-1.png"
            second = root / "neutral-2.png"
            Image.new("RGBA", (8, 8), (32, 32, 32, 255)).save(first)
            Image.new("RGBA", (8, 8), (32, 32, 32, 255)).save(second)
            manifest = {
                "schemaVersion": "1.0.0",
                "contentRole": "neutral-calibration",
                "sourceRole": "neutral-primitives",
                "haloSourceHashes": [],
                "samples": [
                    {
                        "renderer": "in-app-browser",
                        "profileId": "notch-v1",
                        "primitiveId": "solid-gray",
                        "contentRole": "neutral-calibration",
                        "sourceRole": "neutral-primitives",
                        "path": first.name,
                        "sha256": sha256(first),
                    },
                    {
                        "renderer": "in-app-browser",
                        "profileId": "notch-v1",
                        "primitiveId": "solid-gray",
                        "contentRole": "neutral-calibration",
                        "sourceRole": "neutral-primitives",
                        "path": second.name,
                        "sha256": sha256(second),
                    },
                ],
            }
            manifest_path = root / "samples.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            report = analyze_neutral_manifest(manifest_path)
            self.assertEqual(report["groups"][0]["sampleCount"], 2)
            self.assertEqual(report["groups"][0]["p95AbsoluteChannelDeltaMax"], 0)
            manifest["sourceRole"] = "halo-reference"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ParityError, "forbidden"):
                analyze_neutral_manifest(manifest_path)

    def test_authenticity_accepts_consistent_live_native_and_rejects_proxy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "OpenIslandApp"
            executable.write_bytes(b"temporary native executable")
            sidecar = native_authenticity_record(root, native_manifest(executable))
            sidecar_path = root / "authenticity.json"
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            result = verify_authenticity_file(
                sidecar_path,
                expected_renderer="open-island-app",
            )
            self.assertTrue(result["valid"])
            canonical = native_authenticity_record(
                root,
                native_manifest(executable),
                canonical=True,
            )
            sidecar_path.write_text(json.dumps(canonical), encoding="utf-8")
            self.assertTrue(
                verify_authenticity_file(
                    sidecar_path,
                    expected_renderer="open-island-app",
                    require_canonical=True,
                )["canonicalEligible"]
            )
            sidecar = canonical
            sidecar["proxyRenderer"] = True
            sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")
            with self.assertRaisesRegex(ParityError, "proxy"):
                verify_authenticity_file(sidecar_path)

    def test_native_authenticity_rejects_hash_identity_and_request_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "OpenIslandApp"
            executable.write_bytes(b"temporary native executable")
            base = native_authenticity_record(root, native_manifest(executable))
            sidecar_path = root / "authenticity.json"
            mutations = (
                (
                    "fake executable sha",
                    lambda value: value["nativeSidecar"]["executable"].__setitem__(
                        "sha256", "0" * 64
                    ),
                    "does not match file bytes",
                ),
                (
                    "pid mismatch",
                    lambda value: value["nativeSidecar"]["process"].__setitem__("pid", 999),
                    "PID does not own",
                ),
                (
                    "bundle mismatch",
                    lambda value: value["nativeSidecar"]["process"].__setitem__(
                        "bundleId", "com.example.Other"
                    ),
                    "bundle ID does not own",
                ),
                (
                    "profile mismatch",
                    lambda value: value["nativeSidecar"].__setitem__(
                        "profile", "top-bar-v1"
                    ),
                    "native profile mismatch",
                ),
                (
                    "scenario mismatch",
                    lambda value: value["nativeSidecar"].__setitem__("scenario", "E1"),
                    "native scenario mismatch",
                ),
            )
            for label, mutate, message in mutations:
                with self.subTest(label=label):
                    value = deepcopy(base)
                    mutate(value)
                    sidecar_path.write_text(json.dumps(value), encoding="utf-8")
                    with self.assertRaisesRegex(ParityError, message):
                        verify_authenticity_file(sidecar_path)

    def test_native_authenticity_rejects_flat_legacy_and_manual_sidecars(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "OpenIslandApp"
            executable.write_bytes(b"temporary native executable")
            sidecar = native_authenticity_record(root, native_manifest(executable))
            sidecar_path = root / "authenticity.json"
            flat = deepcopy(sidecar)
            flat["nativeSidecar"] = {
                "schemaVersion": "halo-native-capture-sidecar-v1",
                "executablePath": str(executable),
                "processPid": 123,
                "bundleId": "com.example.OpenIsland",
            }
            sidecar_path.write_text(json.dumps(flat), encoding="utf-8")
            with self.assertRaisesRegex(ParityError, "flat legacy"):
                verify_authenticity_file(sidecar_path)

            manual = deepcopy(sidecar)
            manual["nativeSidecar"]["motion"] = "manual"
            sidecar_path.write_text(json.dumps(manual), encoding="utf-8")
            with self.assertRaisesRegex(ParityError, "manual native determinism"):
                verify_authenticity_file(sidecar_path)

    def test_canonical_verification_rejects_explicitly_noncanonical_capture(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "capture.png"
            Image.new("RGBA", (4, 4), (0, 0, 0, 255)).save(artifact)
            sidecar_path = root / "capture.authenticity.json"
            sidecar_path.write_text(
                json.dumps(
                    {
                        "schemaVersion": "1.0.0",
                        "renderer": "in-app-browser",
                        "captureMode": "live-window",
                        "captureAPI": "ScreenCaptureKit",
                        "result": "captured",
                        "canonicalEligible": False,
                        "canonicalIneligibilityReasons": ["crop provenance unproven"],
                        "artifactPath": artifact.name,
                        "artifactSha256": sha256(artifact),
                        "profileId": "notch-v1",
                        "scenarioId": "A1",
                        "onScreen": True,
                        "window": {
                            "cgWindowId": 42,
                            "ownerPid": 123,
                            "ownerBundleId": "com.openai.codex",
                            "bounds": {"x": 0, "y": 0, "width": 540, "height": 360},
                            "layer": 0,
                            "isOnScreen": True,
                        },
                        "captureHelper": {"sha256": "a" * 64},
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ParityError, "canonicalEligible=true"):
                verify_authenticity_file(sidecar_path, require_canonical=True)

    def test_capture_window_integrates_helper_and_marks_unproven_crop_noncanonical(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "fake-capture"
            helper.write_text(
                """#!/usr/bin/env python3
import json
import sys
from PIL import Image
args = sys.argv[1:]
output = args[args.index("--output") + 1]
Image.new("RGBA", (1080, 720), (0, 0, 0, 255)).save(output)
print(json.dumps({
  "captureAPI": "ScreenCaptureKit",
  "captureMode": "live-window",
  "pixelWidth": 1080,
  "pixelHeight": 720,
  "sourceRect": {"x": 0, "y": 0, "width": 540, "height": 360},
  "window": {
    "cgWindowId": 42,
    "ownerPid": 123,
    "ownerBundleId": "com.openai.codex",
    "ownerName": "Codex",
    "title": "Reference",
    "bounds": {"x": 0, "y": 0, "width": 540, "height": 360},
    "layer": 0,
    "isOnScreen": True
  }
}))
""",
                encoding="utf-8",
            )
            helper.chmod(0o755)
            output = root / "capture.png"
            completed = subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                    "capture-window",
                    "--window-id",
                    "42",
                    "--output",
                    str(output),
                    "--renderer",
                    "in-app-browser",
                    "--scenario",
                    "A1",
                    "--profile",
                    "notch-v1",
                    "--expected-pid",
                    "123",
                    "--expected-bundle-id",
                    "com.openai.codex",
                    "--helper",
                    str(helper),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)
            sidecar_path = output.with_suffix(".authenticity.json")
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            self.assertEqual(sidecar["result"], "captured")
            self.assertFalse(sidecar["canonicalEligible"])
            self.assertIn("profile crop provenance", sidecar["canonicalIneligibilityReasons"][0])
            with self.assertRaisesRegex(ParityError, "canonicalEligible=true"):
                verify_authenticity_file(sidecar_path, require_canonical=True)

    def test_capture_window_rejects_helper_source_rect_drift(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "fake-capture"
            helper.write_text(
                """#!/usr/bin/env python3
import json
import sys
from PIL import Image
args = sys.argv[1:]
output = args[args.index("--output") + 1]
Image.new("RGBA", (1080, 720), (0, 0, 0, 255)).save(output)
print(json.dumps({
  "captureAPI": "ScreenCaptureKit",
  "captureMode": "live-window",
  "pixelWidth": 1080,
  "pixelHeight": 720,
  "sourceRect": {"x": 1, "y": 0, "width": 540, "height": 360},
  "window": {
    "cgWindowId": 42,
    "ownerPid": 123,
    "ownerBundleId": "com.openai.codex",
    "ownerName": "Codex",
    "title": "Reference",
    "bounds": {"x": 0, "y": 0, "width": 540, "height": 360},
    "layer": 0,
    "isOnScreen": True
  }
}))
""",
                encoding="utf-8",
            )
            helper.chmod(0o755)
            completed = subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                    "capture-window",
                    "--window-id",
                    "42",
                    "--output",
                    str(root / "capture.png"),
                    "--renderer",
                    "in-app-browser",
                    "--scenario",
                    "A1",
                    "--profile",
                    "notch-v1",
                    "--expected-pid",
                    "123",
                    "--expected-bundle-id",
                    "com.openai.codex",
                    "--helper",
                    str(helper),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0, completed.stdout)
            self.assertIn(
                "source rectangle does not match the requested live-window crop",
                completed.stdout,
            )

    def test_capture_window_merges_verified_native_provenance_without_pid_override(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "OpenIslandApp"
            executable.write_bytes(b"temporary native executable")
            native_path = root / "native.json"
            native_path.write_text(
                json.dumps(native_manifest(executable)),
                encoding="utf-8",
            )
            helper = root / "fake-capture"
            helper.write_text(
                """#!/usr/bin/env python3
import json
import sys
from PIL import Image
args = sys.argv[1:]
output = args[args.index("--output") + 1]
Image.new("RGBA", (1080, 720), (0, 0, 0, 255)).save(output)
print(json.dumps({
  "captureAPI": "ScreenCaptureKit",
  "captureMode": "live-window",
  "pixelWidth": 1080,
  "pixelHeight": 720,
  "sourceRect": {"x": 0, "y": 0, "width": 540, "height": 360},
  "window": {
    "cgWindowId": 42,
    "ownerPid": 123,
    "ownerBundleId": "com.example.OpenIsland",
    "ownerName": "Open Island",
    "title": "Halo",
    "bounds": {"x": 0, "y": 0, "width": 540, "height": 360},
    "layer": 0,
    "isOnScreen": True
  }
}))
""",
                encoding="utf-8",
            )
            helper.chmod(0o755)
            for crop_proven in (False, True):
                with self.subTest(crop_proven=crop_proven):
                    output = root / f"native-{crop_proven}.png"
                    command = [
                        str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                        "capture-window",
                        "--window-id",
                        "42",
                        "--output",
                        str(output),
                        "--renderer",
                        "open-island-app",
                        "--scenario",
                        "A3",
                        "--profile",
                        "notch-v1",
                        "--native-sidecar",
                        str(native_path),
                        "--expected-pid",
                        "999",
                        "--expected-bundle-id",
                        "com.example.Wrong",
                        "--helper",
                        str(helper),
                    ]
                    if crop_proven:
                        command.append("--profile-crop-proven")
                    completed = subprocess.run(
                        command,
                        cwd=REPOSITORY_ROOT,
                        text=True,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        check=False,
                    )
                    self.assertEqual(completed.returncode, 0, completed.stdout)
                    sidecar_path = output.with_suffix(".authenticity.json")
                    sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
                    self.assertEqual(sidecar["nativeSidecar"]["process"]["pid"], 123)
                    self.assertNotIn("executable", sidecar)
                    self.assertEqual(sidecar["canonicalEligible"], crop_proven)
                    result = verify_authenticity_file(
                        sidecar_path,
                        expected_renderer="open-island-app",
                        require_canonical=crop_proven,
                    )
                    self.assertTrue(result["valid"])

    def test_capture_window_accepts_dirty_source_with_bound_native_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / "OpenIslandApp"
            executable.write_bytes(b"temporary native executable")
            native = native_manifest(executable)
            native["executable"]["sourceTreeDirty"] = True
            native_path = root / "native.json"
            native_path.write_text(json.dumps(native), encoding="utf-8")
            helper = root / "fake-capture"
            helper.write_text(
                """#!/usr/bin/env python3
import json
import sys
from PIL import Image
args = sys.argv[1:]
output = args[args.index("--output") + 1]
Image.new("RGBA", (1080, 720), (0, 0, 0, 255)).save(output)
print(json.dumps({
  "captureAPI": "ScreenCaptureKit",
  "captureMode": "live-window",
  "pixelWidth": 1080,
  "pixelHeight": 720,
  "sourceRect": {"x": 0, "y": 0, "width": 540, "height": 360},
  "window": {
    "cgWindowId": 42,
    "ownerPid": 123,
    "ownerBundleId": "com.example.OpenIsland",
    "ownerName": "Open Island",
    "title": "Halo",
    "bounds": {"x": 0, "y": 0, "width": 540, "height": 360},
    "layer": 0,
    "isOnScreen": True
  }
}))
""",
                encoding="utf-8",
            )
            helper.chmod(0o755)
            output = root / "native-dirty.png"
            completed = subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                    "capture-window",
                    "--window-id",
                    "42",
                    "--output",
                    str(output),
                    "--renderer",
                    "open-island-app",
                    "--scenario",
                    "A3",
                    "--profile",
                    "notch-v1",
                    "--native-sidecar",
                    str(native_path),
                    "--profile-crop-proven",
                    "--helper",
                    str(helper),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout)
            sidecar_path = output.with_suffix(".authenticity.json")
            sidecar = json.loads(sidecar_path.read_text(encoding="utf-8"))
            self.assertTrue(sidecar["canonicalEligible"])
            self.assertTrue(sidecar["nativeExpectations"]["sourceTreeDirty"])
            self.assertTrue(
                verify_authenticity_file(
                    sidecar_path,
                    expected_renderer="open-island-app",
                    require_canonical=True,
                )["valid"]
            )

    def test_gate_0a_proof_is_parsed_and_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            calibration = Path(directory)
            proof = calibration / "gate-0a-capture-authenticity.json"
            proof.write_text(
                json.dumps(
                    {
                        "schemaVersion": "1.0.0",
                        "passed": False,
                        "rendererProofs": {},
                    }
                ),
                encoding="utf-8",
            )
            with mock.patch("halo_parity.cli.CALIBRATION_ROOT", calibration):
                checks = _check_gate_0a()
            capture_check = next(
                check
                for check in checks
                if check.name == "canonical reference/native live-window proof"
            )
            self.assertFalse(capture_check.passed)
            self.assertIn("passed=true", capture_check.detail)

    def test_semantic_test_enables_only_the_explicit_parity_compile_condition(self) -> None:
        args = type(
            "Args",
            (),
            {"test_kind": "semantic", "dry_run": False, "record": False, "expect_missing": None},
        )()
        completed = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        with mock.patch("halo_parity.cli.run", return_value=completed) as mocked:
            self.assertEqual(command_test(args), 0)
        command = mocked.call_args.args[0]
        self.assertIn("-Xswiftc", command)
        self.assertIn("-DHALO_PARITY_TESTING", command)

    def test_record_goldens_fails_closed_without_gate_7_approval(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gate7 = root / "gate7.json"
            provenance = root / "provenance.json"
            gate7.write_text(
                json.dumps({"passed": False, "signatureVerified": False}),
                encoding="utf-8",
            )
            provenance.write_text(json.dumps({"records": []}), encoding="utf-8")
            completed = subprocess.run(
                [
                    str(REPOSITORY_ROOT / "scripts" / "halo-parity" / "halo"),
                    "record-goldens",
                    "--gate7-report",
                    str(gate7),
                    "--provenance",
                    str(provenance),
                    "--destination",
                    str(root / "goldens"),
                ],
                cwd=REPOSITORY_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("signature-verified Gate 7", completed.stdout)


if __name__ == "__main__":
    unittest.main()
