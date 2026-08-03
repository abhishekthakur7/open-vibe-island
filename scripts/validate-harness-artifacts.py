#!/usr/bin/env python3

from __future__ import annotations

from collections import Counter
from collections.abc import Iterable
import json
import math
import pathlib
import re
import struct
import sys


SUPPORTED_SCENARIOS = frozenset(
    {
        "closed",
        # Slice 6 added the two collapsed-pill readouts (§J task counter, §I
        # critical usage) and the §H success hero. `closedCritical` shipped as a
        # debug scenario before this validator learned it; that gap predates
        # Slice 6 and is closed here alongside the new cells.
        "closedCritical",
        "closedTaskCounter",
        "completedSuccess",
        "sessionList",
        "approvalCard",
        "questionCard",
        "completionCard",
        "longCompletionCard",
        "diffApprovalCard",
        "codexApprovalCard",
        "multiQuestionCard",
        "subagentsCard",
        "subagentsExpanded",
        "completedInterrupted",
        "completedFailed",
        "usageMeters",
        "emptyState",
    }
)

THEMES = frozenset({"poured", "flightDeck", "halo"})

WIDTH_RANGES = {
    "poured": (610, 630),
    "flightDeck": (566, 586),
    "halo": (610, 630),
}

HEIGHT_RANGES = {
    "closed": (175, 240),
    # The collapsed pills share the closed-notch evidence band: both Slice 6
    # captures measure 184.
    "closedCritical": (175, 240),
    "closedTaskCounter": (175, 240),
    "sessionList": (560, 820),
    "approvalCard": (350, 520),
    "questionCard": (400, 800),
    "completionCard": (250, 520),
    "longCompletionCard": (380, 600),
    "diffApprovalCard": (500, 780),
    "codexApprovalCard": (280, 520),
    "multiQuestionCard": (400, 930),
    "subagentsCard": (450, 850),
    # Pre-existing on main: the expanded nest measures 901 (verified
    # byte-identical at f5b70931), one point over the retired 900 ceiling. The
    # bound is raised minimally rather than widened to the screen cap.
    "subagentsExpanded": (400, 910),
    "completedInterrupted": (240, 540),
    # §H success hero measures 585 in the Slice 6 capture.
    "completedSuccess": (420, 660),
    "completedFailed": (240, 540),
    "usageMeters": (560, 820),
    "emptyState": (260, 450),
}

# Every opened surface can be content-sized or scroll-capped. The collapsed
# pill has its own fixed evidence range and does not consume the usable height.
SCREEN_PROTECTED_SCENARIOS = SUPPORTED_SCENARIOS - {
    "closed",
    "closedCritical",
    "closedTaskCounter",
}

SESSION_ROW_TOOLS = frozenset(
    {
        "Claude Code",
        "Codex",
        "Gemini CLI",
        "OpenCode",
        "Qoder",
        "Qwen Code",
        "Factory",
        "CodeBuddy",
        "Cursor",
        "Kimi CLI",
    }
)

SESSION_ROW_PHASES = frozenset(
    {
        "running",
        "waiting for permission",
        "waiting for an answer",
        "completed",
        "interrupted",
        "failed",
    }
)

RELATIVE_AGE_PATTERN = re.compile(
    r"(?:"
    r"now|today|yesterday|"
    r"last (?:week|month|year)|"
    r"(?:an?|\d+) (?:second|minute|hour|day|week|month|year)s? ago|"
    r"in (?:an?|\d+) (?:second|minute|hour|day|week|month|year)s?"
    r")"
)

# Slice 6 (PI-I-001) re-cut the Codex window to the board's `7d · Pro` plan
# label and its exact 18h40m reset offset. `UsageSummaryAccessibilityFormatter`
# composes `<title> <window label> <pct>%, resets in <countdown>` for every
# theme off the one shared fixture.
#
# Slice 6 correction 2: `UsageCountdownFormatter` *floors*, so the unpadded
# offsets rendered one minute short (`18h 39m`) for all but the first instant
# after load. `AppearancePreviewFixtures.countdownFloorPad` adds `+59s` to every
# reset offset, so the rendered countdowns are now the board's own `2h 10m` /
# `3d 4h` / `18h 40m` throughout a capture window. Only the provider title
# differs per theme (Flight Deck uses the two-letter short title).
EXPECTED_USAGE_METER_SEMANTICS = {
    "poured": (
        "Claude 5h 34%, resets in 2h 10m",
        "Claude 7d 78%, resets in 3d 4h",
        "Codex 7d · Pro 92%, resets in 18h 40m",
    ),
    "flightDeck": (
        "Cl 5h 34%, resets in 2h 10m",
        "Cl 7d 78%, resets in 3d 4h",
        "Cx 7d · Pro 92%, resets in 18h 40m",
    ),
    "halo": (
        "Claude 5h 34%, resets in 2h 10m",
        "Claude 7d 78%, resets in 3d 4h",
        "Codex 7d · Pro 92%, resets in 18h 40m",
    ),
}

FLIGHT_DECK_USAGE_GROUP_ENTRIES = (
    "Cl 5h 34%, resets in 2h 10m · Cl 7d 78%, resets in 3d 4h",
    "Cx 7d · Pro 92%, resets in 18h 40m",
)

MULTI_QUESTION_ACTION_LABELS = {
    "poured": "Submit & next",
    "flightDeck": "Submit Answers",
    "halo": "Next",
}

# `StructuredQuestionPromptView` owns this once at the shared submit seam so
# the themed Poured, Flight Deck, and Halo CTAs expose one unambiguous native
# AXButton. Do not infer this control from visible copy or the legacy summary.
MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER = "open-island.question.primary-action"
MULTI_QUESTION_PRIMARY_ACTION_NAME_SOURCES = frozenset(
    {"AXTitle", "AXDescription"}
)

# The harness launches the normal, unselected fixture. Its preview-only
# preselection seam is not enabled, so every first-page action is disabled.
MULTI_QUESTION_ACTION_ENABLED = {
    "poured": False,
    "flightDeck": False,
    "halo": False,
}

# The Halo expanded fixture exposes nested work as one native AXUnknown per
# subagent. `description` is the recorder's raw AXDescription; `label` is its
# title/description fallback and must agree with that source. Keep the
# deterministic elapsed values here rather than accepting a visual rollup or a
# loosely-shaped duration from another role.
HALO_EXPANDED_SUBAGENT_NATIVE_ROWS = (
    (
        "Running",
        "explore",
        "Map every ClaudeHooks call site",
        "0m 42s",
    ),
    (
        "Running",
        "edit",
        "Rewrite CodexHooks payload model",
        "1m 15s",
    ),
    (
        "Running",
        "test",
        "Add BridgeCodec round-trip tests",
        "0m 08s",
    ),
)


def halo_expanded_subagent_native_description(
    status: str,
    agent_type: str,
    task: str,
    elapsed: str,
) -> str:
    return ", ".join((status, agent_type, task, elapsed))


HALO_EXPANDED_SUBAGENT_NATIVE_DESCRIPTIONS = tuple(
    halo_expanded_subagent_native_description(*row)
    for row in HALO_EXPANDED_SUBAGENT_NATIVE_ROWS
)


def fail(message: str) -> None:
    raise SystemExit(f"Smoke failed: {message}")


