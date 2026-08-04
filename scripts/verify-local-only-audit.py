#!/usr/bin/env python3
"""Fail closed when the Round 1 local-only disposition map is incomplete."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "docs/audits/local-only-disposition-map.json"
VALID_DISPOSITIONS = {"retain", "remove", "replace", "migrate"}
REQUIRED_ALLOWLISTS = {
    "ipc_roles",
    "executables",
    "apple_script_templates",
    "local_urls",
    "cmux_operations",
}
DIRECT_AUTOMATION_PATTERNS = {
    "process": re.compile(r"\bProcess\(\)"),
    "process-executable": re.compile(r"\.executableURL\s*="),
    "process-arguments": re.compile(r"\.arguments\s*="),
    "process-environment": re.compile(r"\.environment\s*="),
    "process-cwd": re.compile(r"\.currentDirectoryURL\s*="),
    "osascript": re.compile(r'"/usr/bin/osascript"'),
    "path-lookup": re.compile(r'"/usr/bin/env"'),
    "apple-script-api": re.compile(r"\bNSAppleScript\b"),
    "node-child-process": re.compile(r"\bchild_process\b"),
    "node-spawn": re.compile(r"\bspawnSync\s*\("),
    "workspace-open": re.compile(
        r"NSWorkspace\.shared\.(?:open|openURL|openApplication|activateFileViewerSelecting)"
    ),
    "shell-script": re.compile(r"\bdo\s+shell\s+script\b", re.IGNORECASE),
}
POWERFUL_PATTERN = re.compile(
    r"AF_UNIX|socket\(|SOCK_STREAM|NWListener|NWBrowser|URLSession|URLRequest|"
    r"Process\(\)|executableURL|osascript|NSWorkspace|openURL|openApplication|"
    r"UserDefaults|sqlite3_|SecItem|Keychain|HookInstallation(?:Manager)?|"
    r"HookInstaller|ManagedHooksBinary"
)
SOURCE_SUFFIXES = {".swift", ".js", ".py"}
POLICY_IMPLEMENTATION_PATHS = {
    "scripts/verify-local-only-audit.py",
    "scripts/verify-no-network-policy.py",
    "scripts/observe-runtime-network.py",
    "scripts/tests/test_verify_local_only_audit.py",
    "scripts/tests/test_verify_no_network_policy.py",
    "scripts/tests/test_observe_runtime_network.py",
}
ROUND_2_REMOVED_PATHS = (
    "ios",
    "Sources/OpenIslandCore/WatchHTTPEndpoint.swift",
    "Sources/OpenIslandCore/WatchNotificationRelay.swift",
    "Tests/OpenIslandCoreTests/WatchNotificationRelayTests.swift",
    "docs/watch-notification-design.md",
    "docs/watch-notification-impl-plan.md",
)
ROUND_2_FORBIDDEN_PATTERN = re.compile(
    r"OpenIslandMobile|OpenIslandWatch|WatchHTTPEndpoint|"
    r"WatchNotificationRelay|WatchSSEEvent|WatchSessionManager|"
    r"watch\.notification\.enabled|Bonjour|NSBonjourServices|"
    r"NSLocalNetworkUsageDescription|IPHONEOS_DEPLOYMENT_TARGET|"
    r"WATCHOS_DEPLOYMENT_TARGET|iphoneos|watchos"
)
ROUND_2_AUDIT_SUFFIXES = {".swift", ".plist", ".pbxproj", ".xcprivacy"}
ROUND_3_REMOVED_PATHS = (
    ".github/workflows",
    ".github/RELEASE_TEMPLATE.md",
    "Sources/OpenIslandApp/UpdateChecker.swift",
    "appcast.xml",
    "scripts/package-app.sh",
    "scripts/update-appcast.sh",
    "docs/releasing.md",
    "docs/release-signing.md",
)
ROUND_3_FORBIDDEN_PATTERN = re.compile(
    r"Sparkle|UpdateChecker|SUFeedURL|SUPublicEDKey|appcast|notarytool|"
    r"\bstapler\b|create-dmg|gh\s+release|Homebrew|homebrew-tap|"
    r"OPEN_ISLAND_(?:NOTARY|EDDSA|SIGN_IDENTITY)"
)
ROUND_3_RETAINED_SCRIPTS = (
    "scripts/setup-dev-signing.sh",
    "scripts/launch-dev-app.sh",
    "scripts/package-local-app.sh",
)
REMOTE_SWIFTPM_REFERENCE = re.compile(r"\.package\s*\(\s*url\s*:")
REMOTE_XCODE_PACKAGE_REFERENCE = re.compile(
    r"XCRemoteSwiftPackageReference|repositoryURL\s*=|XCRemoteSwiftPackageProductDependency"
)
REMOTE_DEPENDENCY_FILENAMES = {"Package.swift", "project.pbxproj"}


class RepositoryScopeError(RuntimeError):
    """Raised when Git cannot provide a safe repository-local audit scope."""


def fail(errors: list[str], message: str) -> None:
    errors.append(message)


def flattened_paths(inventory: dict[str, list[dict[str, object]]]) -> list[str]:
    paths: list[str] = []
    for entries in inventory.values():
        for entry in entries:
            entry_paths = entry.get("paths", [])
            if isinstance(entry_paths, list):
                paths.extend(str(path) for path in entry_paths)
    return paths


def inventory_ids(inventory: dict[str, list[dict[str, object]]]) -> set[str]:
    return {
        str(entry.get("id"))
        for entries in inventory.values()
        for entry in entries
        if isinstance(entry, dict) and entry.get("id")
    }


def repository_candidate_paths(root: Path, filenames: set[str]) -> list[Path]:
    """Return tracked and non-ignored untracked candidate files from Git.

    Git's index and untracked-file discovery define the repository boundary, so
    nested repositories/worktrees and ignored local tooling state are never
    traversed by this audit.
    """
    try:
        result = subprocess.run(
            [
                "git",
                "-C",
                os.fspath(root),
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "-z",
            ],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        raise RepositoryScopeError(
            f"cannot enumerate repository audit scope with git: {exc}"
        ) from exc
    if result.returncode:
        diagnostic = result.stderr.decode(errors="replace").strip()
        if diagnostic:
            raise RepositoryScopeError(
                f"cannot enumerate repository audit scope with git: {diagnostic}"
            )
        raise RepositoryScopeError(
            f"cannot enumerate repository audit scope with git (exit {result.returncode})"
        )

    paths: list[Path] = []
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative = Path(os.fsdecode(raw_path))
        if (
            (relative.name not in filenames and relative.suffix not in filenames)
            or relative.is_absolute()
            or ".git" in relative.parts
            or ".build" in relative.parts
        ):
            continue
        path = root / relative
        if path.is_file():
            paths.append(path)
    return sorted(set(paths), key=lambda path: path.relative_to(root).as_posix())


def remote_dependency_reference_errors(root: Path) -> list[str]:
    """Find forbidden remote package references within the current Git repository."""
    errors: list[str] = []
    candidate_paths = repository_candidate_paths(root, REMOTE_DEPENDENCY_FILENAMES)
    for path in candidate_paths:
        text = path.read_text(errors="ignore")
        relative = path.relative_to(root).as_posix()
        if path.name == "Package.swift" and REMOTE_SWIFTPM_REFERENCE.search(text):
            errors.append(f"remote SwiftPM package reference is forbidden: {relative}")
        if path.name == "project.pbxproj" and REMOTE_XCODE_PACKAGE_REFERENCE.search(text):
            errors.append(f"remote Xcode package reference is forbidden: {relative}")
    return errors


def no_network_policy_errors(root: Path) -> list[str]:
    """Run the Round 5 policy as part of the repository audit gate."""
    policy = root / "scripts/verify-no-network-policy.py"
    if not policy.is_file():
        return ["Round 5 static no-network policy is missing"]
    result = subprocess.run(
        [sys.executable, os.fspath(policy), "--root", os.fspath(root)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        details = (result.stdout + result.stderr).strip()
        return [f"Round 5 static no-network policy failed: {details}"]
    return []


def direct_automation_errors(root: Path, dispositions: list[object]) -> list[str]:
    """Fail closed on direct launch/open/AppleScript additions.

    The only permitted direct primitives have a file-and-symbol disposition in
    the audit map.  A new primitive, a move to another file, or an additional
    occurrence beyond the reviewed count is a CI failure rather than an
    invitation to add a broad directory allowlist.
    """
    errors: list[str] = []
    allowed: dict[tuple[str, str], int] = {}
    for entry in dispositions:
        if not isinstance(entry, dict):
            errors.append("automation_source_dispositions contains a non-object entry")
            continue
        for key in ("id", "path", "symbol", "action", "role", "patterns", "evidence"):
            if not entry.get(key):
                errors.append(f"automation_source_dispositions.{entry.get('id', '<unknown>')} missing {key}")
        path = entry.get("path")
        patterns = entry.get("patterns")
        if not isinstance(path, str) or not isinstance(patterns, dict):
            continue
        for name, count in patterns.items():
            if name not in DIRECT_AUTOMATION_PATTERNS or not isinstance(count, int) or count < 0:
                errors.append(f"automation_source_dispositions.{entry.get('id', '<unknown>')} has invalid pattern count")
                continue
            allowed[(path, name)] = allowed.get((path, name), 0) + count

    observed: dict[tuple[str, str], int] = {}
    for path in repository_candidate_paths(root, {".swift", ".js"}):
        relative = path.relative_to(root).as_posix()
        if not relative.startswith("Sources/"):
            continue
        text = path.read_text(errors="ignore")
        for name, pattern in DIRECT_AUTOMATION_PATTERNS.items():
            count = len(pattern.findall(text))
            if count:
                observed[(relative, name)] = count

    for key, count in sorted(observed.items()):
        expected = allowed.get(key, 0)
        if count != expected:
            errors.append(
                f"uninventoryed direct automation primitive: {key[0]} {key[1]} "
                f"(observed {count}, reviewed {expected})"
            )
    for key, expected in sorted(allowed.items()):
        if observed.get(key, 0) != expected:
            errors.append(
                f"stale direct automation disposition: {key[0]} {key[1]} "
                f"(reviewed {expected}, observed {observed.get(key, 0)})"
            )
    return errors


def main() -> int:
    errors: list[str] = []
    try:
        payload = json.loads(MAP_PATH.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"FAIL: cannot read {MAP_PATH.relative_to(ROOT)}: {exc}")
        return 1

    if payload.get("schema") != 1:
        fail(errors, "unsupported or missing schema")
    inventory = payload.get("inventory")
    if not isinstance(inventory, dict) or not inventory:
        fail(errors, "inventory must be a non-empty object")
        inventory = {}

    for category, entries in inventory.items():
        if not isinstance(entries, list) or not entries:
            fail(errors, f"inventory.{category} must be a non-empty list")
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                fail(errors, f"inventory.{category} contains a non-object entry")
                continue
            for key in ("id", "paths", "disposition", "round", "evidence", "migration"):
                if key not in entry or not entry[key]:
                    fail(errors, f"inventory.{category}.{entry.get('id', '<unknown>')} missing {key}")
            if entry.get("disposition") not in VALID_DISPOSITIONS:
                fail(errors, f"inventory.{category}.{entry.get('id', '<unknown>')} has invalid disposition")
            if not isinstance(entry.get("round"), int) or not 1 <= entry["round"] <= 11:
                fail(errors, f"inventory.{category}.{entry.get('id', '<unknown>')} has invalid owning round")

    allowlists = payload.get("allowlists")
    if not isinstance(allowlists, dict):
        fail(errors, "allowlists must be an object")
        allowlists = {}
    for name in REQUIRED_ALLOWLISTS:
        value = allowlists.get(name)
        if not isinstance(value, list) or not value:
            fail(errors, f"allowlists.{name} must be a non-empty list")
    dispositions = payload.get("automation_source_dispositions")
    if not isinstance(dispositions, list) or not dispositions:
        fail(errors, "automation_source_dispositions must be a non-empty list")
        dispositions = []
    errors.extend(direct_automation_errors(ROOT, dispositions))

    all_paths = flattened_paths(inventory)
    all_ids = inventory_ids(inventory)
    for item_id in ("mobile-xcode-project", "watch-relay"):
        if item_id not in all_ids:
            fail(errors, f"required Round 2 removal record missing from inventory: {item_id}")
    inventory_text = "\n".join(all_paths)
    for marker in (
        "Package.swift:OpenIslandCore",
        "Package.swift:OpenIslandApp",
        "Package.swift:OpenIslandHooks",
        "Package.swift:OpenIslandSetup",
        "ios/OpenIslandMobile.xcodeproj",
        "config/packaging/OpenIslandApp.entitlements",
        ".github/workflows",
        "scripts/package-local-app.sh",
        "scripts/launch-dev-app.sh",
        "README.md",
        "PRIVACY_POLICY.md",
    ):
        if marker not in inventory_text:
            fail(errors, f"required audited surface missing from inventory: {marker}")

    package_text = (ROOT / "Package.swift").read_text()
    try:
        errors.extend(remote_dependency_reference_errors(ROOT))
    except RepositoryScopeError as exc:
        fail(errors, str(exc))
    errors.extend(no_network_policy_errors(ROOT))
    provenance_path = ROOT / "docs/audits/dependency-provenance.md"
    if not provenance_path.is_file() or "zero third-party SwiftPM dependencies" not in provenance_path.read_text(errors="ignore"):
        fail(errors, "Round 4 dependency provenance must record the zero-vendor state")
    entitlements = (ROOT / "config/packaging/OpenIslandApp.entitlements").read_text()
    for entitlement in re.findall(r"<key>([^<]+)</key>", entitlements):
        if entitlement not in inventory_text:
            fail(errors, f"entitlement has no disposition: {entitlement}")

    known_paths = set(payload.get("powerful_source_paths", []))
    if not known_paths:
        fail(errors, "powerful_source_paths is empty")
    for directory in (ROOT / "Sources", ROOT / "ios", ROOT / "scripts"):
        if not directory.exists():
            continue
        for path in directory.rglob("*"):
            if not path.is_file() or path.suffix not in SOURCE_SUFFIXES:
                continue
            relative = path.relative_to(ROOT).as_posix()
            if relative in POLICY_IMPLEMENTATION_PATHS:
                continue
            if POWERFUL_PATTERN.search(path.read_text(errors="ignore")) and relative not in known_paths:
                fail(errors, f"unknown powerful source match: {relative}")

    for relative in ROUND_2_REMOVED_PATHS:
        if (ROOT / relative).exists():
            fail(errors, f"removed Round 2 surface remains: {relative}")

    for relative in ROUND_3_REMOVED_PATHS:
        if (ROOT / relative).exists():
            fail(errors, f"removed Round 3 surface remains: {relative}")

    if ".product(name: \"Sparkle\"" in package_text or "sparkle-project/Sparkle" in package_text:
        fail(errors, "removed Round 3 Sparkle dependency remains in Package.swift")

    round_3_audit_files = [
        ROOT / "Package.swift",
        ROOT / "README.md",
        ROOT / "CLAUDE.md",
        ROOT / "docs/product.md",
        ROOT / "docs/architecture.md",
        ROOT / "docs/index.md",
    ]
    round_3_audit_files.extend(
        path for directory in (ROOT / "Sources", ROOT / "Tests", ROOT / "config")
        if directory.exists()
        for path in directory.rglob("*")
        if path.is_file() and path.suffix in {".swift", ".plist", ".entitlements"}
    )
    for path in round_3_audit_files:
        # A deleted doc carries no forbidden surface; skip it the way the
        # Round 2 sweep below already does instead of raising FileNotFoundError.
        if not path.exists():
            continue
        if ROUND_3_FORBIDDEN_PATTERN.search(path.read_text(errors="ignore")):
            fail(errors, f"forbidden Round 3 updater/distribution surface: {path.relative_to(ROOT)}")

    for relative in ROUND_3_RETAINED_SCRIPTS:
        path = ROOT / relative
        if not path.is_file():
            fail(errors, f"required Round 3 local workflow is missing: {relative}")
            continue
        text = path.read_text(errors="ignore")
        if "--disable-automatic-resolution" not in text and relative != "scripts/setup-dev-signing.sh":
            fail(errors, f"local workflow does not disable automatic resolution: {relative}")
        if ROUND_3_FORBIDDEN_PATTERN.search(text):
            fail(errors, f"local workflow retains updater/distribution coupling: {relative}")

    round_2_audit_files = [
        ROOT / "Package.swift",
        ROOT / "README.md",
        ROOT / "PRIVACY_POLICY.md",
        ROOT / "docs/product.md",
        ROOT / "docs/architecture.md",
    ]
    for directory in (ROOT / "Sources", ROOT / "Tests", ROOT / "config", ROOT / "ios"):
        if directory.exists():
            round_2_audit_files.extend(
                path for path in directory.rglob("*")
                if path.is_file() and path.suffix in ROUND_2_AUDIT_SUFFIXES
            )
    for path in round_2_audit_files:
        if not path.exists():
            continue
        if ROUND_2_FORBIDDEN_PATTERN.search(path.read_text(errors="ignore")):
            fail(errors, f"forbidden Round 2 mobile/Watch/relay declaration: {path.relative_to(ROOT)}")

    if errors:
        print("FAIL: local-only audit gate")
        for error in errors:
            print(f"- {error}")
        return 1
    print("PASS: local-only audit map is complete and all current powerful source matches are dispositioned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
