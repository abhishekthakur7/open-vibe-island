#!/usr/bin/env python3
"""Regression tests for the repository-scoped dependency audit."""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
AUDIT_PATH = REPO_ROOT / "scripts" / "verify-local-only-audit.py"
SPEC = importlib.util.spec_from_file_location("verify_local_only_audit", AUDIT_PATH)
assert SPEC is not None and SPEC.loader is not None
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class RepositoryScopedDependencyAuditTests(unittest.TestCase):
    def make_repository(self, root: pathlib.Path) -> None:
        subprocess.run(["git", "init", "--quiet", str(root)], check=True)

    def test_untracked_current_repository_manifests_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            (root / "Package.swift").write_text(
                '.package(url: "https://example.invalid/Remote.swift", from: "1.0.0")\n'
            )
            project = root / "App.xcodeproj"
            project.mkdir()
            (project / "project.pbxproj").write_text(
                "XCRemoteSwiftPackageReference; repositoryURL = https://example.invalid/Remote;\n"
            )

            errors = AUDIT.remote_dependency_reference_errors(root)

            self.assertEqual(
                errors,
                [
                    "remote Xcode package reference is forbidden: App.xcodeproj/project.pbxproj",
                    "remote SwiftPM package reference is forbidden: Package.swift",
                ],
            )

    def test_nested_worktree_is_not_part_of_the_parent_repository_scope(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            (root / "Package.swift").write_text("// local manifest\n")
            nested = root / ".claude" / "worktrees" / "historical"
            nested.mkdir(parents=True)
            self.make_repository(nested)
            (nested / "Package.swift").write_text(
                '.package(url: "https://example.invalid/Historical.swift", from: "1.0.0")\n'
            )

            candidates = AUDIT.repository_candidate_paths(
                root, AUDIT.REMOTE_DEPENDENCY_FILENAMES
            )

            self.assertEqual(
                [path.relative_to(root).as_posix() for path in candidates], ["Package.swift"]
            )
            self.assertEqual(AUDIT.remote_dependency_reference_errors(root), [])

    def test_git_scope_failure_is_reported_as_a_closed_audit_error(self) -> None:
        with mock.patch.object(AUDIT.subprocess, "run", side_effect=OSError("git unavailable")):
            with self.assertRaisesRegex(
                AUDIT.RepositoryScopeError, "cannot enumerate repository audit scope with git"
            ):
                AUDIT.repository_candidate_paths(REPO_ROOT, AUDIT.REMOTE_DEPENDENCY_FILENAMES)

    def test_uninventoryed_direct_process_primitive_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = pathlib.Path(temporary_directory)
            self.make_repository(root)
            source = root / "Sources"
            source.mkdir()
            (source / "Unreviewed.swift").write_text("let child = Process()\n")

            errors = AUDIT.direct_automation_errors(root, [])

            self.assertEqual(
                errors,
                [
                    "uninventoryed direct automation primitive: "
                    "Sources/Unreviewed.swift process (observed 1, reviewed 0)"
                ],
            )


if __name__ == "__main__":
    unittest.main()
