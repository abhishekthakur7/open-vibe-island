#!/usr/bin/env python3
"""Deterministic fixtures for the passive runtime process-tree observer."""

from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import socket
import subprocess
import sys
import tempfile
import time
import unittest


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
OBSERVER_PATH = REPO_ROOT / "scripts" / "observe-runtime-network.py"
SPEC = importlib.util.spec_from_file_location("observe_runtime_network", OBSERVER_PATH)
assert SPEC is not None and SPEC.loader is not None
OBSERVER = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = OBSERVER
SPEC.loader.exec_module(OBSERVER)


class RuntimeNetworkObserverTests(unittest.TestCase):
    def root_identity(self, process: subprocess.Popen[str]) -> tuple[str, str]:
        for _ in range(40):
            record = OBSERVER.process_snapshot().get(process.pid)
            if record is not None:
                return record.start_identity, record.executable
            time.sleep(0.025)
        self.fail("fixture root was never visible to ps")

    def observe_process(self, process: subprocess.Popen[str]) -> tuple[int, dict[str, object]]:
        start_identity, executable = self.root_identity(process)
        result = subprocess.run(
            [
                sys.executable,
                str(OBSERVER_PATH),
                "--root-pid", str(process.pid),
                "--root-start-identity", start_identity,
                "--expected-root", executable,
                "--duration", "0.35", "--interval", "0.03",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertTrue(result.stdout, result.stderr)
        return result.returncode, json.loads(result.stdout)

    def fixture(self, body: str) -> subprocess.Popen[str]:
        return subprocess.Popen([sys.executable, "-c", body], text=True)

    def test_af_unix_socket_is_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            socket_path = pathlib.Path(temporary_directory) / "bridge.sock"
            body = (
                "import socket,time; s=socket.socket(socket.AF_UNIX); "
                f"s.bind({str(socket_path)!r}); time.sleep(1)"
            )
            process = self.fixture(body)
            try:
                status, report = self.observe_process(process)
            finally:
                process.terminate(); process.wait(timeout=2)
        self.assertEqual(status, 0, report)
        self.assertEqual(report["result"], "PASS")

    def test_ip_socket_fixture_fails(self) -> None:
        process = self.fixture(
            "import socket,time; s=socket.socket(socket.AF_INET); s.bind(('127.0.0.1', 0)); s.listen(); time.sleep(1)"
        )
        try:
            status, report = self.observe_process(process)
        finally:
            process.terminate(); process.wait(timeout=2)
        self.assertEqual(status, 1, report)
        self.assertIn("ip-socket", {item["kind"] for item in report["violations"]})

    def test_remote_url_fixture_fails_without_network_io(self) -> None:
        process = self.fixture("import time; time.sleep(1)")
        try:
            # The argument is intentionally inert: the observer sees a remote
            # request shape but the fixture never resolves or contacts it.
            process.terminate(); process.wait(timeout=2)
            process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(1)", "https://example.invalid"], text=True)
            status, report = self.observe_process(process)
        finally:
            process.terminate(); process.wait(timeout=2)
        self.assertEqual(status, 1, report)
        self.assertIn("remote-url-argument", {item["kind"] for item in report["violations"]})

    def test_named_network_tool_fixture_fails_without_network_io(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            tool = pathlib.Path(temporary_directory) / "curl"
            tool.write_text("#!/bin/sh\nsleep 1\n")
            tool.chmod(0o700)
            process = subprocess.Popen([str(tool)], text=True)
            try:
                status, report = self.observe_process(process)
            finally:
                process.terminate(); process.wait(timeout=2)
        self.assertEqual(status, 1, report)
        self.assertIn("prohibited-network-tool", {item["kind"] for item in report["violations"]})

    def test_descendant_ip_socket_fixture_fails(self) -> None:
        child = "import socket,time; s=socket.socket(socket.AF_INET); s.bind(('127.0.0.1', 0)); s.listen(); time.sleep(1)"
        process = self.fixture(f"import subprocess,sys,time; subprocess.Popen([sys.executable, '-c', {child!r}]); time.sleep(1)")
        try:
            status, report = self.observe_process(process)
        finally:
            process.terminate(); process.wait(timeout=2)
        self.assertEqual(status, 1, report)
        self.assertIn("ip-socket", {item["kind"] for item in report["violations"]})

    def test_unrelated_process_is_not_attributed_to_observed_root(self) -> None:
        unrelated = self.fixture(
            "import socket,time; s=socket.socket(socket.AF_INET); s.bind(('127.0.0.1', 0)); s.listen(); time.sleep(1)"
        )
        root = self.fixture("import time; time.sleep(1)")
        try:
            status, report = self.observe_process(root)
        finally:
            root.terminate(); root.wait(timeout=2)
            unrelated.terminate(); unrelated.wait(timeout=2)
        self.assertEqual(status, 0, report)
        self.assertEqual(report["result"], "PASS")


if __name__ == "__main__":
    unittest.main()
