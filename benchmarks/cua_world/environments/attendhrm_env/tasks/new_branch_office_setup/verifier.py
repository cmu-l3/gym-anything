#!/usr/bin/env python3
"""
Verifier for new_branch_office_setup task (AttendHRM).

Stub verifier - VLM checklist evaluation is the primary verification method.
This provides basic programmatic scoring as a supplement.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_new_branch_office_setup(traj, env_info, task_info):
    """
    Verifies that the new Manchester branch office was fully set up.

    Checks 6 components across 5 HR modules:
      1. Branch creation (Employer module)
      2. Work shift creation (Roster module)
      3. Week-off pattern creation (Roster module)
      4. Leave policy with 3 entitlements (Leave module)
      5. Employee transfers to Manchester (Employee module)
      6. First-day attendance entries (Attendance module)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from VM
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        try:
            copy_from_env("C:\\temp\\new_branch_office_result.json", temp_file.name)
        except Exception:
            copy_from_env("/temp/new_branch_office_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to retrieve verification data: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve verification data from environment. {e}",
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Zero-work gate ---
    if not any([
        result.get("branch_found"),
        result.get("shift_found"),
        result.get("weekoff_found"),
        result.get("policy_found"),
        result.get("emp_108_transferred"),
        result.get("emp_120_transferred"),
        result.get("att_108_exists"),
        result.get("att_120_exists"),
    ]):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No changes detected. Agent did not complete any part of the task.",
        }

    # --- 1. Branch created (20 pts) ---
    if result.get("branch_found"):
        score += 15
        feedback.append("Branch 'Manchester' created.")
        if "MAN" in str(result.get("branch_code", "")).upper():
            score += 5
            feedback.append("Branch code MAN correct.")
    else:
        feedback.append("Branch 'Manchester' NOT found.")

    # --- 2. Work shift created (10 pts) ---
    if result.get("shift_found"):
        score += 10
        feedback.append("Work shift 'Manchester Standard' created.")
    else:
        feedback.append("Work shift NOT found.")

    # --- 3. Week-off pattern created (10 pts) ---
    if result.get("weekoff_found"):
        score += 10
        feedback.append("Week-off pattern 'Manchester Weekly' created.")
    else:
        feedback.append("Week-off pattern NOT found.")

    # --- 4. Leave policy created (20 pts) ---
    if result.get("policy_found"):
        score += 10
        feedback.append("Leave policy 'Manchester Staff Leave 2025' created.")
        entitlements = result.get("policy_entitlements", 0)
        if isinstance(entitlements, int) and entitlements >= 3:
            score += 10
            feedback.append(f"Policy has {entitlements} entitlements (expected 3).")
        elif isinstance(entitlements, int) and entitlements > 0:
            score += 5
            feedback.append(f"Policy has {entitlements} entitlements (expected 3, partial).")
    else:
        feedback.append("Leave policy NOT found.")

    # --- 5. Employee transfers (20 pts) ---
    if result.get("emp_108_at_manchester"):
        score += 10
        feedback.append("Reid Ryan transferred to Manchester.")
    elif result.get("emp_108_transferred"):
        score += 5
        feedback.append("Reid Ryan moved from London (not confirmed at Manchester).")
    else:
        feedback.append("Reid Ryan NOT transferred.")

    if result.get("emp_120_at_manchester"):
        score += 10
        feedback.append("Jessica Owens transferred to Manchester.")
    elif result.get("emp_120_transferred"):
        score += 5
        feedback.append("Jessica Owens moved from London (not confirmed at Manchester).")
    else:
        feedback.append("Jessica Owens NOT transferred.")

    # --- 6. Attendance entries (20 pts) ---
    if result.get("att_108_exists"):
        score += 10
        feedback.append("Reid Ryan attendance Mar 3 recorded.")
    else:
        feedback.append("Reid Ryan attendance NOT found.")

    if result.get("att_120_exists"):
        score += 10
        feedback.append("Jessica Owens attendance Mar 3 recorded.")
    else:
        feedback.append("Jessica Owens attendance NOT found.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
