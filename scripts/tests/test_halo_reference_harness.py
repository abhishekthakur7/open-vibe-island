import hashlib
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from copy import deepcopy


REPO = pathlib.Path(__file__).resolve().parents[2]
REFERENCE = REPO / "Validation/HaloParity/reference"
SOURCE = REPO / "docs/design/overlay-redesign/06-halo.html"
MANIFEST = REPO / "Validation/HaloParity/halo-scenarios.json"
AUTHORITY = REFERENCE / "reference-authority-v1.json"
BUILDER = REFERENCE / "build-reference-harness.mjs"
GENERATED = REFERENCE / "generated/halo-reference-v1.html"
LOCK = REFERENCE / "reference-input-lock-v1.json"
SPEC = REFERENCE / "reference-spec-v1.json"
VARIANTS = REFERENCE / "reference-variants.json"
CONTROLLER = REFERENCE / "halo-reference-controller.js"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class HaloReferenceHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run(["node", str(BUILDER)], cwd=REPO, check=True, capture_output=True, text=True)
        cls.manifest = json.loads(MANIFEST.read_text())
        cls.authority = json.loads(AUTHORITY.read_text())
        cls.spec = json.loads(SPEC.read_text())
        cls.variants = json.loads(VARIANTS.read_text())
        cls.lock = json.loads(LOCK.read_text())

    def test_all_57_ids_have_non_null_controller_mapping(self):
        manifest_ids = [row["id"] for row in self.manifest["scenarios"]]
        authority_ids = [row["id"] for row in self.authority["scenarios"]]
        spec_ids = [row["id"] for row in self.spec["scenarios"]]
        self.assertEqual(57, len(manifest_ids))
        self.assertEqual(authority_ids, spec_ids)
        self.assertEqual(set(manifest_ids), set(spec_ids))
        for row in self.spec["scenarios"]:
            self.assertIn(row["mapping"]["kind"], {"established-anchor", "authored-variant"})
            self.assertTrue(row["mapping"].get("selector"))
            self.assertNotIn("result", row)
            self.assertNotIn("sourceDisposition", row)
            self.assertNotIn("native", row)
        authored = [r for r in self.spec["scenarios"] if r["mapping"]["kind"] == "authored-variant"]
        self.assertEqual(51, len(authored))
        self.assertEqual({r["id"] for r in authored}, set(self.variants["decisions"]))
        for decision in self.variants["decisions"].values():
            self.assertIsNone(decision["provenance"]["approval"])
            self.assertEqual(
                "halo-reference-authority-v1",
                decision["provenance"]["authority"],
            )
            self.assertNotIn("rationale", decision["provenance"])
            self.assertNotIn("sourceScenarioDisposition", decision["provenance"])
            self.assertEqual(12, len(decision["laws"]))

    def test_builder_is_deterministic_and_source_is_immutable(self):
        source_before = sha(SOURCE)
        first = (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS))
        subprocess.run(["node", str(BUILDER)], cwd=REPO, check=True, capture_output=True, text=True)
        second = (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS))
        self.assertEqual(first, second)
        self.assertEqual(source_before, sha(SOURCE))
        self.assertEqual(source_before, self.lock["sourceImmutability"]["sha256"])

    def test_generated_default_is_original_board_plus_inert_injection(self):
        source = SOURCE.read_text()
        generated = GENERATED.read_text()
        self.assertIn('<div class="board">', generated)
        self.assertEqual(source.count("<section>"), generated.count("<section>"))
        self.assertIn('id="halo-reference-status" hidden', generated)
        self.assertIn('id="halo-reference-fiducial" hidden', generated)
        self.assertNotIn('data-halo-harness="true"', generated)
        self.assertIn('html[data-halo-harness="true"] body > .board { display: none; }',
                      (REFERENCE / "halo-reference-variants.css").read_text())

    def test_injected_resource_order(self):
        html = GENERATED.read_text()
        style = html.index('data-halo-injected="styles"')
        spec = html.index('data-halo-injected="spec"')
        export = html.index('data-halo-injected="export"')
        controller = html.index('data-halo-injected="controller"')
        self.assertLess(style, html.index("</head>"))
        self.assertLess(spec, export)
        self.assertLess(export, controller)
        self.assertLess(controller, html.index("</body>"))

    def test_controller_rejects_unknown_config_and_has_deterministic_transitions(self):
        node_script = r"""
const fs = require("fs"), vm = require("vm");
const spec = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const variants = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const code = fs.readFileSync(process.argv[3], "utf8");
const document = {readyState:"loading", addEventListener(){}, querySelectorAll(){return []}};
const window = {__HALO_REFERENCE_SPEC__:spec,__HALO_REFERENCE_VARIANTS__:variants,document,location:{search:""}};
const context = {window,document,URLSearchParams,NodeFilter:{SHOW_TEXT:4},console};
vm.createContext(context); vm.runInContext(code, context);
const c = window.HaloReferenceController;
const base = {scenarioId:"A3",profile:"notch-v1",motionMode:"manual",accessibilityMode:"default",seed:"test-1",eventId:"none",timeMs:0};
const rejected = [];
for (const patch of [{scenarioId:"NOPE"},{profile:"unknown"},{motionMode:"frozen"},{accessibilityMode:"magic"},{eventId:"bogus"},{extra:true}]) {
  try { c.validateConfig(Object.assign({}, base, patch)); rejected.push(false); } catch (_) { rejected.push(true); }
}
process.stdout.write(JSON.stringify({rejected,open:c.transitionPhase("open"),success:c.transitionPhase("complete-success"),escape:c.transitionPhase("escape")}));
"""
        result = subprocess.run(
            ["node", "-e", node_script, str(SPEC), str(VARIANTS), str(CONTROLLER)],
            cwd=REPO, check=True, capture_output=True, text=True
        )
        report = json.loads(result.stdout)
        self.assertTrue(all(report["rejected"]))
        self.assertEqual({"open": "opened", "success": "success", "escape": "closed"},
                         {k: report[k] for k in ("open", "success", "escape")})

    def test_candidate_export_is_png_and_explicitly_unqualified(self):
        export = (REFERENCE / "halo-reference-export.js").read_text()
        self.assertIn('canvas.toBlob(resolve, "image/png")', export)
        self.assertIn("bytes[0] === 137", export)
        self.assertIn('"candidate-unqualified"', export)
        self.assertIn("canonicalCapture: false", export)
        controller = CONTROLLER.read_text()
        self.assertIn('query.get("exportProbe") === "1"', controller)
        self.assertIn("haloExportSignature", controller)

    def test_lock_has_required_hashes_and_recomputable_merkle(self):
        by_path = {item["path"]: item["sha256"] for item in self.lock["inputs"]}
        for required in [
            "docs/design/overlay-redesign/06-halo.html",
            "Validation/HaloParity/reference/reference-authority-v1.json",
            "Validation/HaloParity/reference/build-reference-harness.mjs",
            "Validation/HaloParity/reference/halo-reference-controller.js",
            "Validation/HaloParity/reference/halo-reference-variants.css",
            "Validation/HaloParity/reference/halo-reference-export.js",
        ]:
            self.assertIn(required, by_path)
        for forbidden in [
            "Validation/HaloParity/halo-scenarios.json",
            "Validation/HaloParity/halo-gap-ledger-v1.json",
            "docs/design/overlay-redesign/halo-visual-parity-audit.md",
            "Validation/HaloParity/reference/reference-spec-v1.json",
            "Validation/HaloParity/reference/reference-variants.json",
        ]:
            self.assertNotIn(forbidden, by_path)
        lines = [f"{p}\0{h}" for p, h in by_path.items()]
        root = hashlib.sha256("\n".join(sorted(lines)).encode()).hexdigest()
        self.assertEqual(root, self.lock["merkleRoot"])
        outputs = {item["path"]: item["sha256"] for item in self.lock["outputs"]}
        self.assertEqual(sha(GENERATED), outputs[str(GENERATED.relative_to(REPO))])
        self.assertEqual(sha(SPEC), outputs[str(SPEC.relative_to(REPO))])
        self.assertEqual(sha(VARIANTS), outputs[str(VARIANTS.relative_to(REPO))])

    def test_native_only_manifest_mutations_do_not_change_reference_artifacts(self):
        baseline = (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS))
        mutated = deepcopy(self.manifest)
        for index, row in enumerate(mutated["scenarios"]):
            row["fixtureData"] = {"nativeOnlyMutation": index}
            row["native"] = {
                "fixture": f"mutated-{index}",
                "triggerSequence": ["native-only"],
            }
            row["reproductionEvidence"] = {"attempt": "mutated"}
            row["disposition"] = (
                "exact" if row.get("disposition") != "exact" else "blocked"
            )
            row["rationale"] = "native-only mutation"
            row["result"] = "passed"
            row["approver"] = "not-reference-authority"
        with tempfile.TemporaryDirectory() as directory:
            manifest = pathlib.Path(directory) / "manifest.json"
            manifest.write_text(json.dumps(mutated), encoding="utf-8")
            environment = os.environ.copy()
            environment["HALO_PARITY_SCENARIO_MANIFEST"] = str(manifest)
            subprocess.run(
                ["node", str(BUILDER)],
                cwd=REPO,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(baseline, (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS)))

    def test_manifest_reorder_does_not_change_reference_artifacts(self):
        baseline = (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS))
        mutated = deepcopy(self.manifest)
        mutated["scenarios"].reverse()
        with tempfile.TemporaryDirectory() as directory:
            manifest = pathlib.Path(directory) / "manifest.json"
            manifest.write_text(json.dumps(mutated), encoding="utf-8")
            environment = os.environ.copy()
            environment["HALO_PARITY_SCENARIO_MANIFEST"] = str(manifest)
            subprocess.run(
                ["node", str(BUILDER)],
                cwd=REPO,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
        self.assertEqual(baseline, (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS)))

    def test_manifest_id_change_is_rejected_before_output_writes(self):
        baseline = (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS))
        mutated = deepcopy(self.manifest)
        mutated["scenarios"][0]["id"] = "NOT-A-REFERENCE-ID"
        with tempfile.TemporaryDirectory() as directory:
            manifest = pathlib.Path(directory) / "manifest.json"
            manifest.write_text(json.dumps(mutated), encoding="utf-8")
            environment = os.environ.copy()
            environment["HALO_PARITY_SCENARIO_MANIFEST"] = str(manifest)
            completed = subprocess.run(
                ["node", str(BUILDER)],
                cwd=REPO,
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("ID sets differ", completed.stderr)
        self.assertEqual(baseline, (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS)))

    def test_generated_native_fields_are_overwritten_from_authority(self):
        baseline = (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS))
        corrupted = deepcopy(self.spec)
        corrupted["scenarios"][0]["native"] = {"fixture": "forbidden"}
        corrupted["scenarios"][0]["disposition"] = "exact"
        SPEC.write_text(json.dumps(corrupted), encoding="utf-8")
        try:
            subprocess.run(
                ["node", str(BUILDER)],
                cwd=REPO,
                check=True,
                capture_output=True,
                text=True,
            )
        finally:
            if (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS)) != baseline:
                subprocess.run(
                    ["node", str(BUILDER)],
                    cwd=REPO,
                    check=True,
                    capture_output=True,
                    text=True,
                )
        self.assertEqual(baseline, (sha(GENERATED), sha(LOCK), sha(SPEC), sha(VARIANTS)))


if __name__ == "__main__":
    unittest.main()
