#!/usr/bin/env python3
"""Verifier for relocate_event_manual_picks_scolv task.

A geoscientist must manually re-pick P-wave arrivals on waveform data in scolv
and relocate the hypocenter, committing a manual origin to the database.

Scoring:
- 40 pts: A new Origin with evaluationMode='manual' was committed (did not exist at start)
- 40 pts: The manual origin has at least 2 P-phase arrivals (picked on multiple stations)
- 20 pts: The manual origin's location differs from the initial automatic origin
          (proving genuine relocation, not just re-committing the same solution)

Wrong-target guard: If manual_origin_count == initial_manual_count (no new manual origin),
return 0 immediately.
"""

import json
import os
import tempfile


def verify_relocate_event_manual_picks_scolv(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "relocate_event_manual_picks_scolv"
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

    score = 0
    parts = []

    initial_manual_count = int(result.get("initial_manual_count", 0))
    manual_origin_count = int(result.get("manual_origin_count", 0))
    p_arrival_count = int(result.get("p_arrival_count", 0))
    lat_lon_changed = result.get("lat_lon_changed", False)
    if isinstance(lat_lon_changed, str):
        lat_lon_changed = lat_lon_changed.lower() == "true"
    preferred_is_manual = int(result.get("preferred_is_manual", 0))

    # ── Wrong-target guard ────────────────────────────────────────────────────
    # If no new manual origin was created, nothing was accomplished.
    if manual_origin_count <= initial_manual_count:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No manual Origin found in the database. "
                "The agent must open scolv's waveform picker, re-pick P arrivals, "
                "trigger a relocation, and commit the solution with evaluation mode 'manual'."
            ),
        }

    # ── Criterion 1 (40 pts): Manual origin committed ─────────────────────────
    score += 40
    parts.append("Manual Origin committed to database (40/40)")

    # ── Criterion 2 (40 pts): At least 2 P arrivals in the manual origin ──────
    if p_arrival_count >= 2:
        score += 40
        parts.append(f"Manual origin has {p_arrival_count} P-phase arrivals ≥ 2 (40/40)")
    elif p_arrival_count == 1:
        score += 15
        parts.append(f"Manual origin has only {p_arrival_count} P-phase arrival — need picks on ≥2 stations (15/40)")
    else:
        parts.append("Manual origin has no P-phase arrivals — phase picks not linked to origin (0/40)")

    # ── Criterion 3 (20 pts): Relocation produced a different location ─────────
    if lat_lon_changed:
        score += 20
        parts.append("Relocation produced a new hypocenter location distinct from automatic origin (20/20)")
    else:
        parts.append(
            "Manual origin location is same as automatic origin — relocation may not have run (0/20)"
        )

    # Bonus info (not scored) — whether manual origin was set as preferred
    if preferred_is_manual:
        parts.append("[Info] Manual origin is now the preferred origin for the event")

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
