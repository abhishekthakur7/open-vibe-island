from __future__ import annotations

import hashlib
import json
import math
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
from importlib import metadata
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from .dom import verify_reference_dom as execute_reference_dom
from .trust import (TrustError, contained_path, digest, iter_files, read_json,
    iso_timestamp, validate_provenance, validate_run_root)

ROOT = Path(__file__).resolve().parents[2]
VALIDATION = ROOT / "Validation" / "PouredParity"
ARTIFACTS = ROOT / "artifacts" / "poured-parity"
CLASSES = {"rendered-canonical", "rendered-motion-exemplar", "specified-invariant", "derived-validation", "platform-adaptation"}
NATIVE_STATUSES = {"exact", "partial", "not-located", "not-reproducible"}
LEDGER_STATUSES = {"open", "implementation-in-progress", "implemented-awaiting-capture", "metric-fail", "review-fail", "passed", "waived", "blocked-unvalidated"}
DIRECT_CLASSES = {"rendered-canonical", "rendered-motion-exemplar"}
CONFLICTS = {"PI-REF-001", "PI-REF-002", "PI-REF-003"}
REQUIRED_SCENARIOS = {
    "A1-idle","A2-working-one","A2m-working-many","A3-permission","A3m-permission-queue","A4-question","A5-success","A6-outcomes",
    "B1-hover-peek","B2-pill-peek-panel","C1-grouped-six","C2-cap-boundary","C3-overflow","C4-stress-40",
    "D1-detail","E1-command-permission","E2-diff-permission","E3-jump-codex","E4-notification","F1-question",
    "F2-multi-question","F3-multi-select","F4-compact-question","G1-nested-tasks","G2-compressed-row","G3-task-pill",
    "H1-completed","H2-post-success","I1-usage-normal","I2-usage-threshold","I3-usage-pill","J1-empty",
    "K1-open-close","K2-row-entry","K3-attention-cycle","KX-breath-css","KX-morph-css","KX-attention-css","KX-row-css","KX-success-css",
}
REQUIRED_BINDINGS = ["reference", "scenarios", "fixtures", "behavior", "adaptations", "measurements", "masks", "calibration", "motion_authority", "applicability", "principals", "conflict_dispositions", "gate0c_schemas", "dependencies", "driver", "capture"]
CALIBRATION_LIMITS = {"mapping_residual_max","declared_scale_residual_max","landmark_repeatability_max","cross_renderer_residual_max","pixel_noise_mean_max","color_variance_mean_max","timing_jitter_max","duplicates_max","drops_max"}
SOURCE_DERIVED_PATHS = {"baseline-matrix.json", "review-packet.json"}


ParityError = TrustError


def _raster():
    try:
        from . import raster
        return raster
    except ImportError as exc:
        raise ParityError(f"raster support unavailable; install pinned dependencies: {exc}") from exc


def _authorized(role: str) -> set[str]:
    registry=load(VALIDATION/"principals-v1.json")
    if not isinstance(registry,dict) or set(registry)!={"schema_version","id","status","principals"} or registry.get("schema_version")!=1 or registry.get("status") not in {"pending","approved"} or not isinstance(registry.get("principals"),list): raise ParityError("principal authority registry schema mismatch")
    identities=set(); result=set(); allowed_roles={"product-design-owner","independent-reviewer","calibration-reviewer","implementation-principal","environment-attestor"}
    for row in registry["principals"]:
        if not isinstance(row,dict) or set(row)!={"identity","roles","status"} or not isinstance(row.get("identity"),str) or not row["identity"].strip() or not isinstance(row.get("roles"),list) or not row["roles"] or not set(row["roles"])<=allowed_roles or row.get("status") not in {"approved","revoked"}: raise ParityError("principal authority registry entry schema mismatch")
        normalized=" ".join(row["identity"].strip().casefold().split())
        if normalized in identities: raise ParityError("principal authority registry contains duplicate identities")
        identities.add(normalized)
        if row["status"]=="approved" and role in row["roles"]: result.add(row["identity"])
    return result


def _calibration_authorities(require_approved: bool = False) -> tuple[dict[str,Any],dict[str,Any]]:
    calibration=load(VALIDATION/"calibration-v1.json")
    required={"schema_version","id","contract_version","approval","neutral_only","target_id","color_profile","required_renderers","minimum_stills_per_renderer","minimum_motion_runs_per_renderer","registration","registration_anchor_names","logical_to_device_scale","fiducials","limits","aa_band","threshold_bundle","mask_manifest","dependencies_sha256","bundle_authority","status"}
    if not isinstance(calibration,dict) or set(calibration)!=required or calibration.get("schema_version")!=1 or calibration.get("id")!="poured-calibration-v1" or calibration.get("contract_version")!=1 or calibration.get("neutral_only") is not True or set(calibration.get("required_renderers",[]))!={"css","swiftui"} or calibration.get("minimum_stills_per_renderer")!=5 or calibration.get("minimum_motion_runs_per_renderer")!=3 or calibration.get("fiducials")!=["nw","ne","sw","se"] or calibration.get("threshold_bundle")!="poured-measurements-v1" or calibration.get("bundle_authority")!="calibration-bundle-authority-v1.json" or not isinstance(calibration.get("limits"),dict) or set(calibration["limits"])!=CALIBRATION_LIMITS:
        raise ParityError("calibration authority schema drift")
    approval=calibration.get("approval")
    approved=calibration.get("status")=="approved"
    if approved:
        if not isinstance(approval,dict) or set(approval)!={"status","independent_reviewer"} or approval.get("status")!="approved" or not all(_finite_number(value,minimum=0) for value in calibration["limits"].values()): raise ParityError("approved calibration authority is incomplete")
        validate_provenance(approval["independent_reviewer"],root=ROOT,allowed_dispositions={"PASS"},required_role="independent-reviewer",authorized_identities=_authorized("independent-reviewer"))
    elif calibration.get("status")!="blocked-unvalidated" or approval!={"status":"pending","independent_reviewer":None} or any(value is not None for value in calibration["limits"].values()):
        raise ParityError("pending calibration authority has acceptance values")
    bundle=load(VALIDATION/calibration["bundle_authority"])
    required_bundle={"schema_version","id","status","bundle_path","bundle_sha256","calibration_sha256","approval"}
    if not isinstance(bundle,dict) or set(bundle)!=required_bundle or bundle.get("schema_version")!=1 or bundle.get("id")!="poured-calibration-bundle-authority-v1" or not isinstance(bundle.get("approval"),dict) or set(bundle["approval"])!={"product_design_owner","independent_reviewer"}: raise ParityError("calibration bundle authority schema drift")
    bundle_approved=bundle.get("status")=="approved"
    if bundle_approved:
        if not all(isinstance(bundle.get(key),str) and bundle[key] for key in ("bundle_path","bundle_sha256","calibration_sha256")) or bundle["calibration_sha256"]!=sha256(VALIDATION/"calibration-v1.json"): raise ParityError("approved calibration bundle authority is incomplete")
        owner=validate_provenance(bundle["approval"]["product_design_owner"],root=ROOT,allowed_dispositions={"ACCEPT"},required_role="product-design-owner",authorized_identities=_authorized("product-design-owner"))
        validate_provenance(bundle["approval"]["independent_reviewer"],root=ROOT,allowed_dispositions={"PASS"},required_role="independent-reviewer",distinct_from=owner["identity"],authorized_identities=_authorized("independent-reviewer"))
    elif bundle.get("status")!="pending" or any(bundle.get(key) is not None for key in ("bundle_path","bundle_sha256","calibration_sha256")) or any(value is not None for value in bundle["approval"].values()):
        raise ParityError("pending calibration bundle authority has acceptance values")
    if require_approved and (not approved or not bundle_approved): raise ParityError("Gate 0B blocked: committed calibration authority is absent or pending")
    return calibration,bundle


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ParityError(f"cannot read JSON {path}: {exc}") from exc


