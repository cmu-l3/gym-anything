#!/usr/bin/env python3
"""
Verifier for joint_calibration_validation task.

Scoring (100 points):
  - Criterion 1 (20 pts): calibration_results.csv exists and was created after task start
  - Criterion 2 (25 pts): CSV has >= 10 configuration rows
  - Criterion 3 (25 pts): CSV has measured position columns AND error column,
                          with at least 8 configs having position error data;
                          joint configurations span >= 60 degrees in at least one joint
  - Criterion 4 (30 pts): calibration_report.json exists, is new, has required fields
                          (total_configs, flagged_count, max_error_mm, pass_rate_pct)
                          with total_configs >= 10

Pass threshold: 70
Anti-gaming: do-nothing score = 0
Empty CSV + JSON (filled): 20+30=50 pts if no rows → fails (50 < 70)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/joint_calibration_validation_result.json"


def verify_joint_calibration_validation(traj, env_info, task_info):
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
        feedback.append("Calibration CSV created after task start (+20)")
    elif result.get("csv_exists"):
        feedback.append("CSV exists but predates task start — stale file")
    else:
        feedback.append("calibration_results.csv not found")

    # Criterion 2: >= 10 rows (25 pts)
    row_count = int(result.get("csv_row_count", 0))
    if row_count >= 10:
        score += 25
        feedback.append(f"CSV has {row_count} configurations (>= 10 required) (+25)")
    elif row_count >= 5:
        score += 10
        feedback.append(f"CSV has {row_count} configurations (partial: 10/25)")
    else:
        feedback.append(f"CSV has {row_count} configurations (need >= 10)")

    # Criterion 3: Has position + error data, meaningful joint range (25 pts)
    analysis = result.get("csv_analysis", {})
    if isinstance(analysis, dict):
        has_positions = analysis.get("has_positions", False)
        has_errors = analysis.get("has_errors", False)
        joint_range = float(analysis.get("joint_range_deg", 0.0))
        configs_with_error = int(analysis.get("configs_with_error", 0))

        if has_positions and has_errors and configs_with_error >= 8 and joint_range >= 60:
            score += 25
            feedback.append(
                f"Calibration data complete: {configs_with_error} configs with error, "
                f"joint range={joint_range:.1f}° (+25)"
            )
        elif has_positions and has_errors and configs_with_error >= 4:
            score += 10
            feedback.append(
                f"Partial calibration data: {configs_with_error} configs, "
                f"joint range={joint_range:.1f}° (partial: 10/25)"
            )
        elif not has_positions:
            feedback.append("CSV lacks measured position columns (measured_x/y/z)")
        elif not has_errors:
            feedback.append("CSV lacks position_error_mm column")
        else:
            feedback.append(
                f"Insufficient calibration data: {configs_with_error} configs with error, "
                f"joint range={joint_range:.1f}°"
            )
    else:
        feedback.append("Could not parse calibration CSV")

    # Criterion 4: JSON report with required fields and total_configs >= 10 (30 pts)
    json_fields = result.get("json_fields", {})
    if isinstance(json_fields, dict):
        has_fields = json_fields.get("has_fields", False)
        total_configs = int(json_fields.get("total_configs", 0))
        flagged = int(json_fields.get("flagged_count", 0))
    else:
        has_fields = False
        total_configs = 0
        flagged = 0

    if (result.get("json_exists") and result.get("json_is_new")
            and has_fields and total_configs >= 10):
        score += 30
        feedback.append(
            f"Calibration report valid: {total_configs} configs, {flagged} flagged (+30)"
        )
    elif result.get("json_exists") and result.get("json_is_new") and has_fields:
        score += 15
        feedback.append(
            f"Report exists with fields but total_configs={total_configs} < 10 (partial: 15/30)"
        )
    elif result.get("json_exists") and result.get("json_is_new"):
        score += 5
        feedback.append("Report JSON exists but missing required fields (partial: 5/30)")
    else:
        feedback.append("calibration_report.json not found or not new")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }
