#!/usr/bin/env python3
"""Fail closed when the Round 1 local-only disposition map is incomplete."""

from __future__ import annotations

import json
import re
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
POWERFUL_PATTERN = re.compile(
    r"AF_UNIX|socket\(|SOCK_STREAM|NWListener|NWBrowser|URLSession|URLRequest|"
    r"Process\(\)|executableURL|osascript|NSWorkspace|openURL|openApplication|"
    r"UserDefaults|sqlite3_|SecItem|Keychain|HookInstallation(?:Manager)?|"
    r"HookInstaller|ManagedHooksBinary"
)
SOURCE_SUFFIXES = {".swift", ".js", ".py"}
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
        "scripts/package-app.sh",
        "scripts/launch-dev-app.sh",
        "README.md",
        "PRIVACY_POLICY.md",
    ):
        if marker not in inventory_text:
            fail(errors, f"required audited surface missing from inventory: {marker}")

    package_text = (ROOT / "Package.swift").read_text()
    for dependency in re.findall(r'\.package\(url:\s*"([^"]+)"', package_text):
        if dependency not in inventory_text:
            fail(errors, f"remote package has no disposition: {dependency}")
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
            if relative == "scripts/verify-local-only-audit.py":
                continue
            if POWERFUL_PATTERN.search(path.read_text(errors="ignore")) and relative not in known_paths:
                fail(errors, f"unknown powerful source match: {relative}")

    for relative in ROUND_2_REMOVED_PATHS:
        if (ROOT / relative).exists():
            fail(errors, f"removed Round 2 surface remains: {relative}")

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
