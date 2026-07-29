#!/usr/bin/env python3
"""Passively enforce Open Island's per-action process-tree network boundary.

This observer invokes only fixed absolute macOS inspection tools.  It never
opens a socket itself.  It follows a root PID by PID plus ``lstart`` birth
identity, samples descendants by PPID, and asks ``lsof -i`` only about those
owned PIDs.  Consequently an already-running application merely focused by
Open Island is not in scope unless Open Island actually launches it as a
descendant.

The observer catches sockets that remain live for at least one sampling
interval.  It is deliberately paired with source policy and deterministic
fixtures that keep short-lived sockets open across several samples; macOS does
not expose a non-privileged, lossless historical socket-event stream to this
tool.  AF_UNIX sockets are not requested from lsof and remain permitted.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass


POLICY_VERSION = "round-10"
PS = "/bin/ps"
LSOF = "/usr/sbin/lsof"
DEFAULT_ALLOWED_CHILDREN = frozenset(
    {
        "/bin/ps",
        "/usr/sbin/lsof",
        "/usr/bin/pgrep",
        "/usr/bin/osascript",
        "/usr/bin/open",
    }
)
PROHIBITED_TOOL_NAMES = frozenset(
    {
        "curl", "wget", "ssh", "scp", "sftp", "ftp", "telnet", "nc", "ncat",
    }
)
REMOTE_ARGUMENT = re.compile(r"(?:https?|wss?|ftp|ssh)://", re.IGNORECASE)


@dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    ppid: int
    start_identity: str
    executable: str
    arguments: str

    def public_record(self) -> dict[str, object]:
        # Arguments may include local user data. They are inspected for policy
        # violations but intentionally never written to smoke evidence.
        return {
            "pid": self.pid,
            "ppid": self.ppid,
            "startIdentity": self.start_identity,
            "executable": self.executable,
        }


class ObservationError(RuntimeError):
    pass


def process_snapshot() -> dict[int, ProcessIdentity]:
    result = subprocess.run(
        [PS, "-axo", "pid=,ppid=,lstart=,command="],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise ObservationError("ps process snapshot failed")
    records: dict[int, ProcessIdentity] = {}
    for line in result.stdout.splitlines():
        fields = line.split(None, 8)
        if len(fields) < 8 or not fields[0].isdecimal() or not fields[1].isdecimal():
            continue
        pid, ppid = int(fields[0]), int(fields[1])
        arguments = fields[7] if len(fields) == 8 else fields[7] + " " + fields[8]
        records[pid] = ProcessIdentity(
            pid=pid,
            ppid=ppid,
            start_identity=" ".join(fields[2:7]),
            executable=arguments.split(maxsplit=1)[0],
            arguments=arguments,
        )
    return records


def descendants(root_pid: int, records: dict[int, ProcessIdentity]) -> list[ProcessIdentity]:
    children: dict[int, list[ProcessIdentity]] = {}
    for record in records.values():
        children.setdefault(record.ppid, []).append(record)
    discovered: list[ProcessIdentity] = []
    pending = [root_pid]
    seen: set[int] = set()
    while pending:
        pid = pending.pop()
        if pid in seen:
            continue
        seen.add(pid)
        record = records.get(pid)
        if record is None:
            continue
        discovered.append(record)
        pending.extend(child.pid for child in children.get(pid, ()))
    return sorted(discovered, key=lambda record: record.pid)


def ip_socket_records(pid: int) -> list[str]:
    result = subprocess.run(
        [LSOF, "-n", "-P", "-a", "-p", str(pid), "-i", "-Fn"],
        check=False,
        capture_output=True,
        text=True,
    )
    # lsof uses exit 1 when no selected files exist. Any other failure means
    # observation coverage is incomplete and must fail closed.
    if result.returncode not in (0, 1):
        raise ObservationError(f"lsof IP inspection failed for PID {pid}")
    return [line[1:] for line in result.stdout.splitlines() if line.startswith("n")]


def policy_violations(
    tree: list[ProcessIdentity], allowed_children: frozenset[str]
) -> list[dict[str, object]]:
    violations: list[dict[str, object]] = []
    for index, record in enumerate(tree):
        if index and record.executable not in allowed_children:
            violations.append(
                {"kind": "unallowlisted-descendant", "pid": record.pid, "executable": record.executable}
            )
        name = record.executable.rsplit("/", 1)[-1]
        argument_tool = next(
            (
                token.rsplit("/", 1)[-1]
                for token in record.arguments.split()
                if token.rsplit("/", 1)[-1] in PROHIBITED_TOOL_NAMES
            ),
            None,
        )
        if name in PROHIBITED_TOOL_NAMES or argument_tool:
            violations.append({"kind": "prohibited-network-tool", "pid": record.pid, "executable": record.executable})
        if REMOTE_ARGUMENT.search(record.arguments):
            violations.append({"kind": "remote-url-argument", "pid": record.pid, "executable": record.executable})
        for endpoint in ip_socket_records(record.pid):
            violations.append(
                {"kind": "ip-socket", "pid": record.pid, "executable": record.executable, "endpoint": endpoint}
            )
    return violations


def observe(args: argparse.Namespace) -> dict[str, object]:
    if args.duration <= 0 or args.interval <= 0 or args.interval > args.duration:
        raise ObservationError("duration and interval must be positive and interval cannot exceed duration")
    allowed_children = frozenset(DEFAULT_ALLOWED_CHILDREN | set(args.allow_child))
    deadline = time.monotonic() + args.duration
    snapshots: list[list[dict[str, object]]] = []
    violations: list[dict[str, object]] = []
    root_seen = False
    while True:
        records = process_snapshot()
        root = records.get(args.root_pid)
        if root is None:
            if not root_seen:
                raise ObservationError("root PID was absent before observation")
        elif root.start_identity != args.root_start_identity or root.executable != args.expected_root:
            raise ObservationError("root PID identity did not match the bound launch identity")
        else:
            root_seen = True
            tree = descendants(args.root_pid, records)
            snapshots.append([record.public_record() for record in tree])
            violations.extend(policy_violations(tree, allowed_children))
        if time.monotonic() >= deadline:
            break
        time.sleep(args.interval)
    if not root_seen:
        raise ObservationError("root PID was never observed with its bound identity")
    unique_violations = list({json.dumps(item, sort_keys=True): item for item in violations}.values())
    return {
        "policyVersion": POLICY_VERSION,
        "root": {
            "pid": args.root_pid,
            "startIdentity": args.root_start_identity,
            "executable": args.expected_root,
        },
        "sampling": {"durationSeconds": args.duration, "intervalSeconds": args.interval, "snapshotCount": len(snapshots)},
        "processTreeSnapshots": snapshots,
        "violations": unique_violations,
        "result": "PASS" if not unique_violations else "FAIL",
        "limitations": "Passive lsof sampling detects live IP sockets; static policy covers prohibited APIs and fixtures hold short-lived sockets across samples.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root-pid", type=int, required=True)
    parser.add_argument("--root-start-identity", required=True)
    parser.add_argument("--expected-root", required=True)
    parser.add_argument("--duration", type=float, default=1.2)
    parser.add_argument("--interval", type=float, default=0.05)
    parser.add_argument("--allow-child", action="append", default=[])
    args = parser.parse_args(argv)
    try:
        report = observe(args)
    except ObservationError as error:
        print(json.dumps({"policyVersion": POLICY_VERSION, "result": "ERROR", "error": str(error)}, sort_keys=True))
        return 2
    print(json.dumps(report, sort_keys=True))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
