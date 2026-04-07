#!/usr/bin/env python3
"""
Verifier for proximity_sensor_coverage task.

Scoring (100 points):
  - Criterion 1 (20 pts): sensor_coverage.csv exists and was created after task start
  - Criterion 2 (25 pts): CSV has >= 5 placement rows
  - Criterion 3 (25 pts): CSV has coverage_pct column with >= 4 placements having
                          valid percentage values (0.0–100.0)
  - Criterion 4 (30 pts): sensor_analysis.json exists, is new, has required fields
                          (total_placements, best_placement_id, best_coverage_pct,
                          recommended_x, recommended_y, recommended_z)
                          with total_placements >= 5

Pass threshold: 70
Anti-gaming: do-nothing score = 0
Empty CSV + JSON (filled): 20+30=50 pts if no rows → fails (50 < 70)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/proximity_sensor_coverage_result.json"


def verify_proximity_sensor_coverage(traj, env_info, task_info):
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
        feedback.append("Sensor coverage CSV created after task start (+20)")
    elif result.get("csv_exists"):
        feedback.append("CSV exists but predates task start — stale file")
    else:
        feedback.append("sensor_coverage.csv not found")

    # Criterion 2: >= 5 rows (25 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 5:
        score += 25
        feedback.append(f"CSV has {row_count} placements (>= 5 required) (+25)")
    elif row_count >= 2:
        score += 10
        feedback.append(f"CSV has {row_count} placements (partial: 10/25)")
    else:
        feedback.append(f"CSV has {row_count} placements (need >= 5)")

    # Criterion 3: Has coverage_pct column with valid values (25 pts)
    analysis = result.get("csv_analysis", {})
    if isinstance(analysis, dict):
        has_coverage_col = analysis.get("has_coverage_col", False)
        placements_with_valid_pct = int(analysis.get("placements_with_valid_pct", 0))
        max_coverage_pct = float(analysis.get("max_coverage_pct", 0.0))

        if has_coverage_col and placements_with_valid_pct >= 4:
            score += 25
            feedback.append(
                f"Coverage data complete: {placements_with_valid_pct} valid placements, "
                f"max={max_coverage_pct:.1f}% (+25)"
            )
        elif has_coverage_col and placements_with_valid_pct >= 2:
            score += 10
            feedback.append(
                f"Partial coverage data: {placements_with_valid_pct} valid placements "
                f"(partial: 10/25)"
            )
        elif not has_coverage_col:
            feedback.append("CSV lacks coverage_pct column")
        else:
            feedback.append(
                f"Insufficient coverage data: only {placements_with_valid_pct} valid placements"
            )
    else:
        feedback.append("Could not parse coverage CSV analysis")

    # Criterion 4: JSON analysis with required fields and total_placements >= 5 (30 pts)
    json_fields = result.get("json_fields", {})
    if isinstance(json_fields, dict):
        has_fields = json_fields.get("has_fields", False)
        total_placements = int(json_fields.get("total_placements", 0))
        best_coverage = float(json_fields.get("best_coverage_pct", 0.0))
    else:
        has_fields = False
        total_placements = 0
        best_coverage = 0.0

    if (result.get("json_exists") and result.get("json_is_new")
            and has_fields and total_placements >= 5):
        score += 30
        feedback.append(
            f"Sensor analysis valid: {total_placements} placements, "
            f"best coverage={best_coverage:.1f}% (+30)"
        )
    elif result.get("json_exists") and result.get("json_is_new") and has_fields:
        score += 15
        feedback.append(
            f"Analysis exists with fields but total_placements={total_placements} < 5 "
            f"(partial: 15/30)"
        )
    elif result.get("json_exists") and result.get("json_is_new"):
        score += 5
        feedback.append("Analysis JSON exists but missing required fields (partial: 5/30)")
    else:
        feedback.append("sensor_analysis.json not found or not new")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }
