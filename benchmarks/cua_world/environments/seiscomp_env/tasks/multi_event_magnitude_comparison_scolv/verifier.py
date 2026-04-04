#!/usr/bin/env python3
"""Verifier for multi_event_magnitude_comparison_scolv task.

A seismologist must import an aftershock event from QuakeML, verify both events
in scolv, set the aftershock event type and magnitude type, and export a
comparison bulletin containing both events.

Scoring:
- 30 pts: Aftershock event successfully imported into database
- 20 pts: Aftershock event type set to 'earthquake' in scolv
- 20 pts: Aftershock magnitude type set to 'Mw(mB)'
- 30 pts: Bulletin exported containing both mainshock and aftershock data

Wrong-target guard: If event count hasn't increased, return 0.
"""

import json
import os
import tempfile


def verify_multi_event_magnitude_comparison_scolv(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "multi_event_magnitude_comparison_scolv"
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

    initial_event_count = int(result.get("initial_event_count", 1))
    current_event_count = int(result.get("current_event_count", 0))
    aftershock_exists = _bool(result.get("aftershock_exists", False))
    aftershock_type_correct = _bool(result.get("aftershock_type_correct", False))
    aftershock_has_mwmb = _bool(result.get("aftershock_has_mwmb", False))
    bulletin_exists = _bool(result.get("bulletin_exists", False))
    bulletin_has_mainshock = _bool(result.get("bulletin_has_mainshock", False))
    bulletin_has_aftershock = _bool(result.get("bulletin_has_aftershock", False))
    bulletin_has_magnitudes = _bool(result.get("bulletin_has_magnitudes", False))
    bulletin_size = int(result.get("bulletin_size", 0))

    # ── Do-nothing guard ───────────────────────────────────────────────────
    if not aftershock_exists and not bulletin_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No changes detected. Aftershock not imported and no bulletin created. "
                "The agent must convert the QuakeML file, import it with scdb, "
                "review events in scolv, and export a comparison bulletin."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (30 pts): Aftershock imported ─────────────────────────
    if aftershock_exists and current_event_count > initial_event_count:
        score += 30
        parts.append(
            f"Aftershock imported successfully — {current_event_count} events in DB (30/30)"
        )
    elif aftershock_exists:
        score += 25
        parts.append("Aftershock origin found in DB but event count unchanged (25/30)")
    else:
        parts.append("Aftershock event not found in database (0/30)")

    # ── Criterion 2 (20 pts): Event type set to 'earthquake' ─────────────
    if aftershock_type_correct:
        score += 20
        parts.append("Aftershock event type set to 'earthquake' (20/20)")
    elif aftershock_exists:
        event_type = result.get("aftershock_event_type", "unset")
        parts.append(
            f"Aftershock event type is '{event_type}', expected 'earthquake' (0/20)"
        )
    else:
        parts.append("Cannot check event type — aftershock not imported (0/20)")

    # ── Criterion 3 (20 pts): Magnitude type Mw(mB) ─────────────────────
    if aftershock_has_mwmb:
        score += 20
        parts.append("Aftershock magnitude type set to 'Mw(mB)' (20/20)")
    elif aftershock_exists:
        mag_type = result.get("aftershock_mag_type", "unset")
        parts.append(
            f"Aftershock magnitude type is '{mag_type}', expected 'Mw(mB)' (0/20)"
        )
    else:
        parts.append("Cannot check magnitude type — aftershock not imported (0/20)")

    # ── Criterion 4 (30 pts): Bulletin with both events ──────────────────
    if bulletin_exists and bulletin_has_mainshock and bulletin_has_aftershock:
        score += 30
        parts.append("Bulletin contains both mainshock and aftershock data (30/30)")
    elif bulletin_exists and (bulletin_has_mainshock or bulletin_has_aftershock):
        score += 15
        which = "mainshock" if bulletin_has_mainshock else "aftershock"
        parts.append(
            f"Bulletin exists but only contains {which} data (15/30)"
        )
    elif bulletin_exists and bulletin_size > 10:
        score += 5
        parts.append(
            f"Bulletin exists ({bulletin_size} bytes) but doesn't contain "
            f"identifiable event data (5/30)"
        )
    else:
        parts.append(
            "No bulletin at /home/ga/Desktop/event_comparison.txt (0/30)"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