def write(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temporary.replace(path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_hash(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in sorted((p for p in paths if p.is_file()), key=lambda p: str(p)):
        digest.update(str(path.resolve().relative_to(ROOT)).encode())
        digest.update(b"\0")
        digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if result.returncode:
        raise ParityError(result.stdout.strip())
    return result.stdout.strip()


def safe_run_root(native_commit: str, run_id: str) -> Path:
    for value, label in ((native_commit, "native commit"), (run_id, "run ID")):
        if not value or value in {".", "..", "current"} or "/" in value or "\\" in value:
            raise ParityError(f"unsafe {label}: {value!r}")
    candidate = ARTIFACTS / native_commit / run_id
    return validate_run_root(candidate, ARTIFACTS, require_manifest=False)


def artifact_run_for(path: Path, require_file: bool = False) -> tuple[Path, Path]:
    absolute = path if path.is_absolute() else Path.cwd() / path
    try:
        relative = absolute.relative_to(ARTIFACTS)
    except ValueError as exc:
        raise ParityError("artifact operation requires a canonical poured-parity run root") from exc
    if len(relative.parts) < 3:
        raise ParityError("artifact operation requires a file below a canonical run root")
    root = validate_run_root(ARTIFACTS / relative.parts[0] / relative.parts[1], ARTIFACTS)
    return root, contained_path(root, Path(*relative.parts[2:]), require_file=require_file)


NATIVE_SYMBOL = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*$")


def _swift_sources() -> list[tuple[Path, str]]:
    return [(path, path.read_text(encoding="utf-8", errors="replace")) for path in sorted((ROOT / "Sources").rglob("*.swift"))]


def _verify_native_symbol(scenario_id: str, mapping: Any, sources: list[tuple[Path, str]]) -> None:
    """Reject any native mapping that names a Swift symbol the sources do not declare.

    The manifest is the only place a scenario claims a native driver; an
    unchecked string here silently invents authority (for example the never
    existing `IslandDebugScenario.permission`). Claims are therefore checked
    against the actual repository source text, exactly like anchors are.
    """
    if not isinstance(mapping, str) or not NATIVE_SYMBOL.match(mapping):
        raise ParityError(f"native mapping for {scenario_id} is not a <Type>.<member> Swift symbol: {mapping!r}")
    type_name, member = mapping.split(".", 1)
    declaration = re.compile(rf"\b(?:enum|struct|class|actor|protocol)\s+{re.escape(type_name)}\b")
    extension = re.compile(rf"\bextension\s+{re.escape(type_name)}\b")
    member_declaration = re.compile(rf"\b(?:case|func|var|let)\s+{re.escape(member)}\b")
    candidates = [text for _, text in sources if declaration.search(text)]
    if not candidates:
        raise ParityError(f"native mapping for {scenario_id} names an undeclared Swift type: {mapping}")
    candidates += [text for _, text in sources if extension.search(text)]
    if not any(member_declaration.search(text) for text in candidates):
        raise ParityError(f"native mapping for {scenario_id} names a member absent from Swift sources: {mapping}")


def verify_manifests(require_ready: bool = False) -> dict[str, Any]:
    authority = load(VALIDATION / "authority.json")
    ref = ROOT / authority["reference"]["path"]
    if sha256(ref) != authority["reference"]["sha256"]:
        raise ParityError("reference source hash mismatch")
    lines = ref.read_text(encoding="utf-8").splitlines()
    manifest = load(VALIDATION / "scenarios-v1.json")
    identity_manifest = load(VALIDATION / "reference-identities-v1.json")
    if identity_manifest.get("source_sha256") != authority["reference"]["sha256"]:
        raise ParityError("reference identity contract is bound to the wrong source")
    identities = identity_manifest.get("identities", {})
    scenarios = manifest.get("scenarios")
    if not isinstance(scenarios, list):
        raise ParityError("scenarios must be an array")
    seen: set[str] = set()
    counts: dict[str, int] = {}
    swift_sources = _swift_sources()
    for row in scenarios:
        scenario_id = row.get("id")
        if not isinstance(scenario_id, str) or not scenario_id or scenario_id in seen:
            raise ParityError(f"duplicate or invalid scenario ID: {scenario_id!r}")
        seen.add(scenario_id)
        cls = row.get("class")
        if cls not in CLASSES:
            raise ParityError(f"unknown class for {scenario_id}: {cls!r}")
        native = row.get("native", {})
        status = native.get("status")
        if status not in NATIVE_STATUSES:
            raise ParityError(f"unknown native status for {scenario_id}: {status!r}")
        if not isinstance(native, dict) or set(native) != {"mapping", "status"}:
            raise ParityError(f"native contract schema mismatch for {scenario_id}")
        if native["mapping"] is not None:
            _verify_native_symbol(scenario_id, native["mapping"], swift_sources)
        if row.get("state") not in set("ABCDEFGHIJK"):
            raise ParityError(f"unknown state for {scenario_id}")
        anchor = row.get("anchor", {})
        bounds = anchor.get("lines")
        if not isinstance(bounds, list) or len(bounds) != 2 or bounds[0] < 1 or bounds[1] > len(lines) or bounds[0] > bounds[1]:
            raise ParityError(f"invalid source line anchor for {scenario_id}")
        selector = anchor.get("selector")
        if not isinstance(selector, str) or not selector or not "\n".join(lines[bounds[0] - 1:bounds[1]]).strip():
            raise ParityError(f"empty selector/source anchor for {scenario_id}")
        if row.get("direct_reference", False) and cls not in DIRECT_CLASSES:
            raise ParityError(f"non-rendered scenario {scenario_id} claims a direct reference")
        if cls in DIRECT_CLASSES:
            identity = identities.get(scenario_id)
            if not isinstance(identity, dict) or set(identity) != {"tag", "classes", "text_contains"}:
                raise ParityError(f"missing reference identity contract for {scenario_id}")
            if not identity["tag"] or not isinstance(identity["classes"], list) or not isinstance(identity["text_contains"], list):
                raise ParityError(f"invalid reference identity contract for {scenario_id}")
        counts[cls] = counts.get(cls, 0) + 1
    if seen != REQUIRED_SCENARIOS:
        raise ParityError(f"stable scenario inventory drift: missing={sorted(REQUIRED_SCENARIOS-seen)} extra={sorted(seen-REQUIRED_SCENARIOS)}")
    by_id = {row["id"]: row for row in scenarios}
    expected_contract = {
        "F1-question": ("derived-validation", None, "not-located"),
        "A1-idle": ("rendered-canonical", None, "not-located"),
        "E1-command-permission": ("rendered-canonical", "IslandDebugScenario.approvalCard", "partial"),
        "A2-working-one": ("rendered-canonical", "IslandDebugScenario.closed", "partial"),
        "A2m-working-many": ("rendered-canonical", "IslandDebugScenario.closedMultiRunning", "partial"),
        "A3-permission": ("rendered-canonical", "IslandDebugScenario.closedAttention", "partial"),
        "C4-stress-40": ("derived-validation", None, "not-located"),
        "H1-completed": ("rendered-canonical", "IslandDebugScenario.completedSuccess", "partial"),
    }
    for scenario_id, (expected_class, mapping, status) in expected_contract.items():
        row = by_id.get(scenario_id)
        if row is None or (row["class"], row["native"]["mapping"], row["native"]["status"]) != (expected_class, mapping, status):
            raise ParityError(f"scenario contract drift for {scenario_id}")
    for required_id in ("D1-detail", "E1-command-permission", "E2-diff-permission", "E3-jump-codex"):
        if required_id not in by_id:
            raise ParityError(f"missing stable scenario ID {required_id}")
    ledger = load(VALIDATION / "ledger-v1.json")
    if set(ledger.get("allowed_statuses", [])) != LEDGER_STATUSES:
        raise ParityError("ledger allowed statuses differ from v1 contract")
    ledger_ids: set[str] = set()
    ledger_required = {"id","states","title","reference_expectation","current_behavior","exact_delta","evidence_locations","confidence","severity","priority","source_symbols","deterministic_scenario","regions","acceptance","slice","owner","status","review_verdict","waiver","final_artifact_paths"}
    for item in ledger.get("items", []):
        if item.get("id") in ledger_ids:
            raise ParityError(f"duplicate ledger ID {item.get('id')}")
        ledger_ids.add(item.get("id"))
        if item.get("status") not in LEDGER_STATUSES:
            raise ParityError(f"unknown ledger status for {item.get('id')}")
        if set(item) != ledger_required:
            raise ParityError(f"incomplete ledger item {item.get('id')}: fields differ from v1 contract")
        if not item.get("evidence_locations") or not item.get("regions") or not item.get("states"):
            raise ParityError(f"incomplete ledger item {item.get('id')}")
    conflicts = {x["id"]: x for x in load(VALIDATION / "conflicts-v1.json")["conflicts"]}
    disposition_manifest=load(VALIDATION/"conflict-dispositions-v1.json")
    expected_dispositions={"PI-REF-001":["one-shot","loop","owner-supplied-artifact"],"PI-REF-002":["interactive-spring","css-exemplar-only","owner-supplied-artifact"],"PI-REF-003":["interactive-spring","css-exemplar-only","owner-supplied-artifact"]}
    if not isinstance(disposition_manifest,dict) or set(disposition_manifest)!={"schema_version","id","status","dispositions"} or disposition_manifest.get("schema_version")!=1 or disposition_manifest.get("status")!="pending" or disposition_manifest.get("dispositions")!=expected_dispositions: raise ParityError("conflict-specific disposition vocabulary drift")
    conflict_dispositions=disposition_manifest["dispositions"]
    runtime_contract=load(VALIDATION/"runtime-v1.json"); requirements={line.split("==",1)[0]:line.split("==",1)[1] for line in (VALIDATION/"requirements-v1.txt").read_text().splitlines() if "==" in line}
    if not isinstance(runtime_contract,dict) or set(runtime_contract)!={"schema_version","id","supported_python","packages","secure_wheel_hashes","status"} or runtime_contract.get("schema_version")!=1 or runtime_contract.get("packages")!=requirements or runtime_contract.get("secure_wheel_hashes") is not False: raise ParityError("runtime dependency authority schema/version drift")
    motion_authority=load(VALIDATION/"motion-authority-v1.json")
    if not isinstance(motion_authority,dict) or set(motion_authority)!={"schema_version","id","status","rendered_css","diagnostic_limits","interactive_timelines"} or motion_authority.get("schema_version")!=1 or motion_authority.get("status")!="pending": raise ParityError("motion authority schema drift")
    rendered=motion_authority.get("rendered_css"); diagnostic=motion_authority.get("diagnostic_limits")
    if not isinstance(rendered,dict) or set(rendered)!={"required_checkpoints","required_events","minimum_duration_seconds","start_tolerance_seconds"} or not isinstance(rendered.get("required_checkpoints"),list) or len(rendered["required_checkpoints"])<2 or rendered["required_checkpoints"][0]!="t0" or rendered["required_checkpoints"][-1]!="settled" or len(rendered["required_checkpoints"])!=len(set(rendered["required_checkpoints"])) or not isinstance(rendered.get("required_events"),list) or rendered["required_events"]!=["trigger","settled"] or not _finite_number(rendered.get("minimum_duration_seconds"),minimum=0) or not _finite_number(rendered.get("start_tolerance_seconds"),minimum=0) or not isinstance(diagnostic,dict) or set(diagnostic)!={"timing_jitter_max","duplicates_max","drops_max"} or not all(_finite_number(value,minimum=0) for value in diagnostic.values()) or motion_authority.get("interactive_timelines")!="behavior-v1.json": raise ParityError("motion authority checkpoint/event/tolerance contract drift")
    baseline_schema=load(VALIDATION/"baseline-matrix-schema-v1.json"); sidecar_schema=load(VALIDATION/"baseline-evidence-sidecar-schema-v1.json"); metric_schema=load(VALIDATION/"metric-report-schema-v1.json")
    if baseline_schema.get("required")!=["schema_version","applicability_sha256","ledger_sha256","source_evidence_sha256","records"] or baseline_schema.get("record_required")!=["scenario","profile","variant","authority_class","complete","ledger_ids","evidence","source_evidence_sha256"] or sidecar_schema.get("roles")!=["reference","native","authority"] or sidecar_schema.get("dispositions")!=["exact"] or "source_evidence_sha256" not in metric_schema.get("binding_required",[]) or "evidence_index_sha256" in metric_schema.get("binding_required",[]): raise ParityError("Gate 0C schema authority drift")
    _calibration_authorities()
    _authorized("product-design-owner"); _authorized("independent-reviewer"); _applicability()
    for conflict_id in CONFLICTS:
        conflict = conflicts.get(conflict_id)
        item = next((x for x in ledger["items"] if x["id"] == conflict_id), None)
        if not conflict or not item:
            raise ParityError(f"missing required conflict {conflict_id}")
        resolved = conflict.get("status") != "blocked-unvalidated" or item["status"] == "passed"
        if resolved:
            ruling = conflict.get("ruling")
            authority_record = conflict.get("authority")
            if ruling not in set(conflict_dispositions.get(conflict_id,[])):
                raise ParityError(f"{conflict_id} has no allowed product/design-owner disposition")
            validate_provenance(authority_record, root=ROOT,
                allowed_dispositions={ruling}, required_role="product-design-owner", authorized_identities=_authorized("product-design-owner"))
    pending = authority.get("approval", {}).get("status") != "approved" or not authority.get("acceptance_authority")
    if not pending:
        owner = validate_provenance(authority["approval"], root=ROOT,
            allowed_dispositions={"ACCEPT"}, required_role="product-design-owner", authorized_identities=_authorized("product-design-owner"))
        reviewer = validate_provenance(authority.get("independent_approval"), root=ROOT,
            allowed_dispositions={"PASS"}, required_role="independent-reviewer", distinct_from=owner["identity"], authorized_identities=_authorized("independent-reviewer"))
    if require_ready and pending:
        raise ParityError("authority approval is pending and cannot qualify acceptance")
    return {"scenario_count": len(scenarios), "class_counts": counts, "ledger_count": len(ledger_ids), "approval_pending": pending}


def verify_reference_dom() -> dict[str, Any]:
    verify_manifests()
    authority = load(VALIDATION / "authority.json")
    scenarios = load(VALIDATION / "scenarios-v1.json")["scenarios"]
    identities = load(VALIDATION / "reference-identities-v1.json")["identities"]
    enriched = []
    for row in scenarios:
        copy = dict(row)
        copy["anchor"] = dict(row["anchor"])
        if row["class"] in DIRECT_CLASSES:
            copy["anchor"]["identity"] = identities[row["id"]]
        enriched.append(copy)
    return execute_reference_dom(ROOT / authority["reference"]["path"], authority["reference"]["sha256"], enriched)


def _command_value(command: list[str]) -> str | None:
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=5)
        return result.stdout.strip() or None if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def _finite_number(value: Any, *, minimum: float | None = None, maximum: float | None = None) -> bool:
    return type(value) in {int, float} and math.isfinite(value) and (minimum is None or value >= minimum) and (maximum is None or value <= maximum)


def _browser_identity() -> dict[str,str|None]:
    candidates=[Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),Path("/Applications/Chromium.app/Contents/MacOS/Chromium")]
    executable=next((x for x in candidates if x.is_file()),None)
    version=_command_value([str(executable),"--version"]) if executable else None
    return {"name":version.split()[0] if version else None,"version":version,"executable":str(executable) if executable else None,"sha256":sha256(executable) if executable else None}


def _runtime_identity() -> dict[str,Any]:
    packages={}
    for distribution in ("numpy","opencv-python","Pillow","scipy","websockets"):
        try: packages[distribution]=metadata.version(distribution)
        except metadata.PackageNotFoundError: packages[distribution]=None
    return {"python":platform.python_version(),"implementation":platform.python_implementation(),"executable":sys.executable,"packages":packages,"requirements_sha256":sha256(VALIDATION/"requirements-v1.txt"),"runtime_authority_sha256":sha256(VALIDATION/"runtime-v1.json")}


def _validate_environment(environment: Any, local_git: dict[str, Any], attestation: Any) -> tuple[dict[str,Any],dict[str,Any],list[str]]:
    expected_sections={"git","target","system","display","preferences","locale","browser","window","capture","bundle"}
    if not isinstance(environment,dict) or set(environment)!=expected_sections or environment.get("git") != local_git:
        raise ParityError("binding environment.git must exactly match locally measured Git identity")
    def exact(section: str, keys: set[str]) -> dict[str,Any]:
        value=environment.get(section)
        if not isinstance(value,dict) or set(value)!=keys: raise ParityError(f"binding environment.{section} schema mismatch")
        return value
    target=exact("target",{"name","executable","executable_sha256","build_configuration","macho_uuid","app_version","build_version"})
    system=exact("system",{"macos","hardware","model","gpu"})
    display=exact("display",{"stable_identity","logical_size","native_size","scale","profile","refresh_hz"})
    preferences=exact("preferences",{"appearance","accent","reduce_motion","reduce_transparency","increase_contrast","text_size"})
    locale=exact("locale",{"locale","timezone","hour_cycle"})
    browser=exact("browser",{"name","version","zoom","dpr","viewport","flags"})
    window=exact("window",{"bounds","crop","backdrop_path","backdrop_sha256"})
    capture=exact("capture",{"format","encoding","api","helper_path","helper_sha256"})
    bundle=exact("bundle",{"identifier","signing_identity","team_identifier"})
    strings=[target[k] for k in ("name","build_configuration","macho_uuid","app_version","build_version")]+list(system.values())+[display[k] for k in ("stable_identity","profile")]+[preferences[k] for k in ("appearance","accent","text_size")]+list(locale.values())+[browser[k] for k in ("name","version")]+[capture[k] for k in ("format","encoding","api")]+list(bundle.values())
    if any(not isinstance(value,str) or not value.strip() for value in strings): raise ParityError("binding environment contains empty or untyped identity strings")
    if preferences["appearance"] not in {"light","dark"} or locale["hour_cycle"] not in {"12","24"} or capture["format"] != "png": raise ParityError("binding environment contains unsupported semantic values")
    if any(type(preferences[key]) is not bool for key in ("reduce_motion","reduce_transparency","increase_contrast")): raise ParityError("accessibility preferences must be booleans")
    for key in ("logical_size","native_size"):
        if not isinstance(display[key],list) or len(display[key])!=2 or not all(type(x) is int and x>0 for x in display[key]): raise ParityError(f"display {key} must be two positive integers")
    if not _finite_number(display["scale"],minimum=1,maximum=4) or not _finite_number(display["refresh_hz"],minimum=30,maximum=1000): raise ParityError("display scale/refresh are invalid")
    if not _finite_number(browser["zoom"],minimum=.25,maximum=4) or not _finite_number(browser["dpr"],minimum=1,maximum=4): raise ParityError("browser zoom/DPR are invalid")
    if not isinstance(browser["viewport"],list) or len(browser["viewport"])!=2 or not all(type(x) is int and x>0 for x in browser["viewport"]) or not isinstance(browser["flags"],list) or not all(isinstance(x,str) for x in browser["flags"]): raise ParityError("browser viewport/flags are invalid")
    for key in ("bounds","crop"):
        if not isinstance(window[key],list) or len(window[key])!=4 or not all(_finite_number(x) for x in window[key]): raise ParityError(f"window {key} is invalid")
    if window["bounds"][2]<=0 or window["bounds"][3]<=0 or window["crop"][0]<0 or window["crop"][1]<0 or window["crop"][2]<=0 or window["crop"][3]<=0: raise ParityError("window bounds/crop dimensions are invalid")
    if abs(display["logical_size"][0]*display["scale"]-display["native_size"][0])>.01 or abs(display["logical_size"][1]*display["scale"]-display["native_size"][1])>.01: raise ParityError("display logical/native size does not match scale")
    measured_system={"macos":platform.mac_ver()[0] or None,"hardware":platform.machine() or None}
    if system["macos"]!=measured_system["macos"] or system["hardware"]!=measured_system["hardware"]: raise ParityError("binding system identity differs from locally measured values")
    browser_identity=_browser_identity(); unresolved=[]
    if browser_identity["version"] is None:
        # No local Chrome/Chromium means the bound browser name/version cannot be
        # measured at all. Treat them as unmeasured (like display facts) rather
        # than silently trusting the binding: the run cannot become canonical.
        unresolved.append("environment.browser.measurement")
    elif browser["name"]!=browser_identity["name"] or browser["version"]!=browser_identity["version"]: raise ParityError("binding browser identity differs from locally measured executable")
    if not isinstance(attestation,dict) or set(attestation)!={"path","sha256"}: raise ParityError("binding requires a contained hashed environment attestation")
    relative,actual=_bound_repo_file(attestation,"environment_attestation"); sidecar=load(ROOT/relative)
    required={"schema_version","collector","collected_at","attestor_identity","implementation_identity","facts"}
    collector_path=Path("scripts/poured-parity/environment-collector.py")
    if not isinstance(sidecar,dict) or set(sidecar)!=required or sidecar.get("schema_version")!=1 or not iso_timestamp(sidecar.get("collected_at")) or sidecar.get("collector")!={"path":str(collector_path),"sha256":sha256(ROOT/collector_path)}: raise ParityError("environment attestation schema or collector identity mismatch")
    facts=sidecar.get("facts"); projected={key:environment[key] for key in ("target","system","display","preferences","locale","browser","window","capture","bundle")}
    if facts!=projected: raise ParityError("environment attestation facts differ from binding claims")
    authorized_attestors=_authorized("environment-attestor"); authorized_implementers=_authorized("implementation-principal")
    attestor=sidecar.get("attestor_identity"); implementation=sidecar.get("implementation_identity")
    if not isinstance(attestor,str) or attestor not in authorized_attestors: unresolved.append("environment_attestation.authority")
    if not isinstance(implementation,str) or implementation not in authorized_implementers: implementation=None; unresolved.append("implementation_identity")
    evidence={"measured":{"git":local_git,"system":measured_system,"browser":browser_identity,"runtime":_runtime_identity()},"attested":{"sha256":actual,"collector":sidecar["collector"],"attestor_identity":attestor},"unresolved":sorted(unresolved)}
    return environment,evidence,implementation


def _bound_repo_file(record: Any, label: str) -> tuple[str,str]:
    if not isinstance(record,dict) or set(record)!={"path","sha256"} or not isinstance(record["path"],str) or Path(record["path"]).is_absolute():
        raise ParityError(f"binding {label} requires a repository-relative path/hash")
    path=contained_path(ROOT,record["path"],require_file=True)
    actual=sha256(path)
    if record["sha256"]!=actual: raise ParityError(f"binding {label} hash mismatch")
    return record["path"],actual


def _trusted_original(path: Path, label: str) -> Path:
    resolved=contained_path(ROOT,path,require_file=True)
    if resolved.is_relative_to(ARTIFACTS.resolve()): raise ParityError(f"{label} cannot use mutable artifacts/poured-parity storage")
    return resolved


def fingerprint(binding_input: Path | None = None) -> dict[str, Any]:
    commit = git("rev-parse", "HEAD")
    dirty = bool(git("status", "--porcelain"))
    tracked = [ROOT / value for value in git("ls-files").splitlines()]
    manifest_names = {
        "authority.json":"reference", "scenarios-v1.json":"scenarios",
        "derived-fixtures-v1.json":"fixtures", "behavior-v1.json":"behavior",
        "adaptations-v1.json":"adaptations", "measurements-v1.json":"measurements",
        "mask-policy-v1.json":"masks", "calibration-v1.json":"calibration",
        "motion-authority-v1.json":"motion_authority",
        "capture-triggers-v1.json":"capture",
        "applicability-v1.json":"applicability", "principals-v1.json":"principals",
        "conflict-dispositions-v1.json":"conflict_dispositions",
    }
    bindings = {binding: sha256(VALIDATION / filename) for filename, binding in manifest_names.items()}
    bindings["scenarios"] = tree_hash([VALIDATION / "scenarios-v1.json", VALIDATION / "reference-identities-v1.json"])
    bindings["calibration"] = tree_hash([VALIDATION/"calibration-v1.json",VALIDATION/"calibration-bundle-authority-v1.json"])
    bindings["gate0c_schemas"] = tree_hash([VALIDATION/"baseline-matrix-schema-v1.json",VALIDATION/"baseline-evidence-sidecar-schema-v1.json",VALIDATION/"metric-report-schema-v1.json"])
    bindings["dependencies"] = tree_hash([VALIDATION/"requirements-v1.txt",VALIDATION/"runtime-v1.json"])
    for key in REQUIRED_BINDINGS:
        bindings.setdefault(key, None)
    display = {
        "stable_identity": None, "logical_size": None, "native_size": None,
        "scale": None, "profile": None, "refresh_hz": None,
    }
    environment = {
        "git": {"commit": commit, "dirty": dirty, "source_tree_hash": tree_hash(tracked)},
        "target": {"name": "OpenIslandApp", "executable": None, "executable_sha256": None, "build_configuration": None, "macho_uuid": None, "app_version": None, "build_version": None},
        "system": {"macos": platform.mac_ver()[0] or None, "hardware": platform.machine() or None, "model": _command_value(["sysctl", "-n", "hw.model"]), "gpu": None},
        "display": display,
        "preferences": {"appearance": None, "accent": None, "reduce_motion": None, "reduce_transparency": None, "increase_contrast": None, "text_size": None},
        "locale": {"locale": os.environ.get("LANG"), "timezone": os.environ.get("TZ"), "hour_cycle": None},
        "browser": {"name": None, "version": None, "zoom": None, "dpr": None, "viewport": None, "flags": None},
        "window": {"bounds": None, "crop": None, "backdrop_path": None, "backdrop_sha256": None},
        "capture": {"format": "png", "encoding": None, "api": None, "helper_path": None, "helper_sha256": None},
        "bundle": {"identifier": None, "signing_identity": None, "team_identifier": None},
    }
    implementation_identity: str | None = None; environment_evidence={"measured":{"git":environment["git"],"system":{"macos":environment["system"]["macos"],"hardware":environment["system"]["hardware"]},"browser":_browser_identity(),"runtime":_runtime_identity()},"attested":None,"unresolved":["environment_attestation","implementation_identity"]}
    if binding_input is not None:
        if binding_input.is_absolute(): raise ParityError("binding input must be repository-relative")
        binding_input=_trusted_original(binding_input,"binding input")
        supplied = load(binding_input)
        if not isinstance(supplied,dict) or set(supplied)!={"schema_version","native_commit","source_tree_hash","implementation_identity","environment","environment_attestation","bindings"} or supplied.get("schema_version") != 1 or supplied.get("native_commit") != commit or supplied.get("source_tree_hash") != environment["git"]["source_tree_hash"]:
            raise ParityError("binding input is stale relative to source identity")
        supplied_environment,environment_evidence,implementation_identity = _validate_environment(supplied.get("environment"),environment["git"],supplied.get("environment_attestation"))
        supplied_bindings = supplied.get("bindings")
        if supplied.get("implementation_identity") != load(ROOT/supplied["environment_attestation"]["path"]).get("implementation_identity"): raise ParityError("implementation identity differs from attestation")
        if not isinstance(supplied_bindings,dict) or set(supplied_bindings)!={"driver","capture","fixtures"}:
            raise ParityError("binding input environment/bindings differ from v1 contract")
        environment = supplied_environment
        for key in ("driver", "capture", "fixtures"):
            _,bindings[key]=_bound_repo_file(supplied_bindings.get(key),key)
        file_fields = [
            (environment["target"], "executable", "executable_sha256"),
            (environment["window"], "backdrop_path", "backdrop_sha256"),
            (environment["capture"], "helper_path", "helper_sha256"),
        ]
        for container, path_key, hash_key in file_fields:
            relative,actual=_bound_repo_file({"path":container.get(path_key),"sha256":container.get(hash_key)},path_key)
            container[path_key]=relative; container[hash_key]=actual
    unresolved: list[str] = []
    def walk(value: Any, prefix: str) -> None:
        if value is None:
            unresolved.append(prefix)
        elif isinstance(value, dict):
            for key, child in value.items():
                walk(child, f"{prefix}.{key}" if prefix else key)
    walk(environment, "environment")
    for key, value in bindings.items():
        if value is None:
            unresolved.append(f"bindings.{key}")
    unresolved.extend(environment_evidence["unresolved"])
    if binding_input is None: unresolved.append("binding_contract.original_authority")
    unresolved=sorted(set(unresolved))
    return {"schema_version": 1, "created_at": now(), "native_commit": commit, "dirty": dirty, "source_tree_hash": environment["git"]["source_tree_hash"], "bindings": bindings, "environment": environment, "environment_evidence":environment_evidence,"runtime":_runtime_identity(), "implementation_identity": implementation_identity, "unresolved_fields": unresolved, "canonical_ready": not dirty and not unresolved}


def init_run(run_id: str, binding_input: Path | None = None) -> Path:
    fp = fingerprint(binding_input)
    root = safe_run_root(fp["native_commit"], run_id)
    if root.exists():
        raise ParityError(f"run already exists: {root}")
    directories = load(VALIDATION / "artifact-schema-v1.json")["required_directories"]
    for name in directories:
        (root / name).mkdir(parents=True, exist_ok=True)
    binding_contract=None
    if binding_input is not None:
        source=_trusted_original(binding_input,"binding input")
        stored=root/"binding-input.json"; shutil.copy2(source,stored)
        supplied=load(source); attestation=_trusted_original(Path(supplied["environment_attestation"]["path"]),"environment attestation"); stored_attestation=root/"environment-attestation.json"; shutil.copy2(attestation,stored_attestation)
        genesis={"schema_version":1,"created_at":now(),"binding_input_original_path":str(source.relative_to(ROOT)),"binding_input_sha256":sha256(source),"original_attestation_path":str(attestation.relative_to(ROOT)),"original_attestation_sha256":sha256(attestation),"stored_binding_path":str(stored.relative_to(root)),"stored_binding_sha256":sha256(stored),"stored_attestation_path":str(stored_attestation.relative_to(root)),"stored_attestation_sha256":sha256(stored_attestation),"collector_sha256":sha256(ROOT/"scripts/poured-parity/environment-collector.py")}
        write(root/"run-genesis.json",genesis)
        binding_contract={"genesis_path":"run-genesis.json","genesis_sha256":sha256(root/"run-genesis.json"),"schema_version":1}
    manifest = {**fp, "run_id": run_id, "artifact_root": str(root.relative_to(ROOT)),"binding_contract":binding_contract}
    write(root / "manifest.json", manifest)
    shutil.copy2(VALIDATION / "ledger-v1.json", root / "ledger.json")
    index_run(root)
    return root


def validate_run_manifest(root: Path) -> dict[str,Any]:
    manifest=load(root/"manifest.json")
    required=set(load(VALIDATION/"run-schema-v1.json")["required"])
    if not isinstance(manifest,dict) or set(manifest)!=required: raise ParityError("run manifest fields differ from v1 schema")
    if manifest.get("schema_version")!=1 or not all(isinstance(manifest.get(x),str) and manifest[x] for x in ("run_id","native_commit","source_tree_hash","artifact_root","created_at")) or not iso_timestamp(manifest["created_at"]) or type(manifest.get("dirty")) is not bool or type(manifest.get("canonical_ready")) is not bool or not isinstance(manifest.get("bindings"),dict) or not isinstance(manifest.get("environment"),dict) or manifest.get("implementation_identity") is not None and not isinstance(manifest.get("implementation_identity"),str) or not isinstance(manifest.get("unresolved_fields"),list) or not all(isinstance(x,str) for x in manifest["unresolved_fields"]): raise ParityError("run manifest contains invalid typed fields")
    if manifest["canonical_ready"] != (not manifest["dirty"] and not manifest["unresolved_fields"]): raise ParityError("run canonical readiness contradicts unresolved or dirty state")
    contract=manifest.get("binding_contract")
    if contract is None and manifest["canonical_ready"]: raise ParityError("canonical run lacks trustworthy original binding authority")
    if contract is not None:
        if not isinstance(contract,dict) or set(contract)!={"genesis_path","genesis_sha256","schema_version"} or contract["schema_version"]!=1: raise ParityError("run binding contract schema mismatch")
        genesis_path=contained_path(root,contract["genesis_path"],require_file=True)
        if sha256(genesis_path)!=contract["genesis_sha256"]: raise ParityError("run genesis identity mismatch")
        genesis=load(genesis_path); required_genesis={"schema_version","created_at","binding_input_original_path","binding_input_sha256","original_attestation_path","original_attestation_sha256","stored_binding_path","stored_binding_sha256","stored_attestation_path","stored_attestation_sha256","collector_sha256"}
        if not isinstance(genesis,dict) or set(genesis)!=required_genesis or genesis.get("schema_version")!=1 or genesis.get("collector_sha256")!=sha256(ROOT/"scripts/poured-parity/environment-collector.py"): raise ParityError("run genesis schema/collector mismatch")
        original=_trusted_original(Path(genesis["binding_input_original_path"]),"original binding input"); original_attestation=_trusted_original(Path(genesis["original_attestation_path"]),"original environment attestation")
        stored=contained_path(root,genesis["stored_binding_path"],require_file=True); stored_attestation=contained_path(root,genesis["stored_attestation_path"],require_file=True)
        supplied=load(original)
        if supplied.get("environment_attestation")!={"path":genesis["original_attestation_path"],"sha256":genesis["original_attestation_sha256"]}: raise ParityError("original binding no longer names genesis attestation")
        if sha256(original)!=genesis["binding_input_sha256"] or sha256(stored)!=genesis["stored_binding_sha256"] or genesis["stored_binding_sha256"]!=genesis["binding_input_sha256"]: raise ParityError("stored run binding differs from trustworthy original")
        if sha256(original_attestation)!=genesis["original_attestation_sha256"] or sha256(stored_attestation)!=genesis["stored_attestation_sha256"] or genesis["stored_attestation_sha256"]!=genesis["original_attestation_sha256"]: raise ParityError("stored run attestation differs from trustworthy original")
    return manifest


def _evidence_set_digest(entries: list[dict[str, Any]]) -> str:
    value = hashlib.sha256()
    for entry in entries:
        if entry["path"] == "review-packet.json":
            continue
        value.update(entry["path"].encode()); value.update(b"\0"); value.update(entry["sha256"].encode()); value.update(b"\0"); value.update(str(entry["bytes"]).encode()); value.update(b"\n")
    return value.hexdigest()


def _source_evidence_digest(entries: list[dict[str, Any]]) -> str:
    source=[]
    for entry in entries:
        path=entry["path"]
        parts=Path(path).parts
        generated_report=len(parts)>1 and parts[0] in {"comparisons","motion","interaction","accessibility","regression"} and Path(path).name in {"report.json","metrics.json","motion.json","static-spec.json"}
        if path in SOURCE_DERIVED_PATHS or (parts and parts[0]=="metrics") or generated_report:
            continue
        source.append(entry)
    return _evidence_set_digest(source)


def _validate_index(value: Any) -> dict[str,Any]:
    if not isinstance(value,dict) or set(value)!={"schema_version","generated_at","sealed_for_review","source_evidence_sha256","evidence_set_sha256","files"} or value.get("schema_version")!=1 or not iso_timestamp(value.get("generated_at")) or type(value.get("sealed_for_review")) is not bool or not isinstance(value.get("files"),list): raise ParityError("evidence index schema mismatch")
    seen=set()
    for row in value["files"]:
        if not isinstance(row,dict) or set(row)!={"path","sha256","bytes"} or not isinstance(row["path"],str) or Path(row["path"]).is_absolute() or any(part in {"",".",".."} for part in Path(row["path"]).parts) or not isinstance(row["sha256"],str) or len(row["sha256"])!=64 or any(x not in "0123456789abcdef" for x in row["sha256"]) or type(row["bytes"]) is not int or row["bytes"]<0: raise ParityError("evidence index row schema mismatch")
        if row["path"] in seen: raise ParityError("duplicate evidence index record")
        seen.add(row["path"])
    if not isinstance(value["evidence_set_sha256"],str) or len(value["evidence_set_sha256"])!=64 or value["evidence_set_sha256"]!=_evidence_set_digest(value["files"]): raise ParityError("evidence index digest mismatch")
    if not isinstance(value["source_evidence_sha256"],str) or len(value["source_evidence_sha256"])!=64 or value["source_evidence_sha256"]!=_source_evidence_digest(value["files"]): raise ParityError("source evidence index digest mismatch")
    return value


def index_run(root: Path) -> dict[str, Any]:
    root = validate_run_root(root, ARTIFACTS)
    validate_run_manifest(root)
    existing=load(root/"evidence-index.json") if (root/"evidence-index.json").exists() else None
    if (root / "review-packet.json").exists() or (existing and _validate_index(existing)["sealed_for_review"]):
        raise ParityError("review-bound evidence cannot be reindexed")
    entries = []
    for path in iter_files(root, {"evidence-index.json"}):
        if path.is_file():
            entries.append({"path": str(path.relative_to(root)), "sha256": sha256(path), "bytes": path.stat().st_size})
    index = {"schema_version": 1, "generated_at": now(), "sealed_for_review": False, "source_evidence_sha256":_source_evidence_digest(entries), "evidence_set_sha256": _evidence_set_digest(entries), "files": entries}
    write(root / "evidence-index.json", index)
    return index


def _seal_index_for_review(root: Path) -> dict[str,Any]:
    if not (root/"review-packet.json").is_file(): raise ParityError("review packet must exist before the one-way seal")
    current=_validate_index(load(root/"evidence-index.json"))
    if current["sealed_for_review"]: raise ParityError("review evidence is already sealed")
    entries=[]
    for path in iter_files(root,{"evidence-index.json"}): entries.append({"path":str(path.relative_to(root)),"sha256":sha256(path),"bytes":path.stat().st_size})
    packet=load(root/"review-packet.json"); final_evidence=_evidence_set_digest(entries); final_source=_source_evidence_digest(entries)
    if packet.get("bound_evidence_set_sha256")!=final_evidence or current["source_evidence_sha256"]!=final_source: raise ParityError("review packet cannot seal a changed evidence/source set")
    sealed={"schema_version":1,"generated_at":now(),"sealed_for_review":True,"source_evidence_sha256":final_source,"evidence_set_sha256":final_evidence,"files":entries}
    write(root/"evidence-index.json",sealed); return sealed


def verify_freshness(root: Path) -> dict[str, Any]:
    root = validate_run_root(root, ARTIFACTS)
    manifest = validate_run_manifest(root)
    if root.resolve() != safe_run_root(manifest["native_commit"], manifest["run_id"]).resolve():
        raise ParityError("run directory does not match content-addressed identity")
    contract=manifest.get("binding_contract"); binding_path=None
    if contract:
        genesis=load(contained_path(root,contract["genesis_path"],require_file=True)); binding_path=Path(genesis["binding_input_original_path"])
    current = fingerprint(binding_path)
    for key in ("native_commit", "dirty", "source_tree_hash", "bindings","environment","environment_evidence","runtime","implementation_identity","unresolved_fields","canonical_ready"):
        if manifest.get(key) != current.get(key):
            raise ParityError(f"stale evidence: {key} mismatch")
    index_value = _validate_index(load(root / "evidence-index.json"))
    rows = index_value["files"]
    indexed = {x["path"]: x for x in rows}
    actual = {str(path.relative_to(root)): path for path in iter_files(root, {"evidence-index.json"})}
    if set(indexed) != set(actual):
        raise ParityError("stale evidence: artifact set mismatch")
    for name, path in actual.items():
        if indexed[name].get("sha256") != sha256(path) or indexed[name].get("bytes") != path.stat().st_size:
            raise ParityError(f"stale evidence: artifact hash mismatch for {name}")
    if index_value.get("evidence_set_sha256") != _evidence_set_digest(rows):
        raise ParityError("stale evidence: evidence-set digest mismatch")
    if index_value.get("source_evidence_sha256") != _source_evidence_digest(rows):
        raise ParityError("stale evidence: source-evidence digest mismatch")
    if (root / "review-packet.json").exists():
        packet = load(root / "review-packet.json")
        if not index_value.get("sealed_for_review") or packet.get("bound_evidence_set_sha256") != index_value["evidence_set_sha256"]:
            raise ParityError("review packet is not sealed to the evidence set")
    return {"fresh": True, "files": len(actual)}


def reference_plan() -> dict[str, Any]:
    verified = verify_manifests()
    source_hash = load(VALIDATION / "authority.json")["reference"]["sha256"]
    rows = []
    for row in load(VALIDATION / "scenarios-v1.json")["scenarios"]:
        if row["class"] in DIRECT_CLASSES:
            rows.append({"scenario": row["id"], "class": row["class"], "selector": row["anchor"]["selector"], "lines": row["anchor"]["lines"], "source_sha256": source_hash, "injection": ["selection", "clock", "capture-metadata"], "authoritative": False})
    return {"schema_version": 1, "source_sha256": source_hash, "records": rows, "scenario_count": verified["scenario_count"], "note": "plan isolates existing DOM only; it invents no UI"}


def native_plan() -> dict[str, Any]:
    return {"schema_version": 1, "theme": "poured", "records": [{"scenario": row["id"], "mapping": row["native"]["mapping"], "status": row["native"]["status"], "blocked_reason": row["blocked_reason"]} for row in load(VALIDATION / "scenarios-v1.json")["scenarios"]]}


def analyze_calibration(path: Path) -> dict[str, Any]:
    root,_=artifact_run_for(path,require_file=True)
    authority=load(VALIDATION/"calibration-v1.json"); authority["_path"]=str(VALIDATION/"calibration-v1.json")
    return _raster().analyze_calibration(path,authority,_runtime_identity(),validate_run_manifest(root))


def freeze_calibration(analysis: Path, output: Path, masks: Path, aa_band: int, thresholds: Path, approval_path: Path) -> dict[str, Any]:
    authority=load(VALIDATION/"calibration-v1.json")
    if authority.get("status")!="approved" or authority.get("approval",{}).get("status")!="approved" or authority.get("aa_band")!=aa_band: raise ParityError("calibration configuration authority is pending or does not authorize this freeze")
    authority["_path"]=str(VALIDATION/"calibration-v1.json")
    roots={artifact_run_for(path,require_file=True)[0] for path in (analysis,masks,approval_path)}
    output_root,_=artifact_run_for(output)
    if len(roots)!=1 or output_root not in roots: raise ParityError("calibration analysis, masks, approval, and output must share one canonical run")
    verify_masks(masks)
    threshold_value=load(thresholds)
    if thresholds.resolve()!= (VALIDATION/"measurements-v1.json").resolve() or not isinstance(threshold_value,dict) or set(threshold_value)!={"schema_version","id","provisional_screening_only","targets","hard_failures"}: raise ParityError("calibration thresholds must be the committed exact v1 schema")
    approval = load(approval_path)
    root=next(iter(roots)); validate_provenance(approval, root=root,
        allowed_dispositions={"PASS"}, required_role="independent-reviewer", authorized_identities=_authorized("independent-reviewer"))
    manifest=validate_run_manifest(root)
    frozen=_raster().freeze_calibration(analysis, output, masks, aa_band, thresholds, approval,authority,_runtime_identity(),manifest)
    source=contained_path(analysis.parent,frozen["input_manifest"],require_file=True); manifest=validate_run_manifest(root)
    frozen["analysis_path"]=str(analysis.relative_to(root)); frozen["input_manifest"]=str(source.relative_to(root)); frozen["environment_sha256"]=hashlib.sha256(json.dumps(manifest["environment"],sort_keys=True,separators=(",",":")).encode()).hexdigest(); frozen["bindings_sha256"]=hashlib.sha256(json.dumps(manifest["bindings"],sort_keys=True,separators=(",",":")).encode()).hexdigest()
    write(output,frozen); return frozen


def verify_masks(manifest_path: Path) -> dict[str, Any]:
    root, _ = artifact_run_for(manifest_path, require_file=True)
    value = load(manifest_path)
    reconstruction = contained_path(root,value.get("reconstruction_input", ""),require_file=True)
    reconstruction_root, _ = artifact_run_for(reconstruction, require_file=True)
    if reconstruction_root != root: raise ParityError("mask reconstruction escapes its canonical run")
    required = set(load(VALIDATION / "mask-policy-v1.json")["families"])
    empty=set(load(VALIDATION/"mask-policy-v1.json")["empty_allowed_families"])
    allowed={(x["scenario"],x["profile"],x["variant"],role) for x in _expanded_applicability() for role in x["mask_roles"]}
    return _raster().verify_masks(manifest_path, required, empty, allowed, root,validate_run_manifest(root))


def generate_masks(annotation_path: Path, output: Path) -> dict[str, Any]:
    annotation_root, _ = artifact_run_for(annotation_path, require_file=True)
    output_root, _ = artifact_run_for(output / "placeholder")
    if annotation_root != output_root: raise ParityError("mask reconstruction and output must share one canonical run")
    required = set(load(VALIDATION / "mask-policy-v1.json")["families"])
    empty=set(load(VALIDATION/"mask-policy-v1.json")["empty_allowed_families"])
    allowed={(x["scenario"],x["profile"],x["variant"],role) for x in _expanded_applicability() for role in x["mask_roles"]}
    scopes=[tuple(x.get(k) for k in ("scenario","profile","variant","capture_role")) for x in load(annotation_path).get("scopes",[]) if isinstance(x,dict)]
    if len(scopes)!=len(set(scopes)) or set(scopes)!=allowed: raise ParityError("mask annotations must exactly equal complete applicable role scopes")
    return _raster().generate_masks(annotation_path, output, required, empty, annotation_root,validate_run_manifest(annotation_root))


def _json_digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":")).encode()).hexdigest()