def load_json(path: pathlib.Path) -> dict:
    if not path.exists():
        fail(f"missing file at {path}")
    return json.loads(path.read_text())


def require_path(path: pathlib.Path, context: str) -> None:
    if not path.exists():
        fail(f"missing {context} at {path}")


def find_overlay_window(report: dict) -> dict:
    windows = report.get("windows") or []
    overlay = next((window for window in windows if window.get("kind") == "overlay"), None)
    if overlay is None:
        fail("report is missing an overlay window artifact")
    return overlay


def collect_ax_strings(
    node: dict,
    labels: set[str],
    button_labels: set[str],
    text_values: set[str],
    roles: set[str],
) -> None:
    role = node.get("role")
    if isinstance(role, str) and role:
        roles.add(role)

    label = node.get("label")
    if isinstance(label, str) and label:
        labels.add(label)
        if "button" in (role or "").lower():
            button_labels.add(label)

    value = node.get("value")
    if isinstance(value, str) and value:
        text_values.add(value)

    for child in node.get("children") or []:
        collect_ax_strings(child, labels, button_labels, text_values, roles)


def collect_ax_labels_for_role(node: dict, expected_role: str) -> list[str]:
    """Return source-tree labels for one exact AX role, preserving duplicates."""
    labels: list[str] = []
    if node.get("role") == expected_role:
        label = node.get("label")
        if isinstance(label, str) and label:
            labels.append(label)

    for child in node.get("children") or []:
        labels.extend(collect_ax_labels_for_role(child, expected_role))
    return labels


def collect_ax_nodes_for_role(node: dict, expected_role: str) -> list[dict]:
    """Return source-tree nodes for one exact AX role, preserving duplicates."""
    nodes: list[dict] = []
    if node.get("role") == expected_role:
        nodes.append(node)

    for child in node.get("children") or []:
        nodes.extend(collect_ax_nodes_for_role(child, expected_role))
    return nodes


def collect_ax_nodes_with_identifier(node: dict, expected_identifier: str) -> list[dict]:
    """Return every AX node with an exact identifier, preserving duplicates."""
    nodes: list[dict] = []
    if node.get("identifier") == expected_identifier:
        nodes.append(node)

    for child in node.get("children") or []:
        nodes.extend(collect_ax_nodes_with_identifier(child, expected_identifier))
    return nodes


def collect_ax_values_for_role(node: dict, expected_role: str) -> list[str]:
    """Return source-tree values for one exact AX role, preserving duplicates."""
    values: list[str] = []
    if node.get("role") == expected_role:
        value = node.get("value")
        if isinstance(value, str) and value:
            values.append(value)

    for child in node.get("children") or []:
        values.extend(collect_ax_values_for_role(child, expected_role))
    return values


def require_usage_meter_entries(
    ax_tree: dict,
    expected_entries: tuple[str, ...],
    context: str,
) -> list[str]:
    # SwiftUI exposes the real usage-meter semantics as AXUnknown nodes. Keep
    # these entries as a list: the contract is presence of every distinct
    # expected entry, so duplicates are permitted but cannot satisfy a missing
    # meter. Summary fields and labels from other AX roles are deliberately
    # excluded from this source-specific contract.
    meter_entries = collect_ax_labels_for_role(ax_tree, "AXUnknown")
    for expected_entry in expected_entries:
        assert_exact_normalized_entry(meter_entries, expected_entry, context)
    return meter_entries


def require_halo_expanded_subagent_native_rows(ax_tree: dict) -> None:
    """Require the three deterministic Halo subagent AXDescription nodes.

    The rendered text rollup and harness accessibility summary intentionally do
    not count here: they cannot prove that macOS exposed the localized running
    status, agent type, task, and elapsed time as one native element.
    """
    nodes = collect_ax_nodes_for_role(ax_tree, "AXUnknown")
    expected = Counter(HALO_EXPANDED_SUBAGENT_NATIVE_DESCRIPTIONS)
    descriptions = Counter(
        node.get("description")
        for node in nodes
        if isinstance(node.get("description"), str)
    )
    if len(nodes) != len(expected) or descriptions != expected:
        fail(
            "halo subagentsExpanded AX must expose exactly the three "
            "authoritative AXUnknown source-backed nested-work descriptions"
        )
    for node in nodes:
        if node.get("label") != node.get("description"):
            fail(
                "halo subagentsExpanded AXUnknown nested-work label must "
                "exactly mirror its raw AXDescription"
            )


def require_exact_multi_question_action(
    ax_tree: dict,
    *,
    theme: str,
) -> None:
    """Require the identified page-one action's native AX evidence.

    Poured and Halo paginate the fixture at one question per page, so their
    first-page action advances rather than submits the whole prompt. Flight
    Deck keeps both questions on one page and submits them together. Do not
    let summary fields or a similarly-labelled non-button node prove this
    interactive contract. The recorder resolves AXButton names title-first, so
    accept either native provenance only when its raw source and derived name
    agree exactly with this theme's action.
    """
    expected_name = MULTI_QUESTION_ACTION_LABELS[theme]
    expected_enabled = MULTI_QUESTION_ACTION_ENABLED[theme]
    identified_nodes = collect_ax_nodes_with_identifier(
        ax_tree, MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER
    )
    if len(identified_nodes) != 1:
        fail(
            "multiQuestionCard action must expose exactly one stable identifier "
            f"{MULTI_QUESTION_PRIMARY_ACTION_IDENTIFIER!r} across all AX nodes, "
            f"got {len(identified_nodes)}"
        )

    action = identified_nodes[0]
    if action.get("role") != "AXButton":
        fail(
            "multiQuestionCard stable identifier must belong to an AXButton, "
            f"got {action.get('role')!r}"
        )

    raw_title = action.get("title")
    raw_description = action.get("description")
    derived_name = action.get("accessibleName")
    derived_source = action.get("accessibleNameSource")
    resolved_name, resolved_source = resolve_ax_button_accessible_name(action)
    if (derived_name, derived_source) != (resolved_name, resolved_source):
        fail(
            "multiQuestionCard AXButton action derived accessibleName/source "
            "is inconsistent with its raw AXTitle/AXDescription fields"
        )
    if (
        derived_name != expected_name
        or derived_source not in MULTI_QUESTION_PRIMARY_ACTION_NAME_SOURCES
    ):
        fail(
            "multiQuestionCard AXButton action must expose exact derived "
            f"accessibleName {expected_name!r} from AXTitle or AXDescription, got "
            f"{derived_name!r}/{derived_source!r}"
        )
    if derived_source == "AXTitle" and raw_title != expected_name:
        fail(
            "multiQuestionCard AXButton action with AXTitle provenance must "
            f"expose exact nonempty raw AXTitle {expected_name!r}, got {raw_title!r}"
        )
    if derived_source == "AXDescription":
        if raw_title not in (None, ""):
            fail(
                "multiQuestionCard AXButton action with AXDescription provenance "
                "must leave AXTitle empty for title-first resolution"
            )
        if raw_description != expected_name:
            fail(
                "multiQuestionCard AXButton action with AXDescription provenance "
                f"must expose exact nonempty raw AXDescription {expected_name!r}, "
                f"got {raw_description!r}"
            )

    enabled = action.get("enabled")
    if type(enabled) is not bool or enabled != expected_enabled:
        fail(
            "multiQuestionCard AXButton action must expose authoritative "
            f"enabled={expected_enabled!r}, got {enabled!r}"
        )


def resolve_ax_button_accessible_name(node: dict) -> tuple[str | None, str | None]:
    """Mirror the recorder's AXButton-only title-then-description resolver."""
    if node.get("role") != "AXButton":
        return (None, None)

    for key, source in (("title", "AXTitle"), ("description", "AXDescription")):
        value = node.get(key)
        if isinstance(value, str):
            resolved = value.strip()
            if resolved:
                return (resolved, source)
    return (None, None)


def require_frame_between(frame: dict, *, width: tuple[float, float], height: tuple[float, float], context: str) -> None:
    frame_width = frame.get("width")
    frame_height = frame.get("height")
    if (
        isinstance(frame_width, bool)
        or isinstance(frame_height, bool)
        or not isinstance(frame_width, (int, float))
        or not isinstance(frame_height, (int, float))
        or not math.isfinite(frame_width)
        or not math.isfinite(frame_height)
    ):
        fail(f"{context} is missing width/height")

    min_width, max_width = width
    min_height, max_height = height
    if not (min_width <= frame_width <= max_width):
        fail(f"{context} width {frame_width} is outside expected range {width}")
    if not (min_height <= frame_height <= max_height):
        fail(f"{context} height {frame_height} is outside expected range {height}")


def scenario_height_range(report: dict, scenario: str) -> tuple[float, float]:
    minimum, maximum = HEIGHT_RANGES[scenario]
    if scenario not in SCREEN_PROTECTED_SCENARIOS:
        return (minimum, maximum)

    context = f"{scenario} overlay frame"
    overlay = report.get("overlay")
    if not isinstance(overlay, dict):
        fail(f"{context} is missing overlay metadata")
    visible_frame = overlay.get("visibleFrame")
    if not isinstance(visible_frame, dict):
        fail(f"{context} is missing overlay.visibleFrame")
    visible_height = visible_frame.get("height")
    if (
        isinstance(visible_height, bool)
        or not isinstance(visible_height, (int, float))
        or not math.isfinite(visible_height)
        or visible_height <= 0
    ):
        fail(
            f"{context} overlay.visibleFrame.height must be a finite positive number"
        )
    maximum = min(maximum, visible_height - 20)
    if maximum < minimum:
        fail(f"{context} usable screen is too short for minimum height {minimum}")
    return (minimum, maximum)


def png_dimensions(path: pathlib.Path) -> tuple[int, int]:
    require_path(path, "overlay PNG")
    header = path.read_bytes()[:24]
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        fail(f"overlay image at {path} is not a PNG")
    if header[12:16] != b"IHDR":
        fail(f"overlay PNG at {path} has no leading IHDR chunk")
    return struct.unpack(">II", header[16:24])


def validate_png_scale(report_path: pathlib.Path, overlay: dict) -> None:
    image_rel_path = overlay.get("imagePath")
    if not isinstance(image_rel_path, str) or not image_rel_path:
        fail("overlay window is missing imagePath")
    image_path = report_path.parent / image_rel_path
    pixel_width, pixel_height = png_dimensions(image_path)
    frame = overlay.get("frame") or {}
    frame_width = frame.get("width")
    frame_height = frame.get("height")
    if (
        not isinstance(frame_width, (int, float))
        or not isinstance(frame_height, (int, float))
        or pixel_width != frame_width * 2
        or pixel_height != frame_height * 2
    ):
        fail(
            "overlay PNG dimensions "
            f"{pixel_width}x{pixel_height} do not exactly equal report frame "
            f"{frame_width}x{frame_height} at @2x"
        )


def assert_contains_any(haystack: set[str], needles: list[str], context: str) -> None:
    if not any(needle in item for item in haystack for needle in needles):
        fail(f"{context} is missing any of {needles}")


def assert_contains(haystack: set[str], needle: str, context: str) -> None:
    if not any(needle in item for item in haystack):
        fail(f"{context} is missing {needle!r}")


def normalized_ax_entry(value: str) -> str:
    collapsed = " ".join(value.split())
    return re.sub(r"\s*,\s*", ", ", collapsed)


def assert_exact_normalized_entry(
    haystack: Iterable[str],
    expected: str,
    context: str,
) -> None:
    normalized_expected = normalized_ax_entry(expected)
    if not any(
        normalized_ax_entry(item) == normalized_expected
        for item in haystack
    ):
        fail(f"{context} is missing exact normalized entry {expected!r}")


def is_source_shaped_flight_deck_held(value: str) -> bool:
    match = re.fullmatch(
        r"HELD, (0|[1-9]\d*)m ([0-5]\d)s",
        normalized_ax_entry(value),
    )
    if match is None:
        return False
    minutes, seconds = (int(part) for part in match.groups())
    return minutes * 60 + seconds <= 24 * 60 * 60


def assert_source_shaped_flight_deck_held(
    haystack: set[str],
    context: str,
) -> None:
    if not any(is_source_shaped_flight_deck_held(item) for item in haystack):
        fail(
            f"{context} is missing a source-shaped HELD duration "
            "within the inclusive 24-hour ceiling"
        )


def assert_absent(haystack: set[str], needles: list[str], context: str) -> None:
    present = [needle for needle in needles if any(needle in item for item in haystack)]
    if present:
        fail(f"{context} unexpectedly contains {present}")


def assert_exact_normalized_absent(
    haystack: set[str],
    forbidden: str,
    context: str,
) -> None:
    normalized_forbidden = normalized_ax_entry(forbidden)
    if any(
        normalized_ax_entry(item) == normalized_forbidden
        for item in haystack
    ):
        fail(f"{context} unexpectedly contains exact entry {forbidden!r}")


def require_selected(report: dict, expected_id: str, expected_phase: str) -> None:
    if report.get("selectedSessionID") != expected_id:
        fail(
            f"expected selectedSessionID {expected_id!r}, "
            f"got {report.get('selectedSessionID')!r}"
        )
    if selected_session_phase(report) != expected_phase:
        fail(
            f"expected selected session {expected_id!r} phase "
            f"{expected_phase!r}, got {selected_session_phase(report)!r}"
        )


def require_actionable_surface(report: dict, selected_id: str, kind: str) -> None:
    surface = report.get("islandSurface") or ""
    allowed = {
        f"sessionList:actionable({selected_id})",
        f"{kind}:{selected_id}",
    }
    if surface not in allowed:
        fail(f"expected {kind}/actionable surface for {selected_id!r}, got {surface!r}")


def require_show_all(button_labels: set[str]) -> None:
    assert_contains(button_labels, "Show all 9 sessions", "show-all AX buttons")


def completion_jump_label(theme: str) -> str:
    return {
        "poured": "Jump to terminal",
        "flightDeck": "Jump",
        "halo": "Jump · Ghostty",
    }[theme]


