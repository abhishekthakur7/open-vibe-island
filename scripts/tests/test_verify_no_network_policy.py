#!/usr/bin/env python3
"""Invariant fixtures for the static no-network policy."""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import tempfile
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
POLICY_PATH = REPO_ROOT / "scripts" / "verify-no-network-policy.py"
SPEC = importlib.util.spec_from_file_location("verify_no_network_policy", POLICY_PATH)
assert SPEC is not None and SPEC.loader is not None
POLICY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(POLICY)


class NoNetworkPolicyTests(unittest.TestCase):
    def make_repository(self, root: pathlib.Path) -> None:
        subprocess.run(["git", "init", "--quiet", str(root)], check=True)

    def write(self, root: pathlib.Path, relative: str, text: str) -> None:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def assert_fixture_fails(self, relative: str, text: str, expected: str) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            self.write(root, relative, text)
            self.assertTrue(any(expected in error for error in POLICY.source_policy_errors(root)))

    def test_current_repository_passes(self) -> None:
        self.assertEqual(POLICY.source_policy_errors(REPO_ROOT), [])

    def test_network_framework_and_url_loading_fail(self) -> None:
        self.assert_fixture_fails("Sources/Probe.swift", "import " + "Network\n", "Network framework")
        self.assert_fixture_fails("Sources/Probe.swift", "let task = URL" + "Session.shared\n", "network URL loading")

    def test_ip_socket_and_listener_families_fail(self) -> None:
        self.assert_fixture_fails("Sources/Probe.swift", "let family = AF_" + "INET\n", "IP socket family")
        self.assert_fixture_fails("Sources/Probe.swift", "listen" + "(fd, 1)\n", "IP listener API")

    def test_remote_endpoint_shell_tool_and_package_refs_fail(self) -> None:
        self.assert_fixture_fails("scripts/probe.sh", "curl https" + "://example.invalid\n", "remote endpoint literal")
        self.assert_fixture_fails("scripts/probe.sh", "s" + "sh user@example.invalid\n", "network-capable shell tool")
        self.assert_fixture_fails("scripts/probe.sh", "git " + "fetch origin\n", "remote Git operation")
        self.assert_fixture_fails("Package.swift", ".package(url: \"https" + "://example.invalid/Remote\", from: \"1\")\n", "remote SwiftPM package")

    def test_telemetry_update_and_network_entitlements_fail(self) -> None:
        self.assert_fixture_fails("Sources/Probe.swift", "let updater = Update" + "Checker()\n", "telemetry or update surface")
        self.assert_fixture_fails("config/Probe.entitlements", "com.apple.security.network." + "client\n", "network entitlement")

    def test_packaged_metadata_and_removed_remote_surfaces_fail(self) -> None:
        metadata_errors = POLICY.plist_policy_errors(
            {"SU" + "FeedURL": "https" + "://example.invalid/feed"}, "Info.plist"
        )
        self.assertTrue(any("telemetry or update surface" in error for error in metadata_errors))
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            self.write(root, "scripts/remote-setup.sh", "#!/bin/sh\n")
            self.assertTrue(any("removed Round 5 remote surface" in error for error in POLICY.source_policy_errors(root)))

    def test_retained_local_swiftpm_builds_require_outer_sandbox_compatibility(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            self.write(
                root,
                "scripts/package-local-app.sh",
                "swift build --disable-automatic-resolution --show-bin-path\n",
            )
            errors = POLICY.source_policy_errors(root)
            self.assertTrue(any("local SwiftPM build must disable" in error for error in errors))

    def test_af_unix_is_limited_to_the_mapped_bridge_files(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            allowed = next(iter(POLICY.AF_UNIX_ALLOWED_PATHS))
            self.write(root, allowed, "let family = AF_" + "UNIX\n")
            self.assertEqual(POLICY.source_policy_errors(root), [])
            self.write(root, "Sources/Elsewhere.swift", "let family = AF_" + "UNIX\n")
            errors = POLICY.source_policy_errors(root)
            self.assertTrue(any("AF_UNIX is only allowed" in error for error in errors))

    def test_provenance_documentation_is_inert_and_scoped(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            self.write(root, "docs/audits/dependency-provenance.md", "upstream https" + "://example.invalid\n")
            self.assertEqual(POLICY.source_policy_errors(root), [])

    def test_nested_repository_is_outside_the_git_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            nested = root / ".claude" / "worktrees" / "historical"
            self.make_repository(nested)
            self.write(nested, "Sources/Probe.swift", "import " + "Network\n")
            self.assertEqual(POLICY.source_policy_errors(root), [])


if __name__ == "__main__":
    unittest.main()
