#!/usr/bin/env python3
"""Verifier for export_event_bulletin_scbulletin task.

A geoscientist must use the scbulletin CLI tool to export a seismicity bulletin
from the SeisComP database to /home/ga/Desktop/noto_bulletin.txt.

Scoring:
  25 pts: File exists at the correct path
  25 pts: File is newer than task start (not a pre-existing stale file)
  25 pts: File has meaningful content (size > 50 bytes, earthquake data present)
  25 pts: File contains event-level data (origin info, date/time patterns, or magnitude)

Wrong-target guard: file must exist and be newer than task start.
"""

import json
import os
import re
import tempfile


def verify_export_event_bulletin_scbulletin(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "export_event_bulletin_scbulletin"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(result_path, tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {e}",
        }

    def _bool(v):
        if isinstance(v, bool):
            return v
        return str(v).lower() == "true"

    file_exists = _bool(result.get("file_exists", False))
    file_is_new = _bool(result.get("file_is_new", False))
    file_size = int(result.get("file_size", 0))
    has_content = _bool(result.get("has_content", False))
    has_event_data = _bool(result.get("has_event_data", False))
    has_origin_line = _bool(result.get("has_origin_line", False))
    has_magnitude = _bool(result.get("has_magnitude", False))
    event_count = int(result.get("event_count_in_file", 0))

    # ── Wrong-target guard ────────────────────────────────────────────────────
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No bulletin file found at /home/ga/Desktop/noto_bulletin.txt. "
                "Open a terminal, run scbulletin with the correct flags, "
                "and redirect output to that path."
            ),
        }

    if not file_is_new:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "The bulletin file exists but was NOT created during this task session "
                "(modification time predates task start). "
                "The agent may have found a pre-existing file — re-run scbulletin."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (25 pts): File exists at correct path ────────────────────
    score += 25
    parts.append("Bulletin file found at /home/ga/Desktop/noto_bulletin.txt (25/25)")

    # ── Criterion 2 (25 pts): File created during task (not stale) ───────────
    score += 25
    parts.append("File created during task session (25/25)")

    # ── Criterion 3 (25 pts): File has meaningful content ────────────────────
    if has_content and file_size > 50:
        score += 25
        parts.append(f"File has meaningful content ({file_size} bytes) (25/25)")
    else:
        parts.append(f"File is too small ({file_size} bytes) or empty (0/25)")

    # ── Criterion 4 (25 pts): File contains earthquake event data ────────────
    # At least one of: event data marker, origin line with coordinates, or magnitude
    data_signals = sum([has_event_data, has_origin_line, has_magnitude, event_count > 0])
    if data_signals >= 2:
        score += 25
        detail_parts = []
        if has_event_data:
            detail_parts.append("event data keywords")
        if has_origin_line:
            detail_parts.append("origin coordinate lines")
        if has_magnitude:
            detail_parts.append("magnitude values")
        if event_count > 0:
            detail_parts.append(f"{event_count} date-stamped event lines")
        parts.append(f"Bulletin contains earthquake event data ({', '.join(detail_parts)}) (25/25)")
    elif data_signals == 1:
        score += 10
        parts.append("Bulletin has minimal event data (partial match) (10/25)")
    else:
        parts.append(
            "Bulletin does not appear to contain earthquake event data (0/25). "
            "Verify scbulletin was run with --begin/--end for 2024 and the correct database."
        )

    # Try to also read the bulletin copy for deeper validation
    bulletin_copy_path = f"/tmp/{task_name}_bulletin_copy.txt"
    try:
        tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
        tmp2.close()
        try:
            copy_from_env(bulletin_copy_path, tmp2.name)
            with open(tmp2.name, "r", encoding="utf-8", errors="replace") as f:
                bulletin_text = f.read(4096)  # Read first 4KB
            # Check for Noto Peninsula specific content
            if re.search(r"(Noto|noto|Japan|japan|37\.[0-9]|136\.[0-9]|137\.[0-9])", bulletin_text):
                parts.append("[Info] Bulletin references Noto/Japan region coordinates — correct event")
            elif re.search(r"7\.[0-9]", bulletin_text):
                parts.append("[Info] Bulletin contains M7+ magnitude value")
        finally:
            if os.path.exists(tmp2.name):
                os.unlink(tmp2.name)
    except Exception:
        pass  # Bulletin copy read is advisory only

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