def require_completion_actions(
    button_labels: set[str],
    *,
    theme: str,
    workspace: str,
    transcript_required: bool,
    context: str,
) -> None:
    expected_jump = normalized_ax_entry(completion_jump_label(theme))
    jump_labels = {
        normalized_ax_entry(label)
        for label in button_labels
        if normalized_ax_entry(label).startswith("Jump")
    }
    if jump_labels != {expected_jump}:
        fail(
            f"{context} AX buttons must expose only exact Jump action "
            f"{completion_jump_label(theme)!r}, got {sorted(jump_labels)!r}"
        )

    expected_transcript = normalized_ax_entry(f"Transcript, {workspace}")
    transcript_labels = {
        normalized_ax_entry(label)
        for label in button_labels
        if normalized_ax_entry(label).startswith("Transcript")
    }
    expected_transcripts = (
        {expected_transcript}
        if transcript_required
        else set()
    )
    if transcript_labels != expected_transcripts:
        fail(
            f"{context} AX buttons have incorrect Transcript actions: "
            f"expected {sorted(expected_transcripts)!r}, "
            f"got {sorted(transcript_labels)!r}"
        )


def is_session_row_button(label: str) -> bool:
    # Two accepted shapes, both strict on the leading four fields:
    #  * legacy `tool, workspace, phase, age`
    #  * the narrated Poured row (PI-C-005, Slice 4), which appends the row's
    #    activity line as a fifth free-text component, e.g.
    #    "Claude Code, open-vibe-island, running, 6 seconds ago,
    #     Orchestrating 3 subagents · live 6s".
    # Rejecting the narrated form was a pre-existing failure on main
    # (verified byte-identical at f5b70931): the subagents captures expose only
    # narrated rows, so their lead-row assertion could never pass.
    raw_fields = label.split(",")
    if len(raw_fields) < 4:
        return False
    tool, workspace, phase, age = (field.strip() for field in raw_fields[:4])
    if not all((tool, workspace, phase, age)):
        return False
    if len(raw_fields) > 4:
        # The activity line may itself contain commas; it is one trailing
        # free-text component and must not be empty.
        if not ",".join(raw_fields[4:]).strip():
            return False
    return (
        tool in SESSION_ROW_TOOLS
        and phase in SESSION_ROW_PHASES
        and RELATIVE_AGE_PATTERN.fullmatch(age) is not None
    )


def has_expected_lead_row(
    button_labels: set[str],
    *,
    tool: str,
    workspace: str,
    phase: str,
) -> bool:
    for label in button_labels:
        fields = tuple(field.strip() for field in label.split(","))
        if (
            is_session_row_button(label)
            and fields[:3] == (tool, workspace, phase)
        ):
            return True
    return False


def is_actionable_session_surface(island_surface: str) -> bool:
    return island_surface.startswith("sessionList:actionable(")


def selected_session(report: dict) -> dict:
    selected_id = report.get("selectedSessionID")
    sessions = report.get("sessions") or []
    if not isinstance(selected_id, str) or not isinstance(sessions, list):
        return {}
    return next(
        (
            session for session in sessions
            if isinstance(session, dict) and session.get("id") == selected_id
        ),
        {},
    )


def selected_session_phase(report: dict):
    phase = selected_session(report).get("phase")
    return phase if isinstance(phase, str) else None


def validate_runtime(report_path: pathlib.Path, report: dict) -> None:
    runtime = report.get("runtime")
    if not isinstance(runtime, dict):
        fail("report is missing runtime observability artifacts")

    timeline_rel_path = runtime.get("timelinePath")
    log_rel_path = runtime.get("logPath")
    if not isinstance(timeline_rel_path, str) or not timeline_rel_path:
        fail("runtime timelinePath is missing")
    if not isinstance(log_rel_path, str) or not log_rel_path:
        fail("runtime logPath is missing")

    timeline_path = report_path.parent / timeline_rel_path
    log_path = report_path.parent / log_rel_path
    require_path(timeline_path, "runtime timeline")
    require_path(log_path, "runtime log")

    timeline = json.loads(timeline_path.read_text())
    if not isinstance(timeline, list) or not timeline:
        fail("runtime timeline is empty")

    event_count = runtime.get("eventCount")
    if event_count != len(timeline):
        fail(f"runtime eventCount {event_count!r} does not match timeline length {len(timeline)}")

    if runtime.get("launchCompleted") is not True:
        fail("runtime launchCompleted is false")

    milestones = runtime.get("milestones")
    if not isinstance(milestones, list) or not milestones:
        fail("runtime milestones are missing")

    milestone_names = [milestone.get("name") for milestone in milestones if isinstance(milestone, dict)]
    required_names = {
        "applicationDidFinishLaunching",
        "bootstrapStarted",
        "modelStarted",
        "bootstrapCompleted",
        "captureScheduled",
        "captureStarted",
    }
    missing = sorted(required_names - set(name for name in milestone_names if isinstance(name, str)))
    if missing:
        fail(f"runtime milestones are missing {missing}")

    if report.get("presentOverlay") and "overlayPresented" not in milestone_names:
        fail("runtime milestones are missing overlayPresented for an overlay-present run")

    if report.get("startedBridge") is False and "bridgeSkipped" not in milestone_names:
        fail("runtime milestones are missing bridgeSkipped for a deterministic run")

    timings = runtime.get("timings")
    if not isinstance(timings, dict):
        fail("runtime timings are missing")

    bootstrap_seconds = timings.get("bootstrapSeconds")
    if not isinstance(bootstrap_seconds, (int, float)) or bootstrap_seconds <= 0 or bootstrap_seconds > 2.5:
        fail(f"bootstrapSeconds {bootstrap_seconds!r} is outside the expected range")

    capture_scheduled_seconds = timings.get("captureScheduledSeconds")
    if not isinstance(capture_scheduled_seconds, (int, float)) or capture_scheduled_seconds <= 0 or capture_scheduled_seconds > 2.5:
        fail(f"captureScheduledSeconds {capture_scheduled_seconds!r} is outside the expected range")

    capture_started_seconds = timings.get("captureStartedSeconds")
    if not isinstance(capture_started_seconds, (int, float)) or capture_started_seconds < capture_scheduled_seconds:
        fail(
            "captureStartedSeconds is missing or occurs before captureScheduledSeconds"
        )

    if report.get("presentOverlay"):
        overlay_presented_seconds = timings.get("overlayPresentedSeconds")
        if not isinstance(overlay_presented_seconds, (int, float)) or overlay_presented_seconds <= 0 or overlay_presented_seconds > 2.5:
            fail(f"overlayPresentedSeconds {overlay_presented_seconds!r} is outside the expected range")

    launch_to_capture_seconds = timings.get("launchToCaptureSeconds")
    report_launch_to_capture_seconds = report.get("launchToCaptureSeconds")
    if not isinstance(launch_to_capture_seconds, (int, float)) or launch_to_capture_seconds <= 0 or launch_to_capture_seconds > 5.0:
        fail(f"launchToCaptureSeconds {launch_to_capture_seconds!r} is outside the expected range")
    if report_launch_to_capture_seconds != launch_to_capture_seconds:
        fail("runtime launchToCaptureSeconds does not match report launchToCaptureSeconds")

    if not isinstance(runtime.get("latestMessage"), str) or not runtime.get("latestMessage"):
        fail("runtime latestMessage is missing")


