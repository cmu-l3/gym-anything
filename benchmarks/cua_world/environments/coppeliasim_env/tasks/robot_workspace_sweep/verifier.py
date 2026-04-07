#!/usr/bin/env python3
"""
Verifier for robot_workspace_sweep task.

Scoring (100 points):
  - Criterion 1 (20 pts): workspace_samples.csv exists and was created after task start
  - Criterion 2 (25 pts): CSV contains >= 50 workspace samples
  - Criterion 3 (25 pts): CSV positions span a meaningful workspace
                          (>= 10 distinct positions, reach_range >= 0.05 m)
  - Criterion 4 (30 pts): workspace_report.json exists, is new, and has required fields
                          (total_samples, max_reach_m, min_reach_m)

Pass threshold: 70
Anti-gaming: do-nothing score = 0 (no files exist before task start)
Empty-file check: csv_row_count=0 → criterion 2 fails (score ≤ 45, below threshold)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/robot_workspace_sweep_result.json"


def verify_robot_workspace_sweep(traj, env_info, task_info):
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
        feedback.append("CSV file created after task start (+20)")
    elif result.get("csv_exists"):
        feedback.append("CSV exists but was not created after task start — stale file")
    else:
        feedback.append("workspace_samples.csv not found")

    # Criterion 2: CSV has >= 50 rows (25 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 50:
        score += 25
        feedback.append(f"CSV has {row_count} samples (>= 50 required) (+25)")
    elif row_count >= 20:
        score += 10
        feedback.append(f"CSV has only {row_count} samples (partial: 10/25)")
    else:
        feedback.append(f"CSV has {row_count} samples (need >= 50)")

    # Criterion 3: Positions span a meaningful workspace (25 pts)
    csv_stats = result.get("csv_stats", {})
    if isinstance(csv_stats, dict):
        has_xyz = csv_stats.get("has_xyz", False)
        reach_range = float(csv_stats.get("reach_range", 0.0))
        unique_pos = int(csv_stats.get("unique_positions", 0))
        if has_xyz and reach_range >= 0.05 and unique_pos >= 10:
            score += 25
            feedback.append(
                f"Workspace spans {reach_range:.3f}m reach range, "
                f"{unique_pos} distinct positions (+25)"
            )
        elif has_xyz and unique_pos >= 5:
            score += 10
            feedback.append(
                f"Positions present but limited diversity: "
                f"range={reach_range:.3f}m, unique={unique_pos} (partial: 10/25)"
            )
        else:
            feedback.append("CSV lacks x/y/z position data or positions are not diverse")
    else:
        feedback.append("Could not parse CSV position data")

    # Criterion 4: JSON report exists, is new, has required fields (30 pts)
    json_info = result.get("json_info", {})
    if isinstance(json_info, dict):
        has_fields = json_info.get("has_fields", False)
        max_reach = float(json_info.get("max_reach", 0.0))
        total_samples = int(json_info.get("total_samples", 0))
    else:
        has_fields = False
        max_reach = 0.0
        total_samples = 0

    if result.get("json_exists") and result.get("json_is_new") and has_fields and total_samples >= 50:
        score += 30
        feedback.append(
            f"Report JSON valid: {total_samples} samples, max_reach={max_reach:.3f}m (+30)"
        )
    elif result.get("json_exists") and result.get("json_is_new") and has_fields:
        score += 15
        feedback.append(
            f"Report JSON exists with fields but total_samples={total_samples} < 50 (partial: 15/30)"
        )
    elif result.get("json_exists") and result.get("json_is_new"):
        score += 5
        feedback.append("Report JSON exists but missing required fields (partial: 5/30)")
    else:
        feedback.append("workspace_report.json not found or not new")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }
