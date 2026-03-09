#!/usr/bin/env python3
"""Verifier for event_screening_false_detection_cleanup task.

A seismologist must identify and remove 3 false detection events from a
contaminated database, preserving only the real Noto M7.5 earthquake,
then export a clean bulletin.

Scoring:
- 40 pts: All 3 false detections removed from database (~13 pts each)
- 25 pts: Real Noto M7.5 event preserved (not accidentally deleted)
- 20 pts: Bulletin file exported with real event data
- 15 pts: Bulletin contains only verified events (no false event data)

Wrong-target guard:
- If event count hasn't changed, return 0
- If real event was deleted, heavy penalty
"""

import json
import os
import tempfile


def verify_event_screening_false_detection_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "event_screening_false_detection_cleanup"
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

    initial_event_count = int(result.get("initial_event_count", 4))
    current_event_count = int(result.get("current_event_count", 0))
    false_events_remaining = int(result.get("false_events_remaining", 3))
    real_event_preserved = _bool(result.get("real_event_preserved", True))
    bulletin_exists = _bool(result.get("bulletin_exists", False))
    bulletin_has_real_event = _bool(result.get("bulletin_has_real_event", False))
    bulletin_has_false_events = _bool(result.get("bulletin_has_false_events", False))

    # ── Do-nothing guard ───────────────────────────────────────────────────
    if current_event_count >= initial_event_count and not bulletin_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No changes detected. All events remain in database and no bulletin "
                "was exported. The agent must review events in scolv, identify the 3 "
                "false detections by their unrealistic locations and low magnitudes, "
                "delete them, and export a verified bulletin."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (40 pts): False detections removed ────────────────────
    false_removed = 3 - false_events_remaining
    if false_removed >= 3:
        score += 40
        parts.append("All 3 false detections removed (40/40)")
    elif false_removed >= 1:
        pts = false_removed * 13
        score += pts
        parts.append(
            f"{false_removed}/3 false detections removed, "
            f"{false_events_remaining} still remain ({pts}/40)"
        )
    else:
        parts.append("No false detections removed (0/40)")

    # ── Criterion 2 (25 pts): Real event preserved ───────────────────────
    if real_event_preserved:
        score += 25
        parts.append("Real Noto M7.5 event preserved in database (25/25)")
    else:
        # Heavy penalty for deleting the real event
        parts.append(
            "CRITICAL: Real Noto M7.5 event was deleted — must be preserved (0/25)"
        )

    # ── Criterion 3 (20 pts): Bulletin exported with real event ──────────
    if bulletin_exists and bulletin_has_real_event:
        score += 20
        parts.append("Bulletin exported with real event data (20/20)")
    elif bulletin_exists:
        score += 5
        parts.append("Bulletin exists but doesn't contain identifiable real event data (5/20)")
    else:
        parts.append(
            "No bulletin at /home/ga/Desktop/verified_events.txt (0/20)"
        )

    # ── Criterion 4 (15 pts): Bulletin is clean ──────────────────────────
    if bulletin_exists and bulletin_has_real_event and not bulletin_has_false_events:
        score += 15
        parts.append("Bulletin contains only verified events — clean (15/15)")
    elif bulletin_exists and bulletin_has_false_events:
        parts.append("Bulletin still contains false event references (0/15)")
    elif bulletin_exists:
        score += 5
        parts.append("Bulletin exists but content unclear (5/15)")
    else:
        parts.append("No bulletin to check for cleanliness (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
