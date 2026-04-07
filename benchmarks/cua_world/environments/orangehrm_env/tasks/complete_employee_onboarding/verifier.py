#!/usr/bin/env python3
"""
Verifier for complete_employee_onboarding task.

Scoring (100 pts total, pass threshold 60):

Alex Chen (EMP021, Marketing Specialist):
  - Employee record exists:                20 pts
  - Assigned to Marketing department:      10 pts
  - Has at least 1 emergency contact:      10 pts
  - Annual Leave entitlement >= 15 days:   10 pts
  Subtotal Alex: 50 pts

Maria Santos (EMP022, Financial Analyst):
  - Employee record exists:                20 pts
  - Assigned to Finance department:        10 pts
  - Has at least 1 emergency contact:      10 pts
  - Annual Leave entitlement >= 15 days:   10 pts
  Subtotal Maria: 50 pts

Total: 100 pts. Pass threshold: 60 (need at least both employees created + some other steps).
"""

import json
import os
import tempfile


def verify_complete_employee_onboarding(traj, env_info, task_info):
    result_path = task_info.get("metadata", {}).get(
        "result_file", "/tmp/complete_employee_onboarding_result.json"
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
    # Alex Chen checks
    # -------------------------------------------------------
    alex_exists = data.get("alex_exists", False)
    if alex_exists is True or alex_exists == "true":
        score += 20
        feedback_parts.append("PASS Alex Chen employee record created (+20)")
    else:
        feedback_parts.append("FAIL Alex Chen employee record not found (+0)")

    alex_dept = (data.get("alex_dept") or "").strip()
    if "marketing" in alex_dept.lower():
        score += 10
        feedback_parts.append(f"PASS Alex Chen assigned to Marketing dept (found: '{alex_dept}') (+10)")
    else:
        feedback_parts.append(f"FAIL Alex Chen dept='{alex_dept}' — expected Marketing (+0)")

    alex_ec = int(data.get("alex_ec_count", 0) or 0)
    if alex_ec >= 1:
        score += 10
        feedback_parts.append(f"PASS Alex Chen has {alex_ec} emergency contact(s) (+10)")
    else:
        feedback_parts.append("FAIL Alex Chen has no emergency contacts (+0)")

    alex_al = float(data.get("alex_al_days", 0) or 0)
    if alex_al >= 15:
        score += 10
        feedback_parts.append(f"PASS Alex Chen Annual Leave = {alex_al} days (>= 15, +10)")
    elif alex_al > 0:
        score += 5
        feedback_parts.append(f"PARTIAL Alex Chen Annual Leave = {alex_al} days (some, < 15, +5)")
    else:
        feedback_parts.append("FAIL Alex Chen Annual Leave = 0 days (+0)")

    # -------------------------------------------------------
    # Maria Santos checks
    # -------------------------------------------------------
    maria_exists = data.get("maria_exists", False)
    if maria_exists is True or maria_exists == "true":
        score += 20
        feedback_parts.append("PASS Maria Santos employee record created (+20)")
    else:
        feedback_parts.append("FAIL Maria Santos employee record not found (+0)")

    maria_dept = (data.get("maria_dept") or "").strip()
    if "finance" in maria_dept.lower():
        score += 10
        feedback_parts.append(f"PASS Maria Santos assigned to Finance dept (found: '{maria_dept}') (+10)")
    else:
        feedback_parts.append(f"FAIL Maria Santos dept='{maria_dept}' — expected Finance (+0)")

    maria_ec = int(data.get("maria_ec_count", 0) or 0)
    if maria_ec >= 1:
        score += 10
        feedback_parts.append(f"PASS Maria Santos has {maria_ec} emergency contact(s) (+10)")
    else:
        feedback_parts.append("FAIL Maria Santos has no emergency contacts (+0)")

    maria_al = float(data.get("maria_al_days", 0) or 0)
    if maria_al >= 15:
        score += 10
        feedback_parts.append(f"PASS Maria Santos Annual Leave = {maria_al} days (>= 15, +10)")
    elif maria_al > 0:
        score += 5
        feedback_parts.append(f"PARTIAL Maria Santos Annual Leave = {maria_al} days (some, < 15, +5)")
    else:
        feedback_parts.append("FAIL Maria Santos Annual Leave = 0 days (+0)")

    score = min(score, 100)
    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
