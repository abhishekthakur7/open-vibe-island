#!/usr/bin/env python3

from __future__ import annotations

import binascii
import importlib.util
import json
import pathlib
import re
import shlex
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib


REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPO_ROOT / "scripts" / "validate-harness-artifacts.py"
RUNNER_PATH = REPO_ROOT / "scripts" / "smoke-all-scenarios.sh"
FRESH_FLIGHT_DECK_SESSION_LIST_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-023316-5F1D9909-2DC3-419B-8B41-66B3ED152BA7"
    / "flightDeck-sessionList/report.json"
)
FRESH_FLIGHT_DECK_APPROVAL_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-024241-E6A64B8D-E22B-43E1-9A70-F1626D4909EF"
    / "flightDeck-approvalCard/report.json"
)
FRESH_FLIGHT_DECK_DIFF_APPROVAL_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-030727-31B76852-E558-4160-B91C-EB7C6AC214D4"
    / "flightDeck-diffApprovalCard/report.json"
)
FRESH_FLIGHT_DECK_INTERRUPTED_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-031634-0C660081-C8D6-44B2-B097-EB280A441420"
    / "flightDeck-completedInterrupted/report.json"
)
FRESH_FLIGHT_DECK_USAGE_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-033024-6EA31EB6-1C01-42E1-A7A2-B5CB35C740C2"
    / "flightDeck-usageMeters/report.json"
)
PRESERVED_POURED_USAGE_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-033024-6EA31EB6-1C01-42E1-A7A2-B5CB35C740C2"
    / "poured-usageMeters/report.json"
)
FRESH_HALO_EXPANDED_SUBAGENTS_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-121846-0D5A74A5-26B2-4CFD-BC14-E947B90169D8"
    / "halo-subagentsExpanded/report.json"
)
BROKEN_HALO_EXPANDED_SUBAGENTS_REPORT = (
    REPO_ROOT
    / "shots/after/matrix-20260728-120552-48C98560-8863-44F6-BB2E-7BC04B074767"
    / "halo-subagentsExpanded/report.json"
)

SPEC = importlib.util.spec_from_file_location("validate_harness_artifacts", VALIDATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)

EXPECTED_HEIGHT_RANGES = {
    "closed": (175, 240),
    "sessionList": (560, 820),
    "approvalCard": (350, 520),
    "questionCard": (400, 800),
    "completionCard": (250, 520),
    "longCompletionCard": (380, 600),
    "diffApprovalCard": (500, 780),
    "codexApprovalCard": (280, 520),
    "multiQuestionCard": (400, 930),
    "subagentsCard": (450, 850),
    "subagentsExpanded": (400, 900),
    "completedInterrupted": (240, 540),
    "completedFailed": (240, 540),
    "usageMeters": (560, 820),
    "emptyState": (260, 450),
}

EXPECTED_WIDTH_RANGES = {
    "poured": (610, 630),
    "flightDeck": (566, 586),
    "halo": (610, 630),
}

EXPECTED_SCREEN_PROTECTED_SCENARIOS = frozenset(EXPECTED_HEIGHT_RANGES) - {"closed"}

EXPECTED_USAGE_METER_SEMANTICS = {
    "poured": (
        "Claude 5h 34%, resets in 2h 9m",
        "Claude 7d 78%, resets in 3d 3h",
        "Codex 7d 92%, resets in 18h 59m",
    ),
    "flightDeck": (
        "Cl 5h 34%, resets in 2h 9m",
        "Cl 7d 78%, resets in 3d 3h",
        "Cx 7d 92%, resets in 18h 59m",
    ),
    "halo": (
        "Claude 5h 34%, resets in 2h 9m",
        "Claude 7d 78%, resets in 3d 3h",
        "Codex 7d 92%, resets in 18h 59m",
    ),
}

FLIGHT_DECK_USAGE_GROUP_ENTRIES = (
    "Cl 5h 34%, resets in 2h 9m · Cl 7d 78%, resets in 3d 3h",
    "Cx 7d 92%, resets in 18h 59m",
)

EXPECTED_GOLDEN_PNG_DIMENSIONS = {
    (
        "Tests/OpenIslandAppTests/__Snapshots__/PouredConformanceSnapshotTests/"
        "testPermissionCommandHero.poured-E1-permission-command-notch.png"
    ): (1080, 818),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/ThemeSnapshotHarnessTests/"
        "testFlightDeckPermissionMasterWarningNotch.flightdeck-permission-master-warning-notch.png"
    ): (1080, 848),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/HaloConformanceSnapshotTests/"
        "testPermissionCommandHero.halo-E1-permission-command-notch.png"
    ): (1080, 864),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/PouredConformanceSnapshotTests/"
        "testQuestionHero.poured-F-question-notch.png"
    ): (1080, 844),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/ThemeSnapshotHarnessTests/"
        "testFlightDeckQuestionMasterCautionNotch.flightdeck-question-master-caution-notch.png"
    ): (1080, 1338),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/HaloConformanceSnapshotTests/"
        "testQuestionHero.halo-F-question-notch.png"
    ): (1080, 1048),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/PouredConformanceSnapshotTests/"
        "testExpandedDetailAndSubagents.poured-D-G-subagents-notch.png"
    ): (1080, 1086),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/ThemeSnapshotHarnessTests/"
        "testFlightDeckEngineClusterNotch.flightdeck-engine-cluster-notch.png"
    ): (1080, 1256),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/HaloConformanceSnapshotTests/"
        "testExpandedDetailAndSubagents.halo-D-G-subagents-notch.png"
    ): (1080, 1010),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/PouredConformanceSnapshotTests/"
        "testUsageMeters.poured-I-usage-meters-notch.png"
    ): (1080, 1776),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/HaloConformanceSnapshotTests/"
        "testUsageMeters.halo-I-usage-meters-notch.png"
    ): (1080, 1756),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/PouredConformanceSnapshotTests/"
        "testEmptyState.poured-J-empty-notch.png"
    ): (1080, 472),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/ThemeSnapshotHarnessTests/"
        "testFlightDeckEmptyNominalNotch.flightdeck-empty-nominal-notch.png"
    ): (1080, 462),
    (
        "Tests/OpenIslandAppTests/__Snapshots__/HaloConformanceSnapshotTests/"
        "testEmptyState.halo-J-empty-notch.png"
    ): (1080, 496),
}


def png_dimensions(path: pathlib.Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    if header[12:16] != b"IHDR":
        raise ValueError(f"{path} has no leading IHDR")
    return struct.unpack(">II", header[16:24])


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", binascii.crc32(kind + payload) & 0xFFFFFFFF)
    )


def write_png(path: pathlib.Path, width: int, height: int) -> None:
    row = b"\0" + (b"\0" * (width * 3))
    payload = zlib.compress(row * height)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + png_chunk(b"IDAT", payload)
        + png_chunk(b"IEND", b"")
    )


def base_sessions() -> list[dict]:
    tools = ["Claude Code", "Codex", "Gemini", "Cursor"]
    return [
        {
            "id": f"session-{index}",
            "phase": "running",
            "summary": f"Fixture session {index}",
            "title": f"{tools[index % len(tools)]} · fixture-{index}",
        }
        for index in range(9)
    ]


def scenario_case(scenario: str, theme: str = "poured") -> dict:
    minimum, maximum = EXPECTED_HEIGHT_RANGES.get(scenario, (175, 240))
    width_minimum, width_maximum = EXPECTED_WIDTH_RANGES[theme]
    case = {
        "scenario": scenario,
        "theme": theme,
        "notchStatus": "closed" if scenario == "closed" else "opened",
        "islandSurface": "sessionList",
        "frame": {
            "width": (width_minimum + width_maximum) // 2,
            "height": (minimum + maximum) // 2,
        },
        "visibleHeight": 1200,
        "sessionCount": 9,
        "liveSessionCount": 9,
        "attentionCount": 0,
        "selectedSessionID": None,
        "sessions": base_sessions(),
        "labels": set(),
        "buttonLabels": set(),
        "buttonAX": {},
        "textValues": set(),
        "roles": set(),
    }

    def select(identifier: str, phase: str, summary: str) -> None:
        case["selectedSessionID"] = identifier
        case["sessions"][0] = {
            "id": identifier,
            "phase": phase,
            "summary": summary,
            "title": "Fixture selected session",
        }

    def show_all() -> None:
        case["buttonLabels"].add("Show all 9 sessions")

    if scenario == "closed":
        case["textValues"].add("9 sessions")
    elif scenario == "sessionList":
        case["buttonLabels"].update(
            {
                f"Codex, fixture-{index}, "
                f"{'running' if index == 1 else 'completed'}, "
                f"{index} minutes ago"
                for index in range(1, 10)
            }
        )
        if theme == "poured":
            case["textValues"].update(
                {
                    "SESSIONS, 9, 1, run, 1, done, 7, idle",
                    "All quiet elsewhere · 7 idle",
                }
            )
        elif theme == "flightDeck":
            case["textValues"].update(
                {
                    "Sessions 0 Attn, 1 Run, 1 Done, 7 Idle",
                    "BRIDGE LINK, NO LINK, 9 SESSIONS",
                }
            )
        else:
            case["textValues"].update(
                {
                    "9 total, 1 running, 1 done, 7 idle",
                    "9 sessions · 0 need you",
                }
            )
    elif scenario == "approvalCard":
        select(
            "session-approval",
            "waitingForApproval",
            "Allow exec_command to rewrite SettingsView.swift?",
        )
        case["islandSurface"] = "sessionList:actionable(session-approval)"
        case["buttonLabels"].update(
            {
                "Allow",
                "Deny",
                "Claude Code, open-island, waiting for permission, 20 seconds ago",
            }
        )
        raw_command = (
            "head -5000 /Users/wangruobing/Personal/claude-research/"
            "extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt"
        )
        if theme == "poured":
            case["textValues"].update(
                {
                    raw_command,
                    "Allow exec_command to rewrite SettingsView.swift?",
                }
            )
        elif theme == "flightDeck":
            case["textValues"].update(
                {
                    "PERMISSION REQUIRED",
                    "HELD, 0m 20s",
                    "Opus 4.8 · feat/approval-flow",
                    f"$ {raw_command}",
                    "Sources/OpenIslandApp/Views/SettingsView.swift",
                }
            )
        else:
            case["textValues"].update(
                {
                    "Permission needed",
                    "Allow exec_command to rewrite SettingsView.swift?",
                    "Opus 4.8",
                    raw_command,
                }
            )
        show_all()
    elif scenario == "questionCard":
        select("session-question", "waitingForAnswer", "这个提醒态需要自动收起吗？")
        case["islandSurface"] = "sessionList:actionable(session-question)"
        case["labels"].add("Which authentication method should we use?")
        case["buttonLabels"].update(
            {"JWT tokens", "Session cookies", "OAuth 2.0", "Other", "Submit Answers"}
        )
        case["textValues"].add("1–4 select · Enter submits · Esc closes")
        show_all()
    elif scenario == "completionCard":
        select("session-completion", "completed", "DEV page complete")
        case["islandSurface"] = "sessionList:actionable(session-completion)"
        jump = {
            "poured": "Jump to terminal",
            "flightDeck": "Jump",
            "halo": "Jump · Ghostty",
        }[theme]
        case["buttonLabels"].update({jump, "Transcript, open-island"})
        case["textValues"].add("Plan 文件已写好。你的 hooks 触发情况如何？")
        show_all()
    elif scenario == "longCompletionCard":
        select("session-completion-long", "completed", "README complete")
        case["islandSurface"] = "sessionList:actionable(session-completion-long)"
        jump = {
            "poured": "Jump to terminal",
            "flightDeck": "Jump",
            "halo": "Jump · Ghostty",
        }[theme]
        case["buttonLabels"].update({jump, "Transcript, open-island"})
        case["textValues"].add("README.md committed from an isolated worktree")
        show_all()
    elif scenario == "diffApprovalCard":
        select(
            "fixture-permission-diff",
            "waitingForApproval",
            "Claude wants to edit AGENTS.md.",
        )
        case["islandSurface"] = "sessionList:actionable(fixture-permission-diff)"
        case["buttonLabels"].update(
            {
                "Allow",
                "Deny",
                "Claude Code, open-vibe-island, waiting for permission, 11 seconds ago",
                "Yes, allow writing to AGENTS.md/ from this project",
            }
        )
        case["textValues"].update(
            {
                "## Verification",
                "After making changes, run swift build and confirm it succeeds before moving on.",
                "After making changes, run swift build and swift test and confirm both succeed before moving on.",
                "Capture a harness smoke run whenever the change affects rendered UI.",
                "Summarize what changed once the round is done.",
                "Summarize what changed once the round is done, calling out any verification gaps.",
                "Commit the round on the feature branch before stopping.",
                "+",
                "−",
            }
        )
        if theme == "poured":
            case["textValues"].update(
                {
                    "Tool permission requested",
                    "Claude wants to edit AGENTS.md.",
                    "Updated",
                    "+3",
                    "−2",
                    "Auto-collapses in 10s · hover pauses",
                }
            )
        elif theme == "flightDeck":
            case["textValues"].update(
                {
                    "PERMISSION REQUIRED",
                    "HELD, 0m 11s",
                    "Opus 4.8 · main",
                    "Claude wants to edit AGENTS.md.",
                    "AGENTS.md",
                    "UPDATED",
                    "+3",
                    "−2",
                }
            )
        else:
            case["textValues"].update(
                {
                    "Approve file edit",
                    "Claude wants to edit AGENTS.md.",
                    "Opus 4.8",
                    "AGENTS.md · 5 changed",
                }
            )
        case["roles"].add("AXScrollArea")
        show_all()
    elif scenario == "codexApprovalCard":
        select(
            "fixture-codex-terminal-approval",
            "waitingForApproval",
            "Codex wants to run: git push origin main",
        )
        case["islandSurface"] = (
            "sessionList:actionable(fixture-codex-terminal-approval)"
        )
        case["buttonLabels"].add(
            "Codex, open-vibe-island, waiting for permission, 16 seconds ago"
        )
        if theme == "poured":
            case["buttonLabels"].add("Jump to Codex to approve")
            case["textValues"].update(
                {
                    "Tool permission requested",
                    "$ git push origin main",
                    "Codex wants to run: git push origin main",
                    "Codex approves in-app. Open the pane to allow or deny there.",
                    "Auto-collapses in 10s · hover pauses",
                }
            )
        elif theme == "flightDeck":
            case["buttonLabels"].add("Jump to Codex")
            case["textValues"].update(
                {
                    "PERMISSION REQUIRED",
                    "HELD, 0m 16s",
                    "$ git push origin main",
                    "~/Developer/open-vibe-island",
                    "Codex approves in-app. Open the pane to allow or deny there.",
                }
            )
        else:
            case["buttonLabels"].add("Jump to Codex")
            case["textValues"].update(
                {
                    "Approval waiting",
                    "Codex wants to run: git push origin main",
                    "git push origin main",
                    "Codex approvals happen inside the app. Jump to Codex to review this request.",
                }
            )
        show_all()
    elif scenario == "multiQuestionCard":
        select(
            "fixture-question-multi",
            "waitingForAnswer",
            "Claude needs two decisions before wiring the bridge.",
        )
        case["islandSurface"] = "sessionList:actionable(fixture-question-multi)"
        case["labels"].update({"Auth", "Which auth method should the bridge use?"})
        action_title = {
            "poured": "Submit & next",
            "flightDeck": "Submit Answers",
            "halo": "Next",
        }[theme]
        case["buttonLabels"].add(action_title)
        case["buttonAX"][action_title] = {
            "identifier": VALIDATOR.MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER,
            "title": None,
            "description": action_title,
            "accessibleName": action_title,
            "accessibleNameSource": "AXDescription",
            "enabled": False,
        }
        if theme in {"poured", "halo"}:
            case["labels"].add("Question 1 of 2")
            case["textValues"].add("1–3 select · Enter submits · Esc closes")
        else:
            case["labels"].update(
                {"Scope", "Which surfaces should the bridge expose?"}
            )
            case["textValues"].add("1–7 select · Enter submits · Esc closes")
        show_all()
    elif scenario == "subagentsCard":
        select("fixture-subagents-tasks", "running", "Coordinating rollout")
        case["buttonLabels"].add(
            "Claude Code, open-vibe-island, running, 6 seconds ago"
        )
        case["textValues"].add("3 subagents, 2 of 5 tasks completed")
    elif scenario == "subagentsExpanded":
        select("fixture-subagents-tasks", "running", "Coordinating rollout")
        case["buttonLabels"].add(
            "Claude Code, open-vibe-island, running, 6 seconds ago"
        )
        case["textValues"].update(
            {
                "Map the theme token surface",
                "Port the session rows to Poured 2.0",
                "Sequence the Flight Deck follow-ups",
                "Header + meters + scaffold",
                "2 of 5",
            }
        )
        if theme == "halo":
            case["extraAXNodes"] = [
                {
                    "role": "AXUnknown",
                    "label": description,
                    "description": description,
                    "children": [],
                }
                for description in VALIDATOR.HALO_EXPANDED_SUBAGENT_NATIVE_DESCRIPTIONS
            ]
    elif scenario == "completedInterrupted":
        select(
            "fixture-completed-interrupted",
            "completed",
            "Stopped mid-refactor before the extraction finished.",
        )
        case["islandSurface"] = (
            "sessionList:actionable(fixture-completed-interrupted)"
        )
        jump = {
            "poured": "Jump to terminal",
            "flightDeck": "Jump",
            "halo": "Jump · Ghostty",
        }[theme]
        case["buttonLabels"].update({jump, "Transcript, niche-radar"})
        case["textValues"].update(
            {
                "INTERRUPTED" if theme == "flightDeck" else "Interrupted",
                "Interrupted while moving the scorer — no files were left half-written.",
            }
        )
        show_all()
    elif scenario == "completedFailed":
        select(
            "fixture-completed-failed",
            "completed",
            "Build failed: 2 errors in BridgeServer.swift.",
        )
        case["islandSurface"] = "sessionList:actionable(fixture-completed-failed)"
        case["buttonLabels"].add(
            {
                "poured": "Jump to terminal",
                "flightDeck": "Jump",
                "halo": "Jump · Ghostty",
            }[theme]
        )
        case["textValues"].update(
            {
                "FAILED" if theme == "flightDeck" else "Failed",
                "swift build exited non-zero — BridgeServer.swift has two type errors I could not resolve.",
            }
        )
        show_all()
    elif scenario == "usageMeters":
        if theme == "flightDeck":
            case["labels"].update(FLIGHT_DECK_USAGE_GROUP_ENTRIES)
        else:
            case["labels"].update(EXPECTED_USAGE_METER_SEMANTICS[theme])
    elif scenario == "emptyState":
        case.update(
            {
                "sessionCount": 0,
                "liveSessionCount": 0,
                "attentionCount": 0,
                "selectedSessionID": None,
                "sessions": [],
            }
        )
        if theme == "poured":
            case["textValues"].update(
                {
                    "No open terminal sessions",
                    "Start a coding agent in your terminal",
                }
            )
        elif theme == "flightDeck":
            case["textValues"].update(
                {
                    "ALL SYSTEMS NOMINAL",
                    "No active sessions. Open Island is watching the bridge — the moment an agent needs approval, asks a question, or finishes, a lamp lights here.",
                    "BRIDGE LINK · NO LINK · 0 SESSIONS",
                }
            )
            case["staticTextValues"] = set(case["textValues"])
        else:
            case["textValues"].update(
                {
                    "All quiet",
                    "No active agent sessions. Open Island is watching your terminals and IDEs",
                    "Monitoring",
                }
            )
    return case


