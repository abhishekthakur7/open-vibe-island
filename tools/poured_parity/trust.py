from __future__ import annotations

import hashlib
import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


class TrustError(RuntimeError):
    pass


COMMIT_RE = re.compile(r"^[0-9a-f]{7,64}$")
RUN_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def _reject_symlink_chain(path: Path, stop: Path) -> None:
    current = path
    while True:
        if current.exists() and current.is_symlink():
            raise TrustError(f"symlink is forbidden in evidence path: {current}")
        if current == stop:
            return
        if current.parent == current:
            raise TrustError(f"path is not below evidence root: {path}")
        current = current.parent


def validate_run_root(path: Path, artifacts: Path, require_manifest: bool = True) -> Path:
    raw = path if path.is_absolute() else Path.cwd() / path
    artifacts_raw = artifacts if artifacts.is_absolute() else Path.cwd() / artifacts
    _reject_symlink_chain(raw, artifacts_raw)
    try:
        relative = raw.relative_to(artifacts_raw)
    except ValueError as exc:
        raise TrustError("run must be under artifacts/poured-parity") from exc
    if len(relative.parts) != 2:
        raise TrustError("run root must be artifacts/poured-parity/<native-commit>/<run-id>")
    commit, run_id = relative.parts
    if not COMMIT_RE.fullmatch(commit):
        raise TrustError(f"invalid native commit identity: {commit!r}")
    if run_id == "current" or not RUN_RE.fullmatch(run_id) or run_id in {".", ".."}:
        raise TrustError(f"invalid run identity: {run_id!r}")
    if require_manifest:
        manifest_path = contained_path(raw, "manifest.json", require_file=True)
        manifest = read_json(manifest_path)
        if manifest.get("native_commit") != commit or manifest.get("run_id") != run_id:
            raise TrustError("run directory does not match manifest identity")
        expected = f"artifacts/poured-parity/{commit}/{run_id}"
        if manifest.get("artifact_root", "").rstrip("/") != expected:
            raise TrustError("manifest artifact_root does not match run identity")
    return raw


def contained_path(root: Path, value: str | Path, require_file: bool = False) -> Path:
    relative = Path(value)
    if relative.is_absolute() or not relative.parts or any(part in {"", ".", ".."} for part in relative.parts):
        raise TrustError(f"unsafe relative evidence path: {value!r}")
    candidate = root.joinpath(relative)
    _reject_symlink_chain(candidate, root)
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise TrustError(f"evidence path escapes run: {value!r}") from exc
    if require_file and not candidate.is_file():
        raise TrustError(f"missing evidence file: {relative}")
    return candidate


def iter_files(root: Path, exclusions: Iterable[str] = ()) -> list[Path]:
    excluded = set(exclusions)
    result: list[Path] = []
    for base, directories, files in os.walk(root, followlinks=False):
        base_path = Path(base)
        for name in list(directories):
            child = base_path / name
            if child.is_symlink():
                raise TrustError(f"symlinked evidence directory is forbidden: {child}")
        for name in files:
            child = base_path / name
            if child.is_symlink():
                raise TrustError(f"symlinked evidence file is forbidden: {child}")
            relative = str(child.relative_to(root))
            if relative not in excluded:
                result.append(child)
    return sorted(result, key=lambda item: str(item.relative_to(root)))


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise TrustError(f"cannot read JSON {path}: {exc}") from exc


def iso_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value.endswith("Z"):
        return False
    try:
        datetime.fromisoformat(value[:-1] + "+00:00")
        return True
    except ValueError:
        return False


def normalize_identity(value: str) -> str:
    return " ".join(value.strip().casefold().split())


def validate_provenance(
    record: Any,
    *,
    root: Path | None,
    allowed_dispositions: set[str],
    required_role: str,
    distinct_from: str | None = None,
    evidence_index_hash: str | None = None,
    authorized_identities: set[str] | None = None,
) -> dict[str, Any]:
    required = {"status", "disposition", "identity", "role", "recorded_at", "authority_artifact", "authority_sha256", "evidence_index_sha256"}
    if not isinstance(record, dict) or set(record) != required:
        raise TrustError("approval provenance fields differ from the v1 contract")
    if record["status"] != "approved" or record["disposition"] not in allowed_dispositions:
        raise TrustError("approval provenance is not approved with an allowed disposition")
    identity=normalize_identity(record["identity"]) if isinstance(record["identity"],str) else ""
    other=normalize_identity(distinct_from) if isinstance(distinct_from,str) else None
    if not identity or (other is not None and (identity==other or identity.replace(" ","")==other.replace(" ",""))):
        raise TrustError("approval identity is missing or self-approved")
    if authorized_identities is not None and identity not in {normalize_identity(x) for x in authorized_identities}:
        raise TrustError("approval identity/role is not authorized by the principal registry")
    if record["role"] != required_role or not iso_timestamp(record["recorded_at"]):
        raise TrustError("approval role or timestamp is invalid")
    if not isinstance(record["authority_sha256"], str) or not re.fullmatch(r"[0-9a-f]{64}", record["authority_sha256"]):
        raise TrustError("authority artifact hash is invalid")
    if root is not None:
        artifact = contained_path(root, record["authority_artifact"], require_file=True)
        if digest(artifact) != record["authority_sha256"]:
            raise TrustError("authority artifact hash mismatch")
    if evidence_index_hash is not None and record["evidence_index_sha256"] != evidence_index_hash:
        raise TrustError("approval is not bound to the exact evidence index")
    if evidence_index_hash is None and record["evidence_index_sha256"] is not None and not re.fullmatch(r"[0-9a-f]{64}", record["evidence_index_sha256"]):
        raise TrustError("approval evidence-index hash is invalid")
    return record
