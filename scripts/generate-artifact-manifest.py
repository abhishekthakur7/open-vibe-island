#!/usr/bin/env python3
"""Create the deterministic, signed inventory for a local app bundle."""

import hashlib
import json
import os
import stat
import sys
from pathlib import Path


STATUS_LINE_TEMPLATES = {
    "Contents/Resources/ClaudeStatusLineTemplates/status-line-v1.sh.template",
    "Contents/Resources/ClaudeStatusLineTemplates/status-line-wrapper-v1.sh.template",
    "Contents/Resources/ClaudeStatusLineTemplates/status-line-delegate-v1.sh.template",
}


def entry(bundle: Path, path: Path) -> dict:
    relative = path.relative_to(bundle).as_posix()
    if relative == "Contents/Helpers/OpenIslandHooks":
        artifact_id = "open-island-hooks"
        marker = "OpenIslandHooks"
        template_version = "1"
    elif relative == "Contents/Resources/ClaudeStatusLineTemplates/status-line-v1.sh.template":
        artifact_id = "claude-statusline-script-template"
        marker = "Open Island status-line template"
        template_version = "1"
    elif relative == "Contents/Resources/ClaudeStatusLineTemplates/status-line-wrapper-v1.sh.template":
        artifact_id = "claude-statusline-wrapper-template"
        marker = "Open Island status-line template"
        template_version = "1"
    elif relative == "Contents/Resources/ClaudeStatusLineTemplates/status-line-delegate-v1.sh.template":
        artifact_id = "claude-statusline-delegate-template"
        marker = "Open Island status-line template"
        template_version = "1"
    else:
        artifact_id = "resource:" + relative
        marker = "static-resource"
        template_version = "1"
    try:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as error:
        raise RuntimeError(f"cannot hash {path}: {error}") from error
    return {
        "artifactID": artifact_id,
        "version": 1,
        "relativePath": relative,
        "sha256": digest,
        "expectedMode": stat.S_IMODE(path.stat().st_mode),
        "managedMarker": marker,
        "templateVersion": template_version,
    }


def main() -> int:
    if len(sys.argv) != 2:
        raise RuntimeError("usage: generate-artifact-manifest.py /path/to/Open Island.app")
    bundle = Path(sys.argv[1]).resolve()
    helper = bundle / "Contents/Helpers/OpenIslandHooks"
    resources = bundle / "Contents/Resources"
    if not helper.is_file() or not resources.is_dir():
        raise RuntimeError("bundle is missing the helper or resources directory")
    files = [helper] + sorted(path for path in resources.rglob("*") if path.is_file() and path.name != "OpenIslandArtifacts.json")
    inventory = {path.relative_to(bundle).as_posix() for path in files}
    missing_templates = sorted(STATUS_LINE_TEMPLATES - inventory)
    if missing_templates:
        raise RuntimeError("bundle is missing required Claude status-line templates: " + ", ".join(missing_templates))
    manifest = {"formatVersion": 1, "artifacts": [entry(bundle, path) for path in files]}
    destination = resources / "OpenIslandArtifacts.json"
    temporary = destination.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o644)
    os.replace(temporary, destination)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"artifact manifest generation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