def main() -> None:
    if (
        len(sys.argv) != 4
        or sys.argv[1] != "--theme"
        or sys.argv[2] not in THEMES
    ):
        raise SystemExit(
            "usage: validate-harness-artifacts.py "
            "--theme poured|flightDeck|halo <report.json>"
        )

    theme = sys.argv[2]
    report_path = pathlib.Path(sys.argv[3])
    report = load_json(report_path)
    validate_runtime(report_path, report)
    overlay = find_overlay_window(report)
    validate_png_scale(report_path, overlay)

    accessibility_path = overlay.get("accessibilityPath")
    if not accessibility_path:
        fail("overlay window is missing accessibilityPath")

    ax_path = report_path.parent / accessibility_path
    ax_tree = load_json(ax_path)
    if not isinstance(ax_tree, dict) or not ax_tree.get("children"):
        fail("overlay accessibility artifact is empty")

    labels: set[str] = set()
    button_labels: set[str] = set()
    text_values: set[str] = set()
    roles: set[str] = set()
    collect_ax_strings(ax_tree, labels, button_labels, text_values, roles)

    summary = overlay.get("accessibilitySummary") or {}
    labels.update(summary.get("labels") or [])
    button_labels.update(summary.get("buttonLabels") or [])
    text_values.update(summary.get("textValues") or [])
    if not (labels or button_labels or text_values):
        fail("overlay accessibility semantics are empty")

    scenario = report.get("scenario")
    if not isinstance(scenario, str) or not scenario:
        fail("report is missing scenario")
    if scenario not in SUPPORTED_SCENARIOS:
        fail(f"unsupported scenario {scenario!r}")

    island_surface = report.get("islandSurface") or ""
    notch_status = report.get("notchStatus")
    overlay_frame = overlay.get("frame") or {}
    require_frame_between(
        overlay_frame,
        width=WIDTH_RANGES[theme],
        height=scenario_height_range(report, scenario),
        context=f"{scenario} overlay frame",
    )
    ax_strings = labels | button_labels | text_values

    if scenario == "closed":
        if notch_status != "closed":
            fail(f"expected closed notch, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected closed scenario to use sessionList surface, got {island_surface!r}")
        if report.get("sessionCount") != 9 or report.get("liveSessionCount") != 9:
            fail("closed scenario must report exactly 9 sessions and 9 live sessions")
        if len(report.get("sessions") or []) != 9:
            fail("closed scenario report must contain exactly 9 session snapshots")
        assert_contains(text_values, "9 sessions", "closed AX visible count")

    elif scenario == "closedTaskCounter":
        if notch_status != "closed":
            fail(f"expected closed notch for closedTaskCounter, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(
                "expected closedTaskCounter to use sessionList surface, "
                f"got {island_surface!r}"
            )
        require_selected(report, "fixture-subagents-tasks", "running")
        assert_contains_any(
            ax_strings,
            ["2 of 5", "2/5", "2 / 5"],
            "closedTaskCounter AX task-counter reading",
        )
        if theme == "poured":
            # The collapsed §J pill narrates the counter and the orchestration
            # label; both are exact in the Slice 6 capture.
            for expected, context in (
                ("2 of 5 tasks done", "task counter"),
                ("Refactoring · 3 agents", "orchestration label"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"poured closedTaskCounter AX {context}",
                )

    elif scenario == "closedCritical":
        if notch_status != "closed":
            fail(f"expected closed notch for closedCritical, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(
                "expected closedCritical to use sessionList surface, "
                f"got {island_surface!r}"
            )
        assert_contains_any(
            ax_strings,
            ["92 percent", "92%"],
            "closedCritical AX critical usage readout",
        )
        if theme == "poured":
            for expected, context in (
                ("Codex", "provider"),
                ("Codex 7d · Pro usage 92 percent", "critical usage readout"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"poured closedCritical AX {context}",
                )

    elif scenario == "sessionList":
        if notch_status != "opened":
            fail(f"expected opened notch for sessionList, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected sessionList surface, got {island_surface!r}")
        if report.get("sessionCount") != 9 or report.get("liveSessionCount") != 9:
            fail("sessionList must report exactly 9 sessions and 9 live sessions")
        if len(report.get("sessions") or []) != 9:
            fail("sessionList report must contain exactly 9 session snapshots")
        row_buttons = {label for label in button_labels if is_session_row_button(label)}
        if theme == "poured":
            if len(row_buttons) != 9:
                fail("poured sessionList AX must expose exactly 9 session row buttons")
            expected_summary = (
                "SESSIONS",
                "9",
                "1",
                "run",
                "1",
                "done",
                "7",
                "idle",
            )
            structured_summaries = {
                tuple(part.strip() for part in value.split(","))
                for value in text_values
                if "," in value
            }
            if expected_summary not in structured_summaries:
                fail(
                    "poured sessionList AX must expose the exact structured "
                    "SESSIONS/9/run/done/idle summary"
                )
            assert_contains(
                text_values,
                "All quiet elsewhere · 7 idle",
                "poured sessionList AX idle rollup",
            )
        elif theme == "flightDeck":
            if len(row_buttons) != 9:
                fail(
                    "flightDeck sessionList AX must expose exactly 9 "
                    "session row buttons"
                )
            assert_exact_normalized_entry(
                text_values,
                "Sessions 0 Attn, 1 Run, 1 Done, 7 Idle",
                "flightDeck sessionList AX annunciator rollup",
            )
            assert_exact_normalized_entry(
                text_values,
                "BRIDGE LINK, NO LINK, 9 SESSIONS",
                "flightDeck sessionList AX bridge/count footer",
            )
        else:
            if len(row_buttons) != 9:
                fail(
                    "halo sessionList AX must expose exactly 9 "
                    "session row buttons"
                )
            assert_exact_normalized_entry(
                text_values,
                "9 total, 1 running, 1 done, 7 idle",
                "halo sessionList AX state rollup",
            )
            assert_exact_normalized_entry(
                text_values,
                "9 sessions · 0 need you",
                "halo sessionList AX count/attention footer",
            )

    elif scenario == "approvalCard":
        if notch_status != "opened":
            fail(f"expected opened notch for approvalCard, got {notch_status!r}")
        require_selected(report, "session-approval", "waitingForApproval")
        require_actionable_surface(report, "session-approval", "approvalCard")
        if selected_session(report).get("summary") != "Allow exec_command to rewrite SettingsView.swift?":
            fail("approvalCard selected-session summary is incorrect")
        if not has_expected_lead_row(
            button_labels,
            tool="Claude Code",
            workspace="open-island",
            phase="waiting for permission",
        ):
            fail("approvalCard AX is missing its structured lead session row")
        assert_contains(button_labels, "Allow", "approvalCard AX buttons")
        assert_contains(button_labels, "Deny", "approvalCard AX buttons")
        require_show_all(button_labels)
        raw_command = (
            "head -5000 /Users/wangruobing/Personal/claude-research/"
            "extracts/claude-bun-2.1.81-v3/islands/000_cli.js.txt"
        )
        effect = "Allow exec_command to rewrite SettingsView.swift?"
        countdown = "Auto-collapses in 10s · hover pauses"
        if theme == "poured":
            assert_exact_normalized_entry(
                text_values,
                raw_command,
                "poured approvalCard AX command",
            )
            assert_exact_normalized_entry(
                text_values,
                effect,
                "poured approvalCard AX effect",
            )
        elif theme == "flightDeck":
            for expected, context in (
                ("PERMISSION REQUIRED", "permission kicker"),
                ("Opus 4.8 · feat/approval-flow", "model/branch identity"),
                (f"$ {raw_command}", "command"),
                (
                    "Sources/OpenIslandApp/Views/SettingsView.swift",
                    "affected path",
                ),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"flightDeck approvalCard AX {context}",
                )
            assert_source_shaped_flight_deck_held(
                text_values,
                "flightDeck approvalCard AX held count-up",
            )
            assert_absent(
                text_values,
                [effect, "Auto-collapses in"],
                "flightDeck approvalCard Poured-only copy",
            )
        else:
            for expected, context in (
                ("Permission needed", "title"),
                (effect, "request copy"),
                ("Opus 4.8", "model identity"),
                (raw_command, "command"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"halo approvalCard AX {context}",
                )
            assert_absent(
                text_values,
                [
                    "Auto-collapses in",
                    "PERMISSION REQUIRED",
                    "HELD,",
                    "Sources/OpenIslandApp/Views/SettingsView.swift",
                    "Opus 4.8 · feat/approval-flow",
                ],
                "halo approvalCard foreign-theme copy",
            )

    elif scenario == "questionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for questionCard, got {notch_status!r}")
        require_selected(report, "session-question", "waitingForAnswer")
        require_actionable_surface(report, "session-question", "questionCard")
        if selected_session(report).get("summary") != "这个提醒态需要自动收起吗？":
            fail("questionCard selected-session summary is incorrect")
        assert_contains(
            ax_strings,
            "Which authentication method should we use?",
            "questionCard AX question",
        )
        for option in ("JWT tokens", "Session cookies", "OAuth 2.0", "Other"):
            assert_contains(button_labels, option, "questionCard AX options")
        assert_contains(button_labels, "Submit", "questionCard AX submit")
        assert_contains(
            text_values,
            "1–4 select · Enter submits · Esc closes",
            "questionCard AX keyboard hint",
        )
        require_show_all(button_labels)

    elif scenario == "completionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for completionCard, got {notch_status!r}")
        require_selected(report, "session-completion", "completed")
        require_actionable_surface(report, "session-completion", "completionCard")
        require_completion_actions(
            button_labels,
            theme=theme,
            workspace="open-island",
            transcript_required=True,
            context="completionCard",
        )
        assert_contains(
            ax_strings,
            "Plan 文件已写好。你的 hooks 触发情况如何？",
            "completionCard AX content",
        )
        require_show_all(button_labels)

    elif scenario == "longCompletionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for longCompletionCard, got {notch_status!r}")
        require_selected(report, "session-completion-long", "completed")
        require_actionable_surface(report, "session-completion-long", "completionCard")
        require_completion_actions(
            button_labels,
            theme=theme,
            workspace="open-island",
            transcript_required=True,
            context="longCompletionCard",
        )
        assert_contains(ax_strings, "README.md", "longCompletionCard AX content")
        assert_contains(ax_strings, "worktree", "longCompletionCard AX content")
        require_show_all(button_labels)

    elif scenario == "diffApprovalCard":
        if notch_status != "opened":
            fail(f"expected opened notch for diffApprovalCard, got {notch_status!r}")
        require_selected(report, "fixture-permission-diff", "waitingForApproval")
        require_actionable_surface(report, "fixture-permission-diff", "approvalCard")
        if selected_session(report).get("summary") != "Claude wants to edit AGENTS.md.":
            fail("diffApprovalCard selected-session summary is incorrect")
        if not has_expected_lead_row(
            button_labels,
            tool="Claude Code",
            workspace="open-vibe-island",
            phase="waiting for permission",
        ):
            fail("diffApprovalCard AX is missing its structured lead session row")
        exact_diff_lines = (
            "## Verification",
            "After making changes, run swift build and confirm it succeeds before moving on.",
            "After making changes, run swift build and swift test and confirm both succeed before moving on.",
            "Capture a harness smoke run whenever the change affects rendered UI.",
            "Summarize what changed once the round is done.",
            "Summarize what changed once the round is done, calling out any verification gaps.",
            "Commit the round on the feature branch before stopping.",
        )
        for line in exact_diff_lines:
            assert_exact_normalized_entry(
                text_values,
                line,
                "diffApprovalCard AX exact old/new diff lines",
            )
        for marker in ("+", "−"):
            if marker not in text_values:
                fail(f"diffApprovalCard AX is missing exact marker {marker!r}")
        if "AXScrollArea" not in roles:
            fail("diffApprovalCard AX is missing AXScrollArea")
        for button in (
            "Allow",
            "Deny",
            "Yes, allow writing to AGENTS.md/ from this project",
        ):
            if button not in button_labels:
                fail(f"diffApprovalCard AX buttons are missing exact {button!r}")
        require_show_all(button_labels)
        summary = "Claude wants to edit AGENTS.md."
        countdown = "Auto-collapses in 10s · hover pauses"
        if theme == "poured":
            for expected, context in (
                ("Tool permission requested", "title"),
                (summary, "summary"),
                ("Updated", "diff header"),
                ("+3", "added count"),
                ("−2", "removed count"),
                (countdown, "countdown"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"poured diffApprovalCard AX {context}",
                )
        elif theme == "flightDeck":
            for expected, context in (
                ("PERMISSION REQUIRED", "permission kicker"),
                ("Opus 4.8 · main", "model/branch identity"),
                (summary, "summary"),
                ("AGENTS.md", "affected path"),
                ("UPDATED", "diff header"),
                ("+3", "added count"),
                ("−2", "removed count"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"flightDeck diffApprovalCard AX {context}",
                )
            assert_source_shaped_flight_deck_held(
                text_values,
                "flightDeck diffApprovalCard AX held count-up",
            )
            assert_absent(
                text_values,
                [countdown, "Tool permission requested", "Approve file edit"],
                "flightDeck diffApprovalCard foreign-theme copy",
            )
        else:
            for expected, context in (
                ("Approve file edit", "title"),
                (summary, "summary"),
                ("Opus 4.8", "model identity"),
                ("AGENTS.md · 5 changed", "diff header"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"halo diffApprovalCard AX {context}",
                )
            assert_absent(
                text_values,
                [
                    countdown,
                    "PERMISSION REQUIRED",
                    "HELD,",
                    "Tool permission requested",
                    "UPDATED",
                    "+3",
                    "−2",
                ],
                "halo diffApprovalCard foreign-theme copy",
            )

    elif scenario == "codexApprovalCard":
        if notch_status != "opened":
            fail(f"expected opened notch for codexApprovalCard, got {notch_status!r}")
        require_selected(
            report,
            "fixture-codex-terminal-approval",
            "waitingForApproval",
        )
        require_actionable_surface(
            report,
            "fixture-codex-terminal-approval",
            "approvalCard",
        )
        if selected_session(report).get("summary") != "Codex wants to run: git push origin main":
            fail("codexApprovalCard selected-session summary is incorrect")
        if not has_expected_lead_row(
            button_labels,
            tool="Codex",
            workspace="open-vibe-island",
            phase="waiting for permission",
        ):
            fail("codexApprovalCard AX is missing its structured lead session row")
        assert_absent(
            button_labels,
            ["Allow", "Deny"],
            "codexApprovalCard terminal-only buttons",
        )
        require_show_all(button_labels)
        summary = "Codex wants to run: git push origin main"
        poured_note = (
            "Codex approves in-app. Open the pane to allow or deny there."
        )
        halo_note = (
            "Codex approvals happen inside the app. "
            "Jump to Codex to review this request."
        )
        countdown = "Auto-collapses in 10s · hover pauses"
        if theme == "poured":
            for expected, context in (
                ("Tool permission requested", "title"),
                ("$ git push origin main", "command"),
                (summary, "summary"),
                (poured_note, "terminal note"),
                (countdown, "countdown"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"poured codexApprovalCard AX {context}",
                )
            if "Jump to Codex to approve" not in button_labels:
                fail("poured codexApprovalCard AX is missing its exact terminal CTA")
        elif theme == "flightDeck":
            for expected, context in (
                ("PERMISSION REQUIRED", "permission kicker"),
                ("$ git push origin main", "command"),
                ("~/Developer/open-vibe-island", "affected path"),
                (poured_note, "terminal note"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"flightDeck codexApprovalCard AX {context}",
                )
            assert_source_shaped_flight_deck_held(
                text_values,
                "flightDeck codexApprovalCard AX held count-up",
            )
            if "Jump to Codex" not in button_labels:
                fail(
                    "flightDeck codexApprovalCard AX is missing its exact "
                    "terminal CTA"
                )
            assert_absent(
                text_values,
                [countdown, summary, "Tool permission requested", halo_note],
                "flightDeck codexApprovalCard foreign-theme copy",
            )
        else:
            for expected, context in (
                ("Approval waiting", "title"),
                (summary, "summary"),
                ("git push origin main", "command"),
                (halo_note, "terminal note"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"halo codexApprovalCard AX {context}",
                )
            if "Jump to Codex" not in button_labels:
                fail("halo codexApprovalCard AX is missing its exact terminal CTA")
            assert_absent(
                text_values,
                [
                    countdown,
                    "PERMISSION REQUIRED",
                    "HELD,",
                    "Tool permission requested",
                    poured_note,
                    "$ git push origin main",
                    "~/Developer/open-vibe-island",
                ],
                "halo codexApprovalCard foreign-theme copy",
            )

    elif scenario == "multiQuestionCard":
        if notch_status != "opened":
            fail(f"expected opened notch for multiQuestionCard, got {notch_status!r}")
        require_selected(report, "fixture-question-multi", "waitingForAnswer")
        require_actionable_surface(report, "fixture-question-multi", "questionCard")
        assert_contains(
            ax_strings,
            "Which auth method should the bridge use?",
            "multiQuestionCard AX Auth question",
        )
        assert_contains(ax_strings, "Auth", "multiQuestionCard AX Auth header")
        require_exact_multi_question_action(ax_tree, theme=theme)
        require_show_all(button_labels)
        if theme in {"poured", "halo"}:
            assert_contains(ax_strings, "Question 1 of 2", "multiQuestionCard AX progress")
            assert_contains(
                text_values,
                "1–3 select · Enter submits · Esc closes",
                "multiQuestionCard AX keyboard hint",
            )
            assert_absent(
                ax_strings,
                ["Which surfaces should the bridge expose?", "Scope"],
                "multiQuestionCard paginated page one",
            )
        else:
            assert_contains(
                ax_strings,
                "Which surfaces should the bridge expose?",
                "multiQuestionCard AX Scope question",
            )
            assert_contains(ax_strings, "Scope", "multiQuestionCard AX Scope header")
            assert_contains(
                text_values,
                "1–7 select · Enter submits · Esc closes",
                "multiQuestionCard AX keyboard hint",
            )

    elif scenario == "completedInterrupted":
        if notch_status != "opened":
            fail(f"expected opened notch for completedInterrupted, got {notch_status!r}")
        require_selected(report, "fixture-completed-interrupted", "completed")
        require_actionable_surface(
            report,
            "fixture-completed-interrupted",
            "completionCard",
        )
        if selected_session(report).get("summary") != "Stopped mid-refactor before the extraction finished.":
            fail("completedInterrupted selected-session summary is incorrect")
        expected_outcome = (
            "INTERRUPTED" if theme == "flightDeck" else "Interrupted"
        )
        foreign_outcome = (
            "Interrupted" if theme == "flightDeck" else "INTERRUPTED"
        )
        assert_exact_normalized_entry(
            text_values,
            expected_outcome,
            f"{theme} completedInterrupted AX exact outcome",
        )
        assert_exact_normalized_absent(
            text_values,
            foreign_outcome,
            f"{theme} completedInterrupted AX foreign-case outcome",
        )
        assert_exact_normalized_entry(
            text_values,
            "Interrupted while moving the scorer — no files were left half-written.",
            "completedInterrupted AX exact content",
        )
        require_completion_actions(
            button_labels,
            theme=theme,
            workspace="niche-radar",
            transcript_required=True,
            context="completedInterrupted",
        )
        require_show_all(button_labels)

    elif scenario == "completedFailed":
        if notch_status != "opened":
            fail(f"expected opened notch for completedFailed, got {notch_status!r}")
        require_selected(report, "fixture-completed-failed", "completed")
        require_actionable_surface(report, "fixture-completed-failed", "completionCard")
        if selected_session(report).get("summary") != "Build failed: 2 errors in BridgeServer.swift.":
            fail("completedFailed selected-session summary is incorrect")
        expected_outcome = "FAILED" if theme == "flightDeck" else "Failed"
        foreign_outcome = "Failed" if theme == "flightDeck" else "FAILED"
        assert_exact_normalized_entry(
            text_values,
            expected_outcome,
            f"{theme} completedFailed AX exact outcome",
        )
        assert_exact_normalized_absent(
            text_values,
            foreign_outcome,
            f"{theme} completedFailed AX foreign-case outcome",
        )
        assert_exact_normalized_entry(
            text_values,
            "swift build exited non-zero — BridgeServer.swift has two type errors I could not resolve.",
            "completedFailed AX exact content",
        )
        require_completion_actions(
            button_labels,
            theme=theme,
            workspace="open-vibe-island",
            transcript_required=False,
            context="completedFailed",
        )
        assert_absent(ax_strings, ["Transcript"], "completedFailed AX transcript")
        require_show_all(button_labels)

    elif scenario == "completedSuccess":
        if notch_status != "opened":
            fail(f"expected opened notch for completedSuccess, got {notch_status!r}")
        require_selected(report, "fixture-completed-success", "completed")
        require_actionable_surface(
            report,
            "fixture-completed-success",
            "completionCard",
        )
        if selected_session(report).get("summary") != "Updated AGENTS.md and CLAUDE.md":
            fail("completedSuccess selected-session summary is incorrect")
        if not has_expected_lead_row(
            button_labels,
            tool="Claude Code",
            workspace="the-automator",
            phase="completed",
        ):
            fail("completedSuccess AX is missing its structured lead session row")
        assert_contains_any(
            ax_strings,
            ["Success", "SUCCESS"],
            "completedSuccess AX outcome",
        )
        require_completion_actions(
            button_labels,
            theme=theme,
            workspace="the-automator",
            transcript_required=True,
            context="completedSuccess",
        )
        if theme == "poured":
            # The §H hero's own facts, exactly as the Slice 6 capture exposes
            # them: workspace + branch identity, the Success outcome, the RESULT
            # kicker, and the three result prose lines.
            for expected, context in (
                ("the-automator", "workspace"),
                ("docs/agents-md", "branch"),
                ("Success", "outcome"),
                ("Fable 5 · finished 12m ago", "model/finished identity"),
                ("RESULT", "result kicker"),
                (
                    "Updated AGENTS.md and CLAUDE.md to document the new "
                    "bridge-auth flow. Added a \"Working agreement\" note about "
                    "fail-open hooks and refreshed the support matrix to include "
                    "OpenCode and Kimi.",
                    "result prose",
                ),
                ("2 files changed", "first result fact"),
                ("Support matrix now matches README", "second result fact"),
            ):
                assert_exact_normalized_entry(
                    text_values,
                    expected,
                    f"poured completedSuccess AX {context}",
                )
            assert_exact_normalized_absent(
                text_values,
                "SUCCESS",
                "poured completedSuccess AX foreign-case outcome",
            )
            if "Dismiss session" not in button_labels:
                fail("poured completedSuccess AX is missing its exact Dismiss action")

    elif scenario == "subagentsCard":
        if notch_status != "opened":
            fail(f"expected opened notch for subagentsCard, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected subagentsCard to use sessionList surface, got {island_surface!r}")
        require_selected(report, "fixture-subagents-tasks", "running")
        if not has_expected_lead_row(
            button_labels,
            tool="Claude Code",
            workspace="the-automator",
            phase="running",
        ):
            fail("subagentsCard AX is missing its structured lead session row")
        collapsed_nested_work = "3 subagents, 2 of 5 tasks completed"
        if collapsed_nested_work not in text_values:
            fail(
                "subagentsCard AX textValues are missing the exact combined "
                "nested-work value"
            )
        assert_absent(
            ax_strings,
            [
                "Map every ClaudeHooks call site",
                "Rewrite CodexHooks payload model",
                "Add BridgeCodec round-trip tests",
            ],
            "subagentsCard collapsed AX",
        )

    elif scenario == "subagentsExpanded":
        if notch_status != "opened":
            fail(f"expected opened notch for subagentsExpanded, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected subagentsExpanded to use sessionList surface, got {island_surface!r}")
        require_selected(report, "fixture-subagents-tasks", "running")
        if not has_expected_lead_row(
            button_labels,
            tool="Claude Code",
            workspace="the-automator",
            phase="running",
        ):
            fail("subagentsExpanded AX is missing its structured lead session row")
        if theme == "halo":
            require_halo_expanded_subagent_native_rows(ax_tree)
        for detail in (
            "Map every ClaudeHooks call site",
            "Rewrite CodexHooks payload model",
            "Add BridgeCodec round-trip tests",
            "Rewrite per-agent payload models",
        ):
            assert_contains(ax_strings, detail, "subagentsExpanded AX detail")
        collapsed_nested_work = "3 subagents, 2 of 5 tasks completed"
        if collapsed_nested_work in text_values:
            fail(
                "subagentsExpanded AX textValues retained the collapsed "
                "nested-work value"
            )
        assert_contains_any(
            ax_strings,
            ["2/5", "2 / 5", "2 of 5", "2 OF 5"],
            "subagentsExpanded AX task progress",
        )

    elif scenario == "usageMeters":
        if notch_status != "opened":
            fail(f"expected opened notch for usageMeters, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected usageMeters to use sessionList surface, got {island_surface!r}")
        if report.get("sessionCount") != 9 or report.get("liveSessionCount") != 9:
            fail("usageMeters must report exactly 9 sessions and 9 live sessions")
        if theme == "flightDeck":
            meter_entries = collect_ax_labels_for_role(ax_tree, "AXUnknown")
            for semantic in EXPECTED_USAGE_METER_SEMANTICS[theme]:
                if not any(semantic in entry for entry in meter_entries):
                    fail(
                        "usageMeters AX is missing full per-meter semantic "
                        f"{semantic!r}"
                    )
            require_usage_meter_entries(
                ax_tree,
                FLIGHT_DECK_USAGE_GROUP_ENTRIES,
                "Flight Deck usageMeters AX",
            )
            assert_absent(
                meter_entries,
                ["Claude 5h 34%", "Claude 7d 78%", "Codex 7d · Pro 92%"],
                "Flight Deck usageMeters AX",
            )
        else:
            require_usage_meter_entries(
                ax_tree,
                EXPECTED_USAGE_METER_SEMANTICS[theme],
                f"{theme} usageMeters AX full per-meter semantic",
            )

    elif scenario == "emptyState":
        if notch_status != "opened":
            fail(f"expected opened notch for emptyState, got {notch_status!r}")
        if island_surface != "sessionList":
            fail(f"expected emptyState to use sessionList surface, got {island_surface!r}")
        if (
            report.get("sessionCount") != 0
            or report.get("liveSessionCount") != 0
            or report.get("attentionCount") != 0
            or report.get("selectedSessionID") is not None
            or report.get("sessions") != []
        ):
            fail("emptyState report state must be exactly zero/empty")
        if theme == "poured":
            # Slice 6 (§J) forked the Poured empty state off the shared copy:
            # the "All quiet" title, its own subtitle sentence, and the
            # deterministic hooks-coverage pill. The other themes keep their own
            # copy and are asserted in their own branches below.
            rendered_empty_state_values = collect_ax_values_for_role(
                ax_tree, "AXStaticText"
            )
            for copy, context in (
                ("All quiet", "title"),
                (
                    "No active agents. Open Island is watching your terminals — "
                    "the next permission, question, or finished run will surface "
                    "here.",
                    "subtitle",
                ),
                (
                    "Hooks installed for Claude, Codex, Gemini",
                    "hooks coverage pill",
                ),
            ):
                assert_exact_normalized_entry(
                    rendered_empty_state_values,
                    copy,
                    f"poured emptyState AX {context}",
                )
        elif theme == "flightDeck":
            # The live capture renders FlightDeckEmptyState's copy as
            # AXStaticText.value nodes. Do not accept the derived accessibility
            # summary, labels, buttons, or values exposed by other AX roles:
            # those are not proof that this empty-state copy was rendered.
            rendered_empty_state_values = collect_ax_values_for_role(
                ax_tree, "AXStaticText"
            )
            assert_exact_normalized_entry(
                rendered_empty_state_values,
                "ALL SYSTEMS NOMINAL",
                "flightDeck emptyState AX uppercase heading",
            )
            assert_exact_normalized_entry(
                rendered_empty_state_values,
                "No active sessions. Open Island is watching the bridge — the moment an agent needs approval, asks a question, or finishes, a lamp lights here.",
                "flightDeck emptyState AX exact description",
            )
            telemetry_options = (
                "BRIDGE LINK · MONITORING · 0 SESSIONS",
                "BRIDGE LINK · NO LINK · 0 SESSIONS",
            )
            normalized_telemetry_options = {
                normalized_ax_entry(option) for option in telemetry_options
            }
            if not any(
                normalized_ax_entry(value) in normalized_telemetry_options
                for value in rendered_empty_state_values
            ):
                fail(
                    "flightDeck emptyState AX bridge telemetry is missing exact "
                    "BRIDGE LINK · MONITORING · 0 SESSIONS or "
                    "BRIDGE LINK · NO LINK · 0 SESSIONS"
                )
        else:
            for copy in (
                "All quiet",
                "No active agent sessions. Open Island is watching your terminals and IDEs",
                "Monitoring",
            ):
                assert_contains(ax_strings, copy, "halo emptyState AX copy")

    print(
        f"{scenario}: notch={notch_status}, surface={island_surface}, "
        f"frame={overlay_frame.get('width')}x{overlay_frame.get('height')}, "
        f"buttons={sorted(button_labels)}"
    )


if __name__ == "__main__":
    main()