def _capture_sidecar(root: Path, record: Any, role: str, context: dict[str,Any], index: dict[str,dict[str,Any]]) -> tuple[dict[str,Any],Path]:
    if not isinstance(record,dict) or set(record)!={"path","sha256"}: raise ParityError("capture sidecar binding schema mismatch")
    path=contained_path(root,record["path"],require_file=True)
    if sha256(path)!=record["sha256"] or record["path"] not in index or index[record["path"]]["sha256"]!=record["sha256"]: raise ParityError("capture sidecar is unindexed or hash-mismatched")
    value=load(path); required={"schema_version","scenario","profile","variant","authority_class","capture_role","disposition","image","environment_sha256","bindings_sha256","source_identity","anchors","text","landmarks"}
    if not isinstance(value,dict) or set(value)!=required or value.get("schema_version")!=1 or any(value.get(k)!=context.get(k) for k in ("scenario","profile","variant","authority_class")) or value.get("capture_role")!=role or value.get("disposition")!="exact": raise ParityError("capture sidecar schema/context/role/disposition mismatch")
    scenarios={x["id"]:x for x in load(VALIDATION/"scenarios-v1.json")["scenarios"]}
    if value["authority_class"] not in DIRECT_CLASSES or scenarios.get(value["scenario"],{}).get("class")!=value["authority_class"]: raise ParityError("non-rendered class cannot enter direct static comparison")
    manifest=validate_run_manifest(root)
    if value["environment_sha256"]!=_json_digest(manifest["environment"]) or value["bindings_sha256"]!=_json_digest(manifest["bindings"]): raise ParityError("capture sidecar environment/binding identity mismatch")
    image=value.get("image")
    if not isinstance(image,dict) or set(image)!={"path","sha256","dimensions"}: raise ParityError("capture sidecar image schema mismatch")
    image_path=contained_path(root,image["path"],require_file=True)
    if sha256(image_path)!=image["sha256"] or image["path"] not in index or index[image["path"]]["sha256"]!=image["sha256"] or not isinstance(image["dimensions"],list) or len(image["dimensions"])!=2 or not all(type(x) is int and x>0 for x in image["dimensions"]): raise ParityError("capture image is unindexed, mismatched, or dimensionless")
    source=value.get("source_identity")
    if role=="reference":
        if source!={"source_sha256":sha256(ROOT/load(VALIDATION/"authority.json")["reference"]["path"])}: raise ParityError("reference sidecar source identity mismatch")
    elif not isinstance(source,dict) or set(source)!={"executable_sha256","fixture_sha256"} or source["executable_sha256"]!=manifest["environment"].get("target",{}).get("executable_sha256") or source["fixture_sha256"]!=manifest["bindings"].get("fixtures"): raise ParityError("native sidecar executable/fixture identity mismatch")
    anchors=value.get("anchors")
    if not isinstance(anchors,dict) or len(anchors)<2 or any(not isinstance(name,str) or not name or not isinstance(point,list) or len(point)!=2 or not all(_finite_number(x) for x in point) for name,point in anchors.items()): raise ParityError("capture registration anchors are invalid")
    texts=value.get("text")
    if not isinstance(texts,list) or not texts: raise ParityError("capture text geometry is empty")
    for text_record in texts:
        if not isinstance(text_record,dict) or set(text_record)!={"name","copy","line_count","bounds","baselines","wrapping"} or not all(isinstance(text_record.get(x),str) and text_record[x] for x in ("name","copy","wrapping")) or type(text_record.get("line_count")) is not int or text_record["line_count"]<=0 or not isinstance(text_record.get("bounds"),list) or len(text_record["bounds"])!=4 or not all(_finite_number(x) for x in text_record["bounds"]) or not isinstance(text_record.get("baselines"),list) or len(text_record["baselines"])!=text_record["line_count"] or not all(_finite_number(x) for x in text_record["baselines"]): raise ParityError("capture text geometry schema mismatch")
    landmarks=value.get("landmarks")
    if not isinstance(landmarks,dict) or not landmarks or any(not isinstance(name,str) or not name or not isinstance(point,list) or len(point)!=2 or not all(_finite_number(x) for x in point) for name,point in landmarks.items()): raise ParityError("capture landmarks are invalid")
    return value,image_path


