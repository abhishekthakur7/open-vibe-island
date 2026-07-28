#!/usr/bin/env python3
"""Passive contract tests for the fixed smoke matrix runner.

These tests use only ``--dry-run`` and sourced helper functions replaced with
safe fakes. They never build, launch, capture, inspect a GUI, or write defaults.
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
RUNNER_PATH = REPO_ROOT / "scripts" / "smoke-all-scenarios.sh"
PRODUCTION_EXECUTABLE = "/Applications/Open Island.app/Contents/MacOS/OpenIslandApp"


class SmokeAllScenariosRunnerTests(unittest.TestCase):
    def production_proof_result(
        self,
        baseline_snapshot: str,
        after_snapshot: str,
        *,
        live: bool = True,
    ) -> tuple[int, str]:
        """Run only the sourced production-proof helpers against safe fakes."""

        harness = r'''
source "$RUNNER_PATH"
run_root_physical="/safe/run"
run_root_identity="safe:run"
LAST_WRITTEN_CONTENT=""
validate_directory_identity() { return 0; }
safe_write_content() {
    LAST_WRITTEN_CONTENT="$6"
    print -r -- "safe:file"
}
production_app_snapshot() { print -rn -- "$FAKE_SNAPSHOT"; }
production_app_identity_is_live() { [[ "$FAKE_LIVE" == "1" ]]; }

FAKE_SNAPSHOT="$BASELINE_SNAPSHOT"
record_production_app_baseline
FAKE_SNAPSHOT="$AFTER_SNAPSHOT"
if record_production_app_after; then
    print -r -- "PROOF_STATUS=PASS"
else
    print -r -- "PROOF_STATUS=FAIL"
fi
print -r -- "$LAST_WRITTEN_CONTENT"
'''
        environment = os.environ | {
            "SMOKE_ALL_SCENARIOS_TEST_LIBRARY": "1",
            "RUNNER_PATH": str(RUNNER_PATH),
            "BASELINE_SNAPSHOT": baseline_snapshot,
            "AFTER_SNAPSHOT": after_snapshot,
            "FAKE_LIVE": "1" if live else "0",
        }
        result = subprocess.run(
            ["zsh", "-c", harness],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        status_match = re.search(r"^PROOF_STATUS=(PASS|FAIL)$", result.stdout, re.M)
        self.assertIsNotNone(status_match, result.stdout)
        return (0 if status_match.group(1) == "PASS" else 1, result.stdout)

    def test_dry_run_lists_the_fixed_45_cell_plan_without_evidence_creation(self) -> None:
        evidence_parent = REPO_ROOT / "shots" / "after"
        before = sorted(evidence_parent.iterdir()) if evidence_parent.exists() else []

        result = subprocess.run(
            ["zsh", str(RUNNER_PATH), "--dry-run"],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        plan_lines = [
            line
            for line in result.stdout.splitlines()
            if re.match(r"^PLAN \d{2}/45 ", line)
        ]
        self.assertEqual(len(plan_lines), 45)
        self.assertEqual(plan_lines[0], "PLAN 01/45 theme=poured scenario=closed serial=true")
        self.assertEqual(plan_lines[-1], "PLAN 45/45 theme=halo scenario=emptyState serial=true")
        self.assertIn("DRY-RUN COMPLETE: 45 cells listed; 0 executed", result.stdout)
        after = sorted(evidence_parent.iterdir()) if evidence_parent.exists() else []
        self.assertEqual(after, before)

    def test_runner_records_passive_production_app_baseline_and_after_proof(self) -> None:
        source = RUNNER_PATH.read_text()

        self.assertIn(f'production_app_executable="{PRODUCTION_EXECUTABLE}"', source)
        self.assertIn("record_production_app_baseline()", source)
        self.assertIn("record_production_app_after()", source)
        self.assertIn("production-app-baseline.tsv", source)
        self.assertIn("production-app-after.tsv", source)
        self.assertIn("production_app_none_baseline_proof", source)
        self.assertIn("production_app_baseline_proof", source)
        self.assertIn("production_app_population_proof", source)
        self.assertIn("normalize_start_identity()", source)
        self.assertIn("if ! record_production_app_baseline; then", source)
        self.assertIn("record_production_app_after; then", source)
        self.assertNotIn("app.openisland.dev", source)
        self.assertNotIn("pkill", source)
        self.assertNotIn('open "/Applications/Open Island.app"', source)
        self.assertNotIn('open -a "Open Island"', source)

    def test_production_proof_exactly_matches_empty_single_and_multiple_populations(self) -> None:
        executable = PRODUCTION_EXECUTABLE
        cases = {
            "zero": ("", "", 0),
            "single-leading-padding": (
                f"101\t   Mon Jul 28 09:01:02 2026\t{executable}\n",
                f"101\tMon   Jul 28 09:01:02 2026\t{executable}\n",
                0,
            ),
            "multiple": (
                f"101\tMon Jul 28 09:01:02 2026\t{executable}\n"
                f"202\tTue Jul 29 10:02:03 2026\t{executable}\n",
                f"202\t  Tue Jul 29 10:02:03 2026\t{executable}\n"
                f"101\tMon Jul 28 09:01:02 2026\t{executable}\n",
                0,
            ),
            "new-from-empty": ("", f"303\tWed Jul 30 11:03:04 2026\t{executable}\n", 1),
            "missing": (f"101\tMon Jul 28 09:01:02 2026\t{executable}\n", "", 1),
            "pid-reuse": (
                f"101\tMon Jul 28 09:01:02 2026\t{executable}\n",
                f"101\tTue Jul 29 10:02:03 2026\t{executable}\n",
                1,
            ),
            "new-in-multiple": (
                f"101\tMon Jul 28 09:01:02 2026\t{executable}\n"
                f"202\tTue Jul 29 10:02:03 2026\t{executable}\n",
                f"101\tMon Jul 28 09:01:02 2026\t{executable}\n"
                f"202\tTue Jul 29 10:02:03 2026\t{executable}\n"
                f"303\tWed Jul 30 11:03:04 2026\t{executable}\n",
                1,
            ),
        }
        for name, (baseline, after, expected_status) in cases.items():
            with self.subTest(case=name):
                actual_status, output = self.production_proof_result(baseline, after)
                self.assertEqual(actual_status, expected_status, output)
                self.assertIn("production_app_population_count_proof", output)
        _, reuse_output = self.production_proof_result(
            f"101\tMon Jul 28 09:01:02 2026\t{executable}\n",
            f"101\tTue Jul 29 10:02:03 2026\t{executable}\n",
        )
        self.assertIn("production_app_population_proof\t101\tIDENTITY_CHANGED", reuse_output)

    def test_production_proof_rejects_failed_live_identity_after_matching_snapshot(self) -> None:
        executable = PRODUCTION_EXECUTABLE
        snapshot = f"101\tMon Jul 28 09:01:02 2026\t{executable}\n"
        actual_status, output = self.production_proof_result(snapshot, snapshot, live=False)
        self.assertEqual(actual_status, 1, output)
        self.assertIn("production_app_baseline_proof\t101", output)
        self.assertIn("\tFAIL", output)

    def test_cleanup_hazards_are_terminal_unsafe_but_do_not_skip_later_steps(self) -> None:
        source = RUNNER_PATH.read_text()
        cleanup_start = source.index("cleanup() {")
        cleanup_end = source.index("\n}\n\nfinish()", cleanup_start)
        cleanup_block = source[cleanup_start:cleanup_end]
        for reason in (
            "owned app/launcher termination failed during cleanup",
            "owned launcher termination failed during cleanup",
            "exact private staging cleanup failed during cleanup",
            "passive post-run process inventory could not be written",
            "production app baseline/after proof failed",
            "harness defaults restore/readback failed during cleanup",
        ):
            self.assertIn(f'mark_terminal_unsafe "{reason}', cleanup_block)
        self.assertLess(
            cleanup_block.index("passive post-run process inventory"),
            cleanup_block.index("restore_harness_defaults"),
        )
        self.assertIn("defaults read OpenIslandApp appearance.island.v8.theme", source)
        self.assertIn("defaults read OpenIslandApp overlay.display.preference", source)
        self.assertIn("trap - EXIT", source)
        self.assertIn("return 0", source[source.index("mark_terminal_unsafe() {"):source.index("\n}\n\ncapture_launcher_identity")])

    def test_initialization_traps_cover_baseline_run_root_and_manifest_setup(self) -> None:
        source = RUNNER_PATH.read_text()
        main_start = source.index("# Real-run main")
        trap_start = source.index("trap 'finish $?\' EXIT", main_start)
        baseline_start = source.index("capture_production_app_baseline || {", main_start)
        run_root_start = source.index("create_fresh_run_root", main_start)
        manifest_start = source.index("write_runner_manifest", main_start)

        self.assertLess(trap_start, baseline_start)
        self.assertLess(trap_start, run_root_start)
        self.assertLess(trap_start, manifest_start)
        self.assertIn("trap 'finish 130' INT", source[trap_start:baseline_start])
        self.assertIn("trap 'finish 143' TERM", source[trap_start:baseline_start])
        self.assertIn("trap 'finish 129' HUP", source[trap_start:baseline_start])

        harness = r'''
source "$RUNNER_PATH"
cleanup() { print -r -- "CLEANUP_CALLED"; }
finish 143
'''
        result = subprocess.run(
            ["zsh", "-c", harness],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
            env=os.environ | {
                "SMOKE_ALL_SCENARIOS_TEST_LIBRARY": "1",
                "RUNNER_PATH": str(RUNNER_PATH),
            },
        )
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertEqual(result.stdout.strip(), "CLEANUP_CALLED")

    def test_missing_run_root_still_performs_live_proof_and_is_terminal_unsafe(self) -> None:
        harness = r'''
source "$RUNNER_PATH"
run_root_physical="/safe/missing-run-root"
run_root_identity="safe:missing"
production_app_baseline_observed=true
production_app_baseline_pids=()
production_app_baseline_start_identities=()
production_app_baseline_count=0
run_root_available_for_evidence() { return 1; }
production_app_snapshot() {
    print -u2 -r -- "LIVE_SNAPSHOT_EXECUTED"
    print -rn -- "$FAKE_SNAPSHOT"
}
safe_write_content() {
    print -u2 -r -- "UNTRUSTED_WRITE_ATTEMPTED"
    return 1
}
if record_production_app_after; then
    print -r -- "PROOF_STATUS=PASS"
else
    print -r -- "PROOF_STATUS=FAIL"
fi
print -r -- "TERMINAL_UNSAFE=$terminal_unsafe"
'''
        result = subprocess.run(
            ["zsh", "-c", harness],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
            env=os.environ | {
                "SMOKE_ALL_SCENARIOS_TEST_LIBRARY": "1",
                "RUNNER_PATH": str(RUNNER_PATH),
                "FAKE_SNAPSHOT": "",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PROOF_STATUS=FAIL", result.stdout)
        self.assertIn("TERMINAL_UNSAFE=true", result.stdout)
        self.assertIn("LIVE_SNAPSHOT_EXECUTED", result.stderr)
        self.assertNotIn("UNTRUSTED_WRITE_ATTEMPTED", result.stderr)

    def test_cleanup_classifies_missing_run_root_and_does_not_skip_proof(self) -> None:
        harness = r'''
source "$RUNNER_PATH"
cleanup_done=false
terminal_unsafe=false
run_root_physical="/safe/missing-run-root"
run_root_identity="safe:missing"
run_root_available_for_evidence() { return 1; }
record_process_inventory() { print -r -- "INVENTORY_CALLED"; return 0; }
record_production_app_after() { print -r -- "PROOF_CALLED"; return 1; }
restore_harness_defaults() { print -r -- "DEFAULTS_RESTORE_CALLED"; return 0; }
if cleanup; then
    print -r -- "CLEANUP_STATUS=PASS"
else
    print -r -- "CLEANUP_STATUS=FAIL"
fi
print -r -- "TERMINAL_UNSAFE=$terminal_unsafe"
'''
        result = subprocess.run(
            ["zsh", "-c", harness],
            cwd=REPO_ROOT,
            check=False,
            capture_output=True,
            text=True,
            env=os.environ | {
                "SMOKE_ALL_SCENARIOS_TEST_LIBRARY": "1",
                "RUNNER_PATH": str(RUNNER_PATH),
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("INVENTORY_CALLED", result.stdout)
        self.assertIn("PROOF_CALLED", result.stdout)
        self.assertIn("DEFAULTS_RESTORE_CALLED", result.stdout)
        self.assertIn("CLEANUP_STATUS=FAIL", result.stdout)
        self.assertIn("TERMINAL_UNSAFE=true", result.stdout)
        self.assertIn("passive post-run process inventory could not be written", result.stderr)

    def test_semantic_validator_failure_is_a_regular_cell_failure_and_stops_the_run(self) -> None:
        source = RUNNER_PATH.read_text()
        validator_start = source.index('validate-harness-artifacts.py" \\')
        validator_end = source.index("\n    }\n\n    validation_content", validator_start)
        validator_block = source[validator_start:validator_end]
        self.assertIn("semantic validation failed", validator_block)
        self.assertNotIn("mark_terminal_unsafe", validator_block)

        failure_start = source.index('echo "FAILED: $label" >&2')
        failure_end = source.index("\n    done", failure_start)
        failure_block = source[failure_start:failure_end]
        self.assertIn('if [[ "$terminal_unsafe" == true ]]; then', failure_block)
        self.assertIn("return 1", failure_block)


if __name__ == "__main__":
    unittest.main()
