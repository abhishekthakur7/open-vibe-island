#!/usr/bin/env python3
"""Enforce Open Island's repository-scoped static no-network boundary.

This is intentionally a source policy, not a claim that it observes runtime
traffic. Round 10 owns process-tree observation. Git supplies the candidate
set so ignored files and nested worktrees never affect the result.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY_VERSION = "round-5"
SOURCE_SUFFIXES = {".swift", ".js", ".py", ".sh", ".bash", ".zsh", ".entitlements", ".plist", ".pbxproj", ".xcconfig"}
SHELL_SUFFIXES = {".sh", ".bash", ".zsh"}
MANIFEST_NAMES = {"Package.swift", "project.pbxproj"}
POLICY_IMPLEMENTATION_PATHS = {
    "scripts/verify-local-only-audit.py",
    "scripts/verify-no-network-policy.py",
    "scripts/tests/test_verify_local_only_audit.py",
    "scripts/tests/test_verify_no_network_policy.py",
}
AF_UNIX_ALLOWED_PATHS = {
    "Sources/OpenIslandCore/BridgeTransport.swift",
    "Sources/OpenIslandCore/BridgeCommandClient.swift",
    "Sources/OpenIslandCore/BridgeServer.swift",
    "Sources/OpenIslandCore/LocalBridgeClient.swift",
    "Sources/OpenIslandApp/TerminalJumpService.swift",
    "Sources/OpenIslandApp/Resources/open-island-opencode.js",
    "scripts/replay-bridge-scenarios.py",
}
REMOVED_ROUND_5_PATHS = {
    "docs/ssh-setup.md",
    "scripts/open-island-hooks.py",
    "scripts/remote-setup.sh",
}
PROVENANCE_DOCUMENTATION_PATHS = {
    "docs/audits/dependency-provenance.md",
}

NETWORK_RULES = (
    ("Network framework", re.compile(r"\bimport\s+Network\b")),
    ("network URL loading", re.compile(r"\b(?:URLSession|URLRequest|NWURLSession)\b")),
    ("Network endpoint API", re.compile(r"\b(?:NWListener|NWBrowser|NWConnection|NWEndpoint)\b")),
    ("IP socket family", re.compile(r"\b(?:AF_INET6?|PF_INET|sockaddr_in6?|getaddrinfo|inet_[a-z]+|SOCK_DGRAM|SOCK_RAW|IPPROTO_[A-Z_]+)\b")),
    ("IP listener API", re.compile(r"\b(?:Darwin\.)?(?:listen|accept)\s*\(")),
    ("remote endpoint literal", re.compile(r"\b(?:https?|wss?|ftp|ssh)://", re.IGNORECASE)),
    ("remote forwarding configuration", re.compile(r"\b(?:RemoteForward|LocalForward|ProxyJump|ssh\s+-[LRD])\b")),
    ("network-capable shell tool", re.compile(r"(?<![A-Za-z0-9_.-])(?:curl|wget|ssh|scp|sftp|ftp|telnet|nc|ncat)(?![A-Za-z0-9_.-])")),
    ("remote Git operation", re.compile(r"\bgit\s+(?:clone|fetch|pull|push|ls-remote)\b")),
    ("telemetry or update surface", re.compile(r"\b(?:TelemetryClient|AnalyticsClient|UpdateChecker|SUFeedURL|SUPublicEDKey|Sparkle|appcast)\b")),
    ("remote SwiftPM package", re.compile(r"\.package\s*\(\s*url\s*:")),
    ("remote Xcode package", re.compile(r"\b(?:XCRemoteSwiftPackageReference|XCRemoteSwiftPackageProductDependency|repositoryURL\s*=)")),
)
AF_UNIX_PATTERN = re.compile(r"\b(?:AF_UNIX|sockaddr_un|from\s+[\"']net[\"'])\b")
NETWORK_ENTITLEMENT_PATTERN = re.compile(r"com\.apple\.security\.network\.(?:client|server)")
INERT_FORMAT_URLS = re.compile(r"https?://(?:www\.apple\.com/DTDs/|www\.w3\.org/2000/svg)")
SWIFTPM_BUILD_PATTERN = re.compile(r"^\s*swift\s+build\b.*$", re.MULTILINE)


class RepositoryScopeError(RuntimeError):
    """Raised when Git cannot define the audit boundary."""


def repository_candidate_paths(root: Path) -> list[Path]:
    """Return tracked and non-ignored untracked files, never recursively walking."""
    try:
        result = subprocess.run(
            ["git", "-C", os.fspath(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except OSError as exc:
        raise RepositoryScopeError(f"cannot enumerate no-network audit scope with git: {exc}") from exc
    if result.returncode:
        detail = result.stderr.decode(errors="replace").strip()
        raise RepositoryScopeError(
            f"cannot enumerate no-network audit scope with git" + (f": {detail}" if detail else "")
        )

    candidates: list[Path] = []
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative = Path(os.fsdecode(raw_path))
        if relative.is_absolute() or ".git" in relative.parts or ".build" in relative.parts:
            continue
        path = root / relative
        if path.is_file():
            candidates.append(path)
    return sorted(set(candidates), key=lambda path: path.relative_to(root).as_posix())


def is_policy_candidate(relative: str) -> bool:
    if relative in POLICY_IMPLEMENTATION_PATHS:
        return False
    path = Path(relative)
    if relative in PROVENANCE_DOCUMENTATION_PATHS:
        return True
    if path.name in MANIFEST_NAMES:
        return True
    return bool(path.parts) and path.parts[0] in {"Sources", "scripts", "config"} and path.suffix in SOURCE_SUFFIXES


def line_number(text: str, match: re.Match[str]) -> int:
    return text.count("\n", 0, match.start()) + 1


def match_is_in_line_comment(text: str, match: re.Match[str]) -> bool:
    line_start = text.rfind("\n", 0, match.start()) + 1
    return text[line_start:match.start()].lstrip().startswith("//")


def source_policy_errors(root: Path) -> list[str]:
    errors: list[str] = []
    try:
        candidates = repository_candidate_paths(root)
    except RepositoryScopeError as exc:
        return [str(exc)]

    for relative in sorted(REMOVED_ROUND_5_PATHS):
        if root.joinpath(relative).exists():
            errors.append(f"removed Round 5 remote surface remains: {relative}")

    for path in candidates:
        relative = path.relative_to(root).as_posix()
        if not is_policy_candidate(relative):
            continue
        text = path.read_text(errors="ignore")
        scan_text = INERT_FORMAT_URLS.sub("inert-format-url", text)

        for rule_name, pattern in NETWORK_RULES:
            if relative in PROVENANCE_DOCUMENTATION_PATHS and rule_name == "remote endpoint literal":
                continue
            if relative in AF_UNIX_ALLOWED_PATHS and rule_name == "IP listener API":
                continue
            if rule_name in {"network-capable shell tool", "remote Git operation"} and path.suffix not in SHELL_SUFFIXES:
                continue
            for match in pattern.finditer(scan_text):
                errors.append(f"{rule_name}: {relative}:{line_number(scan_text, match)}")

        for match in AF_UNIX_PATTERN.finditer(scan_text):
            if relative not in AF_UNIX_ALLOWED_PATHS:
                errors.append(f"AF_UNIX is only allowed in mapped bridge files: {relative}:{line_number(scan_text, match)}")

        if relative not in AF_UNIX_ALLOWED_PATHS:
            for match in re.finditer(r"\bsocket\s*\(", scan_text):
                if match_is_in_line_comment(scan_text, match):
                    continue
                errors.append(f"socket API is only allowed in mapped bridge files: {relative}:{line_number(scan_text, match)}")

        for match in NETWORK_ENTITLEMENT_PATTERN.finditer(scan_text):
            errors.append(f"network entitlement is forbidden: {relative}:{line_number(scan_text, match)}")

        if relative in {"scripts/package-local-app.sh", "scripts/launch-dev-app.sh"}:
            for match in SWIFTPM_BUILD_PATTERN.finditer(scan_text):
                command = match.group(0)
                if "--disable-automatic-resolution" not in command or "--disable-sandbox" not in command:
                    errors.append(
                        f"local SwiftPM build must disable resolution and its inner sandbox: "
                        f"{relative}:{line_number(scan_text, match)}"
                    )

    return errors


def entitlement_policy_errors(entitlements: str, label: str) -> list[str]:
    return [f"network entitlement is forbidden: {label}" for _ in NETWORK_ENTITLEMENT_PATTERN.finditer(entitlements)]


def plist_policy_errors(payload: object, label: str) -> list[str]:
    serialized = repr(payload)
    errors: list[str] = []
    for rule_name, pattern in NETWORK_RULES:
        if rule_name in {"IP socket family", "IP listener API"}:
            continue
        if pattern.search(serialized):
            errors.append(f"{rule_name}: {label}")
    return errors


def packaged_app_policy_errors(bundle: Path) -> list[str]:
    errors: list[str] = []
    info_path = bundle / "Contents/Info.plist"
    executable = bundle / "Contents/MacOS/OpenIslandApp"
    if not executable.is_file():
        errors.append(f"packaged app executable is missing: {executable}")
    try:
        payload = plistlib.loads(info_path.read_bytes())
    except (OSError, plistlib.InvalidFileException) as exc:
        errors.append(f"cannot read packaged app metadata: {info_path}: {exc}")
    else:
        errors.extend(plist_policy_errors(payload, info_path.as_posix()))

    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", os.fspath(bundle)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode:
        errors.append(f"cannot inspect packaged app entitlements: {bundle}: {result.stderr.strip()}")
    else:
        errors.extend(entitlement_policy_errors(result.stdout + result.stderr, bundle.as_posix()))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--bundle", type=Path)
    args = parser.parse_args(argv)

    errors = source_policy_errors(args.root.resolve())
    if args.bundle:
        errors.extend(packaged_app_policy_errors(args.bundle.resolve()))
    if errors:
        print(f"FAIL: static no-network policy ({POLICY_VERSION})")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"PASS: static no-network policy ({POLICY_VERSION})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