def write_case(directory: pathlib.Path, case: dict) -> pathlib.Path:
    timeline = [
        {"name": name}
        for name in (
            "applicationDidFinishLaunching",
            "bootstrapStarted",
            "modelStarted",
            "bootstrapCompleted",
            "overlayPresented",
            "bridgeSkipped",
            "captureScheduled",
            "captureStarted",
        )
    ]
    (directory / "timeline.json").write_text(json.dumps(timeline))
    (directory / "runtime.log").write_text("fixture runtime log\n")

    children = []
    for label in sorted(case["buttonLabels"]):
        button = {"role": "AXButton", "label": label, "children": []}
        button.update(case.get("buttonAX", {}).get(label, {}))
        children.append(button)
    usage_meter_labels = case.get("usageMeterLabels", case["labels"])
    usage_meter_role = case.get("usageMeterRole", "AXUnknown")
    for label in sorted(usage_meter_labels):
        children.append(
            {
                "role": (
                    usage_meter_role
                    if case["scenario"] == "usageMeters"
                    else "AXStaticText"
                ),
                "label": label,
                "children": [],
            }
        )
    for value in sorted(case.get("staticTextValues", case["textValues"])):
        children.append(
            {"role": "AXStaticText", "value": value, "children": []}
        )
    children.extend(case.get("extraAXNodes", []))
    for role in sorted(case["roles"]):
        children.append({"role": role, "children": []})
    if case.get("emptyAX"):
        children = []
    (directory / "overlay.ax.json").write_text(
        json.dumps({"role": "AXWindow", "children": children})
    )

    frame = case["frame"]
    pixel_width = int(frame["width"] * 2 + case.get("pngWidthDelta", 0))
    pixel_height = int(frame["height"] * 2 + case.get("pngHeightDelta", 0))
    write_png(directory / "overlay.png", pixel_width, pixel_height)

    visible_frame = {"width": 1512}
    if "visibleHeight" in case:
        visible_frame["height"] = case["visibleHeight"]
    report = {
        "scenario": case["scenario"],
        "presentOverlay": True,
        "startedBridge": False,
        "launchToCaptureSeconds": 1.5,
        "runtime": {
            "timelinePath": "timeline.json",
            "logPath": "runtime.log",
            "eventCount": len(timeline),
            "launchCompleted": True,
            "milestones": timeline,
            "timings": {
                "bootstrapSeconds": 0.4,
                "captureScheduledSeconds": 0.8,
                "captureStartedSeconds": 1.2,
                "overlayPresentedSeconds": 0.6,
                "launchToCaptureSeconds": 1.5,
            },
            "latestMessage": "fixture capture started",
        },
        "windows": [
            {
                "kind": "overlay",
                "frame": frame,
                "imagePath": "overlay.png",
                "accessibilityPath": "overlay.ax.json",
                "accessibilitySummary": {
                    "labels": sorted(case.get("summaryLabels", case["labels"])),
                    "buttonLabels": sorted(
                        case.get("summaryButtonLabels", case["buttonLabels"])
                    ),
                    "textValues": sorted(
                        case.get("summaryTextValues", case["textValues"])
                    ),
                },
            }
        ],
        "overlay": {"visibleFrame": visible_frame},
        "islandSurface": case["islandSurface"],
        "notchStatus": case["notchStatus"],
        "sessionCount": case["sessionCount"],
        "liveSessionCount": case["liveSessionCount"],
        "attentionCount": case["attentionCount"],
        "selectedSessionID": case["selectedSessionID"],
        "sessions": case["sessions"],
    }
    report_path = directory / "report.json"
    report_path.write_text(json.dumps(report))
    return report_path


def run_case(case: dict) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as temporary_directory:
        report_path = write_case(pathlib.Path(temporary_directory), case)
        return subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--theme",
                case["theme"],
                str(report_path),
            ],
            capture_output=True,
            check=False,
            text=True,
        )


class HarnessArtifactValidatorTests(unittest.TestCase):
    def assert_valid(self, case: dict) -> None:
        result = run_case(case)
        self.assertEqual(result.returncode, 0, result.stderr)

    def assert_invalid(self, case: dict, message: str) -> None:
        result = run_case(case)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(message, result.stderr)

    def test_exact_runner_parity_and_all_theme_scenario_cells(self) -> None:
        match = re.search(
            r"^scenarios=\(([^)]*)\)$",
            RUNNER_PATH.read_text(),
            re.MULTILINE,
        )
        self.assertIsNotNone(match)
        runner_scenarios = shlex.split(match.group(1))
        self.assertEqual(len(runner_scenarios), 15)
        self.assertEqual(set(runner_scenarios), set(VALIDATOR.SUPPORTED_SCENARIOS))
        self.assertEqual(VALIDATOR.HEIGHT_RANGES, EXPECTED_HEIGHT_RANGES)
        self.assertEqual(VALIDATOR.WIDTH_RANGES, EXPECTED_WIDTH_RANGES)
        self.assertEqual(
            VALIDATOR.SCREEN_PROTECTED_SCENARIOS,
            EXPECTED_SCREEN_PROTECTED_SCENARIOS,
        )
        self.assertEqual(
            VALIDATOR.EXPECTED_USAGE_METER_SEMANTICS,
            EXPECTED_USAGE_METER_SEMANTICS,
        )
        self.assertEqual(
            VALIDATOR.FLIGHT_DECK_USAGE_GROUP_ENTRIES,
            FLIGHT_DECK_USAGE_GROUP_ENTRIES,
        )
        self.assertIn('--theme "$theme" "$final_report"', RUNNER_PATH.read_text())
        self.assertEqual(VALIDATOR.THEMES, frozenset(EXPECTED_WIDTH_RANGES))
        for theme in sorted(EXPECTED_WIDTH_RANGES):
            for scenario in runner_scenarios:
                with self.subTest(theme=theme, scenario=scenario):
                    self.assert_valid(scenario_case(scenario, theme))

    def test_exact_height_boundaries_for_every_scenario(self) -> None:
        for scenario, (minimum, maximum) in EXPECTED_HEIGHT_RANGES.items():
            for height, valid in (
                (minimum - 1, False),
                (minimum, True),
                (maximum, True),
                (maximum + 1, False),
            ):
                with self.subTest(scenario=scenario, height=height):
                    case = scenario_case(scenario)
                    case["frame"]["height"] = height
                    case["visibleHeight"] = 2000
                    if valid:
                        self.assert_valid(case)
                    else:
                        self.assert_invalid(case, f"{scenario} overlay frame height")

    def test_screen_protected_scenarios_keep_twenty_point_clearance(self) -> None:
        for scenario in EXPECTED_SCREEN_PROTECTED_SCENARIOS:
            visible_height = EXPECTED_HEIGHT_RANGES[scenario][0] + 100
            fitting = scenario_case(scenario)
            fitting["visibleHeight"] = visible_height
            fitting["frame"]["height"] = visible_height - 20
            with self.subTest(scenario=scenario, boundary="visible-20"):
                self.assert_valid(fitting)

            touching = scenario_case(scenario)
            touching["visibleHeight"] = visible_height
            touching["frame"]["height"] = visible_height - 19
            with self.subTest(scenario=scenario, boundary="visible-19"):
                self.assert_invalid(touching, f"{scenario} overlay frame height")

    def test_screen_protected_scenarios_require_finite_visible_height(self) -> None:
        for scenario in EXPECTED_SCREEN_PROTECTED_SCENARIOS:
            for invalid_height in (None, "949", float("nan"), float("inf"), 0, True):
                case = scenario_case(scenario)
                if invalid_height is None:
                    del case["visibleHeight"]
                else:
                    case["visibleHeight"] = invalid_height
                with self.subTest(scenario=scenario, value=repr(invalid_height)):
                    self.assert_invalid(case, "finite positive number")

    def test_theme_width_ranges_reject_wrong_insets(self) -> None:
        for theme, (minimum, maximum) in EXPECTED_WIDTH_RANGES.items():
            for width in (minimum, maximum):
                case = scenario_case("approvalCard", theme)
                case["frame"]["width"] = width
                with self.subTest(theme=theme, width=width):
                    self.assert_valid(case)

        for theme, wrong_width in (
            ("poured", 576),
            ("halo", 576),
            ("flightDeck", 620),
        ):
            case = scenario_case("approvalCard", theme)
            case["frame"]["width"] = wrong_width
            with self.subTest(theme=theme, wrong_width=wrong_width):
                self.assert_invalid(case, "approvalCard overlay frame width")

    def test_correct_metadata_never_bypasses_missing_rendered_semantics(self) -> None:
        semantic_removals = {
            "closed": ("textValues", "9 sessions"),
            "sessionList": (
                "buttonLabels",
                "Codex, fixture-9, completed, 9 minutes ago",
            ),
            "approvalCard": ("buttonLabels", "Allow"),
            "questionCard": ("buttonLabels", "JWT tokens"),
            "completionCard": ("textValues", "Plan 文件已写好。你的 hooks 触发情况如何？"),
            "longCompletionCard": ("textValues", "README.md committed from an isolated worktree"),
            "diffApprovalCard": ("roles", "AXScrollArea"),
            "codexApprovalCard": ("buttonLabels", "Jump to Codex to approve"),
            "multiQuestionCard": ("labels", "Which auth method should the bridge use?"),
            "subagentsCard": (
                "textValues",
                "3 subagents, 2 of 5 tasks completed",
            ),
            "subagentsExpanded": ("textValues", "Map the theme token surface"),
            "completedInterrupted": ("textValues", "Interrupted"),
            "completedFailed": ("textValues", "Failed"),
            "usageMeters": (
                "labels",
                "Codex 7d 92%, resets in 18h 59m",
            ),
            "emptyState": ("textValues", "No open terminal sessions"),
        }
        for scenario, (collection, value) in semantic_removals.items():
            case = scenario_case(scenario)
            case[collection].remove(value)
            with self.subTest(scenario=scenario):
                expected = (
                    "accessibility artifact is empty"
                    if scenario == "closed"
                    else scenario
                )
                self.assert_invalid(case, expected)

    def test_poured_session_list_requires_structured_count_and_rollups(self) -> None:
        structured = "SESSIONS, 9, 1, run, 1, done, 7, idle"
        self.assert_valid(scenario_case("sessionList", "poured"))

        malformed_summaries = {
            "missing-heading": "OVERVIEW, 9, 1, run, 1, done, 7, idle",
            "missing-count": "SESSIONS, 8, 1, run, 1, done, 7, idle",
            "missing-run": "SESSIONS, 9, 1, active, 1, done, 7, idle",
            "missing-done": "SESSIONS, 9, 1, run, 1, complete, 7, idle",
            "missing-idle": "SESSIONS, 9, 1, run, 1, done, 7, quiet",
        }
        for name, replacement in malformed_summaries.items():
            case = scenario_case("sessionList", "poured")
            case["textValues"].remove(structured)
            case["textValues"].add(replacement)
            with self.subTest(case=name):
                self.assert_invalid(case, "exact structured")

        missing_idle_rollup = scenario_case("sessionList", "poured")
        missing_idle_rollup["textValues"].remove("All quiet elsewhere · 7 idle")
        self.assert_invalid(missing_idle_rollup, "idle rollup")

    def test_flight_deck_session_list_requires_source_truthful_ax_entries(self) -> None:
        summary = "Sessions 0 Attn, 1 Run, 1 Done, 7 Idle"
        footer = "BRIDGE LINK, NO LINK, 9 SESSIONS"
        self.assert_valid(scenario_case("sessionList", "flightDeck"))

        normalized_spacing = scenario_case("sessionList", "flightDeck")
        normalized_spacing["textValues"].remove(summary)
        normalized_spacing["textValues"].add(
            "  Sessions 0 Attn,1 Run,  1 Done, 7 Idle  "
        )
        self.assert_valid(normalized_spacing)

        malformed_entries = {
            "missing-count": (
                footer,
                "BRIDGE LINK, NO LINK, SESSIONS",
                "bridge/count footer",
            ),
            "wrong-session-count": (
                footer,
                "BRIDGE LINK, NO LINK, 8 SESSIONS",
                "bridge/count footer",
            ),
            "missing-rollup": (
                summary,
                "Sessions 0 Attn",
                "annunciator rollup",
            ),
            "wrong-rollup": (
                summary,
                "Sessions 0 Attn, 1 Run, 0 Done, 8 Idle",
                "annunciator rollup",
            ),
            "wrong-case": (
                footer,
                "Bridge Link, No Link, 9 Sessions",
                "bridge/count footer",
            ),
            "wrong-case-rollup": (
                summary,
                "SESSIONS 0 ATTN, 1 RUN, 1 DONE, 7 IDLE",
                "annunciator rollup",
            ),
            "wrong-footer-content": (
                footer,
                "BRIDGE LINK, LINK, 9 SESSIONS",
                "bridge/count footer",
            ),
        }
        for name, (original, replacement, message) in malformed_entries.items():
            case = scenario_case("sessionList", "flightDeck")
            case["textValues"].remove(original)
            case["textValues"].add(replacement)
            with self.subTest(case=name):
                self.assert_invalid(case, message)

    def test_flight_deck_empty_state_requires_source_truthful_ax_entries(self) -> None:
        heading = "ALL SYSTEMS NOMINAL"
        description = (
            "No active sessions. Open Island is watching the bridge — the moment "
            "an agent needs approval, asks a question, or finishes, a lamp lights here."
        )
        sysline = "BRIDGE LINK · NO LINK · 0 SESSIONS"
        self.assert_valid(scenario_case("emptyState", "flightDeck"))

        live_bridge = scenario_case("emptyState", "flightDeck")
        live_bridge["staticTextValues"].remove(sysline)
        live_bridge["staticTextValues"].add(
            "BRIDGE LINK · MONITORING · 0 SESSIONS"
        )
        self.assert_valid(live_bridge)

        normalized_live_bridge = scenario_case("emptyState", "flightDeck")
        normalized_live_bridge["staticTextValues"].remove(sysline)
        normalized_live_bridge["staticTextValues"].add(
            "  BRIDGE LINK \t·\n MONITORING · 0 SESSIONS  "
        )
        self.assert_valid(normalized_live_bridge)

        malformed_entries = {
            "title-case-heading": (
                heading,
                "All Systems Nominal",
                "uppercase heading",
            ),
            "truncated-description": (
                description,
                "No active sessions. Open Island is watching the bridge",
                "exact description",
            ),
            "title-case-sysline": (
                sysline,
                "Bridge Link · No Link · 0 Sessions",
                "bridge telemetry",
            ),
            "unknown-link-status": (
                sysline,
                "BRIDGE LINK · STANDBY · 0 SESSIONS",
                "bridge telemetry",
            ),
            "missing-link-status": (
                sysline,
                "BRIDGE LINK · 0 SESSIONS",
                "bridge telemetry",
            ),
            "wrong-session-count": (
                sysline,
                "BRIDGE LINK · NO LINK · 1 SESSIONS",
                "bridge telemetry",
            ),
            "wrong-session-case": (
                sysline,
                "BRIDGE LINK · NO LINK · 0 sessions",
                "bridge telemetry",
            ),
            "missing-dot-spacing": (
                sysline,
                "BRIDGE LINK·MONITORING·0 SESSIONS",
                "bridge telemetry",
            ),
            "missing-leading-dot-spacing": (
                sysline,
                "BRIDGE LINK ·MONITORING · 0 SESSIONS",
                "bridge telemetry",
            ),
            "telemetry-prefix": (
                sysline,
                "STATUS BRIDGE LINK · NO LINK · 0 SESSIONS",
                "bridge telemetry",
            ),
            "telemetry-suffix": (
                sysline,
                "BRIDGE LINK · NO LINK · 0 SESSIONS READY",
                "bridge telemetry",
            ),
        }
        for name, (original, replacement, message) in malformed_entries.items():
            case = scenario_case("emptyState", "flightDeck")
            case["staticTextValues"].remove(original)
            case["staticTextValues"].add(replacement)
            with self.subTest(case=name):
                self.assert_invalid(case, message)

    def test_flight_deck_empty_state_uses_only_ax_static_text_values(self) -> None:
        heading = "ALL SYSTEMS NOMINAL"
        description = (
            "No active sessions. Open Island is watching the bridge — the moment "
            "an agent needs approval, asks a question, or finishes, a lamp lights here."
        )
        sysline = "BRIDGE LINK · NO LINK · 0 SESSIONS"
        case = scenario_case("emptyState", "flightDeck")

        # The report summary and arbitrary AX fields can repeat the required
        # strings, but they are not evidence that FlightDeckEmptyState rendered
        # them. The captured source uses AXStaticText.value exclusively.
        case["staticTextValues"] = {"unrelated rendered static text"}
        case["summaryTextValues"] = {heading, description, sysline}
        case["summaryLabels"] = {heading, description, sysline}
        case["extraAXNodes"] = [
            {
                "role": "AXButton",
                "label": heading,
                "value": description,
                "help": sysline,
                "description": heading,
                "children": [],
            },
            {
                "role": "AXGroup",
                "label": description,
                "value": sysline,
                "help": heading,
                "description": description,
                "children": [],
            },
            {
                "role": "AXStaticText",
                "label": heading,
                "value": "unrelated static-text value",
                "help": description,
                "description": sysline,
                "children": [],
            },
        ]
        self.assert_invalid(case, "uppercase heading")

    def test_halo_session_list_requires_source_truthful_ax_entries(self) -> None:
        summary = "9 total, 1 running, 1 done, 7 idle"
        footer = "9 sessions · 0 need you"
        self.assert_valid(scenario_case("sessionList", "halo"))

        normalized_spacing = scenario_case("sessionList", "halo")
        normalized_spacing["textValues"].remove(summary)
        normalized_spacing["textValues"].add(
            "  9 total,1 running,  1 done, 7 idle  "
        )
        self.assert_valid(normalized_spacing)

        malformed_entries = {
            "missing-count": (
                footer,
                "sessions · 0 need you",
                "count/attention footer",
            ),
            "wrong-attention-count": (
                footer,
                "9 sessions · 1 need you",
                "count/attention footer",
            ),
            "missing-rollup": (
                summary,
                "9 total, 1 running",
                "state rollup",
            ),
            "wrong-rollup": (
                summary,
                "9 total, 1 running, 0 done, 8 idle",
                "state rollup",
            ),
            "wrong-case": (
                summary,
                "9 Total, 1 Running, 1 Done, 7 Idle",
                "state rollup",
            ),
            "wrong-case-footer": (
                footer,
                "9 SESSIONS · 0 NEED YOU",
                "count/attention footer",
            ),
            "wrong-footer-content": (
                footer,
                "9 sessions · all quiet",
                "count/attention footer",
            ),
        }
        for name, (original, replacement, message) in malformed_entries.items():
            case = scenario_case("sessionList", "halo")
            case["textValues"].remove(original)
            case["textValues"].add(replacement)
            with self.subTest(case=name):
                self.assert_invalid(case, message)

    def test_non_poured_session_lists_require_all_nine_structured_rows(self) -> None:
        for theme in ("flightDeck", "halo"):
            case = scenario_case("sessionList", theme)
            case["buttonLabels"].remove(
                "Codex, fixture-9, completed, 9 minutes ago"
            )
            with self.subTest(theme=theme):
                self.assert_invalid(case, "exactly 9 session row buttons")

    def test_fresh_flight_deck_session_list_artifact_regression(self) -> None:
        if not FRESH_FLIGHT_DECK_SESSION_LIST_REPORT.exists():
            self.skipTest("preserved fresh Flight Deck artifact is not present")
        result = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--theme",
                "flightDeck",
                str(FRESH_FLIGHT_DECK_SESSION_LIST_REPORT),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_approval_card_theme_semantics_are_source_truthful(self) -> None:
        for theme in ("poured", "flightDeck", "halo"):
            with self.subTest(theme=theme, case="valid"):
                self.assert_valid(scenario_case("approvalCard", theme))

        poured_requirements = (
            (
                "head -5000 /Users/wangruobing/Personal/claude-research/"
                "extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt",
                "poured approvalCard AX command",
            ),
            (
                "Allow exec_command to rewrite SettingsView.swift?",
                "poured approvalCard AX effect",
            ),
        )
        for semantic, message in poured_requirements:
            case = scenario_case("approvalCard", "poured")
            case["textValues"].remove(semantic)
            with self.subTest(theme="poured", missing=semantic):
                self.assert_invalid(case, message)

        flight_deck_requirements = (
            ("PERMISSION REQUIRED", "permission kicker"),
            ("Opus 4.8 · feat/approval-flow", "model/branch identity"),
            (
                "$ head -5000 /Users/wangruobing/Personal/claude-research/"
                "extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt",
                "command",
            ),
            (
                "Sources/OpenIslandApp/Views/SettingsView.swift",
                "affected path",
            ),
        )
        for semantic, message in flight_deck_requirements:
            case = scenario_case("approvalCard", "flightDeck")
            case["textValues"].remove(semantic)
            with self.subTest(theme="flightDeck", missing=semantic):
                self.assert_invalid(case, message)

        valid_held_boundaries = {
            "59-seconds": "HELD, 0m 59s",
            "60-seconds": "HELD, 1m 00s",
            "23h-59m-59s": "HELD, 1439m 59s",
            "24h-exact": "HELD, 1440m 00s",
        }
        for name, held in valid_held_boundaries.items():
            case = scenario_case("approvalCard", "flightDeck")
            case["textValues"].remove("HELD, 0m 20s")
            case["textValues"].add(held)
            with self.subTest(theme="flightDeck", held=name):
                self.assert_valid(case)

        invalid_held_values = {
            "freeform": "HELD, 20 seconds",
            "seconds-out-of-domain": "HELD, 12m 99s",
            "over-24h-by-one-second": "HELD, 1440m 01s",
            "huge-minutes": "HELD, 999999m 00s",
            "negative-minutes": "HELD, -1m 00s",
            "negative-seconds": "HELD, 0m -1s",
            "padded-minutes": "HELD, 00m 59s",
            "underpadded-seconds": "HELD, 0m 5s",
            "overpadded-seconds": "HELD, 0m 005s",
        }
        for name, held in invalid_held_values.items():
            case = scenario_case("approvalCard", "flightDeck")
            case["textValues"].remove("HELD, 0m 20s")
            case["textValues"].add(held)
            with self.subTest(theme="flightDeck", held=name):
                self.assert_invalid(case, "held count-up")

        for forbidden in (
            "Allow exec_command to rewrite SettingsView.swift?",
            "Auto-collapses in 10s · hover pauses",
        ):
            case = scenario_case("approvalCard", "flightDeck")
            case["textValues"].add(forbidden)
            with self.subTest(theme="flightDeck", forbidden=forbidden):
                self.assert_invalid(case, "Poured-only copy")

        halo_requirements = (
            ("Permission needed", "title"),
            (
                "Allow exec_command to rewrite SettingsView.swift?",
                "request copy",
            ),
            ("Opus 4.8", "model identity"),
            (
                "head -5000 /Users/wangruobing/Personal/claude-research/"
                "extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt",
                "command",
            ),
        )
        for semantic, message in halo_requirements:
            case = scenario_case("approvalCard", "halo")
            case["textValues"].remove(semantic)
            with self.subTest(theme="halo", missing=semantic):
                self.assert_invalid(case, message)

        halo_with_countdown = scenario_case("approvalCard", "halo")
        halo_with_countdown["textValues"].add(
            "Auto-collapses in 10s · hover pauses"
        )
        self.assert_invalid(halo_with_countdown, "foreign-theme copy")

    def test_approval_card_requires_structured_lead_row(self) -> None:
        for theme in ("poured", "flightDeck", "halo"):
            case = scenario_case("approvalCard", theme)
            case["buttonLabels"].remove(
                "Claude Code, open-island, waiting for permission, 20 seconds ago"
            )
            case["buttonLabels"].add(
                "Claude Code, open-island, waiting for permission"
            )
            with self.subTest(theme=theme):
                self.assert_invalid(case, "structured lead session row")

    def test_approval_card_cross_theme_substitution_fails(self) -> None:
        for target_theme, donor_theme in (
            ("poured", "flightDeck"),
            ("flightDeck", "poured"),
            ("flightDeck", "halo"),
            ("halo", "poured"),
            ("halo", "flightDeck"),
        ):
            target = scenario_case("approvalCard", target_theme)
            donor = scenario_case("approvalCard", donor_theme)
            target["textValues"] = set(donor["textValues"])
            with self.subTest(target=target_theme, donor=donor_theme):
                self.assert_invalid(target, f"{target_theme} approvalCard")

    def test_fresh_flight_deck_approval_artifact_regression(self) -> None:
        if not FRESH_FLIGHT_DECK_APPROVAL_REPORT.exists():
            self.skipTest("preserved fresh Flight Deck approval artifact is absent")
        result = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--theme",
                "flightDeck",
                str(FRESH_FLIGHT_DECK_APPROVAL_REPORT),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_diff_approval_theme_semantics_and_common_structure(self) -> None:
        for theme in ("poured", "flightDeck", "halo"):
            with self.subTest(theme=theme, case="valid"):
                self.assert_valid(scenario_case("diffApprovalCard", theme))

        common_removals = (
            (
                "textValues",
                "After making changes, run swift build and confirm it succeeds before moving on.",
                "exact old/new diff lines",
            ),
            ("textValues", "+", "exact marker"),
            (
                "buttonLabels",
                "Yes, allow writing to AGENTS.md/ from this project",
                "buttons",
            ),
            (
                "buttonLabels",
                "Claude Code, open-vibe-island, waiting for permission, 11 seconds ago",
                "structured lead session row",
            ),
            ("roles", "AXScrollArea", "AXScrollArea"),
        )
        for theme in ("poured", "flightDeck", "halo"):
            for collection, semantic, message in common_removals:
                case = scenario_case("diffApprovalCard", theme)
                case[collection].remove(semantic)
                with self.subTest(theme=theme, missing=semantic):
                    self.assert_invalid(case, message)

        flight_deck_requirements = (
            ("PERMISSION REQUIRED", "permission kicker"),
            ("Opus 4.8 · main", "model/branch identity"),
            ("Claude wants to edit AGENTS.md.", "summary"),
            ("AGENTS.md", "affected path"),
            ("UPDATED", "diff header"),
            ("+3", "added count"),
            ("−2", "removed count"),
        )
        for semantic, message in flight_deck_requirements:
            case = scenario_case("diffApprovalCard", "flightDeck")
            case["textValues"].remove(semantic)
            with self.subTest(theme="flightDeck", missing=semantic):
                self.assert_invalid(case, message)

        invalid_held = scenario_case("diffApprovalCard", "flightDeck")
        invalid_held["textValues"].remove("HELD, 0m 11s")
        invalid_held["textValues"].add("HELD, 12m 99s")
        self.assert_invalid(invalid_held, "held count-up")

        halo_requirements = (
            ("Approve file edit", "title"),
            ("Claude wants to edit AGENTS.md.", "summary"),
            ("Opus 4.8", "model identity"),
            ("AGENTS.md · 5 changed", "diff header"),
        )
        for semantic, message in halo_requirements:
            case = scenario_case("diffApprovalCard", "halo")
            case["textValues"].remove(semantic)
            with self.subTest(theme="halo", missing=semantic):
                self.assert_invalid(case, message)

        for theme in ("flightDeck", "halo"):
            countdown = scenario_case("diffApprovalCard", theme)
            countdown["textValues"].add(
                "Auto-collapses in 10s · hover pauses"
            )
            with self.subTest(theme=theme, foreign="countdown"):
                self.assert_invalid(countdown, "foreign-theme copy")

    def test_diff_approval_cross_theme_substitution_fails(self) -> None:
        for target_theme, donor_theme in (
            ("poured", "flightDeck"),
            ("poured", "halo"),
            ("flightDeck", "poured"),
            ("flightDeck", "halo"),
            ("halo", "poured"),
            ("halo", "flightDeck"),
        ):
            target = scenario_case("diffApprovalCard", target_theme)
            donor = scenario_case("diffApprovalCard", donor_theme)
            for collection in ("labels", "buttonLabels", "textValues", "roles"):
                target[collection] = set(donor[collection])
            with self.subTest(target=target_theme, donor=donor_theme):
                self.assert_invalid(target, f"{target_theme} diffApprovalCard")

    def test_fresh_flight_deck_diff_approval_artifact_regression(self) -> None:
        if not FRESH_FLIGHT_DECK_DIFF_APPROVAL_REPORT.exists():
            self.skipTest("preserved fresh Flight Deck diff artifact is absent")
        result = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--theme",
                "flightDeck",
                str(FRESH_FLIGHT_DECK_DIFF_APPROVAL_REPORT),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_codex_approval_theme_semantics_are_source_truthful(self) -> None:
        for theme in ("poured", "flightDeck", "halo"):
            with self.subTest(theme=theme, case="valid"):
                self.assert_valid(scenario_case("codexApprovalCard", theme))

        for theme in ("poured", "flightDeck", "halo"):
            missing_row = scenario_case("codexApprovalCard", theme)
            missing_row["buttonLabels"].remove(
                "Codex, open-vibe-island, waiting for permission, 16 seconds ago"
            )
            with self.subTest(theme=theme, missing="structured-row"):
                self.assert_invalid(missing_row, "structured lead session row")

        theme_requirements = {
            "poured": (
                ("textValues", "Tool permission requested", "title"),
                ("textValues", "$ git push origin main", "command"),
                (
                    "textValues",
                    "Codex wants to run: git push origin main",
                    "summary",
                ),
                (
                    "textValues",
                    "Auto-collapses in 10s · hover pauses",
                    "countdown",
                ),
                (
                    "buttonLabels",
                    "Jump to Codex to approve",
                    "terminal CTA",
                ),
            ),
            "flightDeck": (
                ("textValues", "PERMISSION REQUIRED", "permission kicker"),
                ("textValues", "$ git push origin main", "command"),
                (
                    "textValues",
                    "~/Developer/open-vibe-island",
                    "affected path",
                ),
                ("buttonLabels", "Jump to Codex", "terminal CTA"),
            ),
            "halo": (
                ("textValues", "Approval waiting", "title"),
                (
                    "textValues",
                    "Codex wants to run: git push origin main",
                    "summary",
                ),
                ("textValues", "git push origin main", "command"),
                (
                    "textValues",
                    "Codex approvals happen inside the app. Jump to Codex to review this request.",
                    "terminal note",
                ),
                ("buttonLabels", "Jump to Codex", "terminal CTA"),
            ),
        }
        for theme, requirements in theme_requirements.items():
            for collection, semantic, message in requirements:
                case = scenario_case("codexApprovalCard", theme)
                case[collection].remove(semantic)
                with self.subTest(theme=theme, missing=semantic):
                    self.assert_invalid(case, message)

        invalid_held = scenario_case("codexApprovalCard", "flightDeck")
        invalid_held["textValues"].remove("HELD, 0m 16s")
        invalid_held["textValues"].add("HELD, 1440m 01s")
        self.assert_invalid(invalid_held, "held count-up")

    def test_codex_approval_cross_theme_substitution_fails(self) -> None:
        for target_theme, donor_theme in (
            ("poured", "flightDeck"),
            ("poured", "halo"),
            ("flightDeck", "poured"),
            ("flightDeck", "halo"),
            ("halo", "poured"),
            ("halo", "flightDeck"),
        ):
            target = scenario_case("codexApprovalCard", target_theme)
            donor = scenario_case("codexApprovalCard", donor_theme)
            for collection in ("labels", "buttonLabels", "textValues", "roles"):
                target[collection] = set(donor[collection])
            with self.subTest(target=target_theme, donor=donor_theme):
                self.assert_invalid(target, f"{target_theme} codexApprovalCard")

    def test_session_row_classifier_rejects_agent_named_arbitrary_buttons(self) -> None:
        adversarial_sets = {
            "arbitrary-agent-name": {
                f"Codex arbitrary button {index}" for index in range(1, 10)
            },
            "missing-workspace": {
                f"Codex, , running, {index} minutes ago"
                for index in range(1, 10)
            },
            "missing-field": {
                f"Codex, fixture-{index}, running" for index in range(1, 10)
            },
            "unknown-tool": {
                f"Codex Helper, fixture-{index}, running, {index} minutes ago"
                for index in range(1, 10)
            },
            "unknown-phase": {
                f"Codex, fixture-{index}, arbitrary, {index} minutes ago"
                for index in range(1, 10)
            },
            "malformed-age": {
                f"Codex, fixture-{index}, running, recently"
                for index in range(1, 10)
            },
            "extra-field": {
                f"Codex, fixture-{index}, running, {index} minutes ago, extra"
                for index in range(1, 10)
            },
        }
        for name, malformed_buttons in adversarial_sets.items():
            case = scenario_case("sessionList", "poured")
            case["buttonLabels"] = malformed_buttons
            with self.subTest(case=name):
                self.assert_invalid(case, "exactly 9 session row buttons")

    def test_nested_work_ax_contract_is_not_visual_or_split(self) -> None:
        collapsed_value = "3 subagents, 2 of 5 tasks completed"
        self.assert_valid(scenario_case("subagentsCard"))
        self.assert_valid(scenario_case("subagentsExpanded"))

        label_only = scenario_case("subagentsCard")
        label_only["textValues"].remove(collapsed_value)
        label_only["labels"].update(
            {collapsed_value, "3 SUBAGENTS", "TASKS · 2 OF 5 DONE"}
        )
        self.assert_invalid(label_only, "exact combined nested-work value")

        split_values = scenario_case("subagentsCard")
        split_values["textValues"].remove(collapsed_value)
        split_values["textValues"].update(
            {"3 subagents", "2 of 5 tasks completed"}
        )
        self.assert_invalid(split_values, "exact combined nested-work value")

        missing_value = scenario_case("subagentsCard")
        missing_value["textValues"].remove(collapsed_value)
        self.assert_invalid(missing_value, "exact combined nested-work value")

        malformed_lead = scenario_case("subagentsCard")
        malformed_lead["buttonLabels"] = {
            "Claude Code, open-vibe-island, running"
        }
        self.assert_invalid(malformed_lead, "structured lead session row")

        missing_expanded_lead = scenario_case("subagentsExpanded")
        missing_expanded_lead["buttonLabels"].clear()
        self.assert_invalid(
            missing_expanded_lead,
            "structured lead session row",
        )

        malformed_expanded_lead = scenario_case("subagentsExpanded")
        malformed_expanded_lead["buttonLabels"] = {
            "Claude Code, open-vibe-island, running, recently"
        }
        self.assert_invalid(
            malformed_expanded_lead,
            "structured lead session row",
        )

        retained_collapsed_value = scenario_case("subagentsExpanded")
        retained_collapsed_value["textValues"].add(collapsed_value)
        self.assert_invalid(retained_collapsed_value, "retained the collapsed")

    def test_halo_expanded_subagents_require_exact_native_axunknown_rows(self) -> None:
        expected = VALIDATOR.HALO_EXPANDED_SUBAGENT_NATIVE_DESCRIPTIONS
        self.assert_valid(scenario_case("subagentsExpanded", "halo"))

        summary_decoy = scenario_case("subagentsExpanded", "halo")
        summary_decoy["extraAXNodes"] = []
        summary_decoy["summaryLabels"] = set(expected)
        self.assert_invalid(summary_decoy, "authoritative AXUnknown")

        for role in ("AXStaticText", "AXGroup"):
            other_role_decoy = scenario_case("subagentsExpanded", "halo")
            other_role_decoy["extraAXNodes"] = [
                {
                    "role": role,
                    "label": description,
                    "description": description,
                    "children": [],
                }
                for description in expected
            ]
            with self.subTest(decoy_role=role):
                self.assert_invalid(other_role_decoy, "authoritative AXUnknown")

        for index, description in enumerate(expected):
            omitted = scenario_case("subagentsExpanded", "halo")
            omitted["extraAXNodes"].pop(index)
            with self.subTest(case="omitted", row=index):
                self.assert_invalid(omitted, "authoritative AXUnknown")

            duplicate = scenario_case("subagentsExpanded", "halo")
            duplicate["extraAXNodes"].append(dict(duplicate["extraAXNodes"][index]))
            with self.subTest(case="duplicate", row=index):
                self.assert_invalid(duplicate, "authoritative AXUnknown")

            for replacement, case_name in (
                (description.replace("Running", "Completed", 1), "status"),
                (description.replace("0m 42s", "0m 42", 1), "elapsed-format"),
                (description.replace("1m 15s", "1m 16s", 1), "elapsed-value"),
                (description.replace("Explore", "Scout", 1), "type"),
                (description.replace("Map the theme token surface", "Map tokens", 1), "task"),
            ):
                if replacement == description:
                    continue
                malformed = scenario_case("subagentsExpanded", "halo")
                malformed["extraAXNodes"][index]["description"] = replacement
                malformed["extraAXNodes"][index]["label"] = replacement
                with self.subTest(case=case_name, row=index):
                    self.assert_invalid(malformed, "authoritative AXUnknown")

            label_decoy = scenario_case("subagentsExpanded", "halo")
            label_decoy["extraAXNodes"][index]["label"] = "Visible row decoy"
            with self.subTest(case="label-not-source", row=index):
                self.assert_invalid(label_decoy, "label must exactly mirror")

    def test_halo_expanded_subagents_native_artifact_regression(self) -> None:
        if not FRESH_HALO_EXPANDED_SUBAGENTS_REPORT.exists():
            self.skipTest("preserved fresh Halo expanded artifact is absent")
        fresh = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--theme",
                "halo",
                str(FRESH_HALO_EXPANDED_SUBAGENTS_REPORT),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(fresh.returncode, 0, fresh.stderr)

        if not BROKEN_HALO_EXPANDED_SUBAGENTS_REPORT.exists():
            self.skipTest("preserved broken Halo expanded artifact is absent")
        broken = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--theme",
                "halo",
                str(BROKEN_HALO_EXPANDED_SUBAGENTS_REPORT),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertNotEqual(broken.returncode, 0, broken.stdout)
        self.assertIn("authoritative AXUnknown", broken.stderr)

    def test_cross_substitution_does_not_conflate_distinct_scenarios(self) -> None:
        pairs = [
            ("diffApprovalCard", "codexApprovalCard"),
            ("completedInterrupted", "completedFailed"),
            ("subagentsCard", "subagentsExpanded"),
        ]
        for target, donor in pairs:
            target_case = scenario_case(target)
            donor_case = scenario_case(donor)
            for collection in ("labels", "buttonLabels", "textValues", "roles"):
                target_case[collection] = set(donor_case[collection])
            with self.subTest(target=target, donor=donor):
                self.assert_invalid(target_case, target)

    def test_completion_outcome_badges_require_exact_text_values(self) -> None:
        for theme in ("poured", "flightDeck", "halo"):
            for scenario, title_case, wrong_title_case in (
                ("completedInterrupted", "Interrupted", "Failed"),
                ("completedFailed", "Failed", "Interrupted"),
            ):
                expected = (
                    title_case.upper()
                    if theme == "flightDeck"
                    else title_case
                )
                wrong_outcome = (
                    wrong_title_case.upper()
                    if theme == "flightDeck"
                    else wrong_title_case
                )
                foreign_case = (
                    title_case
                    if theme == "flightDeck"
                    else title_case.upper()
                )

                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="valid-text-value",
                ):
                    self.assert_valid(scenario_case(scenario, theme))

                label_only = scenario_case(scenario, theme)
                label_only["textValues"].remove(expected)
                label_only["labels"].add(expected)
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="label-only",
                ):
                    self.assert_invalid(label_only, "exact outcome")

                missing = scenario_case(scenario, theme)
                missing["textValues"].remove(expected)
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="missing",
                ):
                    self.assert_invalid(missing, "exact outcome")

                substituted_outcome = scenario_case(scenario, theme)
                substituted_outcome["textValues"].remove(expected)
                substituted_outcome["textValues"].add(wrong_outcome)
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="wrong-outcome",
                ):
                    self.assert_invalid(substituted_outcome, "exact outcome")

                wrong_case = scenario_case(scenario, theme)
                wrong_case["textValues"].remove(expected)
                wrong_case["textValues"].add(foreign_case)
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="foreign-case",
                ):
                    self.assert_invalid(wrong_case, "exact outcome")

                extra_foreign_case = scenario_case(scenario, theme)
                extra_foreign_case["textValues"].add(foreign_case)
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="extra-foreign-case",
                ):
                    self.assert_invalid(extra_foreign_case, "foreign-case outcome")

    def test_completion_outcome_cross_theme_and_cross_outcome_substitution_fails(
        self,
    ) -> None:
        for scenario in ("completedInterrupted", "completedFailed"):
            for target_theme, donor_theme in (
                ("poured", "flightDeck"),
                ("flightDeck", "poured"),
                ("flightDeck", "halo"),
                ("halo", "flightDeck"),
            ):
                target = scenario_case(scenario, target_theme)
                donor = scenario_case(scenario, donor_theme)
                target["textValues"] = set(donor["textValues"])
                with self.subTest(
                    scenario=scenario,
                    target=target_theme,
                    donor=donor_theme,
                ):
                    self.assert_invalid(target, "exact outcome")

        for theme in ("poured", "flightDeck", "halo"):
            for target_scenario, donor_scenario in (
                ("completedInterrupted", "completedFailed"),
                ("completedFailed", "completedInterrupted"),
            ):
                target = scenario_case(target_scenario, theme)
                donor = scenario_case(donor_scenario, theme)
                target["textValues"] = set(donor["textValues"])
                with self.subTest(
                    theme=theme,
                    target=target_scenario,
                    donor=donor_scenario,
                ):
                    self.assert_invalid(target, "exact outcome")

    def test_completed_failed_keeps_transcript_absent_for_every_theme(self) -> None:
        for theme in ("poured", "flightDeck", "halo"):
            case = scenario_case("completedFailed", theme)
            case["buttonLabels"].add("Transcript, open-vibe-island")
            with self.subTest(theme=theme):
                self.assert_invalid(case, "incorrect Transcript actions")

    def test_completion_actions_require_exact_ax_buttons_for_every_theme(
        self,
    ) -> None:
        scenario_actions = {
            "completionCard": ("open-island", True),
            "longCompletionCard": ("open-island", True),
            "completedInterrupted": ("niche-radar", True),
            "completedFailed": ("open-vibe-island", False),
        }
        jump_labels = {
            "poured": "Jump to terminal",
            "flightDeck": "Jump",
            "halo": "Jump · Ghostty",
        }
        for theme, expected_jump in jump_labels.items():
            for scenario, (workspace, transcript_required) in (
                scenario_actions.items()
            ):
                valid = scenario_case(scenario, theme)
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="valid",
                ):
                    self.assert_valid(valid)

                jump_nowhere = scenario_case(scenario, theme)
                jump_nowhere["buttonLabels"].remove(expected_jump)
                jump_nowhere["buttonLabels"].add("Jump nowhere")
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="jump-nowhere",
                ):
                    self.assert_invalid(jump_nowhere, "only exact Jump action")

                extra_jump = scenario_case(scenario, theme)
                extra_jump["buttonLabels"].add("Jump nowhere")
                with self.subTest(
                    theme=theme,
                    scenario=scenario,
                    case="extra-jump",
                ):
                    self.assert_invalid(extra_jump, "only exact Jump action")

                expected_transcript = f"Transcript, {workspace}"
                if transcript_required:
                    static_transcript = scenario_case(scenario, theme)
                    static_transcript["buttonLabels"].remove(
                        expected_transcript
                    )
                    static_transcript["textValues"].add(
                        "Transcript unavailable"
                    )
                    with self.subTest(
                        theme=theme,
                        scenario=scenario,
                        case="static-transcript",
                    ):
                        self.assert_invalid(
                            static_transcript,
                            "incorrect Transcript actions",
                        )

                    static_exact_label = scenario_case(scenario, theme)
                    static_exact_label["buttonLabels"].remove(
                        expected_transcript
                    )
                    static_exact_label["labels"].add(expected_transcript)
                    with self.subTest(
                        theme=theme,
                        scenario=scenario,
                        case="static-exact-transcript",
                    ):
                        self.assert_invalid(
                            static_exact_label,
                            "incorrect Transcript actions",
                        )

                    wrong_workspace = scenario_case(scenario, theme)
                    wrong_workspace["buttonLabels"].remove(
                        expected_transcript
                    )
                    wrong_workspace["buttonLabels"].add(
                        "Transcript, wrong-workspace"
                    )
                    with self.subTest(
                        theme=theme,
                        scenario=scenario,
                        case="wrong-workspace",
                    ):
                        self.assert_invalid(
                            wrong_workspace,
                            "incorrect Transcript actions",
                        )
                else:
                    unexpected_transcript = scenario_case(scenario, theme)
                    unexpected_transcript["buttonLabels"].add(
                        expected_transcript
                    )
                    with self.subTest(
                        theme=theme,
                        scenario=scenario,
                        case="unexpected-transcript",
                    ):
                        self.assert_invalid(
                            unexpected_transcript,
                            "incorrect Transcript actions",
                        )

    def test_fresh_flight_deck_interrupted_artifact_regression(self) -> None:
        if not FRESH_FLIGHT_DECK_INTERRUPTED_REPORT.exists():
            self.skipTest("preserved fresh Flight Deck interrupted artifact is absent")
        result = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--theme",
                "flightDeck",
                str(FRESH_FLIGHT_DECK_INTERRUPTED_REPORT),
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_usage_meter_semantics_are_complete_per_ax_entry(self) -> None:
        for theme in EXPECTED_USAGE_METER_SEMANTICS:
            self.assert_valid(scenario_case("usageMeters", theme))

            if theme != "flightDeck":
                grouped = scenario_case("usageMeters", theme)
                grouped["labels"] = {
                    " · ".join(EXPECTED_USAGE_METER_SEMANTICS[theme])
                }
                self.assert_invalid(grouped, "missing exact normalized entry")

            for semantic in EXPECTED_USAGE_METER_SEMANTICS[theme]:
                meter, reset = semantic.split(", ", 1)

                missing_reset = scenario_case("usageMeters", theme)
                missing_reset["labels"] = {
                    entry.replace(semantic, meter)
                    for entry in missing_reset["labels"]
                }
                with self.subTest(
                    theme=theme,
                    semantic=semantic,
                    case="missing-reset",
                ):
                    self.assert_invalid(missing_reset, "full per-meter semantic")

                mismatched_duration = scenario_case("usageMeters", theme)
                mismatched_duration["labels"] = {
                    entry.replace(semantic, f"{meter}, resets in 99h")
                    for entry in mismatched_duration["labels"]
                }
                with self.subTest(
                    theme=theme,
                    semantic=semantic,
                    case="mismatched-duration",
                ):
                    self.assert_invalid(
                        mismatched_duration,
                        "full per-meter semantic",
                    )

                global_reset_elsewhere = scenario_case("usageMeters", theme)
                global_reset_elsewhere["labels"] = {
                    entry.replace(semantic, meter)
                    for entry in global_reset_elsewhere["labels"]
                }
                global_reset_elsewhere["labels"].add(reset)
                with self.subTest(
                    theme=theme,
                    semantic=semantic,
                    case="global-reset",
                ):
                    self.assert_invalid(
                        global_reset_elsewhere,
                        "full per-meter semantic",
                    )

                visual_only = scenario_case("usageMeters", theme)
                visual_only["labels"] = {
                    entry.replace(semantic, meter)
                    for entry in visual_only["labels"]
                }
                visual_only["sessions"][0]["summary"] = semantic
                with self.subTest(
                    theme=theme,
                    semantic=semantic,
                    case="visual-only",
                ):
                    self.assert_invalid(visual_only, "full per-meter semantic")

    def test_poured_and_halo_usage_require_exact_meter_labels(self) -> None:
        for theme in ("poured", "halo"):
            expected_entries = EXPECTED_USAGE_METER_SEMANTICS[theme]

            padded = scenario_case("usageMeters", theme)
            padded["labels"] = {
                f"prefix {semantic} suffix" for semantic in expected_entries
            }
            with self.subTest(theme=theme, case="padded-full-semantics"):
                self.assert_invalid(padded, "missing exact normalized entry")

            short_meters_with_button_decoys = scenario_case("usageMeters", theme)
            short_meters_with_button_decoys["labels"] = set(
                EXPECTED_USAGE_METER_SEMANTICS["flightDeck"]
            )
            short_meters_with_button_decoys["buttonLabels"].update(expected_entries)
            with self.subTest(theme=theme, case="short-meters-with-button-decoys"):
                self.assert_invalid(
                    short_meters_with_button_decoys,
                    "missing exact normalized entry",
                )

            short_meters_with_summary_decoys = scenario_case("usageMeters", theme)
            short_meters_with_summary_decoys["labels"] = set(
                EXPECTED_USAGE_METER_SEMANTICS["flightDeck"]
            )
            short_meters_with_summary_decoys["summaryLabels"] = expected_entries
            with self.subTest(theme=theme, case="short-meters-with-summary-decoys"):
                self.assert_invalid(
                    short_meters_with_summary_decoys,
                    "missing exact normalized entry",
                )

            wrong_role = scenario_case("usageMeters", theme)
            wrong_role["usageMeterRole"] = "AXStaticText"
            with self.subTest(theme=theme, case="full-semantics-in-static-text"):
                self.assert_invalid(wrong_role, "missing exact normalized entry")

            normalized = scenario_case("usageMeters", theme)
            normalized["labels"] = {
                semantic.replace(" ", "  ").replace(",  ", " ,   ")
                for semantic in expected_entries
            }
            with self.subTest(theme=theme, case="whitespace-and-comma-normalization"):
                self.assert_valid(normalized)

            duplicate_meter = scenario_case("usageMeters", theme)
            duplicate_meter["usageMeterLabels"] = [
                *expected_entries,
                expected_entries[0],
            ]
            with self.subTest(theme=theme, case="duplicate-complete-meter"):
                self.assert_valid(duplicate_meter)

            duplicate_missing_meter = scenario_case("usageMeters", theme)
            duplicate_missing_meter["usageMeterLabels"] = [
                expected_entries[0],
                expected_entries[0],
                expected_entries[1],
            ]
            duplicate_missing_meter["summaryLabels"] = expected_entries
            with self.subTest(theme=theme, case="duplicate-does-not-replace-meter"):
                self.assert_invalid(
                    duplicate_missing_meter,
                    "missing exact normalized entry",
                )

    def test_flight_deck_usage_requires_native_grouped_entries(self) -> None:
        separate = scenario_case("usageMeters", "flightDeck")
        separate["labels"] = set(EXPECTED_USAGE_METER_SEMANTICS["flightDeck"])
        self.assert_invalid(separate, "missing exact normalized entry")

        full_titles = scenario_case("usageMeters", "flightDeck")
        full_titles["labels"] = set(EXPECTED_USAGE_METER_SEMANTICS["poured"])
        self.assert_invalid(full_titles, "full per-meter semantic")

        button_group_decoys = scenario_case("usageMeters", "flightDeck")
        button_group_decoys["labels"] = set(
            EXPECTED_USAGE_METER_SEMANTICS["flightDeck"]
        )
        button_group_decoys["buttonLabels"].update(
            FLIGHT_DECK_USAGE_GROUP_ENTRIES
        )
        self.assert_invalid(button_group_decoys, "missing exact normalized entry")

        summary_group_decoys = scenario_case("usageMeters", "flightDeck")
        summary_group_decoys["labels"] = set(
            EXPECTED_USAGE_METER_SEMANTICS["flightDeck"]
        )
        summary_group_decoys["summaryLabels"] = FLIGHT_DECK_USAGE_GROUP_ENTRIES
        self.assert_invalid(summary_group_decoys, "missing exact normalized entry")

        wrong_role = scenario_case("usageMeters", "flightDeck")
        wrong_role["usageMeterRole"] = "AXStaticText"
        self.assert_invalid(wrong_role, "full per-meter semantic")

        partial_grouping = scenario_case("usageMeters", "flightDeck")
        partial_grouping["usageMeterLabels"] = [
            EXPECTED_USAGE_METER_SEMANTICS["flightDeck"][0],
            EXPECTED_USAGE_METER_SEMANTICS["flightDeck"][1],
            FLIGHT_DECK_USAGE_GROUP_ENTRIES[1],
        ]
        partial_grouping["summaryLabels"] = FLIGHT_DECK_USAGE_GROUP_ENTRIES
        self.assert_invalid(partial_grouping, "missing exact normalized entry")

        duplicate_groups = scenario_case("usageMeters", "flightDeck")
        duplicate_groups["usageMeterLabels"] = [
            *FLIGHT_DECK_USAGE_GROUP_ENTRIES,
            FLIGHT_DECK_USAGE_GROUP_ENTRIES[0],
        ]
        self.assert_valid(duplicate_groups)

        duplicate_missing_group = scenario_case("usageMeters", "flightDeck")
        duplicate_missing_group["usageMeterLabels"] = [
            FLIGHT_DECK_USAGE_GROUP_ENTRIES[0],
            FLIGHT_DECK_USAGE_GROUP_ENTRIES[0],
        ]
        duplicate_missing_group["summaryLabels"] = FLIGHT_DECK_USAGE_GROUP_ENTRIES
        self.assert_invalid(duplicate_missing_group, "full per-meter semantic")

    def test_usage_meter_theme_substitution_contracts(self) -> None:
        themes = tuple(EXPECTED_USAGE_METER_SEMANTICS)
        for target_theme in themes:
            for donor_theme in themes:
                if target_theme == donor_theme:
                    continue
                target = scenario_case("usageMeters", target_theme)
                donor = scenario_case("usageMeters", donor_theme)
                target["labels"] = set(donor["labels"])
                with self.subTest(target=target_theme, donor=donor_theme):
                    if (
                        EXPECTED_USAGE_METER_SEMANTICS[target_theme]
                        == EXPECTED_USAGE_METER_SEMANTICS[donor_theme]
                    ):
                        self.assert_valid(target)
                    else:
                        self.assert_invalid(target, "full per-meter semantic")

    def test_preserved_usage_meter_artifact_regressions(self) -> None:
        for theme, report_path in (
            ("flightDeck", FRESH_FLIGHT_DECK_USAGE_REPORT),
            ("poured", PRESERVED_POURED_USAGE_REPORT),
        ):
            if not report_path.exists():
                self.skipTest(f"preserved {theme} usage artifact is absent")
            result = subprocess.run(
                [
                    sys.executable,
                    str(VALIDATOR_PATH),
                    "--theme",
                    theme,
                    str(report_path),
                ],
                capture_output=True,
                check=False,
                text=True,
            )
            with self.subTest(theme=theme):
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_multi_question_action_requires_identified_native_name_and_disabled_state(self) -> None:
        expected_actions = {
            "poured": "Submit & next",
            "flightDeck": "Submit Answers",
            "halo": "Next",
        }
        self.assertEqual(VALIDATOR.MULTI_QUESTION_ACTION_LABELS, expected_actions)
        self.assertEqual(
            VALIDATOR.MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER,
            "open-island.question.primary-action",
        )
        self.assertEqual(
            VALIDATOR.MULTI_QUESTION_PRIMARY_ACTION_NAME_SOURCES,
            frozenset({"AXTitle", "AXDescription"}),
        )
        self.assertEqual(
            VALIDATOR.MULTI_QUESTION_ACTION_ENABLED,
            {theme: False for theme in expected_actions},
        )

        for theme, expected in expected_actions.items():
            with self.subTest(theme=theme, case="valid-description-action"):
                self.assert_valid(scenario_case("multiQuestionCard", theme))

            title_action = scenario_case("multiQuestionCard", theme)
            title_button = title_action["buttonAX"][expected]
            title_button.update(
                {
                    "title": expected,
                    "description": None,
                    "accessibleName": expected,
                    "accessibleNameSource": "AXTitle",
                }
            )
            with self.subTest(theme=theme, case="valid-title-action"):
                self.assert_valid(title_action)

            missing = scenario_case("multiQuestionCard", theme)
            missing["buttonAX"][expected].pop("identifier")
            with self.subTest(theme=theme, case="missing-identifier"):
                self.assert_invalid(missing, "exactly one stable identifier")

            wrong_identifier = scenario_case("multiQuestionCard", theme)
            wrong_identifier["buttonAX"][expected]["identifier"] = "open-island.question.secondary-action"
            with self.subTest(theme=theme, case="wrong-identifier"):
                self.assert_invalid(wrong_identifier, "exactly one stable identifier")

            for malformed in (
                f"  {expected}  ",
                f"— {expected} —",
                f"Open {expected}",
                f"{expected} action",
                expected.swapcase(),
            ):
                description_action = scenario_case("multiQuestionCard", theme)
                description_button = description_action["buttonAX"][expected]
                description_button["description"] = malformed
                description_button["accessibleName"] = malformed
                with self.subTest(theme=theme, provenance="description", malformed=malformed):
                    self.assert_invalid(description_action, "multiQuestionCard AXButton action")

                title_action = scenario_case("multiQuestionCard", theme)
                title_button = title_action["buttonAX"][expected]
                title_button.update(
                    {
                        "title": malformed,
                        "description": None,
                        "accessibleName": malformed,
                        "accessibleNameSource": "AXTitle",
                    }
                )
                with self.subTest(theme=theme, provenance="title", malformed=malformed):
                    self.assert_invalid(title_action, "multiQuestionCard AXButton action")

            padded_description = scenario_case("multiQuestionCard", theme)
            padded_description["buttonAX"][expected]["description"] = f" {expected} "
            with self.subTest(theme=theme, case="padded-description-source"):
                self.assert_invalid(padded_description, "raw AXDescription")

            padded_title = scenario_case("multiQuestionCard", theme)
            padded_title_button = padded_title["buttonAX"][expected]
            padded_title_button.update(
                {
                    "title": f" {expected} ",
                    "description": None,
                    "accessibleName": expected,
                    "accessibleNameSource": "AXTitle",
                }
            )
            with self.subTest(theme=theme, case="padded-title-source"):
                self.assert_invalid(padded_title, "raw AXTitle")

            title_first_conflict = scenario_case("multiQuestionCard", theme)
            title_first_conflict["buttonAX"][expected]["title"] = expected
            with self.subTest(theme=theme, case="description-source-with-title"):
                self.assert_invalid(title_first_conflict, "derived accessibleName/source")

            title_name_conflict = scenario_case("multiQuestionCard", theme)
            title_button = title_name_conflict["buttonAX"][expected]
            title_button.update(
                {
                    "title": f"Open {expected}",
                    "description": None,
                    "accessibleName": expected,
                    "accessibleNameSource": "AXTitle",
                }
            )
            with self.subTest(theme=theme, case="title-name-mismatch"):
                self.assert_invalid(title_name_conflict, "derived accessibleName/source")

            bad_derived_name = scenario_case("multiQuestionCard", theme)
            bad_derived_name["buttonAX"][expected]["accessibleName"] = f"Open {expected}"
            with self.subTest(theme=theme, case="derived-name-mismatch"):
                self.assert_invalid(bad_derived_name, "derived accessibleName/source")

            bad_derived_source = scenario_case("multiQuestionCard", theme)
            bad_derived_source["buttonAX"][expected]["accessibleNameSource"] = "AXTitle"
            with self.subTest(theme=theme, case="derived-source-mismatch"):
                self.assert_invalid(bad_derived_source, "derived accessibleName/source")

            for source in ("AXHelp", "", None):
                unsupported_source = scenario_case("multiQuestionCard", theme)
                unsupported_source["buttonAX"][expected]["accessibleNameSource"] = source
                with self.subTest(theme=theme, source=source):
                    self.assert_invalid(unsupported_source, "derived accessibleName/source")

            for attribute in ("label", "help", "value"):
                decoy = scenario_case("multiQuestionCard", theme)
                decoy["buttonAX"][expected].pop("description")
                decoy["buttonAX"][expected].pop("accessibleName")
                decoy["buttonAX"][expected].pop("accessibleNameSource")
                decoy["buttonAX"][expected][attribute] = expected
                with self.subTest(theme=theme, decoy=attribute):
                    self.assert_invalid(decoy, "exact derived accessibleName")

            description_only = scenario_case("multiQuestionCard", theme)
            description_only["buttonAX"][expected].pop("accessibleName")
            description_only["buttonAX"][expected].pop("accessibleNameSource")
            with self.subTest(theme=theme, decoy="description-only"):
                self.assert_invalid(description_only, "derived accessibleName/source")

            summary_decoy = scenario_case("multiQuestionCard", theme)
            summary_decoy["buttonAX"][expected].pop("description")
            summary_decoy["buttonAX"][expected].pop("accessibleName")
            summary_decoy["buttonAX"][expected].pop("accessibleNameSource")
            summary_decoy["summaryButtonLabels"] = {expected}
            with self.subTest(theme=theme, case="summary-decoy"):
                self.assert_invalid(summary_decoy, "exact derived accessibleName")

            for role in ("AXStaticText", "AXGroup"):
                other_role_decoy = scenario_case("multiQuestionCard", theme)
                other_role_decoy["buttonAX"][expected]["identifier"] = "open-island.question.not-primary"
                other_role_decoy["extraAXNodes"] = [
                    {
                        "role": role,
                        "identifier": VALIDATOR.MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER,
                        "children": [],
                    }
                ]
                with self.subTest(theme=theme, case=f"{role}-only-identifier"):
                    self.assert_invalid(other_role_decoy, "must belong to an AXButton")

                duplicate_other_role = scenario_case("multiQuestionCard", theme)
                duplicate_other_role["extraAXNodes"] = [
                    {
                        "role": role,
                        "identifier": VALIDATOR.MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER,
                        "children": [],
                    }
                ]
                with self.subTest(theme=theme, case=f"duplicate-{role}-identifier"):
                    self.assert_invalid(duplicate_other_role, "exactly one stable identifier")

            duplicate = scenario_case("multiQuestionCard", theme)
            duplicate["extraAXNodes"] = [
                {
                    "role": "AXButton",
                    "identifier": VALIDATOR.MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER,
                    "description": expected,
                    "accessibleName": expected,
                    "accessibleNameSource": "AXDescription",
                    "enabled": False,
                    "children": [],
                }
            ]
            with self.subTest(theme=theme, case="duplicate"):
                self.assert_invalid(duplicate, "exactly one stable identifier")

            ancillary = scenario_case("multiQuestionCard", theme)
            ancillary["extraAXNodes"] = [
                {
                    "role": "AXButton",
                    "identifier": "open-island.question.ancillary-action",
                    "description": expected,
                    "accessibleName": expected,
                    "accessibleNameSource": "AXDescription",
                    "enabled": True,
                    "children": [],
                }
            ]
            with self.subTest(theme=theme, case="ancillary-button"):
                self.assert_valid(ancillary)

            for enabled in (True, None, 0):
                state_regression = scenario_case("multiQuestionCard", theme)
                if enabled is None:
                    state_regression["buttonAX"][expected].pop("enabled")
                else:
                    state_regression["buttonAX"][expected]["enabled"] = enabled
                with self.subTest(theme=theme, enabled=enabled):
                    self.assert_invalid(state_regression, "authoritative enabled")

    def test_png_scale_and_nonempty_ax_are_mandatory(self) -> None:
        wrong_scale = scenario_case("approvalCard")
        wrong_scale["pngHeightDelta"] = 1
        self.assert_invalid(wrong_scale, "do not exactly equal report frame")

        empty_ax = scenario_case("approvalCard")
        empty_ax["emptyAX"] = True
        self.assert_invalid(empty_ax, "accessibility artifact is empty")

    def test_committed_golden_pngs_are_well_formed_at_two_x(self) -> None:
        for relative_path, expected_dimensions in (
            EXPECTED_GOLDEN_PNG_DIMENSIONS.items()
        ):
            with self.subTest(golden=relative_path):
                self.assertEqual(
                    png_dimensions(REPO_ROOT / relative_path),
                    expected_dimensions,
                )

    def test_theme_is_required_and_unsupported_scenario_fails(self) -> None:
        result = subprocess.run(
            [sys.executable, str(VALIDATOR_PATH), "report.json"],
            capture_output=True,
            check=False,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--theme poured|flightDeck|halo", result.stderr)

        unsupported = scenario_case("closed")
        unsupported["scenario"] = "closedAttention"
        self.assert_invalid(unsupported, "unsupported scenario 'closedAttention'")


if __name__ == "__main__":
    unittest.main()
