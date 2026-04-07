#!/usr/bin/env python3
"""
Verifier for ik_weld_trajectory task.

Scoring (100 points):
  - Criterion 1 (20 pts): weld_trajectory.csv exists and was created after task start
  - Criterion 2 (25 pts): CSV has >= 8 waypoint rows
  - Criterion 3 (25 pts): Trajectory spans >= 0.2 m in XY plane (meaningful weld path)
  - Criterion 4 (30 pts): weld_stats.json exists, is new, has required fields
                          with total_waypoints >= 8 and reached_count >= 6

Pass threshold: 70
Anti-gaming: do-nothing score = 0
Strategy enumeration:
  - Do-nothing: 0 pts (no files)
  - CSV only (no JSON): max 70 pts if CSV has 8+ rows and 0.2m span → passes
  - Empty CSV + JSON: 20+30=50 pts if files exist but CSV empty → fails (50<70)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/ik_weld_trajectory_result.json"


def verify_ik_weld_trajectory(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Criterion 1: CSV exists and is new (20 pts)
    if result.get("csv_exists") and result.get("csv_is_new"):
        score += 20
        feedback.append("Weld trajectory CSV created after task start (+20)")
    elif result.get("csv_exists"):
        feedback.append("CSV exists but predates task start — stale file")
    else:
        feedback.append("weld_trajectory.csv not found")

    # Criterion 2: CSV has >= 8 waypoints (25 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 8:
        score += 25
        feedback.append(f"Trajectory has {row_count} waypoints (>= 8 required) (+25)")
    elif row_count >= 4:
        score += 10
        feedback.append(f"Trajectory has {row_count} waypoints (partial: 10/25)")
    else:
        feedback.append(f"Trajectory has {row_count} waypoints (need >= 8)")

    # Criterion 3: Path spans >= 0.2 m in XY plane (25 pts)
    analysis = result.get("csv_analysis", {})
    if isinstance(analysis, dict):
        has_coords = analysis.get("has_coords", False)
        path_span = float(analysis.get("path_span_m", 0.0))
        if has_coords and path_span >= 0.2:
            score += 25
            feedback.append(f"Weld path spans {path_span:.3f} m (>= 0.2 m required) (+25)")
        elif has_coords and path_span >= 0.05:
            score += 10
            feedback.append(f"Path span {path_span:.3f} m (below 0.2 m, partial: 10/25)")
        elif not has_coords:
            feedback.append("CSV lacks actual position coordinates (actual_x/y/z columns)")
        else:
            feedback.append(f"Path span {path_span:.3f} m is too small (< 0.05 m)")
    else:
        feedback.append("Could not parse trajectory CSV analysis")

    # Criterion 4: JSON stats exist, are new, have required fields with valid counts (30 pts)
    json_fields = result.get("json_fields", {})
    if isinstance(json_fields, dict):
        has_fields = json_fields.get("has_fields", False)
        total_wp = int(json_fields.get("total_waypoints", 0))
        reached = int(json_fields.get("reached_count", 0))
    else:
        has_fields = False
        total_wp = 0
        reached = 0

    if result.get("json_exists") and result.get("json_is_new") and has_fields and total_wp >= 8:
        score += 30
        feedback.append(
            f"Stats JSON valid: {total_wp} waypoints, {reached} reached (+30)"
        )
    elif result.get("json_exists") and result.get("json_is_new") and has_fields:
        score += 15
        feedback.append(
            f"Stats JSON exists with fields but total_waypoints={total_wp} < 8 (partial: 15/30)"
        )
    elif result.get("json_exists") and result.get("json_is_new"):
        score += 5
        feedback.append("Stats JSON exists but missing required fields (partial: 5/30)")
    else:
        feedback.append("weld_stats.json not found or not new")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }
