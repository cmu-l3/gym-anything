#!/usr/bin/env python3
"""
Verifier for leave_policy_restructure task.

Scoring (100 pts total, pass threshold 60):
  - 'Compensatory Time Off' leave type created (active):      20 pts
  - EMP003 (David Nguyen) Annual Leave == 12 days:            12 pts
  - EMP010 (Amanda Davis) Annual Leave == 12 days:            12 pts
  - EMP017 (Brian Taylor) Annual Leave == 12 days:            12 pts
  - EMP003 Sick Leave >= 10 days this year:                   11 pts
  - EMP010 Sick Leave >= 10 days this year:                   11 pts
  - EMP017 Sick Leave >= 10 days this year:                   11 pts
  Subtotal above = 89; remaining 11 pts awarded if all 3 AL corrections done
  (bonus for perfect AL fix = 11 extra pts, making max 100)

  Simplified: total = 100 pts, pass = 60.
"""

import json
import os
import tempfile


def verify_leave_policy_restructure(traj, env_info, task_info):
    result_path = task_info.get("metadata", {}).get(
        "result_file", "/tmp/leave_policy_restructure_result.json"
    )

    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        env_info["copy_from_env"](result_path, local_tmp)
        with open(local_tmp, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read result file '{result_path}': {e}",
        }
    finally:
        if os.path.exists(local_tmp):
            os.remove(local_tmp)

    score = 0
    feedback_parts = []

    # -------------------------------------------------------
    # Criterion 1: 'Compensatory Time Off' leave type created (+20 pts)
    # -------------------------------------------------------
    comp_exists = data.get("comp_time_off_exists", False)
    if comp_exists is True or comp_exists == "true":
        score += 20
        feedback_parts.append("PASS 'Compensatory Time Off' leave type created (+20)")
    else:
        feedback_parts.append("FAIL 'Compensatory Time Off' leave type not found (+0)")

    # -------------------------------------------------------
    # Criterion 2-4: Annual Leave corrected to 12 days (+12 pts each)
    # -------------------------------------------------------
    al_correct_count = 0
    for emp_id, field in [("EMP003", "al_emp003_days"), ("EMP010", "al_emp010_days"), ("EMP017", "al_emp017_days")]:
        days = float(data.get(field, 0) or 0)
        # Accept exactly 12 (or within rounding tolerance of 12.0)
        if abs(days - 12.0) < 0.5:
            score += 12
            al_correct_count += 1
            feedback_parts.append(f"PASS {emp_id} Annual Leave = {days} days (correct, +12)")
        elif days < 30:
            # Partial: reduced from 30 but not exactly 12
            score += 5
            feedback_parts.append(f"PARTIAL {emp_id} Annual Leave = {days} days (reduced but not 12, +5)")
        else:
            feedback_parts.append(f"FAIL {emp_id} Annual Leave = {days} days (still 30, uncorrected, +0)")

    # Bonus if all 3 AL corrections done perfectly
    if al_correct_count == 3:
        score += 11
        feedback_parts.append("BONUS All 3 Annual Leave corrections perfect (+11)")

    # -------------------------------------------------------
    # Criterion 5-7: Sick Leave >= 10 days for each Finance employee (+11 pts each)
    # -------------------------------------------------------
    for emp_id, field in [("EMP003", "sl_emp003_days"), ("EMP010", "sl_emp010_days"), ("EMP017", "sl_emp017_days")]:
        days = float(data.get(field, 0) or 0)
        if days >= 10.0:
            score += 11
            feedback_parts.append(f"PASS {emp_id} Sick Leave = {days} days (>= 10, +11)")
        elif days > 0:
            score += 5
            feedback_parts.append(f"PARTIAL {emp_id} Sick Leave = {days} days (some added but < 10, +5)")
        else:
            feedback_parts.append(f"FAIL {emp_id} Sick Leave = {days} days (none added, +0)")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