def compare_static(output: Path, spec: Path) -> dict[str, Any]:
    roots = {artifact_run_for(path, require_file=True)[0] for path in (spec,)}
    output_root, _ = artifact_run_for(output / "placeholder")
    if len(roots) != 1 or output_root not in roots: raise ParityError("static inputs and output must share one canonical run")
    root=next(iter(roots)); value=load(spec); required={"schema_version","context","reference_sidecar","native_sidecar","mask_manifest","calibration_bundle","thresholds_sha256","ledger_sha256","applicability_sha256","source_evidence_sha256"}
    if not isinstance(value,dict) or set(value)!=required or value.get("schema_version")!=1: raise ParityError("static comparison spec schema mismatch")
    context=value.get("context",{}); scenarios={x["id"]:x for x in load(VALIDATION/"scenarios-v1.json")["scenarios"]}
    if not isinstance(context,dict) or set(context)!={"scenario","profile","variant","authority_class"}: raise ParityError("static comparison context schema mismatch")
    if context.get("scenario") not in scenarios or context.get("authority_class")!=scenarios[context["scenario"]]["class"]: raise ParityError("static scenario/class binding is invalid")
    if context["authority_class"] not in DIRECT_CLASSES: raise ParityError("non-rendered class cannot enter direct static comparison")
    applicable={(x["scenario"],x["profile"],x["variant"]) for x in _expanded_applicability()}
    if (context.get("scenario"),context.get("profile"),context.get("variant")) not in applicable: raise ParityError("static scenario/profile/variant is not applicable")
    index_value=_validate_index(load(root/"evidence-index.json")); index={x["path"]:x for x in index_value["files"]}
    if value["source_evidence_sha256"]!=index_value["source_evidence_sha256"] or value["ledger_sha256"]!=sha256(root/"ledger.json") or value["applicability_sha256"]!=sha256(VALIDATION/"applicability-v1.json") or value["thresholds_sha256"]!=sha256(VALIDATION/"measurements-v1.json"): raise ParityError("static current authority/source-evidence/ledger/threshold binding mismatch")
    reference,reference_image=_capture_sidecar(root,value["reference_sidecar"],"reference",context,index); native,native_image=_capture_sidecar(root,value["native_sidecar"],"native",context,index)
    if set(reference["anchors"])!=set(native["anchors"]): raise ParityError("reference/native anchor names differ")
    calibration=load(VALIDATION/"calibration-v1.json"); bundle_authority=load(VALIDATION/"calibration-bundle-authority-v1.json")
    if calibration.get("status")!="approved" or bundle_authority.get("status")!="approved" or not bundle_authority.get("bundle_path") or not bundle_authority.get("bundle_sha256") or bundle_authority.get("bundle_path")!=value["calibration_bundle"].get("path"): raise ParityError("static comparison calibration authority is pending or mismatched")
    bundle=contained_path(root,value["calibration_bundle"]["path"],require_file=True)
    if sha256(bundle)!=bundle_authority["bundle_sha256"] or value["calibration_bundle"].get("sha256")!=bundle_authority["bundle_sha256"]: raise ParityError("static calibration bundle hash mismatch")
    mask_record=value["mask_manifest"]
    if not isinstance(mask_record,dict) or set(mask_record)!={"path","sha256"}: raise ParityError("static mask manifest binding schema mismatch")
    mask_path=contained_path(root,mask_record["path"],require_file=True)
    if sha256(mask_path)!=mask_record["sha256"]: raise ParityError("static mask manifest hash mismatch")
    verify_masks(mask_path)
    raise ParityError("static comparison requires approved role-resolved mask-to-metric adapter; unavailable in pending foundation")


def _validated_motion_report(path: Path,root: Path,index: dict[str,Any]) -> dict[str,Any]:
    scenarios=load(VALIDATION/"scenarios-v1.json"); behavior=load(VALIDATION/"behavior-v1.json"); authority=load(VALIDATION/"motion-authority-v1.json"); calibration=load(VALIDATION/"calibration-v1.json"); value=load(path); bindings=value.get("bindings",{})
    expected={"scenarios_sha256":sha256(VALIDATION/"scenarios-v1.json"),"behavior_sha256":sha256(VALIDATION/"behavior-v1.json"),"motion_authority_sha256":sha256(VALIDATION/"motion-authority-v1.json"),"calibration_sha256":tree_hash([VALIDATION/"calibration-v1.json",VALIDATION/"calibration-bundle-authority-v1.json"]),"source_evidence_sha256":index["source_evidence_sha256"]}
    if bindings!=expected: raise ParityError("motion evidence binding hash mismatch")
    indexed={x["path"]:x for x in index["files"]}
    for label in ("capture_sidecar","manual_clock_attestation"):
        record=value.get(label)
        if not isinstance(record,dict) or set(record)!={"path","sha256"}: raise ParityError(f"motion {label} binding schema mismatch")
        bound=contained_path(root,record["path"],require_file=True)
        if sha256(bound)!=record["sha256"] or record["path"] not in indexed or indexed[record["path"]]["sha256"]!=record["sha256"]: raise ParityError(f"motion {label} is unindexed or hash-mismatched")
    if value.get("canonical_disposition")=="exact" and calibration.get("status")!="approved": raise ParityError("canonical motion requires approved frozen calibration authority")
    report=_raster().validate_motion(path,None,root,validate_run_manifest(root),scenarios,behavior,authority,calibration,load(root/value["capture_sidecar"]["path"]),load(root/value["manual_clock_attestation"]["path"]),indexed); report["runtime"]=_runtime_identity(); return report


def validate_motion(path: Path, output: Path) -> dict[str, Any]:
    root, _ = artifact_run_for(path, require_file=True)
    output_root, _ = artifact_run_for(output)
    if output_root != root: raise ParityError("motion input and output must share one canonical run")
    report=_validated_motion_report(path,root,_validate_index(load(root/"evidence-index.json"))); write(output,report); return report


def _unresolved_authority(run_root: Path | None = None) -> list[str]:
    conflicts=load(VALIDATION/"conflicts-v1.json").get("conflicts",[])
    ledger_path=run_root/"ledger.json" if run_root is not None and (run_root/"ledger.json").is_file() else VALIDATION/"ledger-v1.json"
    ledger={row.get("id"):row for row in load(ledger_path).get("items",[]) if isinstance(row,dict)}
    unresolved=[]
    for conflict in conflicts:
        if not isinstance(conflict,dict) or not isinstance(conflict.get("id"),str): raise ParityError("conflict authority record schema mismatch")
        item=ledger.get(conflict["id"])
        if conflict.get("status")!="resolved" or conflict.get("ruling") is None or conflict.get("authority") is None or not isinstance(item,dict) or item.get("status")!="passed": unresolved.append(conflict["id"])
    return sorted(unresolved)


def review_packet(run_root: Path, approval_path: Path | None = None) -> dict[str, Any]:
    if (run_root/"review-packet.json").exists(): raise ParityError("review packet already exists and cannot be renewed")
    verify_freshness(run_root)
    index = _validate_index(load(run_root / "evidence-index.json"))
    if index["sealed_for_review"]: raise ParityError("evidence index is already sealed")
    pre_review_index_hash = sha256(run_root / "evidence-index.json")
    baseline = {"status":"pending","disposition":None,"identity":None,"role":"independent-reviewer","recorded_at":None,"authority_artifact":None,"authority_sha256":None,"evidence_index_sha256":None}
    if approval_path is not None:
        baseline = load(approval_path)
        validate_provenance(baseline, root=run_root, allowed_dispositions={"PASS","FAIL","BLOCKED"},
            required_role="independent-reviewer", evidence_index_hash=pre_review_index_hash, authorized_identities=_authorized("independent-reviewer"))
    manifest=load(run_root/"manifest.json"); genesis_sha=manifest.get("binding_contract",{}).get("genesis_sha256") if manifest.get("binding_contract") else None
    packet = {"schema_version":1,"created_at":now(),"run":manifest["artifact_root"],"bound_evidence_set_sha256":index["evidence_set_sha256"],"pre_review_index_sha256":pre_review_index_hash,"calibration_sha256":sha256(VALIDATION/"calibration-v1.json"),"calibration_bundle_authority_sha256":sha256(VALIDATION/"calibration-bundle-authority-v1.json"),"applicability_sha256":sha256(VALIDATION/"applicability-v1.json"),"adaptations_sha256":sha256(VALIDATION/"adaptations-v1.json"),"conflicts_sha256":sha256(VALIDATION/"conflicts-v1.json"),"principals_sha256":sha256(VALIDATION/"principals-v1.json"),"motion_authority_sha256":sha256(VALIDATION/"motion-authority-v1.json"),"runtime_authority_sha256":sha256(VALIDATION/"runtime-v1.json"),"scenario_class_matrix":verify_manifests()["class_counts"],"unresolved_authority":_unresolved_authority(run_root),"mask_policy_sha256":sha256(VALIDATION/"mask-policy-v1.json"),"thresholds_sha256":sha256(VALIDATION/"measurements-v1.json"),"ledger_snapshot_sha256":sha256(run_root/"ledger.json"),"environment_sha256":_json_digest(manifest["environment"]),"bindings_sha256":_json_digest(manifest["bindings"]),"genesis_sha256":genesis_sha,"baseline_adequacy":baseline,"parity_claim":False}
    write(run_root/"review-packet.json",packet); _seal_index_for_review(run_root); return packet


def _validate_review_packet(run_root: Path, packet: Any, manifest: dict[str,Any], index: dict[str,Any]) -> dict[str,Any]:
    required={"schema_version","created_at","run","bound_evidence_set_sha256","pre_review_index_sha256","calibration_sha256","calibration_bundle_authority_sha256","applicability_sha256","adaptations_sha256","conflicts_sha256","principals_sha256","motion_authority_sha256","runtime_authority_sha256","scenario_class_matrix","unresolved_authority","mask_policy_sha256","thresholds_sha256","ledger_snapshot_sha256","environment_sha256","bindings_sha256","genesis_sha256","baseline_adequacy","parity_claim"}
    if not isinstance(packet,dict) or set(packet)!=required or packet.get("schema_version")!=1 or not iso_timestamp(packet.get("created_at")) or packet.get("parity_claim") is not False: raise ParityError("Gate 0C blocked: review packet schema/parity claim is invalid")
    expected={"run":manifest["artifact_root"],"bound_evidence_set_sha256":index["evidence_set_sha256"],"calibration_sha256":sha256(VALIDATION/"calibration-v1.json"),"calibration_bundle_authority_sha256":sha256(VALIDATION/"calibration-bundle-authority-v1.json"),"applicability_sha256":sha256(VALIDATION/"applicability-v1.json"),"adaptations_sha256":sha256(VALIDATION/"adaptations-v1.json"),"conflicts_sha256":sha256(VALIDATION/"conflicts-v1.json"),"principals_sha256":sha256(VALIDATION/"principals-v1.json"),"motion_authority_sha256":sha256(VALIDATION/"motion-authority-v1.json"),"runtime_authority_sha256":sha256(VALIDATION/"runtime-v1.json"),"scenario_class_matrix":verify_manifests()["class_counts"],"unresolved_authority":_unresolved_authority(run_root),"mask_policy_sha256":sha256(VALIDATION/"mask-policy-v1.json"),"thresholds_sha256":sha256(VALIDATION/"measurements-v1.json"),"ledger_snapshot_sha256":sha256(run_root/"ledger.json"),"environment_sha256":_json_digest(manifest["environment"]),"bindings_sha256":_json_digest(manifest["bindings"]),"genesis_sha256":manifest.get("binding_contract",{}).get("genesis_sha256") if manifest.get("binding_contract") else None}
    if any(packet.get(key)!=value for key,value in expected.items()) or not isinstance(packet.get("pre_review_index_sha256"),str) or len(packet["pre_review_index_sha256"])!=64: raise ParityError("Gate 0C blocked: review packet semantic bindings are stale or forged")
    validate_provenance(packet["baseline_adequacy"],root=run_root,allowed_dispositions={"PASS"},required_role="independent-reviewer",distinct_from=manifest.get("implementation_identity"),evidence_index_hash=packet["pre_review_index_sha256"],authorized_identities=_authorized("independent-reviewer"))
    return packet


def _applicability() -> dict[str,Any]:
    value=load(VALIDATION/"applicability-v1.json")
    required_top={"schema_version","id","status","profiles","variants","rules","variant_rules","approval","records"}
    expected_variant_rules={"visual_adaptations":["reduced-motion","reduced-transparency","increased-contrast","light-appearance","dark-appearance","supported-text-size"],"interaction_adaptations":["keyboard","voiceover"],"nonstandard_authority_class":"platform-adaptation","authority_family":"adaptation-authority","visual_native_family":"visual-a11y","interaction_native_family":"interaction-a11y"}
    if not isinstance(value,dict) or set(value)!=required_top or value.get("schema_version")!=1 or value.get("status") not in {"pending","approved"} or value.get("profiles")!=["notch-v1","top-bar-v1"] or value.get("variants")!=["standard",*load(VALIDATION/"adaptations-v1.json")["variants"]] or value.get("rules")!={"expansion":"scenario x profile x variant","canonical_disposition":"exact","diagnostic_satisfies_baseline":False} or value.get("variant_rules")!=expected_variant_rules or not isinstance(value.get("records"),list): raise ParityError("Gate 0C applicability schema mismatch")
    visual_rules=set(expected_variant_rules["visual_adaptations"]); interaction_rules=set(expected_variant_rules["interaction_adaptations"])
    if visual_rules&interaction_rules or visual_rules|interaction_rules!=set(load(VALIDATION/"adaptations-v1.json")["variants"]): raise ParityError("Gate 0C applicability variant rules do not classify every adaptation exactly once")
    scenarios={x["id"]:x for x in load(VALIDATION/"scenarios-v1.json")["scenarios"]}; ledger_ids={x["id"] for x in load(VALIDATION/"ledger-v1.json")["items"]}; report_families={"static","motion","geometry","light","text","interaction","accessibility"}; seen=set()
    required={"scenario","authority_class","evidence_roles","mask_roles","metric_families","ledger_ids"}
    for row in value["records"]:
        if not isinstance(row,dict) or set(row)!=required or row.get("scenario") not in scenarios or row.get("authority_class")!=scenarios[row["scenario"]]["class"] or not isinstance(row.get("evidence_roles"),list) or not isinstance(row.get("mask_roles"),list) or not isinstance(row.get("metric_families"),list) or not row["metric_families"] or not set(row["metric_families"])<=report_families or len(row["metric_families"])!=len(set(row["metric_families"])) or not isinstance(row.get("ledger_ids"),list) or not row["ledger_ids"] or not set(row["ledger_ids"])<=ledger_ids or len(row["ledger_ids"])!=len(set(row["ledger_ids"])): raise ParityError("Gate 0C applicability record schema mismatch")
        direct=scenarios[row["scenario"]]["class"] in DIRECT_CLASSES
        expected_roles=["reference","native"] if direct else ["authority","native"]
        expected_masks=(["reference","native"] if direct else ["native"]) if "static" in row["metric_families"] else []
        if row["evidence_roles"]!=expected_roles or row["mask_roles"]!=expected_masks: raise ParityError("Gate 0C applicability class-specific evidence rules mismatch")
        if row["scenario"] in seen: raise ParityError("Gate 0C applicability record is duplicated")
        seen.add(row["scenario"])
    if seen!=set(scenarios): raise ParityError("Gate 0C applicability must exhaustively cover all 39 scenarios")
    approval=value.get("approval")
    if not isinstance(approval,dict) or set(approval)!={"product_design_owner","independent_reviewer"}: raise ParityError("Gate 0C applicability approval schema mismatch")
    if value["status"]=="approved":
        owner=validate_provenance(approval["product_design_owner"],root=ROOT,allowed_dispositions={"ACCEPT"},required_role="product-design-owner",authorized_identities=_authorized("product-design-owner"))
        validate_provenance(approval["independent_reviewer"],root=ROOT,allowed_dispositions={"PASS"},required_role="independent-reviewer",distinct_from=owner["identity"],authorized_identities=_authorized("independent-reviewer"))
    elif approval!={"product_design_owner":None,"independent_reviewer":None}: raise ParityError("pending applicability cannot contain approval provenance")
    return value


def _expanded_from_value(value: dict[str,Any]) -> list[dict[str,Any]]:
    rules=value["variant_rules"]; expanded=[]
    for row in value["records"]:
        for profile in value["profiles"]:
            for variant in value["variants"]:
                item={**row,"profile":profile,"variant":variant}
                if variant=="standard":
                    family="motion" if row["metric_families"]==["motion"] else "visual"
                    item["evidence_families"]=[family if role in {"reference","native"} else ("behavior-authority" if family=="motion" else "derived-authority") for role in row["evidence_roles"]]
                else:
                    if variant not in rules["visual_adaptations"] and variant not in rules["interaction_adaptations"]: raise ParityError("Gate 0C blocked: applicability variant has no adaptation classification")
                    interaction=variant in rules["interaction_adaptations"]
                    item["authority_class"]=rules["nonstandard_authority_class"]
                    item["evidence_roles"]=["authority","native"]
                    item["evidence_families"]=[rules["authority_family"],rules["interaction_native_family"] if interaction else rules["visual_native_family"]]
                    item["mask_roles"]=[] if interaction or "static" not in row["metric_families"] else ["native"]
                    item["metric_families"]=["interaction","accessibility"] if interaction else [*row["metric_families"],"accessibility"]
                expanded.append(item)
    return expanded


def _expanded_applicability() -> list[dict[str,Any]]:
    return _expanded_from_value(_applicability())


def _adaptation_facts(manifest: dict[str,Any], variant: str) -> dict[str,Any]:
    preferences=json.loads(json.dumps(manifest.get("environment",{}).get("preferences",{})))
    overrides={"reduced-motion":("reduce_motion",True),"reduced-transparency":("reduce_transparency",True),"increased-contrast":("increase_contrast",True),"light-appearance":("appearance","light"),"dark-appearance":("appearance","dark"),"supported-text-size":("text_size","supported")}
    if variant!="standard" and variant not in overrides and variant not in {"keyboard","voiceover"}: raise ParityError("Gate 0C blocked: adaptation facts are undefined for this variant")
    if variant in overrides: preferences[overrides[variant][0]]=overrides[variant][1]
    return {"requested_variant":variant,"preferences":preferences,"interaction_mode":variant if variant in {"keyboard","voiceover"} else None}


def _baseline_sidecar(run_root: Path,row: dict[str,Any],evidence: dict[str,Any],family: str,indexed: dict[str,dict[str,Any]],manifest: dict[str,Any]) -> dict[str,Any]:
    sidecar_path=contained_path(run_root,evidence["sidecar_path"],require_file=True)
    try: value=load(sidecar_path)
    except ParityError as exc: raise ParityError("Gate 0C blocked: baseline evidence sidecar is not valid JSON") from exc
    schema=load(VALIDATION/"baseline-evidence-sidecar-schema-v1.json"); required=set(schema["required"])
    if not isinstance(value,dict) or set(value)!=required or value.get("schema_version")!=1 or any(value.get(key)!=row.get(key) for key in ("scenario","profile","variant","authority_class")) or value.get("role")!=evidence["role"] or value.get("family")!=family or value.get("disposition")!="exact" or not isinstance(value.get("capture_id"),str) or not value["capture_id"] or not iso_timestamp(value.get("captured_at")) or value.get("environment_sha256")!=_json_digest(manifest["environment"]) or value.get("bindings_sha256")!=_json_digest(manifest["bindings"]) or value.get("adaptation_facts")!=_adaptation_facts(manifest,row["variant"]): raise ParityError("Gate 0C blocked: baseline evidence sidecar semantic identity mismatch")
    artifact=value.get("artifact")
    if not isinstance(artifact,dict) or set(artifact)!=set(schema["artifact_required"]) or artifact!={"path":evidence["path"],"sha256":evidence["sha256"]}: raise ParityError("Gate 0C blocked: baseline sidecar artifact binding mismatch")
    source=value.get("source_identity"); role=evidence["role"]
    if role=="reference":
        reference=load(VALIDATION/"authority.json")["reference"]
        if row["variant"]!="standard" or row["authority_class"] not in DIRECT_CLASSES or source!={"html_sha256":reference["sha256"]}: raise ParityError("Gate 0C blocked: reference evidence lacks exact direct HTML authority")
    elif role=="native":
        expected={"executable_sha256":manifest.get("environment",{}).get("target",{}).get("executable_sha256"),"fixture_sha256":manifest.get("bindings",{}).get("fixtures")}
        if source!=expected: raise ParityError("Gate 0C blocked: native evidence executable/fixture identity mismatch")
    else:
        if row["authority_class"] in DIRECT_CLASSES or not isinstance(source,dict) or set(source)!={"authority_path","authority_sha256","provenance"}: raise ParityError("Gate 0C blocked: authority evidence is invalid for direct/default pixels")
        authority_path=contained_path(ROOT,source["authority_path"],require_file=True); authority_value=load(authority_path)
        if sha256(authority_path)!=source["authority_sha256"] or not isinstance(authority_value,dict) or authority_value.get("status")!="approved" or authority_value.get("acceptance_authority") is not True or (row["variant"]!="standard" and authority_path!=(VALIDATION/"adaptations-v1.json").resolve()): raise ParityError("Gate 0C blocked: authority evidence path/hash does not match approved applicable authority")
        validate_provenance(source["provenance"],root=ROOT,allowed_dispositions={"ACCEPT"},required_role="product-design-owner",authorized_identities=_authorized("product-design-owner"))
    return value


def _verify_baseline_candidate(matrix: dict[str, Any], run_root: Path | None, index_value: dict[str,Any] | None, applicability: dict[str,Any]) -> dict[str, Any]:
    if applicability["status"]!="approved": raise ParityError("Gate 0C blocked: applicability authority is pending")
    if run_root is None or index_value is None: raise ParityError("Gate 0C baseline validation requires canonical run and index")
    expanded=_expanded_from_value(applicability); expected={(x["scenario"],x["profile"],x["variant"]):x for x in expanded}
    records=matrix.get("records",[])
    contract=load(VALIDATION/"baseline-matrix-schema-v1.json")
    index_value=_validate_index(index_value)
    if not isinstance(matrix,dict) or set(matrix)!={"schema_version","applicability_sha256","ledger_sha256","source_evidence_sha256","records"} or matrix.get("schema_version")!=1 or matrix.get("applicability_sha256")!=sha256(VALIDATION/"applicability-v1.json") or matrix.get("ledger_sha256")!=sha256(run_root/"ledger.json") or matrix.get("source_evidence_sha256")!=index_value["source_evidence_sha256"]: raise ParityError("Gate 0C blocked: baseline matrix schema or bindings are invalid")
    required=set(contract["record_required"]); actual=set()
    evidence_required=set(contract["evidence_required"]); indexed={x["path"]:x for x in index_value["files"]}; ledger_ids={x["id"] for x in load(run_root/"ledger.json").get("items",[])}; manifest=validate_run_manifest(run_root); used_sidecars=set(); used_artifacts=set(); used_captures=set()
    for row in records:
        key=(row.get("scenario"),row.get("profile"),row.get("variant")); applicable=expected.get(key)
        if not isinstance(row,dict) or set(row)!=required or applicable is None or type(row.get("complete")) is not bool or not row["complete"] or row.get("ledger_ids")!=applicable["ledger_ids"] or not set(row["ledger_ids"])<=ledger_ids or not isinstance(row.get("evidence"),list) or row.get("source_evidence_sha256")!=matrix["source_evidence_sha256"] or row.get("authority_class")!=applicable["authority_class"]: raise ParityError("Gate 0C blocked: baseline record schema, ledger relevance, or effective authority is invalid")
        families=applicable["evidence_families"]
        if len(row["evidence"])!=len(families) or len(row["evidence"])!=len(applicable["evidence_roles"]): raise ParityError("Gate 0C blocked: baseline evidence count differs from applicable evidence families/roles")
        roles=[]
        for evidence,family in zip(row["evidence"],families,strict=True):
            if not isinstance(evidence,dict) or set(evidence)!=evidence_required or evidence.get("disposition")!="exact" or evidence.get("role") not in {"reference","native","authority"}: raise ParityError("Gate 0C blocked: baseline evidence schema/disposition is invalid")
            roles.append(evidence["role"])
            for path_key,hash_key in (("path","sha256"),("sidecar_path","sidecar_sha256")):
                path=contained_path(run_root,evidence[path_key],require_file=True)
                if sha256(path)!=evidence[hash_key] or evidence[path_key] not in indexed or indexed[evidence[path_key]]["sha256"]!=evidence[hash_key]: raise ParityError("Gate 0C blocked: baseline evidence is absent, out-of-run, unindexed, or hash-mismatched")
            sidecar=_baseline_sidecar(run_root,row,evidence,family,indexed,manifest)
            if evidence["sidecar_path"] in used_sidecars or evidence["path"] in used_artifacts or sidecar["capture_id"] in used_captures: raise ParityError("Gate 0C blocked: baseline sidecar/artifact/capture identity is reused")
            used_sidecars.add(evidence["sidecar_path"]); used_artifacts.add(evidence["path"]); used_captures.add(sidecar["capture_id"])
        if roles!=applicable["evidence_roles"] or (applicable["authority_class"] not in DIRECT_CLASSES and "reference" in roles): raise ParityError("Gate 0C blocked: baseline evidence roles violate class authority")
        actual.add(key)
    if len(records) != len(expected) or actual != set(expected):
        raise ParityError("Gate 0C blocked: baseline scenario/profile/adaptation matrix is incomplete or duplicated")
    return {"complete":True,"records":len(records)}


def verify_baseline_matrix(matrix: dict[str, Any], run_root: Path | None = None, index_value: dict[str,Any] | None = None, applicability: dict[str,Any] | None = None) -> dict[str, Any]:
    if applicability is not None: raise ParityError("Gate 0C blocked: caller-supplied applicability cannot replace committed authority")
    return _verify_baseline_candidate(matrix,run_root,index_value,_applicability())


def _verify_metric_candidates(metrics_root: Path, run_root: Path | None, index_value: dict[str,Any] | None, applicability: dict[str,Any]) -> dict[str, Any]:
    if run_root is None or index_value is None: raise ParityError("Gate 0C metric validation requires canonical run and index")
    index_value=_validate_index(index_value); metric_paths=list(metrics_root.glob("*.json")); indexed={x["path"]:x for x in index_value["files"]}; expanded=_expanded_from_value(applicability); required_keys={(x["scenario"],x["profile"],x["variant"],family) for x in expanded for family in x["metric_families"]}
    if len(metric_paths)!=len(required_keys): raise ParityError("Gate 0C blocked: per-applicability metric report collection is incomplete or extra")
    contract=load(VALIDATION/"metric-report-schema-v1.json"); metric_names={key:set(value) for key,value in contract["metrics_by_family"].items()}
    by_key={(x["scenario"],x["profile"],x["variant"]):x for x in expanded}; actual=set()
    for path in metric_paths:
        report=load(path)
        family=report.get("family"); required={"schema_version","family","scenario","profile","variant","authority_class","bindings","source_report","overall_screening_status","metrics"}; bindings_required={"ledger_sha256","source_evidence_sha256","applicability_sha256","calibration_sha256","mask_policy_sha256","thresholds_sha256"}
        if not isinstance(report,dict) or set(report)!=required or report.get("schema_version")!=1 or family not in metric_names or not isinstance(report.get("bindings"),dict) or set(report["bindings"])!=bindings_required or report["bindings"]!={"ledger_sha256":sha256(run_root/"ledger.json"),"source_evidence_sha256":index_value["source_evidence_sha256"],"applicability_sha256":sha256(VALIDATION/"applicability-v1.json"),"calibration_sha256":tree_hash([VALIDATION/"calibration-v1.json",VALIDATION/"calibration-bundle-authority-v1.json"]),"mask_policy_sha256":sha256(VALIDATION/"mask-policy-v1.json"),"thresholds_sha256":sha256(VALIDATION/"measurements-v1.json")} or set(report.get("metrics",{}))!=metric_names[family] or report.get("overall_screening_status") != "passed" or any(not isinstance(item,dict) or set(item)!={"status","value","unit"} or item.get("status") != "passed" or type(item.get("value")) not in {int,float,bool} or (type(item.get("value")) in {int,float} and not math.isfinite(item["value"])) or not isinstance(item.get("unit"),str) for item in report.get("metrics",{}).values()):
            raise ParityError(f"Gate 0C blocked: metric report is absent, unsupported, or failed: {path.name}")
        applicable=by_key.get((report["scenario"],report["profile"],report["variant"]))
        if applicable is None or report["authority_class"]!=applicable["authority_class"] or family not in applicable["metric_families"]: raise ParityError(f"Gate 0C blocked: metric report is not applicable: {path.name}")
        source=report.get("source_report")
        if not isinstance(source,dict) or set(source)!={"path","sha256"}: raise ParityError("Gate 0C blocked: metric source report binding is invalid")
        source_path=contained_path(run_root,source["path"],require_file=True)
        if sha256(source_path)!=source["sha256"] or source["path"] not in indexed or indexed[source["path"]]["sha256"]!=source["sha256"]: raise ParityError("Gate 0C blocked: metric source report is absent, unindexed, or forged")
        try: generated=load(source_path)
        except ParityError as exc: raise ParityError("Gate 0C blocked: metric source report is not recognized JSON") from exc
        context={"scenario":report["scenario"],"profile":report["profile"],"variant":report["variant"],"authority_class":report["authority_class"]}
        if family=="motion":
            if not isinstance(generated,dict) or generated.get("generator")!="poured-motion-v1" or any(generated.get(key)!=context[key] for key in context) or generated.get("disposition")!="exact" or generated.get("status")!="measured" or not isinstance(generated.get("source_manifest"),dict): raise ParityError("Gate 0C blocked: motion metric source context/status is unsupported or mismatched")
            manifest_path=contained_path(run_root,generated["source_manifest"].get("path",""),require_file=True)
            if sha256(manifest_path)!=generated["source_manifest"].get("sha256"): raise ParityError("Gate 0C blocked: motion source manifest binding mismatch")
            recomputed=_validated_motion_report(manifest_path,run_root,index_value)
            if generated!=recomputed: raise ParityError("Gate 0C blocked: motion generator report is stale or forged")
            expected_values={"timing_jitter":max(run["timing_jitter"] for run in generated["runs"]),"duplicates":sum(run["duplicates"] for run in generated["runs"]),"drops":sum(run["drops"] for run in generated["runs"])}
            if any(report["metrics"][name]["value"]!=value for name,value in expected_values.items()): raise ParityError("Gate 0C blocked: motion wrapper metric differs from generator report")
        elif family in {"static","geometry","light","text"}:
            if not isinstance(generated,dict) or generated.get("context")!=context or generated.get("overall_screening_status")!="passed": raise ParityError("Gate 0C blocked: raster metric source context/status is unsupported or mismatched")
            raise ParityError("Gate 0C blocked: approved role-resolved static mask-to-metric adapter is unavailable")
        else:
            raise ParityError(f"Gate 0C blocked: {family} generator is unsupported in the pending foundation")
        actual.add((report["scenario"],report["profile"],report["variant"],family))
    if actual!=required_keys: raise ParityError("Gate 0C blocked: metric report coverage differs from applicability")
    return {"complete":True,"reports":len(metric_paths)}


def verify_metric_reports(metrics_root: Path, run_root: Path | None = None, index_value: dict[str,Any] | None = None, applicability: dict[str,Any] | None = None) -> dict[str, Any]:
    if applicability is not None: raise ParityError("Gate 0C blocked: caller-supplied applicability cannot replace committed authority")
    return _verify_metric_candidates(metrics_root,run_root,index_value,_applicability())


def _verify_gate0b_candidate(candidate_root: Path | None) -> dict[str,Any]:
    if candidate_root is None: raise ParityError("Gate 0B requires a candidate run")
    candidate_root=validate_run_root(candidate_root,ARTIFACTS); verify_freshness(candidate_root); candidate=validate_run_manifest(candidate_root)
    calibration,bundle_authority=_calibration_authorities(require_approved=True)
    if not all(calibration.get(x) is not None for x in ("target_id","color_profile","registration_anchor_names","logical_to_device_scale","aa_band","mask_manifest","dependencies_sha256")) or calibration["dependencies_sha256"]!=tree_hash([VALIDATION/"requirements-v1.txt",VALIDATION/"runtime-v1.json"]): raise ParityError("Gate 0B blocked: committed calibration authority is incomplete")
    bundle=contained_path(ROOT,bundle_authority["bundle_path"],require_file=True)
    if sha256(bundle)!=bundle_authority["bundle_sha256"]: raise ParityError("Gate 0B blocked: committed calibration bundle hash mismatch")
    calibration_root,_=artifact_run_for(bundle,require_file=True); frozen=load(bundle); calibration_manifest=validate_run_manifest(calibration_root)
    if not candidate.get("canonical_ready") or not calibration_manifest.get("canonical_ready") or any(candidate.get(key)!=calibration_manifest.get(key) for key in ("environment","bindings","runtime")): raise ParityError("Gate 0B blocked: candidate/calibration run environment or binding identity mismatch")
    analysis_path=contained_path(calibration_root,frozen.get("analysis_path",""),require_file=True); source=contained_path(calibration_root,frozen.get("input_manifest",""),require_file=True); authority={**calibration,"_path":str(VALIDATION/"calibration-v1.json")}; recomputed=_raster().analyze_calibration(source,authority,_runtime_identity(),calibration_manifest); analysis=load(analysis_path)
    frozen_exact={"target_id":calibration["target_id"],"color_profile":calibration["color_profile"],"limits":calibration["limits"],"aa_band_device_px":calibration["aa_band"],"calibration_version":calibration["contract_version"],"thresholds_sha256":sha256(VALIDATION/"measurements-v1.json")}
    if analysis!=recomputed or not recomputed.get("ready") or any(frozen.get(k)!=v for k,v in frozen_exact.items()) or frozen.get("analysis_sha256")!=sha256(analysis_path): raise ParityError("Gate 0B blocked: frozen calibration semantics do not revalidate")
    mask_path=contained_path(ROOT,calibration["mask_manifest"],require_file=True); verify_masks(mask_path)
    if frozen.get("mask_manifest_sha256")!=sha256(mask_path) or frozen.get("runtime")!=_runtime_identity(): raise ParityError("Gate 0B blocked: frozen calibration dependencies differ")
    validate_provenance(frozen.get("approval"),root=calibration_root,allowed_dispositions={"PASS"},required_role="independent-reviewer",authorized_identities=_authorized("independent-reviewer"))
    return {"gate":"0B","passed":True,"candidate":candidate["artifact_root"],"calibration_run":calibration_manifest["artifact_root"]}


def verify_gate(gate: str, run_root: Path | None) -> dict[str, Any]:
    if gate == "0A":
        verify_manifests(require_ready=True)
        dom = verify_reference_dom()
        if not dom.get("passed"):
            raise ParityError("Gate 0A blocked: reference DOM execution did not pass")
        plan = native_plan()
        scenarios = {row["id"]: row for row in load(VALIDATION/"scenarios-v1.json")["scenarios"]}
        unresolved = [x["scenario"] for x in plan["records"] if x["status"] != "exact" or not scenarios[x["scenario"]].get("deterministic") or not scenarios[x["scenario"]].get("reproducible") or not x.get("mapping")]
        if unresolved: raise ParityError(f"Gate 0A blocked: {len(unresolved)} required native scenarios unresolved")
        return {"gate":"0A","passed":True}
    if gate == "0B":
        verify_gate("0A", run_root)
        return _verify_gate0b_candidate(run_root)
    if gate == "0C":
        verify_gate("0B", run_root)
        if run_root is None: raise ParityError("Gate 0C requires a run")
        verify_freshness(run_root)
        manifest = load(run_root/"manifest.json")
        if not manifest.get("canonical_ready") or manifest.get("dirty") or manifest.get("unresolved_fields"):
            raise ParityError("Gate 0C blocked: run fingerprint is not canonical-ready")
        schema = load(VALIDATION/"artifact-schema-v1.json")
        for name in schema["required_files"]:
            contained_path(run_root,name,require_file=True)
        for name in schema["required_directories"]:
            directory=contained_path(run_root,name)
            if not directory.is_dir(): raise ParityError(f"Gate 0C blocked: missing artifact directory {name}")
        index=_validate_index(load(run_root/"evidence-index.json")); packet=_validate_review_packet(run_root,load(run_root/"review-packet.json"),manifest,index)
        matrix=load(contained_path(run_root,"baseline-matrix.json",require_file=True))
        verify_baseline_matrix(matrix,run_root,index)
        verify_metric_reports(run_root/"metrics",run_root,index)
        return {"gate":"0C","passed":True}
    raise ParityError(f"unknown gate {gate}")
